"""Peso e medidas (5.3, ADR-060): registro com limites e consentimento, edição,
tendência (um ponto por dia, média de 7 dias, ritmo por semana), privacidade,
revogação e o progresso das metas de peso."""

from datetime import UTC, date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.modules.body.service import trend_points, weekly_rate
from app.modules.dashboard import router as dashboard_router
from app.modules.dashboard import rules
from tests.test_analytics import ok

API = "/api/v1"
URL = f"{API}/body-measurements"


@pytest.fixture
def ana(signup, client: TestClient) -> dict:
    headers = signup("ana@exemplo.com", "Ana")
    ok(client.put(f"{API}/me/consents/health_data", headers=headers))
    return headers


@pytest.fixture
def bia(signup) -> dict:
    return signup("bia@exemplo.com", "Bia")


def measure(client: TestClient, headers: dict, at: str, **values) -> dict:
    return ok(client.post(URL, headers=headers, json={"measured_at": at, **values}), 201)


def errors(response) -> dict[str, str]:
    assert response.status_code == 422, response.text
    return {e["field"]: e["message"] for e in response.json()["errors"]}


def test_options_are_public(client: TestClient) -> None:
    options = ok(client.get(f"{API}/body-measurement-options"))
    by_metric = {o["metric"]: o for o in options}
    assert options[0]["metric"] == "weight_kg"
    assert (by_metric["weight_kg"]["unit"], by_metric["weight_kg"]["min"]) == ("kg", 20)
    assert by_metric["body_fat_pct"]["estimate"] is True
    assert by_metric["waist_cm"]["label"] == "Cintura"


def test_measurements_need_the_health_consent(client: TestClient, bia: dict) -> None:
    assert ok(client.get(URL, headers=bia)) == []
    response = client.post(
        URL, headers=bia, json={"measured_at": "2026-11-01T07:00:00", "weight_kg": 70}
    )
    assert response.status_code == 403
    assert response.json()["code"] == "consent_required"


def test_recording_and_reading(client: TestClient, ana: dict) -> None:
    saved = measure(
        client, ana, "2026-11-01T07:30:00", weight_kg=72.4, waist_cm=81, notes=" Em jejum "
    )
    # Sem fuso: o horário é o do perfil (São Paulo, UTC-3).
    assert saved["measured_at"].startswith("2026-11-01T10:30:00")
    assert saved["local_time"] == "2026-11-01T07:30:00"
    assert (saved["weight_kg"], saved["waist_cm"], saved["hip_cm"]) == (72.4, 81, None)
    assert saved["notes"] == "Em jejum"
    assert ok(client.get(f"{URL}/{saved['id']}", headers=ana)) == saved

    measure(client, ana, "2026-11-02T07:30:00", weight_kg=72.1)
    listed = ok(client.get(f"{URL}?from=2026-10-01&to=2026-11-30", headers=ana))
    assert [m["weight_kg"] for m in listed] == [72.1, 72.4]  # mais nova antes


@pytest.mark.parametrize(
    ("values", "field"),
    [
        ({}, "__root__"),
        ({"weight_kg": 10}, "weight_kg"),
        ({"weight_kg": 400}, "weight_kg"),
        ({"body_fat_pct": 90}, "body_fat_pct"),
        ({"waist_cm": 300}, "waist_cm"),
        ({"calf_cm": 5}, "calf_cm"),
        ({"weight_kg": 70, "height_cm": 170}, "height_cm"),
    ],
)
def test_values_are_checked(client: TestClient, ana: dict, values: dict, field: str) -> None:
    body = {"measured_at": "2026-11-01T07:00:00", **values}
    found = errors(client.post(URL, headers=ana, json=body))
    assert field in found or any(field in k for k in found)


def test_a_measurement_cannot_be_in_the_future(client: TestClient, ana: dict) -> None:
    later = (datetime.now(UTC) + timedelta(days=1)).isoformat()
    assert (
        "futuro"
        in errors(client.post(URL, headers=ana, json={"measured_at": later, "weight_kg": 70}))[
            "measured_at"
        ]
    )


def test_editing_keeps_at_least_one_value(client: TestClient, ana: dict) -> None:
    saved = measure(client, ana, "2026-11-01T07:00:00", weight_kg=72, waist_cm=80)
    url = f"{URL}/{saved['id']}"
    changed = ok(client.patch(url, headers=ana, json={"weight_kg": None, "hip_cm": 95}))
    assert (changed["weight_kg"], changed["waist_cm"], changed["hip_cm"]) == (None, 80, 95)
    moved = ok(client.patch(url, headers=ana, json={"measured_at": "2026-10-31T21:00:00"}))
    assert moved["local_time"] == "2026-10-31T21:00:00"

    assert "__root__" in errors(
        client.patch(url, headers=ana, json={"waist_cm": None, "hip_cm": None})
    )
    assert "measured_at" in errors(client.patch(url, headers=ana, json={"measured_at": None}))
    assert "hip_cm" in errors(client.patch(url, headers=ana, json={"hip_cm": 400}))

    assert client.delete(url, headers=ana).status_code == 204
    assert client.get(url, headers=ana).status_code == 404


def test_trend_one_point_per_day_and_weekly_rate(client: TestClient, ana: dict) -> None:
    # Duas no mesmo dia: vale a última.
    measure(client, ana, "2026-10-01T07:00:00", weight_kg=81)
    measure(client, ana, "2026-10-01T20:00:00", weight_kg=80)
    measure(client, ana, "2026-10-05T07:00:00", weight_kg=79.6)
    measure(client, ana, "2026-10-15T07:00:00", weight_kg=79)
    measure(client, ana, "2026-10-29T07:00:00", weight_kg=78)
    measure(client, ana, "2026-10-29T08:00:00", waist_cm=84)  # outra medida: não entra

    trend = ok(
        client.get(f"{URL}/trend?metric=weight_kg&from=2026-10-01&to=2026-10-31", headers=ana)
    )
    assert (trend["label"], trend["unit"]) == ("Peso", "kg")
    assert [(p["date"], p["value"]) for p in trend["points"]] == [
        ("2026-10-01", 80),
        ("2026-10-05", 79.6),
        ("2026-10-15", 79),
        ("2026-10-29", 78),
    ]
    # Média de 7 dias: 05/10 junta com 01/10; 15/10 fica sozinho.
    assert [p["average_7d"] for p in trend["points"]] == [80, 79.8, 79, 78]
    assert (trend["change"], trend["min"], trend["max"]) == (-2, 78, 80)
    assert trend["first"]["value"] == 80
    assert trend["last"]["date"] == "2026-10-29"
    # Cerca de meio quilo a menos por semana.
    assert trend["weekly_rate"] == pytest.approx(-0.5, abs=0.05)

    waist = ok(
        client.get(f"{URL}/trend?metric=waist_cm&from=2026-10-01&to=2026-10-31", headers=ana)
    )
    assert len(waist["points"]) == 1
    assert (waist["change"], waist["weekly_rate"]) == (0, None)


def test_trend_without_data_and_period_checks(client: TestClient, ana: dict) -> None:
    empty = ok(client.get(f"{URL}/trend?metric=hip_cm", headers=ana))
    assert (empty["points"], empty["first"], empty["change"], empty["weekly_rate"]) == (
        [],
        None,
        None,
        None,
    )
    # Padrão: os últimos 90 dias.
    assert (
        date.fromisoformat(empty["to_date"]) - date.fromisoformat(empty["from_date"])
    ).days == 89
    assert "from" in errors(client.get(f"{URL}?from=2026-11-05&to=2026-11-01", headers=ana))
    assert "to" in errors(client.get(f"{URL}/trend?from=2024-01-01&to=2026-11-01", headers=ana))
    assert client.get(f"{URL}/trend?metric=height", headers=ana).status_code == 422


def test_measurements_are_private(client: TestClient, ana: dict, bia: dict) -> None:
    saved = measure(client, ana, "2026-11-01T07:00:00", weight_kg=72)
    ok(client.put(f"{API}/me/consents/health_data", headers=bia))
    url = f"{URL}/{saved['id']}"
    assert client.get(url, headers=bia).status_code == 404
    assert client.patch(url, headers=bia, json={"weight_kg": 50}).status_code == 404
    assert client.delete(url, headers=bia).status_code == 404
    assert ok(client.get(f"{URL}?from=2026-10-01&to=2026-11-30", headers=bia)) == []
    trend = ok(client.get(f"{URL}/trend?from=2026-10-01&to=2026-11-30", headers=bia))
    assert trend["points"] == []
    assert ok(client.get(url, headers=ana))["weight_kg"] == 72


def test_revoking_health_data_deletes_the_measurements(client: TestClient, ana: dict) -> None:
    measure(client, ana, "2026-11-01T07:00:00", weight_kg=72)
    assert client.delete(f"{API}/me/consents/health_data", headers=ana).status_code == 204
    assert ok(client.get(f"{URL}?from=2026-10-01&to=2026-11-30", headers=ana)) == []


# --- metas de peso ---


def test_trend_rules() -> None:
    assert weekly_rate([(0, 80), (7, 79)]) is None  # só 2 pontos
    assert weekly_rate([(0, 80), (5, 79.5), (10, 79)]) is None  # menos de 14 dias
    assert weekly_rate([(0, 80), (7, 79.5), (14, 79)]) == -0.5
    points = trend_points(
        [(date(2026, 10, 1), 80), (date(2026, 10, 7), 78), (date(2026, 10, 8), 77)]
    )
    assert [p.average_7d for p in points] == [80, 79, 77.5]


def test_weight_progress_rules() -> None:
    start = date(2026, 10, 1)
    on = date(2026, 10, 30)

    def facts(latest: float | None, begin: float | None = 80) -> rules.GoalFacts:
        return rules.GoalFacts(latest_weight_kg=latest, latest_weight_on=on, start_weight_kg=begin)

    loss = rules.progress("weight_loss", {"target_weight_kg": 70}, facts(76), start)
    assert loss is not None
    # De 80 a 70: 4 de 10 kg percorridos.
    assert (loss.current, loss.ratio, loss.achieved, loss.lower_is_better) == (76, 0.4, False, True)
    assert loss.basis == "peso registrado em 30/10/2026"
    wrong_way = rules.progress("weight_loss", {"target_weight_kg": 70}, facts(82), start)
    assert wrong_way is not None and wrong_way.ratio == 0
    done = rules.progress("weight_loss", {"target_weight_kg": 70}, facts(69.8), start)
    assert done is not None and (done.ratio, done.achieved) == (1, True)

    gain = rules.progress("weight_gain", {"target_weight_kg": 85}, facts(82), start)
    assert gain is not None and (gain.ratio, gain.lower_is_better) == (0.4, False)

    keep = {"target_weight_kg": 72, "tolerance_kg": 1.5}
    inside = rules.progress("weight_maintenance", keep, facts(73.5), start)
    outside = rules.progress("weight_maintenance", keep, facts(73.6), start)
    assert inside is not None and (inside.achieved, inside.ratio) == (True, 1)
    assert outside is not None and (outside.achieved, outside.ratio) == (False, 0)

    nothing = rules.progress("weight_loss", {"target_weight_kg": 70}, rules.GoalFacts(), start)
    assert nothing is not None and (nothing.current, nothing.ratio) == (None, None)


def test_weight_goals_are_measured_on_the_dashboard(
    client: TestClient, ana: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(dashboard_router, "_today", lambda user: date(2026, 11, 1))
    measure(client, ana, "2026-09-28T07:00:00", weight_kg=80)  # antes da meta: o ponto de partida
    measure(client, ana, "2026-10-30T07:00:00", weight_kg=76)
    body = {
        "kind": "weight_loss",
        "title": "Chegar a 70 kg",
        "target": {"target_weight_kg": 70},
        "start_date": "2026-10-01",
    }
    ok(client.post(f"{API}/goals", headers=ana, json=body), 201)

    progress = ok(client.get(f"{API}/dashboard", headers=ana))["goals"][0]["progress"]
    assert progress["current"] == 76
    assert progress["ratio"] == 0.4
    assert progress["unit"] == "kg"
    assert progress["lower_is_better"] is True
    assert progress["basis"] == "peso registrado em 30/10/2026"


def test_weight_goal_without_measurements_is_not_measured(
    client: TestClient, ana: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(dashboard_router, "_today", lambda user: date(2026, 11, 1))
    body = {
        "kind": "weight_gain",
        "title": "Chegar a 75 kg",
        "target": {"target_weight_kg": 75},
        "start_date": "2026-10-01",
    }
    ok(client.post(f"{API}/goals", headers=ana, json=body), 201)
    progress = ok(client.get(f"{API}/dashboard", headers=ana))["goals"][0]["progress"]
    assert (progress["current"], progress["ratio"], progress["achieved"]) == (None, None, False)
