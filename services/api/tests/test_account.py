"""Direitos do titular (5.6, ADR-063): exportar tudo e excluir a conta com a senha."""

# ruff: noqa: F811  (a fixture two_people vem de test_ai_tools)
import json

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.base import Base
from app.modules.users import account
from app.modules.users.models import User
from tests.test_ai_tools import (
    two_people,  # noqa: F401  (fixture)
    user_of,
)
from tests.test_analytics import ok

API = "/api/v1"
PASSWORD = "cavalo bateria grampo"


def login(client: TestClient, email: str) -> dict:
    tokens = ok(client.post(f"{API}/auth/login", json={"email": email, "password": PASSWORD}))
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def owned_rows(db: Session, user_id) -> dict[str, int]:
    """Quantas linhas cada tabela com `user_id`/`owner_user_id` ainda tem da pessoa."""
    counts = {}
    for table in Base.metadata.sorted_tables:
        column = table.c.get("user_id") if "user_id" in table.c else table.c.get("owner_user_id")
        if column is not None:
            counts[table.name] = db.scalar(
                select(func.count()).select_from(table).where(column == user_id)
            )
    return counts


def test_export_covers_every_table() -> None:
    planned = {name for name, _ in account.EXPORT_PLAN}
    assert planned.isdisjoint(account.NOT_EXPORTED)
    # Tabela nova precisa ser exportada ou ficar de fora de propósito.
    assert planned | account.NOT_EXPORTED == set(Base.metadata.tables)


def test_export_has_everything_of_the_person_and_nothing_else(
    client: TestClient, db: Session, two_people
) -> None:
    ana = two_people["ana"]
    bia = login(client, "bia@exemplo.com")
    ok(
        client.post(
            f"{API}/goals",
            headers=bia,
            json={"kind": "custom", "title": "Meta da Bia", "target": {"description": "x"}},
        ),
        201,
    )

    response = client.get(f"{API}/me/export", headers=ana)
    assert response.status_code == 200
    assert response.headers["content-disposition"].startswith('attachment; filename="evofit-dados-')
    assert response.headers["cache-control"] == "no-store"
    body = response.json()
    assert (body["format"], body["version"]) == ("evofit-export", 1)
    assert body["account"]["email"] == "ana@exemplo.com"

    data = body["data"]
    assert len(data["workout_sessions"]) == 1
    assert len(data["set_entries"]) >= 2
    assert len(data["activities"]) == 4  # o treino e as três atividades
    assert len(data["endurance_details"]) == 3
    assert [g["title"] for g in data["goals"]] == ["Correr 10 km"]
    assert len(data["exercises"]) == 1  # só o próprio, não o catálogo
    assert len(data["meals"]) == 2 and len(data["meal_items"]) == 3
    assert len(data["foods"]) == 2
    assert data["nutrition_targets"][0]["kcal"] == 2000
    assert len(data["body_measurements"]) == 5
    assert data["user_profiles"][0]["limitations_note"] == "Dor no joelho ao agachar fundo"
    assert {c["kind"] for c in data["user_consents"]} >= {"terms_privacy", "health_data"}

    text = json.dumps(body)
    # Credenciais nunca saem; nada da outra conta aparece.
    assert "password_hash" not in text and "token_hash" not in text and "$argon2" not in text
    assert "refresh_tokens" not in data
    assert "Meta da Bia" not in text and "bia@exemplo.com" not in text
    bia_id = str(user_of(db, "bia@exemplo.com").id)
    assert bia_id not in text


def test_export_of_an_empty_account(client: TestClient, two_people) -> None:
    body = ok(client.get(f"{API}/me/export", headers=login(client, "bia@exemplo.com")))
    assert body["data"]["workout_sessions"] == []
    assert body["data"]["set_entries"] == []
    assert len(body["data"]["user_profiles"]) == 1


def test_export_needs_a_token_and_has_a_limit(client: TestClient, two_people) -> None:
    assert client.get(f"{API}/me/export").status_code == 401
    bia = login(client, "bia@exemplo.com")
    for _ in range(10):
        assert client.get(f"{API}/me/export", headers=bia).status_code == 200
    blocked = client.get(f"{API}/me/export", headers=bia)
    assert blocked.status_code == 429
    assert "retry-after" in blocked.headers


def test_deleting_the_account_removes_everything(
    client: TestClient, db: Session, two_people
) -> None:
    ana = two_people["ana"]
    ana_id = user_of(db, "ana@exemplo.com").id
    bia_id = user_of(db, "bia@exemplo.com").id
    bia = login(client, "bia@exemplo.com")
    ok(
        client.post(
            f"{API}/goals",
            headers=bia,
            json={"kind": "custom", "title": "Meta da Bia", "target": {"description": "x"}},
        ),
        201,
    )
    assert sum(owned_rows(db, ana_id).values()) > 20
    bia_before = owned_rows(db, bia_id)

    # Senha errada: nada muda.
    wrong = client.request("DELETE", f"{API}/me", headers=ana, json={"password": "outra senha"})
    assert wrong.status_code == 422
    assert wrong.json()["errors"][0] == {"field": "password", "message": "Senha incorreta."}
    assert ok(client.get(f"{API}/me", headers=ana))["email"] == "ana@exemplo.com"

    response = client.request("DELETE", f"{API}/me", headers=ana, json={"password": PASSWORD})
    assert response.status_code == 204

    db.expire_all()
    assert set(owned_rows(db, ana_id).values()) == {0}
    assert user_of_or_none(db, "ana@exemplo.com") is None
    # O token deixa de valer e o login também.
    assert client.get(f"{API}/me", headers=ana).status_code == 401
    failed = client.post(
        f"{API}/auth/login", json={"email": "ana@exemplo.com", "password": PASSWORD}
    )
    assert failed.status_code == 401
    # A outra conta continua inteira.
    assert owned_rows(db, bia_id) == bia_before
    assert ok(client.get(f"{API}/goals", headers=bia))[0]["title"] == "Meta da Bia"


def test_wrong_passwords_are_limited(client: TestClient, two_people) -> None:
    ana = two_people["ana"]
    for _ in range(5):
        response = client.request(
            "DELETE", f"{API}/me", headers=ana, json={"password": "outra senha"}
        )
        assert response.status_code == 422
    blocked = client.request("DELETE", f"{API}/me", headers=ana, json={"password": PASSWORD})
    # Até a senha certa espera a janela: quem adivinha não tem mais tentativas.
    assert blocked.status_code == 429
    assert ok(client.get(f"{API}/me", headers=ana))["email"] == "ana@exemplo.com"


def test_delete_needs_the_password_field(client: TestClient, two_people) -> None:
    ana = two_people["ana"]
    assert client.request("DELETE", f"{API}/me", headers=ana, json={}).status_code == 422
    assert client.request("DELETE", f"{API}/me", headers=ana).status_code == 422
    extra = {"password": PASSWORD, "user_id": "outro"}
    assert client.request("DELETE", f"{API}/me", headers=ana, json=extra).status_code == 422


def user_of_or_none(db: Session, email: str) -> User | None:
    return db.scalar(select(User).where(User.email == email))
