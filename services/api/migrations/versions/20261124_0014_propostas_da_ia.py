"""Propostas de alteração feitas pela IA (4.6, ADR-053).

Revision ID: 0014
Revises: 0013
Create Date: 2026-11-24
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSONB = postgresql.JSONB(astext_type=sa.Text())
KINDS = (
    "'template_add_exercise', 'template_replace_exercise', 'template_adjust_sets', 'goal_create'"
)
STATUSES = "'pending', 'accepted', 'rejected', 'expired', 'failed'"


def upgrade() -> None:
    op.create_table(
        "change_proposals",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("conversation_id", sa.Uuid(), nullable=True),
        sa.Column("message_id", sa.Uuid(), nullable=True),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("payload", JSONB, nullable=False),
        sa.Column("base_hash", sa.String(length=64), nullable=True),
        sa.Column("summary", sa.String(length=200), nullable=False),
        sa.Column("details", JSONB, nullable=False),
        sa.Column("rationale", sa.String(length=300), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("result", sa.String(length=300), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(f"kind IN ({KINDS})", name=op.f("ck_change_proposals_kind_known")),
        sa.CheckConstraint(
            f"status IN ({STATUSES})", name=op.f("ck_change_proposals_status_known")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_change_proposals_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["ai_conversations.id"],
            name=op.f("fk_change_proposals_conversation_id_ai_conversations"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["message_id"],
            ["ai_messages.id"],
            name=op.f("fk_change_proposals_message_id_ai_messages"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_change_proposals")),
    )
    op.create_index("ix_change_proposals_user_id_status", "change_proposals", ["user_id", "status"])
    op.create_index("ix_change_proposals_conversation_id", "change_proposals", ["conversation_id"])


def downgrade() -> None:
    op.drop_index("ix_change_proposals_conversation_id", table_name="change_proposals")
    op.drop_index("ix_change_proposals_user_id_status", table_name="change_proposals")
    op.drop_table("change_proposals")
