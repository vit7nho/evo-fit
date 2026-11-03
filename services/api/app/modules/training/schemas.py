import uuid
from datetime import datetime
from typing import Annotated, Any, Literal, Self

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.modules.exercises import catalog as exercise_catalog
from app.modules.training import catalog
from app.modules.users.schemas import Option

Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=60)]
Rest = Annotated[int, Field(ge=0, le=600)]


class PlannedSet(BaseModel):
    """Uma série planejada: repetições (faixa) ou duração, mais carga e RIR opcionais."""

    model_config = ConfigDict(extra="forbid")

    kind: Literal["warmup", "working", "drop", "rest_pause"] = "working"
    reps_min: Annotated[int, Field(ge=1, le=100)] | None = None
    reps_max: Annotated[int, Field(ge=1, le=100)] | None = None
    duration_s: Annotated[int, Field(ge=5, le=3600)] | None = None
    load_kg: Annotated[float, Field(ge=0, le=1000, multiple_of=0.25)] | None = None
    # Repetições em reserva ao fim da série (0 = até a falha).
    rir_target: Annotated[int, Field(ge=0, le=5)] | None = None

    @model_validator(mode="after")
    def _reps_or_duration(self) -> Self:
        has_reps = self.reps_min is not None or self.reps_max is not None
        if has_reps == (self.duration_s is not None):
            raise ValueError("Informe as repetições ou a duração da série (um dos dois).")
        if has_reps:
            if self.reps_min is None:
                self.reps_min = self.reps_max
            if self.reps_max is None:
                self.reps_max = self.reps_min
            if self.reps_max < self.reps_min:  # type: ignore[operator]
                raise ValueError("O máximo de repetições não pode ser menor que o mínimo.")
        return self


class GroupIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["biset", "superset", "triset", "giant_set"]
    # Descanso depois de cada rodada do grupo.
    rest_after_s: Rest | None = None


class ItemIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    exercise_id: uuid.UUID
    planned_sets: Annotated[list[PlannedSet], Field(min_length=1, max_length=catalog.MAX_SETS)]
    # Descanso entre as séries deste exercício (fora de grupo).
    rest_s: Rest | None = None
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=300)] | None = None
    # Índice em `groups`; nulo = exercício avulso.
    group: Annotated[int, Field(ge=0)] | None = None


class TemplateIn(BaseModel):
    """Ficha inteira: nome, itens na ordem e grupos. Salvar regrava tudo de uma vez."""

    model_config = ConfigDict(extra="forbid")

    name: Name
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=500)] | None = None
    items: Annotated[list[ItemIn], Field(max_length=catalog.MAX_ITEMS)] = []
    groups: Annotated[list[GroupIn], Field(max_length=catalog.MAX_ITEMS // 2)] = []


class TemplateOrder(BaseModel):
    model_config = ConfigDict(extra="forbid")

    template_ids: list[uuid.UUID]


class ExerciseRef(BaseModel):
    id: uuid.UUID
    name: str
    equipment: str
    load_type: str
    is_active: bool
    primary_muscles: list[str]

    @classmethod
    def of(cls, exercise: Any) -> Self:
        """A partir do modelo `Exercise`: músculos principais na ordem do catálogo."""
        order = {m.id: i for i, m in enumerate(exercise_catalog.MUSCLE_GROUPS)}
        return cls(
            id=exercise.id,
            name=exercise.name,
            equipment=exercise.equipment,
            load_type=exercise.load_type,
            is_active=exercise.is_active,
            primary_muscles=sorted(
                (m.muscle_group_id for m in exercise.muscles if m.role == "primary"),
                key=order.__getitem__,
            ),
        )


class GroupOut(BaseModel):
    id: uuid.UUID
    kind: str
    rest_after_s: int | None


class ItemOut(BaseModel):
    id: uuid.UUID
    exercise: ExerciseRef
    planned_sets: list[PlannedSet]
    rest_s: int | None
    notes: str | None
    group: int | None


class TemplateOut(BaseModel):
    id: uuid.UUID
    name: str
    notes: str | None
    position: int
    groups: list[GroupOut]
    items: list[ItemOut]
    # Resumo para a lista: exercícios, séries (sem aquecimento) e músculos principais.
    exercise_count: int
    set_count: int
    muscles: list[str]
    created_at: datetime
    updated_at: datetime


class GroupKindOut(BaseModel):
    code: str
    label: str
    min_size: int
    max_size: int


class WorkoutOptions(BaseModel):
    group_kinds: list[GroupKindOut]
    set_kinds: list[Option]
