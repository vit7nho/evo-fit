"""Adaptador do Gemini (4.4): tradução dos tipos, assinatura de raciocínio, consumo e
erros. O transporte é roteirizado — nenhum teste acessa a rede. As respostas
imitam as que a API devolveu nas sondagens de 25/11/2026 (dados sintéticos)."""

import json
import logging
import urllib.error

import pytest
from pydantic import SecretStr

from app.integrations.ai import errors
from app.integrations.ai.factory import build_provider
from app.integrations.ai.provider import Message, ToolCall, ToolResult, ToolSpec
from app.integrations.ai.providers import gemini
from app.integrations.ai.providers.gemini import (
    DEFAULT_MODEL,
    DEFAULT_MODELS,
    GeminiProvider,
    to_contents,
)
from app.integrations.ai.retry import complete_with_retry
from tests.test_ai_provider import settings

KEY = "AQ.chave-de-teste-123"
# Um modelo só: sem troca de modelo nos testes de erro.
ONE = "gemini-3.6-flash"


@pytest.fixture(autouse=True)
def fresh_quota():
    """A memória das cotas esgotadas é do processo: cada teste começa limpo."""
    gemini._EXHAUSTED.clear()
    yield
    gemini._EXHAUSTED.clear()


TOOL = ToolSpec(
    name="get_goals",
    description="Metas da pessoa e o progresso.",
    input_schema={
        "type": "object",
        "properties": {"period": {"$ref": "#/$defs/Period"}},
        "$defs": {"Period": {"type": "string"}},
        "additionalProperties": False,
    },
)


class Transport:
    """Devolve as respostas do roteiro e guarda cada pedido."""

    def __init__(self, *steps) -> None:
        self.steps = list(steps)
        self.calls: list[dict] = []

    def __call__(self, url, headers, body, timeout_s):
        self.calls.append(
            {"url": url, "headers": headers, "body": json.loads(body), "timeout": timeout_s}
        )
        step = self.steps.pop(0)
        if isinstance(step, Exception):
            raise step
        status, payload = step
        return status, json.dumps(payload).encode()


def ok(*parts, finish="STOP", usage=None, model="gemini-3.6-flash") -> tuple[int, dict]:
    return 200, {
        "candidates": [
            {"content": {"role": "model", "parts": list(parts)}, "finishReason": finish}
        ],
        "usageMetadata": usage
        or {"promptTokenCount": 61, "candidatesTokenCount": 17, "thoughtsTokenCount": 53},
        "modelVersion": model,
    }


def fail(status: int, google: str, **extra) -> tuple[int, dict]:
    return status, {"error": {"code": status, "status": google, "message": "x", **extra}}


def ask(provider: GeminiProvider, *messages: Message, tools=(TOOL,)):
    return provider.complete(
        system="Você é um assistente de treino.",
        messages=list(messages) or [Message.user("Como estou indo?")],
        tools=list(tools),
        max_tokens=1024,
        timeout_s=30,
    )


# --- pedido ---


def test_request_carries_the_key_in_the_header_and_the_tools_as_json_schema() -> None:
    transport = Transport(ok({"text": "Oi"}))
    ask(GeminiProvider(KEY, transport=transport))
    call = transport.calls[0]
    assert call["url"].endswith(f"/models/{DEFAULT_MODEL}:generateContent")
    assert call["url"].startswith("https://")
    assert KEY not in call["url"]
    assert call["headers"]["x-goog-api-key"] == KEY
    assert call["timeout"] == 30
    body = call["body"]
    assert body["systemInstruction"] == {"parts": [{"text": "Você é um assistente de treino."}]}
    assert body["contents"] == [{"role": "user", "parts": [{"text": "Como estou indo?"}]}]
    (declaration,) = body["tools"][0]["functionDeclarations"]
    assert declaration["parametersJsonSchema"] == TOOL.input_schema  # com $defs, intacto
    assert body["generationConfig"] == {
        "maxOutputTokens": 1024,
        "thinkingConfig": {"thinkingLevel": "low"},
    }


def test_no_tools_key_when_none_offered_and_no_thinking_level_on_older_models() -> None:
    transport = Transport(ok({"text": "Oi"}))
    ask(GeminiProvider(KEY, "gemini-2.5-flash", transport=transport), tools=())
    body = transport.calls[0]["body"]
    assert "tools" not in body
    assert body["generationConfig"] == {"maxOutputTokens": 1024}


def test_tool_turns_are_translated_with_the_signature_sent_back() -> None:
    call = ToolCall("call_1", "get_goals", {"period": "mes"}, signature="assinatura==")
    plain = ToolCall("call_2", "get_goals", {})
    contents = to_contents(
        [
            Message.user("Como estão as metas?"),
            Message("assistant", content="Vou consultar.", tool_calls=(call, plain)),
            Message.results(
                ToolResult("call_1", json.dumps({"items": [], "total": 0})),
                ToolResult("call_2", json.dumps(["a", "b"])),
            ),
            Message("assistant", tool_calls=(ToolCall("call_3", "get_goals", {}),)),
            Message.results(ToolResult("call_3", json.dumps({"error": "x"}), is_error=True)),
        ]
    )
    assert contents[1] == {
        "role": "model",
        "parts": [
            {"text": "Vou consultar."},
            {
                "functionCall": {"id": "call_1", "name": "get_goals", "args": {"period": "mes"}},
                "thoughtSignature": "assinatura==",
            },
            {"functionCall": {"id": "call_2", "name": "get_goals", "args": {}}},
        ],
    }
    assert contents[2] == {
        "role": "user",
        "parts": [
            {
                "functionResponse": {
                    "id": "call_1",
                    "name": "get_goals",
                    "response": {"items": [], "total": 0},
                }
            },
            # A resposta precisa ser um objeto: listas vão embrulhadas.
            {
                "functionResponse": {
                    "id": "call_2",
                    "name": "get_goals",
                    "response": {"result": ["a", "b"]},
                }
            },
        ],
    }
    assert contents[4]["parts"][0]["functionResponse"]["response"] == {"error": {"error": "x"}}


# --- resposta ---


def test_text_answer_usage_and_model() -> None:
    completion = ask(
        GeminiProvider(
            KEY, transport=Transport(ok({"text": "Você "}, {"text": "treinou 3 vezes."}))
        )
    )
    assert completion.text == "Você treinou 3 vezes."
    assert completion.tool_calls == ()
    assert completion.stop_reason == "end"
    # Saída = resposta + raciocínio (os dois são cobrados como saída).
    assert (completion.usage.input_tokens, completion.usage.output_tokens) == (61, 70)
    assert completion.model == "gemini-3.6-flash"


def test_tool_calls_keep_id_and_signature_and_skip_thought_summaries() -> None:
    transport = Transport(
        ok(
            {"text": "pensando...", "thought": True},
            {
                "functionCall": {"name": "get_goals", "args": {}, "id": "call_15311"},
                "thoughtSignature": "EvICCu8C",
            },
            {"functionCall": {"name": "get_goals", "args": {"period": "mes"}}},
        )
    )
    completion = ask(GeminiProvider(KEY, transport=transport))
    assert completion.stop_reason == "tool_use"
    assert completion.text == ""
    first, second = completion.tool_calls
    assert (first.id, first.name, first.signature) == ("call_15311", "get_goals", "EvICCu8C")
    assert second.id and second.id != first.id and second.signature is None
    assert "EvICCu8C" not in repr(first)  # a assinatura não vai a logs

    # Na rodada seguinte a assinatura volta exatamente como veio.
    messages = [Message.user("Metas?"), completion.as_message()]
    messages.append(Message.results(ToolResult(first.id, "{}"), ToolResult(second.id, "{}")))
    transport.steps.append(ok({"text": "Sem metas."}))
    ask(GeminiProvider(KEY, transport=transport), *messages)
    sent = transport.calls[1]["body"]["contents"][1]["parts"][0]
    assert sent["thoughtSignature"] == "EvICCu8C"


def test_cut_answer_is_reported_as_max_tokens() -> None:
    completion = ask(
        GeminiProvider(KEY, transport=Transport(ok({"text": "Você"}, finish="MAX_TOKENS")))
    )
    assert completion.stop_reason == "max_tokens"


@pytest.mark.parametrize(
    "response",
    [
        (200, {"promptFeedback": {"blockReason": "SAFETY"}}),
        ok({"text": ""}, finish="SAFETY"),
        ok({"text": ""}, finish="MALFORMED_FUNCTION_CALL"),
        ok({"functionCall": {"name": "get_goals", "args": "não é objeto"}}),
    ],
    ids=["pergunta-bloqueada", "resposta-bloqueada", "chamada-malformada", "argumentos"],
)
def test_unusable_answers_are_invalid_output(response) -> None:
    with pytest.raises(errors.InvalidModelOutput):
        ask(GeminiProvider(KEY, transport=Transport(response)))


# --- erros ---


@pytest.mark.parametrize(
    ("step", "expected", "transient"),
    [
        (fail(503, "UNAVAILABLE"), errors.ProviderUnavailable, True),
        (fail(500, "INTERNAL"), errors.ProviderUnavailable, True),
        (TimeoutError("lento"), errors.ProviderTimeout, True),
        (urllib.error.URLError(TimeoutError()), errors.ProviderTimeout, True),
        (urllib.error.URLError("sem rede"), errors.ProviderUnavailable, True),
        (fail(400, "INVALID_ARGUMENT"), errors.ProviderError, False),
        (fail(403, "PERMISSION_DENIED"), errors.ProviderError, False),
    ],
)
def test_http_and_network_errors_are_translated(step, expected, transient) -> None:
    with pytest.raises(expected) as caught:
        ask(GeminiProvider(KEY, ONE, transport=Transport(step)))
    assert caught.value.transient is transient


def test_rate_limit_reads_the_retry_delay() -> None:
    quota = fail(
        429,
        "RESOURCE_EXHAUSTED",
        details=[{"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "3s"}],
    )
    with pytest.raises(errors.ProviderRateLimited) as caught:
        ask(GeminiProvider(KEY, ONE, transport=Transport(quota)))
    assert caught.value.retry_after_s == 3.0
    with pytest.raises(errors.ProviderRateLimited) as caught:
        ask(GeminiProvider(KEY, ONE, transport=Transport(fail(429, "RESOURCE_EXHAUSTED"))))
    assert caught.value.retry_after_s is None


def test_retry_recovers_from_overload(caplog) -> None:
    transport = Transport(fail(503, "UNAVAILABLE"), ok({"text": "Pronto."}))
    completion = complete_with_retry(
        GeminiProvider(KEY, ONE, transport=transport),
        system="s",
        messages=[Message.user("Oi")],
        tools=[],
        max_tokens=100,
        timeout_s=5,
        sleep=lambda _: None,
    )
    assert completion.text == "Pronto." and len(transport.calls) == 2


def test_the_key_and_the_conversation_never_reach_errors_or_logs(caplog) -> None:
    caplog.set_level(logging.DEBUG)
    provider = GeminiProvider(KEY, transport=Transport(fail(400, "INVALID_ARGUMENT")))
    with pytest.raises(errors.ProviderError) as caught:
        ask(provider, Message.user("Tenho dor no joelho"))
    assert "HTTP 400" in str(caught.value)
    for text in (str(caught.value), caplog.text, repr(provider)):
        assert KEY not in text
        assert "joelho" not in text


# --- configuração ---


def test_factory_builds_gemini_with_the_key_and_the_model() -> None:
    with pytest.raises(errors.ProviderNotConfigured, match="AI_API_KEY"):
        build_provider(settings(ai_provider="gemini"))
    provider = build_provider(settings(ai_provider="gemini", ai_api_key=KEY))
    assert isinstance(provider, GeminiProvider)
    assert provider.name == "gemini" and provider.model == DEFAULT_MODEL
    custom = build_provider(
        settings(ai_provider="gemini", ai_api_key=KEY, ai_model="gemini-3.8-flash")
    )
    assert custom.model == "gemini-3.8-flash"  # type: ignore[attr-defined]
    assert settings().ai_free_tier is False


# --- plano gratuito: salvaguardas ---


def test_provider_endpoint_names_the_companies_and_the_plan(app, client, signup) -> None:
    from app.core.config import get_settings

    headers = signup()
    assert client.get("/api/v1/ai/provider").status_code == 401
    fake = client.get("/api/v1/ai/provider", headers=headers).json()
    assert fake == {
        "provider": "fake",
        "label": "Respostas simuladas (sem IA real)",
        "companies": [],
        "content_used_by": [],
        "free_tier": False,
        "international_transfer": False,
        "demo": False,
    }
    # Mesma configuração (o mesmo segredo do token), trocando só o provedor.
    current = get_settings()

    def configure(**update) -> dict:
        app.dependency_overrides[get_settings] = lambda: current.model_copy(update=update)
        return client.get("/api/v1/ai/provider", headers=headers).json()

    gemini = configure(ai_provider="gemini", ai_api_key=SecretStr(KEY), ai_free_tier=True)
    assert gemini == {
        "provider": "gemini",
        "label": "Google Gemini",
        "companies": ["Google"],
        "content_used_by": ["Google"],
        "free_tier": True,
        "international_transfer": True,
        "demo": False,
    }
    assert KEY not in json.dumps(gemini)

    both = configure(
        ai_provider="groq,gemini",
        ai_api_key=None,
        ai_groq_api_key=SecretStr("gsk_teste"),
        ai_gemini_api_key=SecretStr(KEY),
        ai_free_tier=True,
    )
    assert both["provider"] == "groq,gemini"
    assert both["label"] == "Groq (GPT-OSS) e Google Gemini"
    assert both["companies"] == ["Groq", "Google"]
    assert both["content_used_by"] == ["Google"]  # o Groq não usa o conteúdo

    # Provedor sem chave não recebe nada, então não aparece.
    only_groq = configure(
        ai_provider="groq,gemini",
        ai_api_key=None,
        ai_groq_api_key=SecretStr("gsk_teste"),
        ai_gemini_api_key=None,
        ai_free_tier=True,
    )
    assert only_groq["companies"] == ["Groq"]
    assert only_groq["content_used_by"] == [] and only_groq["free_tier"] is False


# --- vários modelos (cota do plano gratuito) ---


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


DAILY = fail(
    429,
    "RESOURCE_EXHAUSTED",
    details=[{"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "63000s"}],
)


def model_of(call: dict) -> str:
    return call["url"].rsplit("/", 1)[1].split(":")[0]


def test_model_list_comes_from_the_setting() -> None:
    assert GeminiProvider(KEY).models == DEFAULT_MODELS
    assert GeminiProvider(KEY, " a , b ,").models == ("a", "b")
    assert GeminiProvider(KEY, "a,b").model == "a"


def test_overload_falls_back_to_the_next_model(caplog) -> None:
    caplog.set_level(logging.WARNING)
    transport = Transport(fail(503, "UNAVAILABLE"), ok({"text": "Oi"}, model="b"))
    provider = GeminiProvider(KEY, "a,b", transport=transport, exhausted={})
    completion = ask(provider)
    assert completion.text == "Oi" and completion.model == "b"
    assert [model_of(c) for c in transport.calls] == ["a", "b"]
    assert provider.model == "b"  # o resto da pergunta segue no b
    assert "ai_gemini_fallback" in caplog.text
    # Sobrecarga não esgota a cota: a próxima pergunta volta ao primeiro.
    assert GeminiProvider(KEY, "a,b", exhausted={}).model == "a"


def test_daily_quota_sets_the_model_aside_until_the_reset() -> None:
    clock, exhausted = FakeClock(), {}
    transport = Transport(DAILY, ok({"text": "Oi"}))
    provider = GeminiProvider(KEY, "a,b", transport=transport, clock=clock, exhausted=exhausted)
    ask(provider)
    assert exhausted == {"a": 1000.0 + 63000}
    # As próximas perguntas já começam no b, sem gastar um pedido no a.
    assert GeminiProvider(KEY, "a,b", clock=clock, exhausted=exhausted).model == "b"
    clock.now += 63001
    assert GeminiProvider(KEY, "a,b", clock=clock, exhausted=exhausted).model == "a"


def test_short_rate_limit_does_not_set_the_model_aside() -> None:
    exhausted: dict[str, float] = {}
    minute = fail(
        429,
        "RESOURCE_EXHAUSTED",
        details=[{"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "20s"}],
    )
    transport = Transport(minute, ok({"text": "Oi"}))
    ask(GeminiProvider(KEY, "a,b", transport=transport, exhausted=exhausted))
    assert exhausted == {}


def test_no_fallback_after_a_tool_call_and_none_when_all_fail() -> None:
    call = ToolCall("call_1", "get_goals", {}, signature="sig")
    midway = [
        Message.user("Metas?"),
        Message("assistant", tool_calls=(call,)),
        Message.results(ToolResult("call_1", "{}")),
    ]
    transport = Transport(fail(503, "UNAVAILABLE"))
    with pytest.raises(errors.ProviderUnavailable):
        ask(GeminiProvider(KEY, "a,b", transport=transport, exhausted={}), *midway)
    assert len(transport.calls) == 1  # a assinatura é do a: não troca

    every = Transport(fail(503, "UNAVAILABLE"), DAILY)
    with pytest.raises(errors.ProviderRateLimited):
        ask(GeminiProvider(KEY, "a,b", transport=every, exhausted={}))
    assert [model_of(c) for c in every.calls] == ["a", "b"]
