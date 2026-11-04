"""Planos progressivos de caminhada, 5 km e 10 km (3.3).

Revision ID: 0010
Revises: 0009
Create Date: 2026-11-04
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "training_plans",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("template_version", sa.SmallInteger(), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("weekdays", postgresql.ARRAY(sa.SmallInteger()), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("adapted_for", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "kind IN ('walk_habit', 'run_5k', 'run_10k')", name=op.f("ck_training_plans_kind")
        ),
        sa.CheckConstraint(
            "status IN ('active', 'completed', 'ended')", name=op.f("ck_training_plans_status")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_training_plans_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_training_plans")),
    )
    op.create_index(op.f("ix_training_plans_user_id"), "training_plans", ["user_id"])
    op.create_index(
        "uq_training_plans_user_active",
        "training_plans",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("status = 'active'"),
    )

    op.create_table(
        "plan_sessions",
        sa.Column("plan_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("week", sa.SmallInteger(), nullable=False),
        sa.Column("day_index", sa.SmallInteger(), nullable=False),
        sa.Column("template_week", sa.SmallInteger(), nullable=False),
        sa.Column("prescription", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("scheduled_date", sa.Date(), nullable=False),
        sa.Column("completed_activity_id", sa.Uuid(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["completed_activity_id"],
            ["activities.id"],
            name=op.f("fk_plan_sessions_completed_activity_id_activities"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["plan_id"],
            ["training_plans.id"],
            name=op.f("fk_plan_sessions_plan_id_training_plans"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_plan_sessions")),
        sa.UniqueConstraint("plan_id", "position", name=op.f("uq_plan_sessions_plan_id")),
    )
    op.create_index(
        "uq_plan_sessions_completed_activity",
        "plan_sessions",
        ["completed_activity_id"],
        unique=True,
        postgresql_where=sa.text("completed_activity_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_plan_sessions_completed_activity", table_name="plan_sessions")
    op.drop_table("plan_sessions")
    op.drop_index("uq_training_plans_user_active", table_name="training_plans")
    op.drop_index(op.f("ix_training_plans_user_id"), table_name="training_plans")
    op.drop_table("training_plans")
