"""Fichas de treino: fichas, grupos entre exercícios e itens.

Revision ID: 0005
Revises: 0004
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "workout_templates",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(60), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_workout_templates_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_workout_templates")),
    )
    op.create_index(op.f("ix_workout_templates_user_id"), "workout_templates", ["user_id"])

    op.create_table(
        "exercise_groups",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("template_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("rest_after_s", sa.SmallInteger(), nullable=True),
        sa.CheckConstraint(
            "rest_after_s BETWEEN 0 AND 600", name=op.f("ck_exercise_groups_rest_after_range")
        ),
        sa.ForeignKeyConstraint(
            ["template_id"],
            ["workout_templates.id"],
            name=op.f("fk_exercise_groups_template_id_workout_templates"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_exercise_groups")),
    )
    op.create_index(op.f("ix_exercise_groups_template_id"), "exercise_groups", ["template_id"])

    op.create_table(
        "template_items",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("template_id", sa.Uuid(), nullable=False),
        sa.Column("exercise_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("group_id", sa.Uuid(), nullable=True),
        sa.Column("planned_sets", postgresql.JSONB(), nullable=False),
        sa.Column("rest_s", sa.SmallInteger(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.CheckConstraint("rest_s BETWEEN 0 AND 600", name=op.f("ck_template_items_rest_range")),
        sa.ForeignKeyConstraint(
            ["template_id"],
            ["workout_templates.id"],
            name=op.f("fk_template_items_template_id_workout_templates"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["exercise_id"],
            ["exercises.id"],
            name=op.f("fk_template_items_exercise_id_exercises"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["group_id"],
            ["exercise_groups.id"],
            name=op.f("fk_template_items_group_id_exercise_groups"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_template_items")),
    )
    op.create_index(op.f("ix_template_items_exercise_id"), "template_items", ["exercise_id"])
    op.create_index(
        "ix_template_items_template_id_position",
        "template_items",
        ["template_id", "position"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("ix_template_items_template_id_position", table_name="template_items")
    op.drop_index(op.f("ix_template_items_exercise_id"), table_name="template_items")
    op.drop_table("template_items")
    op.drop_index(op.f("ix_exercise_groups_template_id"), table_name="exercise_groups")
    op.drop_table("exercise_groups")
    op.drop_index(op.f("ix_workout_templates_user_id"), table_name="workout_templates")
    op.drop_table("workout_templates")
