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
from tests.test_nutrition import ARROZ, FRANGO
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


def eat_and_weigh(client: TestClient, headers: dict, monkeypatch: pytest.MonkeyPatch) -> None:
    """Refeições em 30 e 31/10, metas desde 25/10 e pesos semanais de 04/10 a 01/11 (5.4)."""
    from app.modules.nutrition import service as nutrition_service

    arroz = ok(client.post(f"{API}/foods", headers=headers, json=ARROZ), 201)
    frango = ok(client.post(f"{API}/foods", headers=headers, json=FRANGO), 201)
    for at, items in (
        # 256 + 238,5 = 494,5 kcal; 5 + 48 = 53 g de proteína.
        (
            "2026-10-30T12:30:00",
            [
                {"food_id": arroz["id"], "quantity_g": 200},
                {"food_id": frango["id"], "quantity_g": 150},
            ],
        ),
        # 318 kcal; 64 g de proteína.
        ("2026-10-31T13:00:00", [{"food_id": frango["id"], "quantity_g": 200}]),
    ):
        body = {"eaten_at": at, "meal_type": "lunch", "items": items}
        ok(client.post(f"{API}/meals", headers=headers, json=body), 201)
    monkeypatch.setattr(nutrition_service, "_today", lambda user: date(2026, 10, 25))
    targets = {"kcal": 2000, "protein_g": 120}
    ok(client.put(f"{API}/nutrition/targets", headers=headers, json=targets))
    for day, weight, waist in (
        ("2026-10-04", 80.0, 86),
        ("2026-10-11", 79.5, None),
        ("2026-10-18", 79.2, None),
        ("2026-10-25", 78.6, None),
        ("2026-11-01", 78.0, 84.5),
    ):
        body = {"measured_at": f"{day}T07:00:00", "weight_kg": weight, "waist_cm": waist}
        ok(client.post(f"{API}/body-measurements", headers=headers, json=body), 201)


@pytest.fixture
def two_people(client: TestClient, signup, clock: Clock, monkeypatch: pytest.MonkeyPatch) -> dict:
    """Ana com treino, corrida, meta, exercício próprio, perfil, refeições, metas
    nutricionais e pesos; Bia sem nada."""
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
    eat_and_weigh(client, ana, monkeypatch)
    return {"session_id": session["id"], "ana": ana}


# --- catálogo ---


def test_every_tool_has_a_closed_schema_without_user_id() -> None:
    specs = registry.specs()
    assert len(specs) == 15  # 11 de leitura (4.2), get_templates e a proposta (4.6),
    # nutrição e corpo (5.4)
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
    # get_templates vem na 4.6 (testada em test_ai_proposals); a proposta muda dados.
    calls["get_templates"] = {}
    calls["get_nutrition_summary"] = {}
    calls["get_body_trend"] = {}
    assert set(calls) | {"get_session_detail", "prepare_change_proposal"} == set(registry.TOOLS)
    for tool, arguments in calls.items():
        body, is_error = run(db, "bia@exemplo.com", tool, **arguments)
        assert not is_error, (tool, body)
        assert isinstance(body, dict)


# --- alimentação, peso e medidas (5.4) ---


def test_nutrition_summary_is_scoped_and_only_numbers(db: Session, two_people) -> None:
    # Padrão: os últimos 7 dias até hoje (01/11).
    week = data(db, "ana@exemplo.com", "get_nutrition_summary")
    assert (week["from_date"], week["to_date"]) == ("2026-10-26", "2026-11-01")
    assert (week["total_days"], week["logged_days"]) == (7, 2)
    # (494,5 + 318) / 2 e (53 + 64) / 2.
    assert week["daily_average"]["kcal"] == 406.2  # 406,25 arredondado
    assert week["daily_average"]["protein_g"] == 58.5
    assert week["targets_now"]["kcal"] == 2000
    assert [d["date"] for d in week["days"]] == ["2026-10-30", "2026-10-31"]
    assert week["days"][0]["totals"]["kcal"] == 494.5
    assert week["days"][0]["targets"]["protein_g"] == 120
    # Nada de nomes de alimentos (só números).
    assert "Arroz" not in json.dumps(week) and "frango" not in json.dumps(week).lower()

    empty = data(db, "bia@exemplo.com", "get_nutrition_summary")
    assert (empty["logged_days"], empty["daily_average"], empty["targets_now"]) == (0, None, None)
    assert empty["days"] == []

    body, is_error = run(
        db, "ana@exemplo.com", "get_nutrition_summary", from_date="2026-01-01", to_date="2026-11-01"
    )
    assert is_error and "92 dias" in body["error"]


def test_body_trend_is_scoped(db: Session, two_people) -> None:
    trend = data(db, "ana@exemplo.com", "get_body_trend")
    assert (trend["label"], trend["unit"], trend["estimate"]) == ("Peso", "kg", False)
    # Padrão: os últimos 90 dias até hoje.
    assert trend["to_date"] == "2026-11-01"
    assert [p["value"] for p in trend["points"]] == [80, 79.5, 79.2, 78.6, 78]
    assert (trend["change"], trend["min"], trend["max"]) == (-2, 78, 80)
    assert trend["weekly_rate"] == pytest.approx(-0.5, abs=0.05)
    assert trend["recorded_metrics"] == ["weight_kg", "waist_cm"]

    waist = data(db, "ana@exemplo.com", "get_body_trend", metric="waist_cm")
    assert (waist["first"]["value"], waist["last"]["value"], waist["change"]) == (86, 84.5, -1.5)

    empty = data(db, "bia@exemplo.com", "get_body_trend")
    assert (empty["points"], empty["last"], empty["recorded_metrics"]) == ([], None, [])
    body, is_error = run(db, "ana@exemplo.com", "get_body_trend", metric="height")
    assert is_error and "metric" in body["error"]


# Plano gratuito do provedor (ADR-056).


def test_free_tier_never_sends_the_limitations_text(db, two_people) -> None:
    def profile(withhold: bool) -> dict:
        ctx = ToolContext(db, user_of(db, "ana@exemplo.com"), withhold_health_notes=withhold)
        call = ToolCall("c1", "get_profile_summary", {"include_limitations_note": True})
        return json.loads(registry.execute(ctx, call).content)

    assert profile(False)["limitations_note"] == "Dor no joelho ao agachar fundo"
    withheld = profile(True)
    assert withheld["limitations_note"] is None
    assert "plano gratuito" in withheld["limitations_note_status"]
    assert withheld["limitation_tags"] == ["Joelho"]  # as etiquetas continuam
    assert "joelho ao agachar" not in json.dumps(withheld, ensure_ascii=False)
