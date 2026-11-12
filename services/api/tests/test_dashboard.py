"""Painel do Início (3.8): foco pelo objetivo, semana, metas com progresso e último
registro, sempre só com os dados do dono do token."""

from datetime import date

import pytest
from fastapi.testclient import TestClient

from app.modules.dashboard import router as dashboard_router
from app.modules.dashboard import rules
from tests.conftest import Clock
from tests.test_analytics import activity, ok, strength_session

API = "/api/v1"
# Domingo: a semana em curso vai de 26/10 a 01/11; o treino do relógio é 01/11.
TODAY = date(2026, 11, 1)


@pytest.fixture(autouse=True)
def fixed_today(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(dashboard_router, "_today", lambda user: TODAY)


def dashboard(client: TestClient, headers: dict) -> dict:
    return ok(client.get(f"{API}/dashboard", headers=headers))


def profile(client: TestClient, headers: dict, **fields) -> None:
    ok(client.patch(f"{API}/me", headers=headers, json=fields))


def goal(client: TestClient, headers: dict, kind: str, target: dict, priority: int = 2) -> dict:
    body = {
        "kind": kind,
        "title": f"Meta {kind}",
        "target": target,
        "start_date": "2026-10-01",
        "priority": priority,
    }
    return ok(client.post(f"{API}/goals", headers=headers, json=body), 201)


# --- regras puras ---


@pytest.mark.parametrize(
    ("objective", "preferred", "recorded", "plan", "expected"),
    [
        # Musculação primeiro para quem quer ganhar massa, com o Meu Corpo junto.
        (
            "gain_muscle",
            ["walk", "strength"],
            {},
            False,
            ["strength", "body", "endurance:walk"],
        ),
        # Registradas sem estar no perfil entram depois, as mais frequentes antes.
        (
            "maintain",
            ["cycle"],
            {"run": 1, "swim": 3},
            True,
            ["endurance:cycle", "endurance:swim", "endurance:run", "plan"],
        ),
        # Quem quer correr vê o plano e a corrida no topo, mesmo sem corrida no perfil.
        (
            "run",
            ["strength"],
            {},
            True,
            ["plan", "endurance:run", "strength", "body"],
        ),
        ("walk_habit", [], {}, False, ["endurance:walk"]),
        # Funcional ainda não tem análise: não vira cartão.
        (None, ["functional"], {}, False, []),
    ],
)
def test_focus_order(objective, preferred, recorded, plan, expected) -> None:
    assert rules.focus_order(objective, preferred, recorded, plan) == expected


def test_progress_rules() -> None:
    start = date(2026, 10, 1)
    strength = rules.progress(
        "strength", {"exercise": "Supino", "load_kg": 80, "reps": 8}, rules.GoalFacts(60), start
    )
    assert strength is not None
    assert (strength.current, strength.ratio, strength.achieved) == (60, 0.75, False)
    assert "8+ repetições desde 01/10/2026" in strength.basis

    # Tempo: menor é melhor; 27:30 para um alvo de 25:00 é 90,9%.
    run_time = rules.progress(
        "run_time",
        {"distance_km": 5, "time_s": 1500},
        rules.GoalFacts(best_pace_s_per_km=330),
        start,
    )
    assert run_time is not None
    assert (run_time.current, run_time.ratio, run_time.achieved) == (1650, 0.9091, False)
    assert run_time.lower_is_better

    # Sem registro que meça, o progresso fica nulo (não 0%).
    empty = rules.progress("run_distance", {"distance_km": 10}, rules.GoalFacts(), start)
    assert empty is not None
    assert (empty.current, empty.ratio, empty.achieved) == (None, None, False)
    assert (
        rules.progress("habit", {"description": "x", "days_per_week": 3}, rules.GoalFacts(), start)
        is None
    )
    assert rules.progress("custom", {}, rules.GoalFacts(), start) is None


# --- API ---


def test_new_account_gets_an_empty_dashboard(client: TestClient, signup) -> None:
    body = dashboard(client, signup())

    assert body["objective"] is None
    assert body["today"] == "2026-11-01"
    assert body["week"] == {
        "from_date": "2026-10-26",
        "to_date": "2026-11-01",
        "sessions": 0,
        "active_days": 0,
        "duration_s": 0,
        "weekly_target": None,
        "previous_sessions": 0,
        "previous_active_days": 0,
        "streak_weeks": 0,
    }
    assert body["focus"] == []
    assert body["goals"] == []
    assert body["active_goals"] == 0
    assert body["last_record"] is None


def test_dashboard_follows_the_objective(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    profile(
        client,
        headers,
        primary_objective="gain_muscle",
        preferred_modalities=["strength", "walk"],
        weekly_availability={"days_per_week": 3, "minutes_per_session": 45},
    )
    strength_session(client, headers, clock)  # 01/11: 2 séries, 1200 kg
    activity(client, headers, "2026-10-30", distance_m=5000)  # corrida, fora do perfil
    activity(client, headers, "2026-10-20", modality="walk", duration_s=2400, distance_m=3000)

    body = dashboard(client, headers)

    assert (body["objective"], body["objective_label"]) == ("gain_muscle", "Ganhar massa muscular")
    week = body["week"]
    assert (week["sessions"], week["active_days"], week["weekly_target"]) == (2, 2, 3)
    assert (week["previous_sessions"], week["previous_active_days"]) == (1, 1)
    assert week["streak_weeks"] == 2

    kinds = [
        f["kind"] if f["kind"] != "endurance" else f"endurance:{f['endurance']['modality']}"
        for f in body["focus"]
    ]
    assert kinds == ["strength", "body", "endurance:walk", "endurance:run"]
    strength, body_card, walk, run = (body["focus"][i] for i in range(4))
    assert strength["strength"] == {
        "sessions": 1,
        "sets": 2,
        "volume_kg": 8 * 60 + 6 * 40 + 8 * 60,
        "previous_sets": 0,
        "previous_volume_kg": 0,
    }
    # Supino: peito, ombros e tríceps; os outros 10 ficaram sem série.
    assert body_card["body"]["untrained"] == 10
    assert len(body_card["body"]["least"]) == 4
    assert {m["weighted_sets_per_week"] for m in body_card["body"]["least"]} == {0}
    # Caminhada da semana anterior: nada nos últimos 7 dias, 3 km nos 7 antes.
    assert (walk["endurance"]["sessions"], walk["endurance"]["previous_distance_m"]) == (0, 3000)
    assert walk["endurance"]["pace_s_per_km"] is None
    assert (run["endurance"]["distance_m"], run["endurance"]["pace_s_per_km"]) == (5000, 360)

    assert body["last_record"] == {
        "modality": "strength",
        "title": "Treino A",
        "day": "2026-11-01",
        "duration_s": 2400,
        "distance_m": None,
        "sets": 2,
        "volume_kg": 1200,
    }


def test_goal_progress_comes_from_the_records(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    strength_session(client, headers, clock)
    activity(client, headers, "2026-10-27", distance_m=5000)  # 6:00/km
    activity(client, headers, "2026-10-29", duration_s=2640, distance_m=8000)  # 5:30/km
    # Fora do período da meta (começa em 01/10): não conta.
    activity(client, headers, "2026-09-20", duration_s=3600, distance_m=12000)

    # O nome do exercício casa sem acentos nem maiúsculas.
    goal(
        client,
        headers,
        "strength",
        {"exercise": "supino RETO com barra", "load_kg": 60, "reps": 8},
        1,
    )
    goal(client, headers, "run_distance", {"distance_km": 10}, 1)
    goal(client, headers, "run_time", {"distance_km": 5, "time_s": 1500}, 1)
    goal(client, headers, "frequency", {"sessions_per_week": 4, "modality": "run"}, 2)
    goal(client, headers, "custom", {"description": "Dormir melhor"}, 3)

    body = dashboard(client, headers)

    assert body["active_goals"] == 5
    assert len(body["goals"]) == 3
    by_kind = {g["kind"]: g["progress"] for g in body["goals"]}
    assert by_kind["strength"]["current"] == 60
    assert by_kind["strength"]["achieved"] is True
    assert by_kind["strength"]["ratio"] == 1
    assert (by_kind["run_distance"]["current"], by_kind["run_distance"]["ratio"]) == (8, 0.8)
    # Melhor pace em corridas de 5 km ou mais: 5:30/km → 27:30 nos 5 km.
    assert by_kind["run_time"]["current"] == 1650
    assert by_kind["run_time"]["lower_is_better"] is True
    assert by_kind["run_time"]["achieved"] is False


def test_frequency_strength_reps_and_unmeasured_goals(
    client: TestClient, signup, clock: Clock
) -> None:
    headers = signup()
    strength_session(client, headers, clock)
    activity(client, headers, "2026-10-27", distance_m=5000)
    # Só o aquecimento teve 10 repetições: não conta para a carga.
    goal(
        client,
        headers,
        "strength",
        {"exercise": "Supino reto com barra", "load_kg": 20, "reps": 10},
        1,
    )
    goal(client, headers, "frequency", {"sessions_per_week": 4, "modality": "run"}, 1)
    goal(client, headers, "custom", {"description": "Dormir melhor"}, 1)

    body = dashboard(client, headers)

    by_kind = {g["kind"]: g for g in body["goals"]}
    assert by_kind["strength"]["progress"]["current"] is None
    assert by_kind["strength"]["progress"]["ratio"] is None
    assert by_kind["frequency"]["progress"]["current"] == 1
    assert by_kind["frequency"]["progress"]["ratio"] == 0.25
    assert by_kind["frequency"]["summary"]
    assert by_kind["custom"]["progress"] is None


def test_hypertrophy_uses_weekly_weighted_sets(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    strength_session(client, headers, clock)
    goal(client, headers, "hypertrophy", {"muscle_group": "chest", "weekly_sets": 10})

    progress = dashboard(client, headers)["goals"][0]["progress"]

    assert progress["unit"] == "sets_per_week"
    assert 0 < progress["current"] < 10
    assert "28 dias" in progress["basis"]


def test_active_plan_opens_the_runner_dashboard(client: TestClient, signup) -> None:
    headers = signup()
    profile(client, headers, primary_objective="run", preferred_modalities=["run"])
    ok(
        client.post(
            f"{API}/training-plans", headers=headers, json={"kind": "run_5k", "weekdays": [0, 2, 4]}
        ),
        201,
    )

    focus = dashboard(client, headers)["focus"]

    assert [f["kind"] for f in focus] == ["plan", "endurance"]
    plan = focus[0]["plan"]
    assert (plan["title"], plan["modality"]) == ("Primeiros 5 km", "run")
    assert (plan["completed_sessions"], plan["current_week"]) == (0, 1)
    assert plan["next_session"]["week"] == 1
    assert plan["next_session"]["summary"]
    assert plan["next_session"]["total_s"] > 0


def test_dashboard_only_shows_the_owners_data(client: TestClient, signup, clock: Clock) -> None:
    ana = signup()
    strength_session(client, ana, clock)
    activity(client, ana, "2026-10-30", distance_m=5000)
    goal(client, ana, "run_distance", {"distance_km": 10})

    bia = dashboard(client, signup("bia@exemplo.com", "Bia"))

    assert bia["week"]["sessions"] == 0
    assert bia["focus"] == []
    assert bia["goals"] == []
    assert bia["last_record"] is None
    assert client.get(f"{API}/dashboard").status_code == 401
