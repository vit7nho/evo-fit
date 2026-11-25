"""Adaptador do Groq, cadeia de provedores e configuração (ADR-057). O transporte é
roteirizado — nenhum teste acessa a rede."""

import json
import logging

import pytest
from pydantic import ValidationError

from app.integrations.ai import errors
from app.integrations.ai.factory import build_provider
from app.integrations.ai.fallback import FallbackProvider
from app.integrations.ai.provider import Completion, Message, ToolCall, ToolResult, ToolSpec
from app.integrations.ai.providers import rotation
from app.integrations.ai.providers.fake import FakeProvider
from app.integrations.ai.providers.gemini import GeminiProvider
from app.integrations.ai.providers.groq import (
    DEFAULT_MODELS,
    GroqProvider,
    inline_refs,
    to_messages,
)
from tests.test_ai_provider import settings

KEY = "gsk_chave-de-teste-123"
ONE = "openai/gpt-oss-120b"
TOOL = ToolSpec(
    name="compare_periods",
    description="Compara dois períodos.",
    input_schema={
        "type": "object",
        "properties": {
            "first": {"$ref": "#/$defs/Period", "description": "o primeiro"},
            "second": {"$ref": "#/$defs/Period"},
        },
        "required": ["first", "second"],
        "$defs": {
            "Period": {
                "type": "object",
                "properties": {"from_date": {"type": "string", "format": "date"}},
            }
        },
    },
)


@pytest.fixture(autouse=True)
def fresh_quota():
    rotation._EXHAUSTED.clear()
    yield
    rotation._EXHAUSTED.clear()


class Transport:
    def __init__(self, *steps) -> None:
        self.steps = list(steps)
        self.calls: list[dict] = []

    def __call__(self, url, headers, body, timeout_s):
        self.calls.append({"url": url, "headers": headers, "body": json.loads(body)})
        step = self.steps.pop(0)
        if isinstance(step, Exception):
            raise step
        status, payload, *extra = step
        return status, (extra[0] if extra else {}), json.dumps(payload).encode()


def ok(content=None, tool_calls=None, finish="stop", model="openai/gpt-oss-120b"):
    message: dict = {"role": "assistant", "content": content}
    if tool_calls:
        message["tool_calls"] = tool_calls
    return (
        200,
        {
            "model": model,
            "choices": [{"index": 0, "message": message, "finish_reason": finish}],
            "usage": {"prompt_tokens": 120, "completion_tokens": 30, "total_tokens": 150},
        },
    )


def fail(status, code="", headers=None):
    return (
        status,
        {"error": {"message": "x", "type": "invalid_request_error", "code": code}},
        headers or {},
    )


def ask(provider, *messages, tools=(TOOL,)) -> Completion:
    return provider.complete(
        system="Você é um assistente de treino.",
        messages=list(messages) or [Message.user("Como estou indo?")],
        tools=list(tools),
        max_tokens=1024,
        timeout_s=30,
    )


# --- pedido ---


def test_request_shape_with_bearer_key_and_inlined_schema() -> None:
    transport = Transport(ok("Oi"))
    ask(GroqProvider(KEY, transport=transport))
    call = transport.calls[0]
    assert call["url"] == "https://api.groq.com/openai/v1/chat/completions"
    assert call["headers"]["Authorization"] == f"Bearer {KEY}"
    body = call["body"]
    assert body["model"] == DEFAULT_MODELS[0]
    assert body["messages"] == [
        {"role": "system", "content": "Você é um assistente de treino."},
        {"role": "user", "content": "Como estou indo?"},
    ]
    assert body["max_completion_tokens"] == 1024
    assert (body["reasoning_effort"], body["include_reasoning"]) == ("low", False)
    assert (body["tool_choice"], body["parallel_tool_calls"]) == ("auto", False)
    (tool,) = body["tools"]
    assert tool["type"] == "function" and tool["function"]["name"] == "compare_periods"
    parameters = tool["function"]["parameters"]
    assert "$defs" not in json.dumps(parameters) and "$ref" not in json.dumps(parameters)
    assert parameters["properties"]["first"] == {
        "type": "object",
        "properties": {"from_date": {"type": "string", "format": "date"}},
        "description": "o primeiro",
    }


def test_no_tools_and_no_reasoning_options_for_other_models() -> None:
    transport = Transport(ok("Oi", model="qwen/qwen3.8-27b"))
    ask(GroqProvider(KEY, "qwen/qwen3.8-27b", transport=transport), tools=())
    body = transport.calls[0]["body"]
    for key in ("tools", "tool_choice", "parallel_tool_calls", "reasoning_effort"):
        assert key not in body


def test_inline_refs_survives_recursion_and_broken_refs() -> None:
    schema = {
        "type": "object",
        "properties": {"node": {"$ref": "#/$defs/Node"}, "bad": {"$ref": "#/$defs/Nope"}},
        "$defs": {"Node": {"type": "object", "properties": {"child": {"$ref": "#/$defs/Node"}}}},
    }
    flat = inline_refs(schema)
    assert flat["properties"]["node"]["properties"]["child"] == {}
    assert flat["properties"]["bad"] == {}
    assert "$defs" not in flat
    assert "$defs" in schema  # o original não muda


def test_tool_turns_follow_the_openai_format() -> None:
    call = ToolCall("call_1", "get_goals", {"período": "mês"})
    messages = to_messages(
        "s",
        [
            Message.user("Metas?"),
            Message("assistant", tool_calls=(call,)),
            Message.results(ToolResult("call_1", '{"items": []}')),
            Message("assistant", content="Sem metas."),
        ],
    )
    assert messages[2] == {
        "role": "assistant",
        "content": None,
        "tool_calls": [
            {
                "id": "call_1",
                "type": "function",
                "function": {"name": "get_goals", "arguments": '{"período": "mês"}'},
            }
        ],
    }
    assert messages[3] == {"role": "tool", "tool_call_id": "call_1", "content": '{"items": []}'}
    assert messages[4] == {"role": "assistant", "content": "Sem metas."}


# --- resposta ---


def test_text_and_tool_calls_are_read() -> None:
    text = ask(GroqProvider(KEY, transport=Transport(ok("Você treinou 3 vezes."))))
    assert (text.text, text.stop_reason, text.model) == (
        "Você treinou 3 vezes.",
        "end",
        "openai/gpt-oss-120b",
    )
    assert (text.usage.input_tokens, text.usage.output_tokens) == (120, 30)

    calls = [
        {"id": "fc_1", "type": "function", "function": {"name": "get_goals", "arguments": "{}"}},
        {"type": "function", "function": {"name": "get_goals", "arguments": '{"status": "a"}'}},
    ]
    tool = ask(GroqProvider(KEY, transport=Transport(ok(None, calls, "tool_calls"))))
    assert tool.stop_reason == "tool_use" and tool.text == ""
    first, second = tool.tool_calls
    assert (first.id, first.arguments) == ("fc_1", {})
    assert second.id and second.arguments == {"status": "a"}

    cut = ask(GroqProvider(KEY, transport=Transport(ok("Você", finish="length"))))
    assert cut.stop_reason == "max_tokens"


@pytest.mark.parametrize(
    "response",
    [
        ok(None, [{"type": "function", "function": {"name": "x", "arguments": "{quebrado"}}]),
        ok(None, [{"type": "function", "function": {"name": "x", "arguments": "[1]"}}]),
        ok("x", finish="content_filter"),
        (200, {"choices": []}),
        fail(400, "tool_use_failed"),
    ],
    ids=["json-quebrado", "nao-objeto", "filtro", "sem-escolhas", "tool-use-failed"],
)
def test_unusable_answers_are_invalid_output(response) -> None:
    with pytest.raises(errors.InvalidModelOutput):
        ask(GroqProvider(KEY, ONE, transport=Transport(response)))


# --- erros e cota ---


@pytest.mark.parametrize(
    ("step", "expected", "transient"),
    [
        (fail(503), errors.ProviderUnavailable, True),
        (fail(498), errors.ProviderUnavailable, True),
        (fail(500), errors.ProviderUnavailable, True),
        (TimeoutError("lento"), errors.ProviderTimeout, True),
        (fail(401, "invalid_api_key"), errors.ProviderError, False),
        (fail(400, "invalid_request"), errors.ProviderError, False),
    ],
)
def test_errors_are_translated(step, expected, transient) -> None:
    with pytest.raises(expected) as caught:
        ask(GroqProvider(KEY, ONE, transport=Transport(step)))
    assert caught.value.transient is transient


def test_rate_limit_reads_retry_after_and_413_counts_as_quota() -> None:
    with pytest.raises(errors.ProviderRateLimited) as caught:
        ask(
            GroqProvider(
                KEY,
                ONE,
                transport=Transport(fail(429, "rate_limit_exceeded", {"Retry-After": "7"})),
            )
        )
    assert caught.value.retry_after_s == 7.0
    with pytest.raises(errors.ProviderRateLimited):
        ask(GroqProvider(KEY, ONE, transport=Transport(fail(413, "rate_limit_exceeded"))))


def test_quota_moves_to_the_next_groq_model() -> None:
    exhausted: dict[str, float] = {}
    daily = fail(429, "rate_limit_exceeded", {"retry-after": "40000"})
    transport = Transport(daily, ok("Oi", model="openai/gpt-oss-20b"))
    completion = ask(GroqProvider(KEY, transport=transport, exhausted=exhausted))
    assert completion.model == "openai/gpt-oss-20b"
    assert [c["body"]["model"] for c in transport.calls] == list(DEFAULT_MODELS)
    assert set(exhausted) == {"openai/gpt-oss-120b"}


def test_the_key_never_reaches_errors_or_logs(caplog) -> None:
    caplog.set_level(logging.DEBUG)
    provider = GroqProvider(KEY, ONE, transport=Transport(fail(401, "invalid_api_key")))
    with pytest.raises(errors.ProviderError) as caught:
        ask(provider, Message.user("Tenho dor no joelho"))
    for text in (str(caught.value), caplog.text, repr(provider)):
        assert KEY not in text and "joelho" not in text


# --- cadeia de provedores ---


class Scripted:
    """Provedor de mentira com nome, para a cadeia."""

    def __init__(self, name: str, *steps) -> None:
        self.name = name
        self.fake = FakeProvider(steps)
        self.model = f"{name}-modelo"

    def complete(self, **kwargs):
        return self.fake.complete(**kwargs)


def test_chain_moves_on_quota_or_outage_only_before_the_first_tool(caplog) -> None:
    caplog.set_level(logging.WARNING)
    groq = Scripted("groq", errors.ProviderRateLimited("cota"))
    gemini = Scripted("gemini", Completion(text="Do Gemini."))
    chain = FallbackProvider([groq, gemini])
    assert chain.name == "groq"
    assert ask(chain).text == "Do Gemini."
    assert (chain.name, chain.model) == ("gemini", "gemini-modelo")
    assert "ai_provider_fallback" in caplog.text

    midway = [
        Message.user("Metas?"),
        Message("assistant", tool_calls=(ToolCall("c1", "get_goals", {}),)),
        Message.results(ToolResult("c1", "{}")),
    ]
    stuck = FallbackProvider(
        [Scripted("groq", errors.ProviderUnavailable("caiu")), Scripted("gemini")]
    )
    with pytest.raises(errors.ProviderUnavailable):
        ask(stuck, *midway)
    assert stuck.name == "groq"

    for final in (errors.ProviderTimeout("lento"), errors.ProviderError("401")):
        alone = FallbackProvider([Scripted("groq", final), Scripted("gemini")])
        with pytest.raises(type(final)):
            ask(alone)
        assert alone.name == "groq"


# --- configuração ---


def test_provider_list_is_validated_without_echoing_the_value() -> None:
    assert settings(ai_provider=" groq , gemini ").ai_providers == ("groq", "gemini")
    for wrong in ("outro", "groq,groq", "", "gsk_segredo123"):
        with pytest.raises(ValidationError) as caught:
            settings(ai_provider=wrong)
        if wrong:
            assert "segredo" not in str(caught.value)


def test_each_provider_has_its_own_key_and_model() -> None:
    config = settings(
        ai_provider="groq,gemini",
        ai_groq_api_key=KEY,
        ai_gemini_api_key="AQ.outra",
        ai_gemini_model="gemini-3.5-flash-lite",
    )
    chain = build_provider(config)
    assert isinstance(chain, FallbackProvider)
    groq, gemini = chain.providers
    assert isinstance(groq, GroqProvider) and groq.models == DEFAULT_MODELS
    assert isinstance(gemini, GeminiProvider) and gemini.models == ("gemini-3.5-flash-lite",)
    for secret in (KEY, "AQ.outra"):
        assert secret not in repr(config) and secret not in repr(chain)

    # AI_API_KEY/AI_MODEL valem só para o primeiro provedor real (compatibilidade).
    legacy = settings(ai_provider="gemini,groq", ai_api_key="AQ.velha", ai_model="m1")
    assert legacy.ai_key_for("gemini").get_secret_value() == "AQ.velha"  # type: ignore[union-attr]
    assert legacy.ai_key_for("groq") is None and legacy.ai_model_for("groq") is None
    assert legacy.ai_model_for("gemini") == "m1"


def test_providers_without_a_key_are_skipped(caplog) -> None:
    caplog.set_level(logging.WARNING)
    only_groq = build_provider(settings(ai_provider="groq,gemini", ai_groq_api_key=KEY))
    assert isinstance(only_groq, GroqProvider)
    assert "ai_provider_skipped" in caplog.text
    with pytest.raises(errors.ProviderNotConfigured, match="AI_GROQ_API_KEY"):
        build_provider(settings(ai_provider="groq"))
    with pytest.raises(errors.ProviderNotConfigured, match="Nenhum provedor"):
        build_provider(settings(ai_provider="groq,gemini"))


def test_groq_switches_model_mid_question_when_the_minute_runs_out() -> None:
    # Groq: o histórico é texto comum; o próximo modelo continua a mesma pergunta.
    midway = [
        Message.user("Metas?"),
        Message("assistant", tool_calls=(ToolCall("c1", "get_goals", {}),)),
        Message.results(ToolResult("c1", "{}")),
    ]
    minute = fail(429, "rate_limit_exceeded", {"retry-after": "25"})
    transport = Transport(minute, ok("Sem metas.", model="openai/gpt-oss-20b"))
    exhausted: dict[str, float] = {}
    completion = ask(GroqProvider(KEY, transport=transport, exhausted=exhausted), *midway)
    assert completion.text == "Sem metas."
    assert [c["body"]["model"] for c in transport.calls] == list(DEFAULT_MODELS)
    assert exhausted == {}  # limite por minuto não tira o modelo do dia
    assert transport.calls[0]["headers"]["User-Agent"] == "evofit-api/1.0"
