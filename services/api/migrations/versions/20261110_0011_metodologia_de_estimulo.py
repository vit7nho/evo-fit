"""Metodologia de estímulo muscular, versionada, com a v1 ativa (3.5).

Revision ID: 0011
Revises: 0010
Create Date: 2026-11-10
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Cópia fixa (não importa do app): a migração grava a v1 como ela era nesta data.
V1 = {
    "role_weights": {"primary": 1.0, "secondary": 0.5},
    "set_kind_weights": {
        "warmup": 0.0,
        "working": 1.0,
        "drop": 0.5,
        "rest_pause": 0.33,
        "cluster": 0.33,
    },
    "drop_chain_cap": 2.0,
    "count_sets_without_reps": False,
    "bands_weekly_sets": {
        "none": [0, 0.5],
        "low": [0.5, 6],
        "mid": [6, 12],
        "high": [12, None],
    },
}


def upgrade() -> None:
    table = op.create_table(
        "stimulus_methodologies",
        sa.Column("version", sa.String(length=16), nullable=False),
        sa.Column("config", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("version", name=op.f("pk_stimulus_methodologies")),
    )
    op.create_index(
        "uq_stimulus_methodologies_active",
        "stimulus_methodologies",
        ["active"],
        unique=True,
        postgresql_where=sa.text("active"),
    )
    op.bulk_insert(
        table,
        [
            {
                "version": "v1",
                "config": V1,
                "active": True,
                "description": (
                    "Séries ponderadas: principal 1, secundário 0,5; drop 0,5 e rest-pause "
                    "0,33 por segmento, cadeia até 2; aquecimento não conta. Faixas por "
                    "semana: até 0,5 nenhuma, de 0,5 a 6 baixa, de 6 a 12 média, 12 ou mais alta."
                ),
            }
        ],
    )


def downgrade() -> None:
    op.drop_index("uq_stimulus_methodologies_active", table_name="stimulus_methodologies")
    op.drop_table("stimulus_methodologies")
