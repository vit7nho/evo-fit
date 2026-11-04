"""Atividades de resistência: registro, regras por modalidade, lista, correção e exclusão."""

import logging
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.activities.models import Activity
from app.modules.sessions.models import WorkoutSession
from tests.test_sessions import TEMPLATE

BASE = "/api/v1/activities"


def ago(**delta: float) -> str:
    return (datetime.now(UTC) - timedelta(**delta)).isoformat()


RUN = {"modality": "run", "started_at": ago(hours=2), "duration_s": 1800, "distance_m": 5000}


def create(client: TestClient, headers: dict[str, str], **changes):
    return client.post(BASE, headers=headers, json={**RUN, **changes})


def created(client: TestClient, headers: dict[str, str], **changes) -> dict:
    response = create(client, headers, **changes)
    assert response.status_code == 201, response.text
    return response.json()


def field_errors(response) -> list[str]:
    return [e["field"] for e in response.json().get("errors", [])]


# --- opções ---


def test_options_are_public_and_cacheable(client: TestClient) -> None:
    response = client.get("/api/v1/activity-options")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=3600"
    body = response.json()
    assert [m["code"] for m in body["modalities"]] == ["run", "walk", "cycle", "swim"]
    assert body["modalities"][0]["label"] == "Corrida"
    assert "freestyle" in [s["code"] for s in body["strokes"]]
    assert body["pool_lengths_m"] == [25, 50]


# --- registro ---


def test_register_a_run(client: TestClient, signup) -> None:
    headers = signup()

    response = create(client, headers, perceived_effort=7, notes="  Parque  ")

    assert response.status_code == 201
    body = response.json()
    assert response.headers["location"] == f"{BASE}/{body['id']}"
    assert body["modality"] == "run"
    assert body["duration_s"] == 1800 and body["distance_m"] == 5000
    assert (body["perceived_effort"], body["notes"]) == (7, "Parque")
    started = datetime.fromisoformat(body["started_at"])
    assert datetime.fromisoformat(body["ended_at"]) == started + timedelta(seconds=1800)
    # Campos de outras modalidades vêm vazios.
    assert body["indoor"] is None and body["laps"] is None


def test_walk_without_distance(client: TestClient, signup) -> None:
    body = created(client, signup(), modality="walk", distance_m=None, duration_s=2400)
    assert (body["modality"], body["distance_m"]) == ("walk", None)


def test_cycling_indoor_defaults_to_false(client: TestClient, signup) -> None:
    headers = signup()
    assert created(client, headers, modality="cycle")["indoor"] is False
    assert created(client, headers, modality="cycle", indoor=True)["indoor"] is True


def test_swim_distance_comes_from_laps(client: TestClient, signup) -> None:
    headers = signup()
    swim = {"modality": "swim", "distance_m": None, "pool_length_m": 25, "laps": 40}

    body = created(client, headers, **swim, stroke="freestyle")
    assert (body["distance_m"], body["laps"], body["stroke"]) == (1000, 40, "freestyle")

    # Distância informada junto precisa bater com as voltas.
    assert created(client, headers, **{**swim, "distance_m": 1000})["distance_m"] == 1000
    response = create(client, headers, **{**swim, "distance_m": 1200})
    assert response.status_code == 422
    assert field_errors(response) == ["distance_m"]

    # Águas abertas: só a distância.
    body = created(client, headers, modality="swim", distance_m=1500)
    assert (body["pool_length_m"], body["laps"]) == (None, None)


@pytest.mark.parametrize(
    ("modality", "field", "value"),
    [
        ("run", "indoor", True),
        ("walk", "laps", 10),
        ("cycle", "pool_length_m", 25),
        ("swim", "indoor", False),
    ],
)
def test_fields_of_another_modality_are_rejected(
    client: TestClient, signup, modality: str, field: str, value
) -> None:
    response = create(client, signup(), modality=modality, **{field: value})
    assert response.status_code == 422
    assert field_errors(response) == [field]


@pytest.mark.parametrize(
    ("changes", "field"),
    [
        ({"modality": "strength"}, "modality"),
        ({"modality": "skate"}, "modality"),
        ({"duration_s": 59}, "duration_s"),
        ({"duration_s": 24 * 3600 + 1}, "duration_s"),
        ({"duration_s": None}, "duration_s"),
        ({"distance_m": 0}, "distance_m"),
        ({"distance_m": 300_001}, "distance_m"),
        ({"perceived_effort": 11}, "perceived_effort"),
        ({"notes": "x" * 1001}, "notes"),
        ({"started_at": "2026-11-01T10:00:00"}, "started_at"),
        ({"started_at": ago(minutes=-10)}, "started_at"),
        ({"started_at": ago(days=6 * 365)}, "started_at"),
        ({"pool_length_m": 25, "modality": "swim", "laps": 0}, "laps"),
        ({"user_id": "00000000-0000-0000-0000-000000000000"}, "user_id"),
    ],
)
def test_validation_points_to_the_field(
    client: TestClient, signup, changes: dict, field: str
) -> None:
    response = create(client, signup(), **changes)
    assert response.status_code == 422, response.text
    assert field in field_errors(response)


def test_distance_limit_depends_on_modality(client: TestClient, signup) -> None:
    headers = signup()
    long_ride = {"modality": "cycle", "distance_m": 300_001, "duration_s": 12 * 3600}
    assert create(client, headers, **long_ride).status_code == 201
    response = create(client, headers, modality="swim", distance_m=30_001)
    assert field_errors(response) == ["distance_m"]


# --- lista ---


def test_list_newest_first_with_filter_and_pages(client: TestClient, signup) -> None:
    headers = signup()
    first = created(client, headers, started_at=ago(days=3))
    walk = created(client, headers, modality="walk", started_at=ago(days=2))
    last = created(client, headers, started_at=ago(days=1))

    ids = [a["id"] for a in client.get(BASE, headers=headers).json()]
    assert ids == [last["id"], walk["id"], first["id"]]

    runs = client.get(f"{BASE}?modality=run", headers=headers).json()
    assert [a["id"] for a in runs] == [last["id"], first["id"]]

    page = client.get(f"{BASE}?limit=2", headers=headers).json()
    after = client.get(BASE, headers=headers, params={"before": page[-1]["started_at"]}).json()
    assert [a["id"] for a in page + after] == ids


def test_strength_workouts_stay_out_of_activities(client: TestClient, signup, db: Session) -> None:
    headers = signup()
    template = client.post("/api/v1/workout-templates", headers=headers, json=TEMPLATE).json()
    session = client.post(
        "/api/v1/workout-sessions", headers=headers, json={"template_id": template["id"]}
    ).json()
    run = created(client, headers)

    assert [a["id"] for a in client.get(BASE, headers=headers).json()] == [run["id"]]
    # A atividade por trás do treino não é acessível por aqui.
    activity_id = db.scalar(
        select(WorkoutSession.activity_id).where(WorkoutSession.id == session["id"])
    )
    assert client.get(f"{BASE}/{activity_id}", headers=headers).status_code == 404
    assert client.delete(f"{BASE}/{activity_id}", headers=headers).status_code == 404


# --- correção ---


def test_update_is_partial_and_null_clears(client: TestClient, signup) -> None:
    headers = signup()
    run = created(client, headers, perceived_effort=6, notes="Parque")

    response = client.patch(
        f"{BASE}/{run['id']}",
        headers=headers,
        json={"duration_s": 2000, "distance_m": None, "notes": ""},
    )

    assert response.status_code == 200
    body = response.json()
    assert (body["duration_s"], body["distance_m"], body["notes"]) == (2000, None, None)
    assert body["perceived_effort"] == 6
    started = datetime.fromisoformat(body["started_at"])
    assert datetime.fromisoformat(body["ended_at"]) == started + timedelta(seconds=2000)


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({"modality": "walk"}, "modality"),
        ({"duration_s": None}, "duration_s"),
        ({"started_at": None}, "started_at"),
        ({"started_at": ago(minutes=-10)}, "started_at"),
        ({"laps": 10}, "laps"),
    ],
)
def test_update_validation(client: TestClient, signup, body: dict, field: str) -> None:
    headers = signup()
    run = created(client, headers)
    response = client.patch(f"{BASE}/{run['id']}", headers=headers, json=body)
    assert response.status_code == 422
    assert field_errors(response) == [field]


def test_swim_update_follows_laps(client: TestClient, signup) -> None:
    headers = signup()
    swim = created(client, headers, modality="swim", distance_m=None, pool_length_m=25, laps=40)
    url = f"{BASE}/{swim['id']}"

    # Mais voltas: a distância acompanha.
    assert client.patch(url, headers=headers, json={"laps": 60}).json()["distance_m"] == 1500
    # Distância que não bate com as voltas é recusada.
    response = client.patch(url, headers=headers, json={"distance_m": 2000})
    assert field_errors(response) == ["distance_m"]
    # Trocando para águas abertas, vale a distância informada.
    body = client.patch(
        url, headers=headers, json={"pool_length_m": None, "laps": None, "distance_m": 2000}
    ).json()
    assert (body["distance_m"], body["laps"]) == (2000, None)


# --- exclusão ---


def test_delete_is_logical(client: TestClient, signup, db: Session) -> None:
    headers = signup()
    run = created(client, headers)
    url = f"{BASE}/{run['id']}"

    assert client.delete(url, headers=headers).status_code == 204
    assert client.get(url, headers=headers).status_code == 404
    assert client.delete(url, headers=headers).status_code == 404
    assert client.get(BASE, headers=headers).json() == []
    stored = db.scalar(select(Activity).where(Activity.id == run["id"]))
    assert stored is not None and stored.deleted_at is not None


# --- posse e privacidade ---


def test_activities_of_another_user_are_invisible(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    run = created(client, ana)
    url = f"{BASE}/{run['id']}"

    assert client.get(BASE, headers=bia).json() == []
    assert client.get(url, headers=bia).status_code == 404
    assert client.patch(url, headers=bia, json={"duration_s": 60}).status_code == 404
    assert client.delete(url, headers=bia).status_code == 404
    assert client.get(url, headers=ana).json() == run


def test_logs_do_not_contain_notes(
    client: TestClient, signup, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    created(client, signup(), notes="Dor no joelho esquerdo")
    assert "joelho" not in caplog.text
    assert "activity_created" in caplog.text


# --- pace, velocidade e métricas opcionais (3.2) ---


def test_run_pace_and_speed(client: TestClient, signup) -> None:
    # Aceite da Fase 3: 5 km em 30 min = 6:00/km.
    body = created(client, signup())
    assert (body["pace_s_per_km"], body["speed_kmh"], body["pace_s_per_100m"]) == (
        360,
        10.0,
        None,
    )


def test_cycling_speed_and_swim_pace(client: TestClient, signup) -> None:
    headers = signup()
    ride = created(client, headers, modality="cycle", distance_m=30_000, duration_s=3600)
    assert (ride["speed_kmh"], ride["pace_s_per_km"]) == (30.0, 120)

    swim = created(client, headers, modality="swim", distance_m=1000, duration_s=1200)
    assert (swim["pace_s_per_100m"], swim["pace_s_per_km"], swim["speed_kmh"]) == (
        120,
        None,
        None,
    )


def test_no_distance_no_pace(client: TestClient, signup) -> None:
    body = created(client, signup(), modality="walk", distance_m=None)
    assert (body["pace_s_per_km"], body["speed_kmh"], body["pace_s_per_100m"]) == (
        None,
        None,
        None,
    )


@pytest.mark.parametrize(
    "changes",
    [
        {"distance_m": 5000, "duration_s": 60},
        {"modality": "walk", "distance_m": 20_000, "duration_s": 3600},
        {"modality": "swim", "distance_m": 3000, "duration_s": 600},
    ],
)
def test_impossible_speed_is_rejected(client: TestClient, signup, changes: dict) -> None:
    response = create(client, signup(), **changes)
    assert response.status_code == 422
    assert field_errors(response) == ["distance_m"]
    assert "rápido demais" in response.json()["errors"][0]["message"]


def test_update_cannot_make_the_speed_impossible(client: TestClient, signup) -> None:
    headers = signup()
    run = created(client, headers)
    response = client.patch(f"{BASE}/{run['id']}", headers=headers, json={"duration_s": 60})
    assert field_errors(response) == ["distance_m"]
    body = client.patch(f"{BASE}/{run['id']}", headers=headers, json={"duration_s": 1500})
    assert body.json()["pace_s_per_km"] == 300


def test_elevation_gain_except_swimming(client: TestClient, signup) -> None:
    headers = signup()
    assert created(client, headers, elevation_gain_m=120)["elevation_gain_m"] == 120
    response = create(client, headers, modality="swim", elevation_gain_m=10)
    assert field_errors(response) == ["elevation_gain_m"]
    assert field_errors(create(client, headers, elevation_gain_m=10_001)) == ["elevation_gain_m"]


def test_heart_rate_requires_health_consent(client: TestClient, signup) -> None:
    headers = signup()

    response = create(client, headers, avg_hr=150)
    assert response.status_code == 403
    assert response.json()["code"] == "consent_required"
    assert client.get(BASE, headers=headers).json() == []

    client.put("/api/v1/me/consents/health_data", headers=headers)
    body = created(client, headers, avg_hr=150, max_hr=178)
    assert (body["avg_hr"], body["max_hr"]) == (150, 178)


@pytest.mark.parametrize(
    ("changes", "field"),
    [
        ({"avg_hr": 160, "max_hr": 150}, "max_hr"),
        ({"avg_hr": 29}, "avg_hr"),
        ({"max_hr": 251}, "max_hr"),
    ],
)
def test_heart_rate_validation(client: TestClient, signup, changes: dict, field: str) -> None:
    headers = signup()
    client.put("/api/v1/me/consents/health_data", headers=headers)
    assert field_errors(create(client, headers, **changes)) == [field]


def test_revoking_health_consent_erases_heart_rate_only(client: TestClient, signup) -> None:
    headers = signup()
    client.put("/api/v1/me/consents/health_data", headers=headers)
    run = created(client, headers, avg_hr=150, max_hr=178, elevation_gain_m=80)

    assert client.delete("/api/v1/me/consents/health_data", headers=headers).status_code == 204
    body = client.get(f"{BASE}/{run['id']}", headers=headers).json()
    assert (body["avg_hr"], body["max_hr"]) == (None, None)
    assert (body["distance_m"], body["elevation_gain_m"]) == (5000, 80)

    # Sem consentimento: limpar pode, gravar de novo não.
    url = f"{BASE}/{run['id']}"
    assert client.patch(url, headers=headers, json={"avg_hr": None}).status_code == 200
    assert client.patch(url, headers=headers, json={"avg_hr": 140}).status_code == 403


def test_logs_do_not_contain_heart_rate(
    client: TestClient, signup, caplog: pytest.LogCaptureFixture
) -> None:
    headers = signup()
    client.put("/api/v1/me/consents/health_data", headers=headers)
    caplog.set_level(logging.DEBUG)
    created(client, headers, avg_hr=163, max_hr=187)
    assert "activity_created" in caplog.text
    for record in caplog.records:
        assert not {"avg_hr", "max_hr"} & vars(record).keys()
        assert "avg_hr" not in record.getMessage()
