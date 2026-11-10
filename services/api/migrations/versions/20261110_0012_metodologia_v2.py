"""Metodologia de estímulo v2: faixa "nenhuma" só para zero (ADR-044).

Revision ID: 0012
Revises: 0011
Create Date: 2026-11-10
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Cópia fixa (não importa do app): igual à v1, só muda a faixa "nenhuma".
V2 = {
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
        "none": [0, 0],
        "low": [0, 6],
        "mid": [6, 12],
        "high": [12, None],
    },
}

methodologies = sa.table(
    "stimulus_methodologies",
    sa.column("version", sa.String),
    sa.column("config", postgresql.JSONB),
    sa.column("active", sa.Boolean),
    sa.column("description", sa.Text),
)


def upgrade() -> None:
    # Desativa antes de inserir: o índice único parcial só aceita uma ativa.
    op.execute(methodologies.update().values(active=False))
    op.bulk_insert(
        methodologies,
        [
            {
                "version": "v2",
                "config": V2,
                "active": True,
                "description": (
                    "Igual à v1, mas a faixa nenhuma vale só para zero: qualquer estímulo "
                    "registrado entra na faixa baixa (abaixo de 6 séries por semana)."
                ),
            }
        ],
    )


def downgrade() -> None:
    op.execute(methodologies.delete().where(methodologies.c.version == "v2"))
    op.execute(methodologies.update().where(methodologies.c.version == "v1").values(active=True))
