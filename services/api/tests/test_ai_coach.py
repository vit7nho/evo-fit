"""Orquestrador e conversas da IA (4.3): laço de ferramentas com o `FakeProvider`
roteirizado, limites (consultas, iterações, por minuto e por dia), consentimento,
falhas do provedor, prompt versionado e o registro de execução sem conteúdo."""

# ruff: noqa: F811  (a fixture two_people vem de test_ai_tools)
import json
import zoneinfo
from datetime import date, datetime, time, timedelta

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import inspect, select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.integrations.ai.errors import (
    InvalidModelOutput,
    ProviderNotConfigured,
    ProviderRateLimited,
    ProviderTimeout,
)
from app.integrations.ai.provider import Completion, ToolCall, Usage
from app.integrations.ai.providers.demo import DemoProvider
from app.integrations.ai.providers.fake import DEMO_REPLY, FakeProvider, FakeRequest
from app.modules.ai_coach import guardrails, orchestrator, prompts
from app.modules.ai_coach import service as ai_service
from app.modules.ai_coach.models import AiMessage, AiRunLog
from app.modules.ai_coach.router import get_provider_factory
from app.modules.ai_coach.tools import base
from tests.conftest import Clock
from tests.test_ai_tools import two_people  # noqa: F401  (fixture)
from tests.test_analytics import ok

API = "/api/v1/ai"
LAST_SESSION = "O que fiz na minha última sessão?"
SAO_PAULO = zoneinfo.ZoneInfo("America/Sao_Paulo")


@pytest.fixture(autouse=True)
def fixed_clock(monkeypatch: pytest.MonkeyPatch, clock: Clock) -> None:
    monkeypatch.setattr(base, "today", lambda user: date(2026, 11, 1))
    monkeypatch.setattr(ai_service, "_now", lambda: clock.now)
    monkeypatch.setattr(orchestrator.time, "sleep", lambda seconds: None)


@pytest.fixture
def use(app: FastAPI, client: TestClient):
    """Troca o provedor da API por um `FakeProvider` (roteirizado ou não)."""

    def _use(*script) -> FakeProvider:
        provider = FakeProvider(list(script) if script else None)
        app.dependency_overrides[get_provider_factory] = lambda: lambda: provider
        return provider

    return _use


@pytest.fixture
def limits(app: FastAPI):
    def _limits(**values: int) -> None:
        settings = get_settings().model_copy(update=values)
        app.dependency_overrides[get_settings] = lambda: settings

    return _limits


def consent(client: TestClient, headers: dict) -> None:
    ok(client.put("/api/v1/me/consents/ai_processing", headers=headers))


def conversation(client: TestClient, headers: dict, **body) -> str:
    return ok(client.post(f"{API}/conversations", headers=headers, json=body), 201)["id"]


def ask(client: TestClient, headers: dict, conversation_id: str, text: str = LAST_SESSION):
    return client.post(
        f"{API}/conversations/{conversation_id}/messages", headers=headers, json={"content": text}
    )


def runs(db: Session) -> list[AiRunLog]:
    return list(db.scalars(select(AiRunLog).order_by(AiRunLog.created_at, AiRunLog.id)))


def tool_use(*calls: tuple[str, dict]) -> Completion:
    return Completion(
        tool_calls=tuple(ToolCall(f"t{i}", name, args) for i, (name, args) in enumerate(calls)),
        stop_reason="tool_use",
        usage=Usage(100, 20),
        model="fake-v1",
    )


def text(answer: str) -> Completion:
    return Completion(text=answer, usage=Usage(150, 40), model="fake-v1")


def last_results(request: FakeRequest) -> list[dict]:
    message = request.messages[-1]
    assert message.role == "tool"
    return [json.loads(r.content) for r in message.tool_results]


@pytest.fixture
def ana(client: TestClient, two_people) -> dict:
    consent(client, two_people["ana"])
    return two_people["ana"]


@pytest.fixture
def bia(client: TestClient, two_people) -> dict:
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "bia@exemplo.com", "password": "cavalo bateria grampo"},
    )
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    consent(client, headers)
    return headers


# --- o caminho principal ---


def test_last_session_is_answered_with_the_tool_data(
    client: TestClient, db: Session, ana: dict, use
) -> None:
    def answer(request: FakeRequest) -> Completion:
        session = last_results(request)[0]["items"][0]
        volume = f"{session['volume_kg']:,.0f}".replace(",", ".")
        minutes = session["duration_s"] // 60
        return text(
            f"Na sua última sessão ({session['name']}), registrada em 01/11, você fez "
            f"{session['sets']} séries de {', '.join(session['exercises'])}, em {minutes} min, "
            f"com volume calculado de {volume} kg."
        )

    provider = use(tool_use(("get_workout_history", {"limit": 1})), answer)
    chat = conversation(client, ana)
    reply = ok(ask(client, ana, chat))

    assert "1.200 kg" in reply["answer"]["content"]
    assert "40 min" in reply["answer"]["content"]
    assert reply["answer"]["tools_used"] == ["get_workout_history"]
    assert reply["question"]["content"] == LAST_SESSION
    assert reply["simulated"] is True
    assert reply["remaining_today"] == 29

    # O que foi ao modelo: o prompt versionado, o cartão de contexto e nada pessoal.
    first = provider.requests[0]
    assert first.system.startswith(prompts.load().text)
    assert "Hoje: 2026-11-01 (domingo), fuso America/Sao_Paulo." in first.system
    assert {t.name for t in first.tools} >= {"get_workout_history", "get_muscle_stimulus"}
    sent = first.system + json.dumps([m.content for m in first.messages])
    assert "ana@exemplo.com" not in sent and "Ana" not in sent
    assert provider.remaining == 0

    # Registro da execução: metadados, nunca conteúdo.
    [run] = runs(db)
    assert (run.outcome, run.provider, run.model) == ("ok", "fake", "fake-v1")
    assert (run.prompt_version, run.prompt_hash) == ("coach.v3", prompts.load().hash)
    assert (run.input_tokens, run.output_tokens, run.iterations) == (250, 60, 2)
    assert [(t["name"], t["ok"]) for t in run.tool_calls] == [("get_workout_history", True)]
    assert run.unverified_numbers == 0
    columns = {c.key for c in inspect(AiRunLog).columns}
    assert not columns & {"content", "text", "question", "answer", "arguments"}

    # A conversa guarda a pergunta e a resposta, e ganha o título da pergunta.
    detail = ok(client.get(f"{API}/conversations/{chat}", headers=ana))
    assert [m["role"] for m in detail["messages"]] == ["user", "assistant"]
    assert detail["title"] == LAST_SESSION


def test_without_records_the_model_sees_empty_data(
    client: TestClient, db: Session, bia: dict, use
) -> None:
    seen = {}

    def answer(request: FakeRequest) -> Completion:
        seen.update(last_results(request)[0])
        return text("Ainda não há registros de treino. Registre um treino para eu analisar.")

    use(tool_use(("get_workout_history", {})), answer)
    reply = ok(ask(client, bia, conversation(client, bia)))

    assert (seen["total_sessions"], seen["items"]) == (0, [])
    assert reply["answer"]["content"].startswith("Ainda não há registros")
    assert runs(db)[0].unverified_numbers == 0


def test_invented_numbers_are_flagged_in_the_log(
    client: TestClient, db: Session, bia: dict, use
) -> None:
    use(text("Você levantou 5.000 kg este mês, 37% a mais."))
    reply = ok(ask(client, bia, conversation(client, bia)))
    # A v1 não bloqueia: registra o alerta para a avaliação (AI_DESIGN §6).
    assert reply["answer"]["content"].startswith("Você levantou")
    assert runs(db)[0].unverified_numbers == 2


def test_invalid_arguments_go_back_to_the_model(
    client: TestClient, db: Session, ana: dict, use
) -> None:
    errors = []

    def retry(request: FakeRequest) -> Completion:
        errors.append(last_results(request)[0]["error"])
        return tool_use(("get_workout_history", {"limit": 5}))

    use(
        tool_use(("get_workout_history", {"user_id": "da-bia", "limit": 5})),
        retry,
        text("Pronto."),
    )
    ok(ask(client, ana, conversation(client, ana)))
    assert "user_id: campo não aceito" in errors[0]
    assert [(t["name"], t["ok"]) for t in runs(db)[0].tool_calls] == [
        ("get_workout_history", False),
        ("get_workout_history", True),
    ]


# --- limites do laço ---


def test_at_most_six_tool_calls_per_answer(client: TestClient, db: Session, ana: dict, use) -> None:
    seven = tool_use(*[("get_goals", {})] * 7)
    provider = use(seven, lambda r: text("Resumo com o que consultei."))
    ok(ask(client, ana, conversation(client, ana)))

    results = [json.loads(r.content) for r in provider.requests[1].messages[-1].tool_results]
    assert sum("error" not in r for r in results) == 6
    assert results[-1]["error"] == orchestrator.LIMIT_REACHED
    # Atingido o limite, a próxima chamada já não oferece ferramentas.
    assert provider.requests[1].tools == []
    assert len(runs(db)[0].tool_calls) == 7


def test_the_last_iteration_forces_a_text_answer(
    client: TestClient, db: Session, ana: dict, use
) -> None:
    insistent = [tool_use(("get_goals", {}))] * orchestrator.MAX_ITERATIONS
    provider = use(*insistent)
    response = ask(client, ana, conversation(client, ana))

    assert response.status_code == 503
    assert response.json()["code"] == "ai_invalid_output"
    assert len(provider.requests) == orchestrator.MAX_ITERATIONS
    assert provider.requests[-1].tools == []
    [run] = runs(db)
    assert (run.outcome, run.iterations) == ("invalid_output", orchestrator.MAX_ITERATIONS)
    assert db.scalars(select(AiMessage)).all() == []


def test_the_last_iteration_accepts_text_alongside_tool_calls(
    client: TestClient, ana: dict, use
) -> None:
    calls = [tool_use(("get_goals", {}))] * (orchestrator.MAX_ITERATIONS - 1)
    final = Completion(
        text="Com o que vi até aqui: siga as metas.",
        tool_calls=(ToolCall("x", "get_goals", {}),),
        stop_reason="tool_use",
    )
    use(*calls, final)
    assert ok(ask(client, ana, conversation(client, ana)))["answer"]["content"].startswith("Com")


def test_long_answers_are_cut(client: TestClient, bia: dict, use) -> None:
    use(text("a" * (guardrails.MAX_ANSWER_CHARS + 500)))
    content = ok(ask(client, bia, conversation(client, bia)))["answer"]["content"]
    assert len(content) == guardrails.MAX_ANSWER_CHARS
    assert content.endswith("…")


# --- falhas do provedor ---


@pytest.mark.parametrize(
    ("failure", "status", "outcome", "code"),
    [
        ([ProviderTimeout()] * 3, 503, "provider_error", "ai_timeout"),
        ([ProviderRateLimited(retry_after_s=60)], 429, "rate_limited", "ai_rate_limited"),
        ([InvalidModelOutput()], 503, "invalid_output", "ai_invalid_output"),
        ([text("   ")], 503, "invalid_output", "ai_invalid_output"),
    ],
)
def test_provider_failures_become_friendly_messages(
    client: TestClient, db: Session, ana: dict, use, failure, status, outcome, code
) -> None:
    provider = use(*failure)
    chat = conversation(client, ana)
    response = ask(client, ana, chat)

    assert response.status_code == status, response.text
    body = response.json()
    assert body["code"] == code
    expected = failure[0] if isinstance(failure[0], Exception) else InvalidModelOutput()
    assert body["detail"] == expected.user_message
    assert provider.remaining == 0  # o timeout foi tentado 3 vezes (2 novas tentativas)
    [run] = runs(db)
    assert (run.outcome, run.error_code) == (outcome, code)
    # A pergunta não fica gravada: dá para repetir sem duplicar a conversa.
    assert ok(client.get(f"{API}/conversations/{chat}", headers=ana))["messages"] == []


def test_a_provider_that_is_not_configured(
    app: FastAPI, client: TestClient, db: Session, ana: dict
) -> None:
    def broken():
        raise ProviderNotConfigured("sem chave")

    app.dependency_overrides[get_provider_factory] = lambda: broken
    response = ask(client, ana, conversation(client, ana))
    assert response.status_code == 503
    assert response.json()["detail"] == ProviderNotConfigured.user_message
    assert runs(db)[0].outcome == "provider_error"


def test_demo_mode_without_a_script(client: TestClient, bia: dict, use) -> None:
    use()
    reply = ok(ask(client, bia, conversation(client, bia)))
    assert reply["answer"]["content"] == DEMO_REPLY
    assert reply["simulated"] is True
    assert reply["demo"] is False


def test_rule_based_demo_is_flagged_and_logged(
    app: FastAPI, client: TestClient, db: Session, bia: dict
) -> None:
    app.dependency_overrides[get_provider_factory] = lambda: DemoProvider
    reply = ok(ask(client, bia, conversation(client, bia)))
    assert (reply["demo"], reply["simulated"]) == (True, False)
    assert "Ainda não há registros" in reply["answer"]["content"]
    assert (runs(db)[0].provider, runs(db)[0].model) == ("demo", "demo-v1")


# --- entrada: consentimento, tamanho e limites ---


def test_ai_processing_consent_is_required(
    client: TestClient,
    db: Session,
    two_people,
    use,
) -> None:
    ana = two_people["ana"]
    provider = use(text("não deveria"))
    chat = conversation(client, ana)
    response = ask(client, ana, chat)
    assert response.status_code == 403
    assert response.json()["code"] == "consent_required"
    assert provider.requests == []

    # Revogar bloqueia de novo.
    consent(client, ana)
    ok(ask(client, ana, chat))
    assert client.delete("/api/v1/me/consents/ai_processing", headers=ana).status_code == 204
    assert ask(client, ana, chat).status_code == 403


@pytest.mark.parametrize("content", ["", "   ", "x" * 2001])
def test_question_size(client: TestClient, bia: dict, use, content: str) -> None:
    use()
    response = ask(client, bia, conversation(client, bia), content)
    assert response.status_code == 422


def test_per_minute_and_daily_limits(
    client: TestClient, db: Session, bia: dict, use, limits, clock: Clock
) -> None:
    use()
    limits(ai_per_minute_limit=2, ai_daily_limit=3)
    chat = conversation(client, bia)

    assert ok(ask(client, bia, chat))["remaining_today"] == 2
    assert ok(ask(client, bia, chat))["remaining_today"] == 1
    blocked = ask(client, bia, chat)
    assert blocked.status_code == 429
    assert blocked.json()["code"] == "ai_per_minute_limit"
    assert blocked.headers["Retry-After"] == "60"

    clock.advance(seconds=61)
    assert ok(ask(client, bia, chat))["remaining_today"] == 0
    clock.advance(minutes=5)
    daily = ask(client, bia, chat)
    assert daily.status_code == 429
    assert daily.json()["code"] == "ai_daily_limit"
    # Até a meia-noite no fuso dela (São Paulo), não em UTC.
    local = clock.now.astimezone(SAO_PAULO)
    midnight = datetime.combine(local.date() + timedelta(days=1), time.min, SAO_PAULO)
    assert int(daily.headers["Retry-After"]) == int((midnight - local).total_seconds())

    # As recusas ficam registradas, mas não contam para o limite.
    assert [r.outcome for r in runs(db)].count("refused") == 2
    clock.advance(hours=17)  # já é o dia seguinte no fuso dela
    ok(ask(client, bia, chat))


# --- histórico e conversa ---


def test_history_goes_to_the_model_trimmed(
    client: TestClient, bia: dict, use, limits, clock: Clock
) -> None:
    limits(ai_per_minute_limit=60)
    script = [text(f"Resposta {i}") for i in range(7)]
    provider = use(*script)
    chat = conversation(client, bia)
    for i in range(7):
        ok(ask(client, bia, chat, f"Pergunta {i}"))
        clock.advance(seconds=1)

    first, last = provider.requests[0], provider.requests[-1]
    assert [m.content for m in first.messages] == ["Pergunta 0"]
    # 10 mensagens anteriores (5 pares), começando numa pergunta, e a nova no fim.
    assert [m.content for m in last.messages] == [
        *[x for i in range(1, 6) for x in (f"Pergunta {i}", f"Resposta {i}")],
        "Pergunta 6",
    ]


def test_specific_mode_puts_the_focus_in_the_context(
    client: TestClient,
    ana: dict,
    use,
    two_people,
) -> None:
    provider = use(text("ok"))
    chat = conversation(
        client,
        ana,
        scope="muscle",
        scope_ref={"muscle_id": "chest", "from_date": "2026-10-01", "to_date": "2026-11-01"},
    )
    ok(ask(client, ana, chat))
    assert "Foco: o músculo Peito (muscle_id chest); comece por get_muscle_stimulus, " in (
        provider.requests[0].system
    )

    session = conversation(
        client, ana, scope="session", scope_ref={"session_id": two_people["session_id"]}
    )
    detail = ok(client.get(f"{API}/conversations/{session}", headers=ana))
    assert detail["title"] == "Sobre um treino"


@pytest.mark.parametrize(
    "body",
    [
        {"scope": "global", "scope_ref": {"muscle_id": "chest"}},
        {"scope": "muscle"},
        {"scope": "muscle", "scope_ref": {"muscle_id": "asas"}},
        {"scope": "period", "scope_ref": {"from_date": "2026-11-01", "to_date": "2026-10-01"}},
        {"scope": "period", "scope_ref": {"from_date": "2025-01-01", "to_date": "2026-11-01"}},
        {"scope": "session", "scope_ref": {"session_id": "nao-e-uuid"}},
        {"scope": "session", "scope_ref": {"session_id": None, "user_id": "x"}},
        {"scope": "planeta"},
    ],
)
def test_invalid_scopes_are_refused(client: TestClient, bia: dict, body: dict) -> None:
    response = client.post(f"{API}/conversations", headers=bia, json=body)
    assert response.status_code == 422, response.text


def test_another_users_records_cannot_be_the_focus(
    client: TestClient,
    bia: dict,
    two_people,
) -> None:
    response = client.post(
        f"{API}/conversations",
        headers=bia,
        json={"scope": "session", "scope_ref": {"session_id": two_people["session_id"]}},
    )
    assert response.status_code == 422
    assert response.json()["errors"] == [
        {"field": "scope_ref", "message": "Registro não encontrado."}
    ]


def test_conversations_are_private_and_deletable(
    client: TestClient, db: Session, ana: dict, bia: dict, use
) -> None:
    use(text("Olá!"))
    chat = conversation(client, ana)
    ok(ask(client, ana, chat))

    assert ok(client.get(f"{API}/conversations", headers=bia)) == []
    for method, path, body in [
        ("GET", f"/conversations/{chat}", None),
        ("POST", f"/conversations/{chat}/messages", {"content": "oi"}),
        ("DELETE", f"/conversations/{chat}", None),
    ]:
        response = client.request(method, f"{API}{path}", headers=bia, json=body)
        assert response.status_code == 404, (method, path)

    assert [c["id"] for c in ok(client.get(f"{API}/conversations", headers=ana))] == [chat]
    assert client.delete(f"{API}/conversations/{chat}", headers=ana).status_code == 204
    assert ok(client.get(f"{API}/conversations", headers=ana)) == []
    assert db.scalars(select(AiMessage)).all() == []
    # O registro da execução fica (sem conteúdo), desligado da conversa apagada.
    [run] = runs(db)
    db.refresh(run)
    assert run.conversation_id is None


# --- prompt e conferência de números ---


def test_prompt_is_versioned() -> None:
    prompt = prompts.load()
    assert prompt.version == "coach.v3"
    assert prompts.load("coach.v2").hash != prompt.hash  # as versões antigas ficam no repositório
    assert prompts.load("coach.v1").hash != prompt.hash
    assert len(prompt.hash) == 16
    for rule in ("somente", "ainda não há registros", "estimativa", "profissional de saúde"):
        assert rule in prompt.text


@pytest.mark.parametrize(
    ("answer", "sources", "missing"),
    [
        ("Você correu 5 km.", ['{"distance_m":5000}'], []),
        ("Pace de 6:24/km.", ['{"pace_s_per_km":384}'], []),
        ("Treinou por 1:05:00.", ['{"duration_s":3900}'], []),
        ("Volume de 1.200 kg.", ['{"volume_kg":1200.0}'], []),
        ("Média de 5,4 km por semana.", ['{"km":5.43}'], []),
        ("Em 01/11/2026 foram 3 séries.", ["{}"], []),
        ("Você levantou 37 kg.", ['{"load_kg":40}'], ["37"]),
        ("Pace de 5:10/km.", ['{"pace_s_per_km":384}'], ["5:10"]),
        # Variação com sinal nos dados, sem sinal no texto (5.4).
        ("Você perdeu 1,5 kg.", ['{"change":-1.5}'], []),
    ],
)
def test_unverified_numbers(answer: str, sources: list[str], missing: list[str]) -> None:
    assert guardrails.unverified_numbers(answer, sources) == missing
