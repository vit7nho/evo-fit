import uuid
from collections.abc import Mapping
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser
from app.modules.exercises import catalog
from app.modules.exercises.models import Exercise
from app.modules.exercises.schemas import (
    ExerciseCreate,
    ExerciseOptions,
    ExerciseOut,
    ExerciseUpdate,
    MuscleGroupOut,
    MuscleOut,
)
from app.modules.exercises.seed import catalog_images
from app.modules.exercises.service import ExerciseService
from app.modules.users.schemas import Option

router = APIRouter(tags=["exercícios"])

DbSession = Annotated[Session, Depends(get_db)]

_MUSCLE_ORDER = {m.id: i for i, m in enumerate(catalog.MUSCLE_GROUPS)}


def _out(exercise: Exercise, user_id: uuid.UUID) -> ExerciseOut:
    return ExerciseOut(
        id=exercise.id,
        name=exercise.name,
        instructions=exercise.instructions,
        mechanics=exercise.mechanics,
        equipment=exercise.equipment,
        load_type=exercise.load_type,
        unilateral=exercise.unilateral,
        is_custom=exercise.owner_user_id == user_id,
        is_active=exercise.is_active,
        images=catalog_images(exercise.slug) if exercise.owner_user_id is None else [],
        # Principais primeiro; dentro de cada papel, a ordem do catálogo (não a alfabética).
        muscles=[
            MuscleOut(
                id=m.muscle_group_id, name=catalog.MUSCLE_NAMES[m.muscle_group_id], role=m.role
            )
            for m in sorted(
                exercise.muscles,
                key=lambda m: (m.role != "primary", _MUSCLE_ORDER[m.muscle_group_id]),
            )
        ],
    )


def _options(source: Mapping[str, str]) -> list[Option]:
    return [Option(code=code, label=label) for code, label in source.items()]


def _muscle_groups() -> list[MuscleGroupOut]:
    return [
        MuscleGroupOut(id=m.id, name=m.name, body_region=m.body_region, view=m.view)
        for m in catalog.MUSCLE_GROUPS
    ]


@router.get(
    "/muscle-groups",
    response_model=list[MuscleGroupOut],
    summary="Grupos musculares (ids estáveis; não exige login)",
)
def muscle_groups(response: Response) -> list[MuscleGroupOut]:
    response.headers["Cache-Control"] = "public, max-age=3600"
    return _muscle_groups()


@router.get(
    "/exercise-options",
    response_model=ExerciseOptions,
    summary="Grupos musculares, equipamentos, mecânicas e tipos de carga (não exige login)",
)
def exercise_options(response: Response) -> ExerciseOptions:
    response.headers["Cache-Control"] = "public, max-age=3600"
    return ExerciseOptions(
        muscle_groups=_muscle_groups(),
        equipment=_options(catalog.EQUIPMENT),
        mechanics=_options(catalog.MECHANICS),
        load_types=_options(catalog.LOAD_TYPES),
    )


@router.get(
    "/exercises",
    response_model=list[ExerciseOut],
    summary="Biblioteca: catálogo do projeto + seus exercícios, em ordem alfabética",
)
def list_exercises(
    user: CurrentUser,
    db: DbSession,
    q: Annotated[str | None, Query(max_length=80, description="Palavras do nome")] = None,
    muscle: Annotated[str | None, Query(description="Id do grupo muscular")] = None,
    equipment: Annotated[list[str] | None, Query(description="Um ou mais equipamentos")] = None,
    mine: Annotated[bool, Query(description="Só os seus")] = False,
    include_archived: Annotated[bool, Query(description="Inclui os seus arquivados")] = False,
) -> list[ExerciseOut]:
    exercises = ExerciseService(db).list(
        user,
        q=q,
        muscle=muscle,
        equipment=equipment or (),
        mine=mine,
        include_archived=include_archived,
    )
    return [_out(e, user.id) for e in exercises]


@router.post(
    "/exercises",
    response_model=ExerciseOut,
    status_code=status.HTTP_201_CREATED,
    summary="Cria um exercício seu",
)
def create_exercise(
    data: ExerciseCreate, user: CurrentUser, db: DbSession, response: Response
) -> ExerciseOut:
    exercise = ExerciseService(db).create(user, data)
    response.headers["Location"] = f"/api/v1/exercises/{exercise.id}"
    return _out(exercise, user.id)


@router.get("/exercises/{exercise_id}", response_model=ExerciseOut, summary="Um exercício")
def get_exercise(exercise_id: uuid.UUID, user: CurrentUser, db: DbSession) -> ExerciseOut:
    return _out(ExerciseService(db).get(user, exercise_id), user.id)


@router.patch(
    "/exercises/{exercise_id}",
    response_model=ExerciseOut,
    summary="Atualiza um exercício seu (parcial); is_active=false arquiva",
)
def update_exercise(
    exercise_id: uuid.UUID, data: ExerciseUpdate, user: CurrentUser, db: DbSession
) -> ExerciseOut:
    return _out(ExerciseService(db).update(user, exercise_id, data), user.id)
