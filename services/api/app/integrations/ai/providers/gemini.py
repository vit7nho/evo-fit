"""Adaptador do Google Gemini (ADR-056): `generateContent` da Gemini API por REST.

Sem dependência nova: a chamada usa `urllib` da biblioteca padrão, e o transporte é
injetável para os testes (nenhum teste acessa a rede).

Tradução dos tipos neutros (provider.py):
- `user` → papel `user` com texto; `assistant` → papel `model` com o texto e os
  `functionCall` (com o `id` e a `thoughtSignature` devolvidos como vieram — sem a
  assinatura, o Gemini recusa a rodada com 400); `tool` → papel `user` com os
  `functionResponse` (o nome vem do pedido correspondente).
- As ferramentas vão em `parametersJsonSchema` (JSON Schema completo, como o
  Pydantic gera, com `$defs`).
- Consumo: entrada = `promptTokenCount`; saída = `candidatesTokenCount` +
  `thoughtsTokenCount` (o raciocínio também é cobrado como saída).

Erros: 429 → `ProviderRateLimited` (com o `retryDelay` da resposta); 5xx, rede →
`ProviderUnavailable`; tempo esgotado → `ProviderTimeout`; 400/401/403/404 →
`ProviderError` (definitivo); resposta bloqueada, vazia ou chamada malformada →
`InvalidModelOutput`. As mensagens de erro e os logs levam só o código HTTP e o
status do Google — nunca a chave, o corpo do pedido ou o da resposta.

Vários modelos (`AI_GEMINI_MODEL=a,b,c`): no plano gratuito a cota é por modelo
(o `gemini-3.6-flash` deu 20 pedidos por dia) e a sobrecarga (503) é frequente; a
troca de modelo fica em `rotation.py`. Depois da primeira chamada de ferramenta a
pergunta segue no mesmo modelo: a `thoughtSignature` é de quem a gerou.
"""

import json
import logging
import re
import time
import urllib.error
import urllib.request
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
from app.integrations.ai.providers.rotation import (  # noqa: F401  (_EXHAUSTED: testes)
    _EXHAUSTED,
    ModelRotation,
    network_errors,
)

logger = logging.getLogger(__name__)

BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
# Modelos do plano gratuito com chamada de ferramentas verificada em 25/11/2026.
DEFAULT_MODELS = ("gemini-3.6-flash", "gemini-3-flash-preview", "gemini-3.5-flash-lite")
DEFAULT_MODEL = DEFAULT_MODELS[0]
# (status HTTP, corpo já decodificado) — ou exceção de rede/tempo.
Transport = Callable[[str, dict[str, str], bytes, float], tuple[int, bytes]]

_BLOCKED = {"SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "LANGUAGE"}


def urllib_transport(url: str, headers: dict[str, str], body: bytes, timeout_s: float):
    if not url.startswith("https://"):
        raise ValueError("Só HTTPS.")
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")  # noqa: S310
    try:
        with urllib.request.urlopen(request, timeout=timeout_s) as response:  # noqa: S310
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def _retry_after(payload: dict[str, Any]) -> float | None:
    """`retryDelay` ("17s", "0.5s") nos detalhes do erro 429, se houver."""
    for detail in payload.get("error", {}).get("details", []) or []:
        delay = detail.get("retryDelay") if isinstance(detail, dict) else None
        if isinstance(delay, str) and (match := re.fullmatch(r"(\d+(?:\.\d+)?)s", delay)):
            return float(match.group(1))
    return None


def _tool_response(content: str, is_error: bool) -> dict[str, Any]:
    """O `response` do `functionResponse` precisa ser um objeto."""
    try:
        value: Any = json.loads(content)
    except ValueError:
        value = content
    if is_error:
        return {"error": value}
    return value if isinstance(value, dict) else {"result": value}


def to_contents(messages: list[Message]) -> list[dict[str, Any]]:
    names: dict[str, str] = {}
    contents: list[dict[str, Any]] = []
    for message in messages:
        match message.role:
            case "user":
                contents.append({"role": "user", "parts": [{"text": message.content}]})
            case "assistant":
                parts: list[dict[str, Any]] = []
                if message.content.strip():
                    parts.append({"text": message.content})
                for call in message.tool_calls:
                    names[call.id] = call.name
                    part: dict[str, Any] = {
                        "functionCall": {"id": call.id, "name": call.name, "args": call.arguments}
                    }
                    if call.signature:
                        part["thoughtSignature"] = call.signature
                    parts.append(part)
                contents.append({"role": "model", "parts": parts})
            case "tool":
                contents.append(
                    {
                        "role": "user",
                        "parts": [
                            {
                                "functionResponse": {
                                    "id": result.call_id,
                                    "name": names.get(result.call_id, "desconhecida"),
                                    "response": _tool_response(result.content, result.is_error),
                                }
                            }
                            for result in message.tool_results
                        ],
                    }
                )
    return contents


def _uses_thinking_level(model: str) -> bool:
    """`thinkingLevel` existe a partir da geração 3; a 2.5 usa outro parâmetro."""
    return not model.startswith(("gemini-2", "gemma"))


class GeminiProvider(ModelRotation):
    name = "gemini"

    def __init__(
        self,
        api_key: str,
        model: str | None = None,
        *,
        transport: Transport = urllib_transport,
        clock: Callable[[], float] = time.monotonic,
        exhausted: dict[str, float] | None = None,
    ) -> None:
        self._api_key = api_key
        self._transport = transport
        self._init_models(model, DEFAULT_MODELS, clock, exhausted)

    def request_body(
        self, *, system: str, messages: list[Message], tools: list[ToolSpec], max_tokens: int
    ) -> dict[str, Any]:
        generation: dict[str, Any] = {"maxOutputTokens": max_tokens}
        if _uses_thinking_level(self.model):
            # Raciocínio curto: as respostas são consultas a dados, não problemas longos,
            # e o raciocínio conta no limite de saída.
            generation["thinkingConfig"] = {"thinkingLevel": "low"}
        body: dict[str, Any] = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": to_contents(messages),
            "generationConfig": generation,
        }
        if tools:
            body["tools"] = [
                {
                    "functionDeclarations": [
                        {
                            "name": t.name,
                            "description": t.description,
                            "parametersJsonSchema": t.input_schema,
                        }
                        for t in tools
                    ]
                }
            ]
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
        url = f"{BASE_URL}/models/{self.model}:generateContent"
        headers = {"x-goog-api-key": self._api_key, "Content-Type": "application/json"}
        data = json.dumps(body, ensure_ascii=False).encode()
        status, raw = network_errors(
            "Gemini", lambda: self._transport(url, headers, data, timeout_s)
        )

        try:
            payload = json.loads(raw or b"{}")
        except ValueError:
            payload = {}
        if status != 200:
            raise self._error(status, payload if isinstance(payload, dict) else {})
        return self._completion(payload)

    @staticmethod
    def _error(status: int, payload: dict[str, Any]) -> ProviderError:
        google_status = str(payload.get("error", {}).get("status", ""))[:40]
        logger.warning("ai_gemini_http_error", extra={"status": status, "google": google_status})
        message = f"Gemini: HTTP {status} {google_status}".strip()
        if status == 429:
            return ProviderRateLimited(message, retry_after_s=_retry_after(payload))
        if status >= 500:
            return ProviderUnavailable(message)
        return ProviderError(message)

    def _completion(self, payload: dict[str, Any]) -> Completion:
        candidates = payload.get("candidates") or []
        if not candidates:
            reason = payload.get("promptFeedback", {}).get("blockReason", "sem candidatos")
            raise InvalidModelOutput(f"Gemini: pergunta bloqueada ({reason}).")
        candidate = candidates[0]
        finish = candidate.get("finishReason", "STOP")
        if finish in _BLOCKED or finish.startswith("MALFORMED") or finish == "UNEXPECTED_TOOL_CALL":
            raise InvalidModelOutput(f"Gemini: resposta interrompida ({finish}).")

        texts: list[str] = []
        calls: list[ToolCall] = []
        for index, part in enumerate(candidate.get("content", {}).get("parts") or []):
            if part.get("thought"):
                continue  # resumo do raciocínio: não é resposta
            if "functionCall" in part:
                call = part["functionCall"]
                args = call.get("args", {})
                if not isinstance(args, dict) or not call.get("name"):
                    raise InvalidModelOutput("Gemini: chamada de ferramenta malformada.")
                calls.append(
                    ToolCall(
                        id=call.get("id") or f"gemini-{index}",
                        name=call["name"],
                        arguments=args,
                        signature=part.get("thoughtSignature"),
                    )
                )
            elif isinstance(part.get("text"), str):
                texts.append(part["text"])

        usage = payload.get("usageMetadata", {})
        stop: StopReason = (
            "tool_use" if calls else "max_tokens" if finish == "MAX_TOKENS" else "end"
        )
        return Completion(
            text="".join(texts),
            tool_calls=tuple(calls),
            stop_reason=stop,
            usage=Usage(
                int(usage.get("promptTokenCount", 0)),
                int(usage.get("candidatesTokenCount", 0)) + int(usage.get("thoughtsTokenCount", 0)),
            ),
            model=str(payload.get("modelVersion") or self.model),
        )
