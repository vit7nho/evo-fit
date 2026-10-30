"""Fluxos HTTP de autenticação: cadastro, login, /me, rotação, reutilização e logout."""

import logging
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.modules.auth import tokens
from app.modules.auth.models import RefreshToken
from app.modules.users.models import ConsentKind, User, UserConsent, UserStatus

PASSWORD = "cavalo bateria grampo"


def register(client: TestClient, email: str = "Ana@Exemplo.com", **overrides):
    body = {
        "email": email,
        "password": PASSWORD,
        "display_name": "Ana",
        "accept_terms": True,
    } | overrides
    return client.post("/api/v1/auth/register", json=body)


def login(client: TestClient, email: str = "ana@exemplo.com", password: str = PASSWORD):
    return client.post("/api/v1/auth/login", json={"email": email, "password": password})


def auth_header(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}


# --- cadastro ---


def test_register_creates_account_profile_consent_and_session(
    client: TestClient, db: Session
) -> None:
    response = register(client)

    assert response.status_code == 201
    assert response.headers["location"] == "/api/v1/me"
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 15 * 60
    assert body["refresh_expires_in"] == 30 * 24 * 3600

    user = db.scalar(select(User).where(User.email == "ana@exemplo.com"))
    assert user is not None  # e-mail normalizado em minúsculas
    assert user.password_hash.startswith("$argon2id$")
    assert PASSWORD not in user.password_hash
    assert user.profile is not None
    assert user.profile.display_name == "Ana"
    consent = db.scalar(select(UserConsent).where(UserConsent.user_id == user.id))
    assert consent is not None
    assert consent.kind is ConsentKind.TERMS_PRIVACY
    assert consent.version == get_settings().terms_version

    stored = db.scalars(select(RefreshToken).where(RefreshToken.user_id == user.id)).all()
    assert len(stored) == 1
    assert stored[0].token_hash != body["refresh_token"]  # só o hash fica no banco


def test_register_rejects_duplicate_email_ignoring_case(client: TestClient) -> None:
    assert register(client, "ana@exemplo.com").status_code == 201
    response = register(client, "  ANA@exemplo.COM ")
    assert response.status_code == 409
    assert response.json()["code"] == "email_already_registered"


@pytest.mark.parametrize(
    ("overrides", "field"),
    [
        ({"password": "curta"}, "password"),
        ({"password": "1234567890"}, "password"),
        ({"accept_terms": False}, "accept_terms"),
        ({"email": "sem-arroba"}, "email"),
        ({"display_name": "   "}, "display_name"),
    ],
)
def test_register_validation_errors_point_to_field(
    client: TestClient, overrides: dict, field: str
) -> None:
    response = register(client, **overrides)
    assert response.status_code == 422
    problem = response.json()
    assert problem["code"] == "validation_error"
    assert [e["field"] for e in problem["errors"]] == [field]


def test_register_rejects_unknown_fields(client: TestClient) -> None:
    # Ninguém escolhe o próprio status, id ou dono pelo corpo da requisição.
    response = register(client, status="disabled")
    assert response.status_code == 422
    assert response.json()["errors"][0] == {"field": "status", "message": "Campo não permitido."}


# --- login ---


def test_login_returns_tokens_and_updates_last_login(client: TestClient, db: Session) -> None:
    register(client)
    user = db.scalar(select(User).where(User.email == "ana@exemplo.com"))
    assert user is not None
    user.last_login_at = None
    db.commit()

    response = login(client, email="ANA@exemplo.com")

    assert response.status_code == 200
    assert response.json()["access_token"]
    db.refresh(user)
    assert user.last_login_at is not None


def test_wrong_password_and_unknown_email_get_identical_responses(client: TestClient) -> None:
    register(client)
    wrong_password = login(client, password="senha errada mas longa")
    unknown_email = login(client, email="ninguem@exemplo.com")

    assert wrong_password.status_code == unknown_email.status_code == 401
    assert wrong_password.headers["www-authenticate"] == "Bearer"

    def without_request_id(r):
        return {k: v for k, v in r.json().items() if k != "request_id"}

    assert without_request_id(wrong_password) == without_request_id(unknown_email)
    assert wrong_password.json()["code"] == "invalid_credentials"


def test_disabled_account_cannot_log_in(client: TestClient, db: Session) -> None:
    register(client)
    user = db.scalar(select(User).where(User.email == "ana@exemplo.com"))
    assert user is not None
    user.status = UserStatus.DISABLED
    db.commit()

    response = login(client)
    assert response.status_code == 403
    assert response.json()["code"] == "account_disabled"


# --- /me e access token ---


def test_me_returns_only_the_token_owner(client: TestClient) -> None:
    ana = register(client, "ana@exemplo.com").json()
    bia = register(client, "bia@exemplo.com", display_name="Bia").json()

    me_ana = client.get("/api/v1/me", headers=auth_header(ana["access_token"])).json()
    me_bia = client.get("/api/v1/me", headers=auth_header(bia["access_token"])).json()

    assert me_ana["email"] == "ana@exemplo.com"
    assert me_ana["profile"]["display_name"] == "Ana"
    assert [c["kind"] for c in me_ana["consents"]] == ["terms_privacy"]
    assert me_bia["email"] == "bia@exemplo.com"
    assert me_ana["id"] != me_bia["id"]
    assert "password_hash" not in me_ana


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"Authorization": "Bearer"},
        {"Authorization": "Basic YW5hOnNlbmhh"},
        {"Authorization": "Bearer nao.e.um.jwt"},
    ],
    ids=["sem-cabecalho", "bearer-vazio", "basic", "lixo"],
)
def test_me_requires_valid_bearer_token(client: TestClient, headers: dict) -> None:
    response = client.get("/api/v1/me", headers=headers)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.json()["code"] in {"not_authenticated", "invalid_token"}


def test_me_rejects_expired_access_token(client: TestClient, db: Session) -> None:
    register(client)
    user = db.scalar(select(User).where(User.email == "ana@exemplo.com"))
    assert user is not None
    expired, _ = tokens.create_access_token(
        user.id, get_settings(), now=datetime.now(UTC) - timedelta(hours=1)
    )
    response = client.get("/api/v1/me", headers=auth_header(expired))
    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


def test_refresh_token_is_not_accepted_as_access_token(client: TestClient) -> None:
    pair = register(client).json()
    response = client.get("/api/v1/me", headers=auth_header(pair["refresh_token"]))
    assert response.status_code == 401


def test_access_token_stops_working_when_account_is_disabled(
    client: TestClient, db: Session
) -> None:
    pair = register(client).json()
    user = db.scalar(select(User).where(User.email == "ana@exemplo.com"))
    assert user is not None
    user.status = UserStatus.DISABLED
    db.commit()

    response = client.get("/api/v1/me", headers=auth_header(pair["access_token"]))
    assert response.status_code == 401


# --- refresh: rotação e reutilização ---


def refresh(client: TestClient, refresh_token: str):
    return client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})


def test_refresh_rotates_tokens(client: TestClient) -> None:
    first = register(client).json()
    response = refresh(client, first["refresh_token"])

    assert response.status_code == 200
    second = response.json()
    assert second["refresh_token"] != first["refresh_token"]
    me = client.get("/api/v1/me", headers=auth_header(second["access_token"]))
    assert me.status_code == 200


def test_reusing_rotated_refresh_token_revokes_the_whole_family(client: TestClient) -> None:
    first = register(client).json()
    second = refresh(client, first["refresh_token"]).json()

    # Alguém reapresenta o token antigo (ex.: copiado do aparelho).
    reuse = refresh(client, first["refresh_token"])
    assert reuse.status_code == 401
    assert reuse.json()["code"] == "refresh_token_reused"

    # O token legítimo mais recente também deixa de valer: a sessão inteira foi encerrada.
    after = refresh(client, second["refresh_token"])
    assert after.status_code == 401
    assert after.json()["code"] == "invalid_refresh_token"


def test_reuse_does_not_affect_other_sessions(client: TestClient) -> None:
    phone = register(client).json()
    tablet = login(client).json()  # outra família

    refresh(client, phone["refresh_token"])
    refresh(client, phone["refresh_token"])  # reutilização: derruba só a família do celular

    assert refresh(client, tablet["refresh_token"]).status_code == 200


def test_expired_refresh_token_is_rejected(client: TestClient, db: Session) -> None:
    pair = register(client).json()
    stored = db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == tokens.hash_refresh_token(pair["refresh_token"])
        )
    )
    assert stored is not None
    stored.expires_at = datetime.now(UTC) - timedelta(seconds=1)
    db.commit()

    response = refresh(client, pair["refresh_token"])
    assert response.status_code == 401
    assert response.json()["code"] == "invalid_refresh_token"


def test_unknown_refresh_token_is_rejected(client: TestClient) -> None:
    response = refresh(client, "token-que-nunca-existiu")
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


# --- logout ---


def test_logout_revokes_session_and_is_idempotent(client: TestClient) -> None:
    pair = register(client).json()

    first = client.post("/api/v1/auth/logout", json={"refresh_token": pair["refresh_token"]})
    second = client.post("/api/v1/auth/logout", json={"refresh_token": pair["refresh_token"]})
    unknown = client.post("/api/v1/auth/logout", json={"refresh_token": "desconhecido"})

    assert first.status_code == second.status_code == unknown.status_code == 204
    assert refresh(client, pair["refresh_token"]).status_code == 401


# --- limite de tentativas ---


def test_login_is_blocked_after_repeated_failures_even_with_right_password(
    client: TestClient,
) -> None:
    register(client)
    for _ in range(5):
        assert login(client, password="senha errada mas longa").status_code == 401

    blocked = login(client)
    assert blocked.status_code == 429
    assert blocked.json()["code"] == "too_many_requests"
    assert int(blocked.headers["retry-after"]) > 0

    # Outra conta não é afetada pelo bloqueio da primeira.
    register(client, "bia@exemplo.com")
    assert login(client, email="bia@exemplo.com").status_code == 200


def test_successful_login_clears_failure_count(client: TestClient) -> None:
    register(client)
    for _ in range(4):
        login(client, password="senha errada mas longa")
    assert login(client).status_code == 200
    for _ in range(4):
        login(client, password="senha errada mas longa")
    assert login(client).status_code == 200


def test_register_is_limited_per_ip(client: TestClient) -> None:
    for i in range(5):
        assert register(client, f"pessoa{i}@exemplo.com").status_code == 201
    response = register(client, "pessoa9@exemplo.com")
    assert response.status_code == 429


# --- privacidade dos logs ---


def test_logs_never_contain_passwords_or_tokens(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    pair = register(client).json()
    login(client, password="senha errada mas longa")
    refresh(client, pair["refresh_token"])
    refresh(client, pair["refresh_token"])  # reutilização gera log de alerta

    text = caplog.text + "".join(str(vars(r)) for r in caplog.records)
    assert PASSWORD not in text
    assert "senha errada mas longa" not in text
    assert pair["refresh_token"] not in text
    assert pair["access_token"] not in text
    assert "ana@exemplo.com" not in text
