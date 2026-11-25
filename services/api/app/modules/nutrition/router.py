import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.analytics.service import today, tz
from app.modules.auth.dependencies import CurrentUser
from app.modules.nutrition.models import Food, Meal
from app.modules.nutrition.schemas import (
    DailyOut,
    FoodIn,
    FoodOut,
    FoodUpdate,
    ItemOut,
    MealIn,
    MealOut,
    NutritionOptions,
    Option,
)
from app.modules.nutrition.service import (
    MEAL_TYPE_LABELS,
    FoodService,
    MealService,
    totals,
)
from app.modules.users.models import User

router = APIRouter(tags=["nutrição"])

DbSession = Annotated[Session, Depends(get_db)]


def food_out(food: Food, user_id: uuid.UUID) -> FoodOut:
    return FoodOut(
        id=food.id,
        name=food.name,
        source=food.source,
        source_ref=food.source_ref,
        mine=food.owner_user_id == user_id,
        kcal=food.kcal,
        protein_g=food.protein_g,
        carbs_g=food.carbs_g,
        fat_g=food.fat_g,
        fiber_g=food.fiber_g,
        default_portion_g=food.default_portion_g,
    )


def meal_out(meal: Meal, user: User) -> MealOut:
    return MealOut(
        id=meal.id,
        eaten_at=meal.eaten_at,
        local_time=meal.eaten_at.astimezone(tz(user)).replace(tzinfo=None),
        meal_type=meal.meal_type,  # type: ignore[arg-type]
        meal_type_label=MEAL_TYPE_LABELS[meal.meal_type],
        notes=meal.notes,
        items=[
            ItemOut(
                id=i.id,
                food_id=i.food_id,
                food_name=i.food_name,
                quantity_g=i.quantity_g,
                kcal=i.kcal,
                protein_g=i.protein_g,
                carbs_g=i.carbs_g,
                fat_g=i.fat_g,
                fiber_g=i.fiber_g,
            )
            for i in meal.items
        ],
        totals=totals(meal.items),
    )


@router.get("/nutrition-options", summary="Tipos de refeição (público)")
def nutrition_options() -> NutritionOptions:
    return NutritionOptions(
        meal_types=[Option(code=c, label=label) for c, label in MEAL_TYPE_LABELS.items()]
    )


# --- alimentos ---


@router.get("/foods", summary="Catálogo e alimentos próprios; busca por nome (`q`)")
def list_foods(
    user: CurrentUser,
    db: DbSession,
    q: Annotated[str | None, Query(max_length=80)] = None,
    mine: bool = False,
) -> list[FoodOut]:
    return [food_out(f, user.id) for f in FoodService(db).list(user, q=q, mine=mine)]


@router.post("/foods", status_code=status.HTTP_201_CREATED, summary="Cria um alimento próprio")
def create_food(data: FoodIn, user: CurrentUser, db: DbSession) -> FoodOut:
    return food_out(FoodService(db).create(user, data), user.id)


@router.get("/foods/{food_id}", summary="Um alimento do catálogo ou próprio")
def get_food(food_id: uuid.UUID, user: CurrentUser, db: DbSession) -> FoodOut:
    return food_out(FoodService(db).get(user, food_id), user.id)


@router.patch("/foods/{food_id}", summary="Edita um alimento próprio (o histórico não muda)")
def update_food(food_id: uuid.UUID, data: FoodUpdate, user: CurrentUser, db: DbSession) -> FoodOut:
    return food_out(FoodService(db).update(user, food_id, data), user.id)


@router.delete(
    "/foods/{food_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Apaga um alimento próprio (as refeições registradas continuam)",
)
def delete_food(food_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    FoodService(db).delete(user, food_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- refeições ---


@router.post(
    "/meals",
    status_code=status.HTTP_201_CREATED,
    summary="Registra uma refeição (exige o consentimento health_data)",
)
def create_meal(data: MealIn, user: CurrentUser, db: DbSession) -> MealOut:
    return meal_out(MealService(db).create(user, data), user)


@router.get("/meals/{meal_id}", summary="Uma refeição com os itens")
def get_meal(meal_id: uuid.UUID, user: CurrentUser, db: DbSession) -> MealOut:
    return meal_out(MealService(db).get(user, meal_id), user)


@router.put(
    "/meals/{meal_id}",
    summary="Regrava a refeição inteira (os itens são recalculados pelos alimentos atuais)",
)
def replace_meal(meal_id: uuid.UUID, data: MealIn, user: CurrentUser, db: DbSession) -> MealOut:
    return meal_out(MealService(db).replace(user, meal_id, data), user)


@router.delete("/meals/{meal_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Apaga")
def delete_meal(meal_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    MealService(db).delete(user, meal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/nutrition/daily",
    summary="As refeições de um dia (no fuso da pessoa) e os totais; padrão: hoje",
)
def daily(
    user: CurrentUser, db: DbSession, day: Annotated[date | None, Query(alias="date")] = None
) -> DailyOut:
    day = day or today(user)
    meals = MealService(db).of_day(user, day)
    return DailyOut(
        date=day,
        totals=totals(item for m in meals for item in m.items),
        meals=[meal_out(m, user) for m in meals],
    )
