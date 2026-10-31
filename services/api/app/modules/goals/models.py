import enum
import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import CheckConstraint, Enum, ForeignKey, Index, SmallInteger, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, Timestamps, UUIDPrimaryKey


class GoalStatus(enum.StrEnum):
    ACTIVE = "active"
    ACHIEVED = "achieved"
    ABANDONED = "abandoned"


class Goal(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "goals"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    # Código de app/modules/goals/kinds.py (texto, não enum: um tipo novo não exige migração).
    kind: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(String(80))
    # Alvo validado pelos campos do tipo (kinds.validate_target).
    target: Mapped[dict[str, Any]] = mapped_column(JSONB)
    start_date: Mapped[date]
    target_date: Mapped[date | None]
    status: Mapped[GoalStatus] = mapped_column(
        Enum(GoalStatus, name="goal_status", values_callable=lambda e: [m.value for m in e]),
        default=GoalStatus.ACTIVE,
    )
    # 1 = alta, 2 = média, 3 = baixa.
    priority: Mapped[int] = mapped_column(SmallInteger, default=2)
    # Quando saiu de "ativa" (alcançada ou abandonada); volta a nulo se reativada.
    closed_at: Mapped[datetime | None]

    __table_args__ = (
        CheckConstraint("priority BETWEEN 1 AND 3", name="priority_range"),
        CheckConstraint(
            "target_date IS NULL OR target_date >= start_date", name="target_after_start"
        ),
        Index("ix_goals_user_id_status", "user_id", "status"),
    )
