import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    Text,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Timestamps, UUIDPrimaryKey


class Activity(UUIDPrimaryKey, Timestamps, Base):
    """Base multimodal (DATA_MODEL §3): musculação pela sessão de treino; corrida,
    caminhada, ciclismo e natação com os detalhes 1:1 abaixo (ARCHITECTURE §6)."""

    __tablename__ = "activities"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # strength | run | walk | cycle | swim | other
    modality: Mapped[str] = mapped_column(String(16))
    started_at: Mapped[datetime]
    ended_at: Mapped[datetime | None]
    # Tempo ativo (sem as pausas), gravado ao finalizar.
    duration_s: Mapped[int | None] = mapped_column(Integer)
    perceived_effort: Mapped[int | None] = mapped_column(SmallInteger)
    notes: Mapped[str | None] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(32), default="app_session")
    external_id: Mapped[str | None] = mapped_column(String(128))
    # Exclusão lógica: indicadores recalculados com histórico (a da conta é física).
    deleted_at: Mapped[datetime | None]

    # Carregados só quando usados (a musculação não tem detalhes de resistência).
    endurance: Mapped[EnduranceDetails | None] = relationship(
        cascade="all, delete-orphan", passive_deletes=True
    )
    cycling: Mapped[CyclingDetails | None] = relationship(
        cascade="all, delete-orphan", passive_deletes=True
    )
    swim: Mapped[SwimDetails | None] = relationship(
        cascade="all, delete-orphan", passive_deletes=True
    )

    __table_args__ = (
        CheckConstraint("perceived_effort BETWEEN 1 AND 10", name="effort_range"),
        CheckConstraint(
            "modality IN ('strength', 'run', 'walk', 'cycle', 'swim', 'other')", name="modality"
        ),
        Index(
            "uq_activities_user_source_external",
            "user_id",
            "source",
            "external_id",
            unique=True,
            postgresql_where=text("external_id IS NOT NULL"),
        ),
        # Listas da pessoa, mais recentes primeiro (DATA_MODEL §8).
        Index(
            "ix_activities_user_started",
            "user_id",
            text("started_at DESC"),
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )


class EnduranceDetails(Base):
    """Corrida, caminhada, ciclismo e natação. Pace e velocidade não são guardados."""

    __tablename__ = "endurance_details"

    activity_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), primary_key=True
    )
    distance_m: Mapped[int | None] = mapped_column(Integer)
    elevation_gain_m: Mapped[int | None] = mapped_column(Integer)
    # Frequência cardíaca (bpm): dado de saúde, exige o consentimento health_data.
    avg_hr: Mapped[int | None] = mapped_column(SmallInteger)
    max_hr: Mapped[int | None] = mapped_column(SmallInteger)

    __table_args__ = (
        CheckConstraint("distance_m > 0", name="distance_positive"),
        CheckConstraint("elevation_gain_m BETWEEN 0 AND 10000", name="elevation_range"),
        CheckConstraint("avg_hr BETWEEN 30 AND 230", name="avg_hr_range"),
        CheckConstraint("max_hr BETWEEN 30 AND 250", name="max_hr_range"),
        CheckConstraint("max_hr >= avg_hr", name="max_hr_not_below_avg"),
    )


class CyclingDetails(Base):
    __tablename__ = "cycling_details"

    activity_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), primary_key=True
    )
    indoor: Mapped[bool] = mapped_column(Boolean, default=False)


class SwimDetails(Base):
    __tablename__ = "swim_details"

    activity_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), primary_key=True
    )
    # Sem piscina: águas abertas.
    pool_length_m: Mapped[int | None] = mapped_column(SmallInteger)
    laps: Mapped[int | None] = mapped_column(SmallInteger)
    # freestyle | breaststroke | backstroke | butterfly | mixed
    stroke: Mapped[str | None] = mapped_column(String(16))

    __table_args__ = (
        CheckConstraint("pool_length_m BETWEEN 10 AND 100", name="pool_length_range"),
        CheckConstraint("laps > 0", name="laps_positive"),
    )
