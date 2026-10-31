import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser
from app.modules.goals import kinds
from app.modules.goals.models import Goal, GoalStatus
from app.modules.goals.schemas import (
    GoalCreate,
    GoalKindOut,
    GoalOptions,
    GoalOut,
    GoalUpdate,
    PriorityOut,
    TargetFieldOut,
)
from app.modules.goals.service import GoalService
from app.modules.users.schemas import Option

router = APIRouter(tags=["metas"])

DbSession = Annotated[Session, Depends(get_db)]

STATUS_LABELS = {
    GoalStatus.ACTIVE: "Ativa",
    GoalStatus.ACHIEVED: "Alcançada",
    GoalStatus.ABANDONED: "Abandonada",
}
PRIORITY_LABELS = {1: "Alta", 2: "Média", 3: "Baixa"}


def _out(goal: Goal) -> GoalOut:
    return GoalOut(
        id=goal.id,
        kind=goal.kind,
        title=goal.title,
        target=goal.target,
        summary=kinds.summarize(goal.kind, goal.target),
        start_date=goal.start_date,
        target_date=goal.target_date,
        status=goal.status,
        priority=goal.priority,
        closed_at=goal.closed_at,
        created_at=goal.created_at,
        updated_at=goal.updated_at,
    )


def _field(spec: kinds.TargetField) -> TargetFieldOut:
    return TargetFieldOut(
        key=spec.key,
        label=spec.label,
        type=spec.type,
        required=spec.required,
        min=spec.min,
        max=spec.max,
        step=spec.step,
        unit=spec.unit,
        options=(
            [Option(code=c, label=label) for c, label in spec.options.items()]
            if spec.options
            else None
        ),
    )


@router.get(
    "/goal-options",
    response_model=GoalOptions,
    summary="Tipos de meta, campos do alvo de cada um e rótulos (não exige login)",
)
def goal_options(response: Response) -> GoalOptions:
    response.headers["Cache-Control"] = "public, max-age=3600"
    return GoalOptions(
        kinds=[
            GoalKindOut(
                code=k.code,
                label=k.label,
                description=k.description,
                health_data=k.health_data,
                fields=[_field(f) for f in k.fields],
            )
            for k in kinds.KINDS.values()
        ],
        statuses=[Option(code=s.value, label=label) for s, label in STATUS_LABELS.items()],
        priorities=[PriorityOut(value=v, label=label) for v, label in PRIORITY_LABELS.items()],
    )


@router.get("/goals", response_model=list[GoalOut], summary="Metas do usuário (ativas primeiro)")
def list_goals(user: CurrentUser, db: DbSession, status: GoalStatus | None = None) -> list[GoalOut]:
    return [_out(g) for g in GoalService(db).list(user, status)]


@router.post(
    "/goals",
    response_model=GoalOut,
    status_code=status.HTTP_201_CREATED,
    summary="Cria uma meta. Metas de peso exigem o consentimento health_data",
)
def create_goal(data: GoalCreate, user: CurrentUser, db: DbSession, response: Response) -> GoalOut:
    goal = GoalService(db).create(user, data)
    response.headers["Location"] = f"/api/v1/goals/{goal.id}"
    return _out(goal)


@router.get("/goals/{goal_id}", response_model=GoalOut, summary="Uma meta")
def get_goal(goal_id: uuid.UUID, user: CurrentUser, db: DbSession) -> GoalOut:
    return _out(GoalService(db).get(user, goal_id))


@router.patch(
    "/goals/{goal_id}",
    response_model=GoalOut,
    summary="Atualiza uma meta (parcial), inclusive o status",
)
def update_goal(goal_id: uuid.UUID, data: GoalUpdate, user: CurrentUser, db: DbSession) -> GoalOut:
    return _out(GoalService(db).update(user, goal_id, data))


@router.delete(
    "/goals/{goal_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Exclui uma meta"
)
def delete_goal(goal_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    GoalService(db).delete(user, goal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
