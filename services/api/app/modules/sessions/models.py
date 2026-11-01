import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    SmallInteger,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Timestamps, UUIDPrimaryKey
from app.modules.activities.models import Activity
from app.modules.exercises.models import Exercise
from app.modules.training.models import ExerciseGroup


class WorkoutSession(UUIDPrimaryKey, Timestamps, Base):
    """Treino executado. Uma sessão aberta (em andamento ou pausada) por usuário."""

    __tablename__ = "workout_sessions"

    activity_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), unique=True
    )
    # Repetido da atividade para filtrar pelo dono sem junção (e no índice abaixo).
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    # A ficha pode ser excluída depois: a sessão guarda a própria cópia (nome e itens).
    template_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("workout_templates.id", ondelete="SET NULL")
    )
    name: Mapped[str] = mapped_column(String(60))
    status: Mapped[str] = mapped_column(String(16))  # in_progress | paused | completed
    paused_at: Mapped[datetime | None]
    paused_total_s: Mapped[int] = mapped_column(Integer, default=0)

    activity: Mapped[Activity] = relationship(lazy="joined")
    groups: Mapped[list[ExerciseGroup]] = relationship(
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="ExerciseGroup.position",
        lazy="selectin",
        primaryjoin="WorkoutSession.id == ExerciseGroup.session_id",
    )
    exercises: Mapped[list[SessionExercise]] = relationship(
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="SessionExercise.position",
        lazy="selectin",
    )

    __table_args__ = (
        Index(
            "uq_workout_sessions_open_per_user",
            "user_id",
            unique=True,
            postgresql_where=text("status IN ('in_progress', 'paused')"),
        ),
        Index("ix_workout_sessions_user_id_status", "user_id", "status"),
    )


class SessionExercise(UUIDPrimaryKey, Base):
    __tablename__ = "session_exercises"

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("workout_sessions.id", ondelete="CASCADE")
    )
    exercise_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("exercises.id", ondelete="CASCADE"), index=True
    )
    position: Mapped[int] = mapped_column(SmallInteger)
    group_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("exercise_groups.id", ondelete="CASCADE")
    )
    # Cópia do plano da ficha (referência na tela); nulo em exercício avulso.
    planned_sets: Mapped[list[dict[str, Any]] | None] = mapped_column(JSONB)
    rest_s: Mapped[int | None] = mapped_column(SmallInteger)
    notes: Mapped[str | None] = mapped_column(Text)

    exercise: Mapped[Exercise] = relationship(lazy="joined")
    group: Mapped[ExerciseGroup | None] = relationship()
    sets: Mapped[list[SetEntry]] = relationship(
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="SetEntry.position",
        lazy="selectin",
    )

    __table_args__ = (Index("ix_session_exercises_session_id_position", "session_id", "position"),)


class SetEntry(UUIDPrimaryKey, Base):
    """Série executada (DATA_MODEL §3). Drop e rest-pause (2.7) encadeiam em parent_set_id."""

    __tablename__ = "set_entries"

    session_exercise_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("session_exercises.id", ondelete="CASCADE"), index=True
    )
    position: Mapped[int] = mapped_column(SmallInteger)
    kind: Mapped[str] = mapped_column(String(16))  # warmup | working | drop | rest_pause | cluster
    parent_set_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("set_entries.id", ondelete="CASCADE")
    )
    reps: Mapped[int | None] = mapped_column(SmallInteger)
    # Carga externa; em exercício assistido, a assistência.
    load_kg: Mapped[float | None] = mapped_column(Numeric(6, 2, asdecimal=False))
    duration_s: Mapped[int | None] = mapped_column(Integer)
    rir: Mapped[int | None] = mapped_column(SmallInteger)
    rpe: Mapped[float | None] = mapped_column(Numeric(3, 1, asdecimal=False))
    to_failure: Mapped[bool] = mapped_column(Boolean, default=False)
    completed_at: Mapped[datetime]

    __table_args__ = (
        CheckConstraint(
            "(kind IN ('drop', 'rest_pause', 'cluster')) = (parent_set_id IS NOT NULL)",
            name="segment_has_parent",
        ),
    )
