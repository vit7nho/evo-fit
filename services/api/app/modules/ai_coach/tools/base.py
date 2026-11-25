"""Base das ferramentas da IA (AI_DESIGN §3, ADR-050).

Uma ferramenta é: nome, descrição em português (o modelo lê), um modelo Pydantic de
entrada e uma função que recebe o **contexto do servidor** — a sessão do banco e o
usuário autenticado — e os argumentos já validados. O usuário nunca vem do modelo:
as entradas proíbem campos extras, então um `user_id` nos argumentos é recusado.
"""

import uuid
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy.orm import Session

from app.modules.analytics.service import MAX_DAYS, today
from app.modules.users.models import User

# Máximo de itens numa lista devolvida (AI_DESIGN §3); acima disso, `truncated: true`.
MAX_ITEMS = 30
DEFAULT_DAYS = 30


@dataclass(frozen=True)
class ToolContext:
    """O que o servidor fornece: nunca sai do modelo."""

    db: Session
    user: User
    # A conversa da pergunta (as propostas ficam ligadas a ela); nula fora do chat.
    conversation_id: uuid.UUID | None = None

    @property
    def today(self) -> date:
        return today(self.user)


class ToolInput(BaseModel):
    """Entrada de ferramenta: campos desconhecidos (ex.: `user_id`) são recusados."""

    model_config = ConfigDict(extra="forbid")


class PeriodInput(ToolInput):
    """Período em datas do fuso da pessoa, inclusive. Sem datas: os últimos 30 dias."""

    from_date: date | None = Field(
        default=None, description="Início (AAAA-MM-DD). Padrão: 30 dias antes do fim."
    )
    to_date: date | None = Field(
        default=None, description="Fim, inclusive (AAAA-MM-DD). Padrão: hoje."
    )

    @model_validator(mode="after")
    def _check(self) -> PeriodInput:
        if self.from_date and self.to_date and self.from_date > self.to_date:
            raise ValueError("O início não pode ser depois do fim.")
        if self.from_date and self.to_date and (self.to_date - self.from_date).days + 1 > MAX_DAYS:
            raise ValueError(f"Use um período de até {MAX_DAYS} dias.")
        return self

    def period(self, ctx: ToolContext) -> tuple[date, date]:
        end = self.to_date or ctx.today
        start = self.from_date or end - timedelta(days=DEFAULT_DAYS - 1)
        if start > end:
            raise ToolError("O início não pode ser depois do fim.")
        if (end - start).days + 1 > MAX_DAYS:
            raise ToolError(f"Use um período de até {MAX_DAYS} dias.")
        return start, end


class ToolError(Exception):
    """Erro explicado ao modelo (ex.: treino não encontrado); a conversa continua."""


@dataclass(frozen=True)
class Tool:
    name: str
    description: str
    input_model: type[ToolInput]
    handler: Callable[[ToolContext, Any], dict[str, Any]]

    @property
    def input_schema(self) -> dict[str, Any]:
        return self.input_model.model_json_schema()


def capped(items: Sequence[Any], limit: int = MAX_ITEMS) -> dict[str, Any]:
    """Lista limitada, com o aviso de corte para o modelo não supor que viu tudo."""
    return {"items": list(items[:limit]), "truncated": len(items) > limit}
