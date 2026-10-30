"""Logs em JSON com remoção de campos sensíveis (ver docs/SECURITY_PRIVACY.md)."""

import json
import logging
from datetime import UTC, datetime
from typing import Any

from app.core.request_context import get_request_id

# Campos que nunca podem aparecer em log, mesmo se passados via `extra=`.
SENSITIVE_KEYS = frozenset(
    {
        "password",
        "password_hash",
        "token",
        "access_token",
        "refresh_token",
        "authorization",
        "api_key",
        "secret",
        "notes",
        "limitations_note",
        "content",
    }
)
REDACTED = "[removido]"

# Atributos padrão de LogRecord, para distinguir o que veio de `extra=`.
_RESERVED = frozenset(vars(logging.makeLogRecord({}))) | {"message", "asctime"}


def redact(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            k: REDACTED if str(k).lower() in SENSITIVE_KEYS else redact(v) for k, v in value.items()
        }
    if isinstance(value, list | tuple):
        return [redact(v) for v in value]
    return value


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
            "request_id": get_request_id(),
        }
        extras = {k: v for k, v in vars(record).items() if k not in _RESERVED}
        payload.update(redact(extras))
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())
    # O access log do uvicorn registra a query string, que pode conter dados; desativado.
    logging.getLogger("uvicorn.access").disabled = True
