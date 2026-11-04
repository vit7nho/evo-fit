import uuid
from datetime import date, datetime

from sqlalchemy import (
    CheckConstraint,
    Date,
    ForeignKey,
    Index,
    SmallInteger,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Timestamps, UUIDPrimaryKey
from app.modules.activities.models import Activity

# Chaves de `adapted_for` que vêm de dados de saúde: saem quando o consentimento é revogado.
HEALTH_FLAGS = ("joint_care", "medical_clearance_advised")


class TrainingPlan(UUIDPrimaryKey, Timestamps, Base):
    """Plano gerado de um template versionado (templates.py). As sessões são uma cópia:
    mudar o template depois não muda o plano de ninguém."""

    __tablename__ = "training_plans"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # walk_habit | run_5k | run_10k
    kind: Mapped[str] = mapped_column(String(16))
    template_version: Mapped[int] = mapped_column(SmallInteger)
    start_date: Mapped[date] = mapped_column(Date)
    # Dias da semana escolhidos (0 = segunda … 6 = domingo), em ordem.
    weekdays: Mapped[list[int]] = mapped_column(ARRAY(SmallInteger))
    # active | completed | ended
    status: Mapped[str] = mapped_column(String(16), default="active")
    # O que a geração levou em conta (experiência; ajustes de saúde, que saem na revogação).
    adapted_for: Mapped[dict] = mapped_column(JSONB, default=dict)
    ended_at: Mapped[datetime | None]

    sessions: Mapped[list[PlanSession]] = relationship(
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="PlanSession.position",
    )

    __table_args__ = (
        CheckConstraint("kind IN ('walk_habit', 'run_5k', 'run_10k')", name="kind"),
        CheckConstraint("status IN ('active', 'completed', 'ended')", name="status"),
        # Um plano em andamento por pessoa.
        Index(
            "uq_training_plans_user_active",
            "user_id",
            unique=True,
            postgresql_where=text("status = 'active'"),
        ),
    )


class PlanSession(UUIDPrimaryKey, Base):
    __tablename__ = "plan_sessions"

    plan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("training_plans.id", ondelete="CASCADE"))
    # Ordem no plano (1…n); semana do plano e sessão dentro dela (1…3).
    position: Mapped[int] = mapped_column(SmallInteger)
    week: Mapped[int] = mapped_column(SmallInteger)
    day_index: Mapped[int] = mapped_column(SmallInteger)
    # Semana do template de onde veio (difere de `week` quando há semanas repetidas).
    template_week: Mapped[int] = mapped_column(SmallInteger)
    prescription: Mapped[list] = mapped_column(JSONB)
    # Sugestão de data; a próxima sessão é sempre a primeira não feita, em qualquer dia.
    scheduled_date: Mapped[date] = mapped_column(Date)
    completed_activity_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("activities.id", ondelete="SET NULL")
    )
    completed_at: Mapped[datetime | None]

    completed_activity: Mapped[Activity | None] = relationship()

    __table_args__ = (
        UniqueConstraint("plan_id", "position"),
        # Uma atividade conta para uma sessão só.
        Index(
            "uq_plan_sessions_completed_activity",
            "completed_activity_id",
            unique=True,
            postgresql_where=text("completed_activity_id IS NOT NULL"),
        ),
    )
