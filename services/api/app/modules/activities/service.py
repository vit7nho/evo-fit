"""Atividades de resistência do usuário autenticado (corrida, caminhada, ciclismo, natação).

Toda consulta filtra pelo dono vindo do token e ignora as excluídas: a atividade de outra
pessoa (ou um treino de musculação, que tem rota própria) responde 404, igual a uma que
não existe. Excluir é lógico (`deleted_at`), para os indicadores recalcularem o histórico.
"""

import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.errors import FieldValidationError, NotFoundError
from app.modules.activities.models import Activity, CyclingDetails, EnduranceDetails, SwimDetails
from app.modules.activities.schemas import ActivityCreate, ActivityUpdate
from app.modules.users.models import User

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ModalitySpec:
    code: str
    label: str
    max_distance_m: int


MODALITIES = {
    m.code: m
    for m in (
        ModalitySpec("run", "Corrida", 300_000),
        ModalitySpec("walk", "Caminhada", 150_000),
        ModalitySpec("cycle", "Ciclismo", 1_000_000),
        ModalitySpec("swim", "Natação", 30_000),
    )
}
STROKES = {
    "freestyle": "Crawl",
    "breaststroke": "Peito",
    "backstroke": "Costas",
    "butterfly": "Borboleta",
    "mixed": "Variado",
}
POOL_LENGTHS_M = [25, 50]

# Datas aceitas: até 5 anos atrás; no futuro, só a folga do relógio do aparelho.
_PAST = timedelta(days=5 * 365)
_CLOCK_SKEW = timedelta(minutes=5)
_CYCLING_FIELDS = {"indoor"}
_SWIM_FIELDS = {"pool_length_m", "laps", "stroke"}
PAGE_SIZE = 20


def _now() -> datetime:
    return datetime.now(UTC)


class ActivityService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def _query(self, user: User):
        return (
            select(Activity)
            .where(
                Activity.user_id == user.id,
                Activity.modality.in_(MODALITIES),
                Activity.deleted_at.is_(None),
            )
            .options(
                selectinload(Activity.endurance),
                selectinload(Activity.cycling),
                selectinload(Activity.swim),
            )
        )

    def list(
        self,
        user: User,
        modality: str | None = None,
        before: datetime | None = None,
        limit: int = PAGE_SIZE,
    ) -> list[Activity]:
        query = self._query(user)
        if modality is not None:
            query = query.where(Activity.modality == modality)
        if before is not None:
            query = query.where(Activity.started_at < before)
        query = query.order_by(Activity.started_at.desc(), Activity.id.desc()).limit(limit)
        return list(self.db.scalars(query))

    def get(self, user: User, activity_id: uuid.UUID) -> Activity:
        activity = self.db.scalar(self._query(user).where(Activity.id == activity_id))
        if activity is None:
            raise NotFoundError("Atividade não encontrada.")
        return activity

    def create(self, user: User, data: ActivityCreate) -> Activity:
        values = data.model_dump()
        _check_fields(data.modality, data.model_fields_set)
        _check_started_at(data.started_at)
        values["distance_m"] = _distance(data.modality, values)
        values["notes"] = data.notes or None

        activity = Activity(
            user_id=user.id,
            modality=data.modality,
            source="manual",
            started_at=data.started_at,
        )
        _apply(activity, values)
        self.db.add(activity)
        self.db.commit()
        self.db.refresh(activity)
        logger.info(
            "activity_created",
            extra={
                "user_id": str(user.id),
                "activity_id": str(activity.id),
                "modality": activity.modality,
            },
        )
        return self.get(user, activity.id)

    def update(self, user: User, activity_id: uuid.UUID, data: ActivityUpdate) -> Activity:
        activity = self.get(user, activity_id)
        changes = data.model_fields_set
        _check_fields(activity.modality, changes)
        for name in {"started_at", "duration_s"} & changes:
            if getattr(data, name) is None:
                raise FieldValidationError(name, "Campo obrigatório.")
        if "started_at" in changes:
            _check_started_at(data.started_at)  # type: ignore[arg-type]

        values = _current(activity) | {name: getattr(data, name) for name in changes}
        if "notes" in changes:
            values["notes"] = data.notes or None
        if changes & ({"distance_m"} | _SWIM_FIELDS):
            values["distance_m"] = _distance(activity.modality, values, changed=changes)
        _apply(activity, values)
        self.db.commit()
        logger.info(
            "activity_updated", extra={"user_id": str(user.id), "activity_id": str(activity.id)}
        )
        return self.get(user, activity.id)

    def delete(self, user: User, activity_id: uuid.UUID) -> None:
        activity = self.get(user, activity_id)
        activity.deleted_at = _now()
        self.db.commit()
        logger.info(
            "activity_deleted", extra={"user_id": str(user.id), "activity_id": str(activity_id)}
        )


def _check_fields(modality: str, fields: set[str]) -> None:
    """Campo de outra modalidade é recusado, para não ser guardado e ignorado em silêncio."""
    allowed = {"cycle": _CYCLING_FIELDS, "swim": _SWIM_FIELDS}.get(modality, set())
    for name in sorted((_CYCLING_FIELDS | _SWIM_FIELDS) - allowed):
        if name in fields:
            label = MODALITIES[modality].label.lower()
            raise FieldValidationError(name, f"Não se aplica a {label}.")


def _check_started_at(started_at: datetime) -> None:
    now = _now()
    if started_at > now + _CLOCK_SKEW:
        raise FieldValidationError("started_at", "A data não pode estar no futuro.")
    if started_at < now - _PAST:
        raise FieldValidationError("started_at", "A data é antiga demais (mais de 5 anos).")


def _distance(modality: str, values: dict, changed: set[str] | None = None) -> int | None:
    """Distância final. Na piscina, voltas vezes o tamanho: preenche a distância que faltar,
    acompanha voltas ou piscina corrigidas e recusa uma distância informada que não bata."""
    distance = values.get("distance_m")
    pool, laps = values.get("pool_length_m"), values.get("laps")
    if modality == "swim" and pool is not None and laps is not None:
        from_laps = pool * laps
        if distance is None or (changed is not None and "distance_m" not in changed):
            distance = from_laps
        elif distance != from_laps:
            raise FieldValidationError(
                "distance_m",
                f"Não bate com as voltas: {laps} × {pool} m = {from_laps} m.",  # noqa: RUF001
            )
    limit = MODALITIES[modality].max_distance_m
    if distance is not None and distance > limit:
        raise FieldValidationError("distance_m", f"Distância acima do limite ({limit // 1000} km).")
    return distance


def _current(activity: Activity) -> dict:
    swim = activity.swim
    return {
        "started_at": activity.started_at,
        "duration_s": activity.duration_s,
        "distance_m": activity.endurance.distance_m if activity.endurance else None,
        "perceived_effort": activity.perceived_effort,
        "notes": activity.notes,
        "indoor": activity.cycling.indoor if activity.cycling else None,
        "pool_length_m": swim.pool_length_m if swim else None,
        "laps": swim.laps if swim else None,
        "stroke": swim.stroke if swim else None,
    }


def _apply(activity: Activity, values: dict) -> None:
    activity.started_at = values["started_at"]
    activity.duration_s = values["duration_s"]
    activity.ended_at = values["started_at"] + timedelta(seconds=values["duration_s"])
    activity.perceived_effort = values["perceived_effort"]
    activity.notes = values["notes"]
    if activity.endurance is None:
        activity.endurance = EnduranceDetails()
    activity.endurance.distance_m = values["distance_m"]
    if activity.modality == "cycle":
        if activity.cycling is None:
            activity.cycling = CyclingDetails()
        activity.cycling.indoor = bool(values["indoor"])
    if activity.modality == "swim":
        if activity.swim is None:
            activity.swim = SwimDetails()
        activity.swim.pool_length_m = values["pool_length_m"]
        activity.swim.laps = values["laps"]
        activity.swim.stroke = values["stroke"]
