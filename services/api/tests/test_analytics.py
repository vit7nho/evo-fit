"""Motor de análise (3.4): frequência, consistência, resistência, tendência e comparação."""

import zoneinfo
from datetime import date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.modules.analytics import metrics
from app.modules.analytics.metrics import Entry
from tests.conftest import Clock
from tests.test_sessions import BASE as SESSIONS
from tests.test_sessions import logged, start, template

API = "/api/v1"
SP = zoneinfo.ZoneInfo("America/Sao_Paulo")
# Semanas de 12/10 a 01/11/2026 (segunda a domingo); o relógio dos treinos é 01/11.
OCT = {"from": "2026-10-12", "to": "2026-11-01"}


def ok(response, status: int = 200) -> dict:
    assert response.status_code == status, response.text
    return response.json()


def at(day: str, hour: int = 7, minute: int = 0) -> str:
    """Horário local (São Paulo) em ISO com fuso."""
    return datetime.fromisoformat(day).replace(hour=hour, minute=minute, tzinfo=SP).isoformat()


def activity(
    client: TestClient, headers: dict, day: str, hour: int = 7, minute: int = 0, **body
) -> dict:
    payload = {"modality": "run", "started_at": at(day, hour, minute), "duration_s": 1800, **body}
    return ok(client.post(f"{API}/activities", headers=headers, json=payload), 201)


def strength_session(client: TestClient, headers: dict, clock: Clock) -> dict:
    """Treino concluído em 01/11: aquecimento, 2 séries válidas e um drop."""
    session = start(client, headers, template_id=template(client, headers)["id"])
    logged(client, headers, session, 0, kind="warmup", reps=10, load_kg=20)
    main = logged(client, headers, session, 0, reps=8, load_kg=60)
    logged(client, headers, session, 0, kind="drop", parent_set_id=main["id"], reps=6, load_kg=40)
    logged(client, headers, session, 0, reps=8, load_kg=60)
    clock.advance(minutes=40)
    return ok(client.post(f"{SESSIONS}/{session['id']}/finish", headers=headers, json={}))


def overview(client: TestClient, headers: dict, **params) -> dict:
    return ok(client.get(f"{API}/analytics/overview", headers=headers, params=params))


# --- funções puras ---


def test_weeks_start_on_monday_and_cover_partial_edges() -> None:
    assert metrics.week_start(date(2026, 11, 1)) == date(2026, 10, 26)  # domingo
    assert metrics.weeks_between(date(2026, 10, 14), date(2026, 10, 27)) == [
        date(2026, 10, 12),
        date(2026, 10, 19),
        date(2026, 10, 26),
    ]


def test_consistency_streak_and_target() -> None:
    def week(start: str, active: int) -> dict:
        return {"week_start": date.fromisoformat(start), "active_days": active}

    weeks = [week("2026-10-05", 3), week("2026-10-12", 0), week("2026-10-19", 2)]
    weeks += [week("2026-10-26", 4), week("2026-11-02", 0)]
    # A semana em curso (02/11) ainda vazia não quebra a sequência.
    result = metrics.consistency(weeks, 3, today=date(2026, 11, 4))
    assert result == {
        "weeks": 5,
        "active_weeks": 3,
        "weeks_on_target": 2,
        "current_streak_weeks": 2,
    }
    # Uma semana passada vazia quebra.
    later = metrics.consistency(weeks, None, today=date(2026, 11, 10))
    assert (later["current_streak_weeks"], later["weeks_on_target"]) == (0, None)


@pytest.mark.parametrize(
    ("values", "direction", "per_week"),
    [
        ([1000, 2000, 3000, 4000], "up", 1000.0),
        ([4000, 3000, 2000], "down", -1000.0),
        ([5000, 5100, 5000, 5100], "flat", 20.0),
        ([0, 5000], None, None),  # poucas semanas
        ([0, 0, 0], None, None),  # sem distância
    ],
)
def test_trend(values: list[float], direction: str | None, per_week: float | None) -> None:
    assert metrics.trend(values) == {"direction": direction, "per_week": per_week}


def test_pace_is_weighted_by_distance() -> None:
    entries = [
        Entry(date(2026, 10, 1), "run", 1500, 5000),  # 5:00/km
        Entry(date(2026, 10, 2), "run", 3600, 6000),  # 10:00/km
        Entry(date(2026, 10, 3), "run", 900, None),  # sem distância: fica fora
    ]
    # 5100 s / 11 km = 463,6 s/km (a média simples dos paces daria 450).
    assert metrics.metric_value("pace_s_per_km", entries) == 464
    assert metrics.metric_value("pace_s_per_km", entries[2:]) is None
    assert metrics.rhythm("swim", 1000, 1200)["pace_s_per_100m"] == 120


@pytest.mark.parametrize(
    ("code", "a", "b", "expected"),
    [
        ("sessions", 4, 6, {"difference": 2, "percent": 50.0, "better": "b"}),
        ("sessions", 0, 3, {"difference": 3, "percent": None, "better": "b"}),
        ("duration_s", 3600, 1800, {"difference": -1800, "percent": -50.0, "better": "a"}),
        ("pace_s_per_km", 360, 330, {"difference": -30, "percent": -8.33, "better": "b"}),
        ("pace_s_per_km", None, 330, {"difference": None, "percent": None, "better": None}),
        ("sessions", 2, 2, {"difference": 0, "percent": 0.0, "better": "same"}),
    ],
)
def test_compare_only_gives_percent_with_a_valid_base(
    code: str, a: float | None, b: float | None, expected: dict
) -> None:
    assert metrics.compare(code, a, b) == expected


# --- visão geral ---


def test_overview_counts_every_modality(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    strength_session(client, headers, clock)
    activity(client, headers, "2026-10-13", distance_m=5000)
    activity(client, headers, "2026-10-13", hour=18, modality="walk", duration_s=2400)
    activity(client, headers, "2026-10-28", modality="cycle", duration_s=3600, distance_m=30000)

    body = overview(client, headers, **OCT)

    assert (body["from_date"], body["to_date"], body["days"]) == ("2026-10-12", "2026-11-01", 21)
    assert body["sessions"] == 4
    assert body["active_days"] == 3  # duas no mesmo dia contam um dia
    assert body["duration_s"] == 2400 + 1800 + 2400 + 3600
    assert [(w["week_start"], w["sessions"], w["active_days"]) for w in body["weeks"]] == [
        ("2026-10-12", 2, 1),
        ("2026-10-19", 0, 0),
        ("2026-10-26", 2, 2),
    ]
    by = {m["modality"]: m for m in body["modalities"]}
    assert by["strength"] == {
        "modality": "strength",
        "sessions": 1,
        "duration_s": 2400,
        "distance_m": None,
        # Aquecimento fora; o drop não é série nova, mas entra no volume.
        "sets": 2,
        "volume_kg": 8 * 60 + 6 * 40 + 8 * 60,
    }
    assert by["walk"]["distance_m"] is None
    assert by["cycle"]["distance_m"] == 30000
    assert body["consistency"] == {
        "weeks": 3,
        "active_weeks": 2,
        "weeks_on_target": None,
        "current_streak_weeks": 1,
    }


def test_overview_uses_the_profile_week_target(client: TestClient, signup) -> None:
    headers = signup()
    ok(
        client.patch(
            f"{API}/me",
            headers=headers,
            json={"weekly_availability": {"days_per_week": 2, "minutes_per_session": 45}},
        )
    )
    for day in ("2026-10-12", "2026-10-14", "2026-10-21"):
        activity(client, headers, day)

    body = overview(client, headers, **OCT)
    assert body["weekly_target"] == 2
    assert body["consistency"]["weeks_on_target"] == 1


def test_days_follow_the_profile_timezone(client: TestClient, signup) -> None:
    headers = signup()
    # Domingo 25/10, 23h30 em São Paulo = segunda 26/10 em UTC.
    activity(client, headers, "2026-10-25", hour=23, minute=30)

    body = overview(client, headers, **{"from": "2026-10-25", "to": "2026-10-25"})
    assert body["sessions"] == 1
    assert body["weeks"][0]["week_start"] == "2026-10-19"
    assert overview(client, headers, **{"from": "2026-10-26", "to": "2026-10-26"})["sessions"] == 0


def test_overview_ignores_deleted_unfinished_and_other_peoples_records(
    client: TestClient, signup, clock: Clock
) -> None:
    headers = signup()
    removed = activity(client, headers, "2026-10-13")
    assert client.delete(f"{API}/activities/{removed['id']}", headers=headers).status_code == 204
    open_session = start(client, headers, template_id=template(client, headers)["id"])
    logged(client, headers, open_session, 0, reps=8, load_kg=60)
    bia = signup("bia@exemplo.com", "Bia")
    activity(client, bia, "2026-10-13")

    body = overview(client, headers, **OCT)
    assert (body["sessions"], body["duration_s"], body["modalities"]) == (0, 0, [])
    assert overview(client, bia, **OCT)["sessions"] == 1


def test_overview_period_rules(client: TestClient, signup) -> None:
    headers = signup()
    today = datetime.now(SP).date()

    body = overview(client, headers)
    assert body["to_date"] == today.isoformat()
    assert body["from_date"] == (today - timedelta(days=29)).isoformat()
    assert body["days"] == 30

    for params, field in (
        ({"from": "2026-10-20", "to": "2026-10-10"}, "from"),
        ({"from": "2025-01-01", "to": "2026-10-10"}, "to"),
    ):
        response = client.get(f"{API}/analytics/overview", headers=headers, params=params)
        assert response.status_code == 422
        assert [e["field"] for e in response.json()["errors"]] == [field]
    full_year = {"from": "2025-11-02", "to": "2026-11-02"}  # 366 dias: aceito
    assert overview(client, headers, **full_year)["days"] == 366


# --- resistência ---


def test_endurance_weeks_pace_and_trend(client: TestClient, signup) -> None:
    headers = signup()
    activity(client, headers, "2026-10-13", distance_m=3000, duration_s=1200)
    activity(client, headers, "2026-10-21", distance_m=5000, duration_s=1800)
    activity(client, headers, "2026-10-23", duration_s=1500)  # sem distância
    activity(client, headers, "2026-10-28", distance_m=8000, duration_s=2880)
    activity(client, headers, "2026-10-29", modality="walk", distance_m=4000)

    body = ok(
        client.get(f"{API}/analytics/endurance", headers=headers, params={"modality": "run", **OCT})
    )

    assert (body["sessions"], body["distance_m"], body["active_weeks"]) == (4, 16000, 3)
    # (1200 + 1800 + 2880) s / 16 km = 367,5 → 368 s/km; a sem distância fica fora.
    assert body["pace_s_per_km"] == 368
    assert body["duration_s"] == 1200 + 1800 + 1500 + 2880
    assert [(w["distance_m"], w["pace_s_per_km"]) for w in body["weeks"]] == [
        (3000, 400),
        (5000, 360),
        (8000, 360),
    ]
    assert body["weeks"][1]["sessions"] == 2
    assert body["distance_trend"] == {"direction": "up", "per_week": 2500.0}


def test_trend_ignores_partial_weeks(client: TestClient, signup) -> None:
    headers = signup()
    for day, km in (("2026-10-13", 3), ("2026-10-20", 5), ("2026-10-27", 7)):
        activity(client, headers, day, distance_m=km * 1000, duration_s=km * 360)

    # Termina na quarta 04/11: a semana de 02/11 (sem corrida ainda) está pela metade.
    params = {"modality": "run", "from": "2026-10-12", "to": "2026-11-04"}
    body = ok(client.get(f"{API}/analytics/endurance", headers=headers, params=params))
    assert [w["distance_m"] for w in body["weeks"]] == [3000, 5000, 7000, 0]
    # Com ela, a reta quase não sobe; sem ela, sobe 2 km por semana.
    assert body["distance_trend"] == {"direction": "up", "per_week": 2000.0}

    # Começando numa quarta, a primeira semana também fica de fora: sobram 2.
    params = {"modality": "run", "from": "2026-10-14", "to": "2026-11-01"}
    body = ok(client.get(f"{API}/analytics/endurance", headers=headers, params=params))
    assert body["distance_trend"] == {"direction": None, "per_week": None}


def test_endurance_swim_and_empty_weeks(client: TestClient, signup) -> None:
    headers = signup()
    activity(client, headers, "2026-10-20", modality="swim", duration_s=1200, distance_m=1000)

    body = ok(
        client.get(
            f"{API}/analytics/endurance", headers=headers, params={"modality": "swim", **OCT}
        )
    )
    assert body["pace_s_per_100m"] == 120
    assert body["pace_s_per_km"] is None
    assert body["weeks"][0] == {
        "week_start": "2026-10-12",
        "sessions": 0,
        "duration_s": 0,
        "distance_m": 0,
        "pace_s_per_km": None,
        "speed_kmh": None,
        "pace_s_per_100m": None,
    }
    assert body["distance_trend"]["direction"] in {"up", "down", "flat"}


def test_endurance_needs_a_valid_modality(client: TestClient, signup) -> None:
    headers = signup()
    for params in ({}, {"modality": "strength"}):
        response = client.get(f"{API}/analytics/endurance", headers=headers, params=params)
        assert response.status_code == 422


# --- comparação ---


def compare(client: TestClient, headers: dict, metric: str, **extra):
    params = {
        "metric": metric,
        "a_from": "2026-10-12",
        "a_to": "2026-10-18",
        "b_from": "2026-10-19",
        "b_to": "2026-10-25",
        **extra,
    }
    return client.get(f"{API}/analytics/compare", headers=headers, params=params)


def test_compare_two_weeks(client: TestClient, signup) -> None:
    headers = signup()
    activity(client, headers, "2026-10-13", distance_m=5000, duration_s=1800)
    activity(client, headers, "2026-10-14", distance_m=5000, duration_s=1800)
    for day in ("2026-10-20", "2026-10-21", "2026-10-22"):
        activity(client, headers, day, distance_m=5000, duration_s=1650)

    sessions = ok(compare(client, headers, "sessions"))
    assert sessions["a"] == {"from_date": "2026-10-12", "to_date": "2026-10-18", "value": 2}
    assert sessions["b"]["value"] == 3
    assert (sessions["difference"], sessions["percent"], sessions["better"]) == (1, 50.0, "b")
    assert sessions["label"] == "Treinos e atividades"

    pace = ok(compare(client, headers, "pace_s_per_km", modality="run"))
    assert (pace["a"]["value"], pace["b"]["value"]) == (360, 330)
    assert pace["higher_is_better"] is False
    assert pace["better"] == "b"  # mais rápido

    distance = ok(compare(client, headers, "distance_m", modality="run"))
    assert (distance["difference"], distance["percent"]) == (5000, 50.0)


def test_compare_without_a_base_gives_no_percent(client: TestClient, signup) -> None:
    headers = signup()
    activity(client, headers, "2026-10-20")

    body = ok(compare(client, headers, "sessions"))
    assert (body["a"]["value"], body["b"]["value"]) == (0, 1)
    assert body["percent"] is None
    assert body["difference"] == 1

    pace = ok(compare(client, headers, "pace_s_per_km", modality="run"))
    assert (pace["a"]["value"], pace["b"]["value"]) == (None, None)  # sem distância
    assert (pace["difference"], pace["percent"], pace["better"]) == (None, None, None)


def test_compare_strength_volume(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    strength_session(client, headers, clock)

    body = ok(
        compare(
            client,
            headers,
            "strength_volume_kg",
            a_from="2026-10-19",
            a_to="2026-10-25",
            b_from="2026-10-26",
            b_to="2026-11-01",
        )
    )
    assert (body["a"]["value"], body["b"]["value"]) == (0, 1200)


@pytest.mark.parametrize(
    ("metric", "extra", "field"),
    [
        ("distance_m", {}, "modality"),
        ("pace_s_per_km", {}, "modality"),
        ("pace_s_per_km", {"modality": "swim"}, "modality"),
        ("sessions", {"a_from": "2026-10-20"}, "a_from"),
        ("sessions", {"b_from": "2025-01-01"}, "b_to"),
    ],
)
def test_compare_validation(
    client: TestClient, signup, metric: str, extra: dict, field: str
) -> None:
    response = compare(client, signup(), metric, **extra)
    assert response.status_code == 422
    assert [e["field"] for e in response.json()["errors"]] == [field]


def test_compare_rejects_unknown_metrics(client: TestClient, signup) -> None:
    assert compare(client, signup(), "calories").status_code == 422
