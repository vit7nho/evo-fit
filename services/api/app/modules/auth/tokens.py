"""Access token JWT curto e refresh token opaco (ADR-005)."""

import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt

from app.core.config import Settings

ALGORITHM = "HS256"
ISSUER = "evofit-api"
ACCESS_TOKEN_TYPE = "access"  # noqa: S105 — rótulo do claim "typ", não um segredo


class InvalidAccessTokenError(Exception):
    pass


def create_access_token(
    user_id: uuid.UUID, settings: Settings, now: datetime | None = None
) -> tuple[str, int]:
    """Retorna o token e a validade em segundos.

    Só identificadores vão no token: nada de e-mail ou dados de perfil.
    """
    issued_at = now or datetime.now(UTC)
    ttl = timedelta(minutes=settings.access_token_ttl_minutes)
    claims = {
        "sub": str(user_id),
        "jti": str(uuid.uuid4()),
        "iss": ISSUER,
        "typ": ACCESS_TOKEN_TYPE,
        "iat": issued_at,
        "exp": issued_at + ttl,
    }
    token = jwt.encode(claims, settings.jwt_secret.get_secret_value(), algorithm=ALGORITHM)
    return token, int(ttl.total_seconds())


def decode_access_token(token: str, settings: Settings) -> uuid.UUID:
    try:
        claims = jwt.decode(
            token,
            settings.jwt_secret.get_secret_value(),
            # Lista fixa: impede tokens com "alg": "none" ou outro algoritmo.
            algorithms=[ALGORITHM],
            issuer=ISSUER,
            options={"require": ["sub", "exp", "iat", "iss", "typ"]},
        )
    except jwt.PyJWTError as exc:
        raise InvalidAccessTokenError from exc
    if claims.get("typ") != ACCESS_TOKEN_TYPE:
        raise InvalidAccessTokenError
    try:
        return uuid.UUID(claims["sub"])
    except (ValueError, TypeError) as exc:
        raise InvalidAccessTokenError from exc


def new_refresh_token() -> tuple[str, str]:
    """Retorna (valor entregue ao cliente, hash armazenado). 256 bits aleatórios."""
    raw = secrets.token_urlsafe(32)
    return raw, hash_refresh_token(raw)


def hash_refresh_token(raw: str) -> str:
    # SHA-256 basta: o valor já tem 256 bits de entropia (não é uma senha escolhida por pessoa).
    return hashlib.sha256(raw.encode()).hexdigest()
