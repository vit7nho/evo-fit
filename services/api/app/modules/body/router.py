import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.analytics.service import tz
from app.modules.auth.dependencies import CurrentUser
from app.modules.body.models import BodyMeasurement
from app.modules.body.schemas import (
    MeasurementIn,
    MeasurementOut,
    MeasurementUpdate,
    Metric,
    MetricInfo,
    TrendOut,
)
from app.modules.body.service import MeasurementService, metric_infos, period
from app.modules.users.models import User

router = APIRouter(tags=["corpo"])

DbSession = Annotated[Session, Depends(get_db)]
From = Annotated[date | None, Query(alias="from")]
To = Annotated[date | None, Query(alias="to")]


def measurement_out(found: BodyMeasurement, user: User) -> MeasurementOut:
    return MeasurementOut(
        id=found.id,
        measured_at=found.measured_at,
        local_time=found.measured_at.astimezone(tz(user)).replace(tzinfo=None),
        weight_kg=found.weight_kg,
        body_fat_pct=found.body_fat_pct,
        waist_cm=found.waist_cm,
        hip_cm=found.hip_cm,
        chest_cm=found.chest_cm,
        arm_cm=found.arm_cm,
        thigh_cm=found.thigh_cm,
        calf_cm=found.calf_cm,
        notes=found.notes,
    )


@router.get("/body-measurement-options", summary="As medidas, unidades e limites (público)")
def options() -> list[MetricInfo]:
    return metric_infos()


@router.get("/body-measurements", summary="Medidas do período (mais novas antes); padrão 90 dias")
def list_measurements(
    user: CurrentUser, db: DbSession, start: From = None, end: To = None
) -> list[MeasurementOut]:
    first, last = period(user, start, end)
    return [measurement_out(m, user) for m in MeasurementService(db).list(user, first, last)]


@router.post(
    "/body-measurements",
    status_code=status.HTTP_201_CREATED,
    summary="Registra peso e/ou medidas (exige o consentimento health_data)",
)
def create_measurement(data: MeasurementIn, user: CurrentUser, db: DbSession) -> MeasurementOut:
    return measurement_out(MeasurementService(db).create(user, data), user)


@router.get(
    "/body-measurements/trend",
    summary="Tendência de uma medida: um ponto por dia, média de 7 dias e ritmo por semana",
)
def trend(
    user: CurrentUser,
    db: DbSession,
    metric: Metric = "weight_kg",
    start: From = None,
    end: To = None,
) -> TrendOut:
    first, last = period(user, start, end)
    return MeasurementService(db).trend(user, metric, first, last)


@router.get("/body-measurements/{measurement_id}", summary="Uma medida")
def get_measurement(measurement_id: uuid.UUID, user: CurrentUser, db: DbSession) -> MeasurementOut:
    return measurement_out(MeasurementService(db).get(user, measurement_id), user)


@router.patch("/body-measurements/{measurement_id}", summary="Altera uma medida")
def update_measurement(
    measurement_id: uuid.UUID, data: MeasurementUpdate, user: CurrentUser, db: DbSession
) -> MeasurementOut:
    return measurement_out(MeasurementService(db).update(user, measurement_id, data), user)


@router.delete(
    "/body-measurements/{measurement_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Apaga"
)
def delete_measurement(measurement_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    MeasurementService(db).delete(user, measurement_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
