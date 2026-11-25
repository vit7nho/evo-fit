import uuid
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

MealType = Literal["breakfast", "lunch", "dinner", "snack", "other"]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=80)]
Per100 = Annotated[float, Field(ge=0, le=100)]


class _Closed(BaseModel):
    model_config = ConfigDict(extra="forbid")


class FoodIn(_Closed):
    """Valores por 100 g."""

    name: Name
    kcal: Annotated[float, Field(ge=0, le=900)]
    protein_g: Per100
    carbs_g: Per100
    fat_g: Per100
    fiber_g: Per100 | None = None
    default_portion_g: Annotated[int, Field(ge=1, le=2000)] | None = None

    @model_validator(mode="after")
    def _plausible(self) -> FoodIn:
        # Em 100 g não cabem mais de 100 g de nutrientes.
        total = self.protein_g + self.carbs_g + self.fat_g + (self.fiber_g or 0)
        if total > 100:
            raise ValueError("Proteína, carboidratos, gordura e fibras somam mais de 100 g.")
        return self


class FoodUpdate(_Closed):
    name: Name | None = None
    kcal: Annotated[float, Field(ge=0, le=900)] | None = None
    protein_g: Per100 | None = None
    carbs_g: Per100 | None = None
    fat_g: Per100 | None = None
    fiber_g: Per100 | None = None
    default_portion_g: Annotated[int, Field(ge=1, le=2000)] | None = None


class FoodOut(BaseModel):
    id: uuid.UUID
    name: str
    source: str
    source_ref: str | None
    mine: bool
    kcal: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float | None
    default_portion_g: int | None


class ItemIn(_Closed):
    food_id: uuid.UUID
    quantity_g: Annotated[float, Field(gt=0, le=5000)]


class MealIn(_Closed):
    # Com fuso: o instante; sem fuso: o horário no fuso do perfil.
    eaten_at: datetime
    meal_type: MealType
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=300)] | None = None
    items: Annotated[list[ItemIn], Field(min_length=1, max_length=30)]


class Nutrients(BaseModel):
    kcal: float
    protein_g: float
    carbs_g: float
    fat_g: float
    # Nulo quando nenhum item tem fibra registrada (não é zero).
    fiber_g: float | None


class ItemOut(Nutrients):
    id: uuid.UUID
    food_id: uuid.UUID | None
    food_name: str
    quantity_g: float


class MealOut(BaseModel):
    id: uuid.UUID
    eaten_at: datetime
    # O mesmo horário no fuso do perfil, sem fuso (o que a tela mostra e edita).
    local_time: datetime
    meal_type: MealType
    meal_type_label: str
    notes: str | None
    items: list[ItemOut]
    totals: Nutrients


Grams = Annotated[int, Field(ge=0, le=5000)]


class TargetsIn(_Closed):
    """Metas diárias; todas nulas = sem metas a partir de hoje. Os limites de
    segurança (ADR-059) são conferidos no serviço, porque dependem do perfil."""

    kcal: Annotated[int, Field(ge=0, le=20000)] | None = None
    protein_g: Grams | None = None
    carbs_g: Grams | None = None
    fat_g: Grams | None = None


class Targets(BaseModel):
    valid_from: date
    kcal: int | None
    protein_g: int | None
    carbs_g: int | None
    fat_g: int | None
    # Calorias dos macronutrientes informados (4/4/9 kcal por grama); nulo sem nenhum.
    macros_kcal: int | None


class Range(BaseModel):
    min: int
    max: int


class TargetLimits(BaseModel):
    """O que a pessoa pode escolher (para o formulário explicar antes de enviar)."""

    kcal: Range
    protein_g: Range
    carbs_g: Range
    fat_g: Range
    # Falso para menores de 18 anos: meta de calorias só com acompanhamento.
    kcal_allowed: bool
    # Tolerância entre as calorias dos macronutrientes e a meta de calorias.
    macros_tolerance_pct: int


class TargetsOut(BaseModel):
    current: Targets | None
    history: list[Targets]
    limits: TargetLimits


class DailyOut(BaseModel):
    date: date
    totals: Nutrients
    meals: list[MealOut]
    # A meta que vale neste dia (nula sem metas).
    targets: Targets | None = None


class SummaryDay(BaseModel):
    date: date
    meals: int
    totals: Nutrients
    targets: Targets | None


class SummaryOut(BaseModel):
    from_date: date
    to_date: date
    # Dias com ao menos uma refeição; a média é só deles.
    logged_days: int
    average: Nutrients | None
    days: list[SummaryDay]


class Option(BaseModel):
    code: str
    label: str


class NutritionOptions(BaseModel):
    meal_types: list[Option]
