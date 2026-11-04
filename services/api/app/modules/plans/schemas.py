import uuid
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

PlanKind = Literal["walk_habit", "run_5k", "run_10k"]
PlanStatus = Literal["active", "completed", "ended"]
Weekday = Annotated[int, Field(ge=0, le=6)]


class PlanCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: PlanKind
    # Exatamente 3 dias (0 = segunda … 6 = domingo); na corrida, sem dias seguidos.
    weekdays: list[Weekday]
    # Padrão: hoje no fuso do perfil; até 4 semanas à frente.
    start_date: date | None = None


class SessionActivity(BaseModel):
    model_config = ConfigDict(extra="forbid")

    activity_id: uuid.UUID


class PlanStep(BaseModel):
    type: Literal["walk", "run"]
    s: int
    effort: Literal["easy", "steady"] | None = None
    # Distância-alvo (a sessão final do 5 km e do 10 km).
    m: int | None = None


class PlanBlock(BaseModel):
    """Um passo, ou `repeat` vezes os `steps`."""

    type: Literal["walk", "run"] | None = None
    s: int | None = None
    effort: Literal["easy", "steady"] | None = None
    m: int | None = None
    repeat: int | None = None
    steps: list[PlanStep] | None = None


class PlanSessionOut(BaseModel):
    id: uuid.UUID
    position: int
    week: int
    day_index: int
    scheduled_date: date
    blocks: list[PlanBlock]
    # Duração prevista, com aquecimento e volta à calma.
    total_s: int
    summary: str
    # Nulo também quando a atividade ligada foi excluída.
    completed_activity_id: uuid.UUID | None
    completed_at: datetime | None


class PlanSummaryOut(BaseModel):
    id: uuid.UUID
    kind: PlanKind
    title: str
    modality: Literal["walk", "run"]
    template_version: int
    status: PlanStatus
    start_date: date
    weekdays: list[int]
    weeks: int
    # A semana da próxima sessão (a última, quando não há próxima).
    current_week: int
    total_sessions: int
    completed_sessions: int
    # A primeira sessão não feita (a ordem vale mais que a data sugerida).
    next_session_id: uuid.UUID | None
    # Os ajustes feitos para a pessoa, em texto.
    adaptations: list[str]
    created_at: datetime
    ended_at: datetime | None


class PlanOut(PlanSummaryOut):
    sessions: list[PlanSessionOut]


class PlanTemplateOut(BaseModel):
    kind: PlanKind
    version: int
    title: str
    summary: str
    modality: Literal["walk", "run"]
    prerequisite: str | None
    sessions_per_week: int
    # Já com os ajustes para a pessoa (semanas repetidas, por exemplo).
    weeks: int
    adaptations: list[str]
    # Aviso quando o histórico sugere outro plano antes (não impede de começar).
    note: str | None
