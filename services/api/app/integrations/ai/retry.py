"""Nova tentativa só para erros transitórios (AI_DESIGN §6: timeout, 429 e 5xx; no
máximo 2, com espera crescente). Erros definitivos sobem na hora.

Os logs registram o provedor, o código do erro e a tentativa — nunca o conteúdo da
conversa.
"""

import logging
import time
from collections.abc import Callable

from app.integrations.ai.errors import ProviderError, ProviderRateLimited
from app.integrations.ai.provider import Completion, LLMProvider, Message, ToolSpec

logger = logging.getLogger(__name__)

# Espera máxima aceita de um `Retry-After` (acima disso, desiste e avisa a pessoa).
MAX_WAIT_S = 5.0


def complete_with_retry(
    provider: LLMProvider,
    *,
    system: str,
    messages: list[Message],
    tools: list[ToolSpec],
    max_tokens: int,
    timeout_s: float,
    retries: int = 2,
    base_delay_s: float = 0.5,
    sleep: Callable[[float], None] = time.sleep,
) -> Completion:
    attempt = 0
    while True:
        try:
            return provider.complete(
                system=system,
                messages=messages,
                tools=tools,
                max_tokens=max_tokens,
                timeout_s=timeout_s,
            )
        except ProviderError as error:
            if not error.transient or attempt >= retries:
                raise
            delay = base_delay_s * 2**attempt
            if isinstance(error, ProviderRateLimited) and error.retry_after_s is not None:
                if error.retry_after_s > MAX_WAIT_S:
                    raise
                delay = max(delay, error.retry_after_s)
            attempt += 1
            logger.warning(
                "ai_provider_retry",
                extra={
                    "provider": provider.name,
                    "error_code": error.code,
                    "attempt": attempt,
                    "delay_s": delay,
                },
            )
            sleep(delay)
