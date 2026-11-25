"""Peso e medidas (5.3, ADR-060).

- Dado de saúde (SECURITY_PRIVACY §1): registrar ou alterar exige `health_data`, e
  revogá-lo apaga as medidas. Os logs levam só os ids.
- O horário sem fuso vale no fuso do perfil, como nas refeições; medida no futuro é
  recusada.
- A tendência usa um ponto por dia (o último registro do dia), a média dos 7 dias
  e o ritmo por semana pela reta que melhor passa pelos pontos.
"""

import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import FieldValidationError, NotFoundError
from app.modules.analytics.service import today, tz
from app.modules.body.models import METRICS, BodyMeasurement
from app.modules.body.schemas import (
    CM_RANGE,
    FAT_RANGE,
    WEIGHT_RANGE,
    MeasurementIn,
    MeasurementUpdate,
    MetricInfo,
    TrendOut,
    TrendPoint,
)
from app.modules.users.models import ConsentKind, User
from app.modules.users.service import ConsentRequiredError, active_consent

logger = logging.getLogger(__name__)

DEFAULT_DAYS = 90
MAX_DAYS = 730
# Tolerância do relógio do aparelho para "agora".
FUTURE_SLACK = timedelta(minutes=10)


@dataclass(frozen=True)
class _Info:
    label: str
    unit: str
    range: tuple[float, float] = CM_RANGE
    estimate: bool = False


INFO = {
    "weight_kg": _Info("Peso", "kg", WEIGHT_RANGE),
    "body_fat_pct": _Info("Gordura corporal", "%", FAT_RANGE, estimate=True),
    "waist_cm": _Info("Cintura", "cm"),
    "hip_cm": _Info("Quadril", "cm"),
    "chest_cm": _Info("Peito", "cm"),
    "arm_cm": _Info("Braço", "cm"),
    "thigh_cm": _Info("Coxa", "cm"),
    "calf_cm": _Info("Panturrilha", "cm"),
}


def metric_infos() -> list[MetricInfo]:
    return [
        MetricInfo(
            metric=metric,  # type: ignore[arg-type]
            label=INFO[metric].label,
            unit=INFO[metric].unit,  # type: ignore[arg-type]
            min=INFO[metric].range[0],
            max=INFO[metric].range[1],
            estimate=INFO[metric].estimate,
        )
        for metric in METRICS
    ]


def period(user: User, start: date | None, end: date | None) -> tuple[date, date]:
    """Padrão: os últimos 90 dias até hoje; no máximo 730 dias."""
    end = end or today(user)
    start = start or end - timedelta(days=DEFAULT_DAYS - 1)
    if start > end:
        raise FieldValidationError("from", "O início não pode ser depois do fim.")
    if (end - start).days + 1 > MAX_DAYS:
        raise FieldValidationError("to", f"Escolha um período de até {MAX_DAYS} dias.")
    return start, end


def weekly_rate(points: list[tuple[int, float]]) -> float | None:
    """Inclinação da reta de mínimos quadrados (por dia) vezes 7."""
    if len(points) < 3 or points[-1][0] - points[0][0] < 14:
        return None
    n = len(points)
    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n
    spread = sum((x - mean_x) ** 2 for x, _ in points)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in points) / spread
    return round(slope * 7, 2)


def trend_points(daily: list[tuple[date, float]]) -> list[TrendPoint]:
    """[daily] em ordem de data, um valor por dia."""
    points = []
    for index, (day, value) in enumerate(daily):
        window = [v for d, v in daily[: index + 1] if (day - d).days < 7]
        points.append(
            TrendPoint(date=day, value=value, average_7d=round(sum(window) / len(window), 2))
        )
    return points


class MeasurementService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def _require_consent(self, user: User) -> None:
        if active_consent(self.db, user.id, ConsentKind.HEALTH_DATA) is None:
            raise ConsentRequiredError(ConsentKind.HEALTH_DATA)

    @staticmethod
    def _at(user: User, moment: datetime) -> datetime:
        at = moment.replace(tzinfo=tz(user)) if moment.tzinfo is None else moment
        if at > datetime.now(UTC) + FUTURE_SLACK:
            raise FieldValidationError("measured_at", "A medida não pode ser no futuro.")
        return at

    def _bounds(self, user: User, start: date, end: date) -> tuple[datetime, datetime]:
        zone = tz(user)
        lower = datetime.combine(start, time.min, zone).astimezone(UTC)
        upper = datetime.combine(end + timedelta(days=1), time.min, zone).astimezone(UTC)
        return lower, upper

    def list(self, user: User, start: date, end: date) -> list[BodyMeasurement]:
        lower, upper = self._bounds(user, start, end)
        return list(
            self.db.scalars(
                select(BodyMeasurement)
                .where(
                    BodyMeasurement.user_id == user.id,
                    BodyMeasurement.measured_at >= lower,
                    BodyMeasurement.measured_at < upper,
                )
                .order_by(BodyMeasurement.measured_at.desc(), BodyMeasurement.id.desc())
                .limit(500)
            )
        )

    def get(self, user: User, measurement_id: uuid.UUID) -> BodyMeasurement:
        found = self.db.scalar(
            select(BodyMeasurement).where(
                BodyMeasurement.id == measurement_id, BodyMeasurement.user_id == user.id
            )
        )
        if found is None:
            raise NotFoundError("Medida não encontrada.")
        return found

    def create(self, user: User, data: MeasurementIn) -> BodyMeasurement:
        self._require_consent(user)
        values = data.model_dump(exclude={"measured_at", "notes"})
        found = BodyMeasurement(
            user_id=user.id,
            measured_at=self._at(user, data.measured_at),
            notes=data.notes or None,
            **values,
        )
        self.db.add(found)
        self.db.commit()
        self.db.refresh(found)
        # Sem os valores no log: são dados de saúde.
        logger.info(
            "body_measurement_created",
            extra={"user_id": str(user.id), "measurement_id": str(found.id)},
        )
        return found

    def update(
        self, user: User, measurement_id: uuid.UUID, data: MeasurementUpdate
    ) -> BodyMeasurement:
        found = self.get(user, measurement_id)  # de outra pessoa: 404
        self._require_consent(user)
        changes = data.model_dump(exclude_unset=True)
        if "measured_at" in changes and changes["measured_at"] is None:
            raise FieldValidationError("measured_at", "Campo obrigatório.")
        current = {n: getattr(found, n) for n in (*METRICS, "notes")}
        current["measured_at"] = found.measured_at
        try:
            merged = MeasurementIn.model_validate({**current, **changes})
        except ValidationError as error:
            first = error.errors()[0]
            field = ".".join(str(p) for p in first["loc"]) or "__root__"
            raise FieldValidationError(
                field, str(first["msg"]).removeprefix("Value error, ")
            ) from None
        if "measured_at" in changes:
            found.measured_at = self._at(user, merged.measured_at)
        for name in METRICS:
            setattr(found, name, getattr(merged, name))
        found.notes = merged.notes or None
        self.db.commit()
        self.db.refresh(found)
        return found

    def delete(self, user: User, measurement_id: uuid.UUID) -> None:
        self.db.delete(self.get(user, measurement_id))
        self.db.commit()

    def trend(self, user: User, metric: str, start: date, end: date) -> TrendOut:
        zone = tz(user)
        by_day: dict[date, float] = {}
        # Do mais antigo ao mais novo: o último do dia fica.
        for row in reversed(self.list(user, start, end)):
            value = getattr(row, metric)
            if value is not None:
                by_day[row.measured_at.astimezone(zone).date()] = value
        daily = sorted(by_day.items())
        points = trend_points(daily)
        values = [v for _, v in daily]
        info = INFO[metric]
        return TrendOut(
            metric=metric,  # type: ignore[arg-type]
            label=info.label,
            unit=info.unit,
            from_date=start,
            to_date=end,
            points=points,
            first=points[0] if points else None,
            last=points[-1] if points else None,
            change=round(values[-1] - values[0], 2) if values else None,
            min=min(values) if values else None,
            max=max(values) if values else None,
            weekly_rate=weekly_rate([((d - start).days, v) for d, v in daily]),
        )

    # --- para as metas de peso ---

    def weight_near(self, user: User, moment: datetime) -> float | None:
        """O peso de quando a meta começou: o último até [moment]; sem ele, o primeiro
        depois."""
        before = self.db.scalar(
            select(BodyMeasurement.weight_kg)
            .where(
                BodyMeasurement.user_id == user.id,
                BodyMeasurement.weight_kg.is_not(None),
                BodyMeasurement.measured_at <= moment,
            )
            .order_by(BodyMeasurement.measured_at.desc())
            .limit(1)
        )
        if before is not None:
            return before
        return self.db.scalar(
            select(BodyMeasurement.weight_kg)
            .where(
                BodyMeasurement.user_id == user.id,
                BodyMeasurement.weight_kg.is_not(None),
                BodyMeasurement.measured_at > moment,
            )
            .order_by(BodyMeasurement.measured_at)
            .limit(1)
        )

    def latest_weight(self, user: User) -> tuple[float, datetime] | None:
        row = self.db.execute(
            select(BodyMeasurement.weight_kg, BodyMeasurement.measured_at)
            .where(BodyMeasurement.user_id == user.id, BodyMeasurement.weight_kg.is_not(None))
            .order_by(BodyMeasurement.measured_at.desc())
            .limit(1)
        ).first()
        return None if row is None else (row[0], row[1])
