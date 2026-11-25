"""Camada do provedor de IA (4.1): tipos neutros, provedor falso, erros, nova
tentativa e escolha pela configuração. Nada aqui acessa a rede."""

import logging

import pytest
from pydantic import SecretStr, ValidationError

from app.core.config import Settings
from app.integrations.ai import errors
from app.integrations.ai.factory import build_provider
from app.integrations.ai.provider import (
    Completion,
    LLMProvider,
    Message,
    ToolCall,
    ToolResult,
    ToolSpec,
    Usage,
)
from app.integrations.ai.providers.fake import (
    DEMO_REPLY,
    FAKE_MODEL,
    FakeProvider,
    FakeRequest,
    FakeScriptExhausted,
)
from app.integrations.ai.retry import complete_with_retry

SYSTEM = "Você é um assistente de treino."
TOOL = ToolSpec(
    name="get_goals",
    description="Metas da pessoa e o progresso.",
    input_schema={"type": "object", "properties": {"status": {"type": "string"}}},
)


def ask(provider: LLMProvider, *messages: Message, tools=(TOOL,)) -> Completion:
    return provider.complete(
        system=SYSTEM,
        messages=list(messages) or [Message.user("Como estou indo?")],
        tools=list(tools),
        max_tokens=800,
        timeout_s=30,
    )


def settings(**changes) -> Settings:
    base = {"database_url": "postgresql://x", "jwt_secret": "x" * 32}
    # Sem o .env: o resultado depende só do teste (e nunca da chave real).
    return Settings(_env_file=None, **{**base, **changes})  # type: ignore[arg-type, call-arg]


# --- tipos neutros ---


def test_messages_reject_incoherent_content() -> None:
    call = ToolCall("c1", "get_goals", {})
    Message.user("Oi")
    Message("assistant", content="Olá")
    Message("assistant", tool_calls=(call,))
    Message.results(ToolResult("c1", "[]"))
    for bad in (
        lambda: Message.user("   "),
        lambda: Message("user", content="Oi", tool_calls=(call,)),
        lambda: Message("assistant"),
        lambda: Message("tool", content="texto solto"),
        lambda: Message("tool"),
    ):
        with pytest.raises(ValueError):
            bad()


def test_completion_continues_the_conversation_and_usage_adds_up() -> None:
    call = ToolCall("c1", "get_goals", {"status": "active"})
    reply = Completion(text="Vou ver suas metas.", tool_calls=(call,), stop_reason="tool_use")
    message = reply.as_message()
    assert (message.role, message.content, message.tool_calls) == (
        "assistant",
        "Vou ver suas metas.",
        (call,),
    )
    assert (Usage(10, 2) + Usage(5, 3)).total == 20


# --- provedor falso ---


def test_fake_follows_the_script_and_records_each_request() -> None:
    call = ToolCall("c1", "get_goals", {"status": "active"})
    fake = FakeProvider(
        [
            Completion(tool_calls=(call,), stop_reason="tool_use", usage=Usage(50, 10)),
            lambda request: Completion(
                text=f"Você tem {request.messages[-1].tool_results[0].content} metas.",
                usage=Usage(70, 12),
            ),
        ]
    )

    first = ask(fake)
    assert first.tool_calls == (call,)
    assert first.model == FAKE_MODEL
    question = Message.user("Como estou indo?")
    second = ask(fake, question, first.as_message(), Message.results(ToolResult("c1", "2")))

    assert second.text == "Você tem 2 metas."
    assert fake.remaining == 0
    assert [len(r.messages) for r in fake.requests] == [1, 3]
    assert fake.requests[0] == FakeRequest(SYSTEM, [question], [TOOL], 800, 30)


def test_fake_can_simulate_failures_and_complains_when_the_script_ends() -> None:
    fake = FakeProvider([errors.ProviderTimeout("sem resposta")])
    with pytest.raises(errors.ProviderTimeout):
        ask(fake)
    with pytest.raises(FakeScriptExhausted):
        ask(fake)


def test_fake_requests_are_copies() -> None:
    fake = FakeProvider([Completion(text="ok")])
    messages = [Message.user("Oi")]
    fake.complete(system=SYSTEM, messages=messages, tools=[], max_tokens=10, timeout_s=1)
    messages.append(Message("assistant", content="mudou"))
    assert len(fake.requests[0].messages) == 1


def test_demo_mode_never_invents_numbers() -> None:
    fake = FakeProvider()
    reply = ask(fake, Message.user("Quantos treinos fiz?"))
    assert reply.text == DEMO_REPLY
    assert not any(char.isdigit() for char in reply.text)
    assert reply.stop_reason == "end"
    assert reply.tool_calls == ()
    assert reply.usage.input_tokens > 0 and reply.usage.output_tokens > 0
    # Determinístico: a mesma pergunta, a mesma resposta.
    assert ask(fake, Message.user("Quantos treinos fiz?")) == reply


# --- erros e nova tentativa ---


def test_errors_say_what_to_retry_and_what_to_show() -> None:
    transient = (errors.ProviderUnavailable, errors.ProviderTimeout, errors.ProviderRateLimited)
    final = (errors.InvalidModelOutput, errors.ProviderNotConfigured)
    assert all(e.transient for e in transient)
    assert not any(e.transient for e in final)
    codes = {e.code for e in (*transient, *final)}
    assert len(codes) == 5
    # O texto para o app não traz detalhe técnico.
    error = errors.ProviderUnavailable("HTTP 503 em https://api.exemplo/v1 com a chave sk-...")
    assert "503" not in error.user_message and "sk-" not in error.user_message


def test_retry_recovers_from_transient_errors_with_growing_waits(caplog) -> None:
    waits: list[float] = []
    fake = FakeProvider(
        [errors.ProviderUnavailable("503"), errors.ProviderTimeout(), Completion(text="ok")]
    )
    with caplog.at_level(logging.WARNING):
        reply = complete_with_retry(
            fake,
            system=SYSTEM,
            messages=[Message.user("Pergunta com dado pessoal")],
            tools=[],
            max_tokens=100,
            timeout_s=30,
            sleep=waits.append,
        )
    assert reply.text == "ok"
    assert waits == [0.5, 1.0]
    assert len(fake.requests) == 3
    # O log diz o que houve, mas não leva o conteúdo da conversa.
    assert [r.error_code for r in caplog.records] == ["ai_unavailable", "ai_timeout"]
    assert "dado pessoal" not in caplog.text


def test_retry_gives_up_after_two_and_never_retries_final_errors() -> None:
    waits: list[float] = []

    def run(script):
        return complete_with_retry(
            FakeProvider(script),
            system=SYSTEM,
            messages=[Message.user("Oi")],
            tools=[],
            max_tokens=100,
            timeout_s=30,
            sleep=waits.append,
        )

    with pytest.raises(errors.ProviderUnavailable):
        run([errors.ProviderUnavailable()] * 3 + [Completion(text="tarde demais")])
    assert len(waits) == 2

    waits.clear()
    with pytest.raises(errors.InvalidModelOutput):
        run([errors.InvalidModelOutput(), Completion(text="não chega")])
    assert waits == []


def test_retry_respects_retry_after_within_limits() -> None:
    waits: list[float] = []

    def run(retry_after: float):
        return complete_with_retry(
            FakeProvider(
                [errors.ProviderRateLimited(retry_after_s=retry_after), Completion(text="ok")]
            ),
            system=SYSTEM,
            messages=[Message.user("Oi")],
            tools=[],
            max_tokens=100,
            timeout_s=30,
            sleep=waits.append,
        )

    assert run(2.0).text == "ok"
    assert waits == [2.0]
    # Mandar esperar demais: desiste e a pessoa recebe a mensagem amigável.
    with pytest.raises(errors.ProviderRateLimited):
        run(60.0)
    assert waits == [2.0]


# --- configuração ---


def test_factory_uses_fake_by_default_and_refuses_unconfigured_real_provider() -> None:
    config = settings()
    assert config.ai_provider == "fake"
    assert isinstance(build_provider(config), FakeProvider)

    with pytest.raises(errors.ProviderNotConfigured, match="Sem adaptador"):
        build_provider(settings(ai_provider="anthropic"))
    with pytest.raises(errors.ProviderNotConfigured, match="Sem adaptador"):
        build_provider(settings(ai_provider="anthropic", ai_api_key="sk-teste"))


def test_settings_validate_the_provider_and_hide_the_key() -> None:
    with pytest.raises(ValidationError):
        settings(ai_provider="outro")
    with pytest.raises(ValidationError):
        settings(ai_timeout_s=0)
    config = settings(ai_provider="anthropic", ai_api_key="sk-segredo-123")
    assert isinstance(config.ai_api_key, SecretStr)
    assert "sk-segredo-123" not in repr(config)
    assert "sk-segredo-123" not in str(config.model_dump())


def test_only_the_adapters_folder_may_know_the_vendor() -> None:
    from pathlib import Path

    import app

    root = Path(app.__file__).parent
    offenders = [
        str(path.relative_to(root))
        for path in root.rglob("*.py")
        if "providers" not in path.parts
        and any(
            name in path.read_text(encoding="utf-8")
            for name in (
                "import anthropic",
                "from anthropic",
                "import openai",
                "generativelanguage.googleapis",
                "x-goog-api-key",
                "api.groq.com",
            )
        )
    ]
    assert offenders == []
