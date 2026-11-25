"""Partes comuns dos adaptadores REST (Gemini, Groq): a chamada HTTP com os erros
de rede traduzidos e a troca de modelo quando a cota acaba (ADR-056/057).

Troca de modelo: com 429 ou 503 no primeiro pedido de uma pergunta, o adaptador
tenta o próximo modelo da lista; o modelo com a cota esgotada (espera acima de
`SHORT_WAIT_S`, ou sem prazo informado) fica de lado até o prazo. Depois da
primeira chamada de ferramenta a pergunta segue no mesmo modelo quando o histórico
é do modelo (a assinatura de raciocínio do Gemini); no Groq pode trocar
(`switch_midway`), porque o limite de tokens por minuto estoura no meio da pergunta.
"""

import logging
import urllib.error
import urllib.request
from collections.abc import Callable
from typing import Any

from app.integrations.ai.errors import (
    ProviderRateLimited,
    ProviderTimeout,
    ProviderUnavailable,
)
from app.integrations.ai.provider import Completion, Message, ToolSpec

logger = logging.getLogger(__name__)

# Espera curta (limite por minuto) não tira o modelo da lista; acima disso, sim.
SHORT_WAIT_S = 60.0

# Modelo → instante (time.monotonic) até quando a cota está esgotada. Fica no
# processo: cada pergunta monta um provedor novo.
_EXHAUSTED: dict[str, float] = {}


def urlopen_post(
    url: str, headers: dict[str, str], body: bytes, timeout_s: float
) -> tuple[int, dict[str, str], bytes]:
    """POST HTTPS com a biblioteca padrão: (status, cabeçalhos, corpo)."""
    if not url.startswith("https://"):
        raise ValueError("Só HTTPS.")
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")  # noqa: S310
    try:
        with urllib.request.urlopen(request, timeout=timeout_s) as response:  # noqa: S310
            return response.status, dict(response.headers.items()), response.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers.items()), error.read()


def network_errors(vendor: str, send: Callable[[], Any]) -> Any:
    """Executa o envio traduzindo tempo esgotado e falha de rede."""
    try:
        return send()
    except TimeoutError as error:
        raise ProviderTimeout(f"{vendor}: tempo esgotado.") from error
    except urllib.error.URLError as error:
        if isinstance(error.reason, TimeoutError):
            raise ProviderTimeout(f"{vendor}: tempo esgotado.") from error
        raise ProviderUnavailable(f"{vendor}: falha de rede.") from error
    except OSError as error:
        raise ProviderUnavailable(f"{vendor}: falha de rede.") from error


class ModelRotation:
    """Escolhe o modelo da pergunta e troca de modelo na cota (ver o módulo)."""

    name: str
    model: str
    models: tuple[str, ...]
    # Pode trocar de modelo no meio da pergunta? Não no Gemini (a assinatura de
    # raciocínio é do modelo que a gerou); sim no Groq (o histórico é texto comum, e
    # cada modelo tem a própria cota por minuto).
    switch_midway = False

    def _init_models(
        self,
        model: str | None,
        defaults: tuple[str, ...],
        clock: Callable[[], float],
        exhausted: dict[str, float] | None,
    ) -> None:
        names = [m.strip() for m in (model or "").split(",") if m.strip()]
        self.models = tuple(names) or defaults
        self._clock = clock
        self._exhausted = _EXHAUSTED if exhausted is None else exhausted
        now = clock()
        self.model = next(
            (m for m in self.models if self._exhausted.get(m, 0) <= now), self.models[0]
        )

    def __repr__(self) -> str:  # a chave nunca aparece
        return f"{type(self).__name__}(model={self.model!r})"

    def _call(
        self,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int,
        timeout_s: float,
    ) -> Completion:
        raise NotImplementedError

    def complete(
        self,
        *,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int,
        timeout_s: float,
    ) -> Completion:
        started = any(m.tool_calls for m in messages) and not self.switch_midway
        while True:
            try:
                return self._call(system, messages, tools, max_tokens, timeout_s)
            except (ProviderRateLimited, ProviderUnavailable) as error:
                if isinstance(error, ProviderTimeout):
                    raise
                if isinstance(error, ProviderRateLimited):
                    wait = error.retry_after_s
                    if wait is None or wait > SHORT_WAIT_S:
                        self._exhausted[self.model] = self._clock() + (wait or SHORT_WAIT_S)
                following = self._next_model()
                if started or following is None:
                    raise
                logger.warning(
                    f"ai_{self.name}_fallback",
                    extra={"from": self.model, "to": following, "error_code": error.code},
                )
                self.model = following

    def _next_model(self) -> str | None:
        now = self._clock()
        index = self.models.index(self.model) if self.model in self.models else -1
        for model in self.models[index + 1 :]:
            if self._exhausted.get(model, 0) <= now:
                return model
        return None
