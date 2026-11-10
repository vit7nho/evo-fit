"""Autorização entre usuários em todos os endpoints (etapa 2.10).

A Ana monta um "mundo" completo (meta, exercício próprio, ficha, treino finalizado e treino
em andamento com séries). A Bia tenta ler, mudar e apagar cada coisa da Ana — pelos ids na
URL, misturando ids dela com os da Ana e referenciando os da Ana no corpo. Nada pode vazar
nem mudar. Uma checagem compara a lista de operações com o OpenAPI: endpoint novo sem
classificação aqui faz o teste falhar.
"""

import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.modules.auth import tokens
from tests.conftest import Clock
from tests.test_activities import RUN
from tests.test_exercises import CUSTOM
from tests.test_goals import STRENGTH
from tests.test_sessions import SUPINO, TEMPLATE

API = "/api/v1"
SESSIONS = f"{API}/workout-sessions"

PUBLIC = {
    ("GET", "/api/v1/health"),
    ("POST", "/api/v1/auth/register"),
    ("POST", "/api/v1/auth/login"),
    ("POST", "/api/v1/auth/refresh"),
    ("POST", "/api/v1/auth/logout"),
    ("GET", "/api/v1/profile-options"),
    ("GET", "/api/v1/goal-options"),
    ("GET", "/api/v1/muscle-groups"),
    ("GET", "/api/v1/exercise-options"),
    ("GET", "/api/v1/workout-options"),
    ("GET", "/api/v1/activity-options"),
}

# Operação autenticada -> corpo válido (None: sem corpo). Os ids no caminho são da Ana.
PROTECTED: dict[tuple[str, str], dict | None] = {
    ("GET", "/api/v1/me"): None,
    ("PATCH", "/api/v1/me"): {"display_name": "Outra"},
    ("PUT", "/api/v1/me/consents/{kind}"): None,
    ("DELETE", "/api/v1/me/consents/{kind}"): None,
    ("GET", "/api/v1/goals"): None,
    ("POST", "/api/v1/goals"): STRENGTH,
    ("GET", "/api/v1/goals/{goal_id}"): None,
    ("PATCH", "/api/v1/goals/{goal_id}"): {"title": "Roubada"},
    ("DELETE", "/api/v1/goals/{goal_id}"): None,
    ("GET", "/api/v1/exercises"): None,
    ("POST", "/api/v1/exercises"): {**CUSTOM, "name": "Outro exercício"},
    ("GET", "/api/v1/exercises/{exercise_id}"): None,
    ("PATCH", "/api/v1/exercises/{exercise_id}"): {"name": "Roubado"},
    ("GET", "/api/v1/workout-templates"): None,
    ("POST", "/api/v1/workout-templates"): TEMPLATE,
    ("PUT", "/api/v1/workout-templates/order"): {"template_ids": []},
    ("GET", "/api/v1/workout-templates/{template_id}"): None,
    ("PUT", "/api/v1/workout-templates/{template_id}"): {**TEMPLATE, "name": "Roubada"},
    ("DELETE", "/api/v1/workout-templates/{template_id}"): None,
    ("POST", "/api/v1/workout-sessions"): {},
    ("GET", "/api/v1/workout-sessions"): None,
    ("GET", "/api/v1/workout-sessions/current"): None,
    ("GET", "/api/v1/workout-sessions/{session_id}"): None,
    ("POST", "/api/v1/workout-sessions/{session_id}/pause"): None,
    ("POST", "/api/v1/workout-sessions/{session_id}/resume"): None,
    ("POST", "/api/v1/workout-sessions/{session_id}/finish"): {},
    ("POST", "/api/v1/workout-sessions/{session_id}/discard"): None,
    ("POST", "/api/v1/workout-sessions/{session_id}/exercises"): {"exercise_id": SUPINO},
    ("PATCH", "/api/v1/workout-sessions/{session_id}/exercises/{entry_id}"): {"rest_s": 30},
    ("DELETE", "/api/v1/workout-sessions/{session_id}/exercises/{entry_id}"): None,
    ("POST", "/api/v1/workout-sessions/{session_id}/exercises/{entry_id}/sets"): {"reps": 1},
    (
        "PATCH",
        "/api/v1/workout-sessions/{session_id}/exercises/{entry_id}/sets/{set_id}",
    ): {"reps": 1},
    (
        "DELETE",
        "/api/v1/workout-sessions/{session_id}/exercises/{entry_id}/sets/{set_id}",
    ): None,
    ("GET", "/api/v1/exercises/{exercise_id}/history"): None,
    ("GET", "/api/v1/analytics/records"): None,
    ("GET", "/api/v1/analytics/overview"): None,
    ("GET", "/api/v1/analytics/endurance"): None,
    ("GET", "/api/v1/analytics/compare"): None,
    ("GET", "/api/v1/analytics/muscles"): None,
    ("GET", "/api/v1/analytics/muscles/{muscle_id}"): None,
    ("GET", "/api/v1/activities"): None,
    ("POST", "/api/v1/activities"): RUN,
    ("GET", "/api/v1/activities/{activity_id}"): None,
    ("PATCH", "/api/v1/activities/{activity_id}"): {"duration_s": 60},
    ("DELETE", "/api/v1/activities/{activity_id}"): None,
    ("GET", "/api/v1/training-plan-templates"): None,
    ("GET", "/api/v1/training-plans"): None,
    ("POST", "/api/v1/training-plans"): {"kind": "walk_habit", "weekdays": [0, 1, 2]},
    ("GET", "/api/v1/training-plans/{plan_id}"): None,
    ("POST", "/api/v1/training-plans/{plan_id}/end"): None,
    ("PUT", "/api/v1/training-plans/{plan_id}/sessions/{plan_session_id}/activity"): {
        "activity_id": str(uuid.uuid4())
    },
    ("DELETE", "/api/v1/training-plans/{plan_id}/sessions/{plan_session_id}/activity"): None,
}

# Operações sobre um registro identificado na URL: com o id de outra conta, só 404.
# (O músculo é do catálogo, de todos: o que muda são os dados de cada um, testados abaixo.)
OWNED = [op for op in PROTECTED if "_id}" in op[1] and "{muscle_id}" not in op[1]]


def send(client: TestClient, op: tuple[str, str], headers: dict[str, str], ids: dict):
    method, path = op
    body = PROTECTED[op]
    kwargs = {"json": body} if body is not None else {}
    return client.request(method, path.format(**ids), headers=headers, **kwargs)


def ok(response, status: int = 200) -> dict:
    assert response.status_code == status, response.text
    return response.json()


def build_world(client: TestClient, headers: dict[str, str]) -> dict[str, str]:
    """Um de cada: consentimento, meta, exercício próprio, ficha, dois treinos, uma corrida
    e um plano com a corrida marcada na primeira sessão."""
    ok(client.put(f"{API}/me/consents/health_data", headers=headers))
    goal = ok(client.post(f"{API}/goals", headers=headers, json=STRENGTH), 201)
    exercise = ok(client.post(f"{API}/exercises", headers=headers, json=CUSTOM), 201)
    template = ok(client.post(f"{API}/workout-templates", headers=headers, json=TEMPLATE), 201)

    done = ok(client.post(SESSIONS, headers=headers, json={"template_id": template["id"]}), 201)
    done_entry = done["exercises"][0]["id"]
    for load in (60, 100):
        ok(
            client.post(
                f"{SESSIONS}/{done['id']}/exercises/{done_entry}/sets",
                headers=headers,
                json={"reps": 5, "load_kg": load},
            ),
            201,
        )
    ok(client.post(f"{SESSIONS}/{done['id']}/finish", headers=headers, json={}))

    live = ok(client.post(SESSIONS, headers=headers, json={"template_id": template["id"]}), 201)
    entry = live["exercises"][0]["id"]
    sets = f"{SESSIONS}/{live['id']}/exercises/{entry}/sets"
    main = ok(client.post(sets, headers=headers, json={"reps": 8, "load_kg": 80}), 201)
    ok(
        client.post(
            sets,
            headers=headers,
            json={"kind": "drop", "parent_set_id": main["id"], "reps": 6, "load_kg": 60},
        ),
        201,
    )
    added = ok(
        client.post(
            f"{SESSIONS}/{live['id']}/exercises",
            headers=headers,
            json={"exercise_id": exercise["id"]},
        ),
        201,
    )
    run = ok(client.post(f"{API}/activities", headers=headers, json=RUN), 201)
    plan = ok(
        client.post(
            f"{API}/training-plans", headers=headers, json={"kind": "run_5k", "weekdays": [0, 2, 4]}
        ),
        201,
    )
    first = plan["sessions"][0]["id"]
    ok(
        client.put(
            f"{API}/training-plans/{plan['id']}/sessions/{first}/activity",
            headers=headers,
            json={"activity_id": run["id"]},
        )
    )
    return {
        "plan_id": plan["id"],
        "plan_session_id": first,
        "activity_id": run["id"],
        "goal_id": goal["id"],
        "exercise_id": exercise["id"],
        "template_id": template["id"],
        "session_id": live["id"],
        "entry_id": entry,
        "set_id": main["id"],
        "custom_entry_id": added["exercises"][-1]["id"],
        "done_session_id": done["id"],
        "done_entry_id": done_entry,
        "kind": "health_data",
        "muscle_id": "chest",
    }


def snapshot(client: TestClient, headers: dict[str, str], ids: dict) -> dict:
    """Tudo o que a dona vê; precisa ficar idêntico depois dos ataques."""
    urls = [
        f"{API}/me",
        f"{API}/goals",
        f"{API}/exercises?mine=true&include_archived=true",
        f"{API}/workout-templates",
        SESSIONS,
        f"{SESSIONS}/current",
        f"{SESSIONS}/{ids['session_id']}",
        f"{SESSIONS}/{ids['done_session_id']}",
        f"{API}/exercises/{SUPINO}/history",
        f"{API}/exercises/{ids['exercise_id']}/history",
        f"{API}/analytics/records",
        f"{API}/activities",
        f"{API}/activities/{ids['activity_id']}",
        f"{API}/training-plans",
        f"{API}/training-plans/{ids['plan_id']}",
    ]
    return {url: ok(client.get(url, headers=headers)) for url in urls}


@pytest.fixture
def ana(signup) -> dict[str, str]:
    return signup("ana@exemplo.com", "Ana")


@pytest.fixture
def bia(signup) -> dict[str, str]:
    return signup("bia@exemplo.com", "Bia")


@pytest.fixture
def world(
    client: TestClient, ana: dict[str, str], clock: Clock, plans_from_yesterday
) -> dict[str, str]:
    # Relógio parado: o tempo decorrido do treino em andamento não muda entre os retratos.
    return build_world(client, ana)


# --- cobertura ---


def test_every_operation_is_classified(app: FastAPI) -> None:
    """Endpoint novo precisa entrar em PUBLIC ou PROTECTED (e ganhar os testes abaixo)."""
    schema = app.openapi()
    operations = {
        (method.upper(), path) for path, item in schema["paths"].items() for method in item
    }
    assert operations == PUBLIC | PROTECTED.keys()

    # O que o OpenAPI anuncia como protegido é exatamente o que tratamos como protegido.
    secured = {
        (method.upper(), path)
        for path, item in schema["paths"].items()
        for method, operation in item.items()
        if operation.get("security")
    }
    assert secured == PROTECTED.keys()


# --- sem credencial válida: 401 em tudo ---


def _forged_tokens(client: TestClient) -> dict[str, dict[str, str]]:
    settings = get_settings()
    pair = client.post(
        f"{API}/auth/register",
        json={
            "email": "cris@exemplo.com",
            "password": "cavalo bateria grampo",
            "display_name": "Cris",
            "accept_terms": True,
        },
    ).json()
    user_id = uuid.UUID(
        jwt.decode(pair["access_token"], options={"verify_signature": False})["sub"]
    )
    claims = jwt.decode(pair["access_token"], options={"verify_signature": False})

    expired, _ = tokens.create_access_token(
        user_id, settings, now=datetime.now(UTC) - timedelta(hours=1)
    )
    other_secret = settings.model_copy(
        update={"jwt_secret": type(settings.jwt_secret)("outro-segredo-que-nao-e-o-da-api-0123")}
    )
    wrong_key, _ = tokens.create_access_token(user_id, other_secret)
    ghost, _ = tokens.create_access_token(uuid.uuid4(), settings)
    unsigned = jwt.encode(claims, None, algorithm="none")

    bearer = {
        "expirado": expired,
        "outra-chave": wrong_key,
        "alg-none": unsigned,
        "conta-inexistente": ghost,
        "refresh-como-access": pair["refresh_token"],
        "lixo": "nao.e.um.jwt",
    }
    return {
        "sem-cabecalho": {},
        "basic": {"Authorization": "Basic YW5hOnNlbmhh"},
        **{name: {"Authorization": f"Bearer {token}"} for name, token in bearer.items()},
    }


CREDENTIALS = [
    "sem-cabecalho",
    "basic",
    "lixo",
    "expirado",
    "outra-chave",
    "alg-none",
    "conta-inexistente",
    "refresh-como-access",
]


@pytest.mark.parametrize("credential", CREDENTIALS)
def test_every_protected_operation_requires_a_valid_token(
    client: TestClient, world: dict, ana: dict, credential: str
) -> None:
    headers = _forged_tokens(client)[credential]
    before = snapshot(client, ana, world)

    wrong = {}
    for op in PROTECTED:
        response = send(client, op, headers, world)
        if response.status_code != 401 or response.json().get("code") not in {
            "not_authenticated",
            "invalid_token",
        }:
            wrong[op] = (response.status_code, response.text[:120])
    assert wrong == {}
    assert snapshot(client, ana, world) == before


# --- ids da Ana na URL ---


@pytest.mark.parametrize("live", [True, False], ids=["treino-em-andamento", "treino-finalizado"])
def test_another_users_records_are_404_everywhere(
    client: TestClient, world: dict, ana: dict, bia: dict, live: bool
) -> None:
    ids = dict(world)
    if not live:
        ids |= {"session_id": world["done_session_id"], "entry_id": world["done_entry_id"]}
        done = client.get(f"{SESSIONS}/{ids['session_id']}", headers=ana).json()
        ids["set_id"] = done["exercises"][0]["sets"][0]["id"]
    before = snapshot(client, ana, world)

    wrong = {}
    for op in OWNED:
        response = send(client, op, bia, ids)
        body = response.json()
        # O 404 não diz se o registro existe em outra conta: igual ao de um id inventado.
        if response.status_code != 404 or body.get("code") != "not_found":
            wrong[op] = (response.status_code, response.text[:120])
    assert wrong == {}
    assert snapshot(client, ana, world) == before


def test_404_for_another_user_is_identical_to_a_missing_id(
    client: TestClient, world: dict, bia: dict
) -> None:
    random_ids = {key: str(uuid.uuid4()) for key in world} | {"kind": world["kind"]}
    for op in OWNED:
        theirs = send(client, op, bia, world).json()
        missing = send(client, op, bia, random_ids).json()
        theirs.pop("request_id", None)
        missing.pop("request_id", None)
        assert theirs == missing, op


# --- ids misturados: o caminho da Bia com um pedaço da Ana ---


def test_mixing_own_ids_with_another_users_ids(
    client: TestClient, world: dict, ana: dict, bia: dict
) -> None:
    template = ok(client.post(f"{API}/workout-templates", headers=bia, json=TEMPLATE), 201)
    session = ok(client.post(SESSIONS, headers=bia, json={"template_id": template["id"]}), 201)
    entry = session["exercises"][0]["id"]
    own_set = ok(
        client.post(
            f"{SESSIONS}/{session['id']}/exercises/{entry}/sets", headers=bia, json={"reps": 5}
        ),
        201,
    )
    before = snapshot(client, ana, world)

    combos = [
        # sessão da Bia + exercício do treino da Ana
        {"session_id": session["id"], "entry_id": world["entry_id"], "set_id": world["set_id"]},
        # sessão e exercício da Bia + série da Ana
        {"session_id": session["id"], "entry_id": entry, "set_id": world["set_id"]},
        # sessão da Ana + exercício e série da Bia
        {"session_id": world["session_id"], "entry_id": entry, "set_id": own_set["id"]},
    ]
    nested = [op for op in OWNED if "{entry_id}" in op[1]]
    for ids in combos:
        for op in nested:
            if "{set_id}" not in op[1] and ids["entry_id"] == entry:
                continue  # sessão e exercício da própria Bia: operação legítima
            response = send(client, op, bia, ids)
            assert response.status_code == 404, (op, ids, response.text)
    assert snapshot(client, ana, world) == before


# --- ids da Ana no corpo ---


def field_errors(response) -> list[str]:
    return [e["field"] for e in response.json().get("errors", [])]


def test_body_cannot_reference_another_users_records(
    client: TestClient, world: dict, ana: dict, bia: dict
) -> None:
    before = snapshot(client, ana, world)
    theirs = world["exercise_id"]
    with_their_exercise = {
        "name": "Com exercício alheio",
        "items": [{"exercise_id": theirs, "planned_sets": [{"reps_min": 8}]}],
    }

    # Ficha com o exercício próprio da Ana: nem criar nem regravar.
    response = client.post(f"{API}/workout-templates", headers=bia, json=with_their_exercise)
    assert response.status_code == 422, response.text
    mine = ok(client.post(f"{API}/workout-templates", headers=bia, json=TEMPLATE), 201)
    response = client.put(
        f"{API}/workout-templates/{mine['id']}", headers=bia, json=with_their_exercise
    )
    assert response.status_code == 422, response.text

    # Ordenar as fichas incluindo a da Ana.
    response = client.put(
        f"{API}/workout-templates/order",
        headers=bia,
        json={"template_ids": [mine["id"], world["template_id"]]},
    )
    assert response.status_code == 422, response.text

    # Iniciar um treino a partir da ficha da Ana.
    response = client.post(SESSIONS, headers=bia, json={"template_id": world["template_id"]})
    assert response.status_code in {404, 422}, response.text

    # No próprio treino: acrescentar o exercício da Ana ou encadear na série dela.
    session = ok(client.post(SESSIONS, headers=bia, json={"template_id": mine["id"]}), 201)
    response = client.post(
        f"{SESSIONS}/{session['id']}/exercises", headers=bia, json={"exercise_id": theirs}
    )
    assert response.status_code == 422, response.text
    entry = session["exercises"][0]["id"]
    response = client.post(
        f"{SESSIONS}/{session['id']}/exercises/{entry}/sets",
        headers=bia,
        json={"kind": "drop", "parent_set_id": world["set_id"], "reps": 5},
    )
    assert response.status_code == 422, response.text

    # No próprio plano: marcar a sessão com a corrida da Ana.
    plan = ok(
        client.post(
            f"{API}/training-plans", headers=bia, json={"kind": "run_5k", "weekdays": [1, 3, 5]}
        ),
        201,
    )
    response = client.put(
        f"{API}/training-plans/{plan['id']}/sessions/{plan['sessions'][0]['id']}/activity",
        headers=bia,
        json={"activity_id": world["activity_id"]},
    )
    assert response.status_code == 422, response.text
    assert field_errors(response) == ["activity_id"]

    assert snapshot(client, ana, world) == before


@pytest.mark.parametrize(
    ("path", "body"),
    [
        ("/goals", {**STRENGTH, "user_id": None}),
        ("/exercises", {**CUSTOM, "name": "Dona falsa", "owner_id": None}),
        ("/workout-templates", {**TEMPLATE, "user_id": None}),
        ("/workout-sessions", {"user_id": None}),
        ("/training-plans", {"kind": "walk_habit", "weekdays": [0, 1, 2], "user_id": None}),
    ],
)
def test_client_cannot_choose_the_owner(
    client: TestClient, world: dict, ana: dict, bia: dict, path: str, body: dict
) -> None:
    ana_id = client.get(f"{API}/me", headers=ana).json()["id"]
    body = {
        key: (ana_id if value is None and key.endswith("_id") else value)
        for key, value in body.items()
    }
    before = snapshot(client, ana, world)

    response = client.post(f"{API}{path}", headers=bia, json=body)
    assert response.status_code == 422, response.text
    assert snapshot(client, ana, world) == before


def test_profile_update_cannot_touch_identity_fields(client: TestClient, bia: dict) -> None:
    me = client.get(f"{API}/me", headers=bia).json()
    for field, value in [
        ("id", str(uuid.uuid4())),
        ("email", "ana@exemplo.com"),
        ("status", "disabled"),
    ]:
        response = client.patch(f"{API}/me", headers=bia, json={field: value})
        assert response.status_code == 422, (field, response.text)
    assert client.get(f"{API}/me", headers=bia).json() == me


# --- listas e cálculos só com os dados da própria conta ---


def test_lists_and_derived_data_never_include_another_user(
    client: TestClient, world: dict, ana: dict, bia: dict
) -> None:
    ana_view = snapshot(client, ana, world)
    markers = {value for key, value in world.items() if key not in {"kind", "muscle_id"}}
    markers |= {CUSTOM["name"], ana_view[f"{API}/me"]["email"], "Ana"}

    # A Bia treina o mesmo supino (exercício do catálogo) que a Ana.
    template = ok(client.post(f"{API}/workout-templates", headers=bia, json=TEMPLATE), 201)
    session = ok(client.post(SESSIONS, headers=bia, json={"template_id": template["id"]}), 201)
    # Pré-preenchimento vem do histórico da Bia (vazio), nunca do da Ana.
    assert session["exercises"][0]["previous"] == []
    assert session["exercises"][0]["previous_at"] is None
    entry = session["exercises"][0]["id"]
    ok(
        client.post(
            f"{SESSIONS}/{session['id']}/exercises/{entry}/sets",
            headers=bia,
            json={"reps": 5, "load_kg": 20},
        ),
        201,
    )
    ok(client.post(f"{SESSIONS}/{session['id']}/finish", headers=bia, json={}))

    urls = [
        f"{API}/me",
        f"{API}/goals",
        f"{API}/exercises",
        f"{API}/exercises?mine=true&include_archived=true",
        f"{API}/exercises?q=TRX",
        f"{API}/workout-templates",
        SESSIONS,
        f"{SESSIONS}/{session['id']}",
        f"{API}/exercises/{SUPINO}/history",
        f"{API}/analytics/records",
        f"{API}/activities",
        f"{API}/training-plans",
        f"{API}/training-plan-templates",
    ]
    for url in urls:
        text = client.get(url, headers=bia).text
        leaked = [marker for marker in markers if marker in text]
        assert leaked == [], (url, leaked)

    # O aviso do 10 km olha só as corridas dela (a Ana correu 5 km).
    offered = client.get(f"{API}/training-plan-templates", headers=bia).json()
    assert {t["kind"]: t["note"] for t in offered}["run_10k"] is not None

    # Indicadores só com os registros dela: a corrida da Ana (de hoje) não aparece.
    summary = client.get(f"{API}/analytics/overview", headers=bia).json()
    assert "run" not in [m["modality"] for m in summary["modalities"]]
    # Os treinos (relógio parado em 01/11/2026): só o dela, não os da Ana.
    week = client.get(f"{API}/analytics/overview?from=2026-10-26&to=2026-11-01", headers=bia).json()
    assert week["sessions"] == 1
    assert week["modalities"][0]["volume_kg"] == 100  # 5 x 20 kg (a Ana chegou a 100 kg)
    runs = client.get(f"{API}/analytics/endurance?modality=run", headers=bia).json()
    assert (runs["sessions"], runs["distance_m"]) == (0, 0)
    today = summary["to_date"]
    compared = client.get(
        f"{API}/analytics/compare?metric=distance_m&modality=run"
        f"&a_from={today}&a_to={today}&b_from={today}&b_to={today}",
        headers=bia,
    ).json()
    assert compared["b"]["value"] == 0

    # Meu Corpo só com as séries dela: 1 série de supino (a Ana fez 2 no mesmo dia).
    body = client.get(f"{API}/analytics/muscles?from=2026-10-26&to=2026-11-01", headers=bia).json()
    chest = next(m for m in body["muscles"] if m["muscle_id"] == "chest")
    assert (chest["weighted_sets"], chest["volume_load_kg"]) == (1.0, 100.0)
    detail = client.get(
        f"{API}/analytics/muscles/chest?from=2026-10-26&to=2026-11-01", headers=bia
    ).json()
    assert [e["sets"] for e in detail["exercises"]] == [1]
    assert [p["best_load_kg"] for p in detail["loads"]] == [20.0]

    # Só os consentimentos dela (a Ana autorizou dados de saúde; a Bia, não).
    consents = client.get(f"{API}/me", headers=bia).json()["consents"]
    assert [c["kind"] for c in consents] == ["terms_privacy"]
    response = client.patch(f"{API}/me", headers=bia, json={"limitation_tags": ["knee"]})
    assert response.status_code == 403

    # Recorde e histórico do supino só com a carga da Bia (a Ana chegou a 100 kg).
    records = client.get(f"{API}/analytics/records", headers=bia).json()
    loads = [r["value"] for item in records for r in item["records"] if r["kind"] == "max_load"]
    assert loads == [20]
    history = client.get(f"{API}/exercises/{SUPINO}/history", headers=bia).json()
    assert len(history["sessions"]) == 1
    assert client.get(f"{SESSIONS}/current", headers=bia).status_code == 204
