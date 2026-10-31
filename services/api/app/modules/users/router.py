from collections.abc import Mapping
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser
from app.modules.users import vocabulary
from app.modules.users.models import ConsentKind, User
from app.modules.users.schemas import (
    ConsentOut,
    MeResponse,
    Option,
    ProfileOptions,
    ProfileOut,
    ProfileUpdate,
)
from app.modules.users.service import ProfileService, active_consents

router = APIRouter(tags=["conta"])

DbSession = Annotated[Session, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings)]


def _me(db: Session, user: User) -> MeResponse:
    return MeResponse(
        id=user.id,
        email=user.email,
        status=user.status,
        created_at=user.created_at,
        profile=ProfileOut.model_validate(user.profile) if user.profile else None,
        consents=[ConsentOut.model_validate(c) for c in active_consents(db, user)],
    )


@router.get("/me", response_model=MeResponse, summary="Conta, perfil e consentimentos ativos")
def get_me(user: CurrentUser, db: DbSession) -> MeResponse:
    return _me(db, user)


@router.patch(
    "/me",
    response_model=MeResponse,
    summary="Atualiza o perfil (parcial). Dados de saúde exigem o consentimento health_data",
)
def update_me(
    data: ProfileUpdate, user: CurrentUser, db: DbSession, settings: AppSettings
) -> MeResponse:
    ProfileService(db, settings).update(user, data)
    return _me(db, user)


@router.put(
    "/me/consents/{kind}",
    response_model=ConsentOut,
    summary="Concede um consentimento (health_data ou ai_processing); idempotente",
)
def grant_consent(
    kind: ConsentKind, user: CurrentUser, db: DbSession, settings: AppSettings
) -> ConsentOut:
    return ConsentOut.model_validate(ProfileService(db, settings).grant(user, kind))


@router.delete(
    "/me/consents/{kind}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Revoga um consentimento; revogar health_data apaga os dados de saúde",
)
def revoke_consent(
    kind: ConsentKind, user: CurrentUser, db: DbSession, settings: AppSettings
) -> Response:
    ProfileService(db, settings).revoke(user, kind)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _options(source: Mapping[str, str]) -> list[Option]:
    return [Option(code=code, label=label) for code, label in source.items()]


@router.get(
    "/profile-options",
    response_model=ProfileOptions,
    summary="Opções e rótulos dos campos do perfil (não exige login)",
)
def profile_options(response: Response) -> ProfileOptions:
    response.headers["Cache-Control"] = "public, max-age=3600"
    return ProfileOptions(
        objectives=_options(vocabulary.OBJECTIVES),
        modalities=_options(vocabulary.MODALITIES),
        equipment=_options(vocabulary.EQUIPMENT),
        dietary_preferences=_options(vocabulary.DIETARY_PREFERENCES),
        limitation_tags=_options(vocabulary.LIMITATION_TAGS),
        experience_levels=_options(vocabulary.EXPERIENCE_LEVELS),
        unit_systems=_options(vocabulary.UNIT_SYSTEMS),
        sex_for_calculations=_options(vocabulary.SEX_FOR_CALCULATIONS),
    )
