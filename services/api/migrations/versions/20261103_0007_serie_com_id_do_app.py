"""Série com id gerado no app (envio idempotente do rascunho local, ADR-037).

Revision ID: 0007
Revises: 0006
Create Date: 2026-11-03
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("set_entries", sa.Column("client_id", sa.Uuid(), nullable=True))
    # Reenviar a mesma série (resposta perdida, app reaberto) não a duplica.
    op.create_index(
        "uq_set_entries_exercise_client_id",
        "set_entries",
        ["session_exercise_id", "client_id"],
        unique=True,
        postgresql_where=sa.text("client_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_set_entries_exercise_client_id", table_name="set_entries")
    op.drop_column("set_entries", "client_id")
