"""Atividades de resistência: detalhes de corrida, caminhada, ciclismo e natação (3.1).

Revision ID: 0008
Revises: 0007
Create Date: 2026-11-04
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _details(name: str, *columns: sa.Column, checks: Sequence[tuple[str, str]] = ()) -> None:
    op.create_table(
        name,
        sa.Column("activity_id", sa.Uuid(), nullable=False),
        *columns,
        *(sa.CheckConstraint(sql, name=op.f(f"ck_{name}_{check}")) for check, sql in checks),
        sa.ForeignKeyConstraint(
            ["activity_id"],
            ["activities.id"],
            name=op.f(f"fk_{name}_activity_id_activities"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("activity_id", name=op.f(f"pk_{name}")),
    )


def upgrade() -> None:
    op.create_check_constraint(
        op.f("ck_activities_modality"),
        "activities",
        "modality IN ('strength', 'run', 'walk', 'cycle', 'swim', 'other')",
    )
    op.create_index(
        "ix_activities_user_started",
        "activities",
        ["user_id", sa.text("started_at DESC")],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    _details(
        "endurance_details",
        sa.Column("distance_m", sa.Integer(), nullable=True),
        checks=[("distance_positive", "distance_m > 0")],
    )
    _details("cycling_details", sa.Column("indoor", sa.Boolean(), nullable=False))
    _details(
        "swim_details",
        sa.Column("pool_length_m", sa.SmallInteger(), nullable=True),
        sa.Column("laps", sa.SmallInteger(), nullable=True),
        sa.Column("stroke", sa.String(length=16), nullable=True),
        checks=[
            ("pool_length_range", "pool_length_m BETWEEN 10 AND 100"),
            ("laps_positive", "laps > 0"),
        ],
    )


def downgrade() -> None:
    op.drop_table("swim_details")
    op.drop_table("cycling_details")
    op.drop_table("endurance_details")
    op.drop_index("ix_activities_user_started", table_name="activities")
    op.drop_constraint(op.f("ck_activities_modality"), "activities", type_="check")
