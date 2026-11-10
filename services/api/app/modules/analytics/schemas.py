from datetime import date
from typing import Literal

from pydantic import BaseModel

EnduranceModality = Literal["run", "walk", "cycle", "swim"]
MetricCode = Literal[
    "sessions",
    "active_days",
    "duration_s",
    "strength_sets",
    "strength_volume_kg",
    "distance_m",
    "pace_s_per_km",
]


class WeekOut(BaseModel):
    week_start: date
    active_days: int
    sessions: int
    duration_s: int


class ConsistencyOut(BaseModel):
    # Semanas que tocam o período (as das pontas podem ser parciais).
    weeks: int
    active_weeks: int
    # Semanas com pelo menos os dias de treino do perfil; nulo sem essa informação.
    weeks_on_target: int | None
    current_streak_weeks: int


class ModalityOut(BaseModel):
    modality: Literal["strength", "run", "walk", "cycle", "swim"]
    sessions: int
    duration_s: int
    # Soma só do que tem distância; nulo quando nenhuma tem (ou na musculação).
    distance_m: int | None
    # Só na musculação.
    sets: int | None
    volume_kg: float | None


class OverviewOut(BaseModel):
    from_date: date
    to_date: date
    days: int
    sessions: int
    active_days: int
    duration_s: int
    # Dias de treino por semana informados no perfil (nulo se não informados).
    weekly_target: int | None
    consistency: ConsistencyOut
    weeks: list[WeekOut]
    modalities: list[ModalityOut]


class EnduranceWeekOut(BaseModel):
    week_start: date
    sessions: int
    duration_s: int
    distance_m: int
    # Ponderados (tempo ÷ distância das atividades com distância); nulos sem distância.
    pace_s_per_km: int | None
    speed_kmh: float | None
    pace_s_per_100m: int | None


class TrendOut(BaseModel):
    # up | down | flat, só com as semanas inteiras do período (a em andamento fica
    # de fora); nulo com menos de 3 delas ou sem distância.
    direction: Literal["up", "down", "flat"] | None
    # Variação da distância semanal, em metros por semana.
    per_week: float | None


class EnduranceOut(BaseModel):
    modality: EnduranceModality
    from_date: date
    to_date: date
    sessions: int
    duration_s: int
    distance_m: int
    pace_s_per_km: int | None
    speed_kmh: float | None
    pace_s_per_100m: int | None
    active_weeks: int
    weeks: list[EnduranceWeekOut]
    distance_trend: TrendOut


class PeriodValue(BaseModel):
    from_date: date
    to_date: date
    value: float | None


class CompareOut(BaseModel):
    metric: MetricCode
    label: str
    modality: EnduranceModality | None
    higher_is_better: bool
    a: PeriodValue
    b: PeriodValue
    # b menos a; percentual sobre a, só quando a > 0.
    difference: float | None
    percent: float | None
    # Qual período foi melhor: a, b ou same (nulo sem valores).
    better: Literal["a", "b", "same"] | None
