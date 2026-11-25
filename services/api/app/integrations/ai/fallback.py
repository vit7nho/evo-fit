"""Vários provedores em ordem de preferência (ADR-057): `AI_PROVIDER=groq,gemini`.

Com cota esgotada (429) ou indisponibilidade (503, rede) no **primeiro** pedido de
uma pergunta, a pergunta vai ao próximo provedor da lista. Depois da primeira
chamada de ferramenta, a pergunta fica no provedor que começou: o histórico das
ferramentas (e a assinatura de raciocínio do Gemini) é dele. Tempo esgotado não
troca de provedor: a pessoa já esperou o bastante, e a nova tentativa decide.

Não conhece nenhum fornecedor: só o `LLMProvider` e os erros neutros.
"""

import logging

from app.integrations.ai.errors import (
    ProviderRateLimited,
    ProviderTimeout,
    ProviderUnavailable,
)
from app.integrations.ai.provider import Completion, LLMProvider, Message, ToolSpec

logger = logging.getLogger(__name__)


class FallbackProvider:
    def __init__(self, providers: list[LLMProvider]) -> None:
        if not providers:
            raise ValueError("Pelo menos um provedor.")
        self.providers = providers
        self._current = 0

    @property
    def current(self) -> LLMProvider:
        return self.providers[self._current]

    @property
    def name(self) -> str:  # type: ignore[override]
        """O provedor que está respondendo (vai para o registro da execução)."""
        return self.current.name

    @property
    def model(self) -> str:
        return str(getattr(self.current, "model", ""))

    def __repr__(self) -> str:
        return f"FallbackProvider({[p.name for p in self.providers]})"

    def complete(
        self,
        *,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int,
        timeout_s: float,
    ) -> Completion:
        started = any(m.tool_calls for m in messages)
        while True:
            try:
                return self.current.complete(
                    system=system,
                    messages=messages,
                    tools=tools,
                    max_tokens=max_tokens,
                    timeout_s=timeout_s,
                )
            except (ProviderRateLimited, ProviderUnavailable) as error:
                last = self._current + 1 >= len(self.providers)
                if isinstance(error, ProviderTimeout) or started or last:
                    raise
                following = self.providers[self._current + 1]
                logger.warning(
                    "ai_provider_fallback",
                    extra={
                        "from": self.current.name,
                        "to": following.name,
                        "error_code": error.code,
                    },
                )
                self._current += 1
