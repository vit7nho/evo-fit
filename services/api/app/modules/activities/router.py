import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.activities.models import Activity
from app.modules.activities.schemas import (
    ActivityCreate,
    ActivityOptions,
    ActivityOut,
    ActivityUpdate,
    Modality,
    ModalityOut,
)
from app.modules.activities.service import (
    MODALITIES,
    PAGE_SIZE,
    POOL_LENGTHS_M,
    STROKES,
    ActivityService,
)
from app.modules.auth.dependencies import CurrentUser
from app.modules.users.schemas import Option

router = APIRouter(tags=["atividades"])

DbSession = Annotated[Session, Depends(get_db)]


def _out(activity: Activity) -> ActivityOut:
    swim = activity.swim
    return ActivityOut(
        id=activity.id,
        modality=activity.modality,  # type: ignore[arg-type]
        started_at=activity.started_at,
        ended_at=activity.ended_at,  # type: ignore[arg-type]
        duration_s=activity.duration_s,  # type: ignore[arg-type]
        distance_m=activity.endurance.distance_m if activity.endurance else None,
        perceived_effort=activity.perceived_effort,
        notes=activity.notes,
        indoor=activity.cycling.indoor if activity.cycling else None,
        pool_length_m=swim.pool_length_m if swim else None,
        laps=swim.laps if swim else None,
        stroke=swim.stroke if swim else None,  # type: ignore[arg-type]
        created_at=activity.created_at,
        updated_at=activity.updated_at,
    )


@router.get(
    "/activity-options",
    response_model=ActivityOptions,
    summary="Modalidades, estilos de nado e rótulos (não exige login)",
)
def activity_options(response: Response) -> ActivityOptions:
    response.headers["Cache-Control"] = "public, max-age=3600"
    return ActivityOptions(
        modalities=[
            ModalityOut(code=m.code, label=m.label, max_distance_m=m.max_distance_m)  # type: ignore[arg-type]
            for m in MODALITIES.values()
        ],
        strokes=[Option(code=code, label=label) for code, label in STROKES.items()],
        pool_lengths_m=POOL_LENGTHS_M,
    )


@router.get(
    "/activities",
    response_model=list[ActivityOut],
    summary="Corridas, caminhadas, pedais e nados, mais recentes primeiro",
)
def list_activities(
    user: CurrentUser,
    db: DbSession,
    modality: Modality | None = None,
    before: Annotated[
        datetime | None, Query(description="Só as que começaram antes (próxima página)")
    ] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = PAGE_SIZE,
) -> list[ActivityOut]:
    return [_out(a) for a in ActivityService(db).list(user, modality, before, limit)]


@router.post(
    "/activities",
    response_model=ActivityOut,
    status_code=status.HTTP_201_CREATED,
    summary="Registra uma atividade (musculação vai por /workout-sessions)",
)
def create_activity(
    data: ActivityCreate, user: CurrentUser, db: DbSession, response: Response
) -> ActivityOut:
    activity = ActivityService(db).create(user, data)
    response.headers["Location"] = f"/api/v1/activities/{activity.id}"
    return _out(activity)


@router.get("/activities/{activity_id}", response_model=ActivityOut, summary="Uma atividade")
def get_activity(activity_id: uuid.UUID, user: CurrentUser, db: DbSession) -> ActivityOut:
    return _out(ActivityService(db).get(user, activity_id))


@router.patch(
    "/activities/{activity_id}",
    response_model=ActivityOut,
    summary="Corrige uma atividade (parcial; a modalidade não muda)",
)
def update_activity(
    activity_id: uuid.UUID, data: ActivityUpdate, user: CurrentUser, db: DbSession
) -> ActivityOut:
    return _out(ActivityService(db).update(user, activity_id, data))


@router.delete(
    "/activities/{activity_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Exclui uma atividade",
)
def delete_activity(activity_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    ActivityService(db).delete(user, activity_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
