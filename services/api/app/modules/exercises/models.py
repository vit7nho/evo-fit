import enum
import uuid

from sqlalchemy import Boolean, Enum, ForeignKey, Index, SmallInteger, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Timestamps, UUIDPrimaryKey


class MuscleRole(enum.StrEnum):
    PRIMARY = "primary"
    SECONDARY = "secondary"


class MuscleGroupRow(Base):
    """Grupo muscular (dados de referência; ids estáveis em catalog.MUSCLE_GROUPS)."""

    __tablename__ = "muscle_groups"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name_pt: Mapped[str] = mapped_column(String(60))
    body_region: Mapped[str] = mapped_column(String(16))
    view: Mapped[str] = mapped_column(String(16))
    position: Mapped[int] = mapped_column(SmallInteger)


class Exercise(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "exercises"

    # Nulo = catálogo global (seed do projeto); preenchido = exercício próprio do usuário.
    owner_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE")
    )
    name: Mapped[str] = mapped_column(String(80))
    slug: Mapped[str] = mapped_column(String(100))
    # Nome sem acentos e em minúsculas: a busca ignora acentos sem extensões no banco.
    search_name: Mapped[str] = mapped_column(String(100))
    instructions: Mapped[str | None] = mapped_column(Text)
    mechanics: Mapped[str] = mapped_column(String(16))
    equipment: Mapped[str] = mapped_column(String(32))
    load_type: Mapped[str] = mapped_column(String(16))
    unilateral: Mapped[bool] = mapped_column(Boolean, default=False)
    # Arquivar em vez de apagar: sessões futuras vão apontar para o exercício.
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    muscles: Mapped[list[ExerciseMuscle]] = relationship(
        back_populates="exercise",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="ExerciseMuscle.role, ExerciseMuscle.muscle_group_id",
        lazy="selectin",
    )

    __table_args__ = (
        # Slug único no catálogo global e, separadamente, entre os exercícios de cada usuário.
        Index(
            "uq_exercises_global_slug",
            "slug",
            unique=True,
            postgresql_where=text("owner_user_id IS NULL"),
        ),
        Index(
            "uq_exercises_owner_slug",
            "owner_user_id",
            "slug",
            unique=True,
            postgresql_where=text("owner_user_id IS NOT NULL"),
        ),
    )


class ExerciseMuscle(Base):
    __tablename__ = "exercise_muscles"

    exercise_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("exercises.id", ondelete="CASCADE"), primary_key=True
    )
    muscle_group_id: Mapped[str] = mapped_column(
        ForeignKey("muscle_groups.id"), primary_key=True, index=True
    )
    role: Mapped[MuscleRole] = mapped_column(
        Enum(MuscleRole, name="muscle_role", values_callable=lambda e: [m.value for m in e])
    )

    exercise: Mapped[Exercise] = relationship(back_populates="muscles")
