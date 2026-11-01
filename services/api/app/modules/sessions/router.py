import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser
from app.modules.exercises import catalog as exercise_catalog
from app.modules.sessions.models import SetEntry, WorkoutSession
from app.modules.sessions.schemas import (
    ExerciseAdd,
    PreviousSet,
    SessionExerciseOut,
    SessionFinish,
    SessionOut,
    SessionStart,
    SetIn,
    SetOut,
    SetUpdate,
)
from app.modules.sessions.service import SessionService, elapsed_s
from app.modules.training.schemas import ExerciseRef, GroupOut, PlannedSet
from app.modules.users.models import User

router = APIRouter(tags=["sessões de treino"])

DbSession = Annotated[Session, Depends(get_db)]

_MUSCLE_ORDER = {m.id: i for i, m in enumerate(exercise_catalog.MUSCLE_GROUPS)}
_BASE = "/workout-sessions"


def _set_out(entry_set: SetEntry) -> SetOut:
    return SetOut(
        id=entry_set.id,
        position=entry_set.position,
        kind=entry_set.kind,
        reps=entry_set.reps,
        load_kg=entry_set.load_kg,
        duration_s=entry_set.duration_s,
        rir=entry_set.rir,
        rpe=entry_set.rpe,
        to_failure=entry_set.to_failure,
        completed_at=entry_set.completed_at,
    )


def _out(service: SessionService, user: User, session: WorkoutSession) -> SessionOut:
    group_index = {g.id: i for i, g in enumerate(session.groups)}
    previous = service.previous_sets(user, session)
    exercises, set_count, volume = [], 0, 0.0
    for entry in session.exercises:
        exercise = entry.exercise
        primary = sorted(
            (m.muscle_group_id for m in exercise.muscles if m.role == "primary"),
            key=_MUSCLE_ORDER.__getitem__,
        )
        for s in entry.sets:
            if s.kind == "warmup":
                continue
            set_count += 1
            if exercise.load_type == "external" and s.load_kg and s.reps:
                volume += s.load_kg * s.reps
        last_sets, last_at = previous.get(entry.exercise_id, ([], None))
        exercises.append(
            SessionExerciseOut(
                id=entry.id,
                exercise=ExerciseRef(
                    id=exercise.id,
                    name=exercise.name,
                    equipment=exercise.equipment,
                    load_type=exercise.load_type,
                    is_active=exercise.is_active,
                    primary_muscles=primary,
                ),
                position=entry.position,
                group=None if entry.group_id is None else group_index[entry.group_id],
                planned_sets=(
                    None
                    if entry.planned_sets is None
                    else [PlannedSet.model_validate(p) for p in entry.planned_sets]
                ),
                rest_s=entry.rest_s,
                notes=entry.notes,
                sets=[_set_out(s) for s in entry.sets],
                previous=[
                    PreviousSet(
                        kind=s.kind, reps=s.reps, load_kg=s.load_kg, duration_s=s.duration_s
                    )
                    for s in last_sets
                ],
                previous_at=last_at,
            )
        )
    activity = session.activity
    return SessionOut(
        id=session.id,
        name=session.name,
        template_id=session.template_id,
        status=session.status,
        started_at=activity.started_at,
        paused_at=session.paused_at,
        paused_total_s=session.paused_total_s,
        ended_at=activity.ended_at,
        elapsed_s=elapsed_s(session),
        perceived_effort=activity.perceived_effort,
        notes=activity.notes,
        groups=[
            GroupOut(id=g.id, kind=g.kind, rest_after_s=g.rest_after_s) for g in session.groups
        ],
        exercises=exercises,
        set_count=set_count,
        volume_kg=round(volume, 2),
    )


@router.post(
    _BASE,
    response_model=SessionOut,
    status_code=status.HTTP_201_CREATED,
    summary="Inicia um treino (de uma ficha ou livre); 409 se já houver um aberto",
)
def start_session(
    data: SessionStart, user: CurrentUser, db: DbSession, response: Response
) -> SessionOut:
    service = SessionService(db)
    session = service.start(user, data)
    response.headers["Location"] = f"/api/v1{_BASE}/{session.id}"
    return _out(service, user, session)


@router.get(
    f"{_BASE}/current",
    response_model=SessionOut,
    responses={204: {"description": "Nenhum treino aberto"}},
    summary="O treino aberto (em andamento ou pausado), se houver",
)
def current_session(user: CurrentUser, db: DbSession) -> SessionOut | Response:
    service = SessionService(db)
    session = service.current(user)
    if session is None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    return _out(service, user, session)


@router.get(f"{_BASE}/{{session_id}}", response_model=SessionOut, summary="Um treino")
def get_session(session_id: uuid.UUID, user: CurrentUser, db: DbSession) -> SessionOut:
    service = SessionService(db)
    return _out(service, user, service.get(user, session_id))


@router.post(f"{_BASE}/{{session_id}}/pause", response_model=SessionOut, summary="Pausa o treino")
def pause_session(session_id: uuid.UUID, user: CurrentUser, db: DbSession) -> SessionOut:
    service = SessionService(db)
    return _out(service, user, service.pause(user, session_id))


@router.post(f"{_BASE}/{{session_id}}/resume", response_model=SessionOut, summary="Retoma o treino")
def resume_session(session_id: uuid.UUID, user: CurrentUser, db: DbSession) -> SessionOut:
    service = SessionService(db)
    return _out(service, user, service.resume(user, session_id))


@router.post(
    f"{_BASE}/{{session_id}}/finish",
    response_model=SessionOut,
    summary="Finaliza o treino (precisa de ao menos uma série)",
)
def finish_session(
    session_id: uuid.UUID, user: CurrentUser, db: DbSession, data: SessionFinish | None = None
) -> SessionOut:
    service = SessionService(db)
    return _out(service, user, service.finish(user, session_id, data or SessionFinish()))


@router.post(
    f"{_BASE}/{{session_id}}/discard",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Descarta um treino aberto (apaga o que foi registrado)",
)
def discard_session(session_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    SessionService(db).discard(user, session_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    f"{_BASE}/{{session_id}}/exercises",
    response_model=SessionOut,
    status_code=status.HTTP_201_CREATED,
    summary="Acrescenta um exercício ao fim do treino",
)
def add_exercise(
    session_id: uuid.UUID, data: ExerciseAdd, user: CurrentUser, db: DbSession
) -> SessionOut:
    service = SessionService(db)
    return _out(service, user, service.add_exercise(user, session_id, data))


@router.delete(
    f"{_BASE}/{{session_id}}/exercises/{{entry_id}}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Tira um exercício do treino (com as séries dele)",
)
def remove_exercise(
    session_id: uuid.UUID, entry_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> Response:
    SessionService(db).remove_exercise(user, session_id, entry_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    f"{_BASE}/{{session_id}}/exercises/{{entry_id}}/sets",
    response_model=SetOut,
    status_code=status.HTTP_201_CREATED,
    summary="Registra uma série (salvamento por série)",
)
def add_set(
    session_id: uuid.UUID, entry_id: uuid.UUID, data: SetIn, user: CurrentUser, db: DbSession
) -> SetOut:
    return _set_out(SessionService(db).add_set(user, session_id, entry_id, data))


@router.patch(
    f"{_BASE}/{{session_id}}/exercises/{{entry_id}}/sets/{{set_id}}",
    response_model=SetOut,
    summary="Corrige uma série",
)
def update_set(
    session_id: uuid.UUID,
    entry_id: uuid.UUID,
    set_id: uuid.UUID,
    data: SetUpdate,
    user: CurrentUser,
    db: DbSession,
) -> SetOut:
    return _set_out(SessionService(db).update_set(user, session_id, entry_id, set_id, data))


@router.delete(
    f"{_BASE}/{{session_id}}/exercises/{{entry_id}}/sets/{{set_id}}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Apaga uma série",
)
def delete_set(
    session_id: uuid.UUID, entry_id: uuid.UUID, set_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> Response:
    SessionService(db).delete_set(user, session_id, entry_id, set_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
