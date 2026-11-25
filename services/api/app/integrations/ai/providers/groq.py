"""Adaptador do Groq (ADR-057): Chat Completions no formato da OpenAI, por REST.

Sem dependência nova (biblioteca padrão; transporte injetável nos testes).

Tradução dos tipos neutros (provider.py):
- o `system` vai como a primeira mensagem `system`;
- `assistant` → `{"role": "assistant", "content", "tool_calls"}` com os argumentos
  em texto JSON; `tool` → uma mensagem `{"role": "tool", "tool_call_id", "content"}`
  por resultado;
- ferramentas em `{"type": "function", "function": {name, description,
  parameters}}`, com os `$ref` do Pydantic resolvidos no lugar (a documentação do
  Groq não garante `$ref`/`$defs`).

Modelos `openai/gpt-oss-*`: raciocínio `low` (`reasoning_effort`) e sem o texto do
raciocínio na resposta (`include_reasoning: false`) — nada a devolver na rodada
seguinte. Uma ferramenta por vez (`parallel_tool_calls: false`): o gpt-oss não faz
chamadas paralelas.

Erros: 429 → `ProviderRateLimited` (com o `retry-after`); 413 (pedido maior que o
limite de tokens por minuto do modelo) → também cota, para trocar de modelo; 498
(capacidade), 5xx e rede → `ProviderUnavailable`; 400 `tool_use_failed` (chamada de
ferramenta malformada) → `InvalidModelOutput`; outros 4xx → `ProviderError`.
Mensagens e logs levam só o código HTTP e o código de erro do Groq.
"""

import copy
import json
import logging
import time
from collections.abc import Callable
from typing import Any

from app.integrations.ai.errors import (
    InvalidModelOutput,
    ProviderError,
    ProviderRateLimited,
    ProviderUnavailable,
)
from app.integrations.ai.provider import (
    Completion,
    Message,
    StopReason,
    ToolCall,
    ToolSpec,
    Usage,
)
from app.integrations.ai.providers.rotation import ModelRotation, network_errors, urlopen_post

logger = logging.getLogger(__name__)

URL = "https://api.groq.com/openai/v1/chat/completions"
USER_AGENT = "evofit-api/1.0"
# Cota por modelo: o 20b entra quando o 120b esgota.
DEFAULT_MODELS = ("openai/gpt-oss-120b", "openai/gpt-oss-20b")

# (status, cabeçalhos, corpo) — ou exceção de rede/tempo.
Transport = Callable[[str, dict[str, str], bytes, float], tuple[int, dict[str, str], bytes]]


def inline_refs(schema: dict[str, Any]) -> dict[str, Any]:
    """Troca cada `{"$ref": "#/$defs/X"}` pela definição e tira os `$defs`."""
    defs = schema.get("$defs", {})

    def resolve(node: Any, seen: tuple[str, ...]) -> Any:
        if isinstance(node, dict):
            ref = node.get("$ref")
            if isinstance(ref, str) and ref.startswith("#/$defs/"):
                name = ref.removeprefix("#/$defs/")
                if name in seen or name not in defs:
                    return {}  # recursão ou referência quebrada: aceita qualquer valor
                target = resolve(copy.deepcopy(defs[name]), (*seen, name))
                extra = {k: v for k, v in node.items() if k != "$ref"}
                return {**target, **resolve(extra, seen)}
            return {k: resolve(v, seen) for k, v in node.items() if k != "$defs"}
        if isinstance(node, list):
            return [resolve(item, seen) for item in node]
        return node

    return resolve(schema, ())


def to_messages(system: str, messages: list[Message]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = [{"role": "system", "content": system}]
    for message in messages:
        match message.role:
            case "user":
                result.append({"role": "user", "content": message.content})
            case "assistant":
                item: dict[str, Any] = {"role": "assistant", "content": message.content or None}
                if message.tool_calls:
                    item["tool_calls"] = [
                        {
                            "id": call.id,
                            "type": "function",
                            "function": {
                                "name": call.name,
                                "arguments": json.dumps(call.arguments, ensure_ascii=False),
                            },
                        }
                        for call in message.tool_calls
                    ]
                result.append(item)
            case "tool":
                result.extend(
                    {"role": "tool", "tool_call_id": r.call_id, "content": r.content}
                    for r in message.tool_results
                )
    return result


def _retry_after(headers: dict[str, str]) -> float | None:
    value = next((v for k, v in headers.items() if k.lower() == "retry-after"), None)
    try:
        return float(value) if value is not None else None
    except ValueError:
        return None


class GroqProvider(ModelRotation):
    name = "groq"
    # 8.000 tokens por minuto por modelo (verificado): a terceira chamada de uma
    # pergunta estoura; o próximo modelo tem a própria cota e continua a pergunta.
    switch_midway = True

    def __init__(
        self,
        api_key: str,
        model: str | None = None,
        *,
        transport: Transport = urlopen_post,
        clock: Callable[[], float] = time.monotonic,
        exhausted: dict[str, float] | None = None,
    ) -> None:
        self._api_key = api_key
        self._transport = transport
        self._init_models(model, DEFAULT_MODELS, clock, exhausted)

    def request_body(
        self, *, system: str, messages: list[Message], tools: list[ToolSpec], max_tokens: int
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "model": self.model,
            "messages": to_messages(system, messages),
            "max_completion_tokens": max_tokens,
        }
        if self.model.startswith("openai/gpt-oss"):
            body["reasoning_effort"] = "low"
            body["include_reasoning"] = False
        if tools:
            body["tools"] = [
                {
                    "type": "function",
                    "function": {
                        "name": t.name,
                        "description": t.description,
                        "parameters": inline_refs(t.input_schema),
                    },
                }
                for t in tools
            ]
            body["tool_choice"] = "auto"
            body["parallel_tool_calls"] = False
        return body

    def _call(
        self,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int,
        timeout_s: float,
    ) -> Completion:
        body = self.request_body(
            system=system, messages=messages, tools=tools, max_tokens=max_tokens
        )
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
            # O Cloudflare do Groq recusa o agente padrão do urllib (403, código 1010).
            "User-Agent": USER_AGENT,
        }
        data = json.dumps(body, ensure_ascii=False).encode()
        status, response_headers, raw = network_errors(
            "Groq", lambda: self._transport(URL, headers, data, timeout_s)
        )
        try:
            payload = json.loads(raw or b"{}")
        except ValueError:
            payload = {}
        if not isinstance(payload, dict):
            payload = {}
        if status != 200:
            raise self._error(status, response_headers, payload)
        return self._completion(payload)

    @staticmethod
    def _error(status: int, headers: dict[str, str], payload: dict[str, Any]) -> ProviderError:
        error = payload.get("error") if isinstance(payload.get("error"), dict) else {}
        code = str(error.get("code") or error.get("type") or "")[:40]
        logger.warning("ai_groq_http_error", extra={"status": status, "groq": code})
        message = f"Groq: HTTP {status} {code}".strip()
        if status in (413, 429):
            return ProviderRateLimited(message, retry_after_s=_retry_after(headers))
        if status == 498 or status >= 500:
            return ProviderUnavailable(message)
        if code == "tool_use_failed":
            return InvalidModelOutput(message)
        return ProviderError(message)

    def _completion(self, payload: dict[str, Any]) -> Completion:
        choices = payload.get("choices") or []
        if not choices:
            raise InvalidModelOutput("Groq: resposta sem escolhas.")
        choice = choices[0]
        message = choice.get("message") or {}
        calls: list[ToolCall] = []
        for index, call in enumerate(message.get("tool_calls") or []):
            function = call.get("function") or {}
            try:
                arguments = json.loads(function.get("arguments") or "{}")
            except ValueError:
                arguments = None
            if not isinstance(arguments, dict) or not function.get("name"):
                raise InvalidModelOutput("Groq: chamada de ferramenta malformada.")
            calls.append(
                ToolCall(
                    id=call.get("id") or f"groq-{index}",
                    name=function["name"],
                    arguments=arguments,
                )
            )
        finish = choice.get("finish_reason")
        if finish == "content_filter":
            raise InvalidModelOutput("Groq: resposta bloqueada.")
        stop: StopReason = "tool_use" if calls else "max_tokens" if finish == "length" else "end"
        usage = payload.get("usage") or {}
        content = message.get("content")
        return Completion(
            text=content if isinstance(content, str) else "",
            tool_calls=tuple(calls),
            stop_reason=stop,
            usage=Usage(
                int(usage.get("prompt_tokens") or 0), int(usage.get("completion_tokens") or 0)
            ),
            model=str(payload.get("model") or self.model),
        )
