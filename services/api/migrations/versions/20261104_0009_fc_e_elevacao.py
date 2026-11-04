"""Frequência cardíaca e ganho de elevação nas atividades de resistência (3.2).

Revision ID: 0009
Revises: 0008
Create Date: 2026-11-04
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_CHECKS = {
    "elevation_range": "elevation_gain_m BETWEEN 0 AND 10000",
    "avg_hr_range": "avg_hr BETWEEN 30 AND 230",
    "max_hr_range": "max_hr BETWEEN 30 AND 250",
    "max_hr_not_below_avg": "max_hr >= avg_hr",
}


def upgrade() -> None:
    op.add_column("endurance_details", sa.Column("elevation_gain_m", sa.Integer(), nullable=True))
    op.add_column("endurance_details", sa.Column("avg_hr", sa.SmallInteger(), nullable=True))
    op.add_column("endurance_details", sa.Column("max_hr", sa.SmallInteger(), nullable=True))
    for name, sql in _CHECKS.items():
        op.create_check_constraint(op.f(f"ck_endurance_details_{name}"), "endurance_details", sql)


def downgrade() -> None:
    for name in reversed(_CHECKS):
        op.drop_constraint(op.f(f"ck_endurance_details_{name}"), "endurance_details", type_="check")
    op.drop_column("endurance_details", "max_hr")
    op.drop_column("endurance_details", "avg_hr")
    op.drop_column("endurance_details", "elevation_gain_m")
