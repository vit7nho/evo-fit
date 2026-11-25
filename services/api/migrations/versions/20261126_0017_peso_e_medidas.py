"""Peso e medidas corporais (5.3, ADR-060).

Revision ID: 0017
Revises: 0016
Create Date: 2026-11-26
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0017"
down_revision: str | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

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


def upgrade() -> None:
    op.create_table(
        "body_measurements",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("measured_at", sa.DateTime(timezone=True), nullable=False),
        *[sa.Column(metric, sa.Float(), nullable=True) for metric in METRICS],
        sa.Column("notes", sa.String(length=300), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            " OR ".join(f"{m} IS NOT NULL" for m in METRICS),
            name=op.f("ck_body_measurements_at_least_one_value"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_body_measurements_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_body_measurements")),
    )
    op.create_index(
        "ix_body_measurements_user_id_measured_at",
        "body_measurements",
        ["user_id", "measured_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_body_measurements_user_id_measured_at", table_name="body_measurements")
    op.drop_table("body_measurements")
