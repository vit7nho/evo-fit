"""Alimentos, refeições e itens (DATA_MODEL §5, ADR-055).

Os nutrientes do alimento são por 100 g. Cada item da refeição guarda uma cópia do
nome e dos nutrientes calculados no momento do registro: editar ou apagar o
alimento depois não muda o histórico.
"""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    CheckConstraint,
    Float,
    ForeignKey,
    Index,
    SmallInteger,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Timestamps, UUIDPrimaryKey

MEAL_TYPES = ("breakfast", "lunch", "dinner", "snack", "other")
FOOD_SOURCES = ("user", "seed", "taco")


class Food(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "foods"

    # Nulo = catálogo (de todos); preenchido = alimento próprio da pessoa.
    owner_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE")
    )
    name: Mapped[str] = mapped_column(String(80))
    search_name: Mapped[str] = mapped_column(String(80))
    source: Mapped[str] = mapped_column(String(8))
    # Referência na fonte (ex.: o número do alimento na TACO).
    source_ref: Mapped[str | None] = mapped_column(String(40))
    # Por 100 g.
    kcal: Mapped[float] = mapped_column(Float)
    protein_g: Mapped[float] = mapped_column(Float)
    carbs_g: Mapped[float] = mapped_column(Float)
    fat_g: Mapped[float] = mapped_column(Float)
    fiber_g: Mapped[float | None] = mapped_column(Float)
    default_portion_g: Mapped[int | None] = mapped_column(SmallInteger)

    __table_args__ = (
        CheckConstraint(
            f"source IN ({', '.join(repr(s) for s in FOOD_SOURCES)})", name="source_known"
        ),
        CheckConstraint(
            "(source = 'user') = (owner_user_id IS NOT NULL)", name="owner_matches_source"
        ),
        Index("ix_foods_owner_user_id_search_name", "owner_user_id", "search_name"),
    )


class Meal(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "meals"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    eaten_at: Mapped[datetime]
    meal_type: Mapped[str] = mapped_column(String(16))
    notes: Mapped[str | None] = mapped_column(String(300))

    items: Mapped[list[MealItem]] = relationship(
        back_populates="meal",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="MealItem.position",
    )

    __table_args__ = (
        CheckConstraint(
            f"meal_type IN ({', '.join(repr(t) for t in MEAL_TYPES)})", name="meal_type_known"
        ),
        Index("ix_meals_user_id_eaten_at", "user_id", "eaten_at"),
    )


class MealItem(UUIDPrimaryKey, Base):
    __tablename__ = "meal_items"

    meal_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("meals.id", ondelete="CASCADE"))
    # Nulo se o alimento próprio for apagado depois: o item fica com a cópia.
    food_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("foods.id", ondelete="SET NULL"))
    position: Mapped[int] = mapped_column(SmallInteger)
    food_name: Mapped[str] = mapped_column(String(80))
    quantity_g: Mapped[float] = mapped_column(Float)
    # Cópia dos nutrientes da quantidade registrada (não por 100 g).
    kcal: Mapped[float] = mapped_column(Float)
    protein_g: Mapped[float] = mapped_column(Float)
    carbs_g: Mapped[float] = mapped_column(Float)
    fat_g: Mapped[float] = mapped_column(Float)
    fiber_g: Mapped[float | None] = mapped_column(Float)

    meal: Mapped[Meal] = relationship(back_populates="items")

    __table_args__ = (Index("ix_meal_items_meal_id", "meal_id"),)


class NutritionTarget(UUIDPrimaryKey, Timestamps, Base):
    """Metas diárias (5.2, ADR-059), com histórico: vale a de `valid_from` mais recente
    até o dia. Todos os valores nulos = sem metas a partir dessa data."""

    __tablename__ = "nutrition_targets"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    # Dia no fuso do perfil (o mesmo que separa as refeições).
    valid_from: Mapped[date]
    kcal: Mapped[int | None] = mapped_column(SmallInteger)
    protein_g: Mapped[int | None] = mapped_column(SmallInteger)
    carbs_g: Mapped[int | None] = mapped_column(SmallInteger)
    fat_g: Mapped[int | None] = mapped_column(SmallInteger)

    __table_args__ = (UniqueConstraint("user_id", "valid_from"),)
