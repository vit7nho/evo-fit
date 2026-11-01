import uuid
from typing import Any

from sqlalchemy import CheckConstraint, ForeignKey, Index, SmallInteger, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Timestamps, UUIDPrimaryKey
from app.modules.exercises.models import Exercise


class WorkoutTemplate(UUIDPrimaryKey, Timestamps, Base):
    """Ficha de treino. Itens e grupos são regravados juntos a cada salvamento."""

    __tablename__ = "workout_templates"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(60))
    notes: Mapped[str | None] = mapped_column(Text)
    # Ordem das fichas do usuário (Treino A, B, C...).
    position: Mapped[int] = mapped_column(SmallInteger)

    groups: Mapped[list[ExerciseGroup]] = relationship(
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="ExerciseGroup.position",
        lazy="selectin",
    )
    items: Mapped[list[TemplateItem]] = relationship(
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="TemplateItem.position",
        lazy="selectin",
    )


class ExerciseGroup(UUIDPrimaryKey, Base):
    """Exercícios consecutivos feitos em sequência, sem descanso entre eles (ADR-009)."""

    __tablename__ = "exercise_groups"

    # Pertence a uma ficha ou a uma sessão (exatamente uma das duas).
    template_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("workout_templates.id", ondelete="CASCADE"), index=True
    )
    session_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("workout_sessions.id", ondelete="CASCADE"), index=True
    )
    position: Mapped[int] = mapped_column(SmallInteger)
    kind: Mapped[str] = mapped_column(String(16))  # superset | biset | triset | giant_set
    rest_after_s: Mapped[int | None] = mapped_column(SmallInteger)

    __table_args__ = (
        CheckConstraint("rest_after_s BETWEEN 0 AND 600", name="rest_after_range"),
        CheckConstraint(
            "(template_id IS NULL) <> (session_id IS NULL)", name="template_or_session"
        ),
    )


class TemplateItem(UUIDPrimaryKey, Base):
    __tablename__ = "template_items"

    template_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("workout_templates.id", ondelete="CASCADE")
    )
    # Exercícios nunca são apagados (os próprios são arquivados), exceto na exclusão da
    # conta: aí o CASCADE leva o item junto, em vez de travar a exclusão.
    exercise_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("exercises.id", ondelete="CASCADE"), index=True
    )
    position: Mapped[int] = mapped_column(SmallInteger)
    group_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("exercise_groups.id", ondelete="CASCADE")
    )
    # Séries planejadas, lidas e editadas como um bloco (DATA_MODEL §3).
    planned_sets: Mapped[list[dict[str, Any]]] = mapped_column(JSONB)
    rest_s: Mapped[int | None] = mapped_column(SmallInteger)
    notes: Mapped[str | None] = mapped_column(Text)

    exercise: Mapped[Exercise] = relationship(lazy="joined")
    # Relação explícita: ao regravar a ficha, o ORM apaga os itens antes dos grupos.
    group: Mapped[ExerciseGroup | None] = relationship()

    __table_args__ = (
        CheckConstraint("rest_s BETWEEN 0 AND 600", name="rest_range"),
        Index("ix_template_items_template_id_position", "template_id", "position", unique=True),
    )
