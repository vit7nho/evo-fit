"""Sessões de treino: ciclo de vida, séries, pré-preenchimento, pausas e posse."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.modules.activities.models import Activity
from app.modules.exercises.seed import global_exercise_id
from app.modules.sessions import service as session_service

SUPINO = str(global_exercise_id("supino-reto-barra"))
CRUCIFIXO = str(global_exercise_id("crucifixo-halteres"))
TRICEPS = str(global_exercise_id("triceps-polia"))
PRANCHA = str(global_exercise_id("prancha"))
FLEXAO = str(global_exercise_id("flexao-de-bracos"))

BASE = "/api/v1/workout-sessions"

TEMPLATE = {
    "name": "Treino A",
    "items": [
        {
            "exercise_id": SUPINO,
            "planned_sets": [{"reps_min": 8, "reps_max": 12}] * 3,
            "rest_s": 120,
        },
        {"exercise_id": CRUCIFIXO, "planned_sets": [{"reps_min": 12}], "group": 0},
        {"exercise_id": TRICEPS, "planned_sets": [{"reps_min": 12}], "group": 0},
    ],
    "groups": [{"kind": "biset", "rest_after_s": 90}],
}


class Clock:
    """Relógio controlado do serviço (pausas e duração sem esperar de verdade)."""

    def __init__(self) -> None:
        self.now = datetime(2026, 11, 1, 10, 0, tzinfo=UTC)

    def advance(self, **delta: int) -> None:
        self.now += timedelta(**delta)


@pytest.fixture
def clock(monkeypatch: pytest.MonkeyPatch) -> Clock:
    fake = Clock()
    monkeypatch.setattr(session_service, "_now", lambda: fake.now)
    return fake


def template(client: TestClient, headers: dict[str, str]) -> dict:
    response = client.post("/api/v1/workout-templates", headers=headers, json=TEMPLATE)
    assert response.status_code == 201, response.text
    return response.json()


def start(client: TestClient, headers: dict[str, str], **body) -> dict:
    response = client.post(BASE, headers=headers, json=body)
    assert response.status_code == 201, response.text
    return response.json()


def log(client: TestClient, headers: dict[str, str], session: dict, index: int, **body):
    entry = session["exercises"][index]["id"]
    return client.post(f"{BASE}/{session['id']}/exercises/{entry}/sets", headers=headers, json=body)


def logged(client: TestClient, headers: dict[str, str], session: dict, index: int, **body) -> dict:
    response = log(client, headers, session, index, **body)
    assert response.status_code == 201, response.text
    return response.json()


def field_errors(response) -> list[str]:
    return [e["field"] for e in response.json().get("errors", [])]


# --- início ---


def test_start_from_template_copies_exercises_groups_and_plan(client: TestClient, signup) -> None:
    headers = signup()
    ficha = template(client, headers)

    response = client.post(BASE, headers=headers, json={"template_id": ficha["id"]})

    assert response.status_code == 201
    session = response.json()
    assert response.headers["location"] == f"/api/v1/workout-sessions/{session['id']}"
    assert session["name"] == "Treino A"
    assert session["template_id"] == ficha["id"]
    assert session["status"] == "in_progress"
    assert [e["exercise"]["id"] for e in session["exercises"]] == [SUPINO, CRUCIFIXO, TRICEPS]
    assert [e["group"] for e in session["exercises"]] == [None, 0, 0]
    assert session["groups"][0]["kind"] == "biset"
    assert session["exercises"][0]["rest_s"] == 120
    assert len(session["exercises"][0]["planned_sets"]) == 3
    assert session["exercises"][0]["sets"] == []
    assert session["exercises"][0]["previous"] == []
    assert (session["set_count"], session["volume_kg"]) == (0, 0)


def test_free_session_and_custom_name(client: TestClient, signup) -> None:
    headers = signup()
    free = start(client, headers)
    assert free["name"] == "Treino livre"
    assert free["exercises"] == []
    client.post(f"{BASE}/{free['id']}/discard", headers=headers)

    named = start(client, headers, name="Treino na praça")
    assert named["name"] == "Treino na praça"


def test_only_one_open_session(client: TestClient, signup) -> None:
    headers = signup()
    first = start(client, headers)

    response = client.post(BASE, headers=headers, json={})
    assert response.status_code == 409
    body = response.json()
    assert body["code"] == "session_in_progress"
    assert body["errors"] == [{"field": "session_id", "message": first["id"]}]


def test_cannot_start_from_another_users_template(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    ficha = template(client, ana)

    response = client.post(BASE, headers=bia, json={"template_id": ficha["id"]})
    assert response.status_code == 404


def test_current_session(client: TestClient, signup) -> None:
    headers = signup()
    assert client.get(f"{BASE}/current", headers=headers).status_code == 204

    session = start(client, headers)
    current = client.get(f"{BASE}/current", headers=headers)
    assert current.status_code == 200
    assert current.json()["id"] == session["id"]


# --- séries ---


def test_log_sets_with_positions_and_summary(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])

    warmup = logged(client, headers, session, 0, kind="warmup", reps=15, load_kg=20)
    first = logged(client, headers, session, 0, reps=10, load_kg=60, rir=2)
    second = logged(client, headers, session, 0, reps=8, load_kg=62.5, rpe=8.5)

    assert [warmup["position"], first["position"], second["position"]] == [0, 1, 2]
    assert first["kind"] == "working" and first["rir"] == 2
    current = client.get(f"{BASE}/{session['id']}", headers=headers).json()
    assert [s["reps"] for s in current["exercises"][0]["sets"]] == [15, 10, 8]
    assert current["set_count"] == 2  # aquecimento não conta
    assert current["volume_kg"] == 60 * 10 + 62.5 * 8


@pytest.mark.parametrize(
    ("index", "body", "field"),
    [
        (0, {"load_kg": 60}, "reps"),
        (0, {"reps": 10, "duration_s": 30}, "duration_s"),
        (0, {"reps": 0}, "reps"),
        (0, {"reps": 10, "load_kg": 60.1}, "load_kg"),
        (0, {"reps": 10, "rpe": 8.3}, "rpe"),
        (0, {"reps": 10, "kind": "cluster"}, "kind"),
        (0, {"reps": 10, "kind": "drop"}, "parent_set_id"),
        (0, {"reps": 10, "to_failure": True, "rir": 2}, "rir"),
        (1, {"reps": 30, "duration_s": 30}, "reps"),  # prancha: por tempo
        (1, {"reps": 30}, "duration_s"),
        (1, {}, "duration_s"),
    ],
)
def test_set_values_are_validated(
    client: TestClient, signup, index: int, body: dict, field: str
) -> None:
    headers = signup()
    session = start(client, headers)
    for exercise_id in (SUPINO, PRANCHA):
        client.post(
            f"{BASE}/{session['id']}/exercises", headers=headers, json={"exercise_id": exercise_id}
        )
    session = client.get(f"{BASE}/{session['id']}", headers=headers).json()

    response = log(client, headers, session, index, **body)
    assert response.status_code == 422
    assert field_errors(response) == [field]


def test_timed_exercise_logs_duration(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers)
    session = client.post(
        f"{BASE}/{session['id']}/exercises", headers=headers, json={"exercise_id": PRANCHA}
    ).json()
    assert logged(client, headers, session, 0, duration_s=45)["duration_s"] == 45


def test_update_and_delete_sets(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    entry = session["exercises"][0]["id"]
    entry_set = logged(client, headers, session, 0, reps=10, load_kg=60, rir=2)
    url = f"{BASE}/{session['id']}/exercises/{entry}/sets/{entry_set['id']}"

    updated = client.patch(url, headers=headers, json={"reps": 9, "rir": None})
    assert updated.status_code == 200
    assert (updated.json()["reps"], updated.json()["load_kg"], updated.json()["rir"]) == (
        9,
        60,
        None,
    )
    assert field_errors(client.patch(url, headers=headers, json={"reps": None})) == ["reps"]
    assert field_errors(client.patch(url, headers=headers, json={"kind": None})) == ["kind"]

    assert client.delete(url, headers=headers).status_code == 204
    current = client.get(f"{BASE}/{session['id']}", headers=headers).json()
    assert current["exercises"][0]["sets"] == []


# --- técnicas: drop set, rest-pause e falha ---


def test_drop_set_segments_chain_to_the_working_set(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    main = logged(client, headers, session, 0, reps=10, load_kg=60, to_failure=True)
    drop1 = logged(
        client, headers, session, 0, kind="drop", parent_set_id=main["id"], reps=6, load_kg=45
    )
    drop2 = logged(
        client, headers, session, 0, kind="drop", parent_set_id=main["id"], reps=5, load_kg=30
    )

    assert main["to_failure"] is True and main["parent_set_id"] is None
    assert drop1["parent_set_id"] == drop2["parent_set_id"] == main["id"]
    current = client.get(f"{BASE}/{session['id']}", headers=headers).json()
    assert [s["kind"] for s in current["exercises"][0]["sets"]] == ["working", "drop", "drop"]
    # Um drop set conta como uma série; o volume soma os segmentos.
    assert current["set_count"] == 1
    assert current["volume_kg"] == 60 * 10 + 45 * 6 + 30 * 5


def test_rest_pause_and_failure_on_segments(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    main = logged(client, headers, session, 0, reps=8, load_kg=60)
    pause = logged(
        client,
        headers,
        session,
        0,
        kind="rest_pause",
        parent_set_id=main["id"],
        reps=3,
        load_kg=60,
        to_failure=True,
        rir=0,
    )
    assert (pause["kind"], pause["to_failure"], pause["rir"]) == ("rest_pause", True, 0)


@pytest.mark.parametrize("parent", ["warmup", "segment", "other_exercise", "missing", "none"])
def test_segment_needs_a_working_parent_in_the_same_exercise(
    client: TestClient, signup, parent: str
) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    warmup = logged(client, headers, session, 0, kind="warmup", reps=15, load_kg=20)
    main = logged(client, headers, session, 0, reps=10, load_kg=60)
    drop = logged(client, headers, session, 0, kind="drop", parent_set_id=main["id"], reps=6)
    other = logged(client, headers, session, 1, reps=12, load_kg=10)
    parent_id = {
        "warmup": warmup["id"],
        "segment": drop["id"],
        "other_exercise": other["id"],
        "missing": "00000000-0000-0000-0000-000000000000",
        "none": None,
    }[parent]

    response = log(client, headers, session, 0, kind="drop", parent_set_id=parent_id, reps=5)
    assert response.status_code == 422
    assert field_errors(response) == ["parent_set_id"]


def test_main_sets_have_no_parent_and_segments_are_limited(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    main = logged(client, headers, session, 0, reps=10, load_kg=60)

    response = log(client, headers, session, 0, parent_set_id=main["id"], reps=8)
    assert field_errors(response) == ["parent_set_id"]

    for _ in range(session_service.MAX_SEGMENTS):
        logged(client, headers, session, 0, kind="drop", parent_set_id=main["id"], reps=4)
    response = log(client, headers, session, 0, kind="drop", parent_set_id=main["id"], reps=4)
    assert field_errors(response) == ["parent_set_id"]


def test_update_failure_and_kind_rules(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    entry = session["exercises"][0]["id"]
    main = logged(client, headers, session, 0, reps=10, load_kg=60, rir=2)
    drop = logged(client, headers, session, 0, kind="drop", parent_set_id=main["id"], reps=6)
    sets_url = f"{BASE}/{session['id']}/exercises/{entry}/sets"

    # Falha com RIR 2 não combina; limpando o RIR, vale.
    response = client.patch(f"{sets_url}/{main['id']}", headers=headers, json={"to_failure": True})
    assert field_errors(response) == ["rir"]
    response = client.patch(
        f"{sets_url}/{main['id']}", headers=headers, json={"to_failure": True, "rir": None}
    )
    assert response.status_code == 200 and response.json()["to_failure"] is True
    assert field_errors(
        client.patch(f"{sets_url}/{main['id']}", headers=headers, json={"to_failure": None})
    ) == ["to_failure"]

    # Série com drop não vira aquecimento; o segmento não muda de tipo.
    assert field_errors(
        client.patch(f"{sets_url}/{main['id']}", headers=headers, json={"kind": "warmup"})
    ) == ["kind"]
    assert field_errors(
        client.patch(f"{sets_url}/{drop['id']}", headers=headers, json={"kind": "working"})
    ) == ["kind"]
    # Mas o segmento pode ser corrigido e marcado como falha.
    response = client.patch(
        f"{sets_url}/{drop['id']}", headers=headers, json={"reps": 7, "to_failure": True}
    )
    assert response.status_code == 200 and response.json()["reps"] == 7


def test_deleting_a_set_deletes_its_segments(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    entry = session["exercises"][0]["id"]
    main = logged(client, headers, session, 0, reps=10, load_kg=60)
    logged(client, headers, session, 0, kind="drop", parent_set_id=main["id"], reps=6)
    other = logged(client, headers, session, 0, reps=9, load_kg=60)

    url = f"{BASE}/{session['id']}/exercises/{entry}/sets/{main['id']}"
    assert client.delete(url, headers=headers).status_code == 204
    current = client.get(f"{BASE}/{session['id']}", headers=headers).json()
    assert [s["id"] for s in current["exercises"][0]["sets"]] == [other["id"]]


def test_previous_sets_bring_their_segments(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    ficha = template(client, headers)
    first = start(client, headers, template_id=ficha["id"])
    main = logged(client, headers, first, 0, reps=10, load_kg=60, to_failure=True)
    logged(client, headers, first, 0, kind="drop", parent_set_id=main["id"], reps=6, load_kg=45)
    logged(client, headers, first, 0, reps=8, load_kg=60)
    client.post(f"{BASE}/{first['id']}/finish", headers=headers, json={})

    clock.advance(days=2)
    second = start(client, headers, template_id=ficha["id"])
    previous = second["exercises"][0]["previous"]
    # A ordem das séries principais segue; o drop vem dentro da primeira.
    assert [(p["reps"], p["to_failure"]) for p in previous] == [(10, True), (8, False)]
    assert previous[0]["segments"] == [
        {"kind": "drop", "reps": 6, "load_kg": 45.0, "duration_s": None}
    ]
    assert previous[1]["segments"] == []


# --- pré-preenchimento ---


def test_previous_sets_come_from_the_last_completed_session(
    client: TestClient, signup, clock: Clock
) -> None:
    headers = signup()
    ficha = template(client, headers)

    first = start(client, headers, template_id=ficha["id"])
    logged(client, headers, first, 0, kind="warmup", reps=15, load_kg=20)
    logged(client, headers, first, 0, reps=10, load_kg=60)
    client.post(f"{BASE}/{first['id']}/finish", headers=headers, json={})

    # Um treino descartado não vira referência.
    clock.advance(days=1)
    discarded = start(client, headers, template_id=ficha["id"])
    logged(client, headers, discarded, 0, reps=1, load_kg=200)
    client.post(f"{BASE}/{discarded['id']}/discard", headers=headers)

    clock.advance(days=1)
    second = start(client, headers, template_id=ficha["id"])
    supino = second["exercises"][0]
    assert supino["previous"] == [
        {
            "kind": "warmup",
            "reps": 15,
            "load_kg": 20.0,
            "duration_s": None,
            "to_failure": False,
            "segments": [],
        },
        {
            "kind": "working",
            "reps": 10,
            "load_kg": 60.0,
            "duration_s": None,
            "to_failure": False,
            "segments": [],
        },
    ]
    assert supino["previous_at"].startswith("2026-11-01T10:00")
    # Sem histórico para este exercício nesta conta.
    assert second["exercises"][1]["previous"] == []


def test_previous_sets_are_per_user(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    session = start(client, ana)
    session = client.post(
        f"{BASE}/{session['id']}/exercises", headers=ana, json={"exercise_id": SUPINO}
    ).json()
    logged(client, ana, session, 0, reps=5, load_kg=100)
    client.post(f"{BASE}/{session['id']}/finish", headers=ana, json={})

    bias = start(client, bia)
    bias = client.post(
        f"{BASE}/{bias['id']}/exercises", headers=bia, json={"exercise_id": SUPINO}
    ).json()
    assert bias["exercises"][0]["previous"] == []


# --- pausa, fim e descarte ---


def test_pause_and_finish_count_only_active_time(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    url = f"{BASE}/{session['id']}"

    clock.advance(minutes=10)
    paused = client.post(f"{url}/pause", headers=headers).json()
    assert paused["status"] == "paused"
    assert paused["elapsed_s"] == 600

    clock.advance(minutes=5)  # pausado: não conta
    assert client.get(url, headers=headers).json()["elapsed_s"] == 600
    resumed = client.post(f"{url}/resume", headers=headers).json()
    assert (resumed["status"], resumed["paused_total_s"]) == ("in_progress", 300)

    logged(client, headers, session, 0, reps=10, load_kg=60)
    clock.advance(minutes=20)
    finished = client.post(
        f"{url}/finish", headers=headers, json={"perceived_effort": 8, "notes": "Bom treino"}
    ).json()

    assert finished["status"] == "completed"
    assert finished["elapsed_s"] == 30 * 60
    assert finished["perceived_effort"] == 8
    assert finished["notes"] == "Bom treino"
    assert finished["ended_at"] is not None
    assert client.get(f"{BASE}/current", headers=headers).status_code == 204


def test_finishing_while_paused_closes_the_pause(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    logged(client, headers, session, 0, reps=10)
    clock.advance(minutes=10)
    client.post(f"{BASE}/{session['id']}/pause", headers=headers)
    clock.advance(minutes=10)

    finished = client.post(f"{BASE}/{session['id']}/finish", headers=headers).json()
    assert (finished["elapsed_s"], finished["paused_total_s"]) == (600, 600)


def test_finish_needs_a_set(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])

    response = client.post(f"{BASE}/{session['id']}/finish", headers=headers)
    assert response.status_code == 422
    assert response.json()["code"] == "session_empty"


def test_finished_session_is_closed(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    logged(client, headers, session, 0, reps=10)
    client.post(f"{BASE}/{session['id']}/finish", headers=headers)

    for response in (
        log(client, headers, session, 0, reps=10),
        client.post(f"{BASE}/{session['id']}/pause", headers=headers),
        client.post(f"{BASE}/{session['id']}/discard", headers=headers),
        client.post(
            f"{BASE}/{session['id']}/exercises", headers=headers, json={"exercise_id": SUPINO}
        ),
    ):
        assert response.status_code == 409
        assert response.json()["code"] == "session_closed"
    # Um novo treino pode começar.
    assert client.post(BASE, headers=headers, json={}).status_code == 201


def test_discard_deletes_everything(client: TestClient, signup, db: Session) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    logged(client, headers, session, 0, reps=10)

    assert client.post(f"{BASE}/{session['id']}/discard", headers=headers).status_code == 204
    assert client.get(f"{BASE}/{session['id']}", headers=headers).status_code == 404
    assert db.scalar(select(func.count()).select_from(Activity)) == 0


# --- exercícios no treino ---


def test_add_only_visible_exercises(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    bias_exercise = client.post(
        "/api/v1/exercises",
        headers=bia,
        json={
            "name": "Exercício da Bia",
            "mechanics": "compound",
            "equipment": "bodyweight",
            "load_type": "bodyweight",
            "muscles": [{"muscle_group_id": "chest", "role": "primary"}],
        },
    ).json()
    session = start(client, ana)

    response = client.post(
        f"{BASE}/{session['id']}/exercises", headers=ana, json={"exercise_id": bias_exercise["id"]}
    )
    assert response.status_code == 422
    assert field_errors(response) == ["exercise_id"]

    added = client.post(
        f"{BASE}/{session['id']}/exercises", headers=ana, json={"exercise_id": FLEXAO}
    )
    assert added.status_code == 201
    assert added.json()["exercises"][0]["rest_s"] == 90


def test_removing_from_a_biset_dissolves_the_group(client: TestClient, signup) -> None:
    headers = signup()
    session = start(client, headers, template_id=template(client, headers)["id"])
    crucifixo = session["exercises"][1]["id"]

    response = client.delete(f"{BASE}/{session['id']}/exercises/{crucifixo}", headers=headers)
    assert response.status_code == 204
    current = client.get(f"{BASE}/{session['id']}", headers=headers).json()
    assert [e["exercise"]["id"] for e in current["exercises"]] == [SUPINO, TRICEPS]
    assert [e["group"] for e in current["exercises"]] == [None, None]
    assert current["groups"] == []


def test_session_survives_template_deletion(client: TestClient, signup) -> None:
    headers = signup()
    ficha = template(client, headers)
    session = start(client, headers, template_id=ficha["id"])

    client.delete(f"/api/v1/workout-templates/{ficha['id']}", headers=headers)

    current = client.get(f"{BASE}/{session['id']}", headers=headers).json()
    assert current["template_id"] is None
    assert len(current["exercises"]) == 3
    assert current["groups"][0]["kind"] == "biset"
    assert logged(client, headers, current, 1, reps=12)["reps"] == 12


# --- posse ---


def test_sessions_of_another_user_are_invisible(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    session = start(client, ana, template_id=template(client, ana)["id"])
    entry = session["exercises"][0]["id"]
    url = f"{BASE}/{session['id']}"

    assert client.get(f"{BASE}/current", headers=bia).status_code == 204
    assert client.get(url, headers=bia).status_code == 404
    assert client.post(f"{url}/pause", headers=bia).status_code == 404
    assert client.post(f"{url}/discard", headers=bia).status_code == 404
    assert (
        client.post(f"{url}/exercises/{entry}/sets", headers=bia, json={"reps": 10}).status_code
        == 404
    )
    assert client.get(url, headers=ana).json()["status"] == "in_progress"


def test_segment_cannot_chain_to_another_users_set(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    anas = start(client, ana, template_id=template(client, ana)["id"])
    anas_set = logged(client, ana, anas, 0, reps=10, load_kg=60)
    bias = start(client, bia, template_id=template(client, bia)["id"])

    response = log(client, bia, bias, 0, kind="drop", parent_set_id=anas_set["id"], reps=6)
    assert response.status_code == 422
    assert field_errors(response) == ["parent_set_id"]


# --- ajustes do exercício no treino ---


def test_adjust_rest_and_note_during_the_session(client: TestClient, signup) -> None:
    headers = signup()
    ficha = template(client, headers)
    session = start(client, headers, template_id=ficha["id"])
    url = f"{BASE}/{session['id']}/exercises/{session['exercises'][0]['id']}"

    response = client.patch(url, headers=headers, json={"rest_s": 150, "notes": "  Banco 3  "})
    assert response.status_code == 200
    entry = response.json()["exercises"][0]
    assert (entry["rest_s"], entry["notes"]) == (150, "Banco 3")

    # Só o que veio muda; nota vazia limpa.
    entry = client.patch(url, headers=headers, json={"notes": ""}).json()["exercises"][0]
    assert (entry["rest_s"], entry["notes"]) == (150, None)
    assert field_errors(client.patch(url, headers=headers, json={"rest_s": 601})) == ["rest_s"]

    # A ficha não muda.
    item = client.get(f"/api/v1/workout-templates/{ficha['id']}", headers=headers).json()
    assert item["items"][0]["rest_s"] == 120


def test_adjusting_another_users_or_closed_session(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    session = start(client, ana, template_id=template(client, ana)["id"])
    url = f"{BASE}/{session['id']}/exercises/{session['exercises'][0]['id']}"

    assert client.patch(url, headers=bia, json={"rest_s": 30}).status_code == 404
    logged(client, ana, session, 0, reps=10, load_kg=60)
    client.post(f"{BASE}/{session['id']}/finish", headers=ana, json={})
    assert client.patch(url, headers=ana, json={"rest_s": 30}).status_code == 409
