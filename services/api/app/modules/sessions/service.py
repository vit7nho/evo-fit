"""Sessões de treino do usuário autenticado (DATA_MODEL §3, ADR-032).

Uma sessão aberta (em andamento ou pausada) por usuário. Cada série é salva na hora,
então fechar e reabrir o app retoma o treino pela API. A sessão de outra pessoa responde
404; a ficha usada e os exercícios adicionados precisam ser visíveis para o dono.
"""

import logging
import uuid
from datetime import UTC, datetime

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError, FieldValidationError, NotFoundError
from app.modules.activities.models import Activity
from app.modules.exercises.models import Exercise
from app.modules.sessions.models import SessionExercise, SetEntry, WorkoutSession
from app.modules.sessions.schemas import ExerciseAdd, SessionFinish, SessionStart, SetIn, SetUpdate
from app.modules.training.models import ExerciseGroup, WorkoutTemplate
from app.modules.users.models import User

logger = logging.getLogger(__name__)

OPEN = ("in_progress", "paused")
MAX_EXERCISES = 30
MAX_SETS = 20
FREE_NAME = "Treino livre"


class SessionInProgressError(AppError):
    def __init__(self, session_id: uuid.UUID) -> None:
        super().__init__(
            409,
            "session_in_progress",
            "Treino em andamento",
            "Você já tem um treino em andamento. Finalize ou descarte antes de começar outro.",
            errors=[{"field": "session_id", "message": str(session_id)}],
        )


class SessionClosedError(AppError):
    def __init__(self) -> None:
        super().__init__(
            409, "session_closed", "Treino encerrado", "Este treino já foi finalizado."
        )


class EmptySessionError(AppError):
    def __init__(self) -> None:
        super().__init__(
            422,
            "session_empty",
            "Treino sem séries",
            "Registre pelo menos uma série para finalizar, ou descarte o treino.",
        )


def _now() -> datetime:
    return datetime.now(UTC)


def elapsed_s(session: WorkoutSession, now: datetime | None = None) -> int:
    """Tempo ativo: do início até agora (ou até o fim), menos as pausas."""
    activity = session.activity
    if activity.duration_s is not None:
        return activity.duration_s
    now = now or _now()
    paused = session.paused_total_s
    if session.paused_at is not None:
        paused += int((now - session.paused_at).total_seconds())
    return max(0, int((now - activity.started_at).total_seconds()) - paused)


def _check_set_values(exercise: Exercise, reps: int | None, duration_s: int | None) -> None:
    """Exercício por tempo registra duração; os demais, repetições."""
    if exercise.load_type == "time":
        if duration_s is None:
            raise FieldValidationError(
                "duration_s", f"{exercise.name} é feito por tempo: informe a duração."
            )
        if reps is not None:
            raise FieldValidationError(
                "reps", f"{exercise.name} é feito por tempo, sem repetições."
            )
    else:
        if reps is None:
            raise FieldValidationError("reps", "Informe as repetições.")
        if duration_s is not None:
            raise FieldValidationError("duration_s", f"{exercise.name} é feito por repetições.")


class SessionService:
    def __init__(self, db: Session) -> None:
        self.db = db

    # --- consultas ---

    def current(self, user: User) -> WorkoutSession | None:
        return self.db.scalar(
            select(WorkoutSession).where(
                WorkoutSession.user_id == user.id, WorkoutSession.status.in_(OPEN)
            )
        )

    def get(self, user: User, session_id: uuid.UUID) -> WorkoutSession:
        session = self.db.scalar(
            select(WorkoutSession).where(
                WorkoutSession.id == session_id, WorkoutSession.user_id == user.id
            )
        )
        if session is None:
            raise NotFoundError("Treino não encontrado.")
        return session

    def previous_sets(
        self, user: User, session: WorkoutSession
    ) -> dict[uuid.UUID, tuple[list[SetEntry], datetime]]:
        """Por exercício: as séries da última sessão concluída em que ele apareceu."""
        found: dict[uuid.UUID, tuple[list[SetEntry], datetime]] = {}
        for exercise_id in {e.exercise_id for e in session.exercises}:
            row = self.db.execute(
                select(SessionExercise, Activity.started_at)
                .join(WorkoutSession, WorkoutSession.id == SessionExercise.session_id)
                .join(Activity, Activity.id == WorkoutSession.activity_id)
                .where(
                    WorkoutSession.user_id == user.id,
                    WorkoutSession.status == "completed",
                    WorkoutSession.id != session.id,
                    Activity.deleted_at.is_(None),
                    SessionExercise.exercise_id == exercise_id,
                )
                .order_by(Activity.started_at.desc(), SessionExercise.position)
                .limit(1)
            ).first()
            if row is not None:
                previous, started_at = row
                sets = [s for s in previous.sets if s.parent_set_id is None]
                if sets:
                    found[exercise_id] = (sets, started_at)
        return found

    # --- ciclo de vida ---

    def start(self, user: User, data: SessionStart) -> WorkoutSession:
        open_session = self.current(user)
        if open_session is not None:
            raise SessionInProgressError(open_session.id)
        template = None
        if data.template_id is not None:
            template = self.db.scalar(
                select(WorkoutTemplate).where(
                    WorkoutTemplate.id == data.template_id, WorkoutTemplate.user_id == user.id
                )
            )
            if template is None:
                raise NotFoundError("Ficha não encontrada.")

        now = _now()
        activity = Activity(
            user_id=user.id, modality="strength", started_at=now, source="app_session"
        )
        session = WorkoutSession(
            activity=activity,
            user_id=user.id,
            template_id=template.id if template else None,
            name=data.name or (template.name if template else FREE_NAME),
            status="in_progress",
            paused_total_s=0,
        )
        if template is not None:
            # Cópia da ficha: editar ou excluir a ficha depois não muda este treino.
            groups = {
                g.id: ExerciseGroup(position=g.position, kind=g.kind, rest_after_s=g.rest_after_s)
                for g in template.groups
            }
            session.groups.extend(groups.values())
            session.exercises.extend(
                SessionExercise(
                    exercise_id=item.exercise_id,
                    position=item.position,
                    group=groups[item.group_id] if item.group_id else None,
                    planned_sets=item.planned_sets,
                    rest_s=item.rest_s,
                    notes=item.notes,
                )
                for item in template.items
            )
        self.db.add(session)
        try:
            self.db.commit()
        except IntegrityError as error:
            # Dois inícios ao mesmo tempo: o índice parcial garante uma sessão aberta só.
            self.db.rollback()
            if "uq_workout_sessions_open_per_user" in str(error.orig):
                raise SessionInProgressError(self.current(user).id) from error
            raise
        self.db.refresh(session)
        logger.info(
            "session_started",
            extra={"user_id": str(user.id), "session_id": str(session.id)},
        )
        return session

    def pause(self, user: User, session_id: uuid.UUID) -> WorkoutSession:
        session = self._open(user, session_id)
        if session.status == "in_progress":
            session.status = "paused"
            session.paused_at = _now()
            self.db.commit()
        return session

    def resume(self, user: User, session_id: uuid.UUID) -> WorkoutSession:
        session = self._open(user, session_id)
        if session.status == "paused":
            self._close_pause(session, _now())
            session.status = "in_progress"
            self.db.commit()
        return session

    def finish(self, user: User, session_id: uuid.UUID, data: SessionFinish) -> WorkoutSession:
        session = self._open(user, session_id)
        if not any(e.sets for e in session.exercises):
            raise EmptySessionError
        now = _now()
        self._close_pause(session, now)
        session.activity.ended_at = now
        session.activity.duration_s = elapsed_s(session, now)
        session.activity.perceived_effort = data.perceived_effort
        session.activity.notes = data.notes or None
        session.status = "completed"
        self.db.commit()
        self.db.refresh(session)
        logger.info(
            "session_finished",
            extra={"user_id": str(user.id), "session_id": str(session.id)},
        )
        return session

    def discard(self, user: User, session_id: uuid.UUID) -> None:
        """Apaga um treino aberto (a atividade leva a sessão, os exercícios e as séries)."""
        session = self._open(user, session_id)
        self.db.delete(session.activity)
        self.db.commit()
        logger.info(
            "session_discarded", extra={"user_id": str(user.id), "session_id": str(session_id)}
        )

    # --- exercícios e séries ---

    def add_exercise(self, user: User, session_id: uuid.UUID, data: ExerciseAdd) -> WorkoutSession:
        session = self._open(user, session_id)
        if len(session.exercises) >= MAX_EXERCISES:
            raise FieldValidationError(
                "exercise_id", f"Um treino tem até {MAX_EXERCISES} exercícios."
            )
        exercise = self.db.scalar(
            select(Exercise).where(
                Exercise.id == data.exercise_id,
                or_(Exercise.owner_user_id.is_(None), Exercise.owner_user_id == user.id),
            )
        )
        if exercise is None:
            raise FieldValidationError("exercise_id", "Exercício não encontrado.")
        position = max((e.position for e in session.exercises), default=-1) + 1
        session.exercises.append(
            SessionExercise(exercise_id=exercise.id, position=position, rest_s=90)
        )
        self.db.commit()
        self.db.refresh(session)
        return session

    def remove_exercise(self, user: User, session_id: uuid.UUID, entry_id: uuid.UUID) -> None:
        session = self._open(user, session_id)
        entry = self._entry(session, entry_id)
        group = entry.group
        session.exercises.remove(entry)
        self.db.flush()
        # Grupo que ficou com um exercício só deixa de ser grupo.
        if group is not None:
            members = [e for e in session.exercises if e.group_id == group.id]
            if len(members) < 2:
                for member in members:
                    member.group = None
                session.groups.remove(group)
        self.db.commit()

    def add_set(
        self, user: User, session_id: uuid.UUID, entry_id: uuid.UUID, data: SetIn
    ) -> SetEntry:
        session = self._open(user, session_id)
        entry = self._entry(session, entry_id)
        if len(entry.sets) >= MAX_SETS:
            raise FieldValidationError(
                "kind", f"Um exercício tem até {MAX_SETS} séries por treino."
            )
        _check_set_values(entry.exercise, data.reps, data.duration_s)
        entry_set = SetEntry(
            position=max((s.position for s in entry.sets), default=-1) + 1,
            kind=data.kind,
            reps=data.reps,
            load_kg=data.load_kg,
            duration_s=data.duration_s,
            rir=data.rir,
            rpe=data.rpe,
            to_failure=False,
            completed_at=_now(),
        )
        entry.sets.append(entry_set)
        self.db.commit()
        self.db.refresh(entry_set)
        return entry_set

    def update_set(
        self,
        user: User,
        session_id: uuid.UUID,
        entry_id: uuid.UUID,
        set_id: uuid.UUID,
        data: SetUpdate,
    ) -> SetEntry:
        session = self._open(user, session_id)
        entry = self._entry(session, entry_id)
        entry_set = self._set(entry, set_id)
        changes = data.model_fields_set
        if "kind" in changes and data.kind is None:
            raise FieldValidationError("kind", "Campo obrigatório.")
        reps = data.reps if "reps" in changes else entry_set.reps
        duration = data.duration_s if "duration_s" in changes else entry_set.duration_s
        _check_set_values(entry.exercise, reps, duration)
        for name in changes:
            setattr(entry_set, name, getattr(data, name))
        self.db.commit()
        self.db.refresh(entry_set)
        return entry_set

    def delete_set(
        self, user: User, session_id: uuid.UUID, entry_id: uuid.UUID, set_id: uuid.UUID
    ) -> None:
        session = self._open(user, session_id)
        entry = self._entry(session, entry_id)
        entry.sets.remove(self._set(entry, set_id))
        self.db.commit()

    # --- apoio ---

    def _open(self, user: User, session_id: uuid.UUID) -> WorkoutSession:
        session = self.get(user, session_id)
        if session.status not in OPEN:
            raise SessionClosedError
        return session

    @staticmethod
    def _entry(session: WorkoutSession, entry_id: uuid.UUID) -> SessionExercise:
        for entry in session.exercises:
            if entry.id == entry_id:
                return entry
        raise NotFoundError("Exercício não encontrado neste treino.")

    @staticmethod
    def _set(entry: SessionExercise, set_id: uuid.UUID) -> SetEntry:
        for entry_set in entry.sets:
            if entry_set.id == set_id:
                return entry_set
        raise NotFoundError("Série não encontrada.")

    @staticmethod
    def _close_pause(session: WorkoutSession, now: datetime) -> None:
        if session.paused_at is not None:
            session.paused_total_s += int((now - session.paused_at).total_seconds())
            session.paused_at = None
