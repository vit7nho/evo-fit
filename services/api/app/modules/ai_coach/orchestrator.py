"""Laço de ferramentas (AI_DESIGN §2): modelo → pedidos de ferramenta → executor →
modelo … até uma resposta em texto.

Limites (§3 e §6):
- até `MAX_TOOL_CALLS` consultas por resposta; os pedidos além disso voltam ao
  modelo como erro explicado (“responda com o que já tem”);
- até `MAX_ITERATIONS` chamadas ao modelo; a última é feita **sem** ferramentas,
  para forçar a resposta em texto;
- resposta vazia, ou pedido de ferramenta quando nenhuma foi oferecida, é saída
  inválida (`InvalidModelOutput`); erros do provedor sobem para o serviço.

O orquestrador não toca no banco além das ferramentas (que só leem) e não guarda
nada: devolve o texto e os metadados para o serviço registrar.
"""

import json
import time
from collections.abc import Callable
from dataclasses import dataclass, field

from app.integrations.ai.errors import InvalidModelOutput
from app.integrations.ai.provider import LLMProvider, Message, ToolCall, ToolResult, Usage
from app.integrations.ai.retry import complete_with_retry
from app.modules.ai_coach import guardrails
from app.modules.ai_coach.tools import registry
from app.modules.ai_coach.tools.base import ToolContext

MAX_TOOL_CALLS = 6
MAX_ITERATIONS = 5

LIMIT_REACHED = (
    f"Limite de {MAX_TOOL_CALLS} consultas por resposta atingido. "
    "Responda com os dados que já consultou e diga o que ficou de fora."
)


@dataclass(frozen=True)
class ToolTrace:
    """O que vai para o registro: nome, se deu certo e o tempo. Sem argumentos."""

    name: str
    ok: bool
    duration_ms: int

    def as_log(self) -> dict[str, object]:
        return {"name": self.name, "ok": self.ok, "duration_ms": self.duration_ms}


@dataclass
class RunResult:
    text: str
    model: str
    usage: Usage = field(default_factory=Usage)
    iterations: int = 0
    tools: list[ToolTrace] = field(default_factory=list)
    unverified: list[str] = field(default_factory=list)
    truncated: bool = False

    @property
    def tools_used(self) -> list[str]:
        """Ferramentas que trouxeram dados, sem repetição, na ordem da primeira consulta."""
        return list(dict.fromkeys(t.name for t in self.tools if t.ok))


@dataclass
class RunState:
    """Parcial da execução, para o serviço registrar mesmo quando dá erro."""

    usage: Usage = field(default_factory=Usage)
    iterations: int = 0
    tools: list[ToolTrace] = field(default_factory=list)
    model: str = ""


def _execute(ctx: ToolContext, call: ToolCall, state: RunState) -> ToolResult:
    started = time.perf_counter()
    result = registry.execute(ctx, call)
    state.tools.append(
        ToolTrace(call.name, not result.is_error, round((time.perf_counter() - started) * 1000))
    )
    return result


def run(
    provider: LLMProvider,
    ctx: ToolContext,
    *,
    system: str,
    history: list[Message],
    question: str,
    max_tokens: int,
    timeout_s: float,
    state: RunState | None = None,
    sleep: Callable[[float], None] | None = None,
) -> RunResult:
    state = state if state is not None else RunState()
    messages = [*history, Message.user(question)]
    specs = registry.specs()
    # Tudo o que a rodada viu: a base da conferência dos números da resposta.
    sources = [question, system, *(m.content for m in history)]
    calls_made = 0

    while True:
        state.iterations += 1
        last = state.iterations >= MAX_ITERATIONS
        offered = [] if last or calls_made >= MAX_TOOL_CALLS else specs
        completion = complete_with_retry(
            provider,
            system=system,
            messages=messages,
            tools=offered,
            max_tokens=max_tokens,
            timeout_s=timeout_s,
            sleep=sleep or time.sleep,
        )
        state.usage += completion.usage
        state.model = completion.model or state.model

        if completion.tool_calls and offered:
            messages.append(completion.as_message())
            results = []
            for call in completion.tool_calls:
                if calls_made >= MAX_TOOL_CALLS:
                    results.append(
                        ToolResult(
                            call.id,
                            json.dumps({"error": LIMIT_REACHED}, ensure_ascii=False),
                            is_error=True,
                        )
                    )
                    state.tools.append(ToolTrace(call.name, False, 0))
                    continue
                calls_made += 1
                result = _execute(ctx, call, state)
                if not result.is_error:
                    sources.append(result.content)
                results.append(result)
            messages.append(Message.results(*results))
            continue

        text = completion.text.strip()
        if not text:
            raise InvalidModelOutput(
                "Pedido de ferramenta sem ferramentas oferecidas."
                if completion.tool_calls
                else "Resposta vazia."
            )
        capped = guardrails.cap(text)
        return RunResult(
            text=capped,
            model=state.model,
            usage=state.usage,
            iterations=state.iterations,
            tools=state.tools,
            unverified=guardrails.unverified_numbers(capped, sources),
            truncated=completion.stop_reason == "max_tokens" or capped != text,
        )
