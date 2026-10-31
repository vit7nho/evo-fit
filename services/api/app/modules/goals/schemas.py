import uuid
from datetime import date, datetime
from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.modules.goals.models import GoalStatus
from app.modules.users.schemas import Option

Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=80)]
Priority = Annotated[int, Field(ge=1, le=3)]


class GoalCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: str
    title: Title
    target: dict[str, Any]
    # Sem data de início, vale o dia de hoje no fuso do perfil.
    start_date: date | None = None
    target_date: date | None = None
    priority: Priority = 2


class GoalUpdate(BaseModel):
    """Atualização parcial. O tipo não muda: para outro tipo, crie outra meta."""

    model_config = ConfigDict(extra="forbid")

    title: Title | None = None
    target: dict[str, Any] | None = None
    start_date: date | None = None
    target_date: date | None = None
    status: GoalStatus | None = None
    priority: Priority | None = None


class GoalOut(BaseModel):
    id: uuid.UUID
    kind: str
    title: str
    target: dict[str, Any]
    # Alvo em texto (ex.: "Correr 5 km"), montado pela API.
    summary: str
    start_date: date
    target_date: date | None
    status: GoalStatus
    priority: int
    closed_at: datetime | None
    created_at: datetime
    updated_at: datetime


class TargetFieldOut(BaseModel):
    key: str
    label: str
    type: str
    required: bool
    min: float | None
    max: float | None
    step: float | None
    unit: str | None
    options: list[Option] | None


class GoalKindOut(BaseModel):
    code: str
    label: str
    description: str
    health_data: bool
    fields: list[TargetFieldOut]


class PriorityOut(BaseModel):
    value: int
    label: str


class GoalOptions(BaseModel):
    kinds: list[GoalKindOut]
    statuses: list[Option]
    priorities: list[PriorityOut]
