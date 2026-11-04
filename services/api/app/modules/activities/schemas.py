import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StringConstraints

from app.modules.users.schemas import Option

# Musculação é registrada pela sessão de treino (/workout-sessions), não aqui.
Modality = Literal["run", "walk", "cycle", "swim"]
Stroke = Literal["freestyle", "breaststroke", "backstroke", "butterfly", "mixed"]

# De 1 minuto a 24 horas.
Duration = Annotated[int, Field(ge=60, le=24 * 3600)]
Effort = Annotated[int, Field(ge=1, le=10)]
Notes = Annotated[str, StringConstraints(strip_whitespace=True, max_length=1000)]
Distance = Annotated[int, Field(ge=1)]
PoolLength = Annotated[int, Field(ge=10, le=100)]
Laps = Annotated[int, Field(ge=1, le=2000)]


class ActivityCreate(BaseModel):
    """Campos comuns + os da modalidade: `indoor` só no ciclismo; piscina, voltas e
    estilo só na natação. Distância em metros, opcional em todas."""

    model_config = ConfigDict(extra="forbid")

    modality: Modality
    started_at: AwareDatetime
    duration_s: Duration
    distance_m: Distance | None = None
    perceived_effort: Effort | None = None
    notes: Notes | None = None
    indoor: bool | None = None
    pool_length_m: PoolLength | None = None
    laps: Laps | None = None
    stroke: Stroke | None = None


class ActivityUpdate(BaseModel):
    """Atualização parcial; `null` limpa os opcionais. A modalidade não muda."""

    model_config = ConfigDict(extra="forbid")

    started_at: AwareDatetime | None = None
    duration_s: Duration | None = None
    distance_m: Distance | None = None
    perceived_effort: Effort | None = None
    notes: Notes | None = None
    indoor: bool | None = None
    pool_length_m: PoolLength | None = None
    laps: Laps | None = None
    stroke: Stroke | None = None


class ActivityOut(BaseModel):
    id: uuid.UUID
    modality: Modality
    started_at: datetime
    ended_at: datetime
    duration_s: int
    distance_m: int | None
    perceived_effort: int | None
    notes: str | None
    # Só no ciclismo (nas outras, null).
    indoor: bool | None
    # Só na natação (nas outras, null).
    pool_length_m: int | None
    laps: int | None
    stroke: Stroke | None
    created_at: datetime
    updated_at: datetime


class ModalityOut(BaseModel):
    code: Modality
    label: str
    # Maior distância aceita, em metros.
    max_distance_m: int


class ActivityOptions(BaseModel):
    modalities: list[ModalityOut]
    strokes: list[Option]
    pool_lengths_m: list[int]
