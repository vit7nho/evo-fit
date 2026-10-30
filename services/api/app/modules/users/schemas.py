import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.modules.users.models import (
    ConsentKind,
    ExperienceLevel,
    SexForCalculations,
    UnitSystem,
    UserStatus,
)


class _FromModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class ProfileOut(_FromModel):
    display_name: str
    birth_year: int | None
    sex_for_calculations: SexForCalculations | None
    timezone: str
    unit_system: UnitSystem
    experience_level: ExperienceLevel | None
    weekly_availability: dict | None
    preferred_modalities: list[str]
    equipment: list[str]
    dietary_preferences: list[str]
    limitation_tags: list[str]
    limitations_note: str | None


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
