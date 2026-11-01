"""Grupos musculares, exercícios e catálogo inicial (seed v1, ADR-016).

Revision ID: 0004
Revises: 0003
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from app.modules.exercises.seed import seed_exercises, seed_muscle_groups

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

muscle_role = postgresql.ENUM("primary", "secondary", name="muscle_role", create_type=False)


def upgrade() -> None:
    bind = op.get_bind()
    muscle_role.create(bind, checkfirst=True)

    op.create_table(
        "muscle_groups",
        sa.Column("id", sa.String(32), nullable=False),
        sa.Column("name_pt", sa.String(60), nullable=False),
        sa.Column("body_region", sa.String(16), nullable=False),
        sa.Column("view", sa.String(16), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_muscle_groups")),
    )

    op.create_table(
        "exercises",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_user_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("slug", sa.String(100), nullable=False),
        sa.Column("search_name", sa.String(100), nullable=False),
        sa.Column("instructions", sa.Text(), nullable=True),
        sa.Column("mechanics", sa.String(16), nullable=False),
        sa.Column("equipment", sa.String(32), nullable=False),
        sa.Column("load_type", sa.String(16), nullable=False),
        sa.Column("unilateral", sa.Boolean(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name=op.f("fk_exercises_owner_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_exercises")),
    )
    op.create_index(
        "uq_exercises_global_slug",
        "exercises",
        ["slug"],
        unique=True,
        postgresql_where=sa.text("owner_user_id IS NULL"),
    )
    op.create_index(
        "uq_exercises_owner_slug",
        "exercises",
        ["owner_user_id", "slug"],
        unique=True,
        postgresql_where=sa.text("owner_user_id IS NOT NULL"),
    )

    op.create_table(
        "exercise_muscles",
        sa.Column("exercise_id", sa.Uuid(), nullable=False),
        sa.Column("muscle_group_id", sa.String(32), nullable=False),
        sa.Column("role", muscle_role, nullable=False),
        sa.ForeignKeyConstraint(
            ["exercise_id"],
            ["exercises.id"],
            name=op.f("fk_exercise_muscles_exercise_id_exercises"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["muscle_group_id"],
            ["muscle_groups.id"],
            name=op.f("fk_exercise_muscles_muscle_group_id_muscle_groups"),
        ),
        sa.PrimaryKeyConstraint("exercise_id", "muscle_group_id", name=op.f("pk_exercise_muscles")),
    )
    op.create_index(
        op.f("ix_exercise_muscles_muscle_group_id"), "exercise_muscles", ["muscle_group_id"]
    )

    seed_muscle_groups(bind)
    seed_exercises(bind, "v1")


def downgrade() -> None:
    op.drop_index(op.f("ix_exercise_muscles_muscle_group_id"), table_name="exercise_muscles")
    op.drop_table("exercise_muscles")
    op.drop_index("uq_exercises_owner_slug", table_name="exercises")
    op.drop_index("uq_exercises_global_slug", table_name="exercises")
    op.drop_table("exercises")
    op.drop_table("muscle_groups")
    muscle_role.drop(op.get_bind(), checkfirst=True)
