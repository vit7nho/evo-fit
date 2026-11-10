from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.errors import FieldValidationError
from app.db.session import get_db
from app.modules.analytics import metrics
from app.modules.analytics.schemas import (
    CompareOut,
    EnduranceModality,
    EnduranceOut,
    MetricCode,
    OverviewOut,
    PeriodValue,
)
from app.modules.analytics.service import AnalyticsService, period, today, weekly_target
from app.modules.auth.dependencies import CurrentUser

router = APIRouter(prefix="/analytics", tags=["análises"])

DbSession = Annotated[Session, Depends(get_db)]
From = Annotated[date | None, Query(alias="from", description="Início (padrão: 30 dias atrás)")]
To = Annotated[date | None, Query(alias="to", description="Fim, inclusive (padrão: hoje)")]


@router.get(
    "/overview",
    response_model=OverviewOut,
    summary="Frequência, consistência, tempo e resumo por modalidade no período",
)
def overview(user: CurrentUser, db: DbSession, start: From = None, end: To = None) -> OverviewOut:
    start, end = period(user, start, end)
    entries = AnalyticsService(db).entries(user, start, end)
    weeks = metrics.weekly(entries, start, end)
    target = weekly_target(user)
    return OverviewOut(
        from_date=start,
        to_date=end,
        days=(end - start).days + 1,
        sessions=len(entries),
        active_days=len({e.day for e in entries}),
        duration_s=sum(e.duration_s for e in entries),
        weekly_target=target,
        consistency=metrics.consistency(weeks, target, today(user)),  # type: ignore[arg-type]
        weeks=weeks,  # type: ignore[arg-type]
        modalities=metrics.by_modality(entries),  # type: ignore[arg-type]
    )


@router.get(
    "/endurance",
    response_model=EnduranceOut,
    summary="Distância, tempo e pace por semana numa modalidade, com a tendência",
)
def endurance(
    modality: EnduranceModality,
    user: CurrentUser,
    db: DbSession,
    start: From = None,
    end: To = None,
) -> EnduranceOut:
    start, end = period(user, start, end)
    entries = AnalyticsService(db).entries(user, start, end, (modality,))
    weeks = metrics.endurance_weeks(entries, modality, start, end)
    measured = [e for e in entries if e.distance_m]
    distance = sum(e.distance_m or 0 for e in measured)
    return EnduranceOut(
        modality=modality,
        from_date=start,
        to_date=end,
        sessions=len(entries),
        duration_s=sum(e.duration_s for e in entries),
        distance_m=distance,
        **metrics.rhythm(modality, distance, sum(e.duration_s for e in measured)),  # type: ignore[arg-type]
        active_weeks=sum(1 for w in weeks if w["sessions"]),
        weeks=weeks,  # type: ignore[arg-type]
        distance_trend=metrics.trend(
            [w["distance_m"] for w in metrics.complete_weeks(weeks, start, end)]
        ),  # type: ignore[arg-type]
    )


@router.get(
    "/compare",
    response_model=CompareOut,
    summary="Compara um indicador entre dois períodos (percentual só com base válida)",
)
def compare(
    metric: MetricCode,
    user: CurrentUser,
    db: DbSession,
    a_from: date,
    a_to: date,
    b_from: date,
    b_to: date,
    modality: EnduranceModality | None = None,
) -> CompareOut:
    spec = metrics.METRICS[metric]
    if spec.needs_modality and modality is None:
        raise FieldValidationError("modality", "Escolha a modalidade para este indicador.")
    if metric == "pace_s_per_km" and modality not in {"run", "walk"}:
        raise FieldValidationError("modality", "Pace por km só para corrida e caminhada.")
    a = period(user, a_from, a_to, start_field="a_from", end_field="a_to")
    b = period(user, b_from, b_to, start_field="b_from", end_field="b_to")
    service = AnalyticsService(db)
    values = [metrics.metric_value(metric, service.entries(user, *p), modality) for p in (a, b)]
    return CompareOut(
        metric=metric,
        label=spec.label,
        modality=modality,
        higher_is_better=spec.higher_is_better,
        a=PeriodValue(from_date=a[0], to_date=a[1], value=values[0]),
        b=PeriodValue(from_date=b[0], to_date=b[1], value=values[1]),
        **metrics.compare(metric, values[0], values[1]),
    )
