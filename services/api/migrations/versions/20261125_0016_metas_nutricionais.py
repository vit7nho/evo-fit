"""Metas nutricionais com histórico (5.2, ADR-059).

Revision ID: 0016
Revises: 0015
Create Date: 2026-11-25
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0016"
down_revision: str | None = "0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "nutrition_targets",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("valid_from", sa.Date(), nullable=False),
        sa.Column("kcal", sa.SmallInteger(), nullable=True),
        sa.Column("protein_g", sa.SmallInteger(), nullable=True),
        sa.Column("carbs_g", sa.SmallInteger(), nullable=True),
        sa.Column("fat_g", sa.SmallInteger(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_nutrition_targets_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_nutrition_targets")),
        sa.UniqueConstraint("user_id", "valid_from", name=op.f("uq_nutrition_targets_user_id")),
    )


def downgrade() -> None:
    op.drop_table("nutrition_targets")
