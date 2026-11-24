"""Conversas com a IA e registro das execuções (4.3, ADR-051).

Revision ID: 0013
Revises: 0012
Create Date: 2026-11-19
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSONB = postgresql.JSONB(astext_type=sa.Text())


def _now() -> sa.Column:
    return sa.Column(
        "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
    )


def upgrade() -> None:
    op.create_table(
        "ai_conversations",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("scope", sa.String(length=16), nullable=False),
        sa.Column("scope_ref", JSONB, nullable=True),
        sa.Column("title", sa.String(length=80), nullable=False),
        _now(),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "scope IN ('global', 'session', 'exercise', 'muscle', 'activity', 'period')",
            name=op.f("ck_ai_conversations_scope_known"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_ai_conversations_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_conversations")),
    )
    op.create_index(
        "ix_ai_conversations_user_id_updated_at", "ai_conversations", ["user_id", "updated_at"]
    )

    op.create_table(
        "ai_messages",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("conversation_id", sa.Uuid(), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("tools_used", JSONB, nullable=False),
        _now(),
        sa.CheckConstraint("role IN ('user', 'assistant')", name=op.f("ck_ai_messages_role_known")),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["ai_conversations.id"],
            name=op.f("fk_ai_messages_conversation_id_ai_conversations"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_messages")),
    )
    op.create_index(
        "ix_ai_messages_conversation_id_created_at",
        "ai_messages",
        ["conversation_id", "created_at"],
    )

    op.create_table(
        "ai_run_logs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("conversation_id", sa.Uuid(), nullable=True),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=64), nullable=False),
        sa.Column("prompt_version", sa.String(length=32), nullable=False),
        sa.Column("prompt_hash", sa.String(length=16), nullable=False),
        sa.Column("input_tokens", sa.Integer(), nullable=False),
        sa.Column("output_tokens", sa.Integer(), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=False),
        sa.Column("iterations", sa.Integer(), nullable=False),
        sa.Column("tool_calls", JSONB, nullable=False),
        sa.Column("unverified_numbers", sa.Integer(), nullable=False),
        sa.Column("outcome", sa.String(length=16), nullable=False),
        sa.Column("error_code", sa.String(length=32), nullable=True),
        _now(),
        sa.CheckConstraint(
            "outcome IN ('ok', 'provider_error', 'rate_limited', 'invalid_output', 'refused')",
            name=op.f("ck_ai_run_logs_outcome_known"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_ai_run_logs_user_id_users"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["ai_conversations.id"],
            name=op.f("fk_ai_run_logs_conversation_id_ai_conversations"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_run_logs")),
    )
    op.create_index("ix_ai_run_logs_user_id_created_at", "ai_run_logs", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_ai_run_logs_user_id_created_at", table_name="ai_run_logs")
    op.drop_table("ai_run_logs")
    op.drop_index("ix_ai_messages_conversation_id_created_at", table_name="ai_messages")
    op.drop_table("ai_messages")
    op.drop_index("ix_ai_conversations_user_id_updated_at", table_name="ai_conversations")
    op.drop_table("ai_conversations")
