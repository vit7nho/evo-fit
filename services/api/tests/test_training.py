"""Fichas de treino: estrutura, séries planejadas, grupos, posse e ordem."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.modules.exercises.seed import global_exercise_id
from app.modules.training import service
from app.modules.training.models import TemplateItem
from app.modules.users.models import User

SUPINO = str(global_exercise_id("supino-reto-barra"))
CRUCIFIXO = str(global_exercise_id("crucifixo-halteres"))
TRICEPS = str(global_exercise_id("triceps-polia"))
PRANCHA = str(global_exercise_id("prancha"))

WORKING = {"kind": "working", "reps_min": 8, "reps_max": 12}


def item(exercise_id: str, *, sets: list[dict] | None = None, **extra) -> dict:
    return {
        "exercise_id": exercise_id,
        "planned_sets": sets or [WORKING, WORKING, WORKING],
        **extra,
    }


TREINO_A = {
    "name": "Treino A — Peito",
    "notes": "Foco em carga",
    "items": [
        item(SUPINO, sets=[{"kind": "warmup", "reps_min": 15}, WORKING, WORKING], rest_s=120),
        item(CRUCIFIXO, group=0),
        item(TRICEPS, group=0),
    ],
    "groups": [{"kind": "biset", "rest_after_s": 90}],
}


def create(client: TestClient, headers: dict[str, str], body: dict | None = None, **changes):
    return client.post(
        "/api/v1/workout-templates", headers=headers, json={**(body or TREINO_A), **changes}
    )


def created(
    client: TestClient, headers: dict[str, str], body: dict | None = None, **changes
) -> dict:
    response = create(client, headers, body, **changes)
    assert response.status_code == 201, response.text
    return response.json()


def field_errors(response) -> list[str]:
    return [e["field"] for e in response.json().get("errors", [])]


# --- opções ---


def test_workout_options_are_public(client: TestClient) -> None:
    response = client.get("/api/v1/workout-options")

    assert response.status_code == 200
    body = response.json()
    assert {k["code"]: (k["min_size"], k["max_size"]) for k in body["group_kinds"]} == {
        "biset": (2, 2),
        "superset": (2, 2),
        "triset": (3, 3),
        "giant_set": (4, 6),
    }
    assert [s["code"] for s in body["set_kinds"]] == ["warmup", "working", "drop", "rest_pause"]


# --- criação ---


def test_create_template_with_items_groups_and_summary(client: TestClient, signup) -> None:
    response = create(client, signup())

    assert response.status_code == 201
    body = response.json()
    assert response.headers["location"] == f"/api/v1/workout-templates/{body['id']}"
    assert body["name"] == "Treino A — Peito"
    assert body["position"] == 1
    assert [i["exercise"]["name"] for i in body["items"]] == [
        "Supino reto com barra",
        "Crucifixo com halteres",
        "Tríceps na polia (pulley)",
    ]
    assert [i["group"] for i in body["items"]] == [None, 0, 0]
    assert body["groups"][0]["kind"] == "biset"
    assert body["groups"][0]["rest_after_s"] == 90
    assert body["items"][0]["rest_s"] == 120
    # Só a faixa mínima informada: o máximo vira o mesmo número.
    assert body["items"][0]["planned_sets"][0] == {
        "kind": "warmup",
        "reps_min": 15,
        "reps_max": 15,
        "duration_s": None,
        "load_kg": None,
        "rir_target": None,
    }
    assert body["exercise_count"] == 3
    assert body["set_count"] == 8  # aquecimento não conta
    assert body["muscles"] == ["chest", "triceps"]


def test_empty_template_and_position_order(client: TestClient, signup) -> None:
    headers = signup()
    first = created(client, headers, {"name": "Treino A"})
    second = created(client, headers, {"name": "Treino B"})

    assert (first["position"], second["position"]) == (1, 2)
    assert first["items"] == [] and first["set_count"] == 0
    listed = client.get("/api/v1/workout-templates", headers=headers).json()
    assert [t["name"] for t in listed] == ["Treino A", "Treino B"]


@pytest.mark.parametrize(
    ("planned", "field"),
    [
        ({"kind": "working"}, "items.0.planned_sets.0"),
        ({"kind": "working", "reps_min": 8, "duration_s": 30}, "items.0.planned_sets.0"),
        ({"kind": "working", "reps_min": 12, "reps_max": 8}, "items.0.planned_sets.0"),
        ({"kind": "working", "reps_min": 0}, "items.0.planned_sets.0.reps_min"),
        ({"kind": "working", "reps_min": 8, "load_kg": 80.3}, "items.0.planned_sets.0.load_kg"),
        ({"kind": "working", "reps_min": 8, "rir_target": 9}, "items.0.planned_sets.0.rir_target"),
        ({"kind": "cluster", "reps_min": 8}, "items.0.planned_sets.0.kind"),
        ({"kind": "working", "reps_min": 8, "tempo": "3010"}, "items.0.planned_sets.0.tempo"),
    ],
)
def test_planned_sets_are_validated(client: TestClient, signup, planned: dict, field: str) -> None:
    response = create(client, signup(), {"name": "Treino", "items": [item(SUPINO, sets=[planned])]})
    assert response.status_code == 422
    assert field_errors(response) == [field]


def test_timed_exercise_plans_duration_and_others_plan_reps(client: TestClient, signup) -> None:
    headers = signup()

    reps_on_plank = create(client, headers, {"name": "Core", "items": [item(PRANCHA)]})
    assert reps_on_plank.status_code == 422
    assert field_errors(reps_on_plank) == ["items.0.planned_sets.0"]

    duration_on_bench = create(
        client, headers, {"name": "Peito", "items": [item(SUPINO, sets=[{"duration_s": 30}])]}
    )
    assert field_errors(duration_on_bench) == ["items.0.planned_sets.0"]

    plank = created(
        client, headers, {"name": "Core", "items": [item(PRANCHA, sets=[{"duration_s": 45}])]}
    )
    assert plank["items"][0]["planned_sets"][0]["duration_s"] == 45


@pytest.mark.parametrize(
    ("items", "groups", "field"),
    [
        (  # grupo com exercícios fora de sequência
            [item(SUPINO, group=0), item(TRICEPS), item(CRUCIFIXO, group=0)],
            [{"kind": "biset"}],
            "groups.0",
        ),
        ([item(SUPINO, group=0), item(TRICEPS, group=0)], [{"kind": "triset"}], "groups.0"),
        ([item(SUPINO, group=0)], [{"kind": "biset"}], "groups.0"),
        ([item(SUPINO, group=1)], [{"kind": "biset"}], "items.0.group"),
        ([item(SUPINO)], [{"kind": "biset"}], "groups.0"),
    ],
)
def test_groups_are_consecutive_and_sized(
    client: TestClient, signup, items: list, groups: list, field: str
) -> None:
    response = create(client, signup(), {"name": "Treino", "items": items, "groups": groups})
    assert response.status_code == 422
    assert field_errors(response) == [field]


def test_giant_set_takes_four_to_six(client: TestClient, signup) -> None:
    headers = signup()
    four = [item(e, group=0) for e in (SUPINO, CRUCIFIXO, TRICEPS, SUPINO)]
    assert created(
        client, headers, {"name": "Gigante", "items": four, "groups": [{"kind": "giant_set"}]}
    )
    seven = [item(SUPINO, group=0) for _ in range(7)]
    response = create(
        client, headers, {"name": "Gigante", "items": seven, "groups": [{"kind": "giant_set"}]}
    )
    assert field_errors(response) == ["groups.0"]


def test_extra_fields_and_name_are_validated(client: TestClient, signup) -> None:
    headers = signup()
    assert field_errors(create(client, headers, name="A")) == ["name"]
    assert field_errors(
        create(client, headers, user_id="00000000-0000-0000-0000-000000000000")
    ) == ["user_id"]


# --- exercícios visíveis e posse ---


def test_only_visible_exercises_can_be_used(client: TestClient, signup) -> None:
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

    for exercise_id in (bias_exercise["id"], "00000000-0000-0000-0000-000000000000"):
        response = create(client, ana, {"name": "Treino", "items": [item(exercise_id)]})
        assert response.status_code == 422
        assert field_errors(response) == ["items.0.exercise_id"]


def test_own_archived_exercise_stays_in_the_template(client: TestClient, signup) -> None:
    headers = signup()
    mine = client.post(
        "/api/v1/exercises",
        headers=headers,
        json={
            "name": "Remada no TRX",
            "mechanics": "compound",
            "equipment": "bodyweight",
            "load_type": "bodyweight",
            "muscles": [{"muscle_group_id": "lats", "role": "primary"}],
        },
    ).json()
    template = created(client, headers, {"name": "Costas", "items": [item(mine["id"])]})
    client.patch(f"/api/v1/exercises/{mine['id']}", headers=headers, json={"is_active": False})

    body = client.get(f"/api/v1/workout-templates/{template['id']}", headers=headers).json()
    assert body["items"][0]["exercise"]["is_active"] is False
    # Continua salvável: arquivar só tira o exercício da biblioteca.
    response = client.put(
        f"/api/v1/workout-templates/{template['id']}",
        headers=headers,
        json={"name": "Costas", "items": [item(mine["id"])]},
    )
    assert response.status_code == 200


def test_templates_of_another_user_are_invisible(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    template = created(client, ana)
    url = f"/api/v1/workout-templates/{template['id']}"

    assert client.get("/api/v1/workout-templates", headers=bia).json() == []
    assert client.get(url, headers=bia).status_code == 404
    assert client.put(url, headers=bia, json={"name": "Roubada"}).status_code == 404
    assert client.delete(url, headers=bia).status_code == 404
    assert client.get(url, headers=ana).json()["name"] == template["name"]


# --- regravar, excluir, ordenar ---


def test_replace_rewrites_items_and_groups(client: TestClient, signup, db: Session) -> None:
    headers = signup()
    template = created(client, headers)

    response = client.put(
        f"/api/v1/workout-templates/{template['id']}",
        headers=headers,
        json={
            "name": "Treino A v2",
            "items": [item(TRICEPS), item(SUPINO, sets=[WORKING])],
            "groups": [],
        },
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["name"] == "Treino A v2"
    assert body["notes"] is None
    assert [i["exercise"]["id"] for i in body["items"]] == [TRICEPS, SUPINO]
    assert body["groups"] == []
    assert body["set_count"] == 4
    stored = db.scalar(select(func.count()).select_from(TemplateItem))
    assert stored == 2


def test_delete_template(client: TestClient, signup) -> None:
    headers = signup()
    template = created(client, headers)
    url = f"/api/v1/workout-templates/{template['id']}"

    assert client.delete(url, headers=headers).status_code == 204
    assert client.get(url, headers=headers).status_code == 404


def test_reorder_needs_every_template_once(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    a = created(client, ana, {"name": "Treino A"})
    b = created(client, ana, {"name": "Treino B"})
    other = created(client, bia, {"name": "Da Bia"})
    url = "/api/v1/workout-templates/order"

    reordered = client.put(url, headers=ana, json={"template_ids": [b["id"], a["id"]]})
    assert [t["name"] for t in reordered.json()] == ["Treino B", "Treino A"]

    for ids in ([a["id"]], [a["id"], a["id"]], [a["id"], other["id"]]):
        response = client.put(url, headers=ana, json={"template_ids": ids})
        assert response.status_code == 422
        assert field_errors(response) == ["template_ids"]


def test_template_limit(client: TestClient, signup, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(service.catalog, "MAX_TEMPLATES", 2)
    headers = signup()
    created(client, headers, {"name": "Treino A"})
    created(client, headers, {"name": "Treino B"})

    response = create(client, headers, {"name": "Treino C"})
    assert response.status_code == 409
    assert response.json()["code"] == "template_limit"


def test_deleting_the_account_removes_templates_with_own_exercises(
    client: TestClient, signup, db: Session
) -> None:
    headers = signup()
    mine = client.post(
        "/api/v1/exercises",
        headers=headers,
        json={
            "name": "Remada no TRX",
            "mechanics": "compound",
            "equipment": "bodyweight",
            "load_type": "bodyweight",
            "muscles": [{"muscle_group_id": "lats", "role": "primary"}],
        },
    ).json()
    created(client, headers, {"name": "Costas", "items": [item(mine["id"]), item(SUPINO)]})

    user = db.scalar(select(User).where(User.email == "ana@exemplo.com"))
    db.delete(user)
    db.commit()

    assert db.scalar(select(func.count()).select_from(TemplateItem)) == 0
