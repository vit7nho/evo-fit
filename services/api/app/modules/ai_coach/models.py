"""Conversas com a IA e o registro de cada execução (DATA_MODEL §7, ADR-051).

Só o texto da pergunta e da resposta fica na conversa: os resultados das
ferramentas não são guardados (são consultados de novo quando preciso), e o
registro da execução (`ai_run_logs`) guarda metadados, nunca conteúdo.
"""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import CheckConstraint, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, Timestamps, UUIDPrimaryKey

SCOPES = ("global", "session", "exercise", "muscle", "activity", "period")
ROLES = ("user", "assistant")
OUTCOMES = ("ok", "provider_error", "rate_limited", "invalid_output", "refused")


def _in(column: str, values: tuple[str, ...]) -> str:
    return f"{column} IN ({', '.join(repr(v) for v in values)})"


class AiConversation(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "ai_conversations"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    scope: Mapped[str] = mapped_column(String(16))
    # Referência do modo específico (ex.: {"muscle_id": "lats"}); nula no global.
    scope_ref: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    title: Mapped[str] = mapped_column(String(80))

    __table_args__ = (
        CheckConstraint(_in("scope", SCOPES), name="scope_known"),
        Index("ix_ai_conversations_user_id_updated_at", "user_id", "updated_at"),
    )


class AiMessage(UUIDPrimaryKey, Base):
    __tablename__ = "ai_messages"

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ai_conversations.id", ondelete="CASCADE")
    )
    role: Mapped[str] = mapped_column(String(16))
    content: Mapped[str] = mapped_column(Text)
    # Nomes das ferramentas consultadas para esta resposta (sem argumentos nem dados).
    tools_used: Mapped[list[str]] = mapped_column(JSONB, default=list)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    __table_args__ = (
        CheckConstraint(_in("role", ROLES), name="role_known"),
        Index("ix_ai_messages_conversation_id_created_at", "conversation_id", "created_at"),
    )


class AiRunLog(UUIDPrimaryKey, Base):
    """Uma execução do orquestrador (ou uma recusa pelos limites). Sem conteúdo."""

    __tablename__ = "ai_run_logs"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ai_conversations.id", ondelete="SET NULL")
    )
    provider: Mapped[str] = mapped_column(String(32))
    model: Mapped[str] = mapped_column(String(64))
    prompt_version: Mapped[str] = mapped_column(String(32))
    prompt_hash: Mapped[str] = mapped_column(String(16))
    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer, default=0)
    iterations: Mapped[int] = mapped_column(Integer, default=0)
    # [{"name": "get_workout_history", "ok": true, "duration_ms": 12}, ...]
    tool_calls: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, default=list)
    # Números da resposta que não aparecem nos dados consultados (heurística, §6).
    unverified_numbers: Mapped[int] = mapped_column(Integer, default=0)
    outcome: Mapped[str] = mapped_column(String(16))
    error_code: Mapped[str | None] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    __table_args__ = (
        CheckConstraint(_in("outcome", OUTCOMES), name="outcome_known"),
        Index("ix_ai_run_logs_user_id_created_at", "user_id", "created_at"),
    )


PROPOSAL_KINDS = (
    "template_add_exercise",
    "template_replace_exercise",
    "template_adjust_sets",
    "goal_create",
)
PROPOSAL_STATUSES = ("pending", "accepted", "rejected", "expired", "failed")


class ChangeProposal(UUIDPrimaryKey, Base):
    """Alteração sugerida pela IA (AI_DESIGN §7, ADR-053). Nada muda até a pessoa
    confirmar; ao confirmar, o serviço dono do dado valida tudo de novo."""

    __tablename__ = "change_proposals"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ai_conversations.id", ondelete="SET NULL")
    )
    # A resposta da IA que trouxe a proposta (preenchida quando a resposta é gravada).
    message_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ai_messages.id", ondelete="SET NULL")
    )
    kind: Mapped[str] = mapped_column(String(32))
    # A alteração já validada, no formato da ferramenta.
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    # Impressão digital da ficha quando a proposta foi feita: se a ficha mudar antes da
    # confirmação, a proposta não é aplicada sobre uma versão que a IA não viu.
    base_hash: Mapped[str | None] = mapped_column(String(64))
    summary: Mapped[str] = mapped_column(String(200))
    details: Mapped[list[str]] = mapped_column(JSONB, default=list)
    rationale: Mapped[str] = mapped_column(String(300))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    # O que aconteceu ao decidir (ex.: por que falhou).
    result: Mapped[str | None] = mapped_column(String(300))
    expires_at: Mapped[datetime]
    decided_at: Mapped[datetime | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    __table_args__ = (
        CheckConstraint(_in("kind", PROPOSAL_KINDS), name="kind_known"),
        CheckConstraint(_in("status", PROPOSAL_STATUSES), name="status_known"),
        Index("ix_change_proposals_user_id_status", "user_id", "status"),
        Index("ix_change_proposals_conversation_id", "conversation_id"),
    )
