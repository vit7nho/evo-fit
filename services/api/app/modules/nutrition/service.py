"""Alimentos, refeições e totais do dia (5.1, ADR-055).

- Alimentos: o catálogo (de todos) e os próprios de cada pessoa; só os próprios
  podem ser editados ou apagados.
- Refeições são dados de saúde (SECURITY_PRIVACY §1): registrar exige o
  consentimento `health_data`, e revogá-lo apaga as refeições.
- Cada item guarda a cópia do nome e dos nutrientes da quantidade registrada.
  Regravar a refeição recalcula os itens pelos valores atuais dos alimentos.
"""

import logging
import uuid
from collections.abc import Iterable
from datetime import UTC, date, datetime, time, timedelta

from pydantic import ValidationError
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.errors import FieldValidationError, NotFoundError
from app.modules.analytics.service import today, tz
from app.modules.exercises.catalog import search_key
from app.modules.nutrition.models import Food, Meal, MealItem, NutritionTarget
from app.modules.nutrition.schemas import (
    FoodIn,
    FoodUpdate,
    MealIn,
    Nutrients,
    Range,
    SummaryDay,
    SummaryOut,
    TargetLimits,
    Targets,
    TargetsIn,
)
from app.modules.users.models import ConsentKind, SexForCalculations, User
from app.modules.users.service import ConsentRequiredError, active_consent

logger = logging.getLogger(__name__)

MEAL_TYPE_LABELS = {
    "breakfast": "Café da manhã",
    "lunch": "Almoço",
    "dinner": "Jantar",
    "snack": "Lanche",
    "other": "Outra",
}
NUTRIENTS = ("kcal", "protein_g", "carbs_g", "fat_g", "fiber_g")


def _visible(user: User):
    return or_(Food.owner_user_id.is_(None), Food.owner_user_id == user.id)


def _scaled(food: Food, quantity_g: float) -> dict[str, float | None]:
    """Nutrientes de `quantity_g` gramas (os do alimento são por 100 g)."""
    factor = quantity_g / 100
    values: dict[str, float | None] = {
        n: round(getattr(food, n) * factor, 1) for n in NUTRIENTS if n != "fiber_g"
    }
    values["fiber_g"] = None if food.fiber_g is None else round(food.fiber_g * factor, 1)
    return values


def totals(rows: Iterable[MealItem]) -> Nutrients:
    rows = list(rows)
    fibers = [r.fiber_g for r in rows if r.fiber_g is not None]
    return Nutrients(
        kcal=round(sum(r.kcal for r in rows), 1),
        protein_g=round(sum(r.protein_g for r in rows), 1),
        carbs_g=round(sum(r.carbs_g for r in rows), 1),
        fat_g=round(sum(r.fat_g for r in rows), 1),
        fiber_g=round(sum(fibers), 1) if fibers else None,
    )


class FoodService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list(self, user: User, *, q: str | None = None, mine: bool = False) -> list[Food]:
        query = select(Food).where(_visible(user))
        if mine:
            query = query.where(Food.owner_user_id == user.id)
        if q:
            # Cada palavra precisa aparecer no nome, sem diferenciar acentos.
            for word in search_key(q).split():
                query = query.where(Food.search_name.contains(word, autoescape=True))
        return list(self.db.scalars(query.order_by(Food.search_name, Food.id).limit(200)))

    def get(self, user: User, food_id: uuid.UUID) -> Food:
        food = self.db.scalar(select(Food).where(Food.id == food_id, _visible(user)))
        if food is None:
            raise NotFoundError("Alimento não encontrado.")
        return food

    def _own(self, user: User, food_id: uuid.UUID) -> Food:
        food = self.get(user, food_id)
        if food.owner_user_id != user.id:
            # O catálogo é de todos: ninguém edita nem apaga.
            raise NotFoundError("Alimento não encontrado.")
        return food

    def create(self, user: User, data: FoodIn) -> Food:
        food = Food(
            owner_user_id=user.id,
            source="user",
            search_name=search_key(data.name),
            **data.model_dump(),
        )
        self.db.add(food)
        self.db.commit()
        self.db.refresh(food)
        logger.info("food_created", extra={"user_id": str(user.id), "food_id": str(food.id)})
        return food

    def update(self, user: User, food_id: uuid.UUID, data: FoodUpdate) -> Food:
        food = self._own(user, food_id)
        changes = data.model_dump(exclude_unset=True)
        for name in {"name", "kcal", "protein_g", "carbs_g", "fat_g"} & changes.keys():
            if changes[name] is None:
                raise FieldValidationError(name, "Campo obrigatório.")
        try:
            merged = FoodIn.model_validate(
                {**{n: getattr(food, n) for n in FoodIn.model_fields}, **changes}
            )
        except ValidationError as error:
            first = error.errors()[0]
            field = ".".join(str(p) for p in first["loc"]) or "__root__"
            raise FieldValidationError(
                field, str(first["msg"]).removeprefix("Value error, ")
            ) from None
        for name, value in merged.model_dump().items():
            setattr(food, name, value)
        food.search_name = search_key(merged.name)
        self.db.commit()
        self.db.refresh(food)
        return food

    def delete(self, user: User, food_id: uuid.UUID) -> None:
        food = self._own(user, food_id)
        self.db.delete(food)  # os itens já registrados ficam com a cópia
        self.db.commit()


class MealService:
    def __init__(self, db: Session) -> None:
        self.db = db

    @staticmethod
    def _at(user: User, moment: datetime) -> datetime:
        """Horário sem fuso = horário no fuso do perfil (o mesmo que separa os dias):
        a refeição cai no dia que a pessoa vê, mesmo com o aparelho em outro fuso."""
        return moment.replace(tzinfo=tz(user)) if moment.tzinfo is None else moment

    def _require_consent(self, user: User) -> None:
        if active_consent(self.db, user.id, ConsentKind.HEALTH_DATA) is None:
            raise ConsentRequiredError(ConsentKind.HEALTH_DATA)

    def _bounds(self, user: User, day: date) -> tuple[datetime, datetime]:
        zone = tz(user)
        lower = datetime.combine(day, time.min, zone).astimezone(UTC)
        upper = datetime.combine(day + timedelta(days=1), time.min, zone).astimezone(UTC)
        return lower, upper

    def of_day(self, user: User, day: date) -> list[Meal]:
        lower, upper = self._bounds(user, day)
        return list(
            self.db.scalars(
                select(Meal)
                .where(Meal.user_id == user.id, Meal.eaten_at >= lower, Meal.eaten_at < upper)
                .order_by(Meal.eaten_at, Meal.id)
            )
        )

    def get(self, user: User, meal_id: uuid.UUID) -> Meal:
        meal = self.db.scalar(select(Meal).where(Meal.id == meal_id, Meal.user_id == user.id))
        if meal is None:
            raise NotFoundError("Refeição não encontrada.")
        return meal

    def _items(self, user: User, data: MealIn) -> list[MealItem]:
        foods = {
            f.id: f
            for f in self.db.scalars(
                select(Food).where(Food.id.in_({i.food_id for i in data.items}), _visible(user))
            )
        }
        items = []
        for index, item in enumerate(data.items):
            food = foods.get(item.food_id)
            if food is None:
                raise FieldValidationError(f"items.{index}.food_id", "Alimento não encontrado.")
            items.append(
                MealItem(
                    food_id=food.id,
                    position=index,
                    food_name=food.name,
                    quantity_g=item.quantity_g,
                    **_scaled(food, item.quantity_g),
                )
            )
        return items

    def create(self, user: User, data: MealIn) -> Meal:
        self._require_consent(user)
        meal = Meal(
            user_id=user.id,
            eaten_at=self._at(user, data.eaten_at),
            meal_type=data.meal_type,
            notes=data.notes or None,
        )
        meal.items = self._items(user, data)
        self.db.add(meal)
        self.db.commit()
        self.db.refresh(meal)
        # Sem alimentos nem quantidades no log: são dados de saúde.
        logger.info("meal_created", extra={"user_id": str(user.id), "meal_id": str(meal.id)})
        return meal

    def replace(self, user: User, meal_id: uuid.UUID, data: MealIn) -> Meal:
        meal = self.get(user, meal_id)  # de outra pessoa: 404, como um id inventado
        self._require_consent(user)
        items = self._items(user, data)
        meal.items.clear()
        self.db.flush()
        meal.eaten_at = self._at(user, data.eaten_at)
        meal.meal_type, meal.notes = data.meal_type, data.notes
        meal.items.extend(items)
        self.db.commit()
        self.db.refresh(meal)
        return meal

    def delete(self, user: User, meal_id: uuid.UUID) -> None:
        meal = self.get(user, meal_id)
        self.db.delete(meal)
        self.db.commit()

    def between(self, user: User, start: date, end: date) -> list[Meal]:
        lower, _ = self._bounds(user, start)
        _, upper = self._bounds(user, end)
        return list(
            self.db.scalars(
                select(Meal)
                .where(Meal.user_id == user.id, Meal.eaten_at >= lower, Meal.eaten_at < upper)
                .order_by(Meal.eaten_at, Meal.id)
            )
        )


# --- metas (5.2, ADR-059) ---

TARGET_FIELDS = ("kcal", "protein_g", "carbs_g", "fat_g")
# Abaixo disso, dietas pedem acompanhamento profissional (referência usual: 1.200 kcal
# para mulheres e 1.500 kcal para homens). Sem o sexo no perfil, vale o menor.
KCAL_MIN = {SexForCalculations.MALE: 1500}
KCAL_MIN_DEFAULT = 1200
KCAL_MAX = 5000
GRAMS = {"protein_g": (20, 300), "carbs_g": (20, 800), "fat_g": (20, 250)}
MACROS_TOLERANCE = 0.15
SUMMARY_MAX_DAYS = 92


def _today(user: User) -> date:
    return today(user)


KCAL_PER_GRAM = {"protein_g": 4, "carbs_g": 4, "fat_g": 9}


def thousands(value: int) -> str:
    """ "2.920", como o app mostra."""
    return f"{value:,}".replace(",", ".")


def macros_kcal(values: dict[str, int | None]) -> int | None:
    given = [
        value * factor
        for name, factor in KCAL_PER_GRAM.items()
        if (value := values.get(name)) is not None
    ]
    return sum(given) if given else None


def is_minor(user: User, day: date) -> bool:
    birth = user.profile.birth_year if user.profile else None
    return birth is not None and day.year - birth < 18


def kcal_min(user: User) -> int:
    sex = user.profile.sex_for_calculations if user.profile else None
    return KCAL_MIN.get(sex, KCAL_MIN_DEFAULT) if sex is not None else KCAL_MIN_DEFAULT


def target_limits(user: User, day: date) -> TargetLimits:
    return TargetLimits(
        kcal=Range(min=kcal_min(user), max=KCAL_MAX),
        **{name: Range(min=low, max=high) for name, (low, high) in GRAMS.items()},
        kcal_allowed=not is_minor(user, day),
        macros_tolerance_pct=round(MACROS_TOLERANCE * 100),
    )


def check_targets(user: User, data: TargetsIn, day: date) -> None:
    """Os limites de segurança (ADR-059): fora deles, a meta precisa de um profissional."""
    if data.kcal is not None:
        if is_minor(user, day):
            raise FieldValidationError(
                "kcal",
                "Para menores de 18 anos, a meta de calorias deve ser definida com um "
                "nutricionista ou médico.",
            )
        low = kcal_min(user)
        if data.kcal < low:
            raise FieldValidationError(
                "kcal",
                f"Abaixo de {thousands(low)} kcal por dia, a meta precisa do acompanhamento "
                "de um nutricionista ou médico.",
            )
        if data.kcal > KCAL_MAX:
            raise FieldValidationError(
                "kcal",
                f"Acima de {thousands(KCAL_MAX)} kcal por dia, defina a meta com um nutricionista.",
            )
    labels = {"protein_g": "proteína", "carbs_g": "carboidratos", "fat_g": "gordura"}
    for name, (low, high) in GRAMS.items():
        value = getattr(data, name)
        if value is not None and not low <= value <= high:
            raise FieldValidationError(
                name,
                f"A meta de {labels[name]} precisa ficar entre {low} e {high} g por dia; "
                "fora disso, defina com um nutricionista.",
            )
    from_macros = macros_kcal(data.model_dump())
    if data.kcal is None or from_macros is None:
        return
    complete = None not in (data.protein_g, data.carbs_g, data.fat_g)
    total, goal = thousands(from_macros), thousands(data.kcal)
    if from_macros > data.kcal * (1 + MACROS_TOLERANCE):
        raise FieldValidationError(
            "__root__", f"Os macronutrientes somam {total} kcal, acima da meta de {goal} kcal."
        )
    if complete and from_macros < data.kcal * (1 - MACROS_TOLERANCE):
        raise FieldValidationError(
            "__root__",
            f"Os macronutrientes somam {total} kcal, bem abaixo da meta de {goal} kcal.",
        )


def targets_out(target: NutritionTarget | None) -> Targets | None:
    if target is None or all(getattr(target, n) is None for n in TARGET_FIELDS):
        return None
    values = {n: getattr(target, n) for n in TARGET_FIELDS}
    return Targets(valid_from=target.valid_from, macros_kcal=macros_kcal(values), **values)


class TargetService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def _all(self, user: User, until: date | None = None) -> list[NutritionTarget]:
        query = select(NutritionTarget).where(NutritionTarget.user_id == user.id)
        if until is not None:
            query = query.where(NutritionTarget.valid_from <= until)
        return list(self.db.scalars(query.order_by(NutritionTarget.valid_from)))

    def on(self, user: User, day: date) -> NutritionTarget | None:
        return self.db.scalar(
            select(NutritionTarget)
            .where(NutritionTarget.user_id == user.id, NutritionTarget.valid_from <= day)
            .order_by(NutritionTarget.valid_from.desc())
            .limit(1)
        )

    def history(self, user: User) -> list[NutritionTarget]:
        return list(reversed(self._all(user)))[:50]

    def set(self, user: User, data: TargetsIn) -> NutritionTarget | None:
        """Vale a partir de hoje (no fuso do perfil); outra mudança no mesmo dia
        substitui a de hoje. As anteriores ficam no histórico."""
        if active_consent(self.db, user.id, ConsentKind.HEALTH_DATA) is None:
            raise ConsentRequiredError(ConsentKind.HEALTH_DATA)
        day = _today(user)
        check_targets(user, data, day)
        values = data.model_dump()
        current = self.on(user, day)
        if current is not None and all(getattr(current, n) == values[n] for n in TARGET_FIELDS):
            return current
        if current is None and all(v is None for v in values.values()):
            return None
        if current is not None and current.valid_from == day:
            target = current
            for name, value in values.items():
                setattr(target, name, value)
        else:
            target = NutritionTarget(user_id=user.id, valid_from=day, **values)
            self.db.add(target)
        self.db.commit()
        self.db.refresh(target)
        # Sem os valores no log: são dados de saúde.
        logger.info("nutrition_targets_set", extra={"user_id": str(user.id)})
        return target

    def summary(self, user: User, start: date, end: date) -> SummaryOut:
        if start > end:
            raise FieldValidationError("from", "O início precisa ser antes do fim.")
        if (end - start).days + 1 > SUMMARY_MAX_DAYS:
            raise FieldValidationError("to", f"Escolha até {SUMMARY_MAX_DAYS} dias.")
        zone = tz(user)
        by_day: dict[date, list[Meal]] = {}
        for meal in MealService(self.db).between(user, start, end):
            by_day.setdefault(meal.eaten_at.astimezone(zone).date(), []).append(meal)
        targets = self._all(user, until=end)
        days = []
        for offset in range((end - start).days + 1):
            day = start + timedelta(days=offset)
            valid = [t for t in targets if t.valid_from <= day]
            meals = by_day.get(day, [])
            days.append(
                SummaryDay(
                    date=day,
                    meals=len(meals),
                    totals=totals(item for m in meals for item in m.items),
                    targets=targets_out(valid[-1] if valid else None),
                )
            )
        logged = [d.totals for d in days if d.meals]
        average = None
        if logged:
            fibers = [t.fiber_g for t in logged if t.fiber_g is not None]
            average = Nutrients(
                kcal=round(sum(t.kcal for t in logged) / len(logged), 1),
                protein_g=round(sum(t.protein_g for t in logged) / len(logged), 1),
                carbs_g=round(sum(t.carbs_g for t in logged) / len(logged), 1),
                fat_g=round(sum(t.fat_g for t in logged) / len(logged), 1),
                fiber_g=round(sum(fibers) / len(fibers), 1) if fibers else None,
            )
        return SummaryOut(
            from_date=start, to_date=end, logged_days=len(logged), average=average, days=days
        )
