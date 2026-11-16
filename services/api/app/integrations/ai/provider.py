"""Interface neutra com o modelo de linguagem (ADR-011, AI_DESIGN §2).

Só tipos simples e um `Protocol`: nenhum arquivo fora de `providers/` conhece o
fornecedor. O orquestrador (4.3) fala com qualquer `LLMProvider` por estes tipos, e
trocar de fornecedor é escrever um adaptador novo (4.4).
"""

from dataclasses import dataclass, field
from typing import Any, Literal, Protocol

Role = Literal["user", "assistant", "tool"]
# end: o modelo terminou; tool_use: pediu ferramentas; max_tokens: cortado no limite.
StopReason = Literal["end", "tool_use", "max_tokens"]


@dataclass(frozen=True)
class ToolSpec:
    """Uma ferramenta oferecida ao modelo: nome, descrição (em português) e o JSON
    Schema da entrada (gerado do modelo Pydantic da ferramenta)."""

    name: str
    description: str
    input_schema: dict[str, Any]


@dataclass(frozen=True)
class ToolCall:
    """Pedido do modelo para executar uma ferramenta. Os argumentos ainda não foram
    validados: quem executa valida (e nunca aceita `user_id` vindo daqui)."""

    id: str
    name: str
    arguments: dict[str, Any]


@dataclass(frozen=True)
class ToolResult:
    """Resposta de uma ferramenta, devolvida ao modelo (conteúdo em JSON, como texto)."""

    call_id: str
    content: str
    is_error: bool = False


@dataclass(frozen=True)
class Message:
    """Uma mensagem da conversa. `user`: a pergunta; `assistant`: o texto e/ou os
    pedidos de ferramenta do modelo; `tool`: os resultados desses pedidos."""

    role: Role
    content: str = ""
    tool_calls: tuple[ToolCall, ...] = ()
    tool_results: tuple[ToolResult, ...] = ()

    def __post_init__(self) -> None:
        match self.role:
            case "user":
                ok = bool(self.content.strip()) and not self.tool_calls and not self.tool_results
            case "assistant":
                ok = (bool(self.content.strip()) or bool(self.tool_calls)) and not self.tool_results
            case "tool":
                ok = bool(self.tool_results) and not self.content and not self.tool_calls
        if not ok:
            raise ValueError(f"Mensagem '{self.role}' com conteúdo incoerente.")

    @classmethod
    def user(cls, text: str) -> Message:
        return cls("user", content=text)

    @classmethod
    def results(cls, *results: ToolResult) -> Message:
        return cls("tool", tool_results=results)


@dataclass(frozen=True)
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0

    @property
    def total(self) -> int:
        return self.input_tokens + self.output_tokens

    def __add__(self, other: Usage) -> Usage:
        return Usage(
            self.input_tokens + other.input_tokens, self.output_tokens + other.output_tokens
        )


@dataclass(frozen=True)
class Completion:
    """Uma resposta do modelo: texto, pedidos de ferramenta (ou os dois), o motivo da
    parada, o consumo e o modelo que respondeu (vai para `ai_run_logs`)."""

    text: str = ""
    tool_calls: tuple[ToolCall, ...] = ()
    stop_reason: StopReason = "end"
    usage: Usage = field(default_factory=Usage)
    model: str = ""

    def as_message(self) -> Message:
        """A resposta como mensagem do assistente, para seguir a conversa."""
        return Message("assistant", content=self.text, tool_calls=self.tool_calls)


class LLMProvider(Protocol):
    """Um fornecedor de modelo. Erros saem como `ProviderError` (errors.py), nunca
    como exceções do SDK do fornecedor."""

    name: str

    def complete(
        self,
        *,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int,
        timeout_s: float,
    ) -> Completion: ...
