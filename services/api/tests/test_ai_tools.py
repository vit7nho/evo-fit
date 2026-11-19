"""Ferramentas de leitura da IA (4.2): cada uma só enxerga os dados do usuário do
contexto, recusa `user_id` vindo do modelo, respeita os limites e devolve JSON."""

import json
import logging
from datetime import date

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.integrations.ai.provider import ToolCall
from app.modules.ai_coach.tools import base, registry
from app.modules.ai_coach.tools.base import ToolContext
from app.modules.users.models import User
from tests.conftest import Clock
from tests.test_analytics import activity, ok, strength_session
from tests.test_exercises import CUSTOM
from tests.test_sessions import start, template

API = "/api/v1"
OCT = {"from_date": "2026-10-01", "to_date": "2026-11-01"}


@pytest.fixture(autouse=True)
def fixed_today(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(base, "today", lambda user: date(2026, 11, 1))


def user_of(db: Session, email: str) -> User:
    user = db.scalar(select(User).where(User.email == email))
    assert user is not None
    return user


def run(db: Session, email: str, tool: str, **arguments):
    """Executa como o usuário `email`; devolve (resultado, é erro)."""
    result = registry.execute(ToolContext(db, user_of(db, email)), ToolCall("c1", tool, arguments))
    return json.loads(result.content), result.is_error


def data(db: Session, email: str, tool: str, **arguments) -> dict:
    body, is_error = run(db, email, tool, **arguments)
    assert not is_error, body
    return body


@pytest.fixture
def two_people(client: TestClient, signup, clock: Clock) -> dict:
    """Ana com treino, corrida, meta, exercício próprio e perfil; Bia sem nada."""
    ana = signup("ana@exemplo.com", "Ana")
    signup("bia@exemplo.com", "Bia")
    ok(client.put(f"{API}/me/consents/health_data", headers=ana))
    ok(
        client.patch(
            f"{API}/me",
            headers=ana,
            json={
                "primary_objective": "gain_muscle",
                "preferred_modalities": ["strength", "run"],
                "equipment": ["dumbbells"],
                "limitation_tags": ["knee"],
                "limitations_note": "Dor no joelho ao agachar fundo",
            },
        )
    )
    session = strength_session(client, ana, clock)  # 01/11: supino, 2 séries, 1200 kg
    activity(client, ana, "2026-10-28", distance_m=5000)
    activity(client, ana, "2026-10-29", modality="walk", duration_s=2400, distance_m=3000)
    activity(client, ana, "2026-10-30", distance_m=6000, duration_s=2100)
    ok(
        client.post(
            f"{API}/goals",
            headers=ana,
            json={
                "kind": "run_distance",
                "title": "Correr 10 km",
                "target": {"distance_km": 10},
                "start_date": "2026-10-01",
            },
        ),
        201,
    )
    ok(client.post(f"{API}/exercises", headers=ana, json=CUSTOM), 201)
    return {"session_id": session["id"], "ana": ana}


# --- catálogo ---


def test_every_tool_has_a_closed_schema_without_user_id() -> None:
    specs = registry.specs()
    assert len(specs) == 11
    for spec in specs:
        assert spec.description and spec.description[0].isupper()
        assert spec.input_schema["type"] == "object"
        assert spec.input_schema.get("additionalProperties") is False
        assert "user_id" not in json.dumps(spec.input_schema)
    assert [s.name for s in registry.specs(["get_goals"])] == ["get_goals"]


# --- validação no executor ---


def test_user_id_from_the_model_is_refused(db: Session, two_people) -> None:
    ana = user_of(db, "ana@exemplo.com")
    for tool in ("get_goals", "get_workout_history", "get_activities"):
        body, is_error = run(db, "bia@exemplo.com", tool, user_id=str(ana.id))
        assert is_error
        assert "user_id: campo não aceito" in body["error"]


def test_bad_calls_come_back_as_explained_errors(db: Session, two_people) -> None:
    cases = [
        ("delete_everything", {}, "Ferramenta desconhecida"),
        ("get_workout_history", {"limit": 50}, "limit"),
        ("get_activities", {"from_date": "2025-01-01", "to_date": "2026-11-01"}, "366"),
        ("get_activities", {"from_date": "2026-11-02", "to_date": "2026-11-01"}, "depois"),
        ("get_exercise_history", {}, "exercise_id ou name"),
        ("get_muscle_stimulus", {"muscle_ids": ["coracao"]}, "desconhecido"),
        ("search_exercises", {"muscle_id": "coracao"}, "desconhecido"),
        (
            "compare_periods",
            {"metric": "distance_m", "period_a": OCT, "period_b": OCT},
            "modalidade",
        ),
    ]
    for tool, arguments, expected in cases:
        body, is_error = run(db, "ana@exemplo.com", tool, **arguments)
        assert is_error, tool
        assert expected in body["error"], (tool, body)


def test_logs_name_the_tool_but_never_the_arguments(db: Session, two_people, caplog) -> None:
    with caplog.at_level(logging.INFO):
        run(db, "ana@exemplo.com", "get_exercise_history", name="segredo pessoal xyz")
    records = [r for r in caplog.records if r.getMessage() == "ai_tool_executed"]
    assert [(r.tool, r.outcome) for r in records] == [("get_exercise_history", "tool_error")]
    assert "segredo pessoal" not in caplog.text


# --- escopo: cada ferramenta só vê a própria pessoa ---


def test_workouts_are_scoped_to_the_owner(db: Session, two_people) -> None:
    mine = data(db, "ana@exemplo.com", "get_workout_history", **OCT)
    assert mine["total_sessions"] == 1
    assert (mine["items"][0]["sets"], mine["items"][0]["volume_kg"]) == (2, 1200)
    assert data(db, "bia@exemplo.com", "get_workout_history", **OCT)["total_sessions"] == 0

    session_id = two_people["session_id"]
    detail = data(db, "ana@exemplo.com", "get_session_detail", session_id=session_id)
    sets = detail["exercises"][0]["sets"]
    assert [s["kind"] for s in sets] == ["warmup", "working", "drop", "working"]
    assert [s["segment"] for s in sets] == [False, False, True, False]
    # O treino da Ana, pedido pela Bia: não encontrado (como na API).
    body, is_error = run(db, "bia@exemplo.com", "get_session_detail", session_id=session_id)
    assert is_error and "não encontrado" in body["error"].lower()


def test_current_session_and_exercise_history(client: TestClient, db: Session, two_people) -> None:
    ana = two_people["ana"]
    start(client, ana, template_id=template(client, ana)["id"])
    current = data(db, "ana@exemplo.com", "get_current_session")["session"]
    assert current["status"] == "in_progress"
    assert data(db, "bia@exemplo.com", "get_current_session")["session"] is None

    history = data(db, "ana@exemplo.com", "get_exercise_history", name="supino reto com BARRA")
    assert history["exercise"]["name"] == "Supino reto com barra"
    assert len(history["sessions"]) == 1
    assert history["e1rm_trend"]["last"]["kg"] == 76  # 60 kg vezes 8 repetições: Epley
    assert "estimativa" in history["e1rm_trend"]["note"]
    # Bia vê o exercício do catálogo, mas nenhum treino dela.
    empty = data(db, "bia@exemplo.com", "get_exercise_history", name="supino reto com barra")
    assert empty["sessions"] == [] and empty["records"] == []
    # O exercício próprio da Ana não existe para a Bia.
    custom = data(db, "ana@exemplo.com", "search_exercises", query="TRX", only_my_equipment=False)
    custom_id = custom["items"][0]["exercise_id"]
    body, is_error = run(db, "bia@exemplo.com", "get_exercise_history", exercise_id=custom_id)
    assert is_error and "não encontrado" in body["error"].lower()


def test_analytics_tools_are_scoped(db: Session, two_people) -> None:
    ana = data(db, "ana@exemplo.com", "get_muscle_stimulus", muscle_ids=["chest"], **OCT)
    chest = next(m for m in ana["muscles"] if m["muscle_id"] == "chest")
    assert chest["weighted_sets_per_week"] > 0
    assert ana["details"][0]["exercises"][0]["name"] == "Supino reto com barra"
    assert "não diagnóstico" in ana["notice"]
    bia = data(db, "bia@exemplo.com", "get_muscle_stimulus", **OCT)
    assert {m["band"] for m in bia["muscles"]} == {"none"}

    a = {"from_date": "2026-10-01", "to_date": "2026-10-15"}
    b = {"from_date": "2026-10-16", "to_date": "2026-11-01"}
    compared = data(
        db, "ana@exemplo.com", "compare_periods", metric="sessions", period_a=a, period_b=b
    )
    assert (compared["a"]["value"], compared["b"]["value"], compared["percent"]) == (0, 4, None)
    nothing = data(
        db, "bia@exemplo.com", "compare_periods", metric="sessions", period_a=a, period_b=b
    )
    assert nothing["b"]["value"] == 0

    run_ = data(db, "ana@exemplo.com", "get_endurance_progress", modality="run", **OCT)
    assert (run_["distance_m"], run_["sessions"]) == (11000, 2)
    assert (
        data(db, "bia@exemplo.com", "get_endurance_progress", modality="run", **OCT)["distance_m"]
        == 0
    )


def test_activities_are_scoped_truncated_and_never_estimated(db: Session, two_people) -> None:
    listed = data(db, "ana@exemplo.com", "get_activities", **OCT)
    assert [a["modality"] for a in listed["items"]] == ["run", "walk", "run"]
    walk = listed["items"][1]
    # A caminhada não teve FC nem esforço: nulos, não inventados.
    assert (walk["avg_hr"], walk["perceived_effort"]) == (None, None)
    assert listed["items"][0]["pace_s_per_km"] == 350  # 35 min em 6 km
    cut = data(db, "ana@exemplo.com", "get_activities", limit=2, **OCT)
    assert (len(cut["items"]), cut["truncated"]) == (2, True)
    runs = data(db, "ana@exemplo.com", "get_activities", modality="run", **OCT)
    assert len(runs["items"]) == 2
    assert data(db, "bia@exemplo.com", "get_activities", **OCT)["items"] == []


def test_goals_profile_and_search_are_scoped(db: Session, two_people) -> None:
    goals = data(db, "ana@exemplo.com", "get_goals")["items"]
    assert [g["title"] for g in goals] == ["Correr 10 km"]
    assert (goals[0]["progress"]["current"], goals[0]["progress"]["unit"]) == (6, "km")
    assert data(db, "bia@exemplo.com", "get_goals")["items"] == []

    profile = data(db, "ana@exemplo.com", "get_profile_summary")
    assert profile["primary_objective"] == "Ganhar massa muscular"
    assert profile["limitation_tags"] == ["Joelho"]
    assert "limitations_note" not in profile
    text = json.dumps(profile, ensure_ascii=False)
    for private in ("Ana", "ana@exemplo.com"):
        assert private not in text
    with_note = data(db, "ana@exemplo.com", "get_profile_summary", include_limitations_note=True)
    assert with_note["limitations_note"] == "Dor no joelho ao agachar fundo"
    bia = data(db, "bia@exemplo.com", "get_profile_summary", include_limitations_note=True)
    assert bia.get("limitations_note") is None

    # Ana tem só halteres: a busca filtra pelo equipamento dela (e o próprio dela aparece).
    back = data(db, "ana@exemplo.com", "search_exercises", muscle_id="lats")
    assert back["equipment_filter"] == ["bodyweight", "dumbbells"]
    assert "Remada no TRX" in [e["name"] for e in back["items"]]
    assert all(e["equipment"] in {"Halteres", "Sem equipamento"} for e in back["items"])
    assert "Remada no TRX" not in [
        e["name"]
        for e in data(db, "bia@exemplo.com", "search_exercises", muscle_id="lats")["items"]
    ]


def test_every_tool_returns_valid_json_for_an_empty_account(db: Session, two_people) -> None:
    calls = {
        "get_profile_summary": {},
        "get_goals": {"status": None},
        "get_workout_history": {},
        "get_current_session": {},
        "get_exercise_history": {"name": "agachamento livre"},
        "get_muscle_stimulus": {},
        "compare_periods": {"metric": "duration_s", "period_a": OCT, "period_b": OCT},
        "get_activities": {},
        "get_endurance_progress": {"modality": "swim"},
        "search_exercises": {"query": "rosca"},
    }
    assert set(calls) | {"get_session_detail"} == set(registry.TOOLS)
    for tool, arguments in calls.items():
        body, is_error = run(db, "bia@exemplo.com", tool, **arguments)
        assert not is_error, (tool, body)
        assert isinstance(body, dict)
