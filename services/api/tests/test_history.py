"""Histórico de treinos, histórico por exercício, recordes e comparação."""

import pytest
from fastapi.testclient import TestClient

from app.modules.history.service import e1rm
from tests.conftest import Clock
from tests.test_sessions import BASE, FLEXAO, PRANCHA, SUPINO, logged, start


def workout(client: TestClient, headers: dict, *exercise_ids: str) -> dict:
    """Treino livre com os exercícios, na ordem."""
    session = start(client, headers)
    for exercise_id in exercise_ids:
        session = client.post(
            f"{BASE}/{session['id']}/exercises", headers=headers, json={"exercise_id": exercise_id}
        ).json()
    return session


def finish(client: TestClient, headers: dict, session: dict) -> dict:
    response = client.post(f"{BASE}/{session['id']}/finish", headers=headers, json={})
    assert response.status_code == 200, response.text
    return response.json()


@pytest.fixture
def three_sessions(client: TestClient, signup, clock: Clock) -> tuple[dict, list[dict]]:
    """Três treinos de supino em dias seguidos:
    1) 60x10, 60x8 · 2) 62,5x8 + drop 50x6 · 3) aquecimento 100x1, 55x12."""
    headers = signup()
    done = []

    s = workout(client, headers, SUPINO)
    logged(client, headers, s, 0, reps=10, load_kg=60)
    logged(client, headers, s, 0, reps=8, load_kg=60)
    done.append(finish(client, headers, s))

    clock.advance(days=1)
    s = workout(client, headers, SUPINO)
    main = logged(client, headers, s, 0, reps=8, load_kg=62.5)
    logged(client, headers, s, 0, kind="drop", parent_set_id=main["id"], reps=6, load_kg=50)
    done.append(finish(client, headers, s))

    clock.advance(days=1)
    s = workout(client, headers, SUPINO)
    # Aquecimento pesado não é recorde.
    logged(client, headers, s, 0, kind="warmup", reps=1, load_kg=100)
    logged(client, headers, s, 0, reps=12, load_kg=55)
    done.append(finish(client, headers, s))
    return headers, done


def test_e1rm_is_epley_up_to_12_reps() -> None:
    assert e1rm(100, 1) == 100
    assert e1rm(100, 10) == 133.3
    assert e1rm(100, 13) is None
    assert e1rm(None, 5) is None


def test_exercise_history_and_records(client: TestClient, three_sessions) -> None:
    headers, (s1, s2, s3) = three_sessions
    body = client.get(f"/api/v1/exercises/{SUPINO}/history", headers=headers).json()

    records = {r["kind"]: r for r in body["records"]}
    assert (records["max_load"]["value"], records["max_load"]["reps"]) == (62.5, 8)
    assert records["max_load"]["session_id"] == s2["id"]
    # 60x10 estima mais que 62,5x8 (80 contra 79,2).
    assert (records["best_e1rm"]["value"], records["best_e1rm"]["session_id"]) == (80, s1["id"])
    # Volume do 1º: 600 + 480; o do 2º soma o drop: 500 + 300.
    assert (records["max_volume"]["value"], records["max_volume"]["session_id"]) == (
        1080,
        s1["id"],
    )
    assert [(r["reps"], r["value"]) for r in body["rep_records"]] == [
        (8, 62.5),
        (10, 60),
        (12, 55),
    ]

    assert [s["session_id"] for s in body["sessions"]] == [s3["id"], s2["id"], s1["id"]]
    second = body["sessions"][1]
    assert [(x["kind"], x["is_segment"]) for x in second["sets"]] == [
        ("working", False),
        ("drop", True),
    ]
    assert second["volume_kg"] == 800 and second["records"] == ["max_load"]
    # A primeira vez não bate recorde: não havia com o que comparar.
    assert body["sessions"][2]["records"] == []


def test_session_detail_shows_records_and_compares_with_the_one_before(
    client: TestClient, three_sessions
) -> None:
    headers, (s1, s2, _) = three_sessions
    detail = client.get(f"{BASE}/{s2['id']}", headers=headers).json()
    assert detail["records"] == [
        {
            "exercise_id": SUPINO,
            "kind": "max_load",
            "value": 62.5,
            "reps": 8,
            "load_kg": 62.5,
            "previous": 60,
        }
    ]
    # "A última vez" do 2º treino é o 1º, não o 3º (mais recente).
    assert [p["load_kg"] for p in detail["exercises"][0]["previous"]] == [60, 60]
    first = client.get(f"{BASE}/{s1['id']}", headers=headers).json()
    assert first["exercises"][0]["previous"] == [] and first["records"] == []


def test_open_session_has_no_records(client: TestClient, three_sessions) -> None:
    headers, _ = three_sessions
    session = workout(client, headers, SUPINO)
    logged(client, headers, session, 0, reps=5, load_kg=100)
    assert client.get(f"{BASE}/{session['id']}", headers=headers).json()["records"] == []


def test_history_list_is_paginated_newest_first(client: TestClient, three_sessions) -> None:
    headers, (s1, s2, s3) = three_sessions
    page = client.get(f"{BASE}?limit=2", headers=headers).json()
    assert [i["id"] for i in page["items"]] == [s3["id"], s2["id"]]
    second = page["items"][1]
    assert (second["set_count"], second["volume_kg"], second["record_count"]) == (1, 800, 1)
    assert second["exercise_names"] == ["Supino reto com barra"]
    assert page["next_before"] is not None

    rest = client.get(
        f"{BASE}", headers=headers, params={"limit": 2, "before": page["next_before"]}
    ).json()
    assert [i["id"] for i in rest["items"]] == [s1["id"]]
    assert rest["next_before"] is None


def test_open_and_discarded_sessions_stay_out(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    s = workout(client, headers, SUPINO)
    logged(client, headers, s, 0, reps=5, load_kg=200)
    client.post(f"{BASE}/{s['id']}/discard", headers=headers)
    workout(client, headers, SUPINO)  # aberto

    assert client.get(BASE, headers=headers).json()["items"] == []
    history = client.get(f"/api/v1/exercises/{SUPINO}/history", headers=headers).json()
    assert history["records"] == [] and history["sessions"] == []


def test_records_by_exercise_and_load_type(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    s = workout(client, headers, SUPINO, FLEXAO, PRANCHA)
    logged(client, headers, s, 0, reps=10, load_kg=60)
    logged(client, headers, s, 1, reps=20)
    logged(client, headers, s, 2, duration_s=60)
    finish(client, headers, s)
    clock.advance(days=1)
    s = workout(client, headers, FLEXAO)
    logged(client, headers, s, 0, reps=25)
    finish(client, headers, s)

    body = client.get("/api/v1/analytics/records", headers=headers).json()
    # Do feito mais recentemente; cada um com os tipos que fazem sentido.
    assert body[0]["exercise"]["id"] == FLEXAO
    by_id = {e["exercise"]["id"]: {r["kind"]: r["value"] for r in e["records"]} for e in body}
    assert by_id[FLEXAO] == {"max_reps": 25}
    assert by_id[PRANCHA] == {"max_duration": 60}
    assert by_id[SUPINO] == {"max_load": 60, "best_e1rm": 80, "max_volume": 600}


def test_history_and_records_are_per_user(client: TestClient, three_sessions, signup) -> None:
    ana, (s1, _, _) = three_sessions
    bia = signup("bia@exemplo.com", "Bia")

    assert client.get(BASE, headers=bia).json()["items"] == []
    assert client.get("/api/v1/analytics/records", headers=bia).json() == []
    history = client.get(f"/api/v1/exercises/{SUPINO}/history", headers=bia).json()
    assert history["records"] == [] and history["sessions"] == []
    assert client.get(f"{BASE}/{s1['id']}", headers=bia).status_code == 404

    # Exercício próprio de outra pessoa: nem o histórico aparece.
    custom = client.post(
        "/api/v1/exercises",
        headers=ana,
        json={
            "name": "Supino da Ana",
            "mechanics": "compound",
            "equipment": "barbell",
            "load_type": "external",
            "unilateral": False,
            "muscles": [{"muscle_group_id": "chest", "role": "primary"}],
        },
    ).json()
    assert client.get(f"/api/v1/exercises/{custom['id']}/history", headers=bia).status_code == 404
