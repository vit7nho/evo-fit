"""Direitos do titular (LGPD art. 18, 5.6, ADR-063): exportação e exclusão da conta.

- **Exportação:** um JSON com tudo o que é da pessoa, tabela por tabela (portável,
  legível por máquina). Ficam de fora só o hash da senha e os tokens de sessão —
  credenciais, não dados pessoais úteis — e os catálogos, que são de todos.
- **Exclusão:** física e em cascata (todas as tabelas apontam para `users` com
  `ON DELETE CASCADE`), depois de conferir a senha. O log guarda só o id.
"""

import enum
import logging
import uuid
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import Table, or_, select
from sqlalchemy.orm import Session

from app.core.errors import FieldValidationError
from app.db.base import Base
from app.modules.auth import passwords, rate_limit
from app.modules.auth.rate_limit import RateLimiter
from app.modules.users.models import User

logger = logging.getLogger(__name__)

EXPORT_FORMAT = "evofit-export"
EXPORT_VERSION = 1

# O que pertence à pessoa, na ordem em que aparece no arquivo: (tabela, regra). A regra
# é a coluna que aponta para `users` (str) ou as ligações com tabelas já exportadas
# ((coluna, tabela-mãe), ...) — basta uma bater. Tabela nova com dados da pessoa
# precisa entrar aqui (test_export_covers_every_table confere).
EXPORT_PLAN: tuple[tuple[str, str | tuple[tuple[str, str], ...]], ...] = (
    ("user_profiles", "user_id"),
    ("user_consents", "user_id"),
    ("goals", "user_id"),
    ("exercises", "owner_user_id"),
    ("exercise_muscles", (("exercise_id", "exercises"),)),
    ("workout_templates", "user_id"),
    ("activities", "user_id"),
    ("endurance_details", (("activity_id", "activities"),)),
    ("cycling_details", (("activity_id", "activities"),)),
    ("swim_details", (("activity_id", "activities"),)),
    ("workout_sessions", "user_id"),
    ("exercise_groups", (("template_id", "workout_templates"), ("session_id", "workout_sessions"))),
    ("template_items", (("template_id", "workout_templates"),)),
    ("session_exercises", (("session_id", "workout_sessions"),)),
    ("set_entries", (("session_exercise_id", "session_exercises"),)),
    ("training_plans", "user_id"),
    ("plan_sessions", (("plan_id", "training_plans"),)),
    ("foods", "owner_user_id"),
    ("meals", "user_id"),
    ("meal_items", (("meal_id", "meals"),)),
    ("nutrition_targets", "user_id"),
    ("body_measurements", "user_id"),
    ("ai_conversations", "user_id"),
    ("ai_messages", (("conversation_id", "ai_conversations"),)),
    ("change_proposals", "user_id"),
    ("ai_run_logs", "user_id"),
)
# Ficam de fora de propósito: credenciais e catálogos de todos.
NOT_EXPORTED = {"users", "refresh_tokens", "muscle_groups", "stimulus_methodologies"}
HIDDEN_COLUMNS = {"password_hash", "token_hash"}


def _value(value: Any) -> Any:
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, enum.Enum):
        return value.value
    return value


def _rows(db: Session, table: Table, condition) -> list[dict[str, Any]]:
    columns = [c for c in table.columns if c.name not in HIDDEN_COLUMNS]
    query = select(*columns).where(condition)
    if "id" in table.c:
        query = query.order_by(table.c.id)
    return [{k: _value(v) for k, v in row._mapping.items()} for row in db.execute(query)]


def export_account(db: Session, user: User) -> dict[str, Any]:
    tables = Base.metadata.tables
    data: dict[str, list[dict[str, Any]]] = {}
    ids: dict[str, list[Any]] = {}
    for name, rule in EXPORT_PLAN:
        table = tables[name]
        if isinstance(rule, str):
            condition = table.c[rule] == user.id
        else:
            links = [table.c[col].in_(ids[parent]) for col, parent in rule if ids[parent]]
            if not links:
                data[name] = []
                ids[name] = []
                continue
            condition = or_(*links)
        rows = _rows(db, table, condition)
        data[name] = rows
        ids[name] = [uuid.UUID(r["id"]) for r in rows if "id" in r]
    account = _rows(db, tables["users"], tables["users"].c.id == user.id)[0]
    logger.info("account_exported", extra={"user_id": str(user.id)})
    return {
        "format": EXPORT_FORMAT,
        "version": EXPORT_VERSION,
        "exported_at": datetime.now(UTC).isoformat(),
        "notice": (
            "Todos os seus dados no EvoFit, tabela por tabela. Ficam de fora o hash da "
            "senha e os tokens de sessão. Os exercícios e alimentos do catálogo, que são "
            "de todos, aparecem só pelo id."
        ),
        "account": account,
        "data": data,
    }


def delete_account(db: Session, user: User, password: str, limiter: RateLimiter) -> None:
    """Confere a senha (com limite de erros, como o login) e apaga tudo da pessoa."""
    key = f"delete_account:user:{user.id}"
    limiter.check(key, rate_limit.LOGIN_FAILURES_PER_EMAIL)
    if not passwords.verify_password(user.password_hash, password):
        limiter.record(key, rate_limit.LOGIN_FAILURES_PER_EMAIL)
        raise FieldValidationError("password", "Senha incorreta.")
    limiter.reset(key)
    user_id = str(user.id)
    db.delete(user)
    db.commit()
    # Só o id (pseudônimo): o e-mail e o resto já não existem.
    logger.info("account_deleted", extra={"user_id": user_id})
