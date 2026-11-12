"""Painel do Início (3.8): um pedido com o que importa para o objetivo da pessoa.

Só leitura e só com os registros do dono do token. Reaproveita o motor de análise
(entradas, estímulo), as metas e os planos; as decisões de conteúdo e de ordem ficam
em `rules`.
"""

from collections import Counter
from datetime import UTC, date, datetime, time, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.activities.models import Activity, EnduranceDetails
from app.modules.analytics import metrics, stimulus
from app.modules.analytics.metrics import STRENGTH, Entry, week_start
from app.modules.analytics.service import (
    AnalyticsService,
    MethodologyUnavailableError,
    today,
    tz,
    weekly_target,
)
from app.modules.auth.dependencies import CurrentUser
from app.modules.dashboard import rules
from app.modules.dashboard.schemas import (
    BodyFocusOut,
    DashboardOut,
    EnduranceFocusOut,
    FocusOut,
    GoalCardOut,
    LastRecordOut,
    LeastMuscleOut,
    NextPlanSessionOut,
    PlanFocusOut,
    ProgressOut,
    StrengthFocusOut,
    WeekOut,
)
from app.modules.exercises.catalog import search_key
from app.modules.exercises.models import Exercise
from app.modules.goals import kinds
from app.modules.goals.models import Goal, GoalStatus
from app.modules.goals.service import GoalService
from app.modules.plans.models import TrainingPlan
from app.modules.plans.service import PlanService, is_done
from app.modules.plans.templates import TEMPLATES, describe, session_seconds
from app.modules.sessions.models import SessionExercise, SetEntry, WorkoutSession
from app.modules.users.models import User
from app.modules.users.vocabulary import OBJECTIVES

router = APIRouter(tags=["painel"])

DbSession = Annotated[Session, Depends(get_db)]

# Semanas olhadas para trás (a sequência de semanas ativas e os 30 dias cabem nelas).
HISTORY_WEEKS = 26
GOALS_SHOWN = 3
LEAST_SHOWN = 4


def _today(user: User) -> date:
    """Hoje no fuso do perfil (separado para os testes fixarem a data)."""
    return today(user)


def _between(entries: list[Entry], first: date, last: date) -> list[Entry]:
    return [e for e in entries if first <= e.day <= last]


def _lower(user: User, day: date) -> datetime:
    return datetime.combine(day, time.min, tz(user)).astimezone(UTC)


def _week(entries: list[Entry], day: date, user: User) -> WeekOut:
    monday = week_start(day)
    current = _between(entries, monday, day)
    previous = _between(entries, monday - timedelta(days=7), monday - timedelta(days=1))
    weeks = metrics.weekly(entries, monday - timedelta(weeks=HISTORY_WEEKS - 1), day)
    return WeekOut(
        from_date=monday,
        to_date=day,
        sessions=len(current),
        active_days=len({e.day for e in current}),
        duration_s=sum(e.duration_s for e in current),
        weekly_target=weekly_target(user),
        previous_sessions=len(previous),
        previous_active_days=len({e.day for e in previous}),
        streak_weeks=metrics.consistency(weeks, None, day)["current_streak_weeks"],  # type: ignore[arg-type]
    )


def _strength(last: list[Entry], before: list[Entry]) -> StrengthFocusOut:
    mine = [e for e in last if e.modality == STRENGTH]
    old = [e for e in before if e.modality == STRENGTH]
    return StrengthFocusOut(
        sessions=len(mine),
        sets=sum(e.sets for e in mine),
        volume_kg=round(sum(e.volume_kg for e in mine), 2),
        previous_sets=sum(e.sets for e in old),
        previous_volume_kg=round(sum(e.volume_kg for e in old), 2),
    )


def _endurance(modality: str, last: list[Entry], before: list[Entry]) -> EnduranceFocusOut:
    mine = [e for e in last if e.modality == modality]
    measured = [e for e in mine if e.distance_m]
    distance = sum(e.distance_m or 0 for e in measured)
    return EnduranceFocusOut(
        modality=modality,  # type: ignore[arg-type]
        sessions=len(mine),
        duration_s=sum(e.duration_s for e in mine),
        distance_m=distance,
        previous_distance_m=sum(e.distance_m or 0 for e in before if e.modality == modality),
        **metrics.rhythm(modality, distance, sum(e.duration_s for e in measured)),  # type: ignore[arg-type]
    )


def _body(analytics: AnalyticsService, user: User, day: date) -> BodyFocusOut | None:
    try:
        methodology = analytics.methodology()
    except MethodologyUnavailableError:
        return None
    days = 30
    data = analytics.stimulus(user, day - timedelta(days=days - 1), day)
    groups = analytics.muscles()
    rows = {
        r.muscle_id: r
        for r in stimulus.muscle_stimulus(
            data.sets, data.refs, [g.id for g in groups], methodology.config, days
        )
    }
    lowest = min((r.weighted_sets_per_week for r in rows.values()), default=0)
    return BodyFocusOut(
        methodology_version=methodology.version,
        period_days=days,
        least=[
            LeastMuscleOut(
                muscle_id=g.id,
                name=g.name_pt,
                weighted_sets_per_week=rows[g.id].weighted_sets_per_week,
            )
            for g in groups
            if rows[g.id].weighted_sets_per_week == lowest
        ][:LEAST_SHOWN],
        untrained=sum(1 for r in rows.values() if r.weighted_sets == 0),
    )


def _plan(plan: TrainingPlan) -> PlanFocusOut:
    template = TEMPLATES[plan.kind]
    nxt = next((s for s in plan.sessions if not is_done(s)), None)
    weeks = max((s.week for s in plan.sessions), default=0)
    return PlanFocusOut(
        id=plan.id,
        kind=plan.kind,
        title=template.title,
        modality=template.modality,
        current_week=nxt.week if nxt else weeks,
        weeks=weeks,
        completed_sessions=sum(1 for s in plan.sessions if is_done(s)),
        total_sessions=len(plan.sessions),
        next_session=NextPlanSessionOut(
            id=nxt.id,
            week=nxt.week,
            scheduled_date=nxt.scheduled_date,
            summary=describe(nxt.prescription),
            total_s=session_seconds(nxt.prescription),
        )
        if nxt
        else None,
    )


class _GoalFacts:
    """Busca, sob demanda, os fatos que cada tipo de meta usa."""

    def __init__(self, db: Session, analytics: AnalyticsService, user: User, day: date) -> None:
        self.db, self.analytics, self.user, self.day = db, analytics, user, day
        self._weekly_sets: dict[str, float] | None = None

    def for_goal(self, goal: Goal, week: list[Entry]) -> rules.GoalFacts:
        t = goal.target
        since = _lower(self.user, goal.start_date)
        match goal.kind:
            case "strength":
                return rules.GoalFacts(best_load_kg=self._best_load(t, since))
            case "hypertrophy":
                return rules.GoalFacts(weekly_sets=self._sets_per_week().get(t["muscle_group"]))
            case "run_distance":
                longest = self.db.scalar(self._runs(func.max(EnduranceDetails.distance_m), since))
                return rules.GoalFacts(longest_run_m=longest)
            case "run_time":
                meters = round(float(t["distance_km"]) * 1000)
                pace = self.db.scalar(
                    self._runs(
                        func.min(Activity.duration_s * 1000.0 / EnduranceDetails.distance_m),
                        since,
                    ).where(EnduranceDetails.distance_m >= meters, Activity.duration_s > 0)
                )
                return rules.GoalFacts(best_pace_s_per_km=None if pace is None else float(pace))
            case "frequency":
                modality = t.get("modality")
                return rules.GoalFacts(
                    week_sessions=sum(1 for e in week if modality in (None, e.modality))
                )
        return rules.GoalFacts()

    def _runs(self, column, since: datetime):
        """[column] sobre as corridas com distância da pessoa desde [since]."""
        return (
            select(column)
            .select_from(Activity)
            .join(EnduranceDetails, EnduranceDetails.activity_id == Activity.id)
            .where(
                Activity.user_id == self.user.id,
                Activity.modality == "run",
                Activity.deleted_at.is_(None),
                Activity.started_at >= since,
                EnduranceDetails.distance_m.is_not(None),
            )
        )

    def _best_load(self, target: dict, since: datetime) -> float | None:
        # O exercício da meta é texto: casa pelo nome (sem acentos e maiúsculas) com
        # um exercício do catálogo ou da própria pessoa.
        ids = select(Exercise.id).where(
            Exercise.search_name == search_key(target["exercise"]),
            (Exercise.owner_user_id.is_(None)) | (Exercise.owner_user_id == self.user.id),
        )
        best = self.db.scalar(
            select(func.max(SetEntry.load_kg))
            .join(SessionExercise, SessionExercise.id == SetEntry.session_exercise_id)
            .join(WorkoutSession, WorkoutSession.id == SessionExercise.session_id)
            .join(Activity, Activity.id == WorkoutSession.activity_id)
            .where(
                WorkoutSession.user_id == self.user.id,
                WorkoutSession.status == "completed",
                Activity.deleted_at.is_(None),
                Activity.started_at >= since,
                SessionExercise.exercise_id.in_(ids),
                SetEntry.kind != "warmup",
                SetEntry.reps >= target["reps"],
            )
        )
        return None if best is None else float(best)

    def _sets_per_week(self) -> dict[str, float]:
        if self._weekly_sets is None:
            try:
                config = self.analytics.methodology().config
            except MethodologyUnavailableError:
                self._weekly_sets = {}
                return self._weekly_sets
            days = 28
            data = self.analytics.stimulus(self.user, self.day - timedelta(days=days - 1), self.day)
            groups = [g.id for g in self.analytics.muscles()]
            self._weekly_sets = {
                r.muscle_id: r.weighted_sets_per_week
                for r in stimulus.muscle_stimulus(data.sets, data.refs, groups, config, days)
            }
        return self._weekly_sets


def _goal(goal: Goal, facts: rules.GoalFacts) -> GoalCardOut:
    measured = rules.progress(goal.kind, goal.target, facts, goal.start_date)
    return GoalCardOut(
        id=goal.id,
        kind=goal.kind,
        title=goal.title,
        summary=kinds.summarize(goal.kind, goal.target),
        target_date=goal.target_date,
        priority=goal.priority,
        progress=None
        if measured is None
        else ProgressOut(
            current=measured.current,
            target=measured.target,
            unit=measured.unit,  # type: ignore[arg-type]
            ratio=measured.ratio,
            achieved=measured.achieved,
            lower_is_better=measured.lower_is_better,
            basis=measured.basis,
        ),
    )


def _last_record(entries: list[Entry]) -> LastRecordOut | None:
    dated = [e for e in entries if e.started_at is not None]
    if not dated:
        return None
    last = max(dated, key=lambda e: e.started_at)  # type: ignore[arg-type,return-value]
    strength = last.modality == STRENGTH
    return LastRecordOut(
        modality=last.modality,  # type: ignore[arg-type]
        title=last.title,
        day=last.day,
        duration_s=last.duration_s,
        distance_m=last.distance_m,
        sets=last.sets if strength else None,
        volume_kg=round(last.volume_kg, 2) if strength else None,
    )


@router.get(
    "/dashboard",
    response_model=DashboardOut,
    summary="Painel do Início: semana, foco pelo objetivo, metas com progresso e último registro",
)
def dashboard(user: CurrentUser, db: DbSession) -> DashboardOut:
    day = _today(user)
    analytics = AnalyticsService(db)
    first = week_start(day) - timedelta(weeks=HISTORY_WEEKS - 1)
    entries = analytics.entries(user, first, day)

    last7 = _between(entries, day - timedelta(days=6), day)
    before7 = _between(entries, day - timedelta(days=13), day - timedelta(days=7))
    recorded = Counter(e.modality for e in _between(entries, day - timedelta(days=29), day))
    profile = user.profile
    objective = profile.primary_objective if profile else None
    plan = next((p for p in PlanService(db).list(user) if p.status == "active"), None)

    focus: list[FocusOut] = []
    for card in rules.focus_order(
        objective,
        list(profile.preferred_modalities or []) if profile else [],
        dict(recorded),
        plan is not None,
    ):
        match card.split(":"):
            case ["strength"]:
                focus.append(FocusOut(kind="strength", strength=_strength(last7, before7)))
            case ["body"]:
                if (body := _body(analytics, user, day)) is not None:
                    focus.append(FocusOut(kind="body", body=body))
            case ["endurance", modality]:
                focus.append(
                    FocusOut(kind="endurance", endurance=_endurance(modality, last7, before7))
                )
            case ["plan"] if plan is not None:
                focus.append(FocusOut(kind="plan", plan=_plan(plan)))

    week = _week(entries, day, user)
    this_week = _between(entries, week.from_date, day)
    active = GoalService(db).list(user, GoalStatus.ACTIVE)
    facts = _GoalFacts(db, analytics, user, day)
    return DashboardOut(
        objective=objective,
        objective_label=OBJECTIVES.get(objective) if objective else None,
        today=day,
        week=week,
        focus=focus,
        goals=[_goal(g, facts.for_goal(g, this_week)) for g in active[:GOALS_SHOWN]],
        active_goals=len(active),
        last_record=_last_record(entries),
    )
