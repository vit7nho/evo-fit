"""Propostas de alteração da IA (4.6): a ferramenta valida pelas regras da ficha ou da
meta sem mudar nada; só a confirmação aplica (validando de novo); ficha alterada
depois, proposta recusada ou vencida não aplicam nada; e tudo só para o dono."""

# ruff: noqa: F811  (a fixture two_people vem de test_ai_tools)
import json
import uuid
from datetime import date, timedelta

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.integrations.ai.errors import InvalidModelOutput
from app.integrations.ai.provider import Completion, ToolCall, Usage
from app.integrations.ai.providers.fake import FakeProvider, FakeRequest
from app.modules.ai_coach import prompts, proposals
from app.modules.ai_coach import service as ai_service
from app.modules.ai_coach.models import ChangeProposal
from app.modules.ai_coach.router import get_provider_factory
from app.modules.ai_coach.tools import base, registry
from app.modules.ai_coach.tools.base import ToolContext
from app.modules.exercises.seed import global_exercise_id
from tests.conftest import Clock
from tests.test_ai_tools import (
    two_people,  # noqa: F401  (fixture)
    user_of,
)
from tests.test_analytics import ok
from tests.test_exercises import CUSTOM
from tests.test_sessions import CRUCIFIXO, PRANCHA, TEMPLATE

API = "/api/v1"
MESA = str(global_exercise_id("mesa-flexora"))


@pytest.fixture(autouse=True)
def fixed_clock(monkeypatch: pytest.MonkeyPatch, clock: Clock) -> None:
    monkeypatch.setattr(base, "today", lambda user: date(2026, 11, 1))
    monkeypatch.setattr(ai_service, "_now", lambda: clock.now)


@pytest.fixture
def ana(client: TestClient, two_people) -> dict:
    """A Ana com o consentimento de IA, a ficha "Treino A" e uma conversa."""
    headers = two_people["ana"]
    ok(client.put(f"{API}/me/consents/ai_processing", headers=headers))
    template = ok(client.post(f"{API}/workout-templates", headers=headers, json=TEMPLATE), 201)
    chat = ok(client.post(f"{API}/ai/conversations", headers=headers, json={}), 201)
    return {"headers": headers, "template": template, "chat": chat["id"]}


def call(db: Session, ana: dict, tool: str, email: str = "ana@exemplo.com", **arguments):
    ctx = ToolContext(db, user_of(db, email), uuid.UUID(ana["chat"]))
    result = registry.execute(ctx, ToolCall("c1", tool, arguments))
    db.commit()  # como o chat: a proposta fica gravada com a resposta
    return json.loads(result.content), result.is_error


def propose(db: Session, ana: dict, change: dict, email: str = "ana@exemplo.com"):
    return call(db, ana, "prepare_change_proposal", email, change=change, rationale="Pelos dados.")


def add_mesa(ana: dict) -> dict:
    return {
        "kind": "template_add_exercise",
        "template_id": ana["template"]["id"],
        "exercise_id": MESA,
        "planned_sets": [{"reps_min": 10, "reps_max": 12}] * 3,
        "rest_s": 90,
    }


def item(ana: dict, index: int) -> str:
    return ana["template"]["items"][index]["id"]


def template_now(client: TestClient, ana: dict) -> dict:
    return ok(
        client.get(f"{API}/workout-templates/{ana['template']['id']}", headers=ana["headers"])
    )


def decide(client: TestClient, ana: dict, proposal_id: str, action: str, headers=None):
    return client.post(
        f"{API}/ai/proposals/{proposal_id}/{action}", headers=headers or ana["headers"]
    )


# --- leitura das fichas ---


def test_get_templates_gives_ids_exercises_and_sets(db: Session, ana: dict) -> None:
    body, is_error = call(db, ana, "get_templates")
    assert not is_error
    ficha = next(f for f in body["items"] if f["template_id"] == ana["template"]["id"])
    assert ficha["name"] == "Treino A"
    assert [i["item_id"] for i in ficha["items"]] == [i["id"] for i in ana["template"]["items"]]
    assert ficha["items"][0]["sets_text"] == "3 séries de 8 a 12 reps"
    assert ficha["items"][0]["primary_muscles"] == ["chest"]
    assert [i["group"] for i in ficha["items"]] == [None, "Bi-set", "Bi-set"]
    # A Bia não vê a ficha da Ana.
    body, _ = call(db, ana, "get_templates", "bia@exemplo.com")
    assert body["items"] == []


# --- acrescentar, ajustar, trocar ---


def test_add_exercise_changes_nothing_until_confirmed(
    client: TestClient, db: Session, ana: dict
) -> None:
    before = template_now(client, ana)
    body, is_error = propose(db, ana, add_mesa(ana))
    assert not is_error, body
    assert body["summary"] == "Acrescentar Mesa flexora à ficha “Treino A”"
    assert body["details"] == ["Séries: 3 séries de 10 a 12 reps", "Descanso: 90 s"]
    assert "não diga que a alteração já foi feita" in body["note"]
    assert template_now(client, ana) == before

    pending = ok(client.get(f"{API}/ai/proposals?status=pending", headers=ana["headers"]))
    assert [p["id"] for p in pending] == [body["proposal_id"]]
    assert pending[0]["rationale"] == "Pelos dados."

    applied = ok(decide(client, ana, body["proposal_id"], "accept"))
    assert applied["status"] == "accepted"
    assert applied["template_id"] == ana["template"]["id"]
    after = template_now(client, ana)
    assert [i["exercise"]["name"] for i in after["items"]][-1] == "Mesa flexora"
    assert [
        {k: v for k, v in s.items() if v is not None} for s in after["items"][-1]["planned_sets"]
    ] == [{"kind": "working", "reps_min": 10, "reps_max": 12}] * 3
    assert after["items"][-1]["rest_s"] == 90
    # O resto da ficha (bi-set incluído) continua igual.
    assert after["groups"] == [{**before["groups"][0], "id": after["groups"][0]["id"]}]
    assert len(after["items"]) == 4

    again = decide(client, ana, body["proposal_id"], "accept")
    assert again.status_code == 409
    assert again.json()["code"] == "proposal_not_pending"


def test_adjust_sets_shows_before_and_after(client: TestClient, db: Session, ana: dict) -> None:
    body, is_error = propose(
        db,
        ana,
        {
            "kind": "template_adjust_sets",
            "template_id": ana["template"]["id"],
            "item_id": item(ana, 0),
            "planned_sets": [{"reps_min": 6, "reps_max": 8, "load_kg": 62.5}] * 4,
        },
    )
    assert not is_error, body
    assert body["summary"] == "Ajustar as séries de Supino reto com barra na ficha “Treino A”"
    assert body["details"] == [
        "Antes: 3 séries de 8 a 12 reps",
        "Depois: 4 séries de 6 a 8 reps com 62.5 kg",
    ]
    ok(decide(client, ana, body["proposal_id"], "accept"))
    sets = template_now(client, ana)["items"][0]["planned_sets"]
    assert len(sets) == 4 and sets[0]["load_kg"] == 62.5

    # Mesmas séries de agora: nada a propor.
    body, is_error = propose(
        db,
        ana,
        {
            "kind": "template_adjust_sets",
            "template_id": ana["template"]["id"],
            "item_id": template_now(client, ana)["items"][0]["id"],
            "planned_sets": sets,
        },
    )
    assert is_error and body["error"] == "As séries propostas são iguais às atuais."


def test_replace_exercise_keeps_sets_and_follows_the_rules(
    client: TestClient, db: Session, ana: dict
) -> None:
    replace = {
        "kind": "template_replace_exercise",
        "template_id": ana["template"]["id"],
        "item_id": item(ana, 1),
    }
    body, is_error = propose(db, ana, {**replace, "exercise_id": MESA})
    assert not is_error, body
    assert body["summary"] == "Trocar Crucifixo com halteres por Mesa flexora na ficha “Treino A”"
    assert body["details"] == ["Séries mantidas: 1 série de 12 reps"]

    # A prancha é por tempo: séries de repetições não servem (regra da ficha).
    body, is_error = propose(db, ana, {**replace, "exercise_id": PRANCHA})
    assert is_error
    assert "é feito por tempo" in body["error"]
    # O mesmo exercício não é troca.
    body, is_error = propose(db, ana, {**replace, "exercise_id": CRUCIFIXO})
    assert is_error and body["error"] == "O exercício novo é o mesmo que já está na ficha."
    # Item que não é desta ficha.
    body, is_error = propose(
        db, ana, {**replace, "item_id": str(uuid.uuid4()), "exercise_id": MESA}
    )
    assert is_error and "Item não encontrado" in body["error"]
    assert len(db.scalars(select(ChangeProposal)).all()) == 1


def test_another_users_template_or_exercise_is_not_found(
    client: TestClient, db: Session, ana: dict, signup
) -> None:
    # A Bia tenta propor na ficha da Ana.
    body, is_error = propose(db, ana, add_mesa(ana), "bia@exemplo.com")
    assert is_error and body["error"] == "Ficha não encontrada. Consulte get_templates."
    # A Ana não pode usar o exercício próprio da Bia.
    bia = client.post(
        f"{API}/auth/login", json={"email": "bia@exemplo.com", "password": "cavalo bateria grampo"}
    ).json()
    custom = ok(
        client.post(
            f"{API}/exercises",
            headers={"Authorization": f"Bearer {bia['access_token']}"},
            json={**CUSTOM, "name": "Remada da Bia"},
        ),
        201,
    )
    body, is_error = propose(db, ana, {**add_mesa(ana), "exercise_id": custom["id"]})
    assert is_error and "Exercício não encontrado" in body["error"]
    assert db.scalars(select(ChangeProposal)).all() == []


def test_proposals_need_a_conversation_and_have_a_limit(db: Session, ana: dict) -> None:
    ctx = ToolContext(db, user_of(db, "ana@exemplo.com"))
    result = registry.execute(
        ctx,
        ToolCall(
            "c1", "prepare_change_proposal", {"change": add_mesa(ana), "rationale": "Pelos dados."}
        ),
    )
    assert result.is_error
    assert "dentro de uma conversa" in json.loads(result.content)["error"]

    for _ in range(proposals.MAX_PENDING):
        assert not propose(db, ana, add_mesa(ana))[1]
    body, is_error = propose(db, ana, add_mesa(ana))
    assert is_error and "aguardando a resposta" in body["error"]


# --- decisão ---


def test_a_template_changed_after_the_proposal_is_not_overwritten(
    client: TestClient, db: Session, ana: dict
) -> None:
    body, _ = propose(db, ana, add_mesa(ana))
    # A Ana edita a ficha no app antes de responder.
    edited = {**TEMPLATE, "name": "Treino A editado"}
    ok(
        client.put(
            f"{API}/workout-templates/{ana['template']['id']}", headers=ana["headers"], json=edited
        )
    )
    response = decide(client, ana, body["proposal_id"], "accept")
    assert response.status_code == 409
    assert response.json()["code"] == "proposal_stale"
    now = template_now(client, ana)
    assert now["name"] == "Treino A editado"
    assert "Mesa flexora" not in [i["exercise"]["name"] for i in now["items"]]
    [failed] = ok(client.get(f"{API}/ai/proposals?status=failed", headers=ana["headers"]))
    assert failed["result"].startswith("A ficha foi alterada depois da sugestão")


def test_reject_and_expire(
    client: TestClient, db: Session, ana: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    before = template_now(client, ana)
    rejected, _ = propose(db, ana, add_mesa(ana))
    late, _ = propose(db, ana, add_mesa(ana))
    assert ok(decide(client, ana, rejected["proposal_id"], "reject"))["status"] == "rejected"
    assert decide(client, ana, rejected["proposal_id"], "accept").status_code == 409

    real = proposals._now()
    monkeypatch.setattr(proposals, "_now", lambda: real + timedelta(days=8))
    response = decide(client, ana, late["proposal_id"], "accept")
    assert response.status_code == 409
    assert "expirou" in response.json()["detail"]
    statuses = {
        p["id"]: p["status"] for p in ok(client.get(f"{API}/ai/proposals", headers=ana["headers"]))
    }
    assert statuses == {rejected["proposal_id"]: "rejected", late["proposal_id"]: "expired"}
    assert template_now(client, ana) == before


def test_another_users_proposal_is_404(client: TestClient, db: Session, ana: dict) -> None:
    body, _ = propose(db, ana, add_mesa(ana))
    bia = client.post(
        f"{API}/auth/login", json={"email": "bia@exemplo.com", "password": "cavalo bateria grampo"}
    ).json()
    headers = {"Authorization": f"Bearer {bia['access_token']}"}
    for action in ("accept", "reject"):
        assert decide(client, ana, body["proposal_id"], action, headers).status_code == 404
    assert ok(client.get(f"{API}/ai/proposals", headers=headers)) == []
    assert ok(client.get(f"{API}/ai/proposals", headers=ana["headers"]))[0]["status"] == "pending"


# --- metas ---


def test_goal_proposal_creates_the_goal_on_confirmation(
    client: TestClient, db: Session, ana: dict
) -> None:
    goals_before = ok(client.get(f"{API}/goals", headers=ana["headers"]))
    body, is_error = propose(
        db,
        ana,
        {
            "kind": "goal_create",
            "goal_kind": "strength",
            "title": "Supino 70 kg",
            "target": {"exercise": "Supino reto com barra", "load_kg": 70, "reps": 5},
        },
    )
    assert not is_error, body
    assert body["summary"].startswith("Criar a meta “Supino 70 kg”")
    assert ok(client.get(f"{API}/goals", headers=ana["headers"])) == goals_before

    applied = ok(decide(client, ana, body["proposal_id"], "accept"))
    goals = ok(client.get(f"{API}/goals", headers=ana["headers"]))
    created = next(g for g in goals if g["title"] == "Supino 70 kg")
    assert applied["goal_id"] == created["id"]

    # As regras da meta valem na proposta: alvo fora do tipo é recusado.
    body, is_error = propose(
        db,
        ana,
        {
            "kind": "goal_create",
            "goal_kind": "run_distance",
            "title": "Correr",
            "target": {"km": 5},
        },
    )
    assert is_error


def test_weight_goal_without_health_consent_is_refused(db: Session, ana: dict) -> None:
    body, is_error = propose(
        db,
        ana,
        {
            "kind": "goal_create",
            "goal_kind": "weight_loss",
            "title": "Peso",
            "target": {"target_weight_kg": 70},
        },
        "bia@exemplo.com",
    )
    assert is_error
    assert "dados de saúde" in body["error"]


# --- no chat ---


def tool_use(*calls: tuple[str, dict]) -> Completion:
    return Completion(
        tool_calls=tuple(ToolCall(f"t{i}", n, a) for i, (n, a) in enumerate(calls)),
        stop_reason="tool_use",
        usage=Usage(10, 5),
        model="fake-v1",
    )


def test_the_chat_shows_the_proposal_and_only_confirmation_applies(
    app: FastAPI, client: TestClient, db: Session, ana: dict
) -> None:
    def propose_from_templates(request: FakeRequest) -> Completion:
        ficha = next(
            f
            for f in json.loads(request.messages[-1].tool_results[0].content)["items"]
            if f["template_id"] == ana["template"]["id"]
        )
        return tool_use(
            (
                "prepare_change_proposal",
                {
                    "change": {
                        "kind": "template_add_exercise",
                        "template_id": ficha["template_id"],
                        "exercise_id": MESA,
                        "planned_sets": [{"reps_min": 10, "reps_max": 12}] * 3,
                    },
                    "rationale": "Posterior de coxa sem nenhuma série em 30 dias.",
                },
            )
        )

    provider = FakeProvider(
        [
            tool_use(("get_templates", {})),
            propose_from_templates,
            Completion(text="Sugeri a mesa flexora; confirme abaixo.", model="fake-v1"),
        ]
    )
    app.dependency_overrides[get_provider_factory] = lambda: lambda: provider
    before = template_now(client, ana)
    reply = ok(
        client.post(
            f"{API}/ai/conversations/{ana['chat']}/messages",
            headers=ana["headers"],
            json={"content": "Adicione um exercício de posterior na ficha A"},
        )
    )
    [card] = reply["answer"]["proposals"]
    assert card["status"] == "pending"
    assert card["summary"] == "Acrescentar Mesa flexora à ficha “Treino A”"
    assert reply["answer"]["tools_used"] == ["get_templates", "prepare_change_proposal"]
    assert template_now(client, ana) == before
    # O prompt (desde o v2) explica as propostas.
    assert "prepare_change_proposal" in provider.requests[0].system
    assert prompts.load().version == "coach.v3"

    detail = ok(client.get(f"{API}/ai/conversations/{ana['chat']}", headers=ana["headers"]))
    assert [len(m["proposals"]) for m in detail["messages"]] == [0, 1]

    ok(decide(client, ana, card["id"], "accept"))
    assert "Mesa flexora" in [i["exercise"]["name"] for i in template_now(client, ana)["items"]]
    detail = ok(client.get(f"{API}/ai/conversations/{ana['chat']}", headers=ana["headers"]))
    assert detail["messages"][1]["proposals"][0]["status"] == "accepted"


def test_a_failed_answer_drops_its_proposals(
    app: FastAPI, client: TestClient, db: Session, ana: dict
) -> None:
    def propose_then(request: FakeRequest) -> Completion:
        return tool_use(
            ("prepare_change_proposal", {"change": add_mesa(ana), "rationale": "Pelos dados."})
        )

    provider = FakeProvider([propose_then, InvalidModelOutput()])
    app.dependency_overrides[get_provider_factory] = lambda: lambda: provider
    response = client.post(
        f"{API}/ai/conversations/{ana['chat']}/messages",
        headers=ana["headers"],
        json={"content": "Mude minha ficha"},
    )
    assert response.status_code == 503
    assert db.scalars(select(ChangeProposal)).all() == []
    assert ok(client.get(f"{API}/ai/proposals", headers=ana["headers"])) == []


def test_describe_sets() -> None:
    from app.modules.training.schemas import PlannedSet

    assert proposals.describe_sets([PlannedSet(reps_min=10)]) == "1 série de 10 reps"
    assert (
        proposals.describe_sets(
            [
                PlannedSet(kind="warmup", reps_min=15, load_kg=20),
                PlannedSet(reps_min=8, reps_max=10),
            ]
        )
        == "aquecimento 15 reps com 20 kg, 8 a 10 reps"
    )
    assert proposals.describe_sets([PlannedSet(duration_s=45)] * 2) == "2 séries de 45 s"
