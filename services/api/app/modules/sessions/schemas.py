import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.modules.training.schemas import ExerciseRef, GroupOut, PlannedSet, Rest

Reps = Annotated[int, Field(ge=1, le=200)]
Load = Annotated[float, Field(ge=0, le=1000, multiple_of=0.25)]
Duration = Annotated[int, Field(ge=1, le=86_400)]
Rir = Annotated[int, Field(ge=0, le=10)]
Rpe = Annotated[float, Field(ge=1, le=10, multiple_of=0.5)]


class SessionStart(BaseModel):
    """A partir de uma ficha (copia exercícios, grupos e plano) ou livre (sem `template_id`)."""

    model_config = ConfigDict(extra="forbid")

    template_id: uuid.UUID | None = None
    name: (
        Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=60)] | None
    ) = None


class ExerciseAdd(BaseModel):
    model_config = ConfigDict(extra="forbid")

    exercise_id: uuid.UUID


class ExerciseUpdate(BaseModel):
    """Ajustes de um exercício durante o treino (só nesta sessão; a ficha não muda)."""

    model_config = ConfigDict(extra="forbid")

    rest_s: Rest | None = None
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=500)] | None = None


class SetIn(BaseModel):
    """Série executada. Repetições ou duração, conforme o exercício; carga e RIR/RPE opcionais.

    Drop set e rest-pause são segmentos da mesma série: `kind` `drop`/`rest_pause` com
    `parent_set_id` apontando para a série válida que eles continuam (ADR-033).
    """

    model_config = ConfigDict(extra="forbid")

    kind: Literal["warmup", "working", "drop", "rest_pause"] = "working"
    parent_set_id: uuid.UUID | None = None
    reps: Reps | None = None
    load_kg: Load | None = None
    duration_s: Duration | None = None
    rir: Rir | None = None
    rpe: Rpe | None = None
    to_failure: bool = False


class SetUpdate(BaseModel):
    """Correção parcial de uma série; `null` limpa os campos opcionais."""

    model_config = ConfigDict(extra="forbid")

    # Só entre aquecimento e válida; o tipo de um segmento não muda.
    kind: Literal["warmup", "working"] | None = None
    reps: Reps | None = None
    load_kg: Load | None = None
    duration_s: Duration | None = None
    rir: Rir | None = None
    rpe: Rpe | None = None
    to_failure: bool | None = None


class SessionFinish(BaseModel):
    model_config = ConfigDict(extra="forbid")

    perceived_effort: Annotated[int, Field(ge=1, le=10)] | None = None
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=1000)] | None = None


class SetOut(BaseModel):
    id: uuid.UUID
    position: int
    kind: str
    # Série que o segmento (drop, rest-pause) continua; nulo nas séries principais.
    parent_set_id: uuid.UUID | None
    reps: int | None
    load_kg: float | None
    duration_s: int | None
    rir: int | None
    rpe: float | None
    to_failure: bool
    completed_at: datetime


class PreviousSegment(BaseModel):
    kind: str
    reps: int | None
    load_kg: float | None
    duration_s: int | None


class PreviousSet(BaseModel):
    kind: str
    reps: int | None
    load_kg: float | None
    duration_s: int | None
    to_failure: bool
    # Segmentos feitos depois dela (drop, rest-pause), na ordem.
    segments: list[PreviousSegment]


class SessionExerciseOut(BaseModel):
    id: uuid.UUID
    exercise: ExerciseRef
    position: int
    group: int | None
    planned_sets: list[PlannedSet] | None
    rest_s: int | None
    notes: str | None
    sets: list[SetOut]
    # Séries da última sessão concluída com este exercício: base do pré-preenchimento.
    previous: list[PreviousSet]
    previous_at: datetime | None


class SessionOut(BaseModel):
    id: uuid.UUID
    name: str
    template_id: uuid.UUID | None
    status: str
    started_at: datetime
    paused_at: datetime | None
    paused_total_s: int
    ended_at: datetime | None
    # Tempo ativo até agora (ou o total, se concluída), calculado no servidor: o app soma
    # o tempo local desde a resposta, sem depender do relógio do aparelho bater com o da API.
    elapsed_s: int
    perceived_effort: int | None
    notes: str | None
    groups: list[GroupOut]
    exercises: list[SessionExerciseOut]
    # Resumo: séries válidas (sem aquecimento nem segmentos: um drop set é uma série só) e
    # volume (carga x repetições, só carga externa, segmentos incluídos).
    set_count: int
    volume_kg: float
