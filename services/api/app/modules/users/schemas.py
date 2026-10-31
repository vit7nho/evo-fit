import uuid
import zoneinfo
from collections.abc import Callable, Mapping
from datetime import UTC, datetime
from functools import lru_cache
from typing import Annotated, Any, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, StringConstraints

from app.modules.users import vocabulary
from app.modules.users.models import (
    ConsentKind,
    ExperienceLevel,
    SexForCalculations,
    UnitSystem,
    UserStatus,
)

# --- validadores de vocabulário ---


def _one_of(options: Mapping[str, str]) -> Callable[[str], str]:
    def check(value: str) -> str:
        if value not in options:
            raise ValueError(f"Valor inválido: {value}.")
        return value

    return check


def _many_of(options: Mapping[str, str]) -> Callable[[list[str]], list[str]]:
    def check(values: list[str]) -> list[str]:
        for value in values:
            _one_of(options)(value)
        if len(set(values)) != len(values):
            raise ValueError("Há valores repetidos.")
        return values

    return check


def _codes(options: Mapping[str, str], max_items: int) -> Any:
    """Lista de códigos de um vocabulário, sem repetição."""
    return Annotated[list[str], Field(max_length=max_items), AfterValidator(_many_of(options))]


@lru_cache
def _timezones() -> frozenset[str]:
    return frozenset(zoneinfo.available_timezones())


def _timezone(value: str) -> str:
    if value not in _timezones():
        raise ValueError("Fuso horário inválido (ex.: America/Sao_Paulo).")
    return value


def _birth_year(value: int) -> int:
    current = datetime.now(UTC).year
    # Idade mínima de 13 anos para usar o app; acima de 100, provável erro de digitação.
    if not current - 100 <= value <= current - 13:
        raise ValueError(f"Informe um ano entre {current - 100} e {current - 13}.")
    return value


Objective = Annotated[str, AfterValidator(_one_of(vocabulary.OBJECTIVES))]
Objectives = _codes(vocabulary.OBJECTIVES, 5)
Modalities = _codes(vocabulary.MODALITIES, len(vocabulary.MODALITIES))
Equipment = _codes(vocabulary.EQUIPMENT, len(vocabulary.EQUIPMENT))
DietaryPreferences = _codes(vocabulary.DIETARY_PREFERENCES, len(vocabulary.DIETARY_PREFERENCES))
LimitationTags = _codes(vocabulary.LIMITATION_TAGS, len(vocabulary.LIMITATION_TAGS))


class _FromModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class WeeklyAvailability(BaseModel):
    model_config = ConfigDict(extra="forbid")

    days_per_week: int = Field(ge=1, le=7)
    minutes_per_session: int = Field(ge=10, le=300)


# --- leitura ---


class ProfileOut(_FromModel):
    display_name: str
    birth_year: int | None
    sex_for_calculations: SexForCalculations | None
    timezone: str
    unit_system: UnitSystem
    experience_level: ExperienceLevel | None
    weekly_availability: WeeklyAvailability | None
    primary_objective: str | None
    secondary_objectives: list[str]
    preferred_modalities: list[str]
    equipment: list[str]
    dietary_preferences: list[str]
    limitation_tags: list[str]
    limitations_note: str | None
    onboarding_completed_at: datetime | None


class ConsentOut(_FromModel):
    kind: ConsentKind
    version: str
    granted_at: datetime


class MeResponse(_FromModel):
    id: uuid.UUID
    email: str
    status: UserStatus
    created_at: datetime
    profile: ProfileOut | None
    consents: list[ConsentOut]


class Option(BaseModel):
    code: str
    label: str


class ProfileOptions(BaseModel):
    """Opções válidas de cada campo do perfil, na ordem de exibição."""

    objectives: list[Option]
    modalities: list[Option]
    equipment: list[Option]
    dietary_preferences: list[Option]
    limitation_tags: list[Option]
    experience_levels: list[Option]
    unit_systems: list[Option]
    sex_for_calculations: list[Option]


# --- escrita ---


class ProfileUpdate(BaseModel):
    """Atualização parcial: só os campos enviados mudam; `null` limpa os opcionais."""

    model_config = ConfigDict(extra="forbid")

    display_name: (
        Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=60)] | None
    ) = None
    birth_year: Annotated[int, AfterValidator(_birth_year)] | None = None
    sex_for_calculations: SexForCalculations | None = None
    timezone: Annotated[str, AfterValidator(_timezone)] | None = None
    unit_system: UnitSystem | None = None
    experience_level: ExperienceLevel | None = None
    weekly_availability: WeeklyAvailability | None = None
    primary_objective: Objective | None = None
    secondary_objectives: Objectives | None = None
    preferred_modalities: Modalities | None = None
    equipment: Equipment | None = None
    dietary_preferences: DietaryPreferences | None = None
    limitation_tags: LimitationTags | None = None
    limitations_note: (
        Annotated[str, StringConstraints(strip_whitespace=True, max_length=1000)] | None
    ) = None
    onboarding_completed: Literal[True] | None = Field(
        default=None, description="Marca o onboarding como concluído (não volta atrás)."
    )
