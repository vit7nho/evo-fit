"""Conta de demonstração (Fase 6, ADR-065): o seed passa pelas rotas da API e termina hoje."""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import demo_seed
from app.core.config import Environment, get_settings
from app.modules.users.models import User
from tests.test_analytics import ok

API = "/api/v1"
PASSWORD = "abacate barco cadeira dente"
SP = ZoneInfo("America/Sao_Paulo")


@pytest.fixture
def demo(app: FastAPI, client: TestClient, db: Session) -> dict:
    result = demo_seed.seed(app, db, PASSWORD)
    tokens = ok(
        client.post(f"{API}/auth/login", json={"email": demo_seed.EMAIL, "password": PASSWORD})
    )
    return {"result": result, "headers": {"Authorization": f"Bearer {tokens['access_token']}"}}


def get(client: TestClient, demo: dict, path: str, **params) -> dict | list:
    return ok(client.get(f"{API}{path}", headers=demo["headers"], params=params))


def test_profile_and_consents(client: TestClient, demo: dict) -> None:
    me = get(client, demo, "/me")
    assert me["profile"]["display_name"] == "Demo"
    assert me["profile"]["primary_objective"] == "gain_muscle"
    assert {"health_data", "ai_processing"} <= {c["kind"] for c in me["consents"]}


def test_eight_weeks_of_training_end_yesterday(client: TestClient, demo: dict) -> None:
    items, before = [], None
    while True:  # o histórico vem em páginas de até 50
        page = get(
            client, demo, "/workout-sessions", limit=50, **({"before": before} if before else {})
        )
        items += page["items"]
        if not (before := page.get("next_before")):
            break
    # 3 treinos por semana em 8 semanas, menos os dois dias pulados.
    assert len(items) == 3 * demo_seed.WEEKS - 2
    today = datetime.now(SP).date()
    newest = max(datetime.fromisoformat(s["started_at"]).astimezone(SP).date() for s in items)
    assert today - timedelta(days=7) <= newest < today
    records = get(client, demo, "/analytics/records")
    assert records, "a progressão de carga gera recordes"


def test_body_map_shows_what_was_trained_less(client: TestClient, demo: dict) -> None:
    muscles = get(client, demo, "/analytics/muscles", period="30d")["muscles"]
    by_sets = sorted(muscles, key=lambda m: m["weighted_sets"])
    # Panturrilhas não têm exercício próprio nas fichas: ficam entre as menos treinadas.
    assert "Panturrilhas" in {m["name"] for m in by_sets[:2]}
    assert {m["band"] for m in muscles} >= {"low", "mid"}


def test_plan_nutrition_body_and_goals(client: TestClient, demo: dict) -> None:
    plans = get(client, demo, "/training-plans")
    active = [p for p in plans if p["status"] == "active"]
    assert len(active) == 1
    # Tudo o que passou do plano foi feito (3 corridas por semana há ~3 semanas): a
    # próxima sessão é a de hoje ou a seguinte, não uma atrasada.
    assert 6 <= active[0]["completed_sessions"] <= 9
    plan = get(client, demo, f"/training-plans/{active[0]['id']}")
    pending = [s for s in plan["sessions"] if not s["completed_activity_id"]]
    assert pending[0]["scheduled_date"] >= datetime.now(SP).date().isoformat()

    summary = get(client, demo, "/nutrition/summary")
    assert summary["logged_days"] == 7
    # Média de 6 dias completos (~2.650 kcal) e de hoje, só com o café da manhã.
    assert 2200 < summary["average"]["kcal"] < 2800
    assert get(client, demo, "/nutrition/targets")["current"]["kcal"] == 2600

    measurements = get(client, demo, "/body-measurements", days=90)
    weights = [m["weight_kg"] for m in measurements if m["weight_kg"]]
    assert len(weights) == demo_seed.WEEKS
    assert max(weights) > min(weights)

    goals = get(client, demo, "/goals")
    assert {g["status"] for g in goals} == {"active", "achieved"}

    dashboard = get(client, demo, "/dashboard")
    assert dashboard["focus"], "o Início tem o que mostrar"


def test_running_again_replaces_only_the_demo_account(
    app: FastAPI, client: TestClient, db: Session, demo: dict, signup
) -> None:
    signup("ana@exemplo.com", "Ana")
    result = demo_seed.seed(app, db, "outra frase bem comprida")
    assert result["replaced"] is True
    emails = db.scalars(select(User.email)).all()
    assert sorted(emails) == ["ana@exemplo.com", demo_seed.EMAIL]
    login = {"email": demo_seed.EMAIL, "password": PASSWORD}
    assert client.post(f"{API}/auth/login", json=login).status_code == 401
    assert db.scalar(select(func.count()).select_from(User)) == 2


def test_refuses_production(app: FastAPI, db: Session, monkeypatch: pytest.MonkeyPatch) -> None:
    settings = get_settings().model_copy(update={"app_env": Environment.PRODUCTION})
    monkeypatch.setattr(demo_seed, "get_settings", lambda: settings)
    with pytest.raises(demo_seed.SeedError, match="production"):
        demo_seed.seed(app, db, PASSWORD)
    assert db.scalar(select(func.count()).select_from(User)) == 0


def test_generated_passphrase_has_four_words() -> None:
    words = demo_seed.passphrase().split()
    assert len(words) == 4 and all(w in demo_seed.WORDS for w in words)
