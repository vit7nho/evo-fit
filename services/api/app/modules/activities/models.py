import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, ForeignKey, Index, Integer, SmallInteger, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, Timestamps, UUIDPrimaryKey


class Activity(UUIDPrimaryKey, Timestamps, Base):
    """Base multimodal (DATA_MODEL §3): musculação hoje; corrida, caminhada etc. na Fase 3."""

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

    __table_args__ = (
        CheckConstraint("perceived_effort BETWEEN 1 AND 10", name="effort_range"),
        Index(
            "uq_activities_user_source_external",
            "user_id",
            "source",
            "external_id",
            unique=True,
            postgresql_where=text("external_id IS NOT NULL"),
        ),
    )
