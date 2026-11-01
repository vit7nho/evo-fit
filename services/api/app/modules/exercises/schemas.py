import uuid
from collections.abc import Callable, Mapping
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, StringConstraints

from app.modules.exercises import catalog
from app.modules.exercises.models import MuscleRole
from app.modules.users.schemas import Option


def _one_of(options: Mapping[str, str]) -> Callable[[str], str]:
    def check(value: str) -> str:
        if value not in options:
            raise ValueError(f"Valor inválido: {value}.")
        return value

    return check


Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=80)]
Instructions = Annotated[str, StringConstraints(strip_whitespace=True, max_length=2000)]
Equipment = Annotated[str, AfterValidator(_one_of(catalog.EQUIPMENT))]
Mechanics = Annotated[str, AfterValidator(_one_of(catalog.MECHANICS))]
LoadType = Annotated[str, AfterValidator(_one_of(catalog.LOAD_TYPES))]
MuscleId = Annotated[str, AfterValidator(_one_of(catalog.MUSCLE_NAMES))]


class MuscleIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    muscle_group_id: MuscleId
    role: MuscleRole


class ExerciseCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Name
    instructions: Instructions | None = None
    mechanics: Mechanics
    equipment: Equipment
    load_type: LoadType
    unilateral: bool = False
    muscles: Annotated[list[MuscleIn], Field(min_length=1, max_length=len(catalog.MUSCLE_GROUPS))]


class ExerciseUpdate(BaseModel):
    """Atualização parcial de um exercício próprio. `is_active: false` arquiva."""

    model_config = ConfigDict(extra="forbid")

    name: Name | None = None
    instructions: Instructions | None = None
    mechanics: Mechanics | None = None
    equipment: Equipment | None = None
    load_type: LoadType | None = None
    unilateral: bool | None = None
    is_active: bool | None = None
    muscles: (
        Annotated[list[MuscleIn], Field(min_length=1, max_length=len(catalog.MUSCLE_GROUPS))] | None
    ) = None


class MuscleOut(BaseModel):
    id: str
    name: str
    role: MuscleRole


class ExerciseOut(BaseModel):
    id: uuid.UUID
    name: str
    instructions: str | None
    mechanics: str
    equipment: str
    load_type: str
    unilateral: bool
    # Criado pelo usuário (editável) ou do catálogo do projeto (só leitura).
    is_custom: bool
    is_active: bool
    muscles: list[MuscleOut]
    # Fotos do catálogo (posição inicial e final), caminhos relativos à API; vazio se não há.
    images: list[str]


class MuscleGroupOut(BaseModel):
    id: str
    name: str
    body_region: str
    view: str


class ExerciseOptions(BaseModel):
    muscle_groups: list[MuscleGroupOut]
    equipment: list[Option]
    mechanics: list[Option]
    load_types: list[Option]
