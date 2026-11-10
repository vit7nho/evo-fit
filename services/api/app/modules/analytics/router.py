from datetime import date, timedelta
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.errors import FieldValidationError, NotFoundError
from app.db.session import get_db
from app.modules.analytics import metrics, stimulus
from app.modules.analytics.schemas import (
    CompareOut,
    EnduranceModality,
    EnduranceOut,
    LoadPointOut,
    MetricCode,
    MuscleDetailOut,
    MuscleExerciseOut,
    MuscleOut,
    MusclesOut,
    OverviewOut,
    PeriodValue,
    PreviousOut,
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


# --- estímulo muscular (3.5) ---

NOTICE = (
    "Referência geral de volume registrado (séries ponderadas por semana), "
    "não diagnóstico nem prescrição."
)


def _muscle_out(row: stimulus.MuscleStimulus, group) -> MuscleOut:
    return MuscleOut(
        muscle_id=row.muscle_id,
        name=group.name_pt,
        view=group.view,
        weighted_sets=row.weighted_sets,
        weighted_sets_per_week=row.weighted_sets_per_week,
        band=row.band,  # type: ignore[arg-type]
        frequency=row.frequency,
        volume_load_kg=row.volume_load_kg,
    )


def _stimulus(service: AnalyticsService, user, start: date, end: date, config: dict):
    data = service.stimulus(user, start, end)
    groups = service.muscles()
    rows = stimulus.muscle_stimulus(
        data.sets, data.refs, [g.id for g in groups], config, (end - start).days + 1
    )
    return data, groups, {r.muscle_id: r for r in rows}


@router.get(
    "/muscles",
    response_model=MusclesOut,
    summary="Meu Corpo: séries ponderadas por semana e faixa de cada músculo no período",
)
def muscles(user: CurrentUser, db: DbSession, start: From = None, end: To = None) -> MusclesOut:
    start, end = period(user, start, end)
    service = AnalyticsService(db)
    methodology = service.methodology()
    _, groups, rows = _stimulus(service, user, start, end, methodology.config)
    return MusclesOut(
        methodology_version=methodology.version,
        from_date=start,
        to_date=end,
        period_days=(end - start).days + 1,
        bands=methodology.config["bands_weekly_sets"],
        notice=NOTICE,
        muscles=[_muscle_out(rows[g.id], g) for g in groups],
    )


@router.get(
    "/muscles/{muscle_id}",
    response_model=MuscleDetailOut,
    summary="Detalhe de um músculo: exercícios, evolução das cargas e comparação",
)
def muscle_detail(
    muscle_id: str,
    user: CurrentUser,
    db: DbSession,
    start: From = None,
    end: To = None,
    compare: Literal["previous"] | None = None,
) -> MuscleDetailOut:
    start, end = period(user, start, end)
    service = AnalyticsService(db)
    methodology = service.methodology()
    data, groups, rows = _stimulus(service, user, start, end, methodology.config)
    group = next((g for g in groups if g.id == muscle_id), None)
    if group is None:
        raise NotFoundError("Músculo não encontrado.")
    row = rows[muscle_id]

    values = stimulus.set_values(data.sets, methodology.config)
    exercises = []
    loads: dict[tuple[date, str], float] = {}
    for exercise_id, weighted in sorted(row.exercises.items(), key=lambda kv: -kv[1]):
        exercise = data.exercises[exercise_id]
        role = next(r.role for r in data.refs[exercise_id] if r.muscle_id == muscle_id)
        mine = [s for s in data.sets if s.exercise_id == exercise_id and s.kind != "warmup"]
        external = exercise.load_type == "external"
        loaded = [s for s in mine if external and s.load_kg]
        for s in loaded:
            key = (s.day, str(exercise_id))
            loads[key] = max(loads.get(key, 0.0), s.load_kg or 0.0)
        exercises.append(
            MuscleExerciseOut(
                exercise_id=str(exercise_id),
                name=exercise.name,
                role=role,  # type: ignore[arg-type]
                weighted_sets=weighted,
                sets=sum(1 for s in mine if s.parent_set_id is None and values[s.id] > 0),
                best_load_kg=max((s.load_kg or 0.0 for s in loaded), default=None),
            )
        )

    previous = None
    if compare == "previous":
        days = (end - start).days + 1
        p_end = start - timedelta(days=1)
        p_start = p_end - timedelta(days=days - 1)
        _, _, before = _stimulus(service, user, p_start, p_end, methodology.config)
        old = before[muscle_id]
        diff = metrics.compare("duration_s", old.weighted_sets_per_week, row.weighted_sets_per_week)
        previous = PreviousOut(
            from_date=p_start,
            to_date=p_end,
            weighted_sets_per_week=old.weighted_sets_per_week,
            frequency=old.frequency,
            band=old.band,  # type: ignore[arg-type]
            difference=diff["difference"],
            percent=diff["percent"],
        )

    return MuscleDetailOut(
        methodology_version=methodology.version,
        from_date=start,
        to_date=end,
        period_days=(end - start).days + 1,
        notice=NOTICE,
        muscle=_muscle_out(row, group),
        exercises=exercises,
        loads=[
            LoadPointOut(day=day, exercise_id=exercise_id, best_load_kg=load)
            for (day, exercise_id), load in sorted(loads.items())
        ],
        previous=previous,
    )
