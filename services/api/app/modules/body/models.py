"""Peso e medidas corporais (DATA_MODEL §5, ADR-060). Dado de saúde."""

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, Float, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, Timestamps, UUIDPrimaryKey

# As medidas, na ordem em que o app mostra.
METRICS = (
    "weight_kg",
    "body_fat_pct",
    "waist_cm",
    "hip_cm",
    "chest_cm",
    "arm_cm",
    "thigh_cm",
    "calf_cm",
)


class BodyMeasurement(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "body_measurements"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    measured_at: Mapped[datetime]
    weight_kg: Mapped[float | None] = mapped_column(Float)
    # Estimativa (balança de bioimpedância, dobras): o app rotula assim.
    body_fat_pct: Mapped[float | None] = mapped_column(Float)
    waist_cm: Mapped[float | None] = mapped_column(Float)
    hip_cm: Mapped[float | None] = mapped_column(Float)
    chest_cm: Mapped[float | None] = mapped_column(Float)
    arm_cm: Mapped[float | None] = mapped_column(Float)
    thigh_cm: Mapped[float | None] = mapped_column(Float)
    calf_cm: Mapped[float | None] = mapped_column(Float)
    notes: Mapped[str | None] = mapped_column(String(300))

    __table_args__ = (
        CheckConstraint(
            " OR ".join(f"{m} IS NOT NULL" for m in METRICS), name="at_least_one_value"
        ),
        Index("ix_body_measurements_user_id_measured_at", "user_id", "measured_at"),
    )
