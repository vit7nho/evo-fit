import enum
import uuid
from datetime import datetime

from sqlalchemy import ARRAY, CheckConstraint, Enum, ForeignKey, SmallInteger, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Timestamps, UUIDPrimaryKey


def _pg_enum(enum_cls: type[enum.Enum], name: str) -> Enum:
    # Persiste o .value (minúsculo) em vez do nome do membro.
    return Enum(enum_cls, name=name, values_callable=lambda e: [m.value for m in e])


class UserStatus(enum.StrEnum):
    ACTIVE = "active"
    DISABLED = "disabled"


class UnitSystem(enum.StrEnum):
    METRIC = "metric"
    IMPERIAL = "imperial"


class ExperienceLevel(enum.StrEnum):
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class SexForCalculations(enum.StrEnum):
    FEMALE = "female"
    MALE = "male"
    UNSPECIFIED = "unspecified"


class ConsentKind(enum.StrEnum):
    TERMS_PRIVACY = "terms_privacy"
    HEALTH_DATA = "health_data"
    AI_PROCESSING = "ai_processing"


class User(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "users"

    # Normalizado em minúsculas pelo serviço; a unicidade vale para o valor normalizado.
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    status: Mapped[UserStatus] = mapped_column(
        _pg_enum(UserStatus, "user_status"), default=UserStatus.ACTIVE
    )
    last_login_at: Mapped[datetime | None]

    profile: Mapped[UserProfile | None] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True
    )

    __table_args__ = (CheckConstraint("email = lower(email)", name="email_lowercase"),)


class UserProfile(Timestamps, Base):
    __tablename__ = "user_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    display_name: Mapped[str] = mapped_column(String(60))
    # Ano em vez da data completa: minimização de dados (LGPD).
    birth_year: Mapped[int | None] = mapped_column(SmallInteger)
    sex_for_calculations: Mapped[SexForCalculations | None] = mapped_column(
        _pg_enum(SexForCalculations, "sex_for_calculations")
    )
    timezone: Mapped[str] = mapped_column(String(64), default="America/Sao_Paulo")
    unit_system: Mapped[UnitSystem] = mapped_column(
        _pg_enum(UnitSystem, "unit_system"), default=UnitSystem.METRIC
    )
    experience_level: Mapped[ExperienceLevel | None] = mapped_column(
        _pg_enum(ExperienceLevel, "experience_level")
    )
    # {"days_per_week": int, "minutes_per_session": int} — validado pelo schema Pydantic.
    weekly_availability: Mapped[dict | None] = mapped_column(JSONB)
    # Listas de valores controlados; o vocabulário é validado na API (Fase 2).
    preferred_modalities: Mapped[list[str]] = mapped_column(ARRAY(String(32)), default=list)
    equipment: Mapped[list[str]] = mapped_column(ARRAY(String(32)), default=list)
    dietary_preferences: Mapped[list[str]] = mapped_column(ARRAY(String(32)), default=list)
    limitation_tags: Mapped[list[str]] = mapped_column(ARRAY(String(48)), default=list)
    # Dado sensível de saúde: só com consentimento health_data; nunca em logs.
    limitations_note: Mapped[str | None] = mapped_column(Text)

    user: Mapped[User] = relationship(back_populates="profile")

    __table_args__ = (CheckConstraint("birth_year BETWEEN 1900 AND 2100", name="birth_year_range"),)


class UserConsent(UUIDPrimaryKey, Base):
    __tablename__ = "user_consents"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[ConsentKind] = mapped_column(_pg_enum(ConsentKind, "consent_kind"))
    version: Mapped[str] = mapped_column(String(20))
    granted_at: Mapped[datetime]
    revoked_at: Mapped[datetime | None]
