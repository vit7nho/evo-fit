from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import UnauthorizedError
from app.db.session import get_db
from app.modules.auth.rate_limit import RateLimiter
from app.modules.auth.tokens import InvalidAccessTokenError, decode_access_token
from app.modules.users.models import User, UserStatus

# auto_error=False: a falta do cabeçalho vira o nosso 401 em problem+json, não o padrão do FastAPI.
_bearer = HTTPBearer(auto_error=False, description="Access token obtido em /auth/login.")


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    db: Annotated[Session, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    """Usuário dono da requisição. É a única origem do user_id nos endpoints."""
    if credentials is None:
        raise UnauthorizedError("not_authenticated", "Entre na sua conta para continuar.")
    try:
        user_id = decode_access_token(credentials.credentials, settings)
    except InvalidAccessTokenError:
        raise UnauthorizedError("invalid_token", "Sessão inválida ou expirada.") from None
    user = db.get(User, user_id)
    if user is None or user.status is not UserStatus.ACTIVE:
        raise UnauthorizedError("invalid_token", "Sessão inválida ou expirada.")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def get_rate_limiter(request: Request) -> RateLimiter:
    return request.app.state.rate_limiter


def client_ip(request: Request) -> str:
    # Sem proxy reverso na v1: o endereço da conexão é o do cliente. Com proxy, configurar
    # o uvicorn com --proxy-headers e a lista de proxies confiáveis.
    return request.client.host if request.client else "desconhecido"
