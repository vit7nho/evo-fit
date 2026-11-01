import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser
from app.modules.exercises import catalog as exercise_catalog
from app.modules.training import catalog
from app.modules.training.models import WorkoutTemplate
from app.modules.training.schemas import (
    ExerciseRef,
    GroupKindOut,
    GroupOut,
    ItemOut,
    PlannedSet,
    TemplateIn,
    TemplateOrder,
    TemplateOut,
    WorkoutOptions,
)
from app.modules.training.service import TemplateService
from app.modules.users.schemas import Option

router = APIRouter(tags=["fichas"])

DbSession = Annotated[Session, Depends(get_db)]

_MUSCLE_ORDER = {m.id: i for i, m in enumerate(exercise_catalog.MUSCLE_GROUPS)}


def _out(template: WorkoutTemplate) -> TemplateOut:
    group_index = {group.id: i for i, group in enumerate(template.groups)}
    items, muscles, set_count = [], set(), 0
    for item in template.items:
        exercise = item.exercise
        primary = sorted(
            (m.muscle_group_id for m in exercise.muscles if m.role == "primary"),
            key=_MUSCLE_ORDER.__getitem__,
        )
        muscles.update(primary)
        planned = [PlannedSet.model_validate(s) for s in item.planned_sets]
        set_count += sum(1 for s in planned if s.kind != "warmup")
        items.append(
            ItemOut(
                id=item.id,
                exercise=ExerciseRef(
                    id=exercise.id,
                    name=exercise.name,
                    equipment=exercise.equipment,
                    load_type=exercise.load_type,
                    is_active=exercise.is_active,
                    primary_muscles=primary,
                ),
                planned_sets=planned,
                rest_s=item.rest_s,
                notes=item.notes,
                group=None if item.group_id is None else group_index[item.group_id],
            )
        )
    return TemplateOut(
        id=template.id,
        name=template.name,
        notes=template.notes,
        position=template.position,
        groups=[
            GroupOut(id=g.id, kind=g.kind, rest_after_s=g.rest_after_s) for g in template.groups
        ],
        items=items,
        exercise_count=len(items),
        set_count=set_count,
        muscles=sorted(muscles, key=_MUSCLE_ORDER.__getitem__),
        created_at=template.created_at,
        updated_at=template.updated_at,
    )


@router.get(
    "/workout-options",
    response_model=WorkoutOptions,
    summary="Tipos de agrupamento e de série planejada (não exige login)",
)
def workout_options(response: Response) -> WorkoutOptions:
    response.headers["Cache-Control"] = "public, max-age=3600"
    return WorkoutOptions(
        group_kinds=[
            GroupKindOut(
                code=code,
                label=label,
                min_size=catalog.GROUP_SIZES[code][0],
                max_size=catalog.GROUP_SIZES[code][1],
            )
            for code, label in catalog.GROUP_KINDS.items()
        ],
        set_kinds=[Option(code=code, label=label) for code, label in catalog.SET_KINDS.items()],
    )


@router.get(
    "/workout-templates", response_model=list[TemplateOut], summary="Suas fichas, na sua ordem"
)
def list_templates(user: CurrentUser, db: DbSession) -> list[TemplateOut]:
    return [_out(t) for t in TemplateService(db).list(user)]


@router.post(
    "/workout-templates",
    response_model=TemplateOut,
    status_code=status.HTTP_201_CREATED,
    summary="Cria uma ficha (nome, itens e grupos)",
)
def create_template(
    data: TemplateIn, user: CurrentUser, db: DbSession, response: Response
) -> TemplateOut:
    template = TemplateService(db).create(user, data)
    response.headers["Location"] = f"/api/v1/workout-templates/{template.id}"
    return _out(template)


# Antes de "/{template_id}": o caminho literal tem precedência.
@router.put(
    "/workout-templates/order",
    response_model=list[TemplateOut],
    summary="Reordena as fichas (todas, cada uma uma vez)",
)
def reorder_templates(data: TemplateOrder, user: CurrentUser, db: DbSession) -> list[TemplateOut]:
    return [_out(t) for t in TemplateService(db).reorder(user, data.template_ids)]


@router.get("/workout-templates/{template_id}", response_model=TemplateOut, summary="Uma ficha")
def get_template(template_id: uuid.UUID, user: CurrentUser, db: DbSession) -> TemplateOut:
    return _out(TemplateService(db).get(user, template_id))


@router.put(
    "/workout-templates/{template_id}",
    response_model=TemplateOut,
    summary="Regrava a ficha inteira (nome, itens e grupos)",
)
def replace_template(
    template_id: uuid.UUID, data: TemplateIn, user: CurrentUser, db: DbSession
) -> TemplateOut:
    return _out(TemplateService(db).replace(user, template_id, data))


@router.delete(
    "/workout-templates/{template_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Exclui uma ficha",
)
def delete_template(template_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    TemplateService(db).delete(user, template_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
