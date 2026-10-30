from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser
from app.modules.users.models import UserConsent
from app.modules.users.schemas import ConsentOut, MeResponse, ProfileOut

router = APIRouter(tags=["conta"])


@router.get("/me", response_model=MeResponse, summary="Conta, perfil e consentimentos ativos")
def get_me(user: CurrentUser, db: Annotated[Session, Depends(get_db)]) -> MeResponse:
    consents = db.scalars(
        select(UserConsent)
        .where(UserConsent.user_id == user.id, UserConsent.revoked_at.is_(None))
        .order_by(UserConsent.granted_at)
    ).all()
    return MeResponse(
        id=user.id,
        email=user.email,
        status=user.status,
        created_at=user.created_at,
        profile=ProfileOut.model_validate(user.profile) if user.profile else None,
        consents=[ConsentOut.model_validate(c) for c in consents],
    )
