"""Biblioteca de exercícios: catálogo global do projeto + exercícios próprios de cada usuário.

Visível para um usuário = global ou criado por ele. O exercício de outra pessoa responde
404, igual a um inexistente. O catálogo global é só leitura (403 ao tentar alterar).
"""

import logging
import uuid
from collections.abc import Sequence

from sqlalchemy import exists, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError, FieldValidationError, NotFoundError
from app.modules.exercises import catalog
from app.modules.exercises.models import Exercise, ExerciseMuscle, MuscleRole
from app.modules.exercises.schemas import ExerciseCreate, ExerciseUpdate, MuscleIn
from app.modules.users.models import User

logger = logging.getLogger(__name__)

# Teto de exercícios próprios por usuário (ativos ou arquivados): contra abuso.
MAX_CUSTOM = 200


class ExerciseReadOnlyError(AppError):
    def __init__(self) -> None:
        super().__init__(
            403,
            "exercise_read_only",
            "Exercício do catálogo",
            "Exercícios do catálogo não podem ser alterados. Crie um exercício seu.",
        )


class DuplicateExerciseError(AppError):
    def __init__(self) -> None:
        super().__init__(
            409,
            "exercise_exists",
            "Exercício já existe",
            "Você já tem um exercício com esse nome.",
            errors=[{"field": "name", "message": "Você já tem um exercício com esse nome."}],
        )


class CustomExerciseLimitError(AppError):
    def __init__(self) -> None:
        super().__init__(
            409,
            "exercise_limit",
            "Limite de exercícios",
            f"Você já criou {MAX_CUSTOM} exercícios. Arquive ou reaproveite algum.",
        )


def _visible(user: User):
    return or_(Exercise.owner_user_id.is_(None), Exercise.owner_user_id == user.id)


def _check_muscles(muscles: Sequence[MuscleIn]) -> list[ExerciseMuscle]:
    ids = [m.muscle_group_id for m in muscles]
    if len(set(ids)) != len(ids):
        raise FieldValidationError("muscles", "Cada músculo pode aparecer uma vez só.")
    if not any(m.role is MuscleRole.PRIMARY for m in muscles):
        raise FieldValidationError("muscles", "Escolha pelo menos um músculo principal.")
    return [ExerciseMuscle(muscle_group_id=m.muscle_group_id, role=m.role) for m in muscles]


class ExerciseService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list(
        self,
        user: User,
        *,
        q: str | None = None,
        muscle: str | None = None,
        equipment: Sequence[str] = (),
        mine: bool = False,
        include_archived: bool = False,
    ) -> list[Exercise]:
        query = select(Exercise).where(_visible(user))
        if mine:
            query = query.where(Exercise.owner_user_id == user.id)
        if not include_archived:
            query = query.where(Exercise.is_active.is_(True))
        if q:
            # Cada palavra precisa aparecer no nome, sem diferenciar acentos.
            for word in catalog.search_key(q).split():
                query = query.where(Exercise.search_name.contains(word, autoescape=True))
        if muscle:
            query = query.where(
                exists().where(
                    ExerciseMuscle.exercise_id == Exercise.id,
                    ExerciseMuscle.muscle_group_id == muscle,
                )
            )
        if equipment:
            query = query.where(Exercise.equipment.in_(equipment))
        return list(self.db.scalars(query.order_by(Exercise.search_name, Exercise.id)))

    def get(self, user: User, exercise_id: uuid.UUID) -> Exercise:
        exercise = self.db.scalar(
            select(Exercise).where(Exercise.id == exercise_id, _visible(user))
        )
        if exercise is None:
            raise NotFoundError("Exercício não encontrado.")
        return exercise

    def create(self, user: User, data: ExerciseCreate) -> Exercise:
        muscles = _check_muscles(data.muscles)
        count = self.db.scalar(
            select(func.count()).select_from(Exercise).where(Exercise.owner_user_id == user.id)
        )
        if (count or 0) >= MAX_CUSTOM:
            raise CustomExerciseLimitError
        exercise = Exercise(
            owner_user_id=user.id,
            name=data.name,
            slug=catalog.slugify(data.name),
            search_name=catalog.search_key(data.name),
            instructions=data.instructions or None,
            mechanics=data.mechanics,
            equipment=data.equipment,
            load_type=data.load_type,
            unilateral=data.unilateral,
            is_active=True,
            muscles=muscles,
        )
        self.db.add(exercise)
        self._commit_unique()
        self.db.refresh(exercise)
        logger.info(
            "exercise_created", extra={"user_id": str(user.id), "exercise_id": str(exercise.id)}
        )
        return exercise

    def update(self, user: User, exercise_id: uuid.UUID, data: ExerciseUpdate) -> Exercise:
        exercise = self.get(user, exercise_id)
        if exercise.owner_user_id != user.id:
            raise ExerciseReadOnlyError
        changes = data.model_fields_set
        for name in {"name", "mechanics", "equipment", "load_type", "unilateral", "is_active"}:
            if name in changes and getattr(data, name) is None:
                raise FieldValidationError(name, "Campo obrigatório.")
        if "muscles" in changes:
            if data.muscles is None:
                raise FieldValidationError("muscles", "Campo obrigatório.")
            new_muscles = _check_muscles(data.muscles)
            # Esvazia antes de inserir: a chave (exercício, músculo) pode se repetir.
            exercise.muscles.clear()
            self.db.flush()
            exercise.muscles.extend(new_muscles)

        if data.name is not None:
            exercise.name = data.name
            exercise.slug = catalog.slugify(data.name)
            exercise.search_name = catalog.search_key(data.name)
        if "instructions" in changes:
            exercise.instructions = data.instructions or None
        for name in ("mechanics", "equipment", "load_type", "unilateral", "is_active"):
            value = getattr(data, name)
            if value is not None:
                setattr(exercise, name, value)

        self._commit_unique()
        self.db.refresh(exercise)
        logger.info(
            "exercise_updated",
            extra={
                "user_id": str(user.id),
                "exercise_id": str(exercise.id),
                "fields": sorted(changes),
            },
        )
        return exercise

    def _commit_unique(self) -> None:
        try:
            self.db.commit()
        except IntegrityError as error:
            self.db.rollback()
            if "uq_exercises_owner_slug" in str(error.orig):
                raise DuplicateExerciseError from error
            raise
