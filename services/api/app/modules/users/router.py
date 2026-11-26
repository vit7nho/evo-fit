from collections.abc import Mapping
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser, get_rate_limiter
from app.modules.auth.rate_limit import Limit, RateLimiter
from app.modules.users import vocabulary
from app.modules.users.account import delete_account, export_account
from app.modules.users.models import ConsentKind, User
from app.modules.users.schemas import (
    ConsentOut,
    DeleteAccountIn,
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
Limiter = Annotated[RateLimiter, Depends(get_rate_limiter)]

# Exportação: até 10 por hora por conta.
EXPORT_PER_USER = Limit(max_hits=10, window_s=60 * 60)


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


# --- direitos do titular (5.6, ADR-063) ---


@router.get(
    "/me/export",
    summary="Exporta todos os dados da conta (JSON, como arquivo para baixar)",
)
def export_me(user: CurrentUser, db: DbSession, limiter: Limiter) -> JSONResponse:
    # Arquivo grande e raro: um limite folgado evita abuso sem atrapalhar ninguém.
    limiter.hit(f"export:user:{user.id}", EXPORT_PER_USER)
    data = export_account(db, user)
    day = data["exported_at"][:10]
    return JSONResponse(
        data,
        headers={
            "Content-Disposition": f'attachment; filename="evofit-dados-{day}.json"',
            "Cache-Control": "no-store",
        },
    )


@router.delete(
    "/me",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Exclui a conta e todos os dados (exige a senha); não há como desfazer",
)
def delete_me(
    data: DeleteAccountIn, user: CurrentUser, db: DbSession, limiter: Limiter
) -> Response:
    delete_account(db, user, data.password, limiter)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
