"""Catálogo e executor das ferramentas de leitura (4.2).

`execute` é o único caminho do pedido do modelo até os dados: valida os argumentos,
roda a ferramenta com o usuário autenticado e devolve um `ToolResult` em JSON.
Argumentos inválidos, ferramenta desconhecida ou registro não encontrado voltam ao
modelo como erro explicado (ele pode corrigir e tentar de novo); falhas inesperadas
viram uma mensagem genérica, sem detalhe interno. Os logs registram a ferramenta, o
resultado e o tempo — nunca os argumentos nem o conteúdo.
"""

import json
import logging
import time
from datetime import date, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from pydantic import ValidationError

from app.core.errors import AppError
from app.integrations.ai.provider import ToolCall, ToolResult, ToolSpec
from app.modules.ai_coach.tools import activities, analytics, goals, profile, workouts
from app.modules.ai_coach.tools.base import Tool, ToolContext, ToolError

logger = logging.getLogger(__name__)

TOOLS: dict[str, Tool] = {
    tool.name: tool
    for tool in (
        *profile.TOOLS,
        *goals.TOOLS,
        *workouts.TOOLS,
        *analytics.TOOLS,
        *activities.TOOLS,
    )
}


def specs(names: list[str] | None = None) -> list[ToolSpec]:
    """As ferramentas oferecidas ao modelo (todas, ou só as pedidas)."""
    chosen = [TOOLS[n] for n in names] if names is not None else list(TOOLS.values())
    return [ToolSpec(t.name, t.description, t.input_schema) for t in chosen]


def _json_default(value: Any) -> Any:
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, UUID | Decimal):
        return str(value)
    raise TypeError(f"Tipo não serializável: {type(value).__name__}")


def _dump(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, default=_json_default, separators=(",", ":"))


def _error(call: ToolCall, message: str) -> ToolResult:
    return ToolResult(call.id, _dump({"error": message}), is_error=True)


def _validation_message(error: ValidationError) -> str:
    parts = []
    for item in error.errors():
        field = ".".join(str(p) for p in item["loc"]) or "entrada"
        if item["type"] == "extra_forbidden":
            parts.append(f"{field}: campo não aceito")
        else:
            parts.append(f"{field}: {item['msg']}")
    return "Argumentos inválidos — " + "; ".join(parts)


def execute(ctx: ToolContext, call: ToolCall) -> ToolResult:
    started = time.perf_counter()
    tool = TOOLS.get(call.name)
    outcome = "ok"
    try:
        if tool is None:
            outcome = "unknown_tool"
            return _error(call, f"Ferramenta desconhecida: {call.name}.")
        try:
            args = tool.input_model.model_validate(call.arguments)
        except ValidationError as error:
            outcome = "invalid_arguments"
            return _error(call, _validation_message(error))
        try:
            return ToolResult(call.id, _dump(tool.handler(ctx, args)))
        except ToolError as error:
            outcome = "tool_error"
            return _error(call, str(error))
        except AppError as error:
            # Mesmas regras da API (período longo, registro de outra pessoa...).
            outcome = "tool_error"
            fields = "; ".join(e["message"] for e in error.errors if e.get("message"))
            return _error(call, fields or error.detail or error.title)
        except Exception:
            outcome = "failed"
            logger.exception("ai_tool_failed", extra={"tool": call.name})
            return _error(call, "Falha ao consultar os dados. Tente outra consulta.")
    finally:
        logger.info(
            "ai_tool_executed",
            extra={
                "tool": call.name if tool else "unknown",
                "outcome": outcome,
                "duration_ms": round((time.perf_counter() - started) * 1000),
            },
        )
