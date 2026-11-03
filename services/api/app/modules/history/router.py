import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser
from app.modules.exercises.models import Exercise
from app.modules.exercises.service import ExerciseService
from app.modules.history.schemas import (
    ExerciseHistory,
    ExerciseRecords,
    ExerciseSession,
    HistorySet,
    RecordEvent,
    RecordOut,
    SessionPage,
    SessionSummary,
)
from app.modules.history.service import RECORD_KINDS, Event, HistoryService, Mark, e1rm
from app.modules.sessions.models import SetEntry, WorkoutSession
from app.modules.training.schemas import ExerciseRef
from app.modules.users.models import User

router = APIRouter(tags=["histórico e recordes"])

DbSession = Annotated[Session, Depends(get_db)]
Limit = Annotated[int, Query(ge=1, le=50)]


def record_out(kind: str, mark: Mark) -> RecordOut:
    return RecordOut(
        kind=kind,
        value=mark.value,
        reps=mark.reps,
        load_kg=mark.load_kg,
        session_id=mark.session_id,
        achieved_at=mark.achieved_at,
    )


def event_out(event: Event) -> RecordEvent:
    return RecordEvent(
        exercise_id=event.exercise_id,
        kind=event.kind,
        value=event.mark.value,
        reps=event.mark.reps,
        load_kg=event.mark.load_kg,
        previous=event.previous,
    )


def session_events(db: Session, user: User, session: WorkoutSession) -> list[RecordEvent]:
    """Recordes batidos num treino concluído (comparando só com os treinos anteriores)."""
    if session.status != "completed":
        return []
    timeline = HistoryService(db).timeline(
        user,
        exercise_ids={e.exercise_id for e in session.exercises},
        until=session.activity.started_at,
    )
    return [event_out(e) for e in timeline.events.get(session.id, [])]


def _ordered_sets(sets: list[SetEntry]) -> list[HistorySet]:
    """Cada série principal seguida dos próprios segmentos."""
    out = []
    for main in (s for s in sets if s.parent_set_id is None):
        for s in [main, *(g for g in sets if g.parent_set_id == main.id)]:
            out.append(
                HistorySet(
                    kind=s.kind,
                    reps=s.reps,
                    load_kg=s.load_kg,
                    duration_s=s.duration_s,
                    to_failure=s.to_failure,
                    is_segment=s.parent_set_id is not None,
                )
            )
    return out


@router.get(
    "/workout-sessions",
    response_model=SessionPage,
    summary="Histórico: treinos concluídos, do mais recente (paginado por `before`)",
)
def list_sessions(
    user: CurrentUser,
    db: DbSession,
    limit: Limit = 20,
    before: datetime | None = None,
) -> SessionPage:
    service = HistoryService(db)
    sessions, next_before = service.sessions(user, limit, before)
    events = service.timeline(user).events if sessions else {}
    items = []
    for session in sessions:
        set_count, volume = 0, 0.0
        for entry in session.exercises:
            for s in entry.sets:
                if s.kind == "warmup":
                    continue
                if s.parent_set_id is None:
                    set_count += 1
                if entry.exercise.load_type == "external" and s.load_kg and s.reps:
                    volume += s.load_kg * s.reps
        items.append(
            SessionSummary(
                id=session.id,
                name=session.name,
                started_at=session.activity.started_at,
                duration_s=session.activity.duration_s,
                set_count=set_count,
                volume_kg=round(volume, 2),
                exercise_count=len(session.exercises),
                exercise_names=[e.exercise.name for e in session.exercises[:4]],
                record_count=len(events.get(session.id, [])),
            )
        )
    return SessionPage(items=items, next_before=next_before)


@router.get(
    "/exercises/{exercise_id}/history",
    response_model=ExerciseHistory,
    summary="Séries do usuário nesse exercício, treino a treino, e os recordes",
)
def exercise_history(
    exercise_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    limit: Limit = 10,
    before: datetime | None = None,
) -> ExerciseHistory:
    exercise = ExerciseService(db).get(user, exercise_id)
    service = HistoryService(db)
    timeline = service.timeline(user, exercise_ids={exercise.id})
    best = timeline.best.get(exercise.id, {})
    rows, next_before = service.exercise_sessions(user, exercise.id, limit, before)
    sessions = []
    for session, entry in rows:
        external = exercise.load_type == "external"
        volume = sum(
            s.load_kg * s.reps
            for s in entry.sets
            if external and s.kind != "warmup" and s.load_kg and s.reps
        )
        estimates = [
            e1rm(s.load_kg, s.reps)
            for s in entry.sets
            if external and s.parent_set_id is None and s.kind == "working"
        ]
        sessions.append(
            ExerciseSession(
                session_id=session.id,
                session_name=session.name,
                started_at=session.activity.started_at,
                sets=_ordered_sets(entry.sets),
                volume_kg=round(volume, 2),
                best_e1rm=max((e for e in estimates if e), default=None),
                records=[
                    e.kind
                    for e in timeline.events.get(session.id, [])
                    if e.exercise_id == exercise.id
                ],
            )
        )
    return ExerciseHistory(
        exercise=ExerciseRef.of(exercise),
        records=[
            record_out(kind, best[kind])
            for kind in RECORD_KINDS.get(exercise.load_type, ())
            if kind in best
        ],
        rep_records=[
            record_out("rep_max", mark)
            for _, mark in sorted(timeline.rep_best.get(exercise.id, {}).items())
        ],
        sessions=sessions,
        next_before=next_before,
    )


@router.get(
    "/analytics/records",
    response_model=list[ExerciseRecords],
    summary="Recordes pessoais por exercício, do feito mais recentemente",
)
def records(user: CurrentUser, db: DbSession) -> list[ExerciseRecords]:
    service = HistoryService(db)
    timeline = service.timeline(user)
    out = []
    for exercise_id, done_at in sorted(
        timeline.last_done.items(), key=lambda item: item[1], reverse=True
    ):
        best = timeline.best.get(exercise_id, {})
        kinds = RECORD_KINDS.get(timeline.load_types[exercise_id], ())
        found = [record_out(kind, best[kind]) for kind in kinds if kind in best]
        if not found:
            continue
        out.append(
            ExerciseRecords(
                # Vem dos treinos do próprio usuário: catálogo ou exercício dele.
                exercise=ExerciseRef.of(db.get(Exercise, exercise_id)),
                records=found,
                last_done_at=done_at,
            )
        )
    return out
