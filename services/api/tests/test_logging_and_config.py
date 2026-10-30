import json
import logging

import pytest

from app.core.config import Settings
from app.core.logging import REDACTED, JsonFormatter, redact


def test_redact_removes_sensitive_keys_recursively() -> None:
    data = {
        "email_domain": "example.com",
        "Password": "segredo",
        "nested": {"refresh_token": "abc", "items": [{"limitations_note": "dor no joelho"}]},
    }
    assert redact(data) == {
        "email_domain": "example.com",
        "Password": REDACTED,
        "nested": {"refresh_token": REDACTED, "items": [{"limitations_note": REDACTED}]},
    }


def test_json_formatter_redacts_extra_fields() -> None:
    record = logging.makeLogRecord(
        {"msg": "login_failed", "levelname": "WARNING", "name": "auth", "password": "123456"}
    )
    line = json.loads(JsonFormatter().format(record))
    assert line["msg"] == "login_failed"
    assert line["password"] == REDACTED
    assert "123456" not in json.dumps(line)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("http://localhost:3000", ["http://localhost:3000"]),
        (" http://a.test , http://b.test ,", ["http://a.test", "http://b.test"]),
        ("", []),
    ],
)
def test_cors_origins_are_parsed_from_comma_separated_env(
    monkeypatch: pytest.MonkeyPatch, raw: str, expected: list[str]
) -> None:
    monkeypatch.setenv("CORS_ORIGINS", raw)
    assert Settings(_env_file=None).cors_origins == expected
