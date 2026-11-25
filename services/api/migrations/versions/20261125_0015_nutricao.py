"""Alimentos, refeições e itens (5.1, ADR-055).

Revision ID: 0015
Revises: 0014
Create Date: 2026-11-25
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0015"
down_revision: str | None = "0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "foods",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_user_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("search_name", sa.String(length=80), nullable=False),
        sa.Column("source", sa.String(length=8), nullable=False),
        sa.Column("source_ref", sa.String(length=40), nullable=True),
        sa.Column("kcal", sa.Float(), nullable=False),
        sa.Column("protein_g", sa.Float(), nullable=False),
        sa.Column("carbs_g", sa.Float(), nullable=False),
        sa.Column("fat_g", sa.Float(), nullable=False),
        sa.Column("fiber_g", sa.Float(), nullable=True),
        sa.Column("default_portion_g", sa.SmallInteger(), nullable=True),
        *_timestamps(),
        sa.CheckConstraint(
            "source IN ('user', 'seed', 'taco')", name=op.f("ck_foods_source_known")
        ),
        sa.CheckConstraint(
            "(source = 'user') = (owner_user_id IS NOT NULL)",
            name=op.f("ck_foods_owner_matches_source"),
        ),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name=op.f("fk_foods_owner_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_foods")),
    )
    op.create_index("ix_foods_owner_user_id_search_name", "foods", ["owner_user_id", "search_name"])

    op.create_table(
        "meals",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("eaten_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("meal_type", sa.String(length=16), nullable=False),
        sa.Column("notes", sa.String(length=300), nullable=True),
        *_timestamps(),
        sa.CheckConstraint(
            "meal_type IN ('breakfast', 'lunch', 'dinner', 'snack', 'other')",
            name=op.f("ck_meals_meal_type_known"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_meals_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_meals")),
    )
    op.create_index("ix_meals_user_id_eaten_at", "meals", ["user_id", "eaten_at"])

    op.create_table(
        "meal_items",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("meal_id", sa.Uuid(), nullable=False),
        sa.Column("food_id", sa.Uuid(), nullable=True),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("food_name", sa.String(length=80), nullable=False),
        sa.Column("quantity_g", sa.Float(), nullable=False),
        sa.Column("kcal", sa.Float(), nullable=False),
        sa.Column("protein_g", sa.Float(), nullable=False),
        sa.Column("carbs_g", sa.Float(), nullable=False),
        sa.Column("fat_g", sa.Float(), nullable=False),
        sa.Column("fiber_g", sa.Float(), nullable=True),
        sa.ForeignKeyConstraint(
            ["meal_id"],
            ["meals.id"],
            name=op.f("fk_meal_items_meal_id_meals"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["food_id"],
            ["foods.id"],
            name=op.f("fk_meal_items_food_id_foods"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_meal_items")),
    )
    op.create_index("ix_meal_items_meal_id", "meal_items", ["meal_id"])


def downgrade() -> None:
    op.drop_index("ix_meal_items_meal_id", table_name="meal_items")
    op.drop_table("meal_items")
    op.drop_index("ix_meals_user_id_eaten_at", table_name="meals")
    op.drop_table("meals")
    op.drop_index("ix_foods_owner_user_id_search_name", table_name="foods")
    op.drop_table("foods")
