import uuid
from datetime import date
from typing import Literal

from pydantic import BaseModel


class WeekOut(BaseModel):
    """Semana em curso: de segunda até hoje (fuso do perfil)."""

    from_date: date
    to_date: date
    sessions: int
    active_days: int
    duration_s: int
    # Dias de treino por semana do perfil; nulo sem essa informação.
    weekly_target: int | None
    # A semana anterior inteira (segunda a domingo), para comparar.
    previous_sessions: int
    previous_active_days: int
    # Semanas ativas seguidas até agora (a em curso ainda vazia não quebra).
    streak_weeks: int


class StrengthFocusOut(BaseModel):
    """Últimos 7 dias contra os 7 anteriores."""

    sessions: int
    sets: int
    volume_kg: float
    previous_sets: int
    previous_volume_kg: float


class EnduranceFocusOut(BaseModel):
    """Últimos 7 dias contra os 7 anteriores; ritmo nulo sem distância."""

    modality: Literal["run", "walk", "cycle", "swim"]
    sessions: int
    duration_s: int
    distance_m: int
    previous_distance_m: int
    pace_s_per_km: int | None
    speed_kmh: float | None
    pace_s_per_100m: int | None


class LeastMuscleOut(BaseModel):
    muscle_id: str
    name: str
    weighted_sets_per_week: float


class BodyFocusOut(BaseModel):
    """Meu Corpo nos últimos 30 dias: os de menor estímulo."""

    methodology_version: str
    period_days: int
    # Os músculos com o menor valor (todos os empatados, até 4).
    least: list[LeastMuscleOut]
    # Quantos dos 13 ficaram sem nenhuma série.
    untrained: int


class NextPlanSessionOut(BaseModel):
    id: uuid.UUID
    week: int
    scheduled_date: date
    summary: str
    total_s: int


class PlanFocusOut(BaseModel):
    id: uuid.UUID
    kind: str
    title: str
    modality: str
    current_week: int
    weeks: int
    completed_sessions: int
    total_sessions: int
    next_session: NextPlanSessionOut | None


class FocusOut(BaseModel):
    """Um cartão do foco; só o campo do tipo vem preenchido."""

    kind: Literal["strength", "body", "endurance", "plan"]
    strength: StrengthFocusOut | None = None
    body: BodyFocusOut | None = None
    endurance: EnduranceFocusOut | None = None
    plan: PlanFocusOut | None = None


class ProgressOut(BaseModel):
    # Nulo quando ainda não há registro que meça a meta (nunca um zero inventado).
    current: float | None
    target: float
    unit: Literal["kg", "km", "s", "sets_per_week", "sessions"]
    # 0 a 1 (1 = atingido); nulo sem valor medido.
    ratio: float | None
    achieved: bool
    # No tempo de corrida, menor é melhor.
    lower_is_better: bool
    # De onde vem o número, em texto (ex.: "corrida mais longa desde 01/10/2026").
    basis: str


class GoalCardOut(BaseModel):
    id: uuid.UUID
    kind: str
    title: str
    summary: str
    target_date: date | None
    priority: int
    # Nulo nos tipos que os registros não medem (peso, hábito, livre).
    progress: ProgressOut | None


class LastRecordOut(BaseModel):
    modality: Literal["strength", "run", "walk", "cycle", "swim"]
    # Nome do treino na musculação; nulo nas atividades.
    title: str | None
    day: date
    duration_s: int
    distance_m: int | None
    sets: int | None
    volume_kg: float | None


class DashboardOut(BaseModel):
    objective: str | None
    objective_label: str | None
    today: date
    week: WeekOut
    focus: list[FocusOut]
    # As 3 primeiras metas ativas (prioridade, prazo) e o total delas.
    goals: list[GoalCardOut]
    active_goals: int
    last_record: LastRecordOut | None
