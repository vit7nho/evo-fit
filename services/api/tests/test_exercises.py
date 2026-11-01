"""Biblioteca de exercícios: catálogo (seed), busca, filtros, exercícios próprios e posse."""

import json

import pytest
from fastapi.testclient import TestClient

from app.modules.exercises import catalog, service
from app.modules.exercises.seed import IMAGES_DIR, SEED_DIR, global_exercise_id, load_seed

SEED = load_seed("v1")

CUSTOM = {
    "name": "Remada no TRX",
    "instructions": "Corpo inclinado para trás, puxe até o peito.",
    "mechanics": "compound",
    "equipment": "bodyweight",
    "load_type": "bodyweight",
    "muscles": [
        {"muscle_group_id": "lats", "role": "primary"},
        {"muscle_group_id": "biceps", "role": "secondary"},
    ],
}


def names(response) -> list[str]:
    assert response.status_code == 200, response.text
    return [e["name"] for e in response.json()]


def create(client: TestClient, headers: dict[str, str], **changes):
    return client.post("/api/v1/exercises", headers=headers, json={**CUSTOM, **changes})


def field_errors(response) -> list[str]:
    return [e["field"] for e in response.json().get("errors", [])]


# --- integridade do seed (sem banco) ---


def test_seed_has_the_planned_size_and_unique_slugs() -> None:
    assert 60 <= len(SEED) <= 80
    slugs = [e["slug"] for e in SEED]
    assert len(set(slugs)) == len(slugs)
    assert len({catalog.search_key(e["name"]) for e in SEED}) == len(SEED)


@pytest.mark.parametrize("item", SEED, ids=[e["slug"] for e in SEED])
def test_every_seed_exercise_is_consistent(item: dict) -> None:
    assert item["equipment"] in catalog.EQUIPMENT
    assert item["mechanics"] in catalog.MECHANICS
    assert item["load_type"] in catalog.LOAD_TYPES
    assert item["primary"], "precisa de ao menos um músculo principal"
    all_muscles = item["primary"] + item["secondary"]
    assert set(all_muscles) <= set(catalog.MUSCLE_NAMES)
    assert len(set(all_muscles)) == len(all_muscles), "músculo repetido"
    assert len(item["name"]) <= 80
    assert 40 <= len(item["instructions"]) <= 400


def test_every_muscle_group_has_exercises_as_primary() -> None:
    primaries = {m for e in SEED for m in e["primary"]}
    assert primaries == set(catalog.MUSCLE_NAMES)


def test_search_key_and_slug_ignore_accents_and_case() -> None:
    assert catalog.search_key("  Tríceps   FRANCÊS ") == "triceps frances"
    assert catalog.slugify("Elevação pélvica (hip thrust)") == "elevacao-pelvica-hip-thrust"


# --- catálogo público ---


def test_muscle_groups_are_public_stable_and_ordered(client: TestClient) -> None:
    response = client.get("/api/v1/muscle-groups")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=3600"
    body = response.json()
    assert [m["id"] for m in body] == [m.id for m in catalog.MUSCLE_GROUPS]
    assert body[0] == {"id": "chest", "name": "Peito", "body_region": "upper", "view": "front"}


def test_exercise_options_list_every_vocabulary(client: TestClient) -> None:
    body = client.get("/api/v1/exercise-options").json()

    assert len(body["muscle_groups"]) == len(catalog.MUSCLE_GROUPS)
    assert [o["code"] for o in body["equipment"]] == list(catalog.EQUIPMENT)
    assert [o["code"] for o in body["mechanics"]] == ["compound", "isolation"]
    assert [o["code"] for o in body["load_types"]] == list(catalog.LOAD_TYPES)


# --- lista, busca e filtros ---


def test_list_requires_login(client: TestClient) -> None:
    assert client.get("/api/v1/exercises").status_code == 401


def test_list_returns_the_whole_catalog_in_alphabetical_order(client: TestClient, signup) -> None:
    listed = names(client.get("/api/v1/exercises", headers=signup()))

    assert len(listed) == len(SEED)
    assert listed == sorted(listed, key=catalog.search_key)


def test_seed_ids_are_the_same_everywhere(client: TestClient, signup) -> None:
    exercise_id = global_exercise_id("supino-reto-barra")
    body = client.get(f"/api/v1/exercises/{exercise_id}", headers=signup()).json()

    assert body["name"] == "Supino reto com barra"
    assert body["is_custom"] is False
    assert body["muscles"][0] == {"id": "chest", "name": "Peito", "role": "primary"}
    assert {m["id"] for m in body["muscles"] if m["role"] == "secondary"} == {"triceps", "delts"}


def test_search_ignores_accents_and_needs_every_word(client: TestClient, signup) -> None:
    headers = signup()

    triceps = names(client.get("/api/v1/exercises?q=triceps", headers=headers))
    assert triceps and all("Tríceps" in n for n in triceps)

    both = names(client.get("/api/v1/exercises?q=supino%20halteres", headers=headers))
    assert both == ["Supino inclinado com halteres", "Supino reto com halteres"]

    # Curinga do SQL não vira curinga na busca.
    assert names(client.get("/api/v1/exercises?q=%25", headers=headers)) == []


def test_filter_by_muscle_and_equipment(client: TestClient, signup) -> None:
    headers = signup()

    glutes = client.get("/api/v1/exercises?muscle=glutes", headers=headers).json()
    assert glutes
    assert all(any(m["id"] == "glutes" for m in e["muscles"]) for e in glutes)

    home = client.get(
        "/api/v1/exercises?equipment=bodyweight&equipment=bands", headers=headers
    ).json()
    assert {e["equipment"] for e in home} == {"bodyweight", "bands"}
    expected = sum(1 for e in SEED if e["equipment"] in {"bodyweight", "bands"})
    assert len(home) == expected


# --- exercícios próprios ---


def test_create_custom_exercise(client: TestClient, signup) -> None:
    headers = signup()
    response = create(client, headers)

    assert response.status_code == 201
    body = response.json()
    assert response.headers["location"] == f"/api/v1/exercises/{body['id']}"
    assert body["is_custom"] is True
    assert body["is_active"] is True
    assert [m["id"] for m in body["muscles"]] == ["lats", "biceps"]
    assert "Remada no TRX" in names(client.get("/api/v1/exercises?q=trx", headers=headers))


@pytest.mark.parametrize(
    ("changes", "field"),
    [
        ({"muscles": [{"muscle_group_id": "lats", "role": "secondary"}]}, "muscles"),
        (
            {
                "muscles": [
                    {"muscle_group_id": "lats", "role": "primary"},
                    {"muscle_group_id": "lats", "role": "secondary"},
                ]
            },
            "muscles",
        ),
        ({"muscles": []}, "muscles"),
        (
            {"muscles": [{"muscle_group_id": "back", "role": "primary"}]},
            "muscles.0.muscle_group_id",
        ),
        ({"equipment": "trx"}, "equipment"),
        ({"load_type": "heavy"}, "load_type"),
        ({"name": "A"}, "name"),
        ({"owner_user_id": "00000000-0000-0000-0000-000000000000"}, "owner_user_id"),
    ],
)
def test_create_validates_fields(client: TestClient, signup, changes: dict, field: str) -> None:
    response = create(client, signup(), **changes)
    assert response.status_code == 422
    assert field_errors(response) == [field]


def test_duplicate_name_is_per_user(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    assert create(client, ana).status_code == 201

    duplicate = create(client, ana, name="  remada no trx ")
    assert duplicate.status_code == 409
    assert duplicate.json()["code"] == "exercise_exists"
    # Outra pessoa pode usar o mesmo nome; e o nome de um exercício do catálogo também.
    assert create(client, bia).status_code == 201
    assert create(client, ana, name="Supino reto com barra").status_code == 201


def test_custom_exercises_of_another_user_are_invisible(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com", "Bia")
    exercise = create(client, ana).json()
    url = f"/api/v1/exercises/{exercise['id']}"

    assert "Remada no TRX" not in names(client.get("/api/v1/exercises", headers=bia))
    assert client.get(url, headers=bia).status_code == 404
    assert client.patch(url, headers=bia, json={"name": "Roubado"}).status_code == 404
    assert client.get(url, headers=ana).json()["name"] == "Remada no TRX"


def test_update_custom_exercise_replaces_muscles(client: TestClient, signup) -> None:
    headers = signup()
    exercise = create(client, headers).json()

    response = client.patch(
        f"/api/v1/exercises/{exercise['id']}",
        headers=headers,
        json={
            "name": "Remada invertida",
            "muscles": [
                {"muscle_group_id": "lats", "role": "primary"},
                {"muscle_group_id": "traps", "role": "primary"},
            ],
            "instructions": "",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Remada invertida"
    assert {m["id"] for m in body["muscles"]} == {"lats", "traps"}
    assert body["instructions"] is None


def test_catalog_exercises_are_read_only(client: TestClient, signup) -> None:
    exercise_id = global_exercise_id("leg-press")
    response = client.patch(
        f"/api/v1/exercises/{exercise_id}", headers=signup(), json={"name": "Meu leg"}
    )
    assert response.status_code == 403
    assert response.json()["code"] == "exercise_read_only"


def test_required_fields_reject_null_on_update(client: TestClient, signup) -> None:
    headers = signup()
    exercise = create(client, headers).json()
    for field in ("name", "equipment", "muscles", "is_active"):
        response = client.patch(
            f"/api/v1/exercises/{exercise['id']}", headers=headers, json={field: None}
        )
        assert response.status_code == 422, field


def test_archived_exercises_leave_the_list_but_stay_reachable(client: TestClient, signup) -> None:
    headers = signup()
    exercise = create(client, headers).json()
    url = f"/api/v1/exercises/{exercise['id']}"

    client.patch(url, headers=headers, json={"is_active": False})

    assert "Remada no TRX" not in names(client.get("/api/v1/exercises", headers=headers))
    archived = names(
        client.get("/api/v1/exercises?mine=true&include_archived=true", headers=headers)
    )
    assert archived == ["Remada no TRX"]
    assert client.get(url, headers=headers).json()["is_active"] is False


def test_custom_exercise_limit(client: TestClient, signup, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(service, "MAX_CUSTOM", 2)
    headers = signup()
    assert create(client, headers, name="Um").status_code == 201
    assert create(client, headers, name="Dois").status_code == 201

    response = create(client, headers, name="Três")
    assert response.status_code == 409
    assert response.json()["code"] == "exercise_limit"


def test_hypertrophy_goal_uses_the_same_muscle_groups(client: TestClient) -> None:
    options = client.get("/api/v1/goal-options").json()
    hypertrophy = next(k for k in options["kinds"] if k["code"] == "hypertrophy")
    muscle_field = hypertrophy["fields"][0]
    assert [o["code"] for o in muscle_field["options"]] == [m.id for m in catalog.MUSCLE_GROUPS]


def test_muscles_come_primary_first_in_catalog_order(client: TestClient, signup) -> None:
    exercise_id = global_exercise_id("remada-curvada-barra")
    muscles = client.get(f"/api/v1/exercises/{exercise_id}", headers=signup()).json()["muscles"]
    # Ordem do catálogo (Ombros antes de Bíceps), não a alfabética dos códigos.
    assert [m["id"] for m in muscles] == ["lats", "traps", "delts", "biceps"]


# --- fotos do catálogo (free-exercise-db, ADR-030) ---


def test_image_mapping_points_to_seed_exercises_and_existing_files() -> None:
    mapping = json.loads((SEED_DIR / "images.v1.json").read_text(encoding="utf-8"))["images"]
    seed_slugs = {e["slug"] for e in SEED}

    assert set(mapping) <= seed_slugs
    assert len(mapping) == 67
    for slug in mapping:
        for index in (0, 1):
            image = IMAGES_DIR / slug / f"{index}.jpg"
            assert image.read_bytes()[:2] == b"\xff\xd8", image


def test_catalog_exercise_lists_its_photos_and_they_are_served(client: TestClient, signup) -> None:
    exercise_id = global_exercise_id("leg-press")
    body = client.get(f"/api/v1/exercises/{exercise_id}", headers=signup()).json()

    assert body["images"] == [
        "/api/v1/media/exercises/leg-press/0.jpg",
        "/api/v1/media/exercises/leg-press/1.jpg",
    ]
    photo = client.get(body["images"][0])
    assert photo.status_code == 200
    assert photo.headers["content-type"] == "image/jpeg"
    assert photo.headers["cache-control"] == "public, max-age=86400"


def test_exercises_without_photos_return_an_empty_list(client: TestClient, signup) -> None:
    headers = signup()
    swing = global_exercise_id("kettlebell-swing")
    assert client.get(f"/api/v1/exercises/{swing}", headers=headers).json()["images"] == []
    assert create(client, headers).json()["images"] == []


def test_media_route_does_not_leave_the_images_folder(client: TestClient) -> None:
    # Codificado, para o cliente HTTP não normalizar o ".." antes de enviar.
    assert client.get("/api/v1/media/exercises/%2e%2e/images.v1.json").status_code == 404
    assert client.get("/api/v1/media/exercises/%2e%2e/__init__.py").status_code == 404
    assert client.get("/api/v1/media/exercises/leg-press/9.jpg").status_code == 404
