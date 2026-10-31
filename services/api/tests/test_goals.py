"""Metas: tipos, validação do alvo, posse, datas, status e dados de saúde."""

import logging
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from app.modules.goals import kinds
from app.modules.goals.service import MAX_ACTIVE

STRENGTH = {
    "kind": "strength",
    "title": "Supino de 80 kg",
    "target": {"exercise": "Supino reto", "load_kg": 80, "reps": 5},
}
WEIGHT = {"kind": "weight_loss", "title": "Chegar a 70 kg", "target": {"target_weight_kg": 70}}


def today() -> date:
    return datetime.now(ZoneInfo("America/Sao_Paulo")).date()


def create(client: TestClient, headers: dict[str, str], body: dict | None = None, **changes):
    return client.post("/api/v1/goals", headers=headers, json={**(body or STRENGTH), **changes})


def created(client: TestClient, headers: dict[str, str], body: dict | None = None, **changes):
    response = create(client, headers, body, **changes)
    assert response.status_code == 201, response.text
    return response.json()


def patch(client: TestClient, headers: dict[str, str], goal_id: str, body: dict):
    return client.patch(f"/api/v1/goals/{goal_id}", headers=headers, json=body)


def field_errors(response) -> list[str]:
    return [e["field"] for e in response.json().get("errors", [])]


def grant_health(client: TestClient, headers: dict[str, str]) -> None:
    response = client.put("/api/v1/me/consents/health_data", headers=headers)
    assert response.status_code == 200


# --- opções ---


def test_goal_options_are_public_and_describe_every_kind(client: TestClient) -> None:
    response = client.get("/api/v1/goal-options")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=3600"
    body = response.json()
    assert [k["code"] for k in body["kinds"]] == list(kinds.KINDS)
    strength = body["kinds"][0]
    assert strength["label"] == "Força"
    assert [f["key"] for f in strength["fields"]] == ["exercise", "load_kg", "reps"]
    load = strength["fields"][1]
    assert (load["type"], load["min"], load["max"], load["step"], load["unit"]) == (
        "number",
        1,
        500,
        0.5,
        "kg",
    )
    health = {k["code"] for k in body["kinds"] if k["health_data"]}
    assert health == {"weight_loss", "weight_gain", "weight_maintenance"}
    assert [s["code"] for s in body["statuses"]] == ["active", "achieved", "abandoned"]
    assert body["priorities"][0] == {"value": 1, "label": "Alta"}


# --- criação ---


def test_create_returns_goal_with_defaults_summary_and_location(client: TestClient, signup) -> None:
    response = create(client, signup())

    assert response.status_code == 201
    goal = response.json()
    assert response.headers["location"] == f"/api/v1/goals/{goal['id']}"
    assert goal["kind"] == "strength"
    assert goal["summary"] == "Supino reto: 80 kg × 5"  # noqa: RUF001
    assert goal["status"] == "active"
    assert goal["priority"] == 2
    assert goal["start_date"] == today().isoformat()
    assert goal["target_date"] is None
    assert goal["closed_at"] is None


@pytest.mark.parametrize(
    ("body", "summary"),
    [
        (
            {"kind": "run_time", "target": {"distance_km": 5, "time_s": 1530}},
            "5 km em 25:30",
        ),
        (
            {"kind": "frequency", "target": {"sessions_per_week": 3, "modality": "walk"}},
            "3x por semana · Caminhada",
        ),
        ({"kind": "frequency", "target": {"sessions_per_week": 4}}, "4x por semana"),
        (
            {"kind": "hypertrophy", "target": {"muscle_group": "glutes", "weekly_sets": 12}},
            "Glúteos: 12 séries por semana",
        ),
        ({"kind": "run_distance", "target": {"distance_km": 10.5}}, "10,5 km"),
        ({"kind": "custom", "target": {}}, ""),
    ],
)
def test_every_kind_validates_and_summarizes(
    client: TestClient, signup, body: dict, summary: str
) -> None:
    goal = created(client, signup(), {"title": "Minha meta", **body})
    assert goal["summary"] == summary


@pytest.mark.parametrize(
    ("target", "field", "message"),
    [
        ({"exercise": "Supino", "load_kg": 80}, "target.reps", "Campo obrigatório."),
        ({"exercise": "Supino", "load_kg": 80, "reps": 5, "rpe": 8}, "target.rpe", None),
        ({"exercise": "Supino", "load_kg": 900, "reps": 5}, "target.load_kg", None),
        ({"exercise": "Supino", "load_kg": 80.3, "reps": 5}, "target.load_kg", None),
        ({"exercise": "Supino", "load_kg": 80, "reps": 5.5}, "target.reps", None),
        ({"exercise": "Supino", "load_kg": "80", "reps": 5}, "target.load_kg", None),
        ({"exercise": "S", "load_kg": 80, "reps": 5}, "target.exercise", None),
        ({"exercise": "   ", "load_kg": 80, "reps": 5}, "target.exercise", "Campo obrigatório."),
        ({"exercise": "Supino", "load_kg": True, "reps": 5}, "target.load_kg", None),
    ],
)
def test_target_is_validated_against_the_kind_fields(
    client: TestClient, signup, target: dict, field: str, message: str | None
) -> None:
    response = create(client, signup(), target=target)

    assert response.status_code == 422
    assert field_errors(response) == [field]
    if message:
        assert response.json()["errors"][0]["message"] == message


def test_load_out_of_range_message_names_the_limits(client: TestClient, signup) -> None:
    response = create(client, signup(), target={"exercise": "Supino", "load_kg": 0, "reps": 5})
    assert response.json()["errors"][0]["message"] == "Informe um valor entre 1 e 500 kg."


def test_choice_must_be_one_of_the_options(client: TestClient, signup) -> None:
    response = create(
        client,
        signup(),
        {"kind": "hypertrophy", "title": "Costas", "target": {"muscle_group": "back"}},
    )
    assert field_errors(response) == ["target.muscle_group"]


def test_unknown_kind_title_and_extra_fields_are_rejected(client: TestClient, signup) -> None:
    headers = signup()
    assert field_errors(create(client, headers, kind="yoga")) == ["kind"]
    assert field_errors(create(client, headers, title=" a ")) == ["title"]
    # O dono vem do token; o corpo não escolhe usuário nem status inicial.
    response = create(client, headers, user_id="00000000-0000-0000-0000-000000000000")
    assert field_errors(response) == ["user_id"]


@pytest.mark.parametrize(
    ("changes", "field"),
    [
        ({"target_date": (date(2020, 1, 1)).isoformat()}, "target_date"),
        ({"start_date": "2026-12-01", "target_date": "2026-11-30"}, "target_date"),
        ({"target_date": (date.today() + timedelta(days=11 * 365)).isoformat()}, "target_date"),
        ({"start_date": "2015-01-01"}, "start_date"),
        ({"start_date": (date.today() + timedelta(days=400)).isoformat()}, "start_date"),
    ],
)
def test_dates_are_validated(client: TestClient, signup, changes: dict, field: str) -> None:
    response = create(client, signup(), **changes)
    assert response.status_code == 422
    assert field_errors(response) == [field]


def test_requires_login(client: TestClient) -> None:
    assert client.get("/api/v1/goals").status_code == 401
    assert client.post("/api/v1/goals", json=STRENGTH).status_code == 401


# --- lista e posse ---


def test_list_shows_active_first_by_priority_and_filters_by_status(
    client: TestClient, signup
) -> None:
    headers = signup()
    low = created(client, headers, title="Baixa", priority=3)
    high = created(client, headers, title="Alta", priority=1)
    done = created(client, headers, title="Feita", priority=1)
    patch(client, headers, done["id"], {"status": "achieved"})

    titles = [g["title"] for g in client.get("/api/v1/goals", headers=headers).json()]
    assert titles == [high["title"], low["title"], done["title"]]

    achieved = client.get("/api/v1/goals?status=achieved", headers=headers).json()
    assert [g["id"] for g in achieved] == [done["id"]]


def test_goals_of_another_user_are_invisible(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    goal = created(client, ana)
    url = f"/api/v1/goals/{goal['id']}"

    assert client.get("/api/v1/goals", headers=bia).json() == []
    assert client.get(url, headers=bia).status_code == 404
    assert patch(client, bia, goal["id"], {"title": "Roubada"}).status_code == 404
    assert client.delete(url, headers=bia).status_code == 404
    # Continua intacta para a dona.
    assert client.get(url, headers=ana).json()["title"] == goal["title"]


# --- atualização ---


def test_update_title_target_priority_and_clear_deadline(client: TestClient, signup) -> None:
    headers = signup()
    deadline = (today() + timedelta(days=60)).isoformat()
    goal = created(client, headers, target_date=deadline)

    response = patch(
        client,
        headers,
        goal["id"],
        {
            "title": "Supino de 85 kg",
            "target": {"exercise": "Supino reto", "load_kg": 85, "reps": 3},
            "priority": 1,
            "target_date": None,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Supino de 85 kg"
    assert body["summary"] == "Supino reto: 85 kg × 3"  # noqa: RUF001
    assert body["priority"] == 1
    assert body["target_date"] is None


def test_update_validates_target_with_the_existing_kind(client: TestClient, signup) -> None:
    headers = signup()
    goal = created(client, headers)

    response = patch(client, headers, goal["id"], {"target": {"distance_km": 5}})
    assert response.status_code == 422
    assert field_errors(response) == ["target.distance_km"]
    # O tipo não muda por PATCH.
    assert field_errors(patch(client, headers, goal["id"], {"kind": "run_distance"})) == ["kind"]


def test_required_fields_reject_null(client: TestClient, signup) -> None:
    headers = signup()
    goal = created(client, headers)
    for field in ("title", "target", "status", "priority", "start_date"):
        response = patch(client, headers, goal["id"], {field: None})
        assert response.status_code == 422, field
        assert field_errors(response) == [field]


def test_deadline_cannot_move_before_start(client: TestClient, signup) -> None:
    headers = signup()
    goal = created(client, headers)
    before = (today() - timedelta(days=1)).isoformat()
    assert field_errors(patch(client, headers, goal["id"], {"target_date": before})) == [
        "target_date"
    ]


def test_closing_and_reopening_tracks_closed_at(client: TestClient, signup) -> None:
    headers = signup()
    goal = created(client, headers)

    achieved = patch(client, headers, goal["id"], {"status": "achieved"}).json()
    assert achieved["status"] == "achieved"
    assert achieved["closed_at"] is not None

    reopened = patch(client, headers, goal["id"], {"status": "active"}).json()
    assert reopened["status"] == "active"
    assert reopened["closed_at"] is None


def test_delete_removes_the_goal(client: TestClient, signup) -> None:
    headers = signup()
    goal = created(client, headers)
    url = f"/api/v1/goals/{goal['id']}"

    assert client.delete(url, headers=headers).status_code == 204
    assert client.get(url, headers=headers).status_code == 404


# --- limite ---


def test_active_goal_limit(client: TestClient, signup) -> None:
    headers = signup()
    goals = [created(client, headers, title=f"Meta {i}") for i in range(MAX_ACTIVE)]

    response = create(client, headers)
    assert response.status_code == 409
    assert response.json()["code"] == "goal_limit"

    # Concluir uma libera espaço; reativar com o limite cheio é recusado.
    patch(client, headers, goals[0]["id"], {"status": "achieved"})
    created(client, headers)
    assert patch(client, headers, goals[0]["id"], {"status": "active"}).status_code == 409


# --- dados de saúde ---


def test_weight_goal_requires_health_consent(client: TestClient, signup) -> None:
    headers = signup()

    response = create(client, headers, WEIGHT)
    assert response.status_code == 403
    assert response.json()["code"] == "consent_required"

    grant_health(client, headers)
    assert create(client, headers, WEIGHT).json()["summary"] == "70 kg"


def test_revoking_health_consent_deletes_weight_goals_only(client: TestClient, signup) -> None:
    headers = signup()
    grant_health(client, headers)
    created(client, headers, WEIGHT)
    strength = created(client, headers)

    assert client.delete("/api/v1/me/consents/health_data", headers=headers).status_code == 204

    remaining = client.get("/api/v1/goals", headers=headers).json()
    assert [g["id"] for g in remaining] == [strength["id"]]


def test_logs_do_not_contain_title_or_target(
    client: TestClient, signup, caplog: pytest.LogCaptureFixture
) -> None:
    headers = signup()
    grant_health(client, headers)
    with caplog.at_level(logging.INFO):
        goal = created(client, headers, WEIGHT)
        patch(client, headers, goal["id"], {"title": "Segredo pessoal"})

    text = caplog.text + "".join(str(r.__dict__) for r in caplog.records)
    assert "goal_created" in text
    assert "Segredo pessoal" not in text
    assert "Chegar a 70 kg" not in text
    assert "70" not in "".join(str(getattr(r, "target", "")) for r in caplog.records)
