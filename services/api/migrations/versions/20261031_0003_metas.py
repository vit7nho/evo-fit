"""Metas do usuário.

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-31
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

goal_status = postgresql.ENUM(
    "active", "achieved", "abandoned", name="goal_status", create_type=False
)


def upgrade() -> None:
    goal_status.create(op.get_bind(), checkfirst=True)
    op.create_table(
        "goals",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("title", sa.String(80), nullable=False),
        sa.Column("target", postgresql.JSONB(), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("target_date", sa.Date(), nullable=True),
        sa.Column("status", goal_status, nullable=False),
        sa.Column("priority", sa.SmallInteger(), nullable=False),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint("priority BETWEEN 1 AND 3", name=op.f("ck_goals_priority_range")),
        sa.CheckConstraint(
            "target_date IS NULL OR target_date >= start_date",
            name=op.f("ck_goals_target_after_start"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_goals_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_goals")),
    )
    op.create_index("ix_goals_user_id_status", "goals", ["user_id", "status"])


def downgrade() -> None:
    op.drop_index("ix_goals_user_id_status", table_name="goals")
    op.drop_table("goals")
    goal_status.drop(op.get_bind(), checkfirst=True)
