"""Perfil e consentimentos do usuário autenticado (docs/SECURITY_PRIVACY.md §3)."""

import logging
from datetime import UTC, datetime

from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import AppError, FieldValidationError
from app.modules.activities.models import Activity, EnduranceDetails
from app.modules.goals.kinds import HEALTH_KINDS
from app.modules.goals.models import Goal
from app.modules.users.models import ConsentKind, User, UserConsent, UserProfile
from app.modules.users.schemas import ProfileUpdate

logger = logging.getLogger(__name__)

# Campos que não aceitam null (têm valor padrão no perfil).
_REQUIRED = {"display_name", "timezone", "unit_system"}
# Listas: null equivale a lista vazia.
_LISTS = {
    "secondary_objectives",
    "preferred_modalities",
    "equipment",
    "dietary_preferences",
    "limitation_tags",
}
_HEALTH_FIELDS = {"limitation_tags", "limitations_note"}


class ConsentRequiredError(AppError):
    def __init__(self, kind: ConsentKind) -> None:
        super().__init__(
            403,
            "consent_required",
            "Consentimento necessário",
            "Para salvar dados de saúde, autorize o uso desses dados no seu perfil.",
            errors=[{"field": "consent", "message": kind.value}],
        )


class ConsentNotRevocableError(AppError):
    def __init__(self) -> None:
        super().__init__(
            409,
            "consent_not_revocable",
            "Consentimento obrigatório",
            "Os termos de uso são necessários para manter a conta. "
            "Para deixar de usá-los, exclua a conta.",
        )


def active_consent(db: Session, user_id: object, kind: ConsentKind) -> UserConsent | None:
    return db.scalar(
        select(UserConsent).where(
            UserConsent.user_id == user_id,
            UserConsent.kind == kind,
            UserConsent.revoked_at.is_(None),
        )
    )


def active_consents(db: Session, user: User) -> list[UserConsent]:
    return list(
        db.scalars(
            select(UserConsent)
            .where(UserConsent.user_id == user.id, UserConsent.revoked_at.is_(None))
            .order_by(UserConsent.granted_at)
        )
    )


class ProfileService:
    def __init__(self, db: Session, settings: Settings) -> None:
        self.db = db
        self.settings = settings

    def update(self, user: User, data: ProfileUpdate) -> UserProfile:
        profile = user.profile
        if profile is None:  # contas criadas pelo cadastro sempre têm perfil
            profile = UserProfile(user_id=user.id, display_name="")
            self.db.add(profile)

        changes = {name: getattr(data, name) for name in data.model_fields_set}
        changes.pop("onboarding_completed", None)

        for name in _REQUIRED & changes.keys():
            if changes[name] is None:
                raise FieldValidationError(name, "Campo obrigatório.")
        for name in _LISTS & changes.keys():
            if changes[name] is None:
                changes[name] = []
        if changes.get("limitations_note") == "":
            changes["limitations_note"] = None

        primary = changes.get("primary_objective", profile.primary_objective)
        secondary = changes.get("secondary_objectives", profile.secondary_objectives)
        if primary is not None and primary in secondary:
            raise FieldValidationError(
                "secondary_objectives", "O objetivo principal não precisa ser repetido aqui."
            )

        # Dado de saúde novo só com consentimento ativo; limpar é sempre permitido.
        adds_health_data = any(changes.get(f) for f in _HEALTH_FIELDS & changes.keys())
        if adds_health_data and not active_consent(self.db, user.id, ConsentKind.HEALTH_DATA):
            raise ConsentRequiredError(ConsentKind.HEALTH_DATA)

        for name, value in changes.items():
            if name == "weekly_availability" and value is not None:
                value = value.model_dump()
            setattr(profile, name, value)
        if data.onboarding_completed and profile.onboarding_completed_at is None:
            profile.onboarding_completed_at = datetime.now(UTC)

        self.db.commit()
        self.db.refresh(profile)
        # Só os nomes dos campos: os valores podem ser dados de saúde.
        logger.info("profile_updated", extra={"user_id": str(user.id), "fields": sorted(changes)})
        return profile

    # --- consentimentos ---

    def grant(self, user: User, kind: ConsentKind) -> UserConsent:
        """Idempotente: um consentimento já ativo é devolvido sem criar outro registro."""
        if kind is ConsentKind.TERMS_PRIVACY:
            raise FieldValidationError("kind", "Os termos são aceitos no cadastro.")
        existing = active_consent(self.db, user.id, kind)
        if existing is not None:
            return existing
        consent = UserConsent(
            user_id=user.id,
            kind=kind,
            version=self.settings.terms_version,
            granted_at=datetime.now(UTC),
        )
        self.db.add(consent)
        self.db.commit()
        logger.info("consent_granted", extra={"user_id": str(user.id), "kind": kind.value})
        return consent

    def revoke(self, user: User, kind: ConsentKind) -> None:
        """Revoga (idempotente). Revogar health_data apaga os dados de saúde (perfil e peso)."""
        if kind is ConsentKind.TERMS_PRIVACY:
            raise ConsentNotRevocableError
        consent = active_consent(self.db, user.id, kind)
        if consent is not None:
            consent.revoked_at = datetime.now(UTC)
        if kind is ConsentKind.HEALTH_DATA and user.profile is not None:
            # Sem base legal para mantê-los (LGPD art. 11): saem junto com o consentimento.
            user.profile.limitation_tags = []
            user.profile.limitations_note = None
        if kind is ConsentKind.HEALTH_DATA:
            # Metas de peso também são dados de saúde.
            self.db.execute(
                delete(Goal).where(Goal.user_id == user.id, Goal.kind.in_(HEALTH_KINDS))
            )
            # E a frequência cardíaca das atividades (o resto da atividade fica).
            self.db.execute(
                update(EnduranceDetails)
                .where(
                    EnduranceDetails.activity_id.in_(
                        select(Activity.id).where(Activity.user_id == user.id)
                    )
                )
                .values(avg_hr=None, max_hr=None)
            )
        self.db.commit()
        logger.info("consent_revoked", extra={"user_id": str(user.id), "kind": kind.value})
