"""Objetivos do perfil e conclusão do onboarding.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-31
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("user_profiles", sa.Column("primary_objective", sa.String(32), nullable=True))
    # server_default só para preencher perfis já existentes; depois a aplicação define o valor.
    op.add_column(
        "user_profiles",
        sa.Column(
            "secondary_objectives",
            postgresql.ARRAY(sa.String(32)),
            nullable=False,
            server_default="{}",
        ),
    )
    op.alter_column("user_profiles", "secondary_objectives", server_default=None)
    op.add_column(
        "user_profiles",
        sa.Column("onboarding_completed_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("user_profiles", "onboarding_completed_at")
    op.drop_column("user_profiles", "secondary_objectives")
    op.drop_column("user_profiles", "primary_objective")
