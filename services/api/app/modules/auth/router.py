from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response, status
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import UnauthorizedError
from app.db.session import get_db
from app.modules.auth import rate_limit
from app.modules.auth.dependencies import client_ip, get_rate_limiter
from app.modules.auth.rate_limit import RateLimiter
from app.modules.auth.schemas import LoginRequest, RefreshRequest, RegisterRequest, TokenPair
from app.modules.auth.service import AuthService

router = APIRouter(prefix="/auth", tags=["autenticação"])

DbSession = Annotated[Session, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings)]
Limiter = Annotated[RateLimiter, Depends(get_rate_limiter)]


@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
    response_model=TokenPair,
    summary="Cria a conta, registra o aceite dos termos e já inicia a sessão",
)
def register(
    data: RegisterRequest,
    request: Request,
    response: Response,
    db: DbSession,
    settings: AppSettings,
    limiter: Limiter,
) -> TokenPair:
    limiter.hit(f"register:ip:{client_ip(request)}", rate_limit.REGISTER_PER_IP)
    _, pair = AuthService(db, settings).register(data, request.headers.get("user-agent"))
    response.headers["Location"] = "/api/v1/me"
    return pair


@router.post("/login", response_model=TokenPair, summary="Entra com e-mail e senha")
def login(
    data: LoginRequest,
    request: Request,
    db: DbSession,
    settings: AppSettings,
    limiter: Limiter,
) -> TokenPair:
    limiter.hit(f"login:ip:{client_ip(request)}", rate_limit.LOGIN_PER_IP)
    email_key = f"login:email:{data.email}"
    # Bloqueia mesmo com a senha certa enquanto houver falhas demais: impede adivinhação.
    limiter.check(email_key, rate_limit.LOGIN_FAILURES_PER_EMAIL)
    service = AuthService(db, settings)
    try:
        user = service.authenticate(data)
    except UnauthorizedError:
        limiter.record(email_key, rate_limit.LOGIN_FAILURES_PER_EMAIL)
        raise
    limiter.reset(email_key)
    return service.login(user, data.password, request.headers.get("user-agent"))


@router.post(
    "/refresh",
    response_model=TokenPair,
    summary="Troca o refresh token por um novo par (o anterior deixa de valer)",
)
def refresh(
    data: RefreshRequest,
    request: Request,
    db: DbSession,
    settings: AppSettings,
    limiter: Limiter,
) -> TokenPair:
    limiter.hit(f"refresh:ip:{client_ip(request)}", rate_limit.REFRESH_PER_IP)
    return AuthService(db, settings).refresh(data.refresh_token, request.headers.get("user-agent"))


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Encerra a sessão deste aparelho (revoga a família do refresh token)",
)
def logout(data: RefreshRequest, db: DbSession, settings: AppSettings) -> None:
    AuthService(db, settings).logout(data.refresh_token)
