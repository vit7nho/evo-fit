"""Avaliação do assistente (4.7, ADR-054).

- Os testes do roteiro rodam sempre, com um provedor roteirizado: provam que as
  checagens pegam o que devem (ferramenta não consultada, número inventado, conta
  vazia sem “ainda não há registros”, proposta não criada).
- A avaliação de verdade roda só quando pedida, com o provedor configurado no
  ambiente (AI_PROVIDER, AI_API_KEY, AI_MODEL):

      EVOFIT_EVAL=1 EVOFIT_EVAL_REPORT=../../docs/avaliacao_ia_resultado.md \\
          .venv/Scripts/python.exe -m pytest tests/test_coach_eval.py -s

  Ela usa o banco de testes (como os outros testes) e nunca o de desenvolvimento.
"""

# ruff: noqa: F811  (a fixture two_people vem de test_ai_tools)
import os
from datetime import date
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.integrations.ai.factory import build_provider
from app.integrations.ai.provider import Completion, ToolCall, Usage
from app.integrations.ai.providers.fake import FakeProvider
from app.modules.ai_coach import orchestrator
from app.modules.ai_coach import service as ai_service
from app.modules.ai_coach.router import get_provider_factory
from app.modules.ai_coach.tools import base
from tests import coach_eval
from tests.conftest import Clock
from tests.test_ai_tools import (
    two_people,  # noqa: F401  (fixture)
    user_of,
)
from tests.test_analytics import ok

API = "/api/v1"


@pytest.fixture(autouse=True)
def fixed_clock(monkeypatch: pytest.MonkeyPatch, clock: Clock) -> None:
    monkeypatch.setattr(base, "today", lambda user: date(2026, 11, 1))
    monkeypatch.setattr(ai_service, "_now", lambda: clock.now)
    monkeypatch.setattr(orchestrator.time, "sleep", lambda seconds: None)


@pytest.fixture
def accounts(app: FastAPI, client: TestClient, db: Session, two_people) -> dict:
    """Ana (com dados) e Bia (vazia), as duas com o consentimento de IA e limites
    folgados (a avaliação faz ~20 perguntas seguidas)."""
    bia = client.post(
        f"{API}/auth/login",
        json={"email": "bia@exemplo.com", "password": "cavalo bateria grampo"},
    ).json()
    headers = {
        "ana": two_people["ana"],
        "bia": {"Authorization": f"Bearer {bia['access_token']}"},
    }
    for h in headers.values():
        ok(client.put(f"{API}/me/consents/ai_processing", headers=h))
    settings = get_settings().model_copy(update={"ai_per_minute_limit": 60, "ai_daily_limit": 1000})
    app.dependency_overrides[get_settings] = lambda: settings
    users = {name: user_of(db, f"{name}@exemplo.com").id for name in headers}
    return {"headers": headers, "users": users}


def run(client: TestClient, db: Session, accounts: dict, question: coach_eval.Question):
    account = question.account
    return coach_eval.ask(
        client, db, accounts["headers"][account], accounts["users"][account], question
    )


def use(app: FastAPI, provider) -> None:
    app.dependency_overrides[get_provider_factory] = lambda: lambda: provider


def by_id(question_id: str) -> coach_eval.Question:
    return next(q for q in coach_eval.QUESTIONS if q.id == question_id)


def tool_use(name: str, **arguments) -> Completion:
    return Completion(
        tool_calls=(ToolCall("t1", name, arguments),),
        stop_reason="tool_use",
        usage=Usage(100, 10),
        model="roteiro",
    )


def text(answer: str) -> Completion:
    return Completion(text=answer, usage=Usage(200, 40), model="roteiro")


# --- o conjunto de perguntas ---


def test_the_question_set() -> None:
    questions = coach_eval.QUESTIONS
    assert 20 <= len(questions) <= 25
    assert len({q.id for q in questions}) == len(questions)
    assert {q.account for q in questions} == {"ana", "bia"}
    assert sum(q.account == "bia" for q in questions) >= 3
    assert {q.proposal_kind for q in questions} >= {"template_add_exercise", "goal_create"}
    for q in questions:
        assert q.review, q.id
        assert q.tools_any <= coach_eval.DATA_TOOLS, q.id


# --- as checagens pegam o que devem ---


def test_a_good_answer_passes(app: FastAPI, client: TestClient, db: Session, accounts) -> None:
    use(
        app,
        FakeProvider(
            [
                tool_use("get_workout_history", limit=1),
                text(
                    "Na sua última sessão (01/11) você fez supino reto com barra: "
                    "volume calculado de 1.200 kg."
                ),
            ]
        ),
    )
    result = run(client, db, accounts, by_id("ultima-sessao"))
    assert result.failures == []
    assert result.tools == ["get_workout_history"]
    assert result.unverified == 0
    assert (result.input_tokens, result.output_tokens) == (300, 50)


def test_invented_numbers_and_missing_tools_fail(
    app: FastAPI, client: TestClient, db: Session, accounts
) -> None:
    use(app, FakeProvider([text("Você fez 4 séries de 80 kg e 3.500 kg de volume.")]))
    result = run(client, db, accounts, by_id("vazia-ultima-sessao"))
    assert result.failures == [
        "não consultou get_session_detail ou get_workout_history",
        "faltou dizer algo como “ainda não há”",
        "2 número(s) que não estão nos dados consultados",
    ]


def test_proposal_questions_require_a_pending_proposal(
    app: FastAPI, client: TestClient, db: Session, accounts
) -> None:
    use(app, FakeProvider([text("Adicionei a mesa flexora na sua ficha.")]))
    result = run(client, db, accounts, by_id("proposta-ficha"))
    assert "não criou a proposta template_add_exercise" in result.failures
    assert "disse “adicionei”" in result.failures
    assert coach_eval.proposals_applied(db) == 0


def test_provider_failure_is_reported(app: FastAPI, client: TestClient, db, accounts) -> None:
    use(app, FakeProvider([text("   ")]))
    result = run(client, db, accounts, by_id("fora-do-escopo"))
    assert result.failures == ["a pergunta falhou (HTTP 503)"]


def test_report_has_the_review_columns(
    app: FastAPI, client: TestClient, db: Session, accounts
) -> None:
    use(app, FakeProvider([text("Só posso ajudar com treino, atividade física e hábitos.")]))
    result = run(client, db, accounts, by_id("fora-do-escopo"))
    markdown = coach_eval.report([result], provider="fake", model="roteiro", applied=0)
    assert "**1 de 1** perguntas sem falha" in markdown
    assert "| Números corretos? | Tom e segurança? |" in markdown
    assert "| 1 | Qual é a capital da França? | ana | ok | — | 0 | ☐ | ☐ |" in markdown
    assert "> Só posso ajudar com treino, atividade física e hábitos." in markdown
    assert "*Esperado:* Diz em uma frase" in markdown


def test_normalize_ignores_case_and_accents() -> None:
    assert coach_eval.normalize("Ainda NÃO há registros") == "ainda nao ha registros"


# --- a avaliação de verdade (só quando pedida) ---


@pytest.mark.skipif(os.environ.get("EVOFIT_EVAL") != "1", reason="defina EVOFIT_EVAL=1")
def test_run_the_evaluation(app: FastAPI, client: TestClient, db: Session, accounts) -> None:
    settings = get_settings()
    provider = build_provider(settings)
    use(app, provider)
    results = [run(client, db, accounts, q) for q in coach_eval.QUESTIONS]
    markdown = coach_eval.report(
        results,
        provider=settings.ai_provider,
        model=settings.ai_model or "",
        applied=coach_eval.proposals_applied(db),
    )
    if path := os.environ.get("EVOFIT_EVAL_REPORT"):
        Path(path).write_text(markdown, encoding="utf-8")
    print(coach_eval.summary(results))
    # A avaliação registra; quem decide se está bom é a revisão do relatório. O que
    # nunca pode acontecer é aplicar uma alteração sem confirmação.
    assert coach_eval.proposals_applied(db) == 0
