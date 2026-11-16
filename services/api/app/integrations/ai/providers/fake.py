"""Provedor falso (AI_DESIGN §2): sem rede, sem custo e determinístico.

- **Roteirizado** (testes): recebe a sequência de respostas — `Completion`, uma
  exceção (`ProviderError`) para simular falhas ou uma função que monta a resposta
  a partir do pedido — e guarda cada pedido recebido para conferência.
- **Demonstração** (sem roteiro): responde sempre em texto, dizendo que é uma
  resposta simulada. Nunca inventa números: o provedor real chega na 4.4.
"""

import copy
from collections.abc import Callable, Iterable
from dataclasses import dataclass

from app.integrations.ai.provider import Completion, Message, ToolSpec, Usage

FAKE_MODEL = "fake-v1"

DEMO_REPLY = (
    "Esta é uma resposta simulada: a IA de verdade ainda não está ligada neste "
    "servidor, então não vou citar números dos seus registros. Quando ela estiver "
    "ativa, vou consultar seus treinos e atividades para responder."
)


@dataclass(frozen=True)
class FakeRequest:
    """Um pedido recebido pelo falso (cópia, para o teste conferir depois)."""

    system: str
    messages: list[Message]
    tools: list[ToolSpec]
    max_tokens: int
    timeout_s: float


Step = Completion | Exception | Callable[[FakeRequest], Completion]


class FakeScriptExhausted(AssertionError):
    """O orquestrador pediu mais respostas do que o roteiro previa (erro de teste)."""


def estimate_tokens(text: str) -> int:
    """Estimativa simples (~4 caracteres por token), só para o consumo não ser zero."""
    return max(1, round(len(text) / 4)) if text else 0


class FakeProvider:
    name = "fake"

    def __init__(self, script: Iterable[Step] | None = None) -> None:
        self._script = None if script is None else list(script)
        self.requests: list[FakeRequest] = []

    @property
    def remaining(self) -> int:
        return 0 if self._script is None else len(self._script)

    def complete(
        self,
        *,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int,
        timeout_s: float,
    ) -> Completion:
        request = FakeRequest(
            system=system,
            messages=copy.deepcopy(messages),
            tools=list(tools),
            max_tokens=max_tokens,
            timeout_s=timeout_s,
        )
        self.requests.append(request)
        if self._script is None:
            return self._demo(request)
        if not self._script:
            raise FakeScriptExhausted(
                f"Roteiro do FakeProvider esgotado no pedido {len(self.requests)}."
            )
        step = self._script.pop(0)
        if isinstance(step, Exception):
            raise step
        completion = step(request) if callable(step) else step
        if completion.model:
            return completion
        return Completion(
            text=completion.text,
            tool_calls=completion.tool_calls,
            stop_reason=completion.stop_reason,
            usage=completion.usage,
            model=FAKE_MODEL,
        )

    @staticmethod
    def _demo(request: FakeRequest) -> Completion:
        prompt = request.system + "".join(m.content for m in request.messages)
        return Completion(
            text=DEMO_REPLY,
            stop_reason="end",
            usage=Usage(estimate_tokens(prompt), estimate_tokens(DEMO_REPLY)),
            model=FAKE_MODEL,
        )
