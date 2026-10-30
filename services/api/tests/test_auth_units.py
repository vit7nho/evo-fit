"""Testes unitários de senha, tokens e limite de tentativas (sem HTTP)."""

import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest

from app.core.config import get_settings
from app.modules.auth import passwords, tokens
from app.modules.auth.rate_limit import Limit, RateLimiter, TooManyRequestsError

# --- senhas ---


def test_hash_is_argon2id_and_verifies() -> None:
    hashed = passwords.hash_password("uma senha longa e boa")
    assert hashed.startswith("$argon2id$")
    assert passwords.verify_password(hashed, "uma senha longa e boa")
    assert not passwords.verify_password(hashed, "outra senha qualquer")


def test_verify_password_rejects_garbage_hash() -> None:
    assert not passwords.verify_password("isto-nao-e-um-hash", "qualquer coisa")


@pytest.mark.parametrize(
    ("password", "expected"),
    [
        ("curta123", "pelo menos 10"),
        ("x" * 129, "no máximo 128"),
        ("1234567890", "muito comum"),
        ("QwErTyUiOp", "muito comum"),
        ("abababababab", "muito comum"),
        ("maria.silva-2026", "não pode conter o seu e-mail"),
    ],
)
def test_password_policy_rejects(password: str, expected: str) -> None:
    error = passwords.password_policy_error(password, "maria.silva@exemplo.com")
    assert error is not None
    assert expected in error


def test_password_policy_accepts_reasonable_password() -> None:
    assert passwords.password_policy_error("cavalo bateria grampo", "ana@exemplo.com") is None


# --- tokens ---


def test_access_token_roundtrip_carries_only_ids() -> None:
    settings = get_settings()
    user_id = uuid.uuid7()
    token, expires_in = tokens.create_access_token(user_id, settings)
    assert expires_in == settings.access_token_ttl_minutes * 60
    assert tokens.decode_access_token(token, settings) == user_id
    claims = jwt.decode(token, options={"verify_signature": False})
    assert set(claims) == {"sub", "jti", "iss", "typ", "iat", "exp"}


def test_expired_access_token_is_rejected() -> None:
    settings = get_settings()
    past = datetime.now(UTC) - timedelta(hours=1)
    token, _ = tokens.create_access_token(uuid.uuid7(), settings, now=past)
    with pytest.raises(tokens.InvalidAccessTokenError):
        tokens.decode_access_token(token, settings)


@pytest.mark.parametrize(
    "token_factory",
    [
        # Assinado com outro segredo.
        lambda now: jwt.encode(
            {
                "sub": str(uuid.uuid7()),
                "iss": tokens.ISSUER,
                "typ": "access",
                "iat": now,
                "exp": now + timedelta(minutes=5),
            },
            "outro-segredo-qualquer-com-32-caracteres!!",
            algorithm="HS256",
        ),
        # Algoritmo "none" (sem assinatura).
        lambda now: jwt.encode(
            {
                "sub": str(uuid.uuid7()),
                "iss": tokens.ISSUER,
                "typ": "access",
                "iat": now,
                "exp": now + timedelta(minutes=5),
            },
            None,
            algorithm="none",
        ),
    ],
    ids=["outro-segredo", "alg-none"],
)
def test_forged_access_tokens_are_rejected(token_factory) -> None:
    with pytest.raises(tokens.InvalidAccessTokenError):
        tokens.decode_access_token(token_factory(datetime.now(UTC)), get_settings())


def test_token_with_wrong_type_is_rejected() -> None:
    settings = get_settings()
    now = datetime.now(UTC)
    token = jwt.encode(
        {
            "sub": str(uuid.uuid7()),
            "iss": tokens.ISSUER,
            "typ": "refresh",
            "iat": now,
            "exp": now + timedelta(minutes=5),
        },
        settings.jwt_secret.get_secret_value(),
        algorithm="HS256",
    )
    with pytest.raises(tokens.InvalidAccessTokenError):
        tokens.decode_access_token(token, settings)


def test_refresh_tokens_are_random_and_only_hash_is_kept() -> None:
    raw1, hash1 = tokens.new_refresh_token()
    raw2, _ = tokens.new_refresh_token()
    assert raw1 != raw2
    assert len(raw1) >= 43  # 32 bytes em base64url
    assert hash1 == tokens.hash_refresh_token(raw1)
    assert raw1 not in hash1


# --- limite de tentativas ---


class _Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def test_rate_limiter_blocks_after_limit_and_frees_after_window() -> None:
    clock = _Clock()
    limiter = RateLimiter(clock)
    limit = Limit(max_hits=3, window_s=60)
    for _ in range(3):
        limiter.hit("k", limit)
    with pytest.raises(TooManyRequestsError) as exc:
        limiter.hit("k", limit)
    assert exc.value.headers == {"Retry-After": "60"}

    clock.now += 61
    limiter.hit("k", limit)  # a janela passou


def test_rate_limiter_keys_are_independent_and_reset_clears() -> None:
    limiter = RateLimiter(_Clock())
    limit = Limit(max_hits=1, window_s=60)
    limiter.record("a", limit)
    with pytest.raises(TooManyRequestsError):
        limiter.check("a", limit)
    limiter.check("b", limit)
    limiter.reset("a")
    limiter.check("a", limit)
