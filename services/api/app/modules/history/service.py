"""Histórico de treinos e recordes pessoais (DATA_MODEL §3, ADR-035).

Os recordes são calculados sob demanda a partir das séries salvas, numa passada em
ordem cronológica pelos treinos concluídos do usuário: o melhor de cada tipo até ali,
e os treinos em que ele foi superado. Só contam treinos concluídos, de atividades não
excluídas, do próprio usuário.
"""

import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.activities.models import Activity
from app.modules.exercises.models import Exercise
from app.modules.sessions.models import SessionExercise, SetEntry, WorkoutSession
from app.modules.users.models import User

# Epley perde precisão com muitas repetições: acima disso, sem estimativa.
E1RM_MAX_REPS = 12
REP_RECORD_MAX = 20

# Tipos de recorde por forma de medir o exercício.
RECORD_KINDS = {
    "external": ("max_load", "best_e1rm", "max_volume"),
    "bodyweight": ("max_reps",),
    "assisted": ("max_reps",),
    "time": ("max_duration",),
}


def e1rm(load_kg: float | None, reps: int | None) -> float | None:
    """1RM estimado (Epley). É uma estimativa; vale só de 1 a 12 repetições."""
    if not load_kg or not reps or reps < 1 or reps > E1RM_MAX_REPS:
        return None
    return round(load_kg if reps == 1 else load_kg * (1 + reps / 30), 1)


@dataclass
class Mark:
    """Um valor de recorde e onde ele aconteceu."""

    value: float
    reps: int | None
    load_kg: float | None
    session_id: uuid.UUID
    achieved_at: datetime


@dataclass
class Event:
    exercise_id: uuid.UUID
    kind: str
    mark: Mark
    previous: float


@dataclass
class Timeline:
    """Resultado da passada: o melhor de cada tipo e os recordes batidos por treino."""

    best: dict[uuid.UUID, dict[str, Mark]] = field(default_factory=lambda: defaultdict(dict))
    rep_best: dict[uuid.UUID, dict[int, Mark]] = field(default_factory=lambda: defaultdict(dict))
    events: dict[uuid.UUID, list[Event]] = field(default_factory=lambda: defaultdict(list))
    last_done: dict[uuid.UUID, datetime] = field(default_factory=dict)
    load_types: dict[uuid.UUID, str] = field(default_factory=dict)


def session_marks(
    sets: list[SetEntry], load_type: str, session_id: uuid.UUID, at: datetime
) -> dict[str, Mark]:
    """Os valores de um exercício num treino. Séries principais válidas contam para
    carga, 1RM, repetições e duração; o volume soma também os segmentos (drop,
    rest-pause), como no resumo do treino."""
    mains = [s for s in sets if s.parent_set_id is None and s.kind == "working"]
    marks: dict[str, Mark] = {}

    def keep(kind: str, value: float | None, s: SetEntry | None = None) -> None:
        if value is None or value <= 0:
            return
        if kind not in marks or value > marks[kind].value:
            marks[kind] = Mark(
                value=value,
                reps=s.reps if s else None,
                load_kg=s.load_kg if s else None,
                session_id=session_id,
                achieved_at=at,
            )

    if load_type == "external":
        for s in mains:
            if s.reps:
                keep("max_load", s.load_kg, s)
                keep("best_e1rm", e1rm(s.load_kg, s.reps), s)
        volume = sum(
            s.load_kg * s.reps for s in sets if s.kind != "warmup" and s.load_kg and s.reps
        )
        keep("max_volume", round(volume, 2))
    elif load_type == "time":
        for s in mains:
            keep("max_duration", float(s.duration_s) if s.duration_s else None, s)
    else:
        for s in mains:
            keep("max_reps", float(s.reps) if s.reps else None, s)
    return marks


class HistoryService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def _completed(self, user: User):
        return (
            select(WorkoutSession)
            .join(Activity, Activity.id == WorkoutSession.activity_id)
            .where(
                WorkoutSession.user_id == user.id,
                WorkoutSession.status == "completed",
                Activity.deleted_at.is_(None),
            )
        )

    def timeline(
        self,
        user: User,
        exercise_ids: set[uuid.UUID] | None = None,
        until: datetime | None = None,
    ) -> Timeline:
        """Passada cronológica pelos treinos concluídos (até `until`, inclusive)."""
        query = (
            select(SetEntry, SessionExercise.exercise_id, WorkoutSession.id, Activity.started_at)
            .join(SessionExercise, SessionExercise.id == SetEntry.session_exercise_id)
            .join(WorkoutSession, WorkoutSession.id == SessionExercise.session_id)
            .join(Activity, Activity.id == WorkoutSession.activity_id)
            .where(
                WorkoutSession.user_id == user.id,
                WorkoutSession.status == "completed",
                Activity.deleted_at.is_(None),
            )
            .order_by(Activity.started_at, WorkoutSession.id, SetEntry.position)
        )
        if exercise_ids is not None:
            query = query.where(SessionExercise.exercise_id.in_(exercise_ids))
        if until is not None:
            query = query.where(Activity.started_at <= until)

        # Agrupa por treino (na ordem) e exercício.
        grouped: dict[tuple[uuid.UUID, datetime], dict[uuid.UUID, list[SetEntry]]] = {}
        for entry_set, exercise_id, session_id, started_at in self.db.execute(query):
            grouped.setdefault((session_id, started_at), defaultdict(list))[exercise_id].append(
                entry_set
            )
        all_ids = {e for per in grouped.values() for e in per}
        load_types = dict(
            self.db.execute(
                select(Exercise.id, Exercise.load_type).where(Exercise.id.in_(all_ids))
            ).all()
        )

        result = Timeline(load_types=load_types)
        for (session_id, started_at), per_exercise in grouped.items():
            for exercise_id, sets in per_exercise.items():
                load_type = load_types[exercise_id]
                result.last_done[exercise_id] = started_at
                best = result.best[exercise_id]
                for kind, mark in session_marks(sets, load_type, session_id, started_at).items():
                    current = best.get(kind)
                    # Primeira vez não é recorde batido: não havia com o que comparar.
                    if current is not None and mark.value > current.value:
                        result.events[session_id].append(
                            Event(exercise_id, kind, mark, current.value)
                        )
                    if current is None or mark.value > current.value:
                        best[kind] = mark
                if load_type == "external":
                    reps_best = result.rep_best[exercise_id]
                    for s in sets:
                        if (
                            s.parent_set_id is None
                            and s.kind == "working"
                            and s.reps
                            and s.reps <= REP_RECORD_MAX
                            and s.load_kg
                        ):
                            current = reps_best.get(s.reps)
                            if current is None or s.load_kg > current.value:
                                reps_best[s.reps] = Mark(
                                    s.load_kg, s.reps, s.load_kg, session_id, started_at
                                )
        return result

    def sessions(
        self, user: User, limit: int, before: datetime | None
    ) -> tuple[list[WorkoutSession], datetime | None]:
        """Treinos concluídos, do mais recente; `before` pagina pelo início do treino."""
        query = self._completed(user).order_by(Activity.started_at.desc(), WorkoutSession.id.desc())
        if before is not None:
            query = query.where(Activity.started_at < before)
        rows = list(self.db.scalars(query.limit(limit + 1)))
        page = rows[:limit]
        more = len(rows) > limit
        return page, page[-1].activity.started_at if more and page else None

    def exercise_sessions(
        self, user: User, exercise_id: uuid.UUID, limit: int, before: datetime | None
    ) -> tuple[list[tuple[WorkoutSession, SessionExercise]], datetime | None]:
        """As vezes em que o exercício foi feito (um item por treino), do mais recente."""
        query = (
            select(WorkoutSession, SessionExercise)
            .join(Activity, Activity.id == WorkoutSession.activity_id)
            .join(SessionExercise, SessionExercise.session_id == WorkoutSession.id)
            .where(
                WorkoutSession.user_id == user.id,
                WorkoutSession.status == "completed",
                Activity.deleted_at.is_(None),
                SessionExercise.exercise_id == exercise_id,
            )
            .order_by(Activity.started_at.desc(), SessionExercise.position)
        )
        if before is not None:
            query = query.where(Activity.started_at < before)
        rows: list[tuple[WorkoutSession, SessionExercise]] = []
        seen: set[uuid.UUID] = set()
        # O mesmo exercício duas vezes no treino: a primeira entrada com séries.
        for session, entry in self.db.execute(query):
            if session.id in seen or not entry.sets:
                continue
            seen.add(session.id)
            rows.append((session, entry))
            if len(rows) > limit:
                break
        page = rows[:limit]
        more = len(rows) > limit
        return page, page[-1][0].activity.started_at if more and page else None
