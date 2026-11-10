"""Leitura dos registros da pessoa para o motor de análise (o módulo só lê).

Toda consulta filtra pelo dono vindo do token; atividades excluídas e treinos não
concluídos ficam de fora. Os dias são os do fuso do perfil: uma corrida às 23h de
domingo conta no domingo, mesmo já sendo segunda em UTC.
"""

import zoneinfo
from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.errors import FieldValidationError
from app.modules.activities.models import Activity
from app.modules.analytics.metrics import STRENGTH, Entry
from app.modules.sessions.models import SessionExercise, WorkoutSession
from app.modules.users.models import User

ENDURANCE = ("run", "walk", "cycle", "swim")
MAX_DAYS = 366
DEFAULT_DAYS = 30


def tz(user: User) -> zoneinfo.ZoneInfo:
    return zoneinfo.ZoneInfo(user.profile.timezone if user.profile else "America/Sao_Paulo")


def today(user: User) -> date:
    return datetime.now(tz(user)).date()


def period(
    user: User,
    start: date | None,
    end: date | None,
    *,
    start_field: str = "from",
    end_field: str = "to",
) -> tuple[date, date]:
    """Padrão: os últimos 30 dias, até hoje. No máximo 366 dias."""
    end = end or today(user)
    start = start or end - timedelta(days=DEFAULT_DAYS - 1)
    if start > end:
        raise FieldValidationError(start_field, "O início não pode ser depois do fim.")
    if (end - start).days + 1 > MAX_DAYS:
        raise FieldValidationError(end_field, f"Escolha um período de até {MAX_DAYS} dias.")
    return start, end


def weekly_target(user: User) -> int | None:
    availability = user.profile.weekly_availability if user.profile else None
    return (availability or {}).get("days_per_week")


class AnalyticsService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def entries(
        self, user: User, start: date, end: date, modalities: tuple[str, ...] | None = None
    ) -> list[Entry]:
        zone = tz(user)
        lower = datetime.combine(start, time.min, zone).astimezone(UTC)
        upper = datetime.combine(end + timedelta(days=1), time.min, zone).astimezone(UTC)
        wanted = modalities or (STRENGTH, *ENDURANCE)
        result: list[Entry] = []

        endurance = [m for m in wanted if m in ENDURANCE]
        if endurance:
            activities = self.db.scalars(
                select(Activity)
                .where(
                    Activity.user_id == user.id,
                    Activity.modality.in_(endurance),
                    Activity.deleted_at.is_(None),
                    Activity.started_at >= lower,
                    Activity.started_at < upper,
                )
                .options(selectinload(Activity.endurance))
            )
            for activity in activities:
                result.append(
                    Entry(
                        day=activity.started_at.astimezone(zone).date(),
                        modality=activity.modality,
                        duration_s=activity.duration_s or 0,
                        distance_m=activity.endurance.distance_m if activity.endurance else None,
                    )
                )

        if STRENGTH in wanted:
            sessions = self.db.scalars(
                select(WorkoutSession)
                .join(Activity, Activity.id == WorkoutSession.activity_id)
                .where(
                    WorkoutSession.user_id == user.id,
                    WorkoutSession.status == "completed",
                    Activity.deleted_at.is_(None),
                    Activity.started_at >= lower,
                    Activity.started_at < upper,
                )
                .options(
                    selectinload(WorkoutSession.exercises).selectinload(SessionExercise.sets),
                    selectinload(WorkoutSession.exercises).selectinload(SessionExercise.exercise),
                )
            )
            for session in sessions:
                sets, volume = 0, 0.0
                # Mesmas regras do histórico (2.8): aquecimento não conta; segmentos
                # (drop, rest-pause) não são séries novas, mas entram no volume.
                for entry in session.exercises:
                    for s in entry.sets:
                        if s.kind == "warmup":
                            continue
                        if s.parent_set_id is None:
                            sets += 1
                        if entry.exercise.load_type == "external" and s.load_kg and s.reps:
                            volume += s.load_kg * s.reps
                result.append(
                    Entry(
                        day=session.activity.started_at.astimezone(zone).date(),
                        modality=STRENGTH,
                        duration_s=session.activity.duration_s or 0,
                        sets=sets,
                        volume_kg=volume,
                    )
                )
        return sorted(result, key=lambda e: e.day)
