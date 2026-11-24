"""Conversas com a IA (4.3, ADR-051): entrada, limites, orquestrador e registro.

Ordem de uma pergunta:
1. a conversa precisa ser da pessoa (senão 404, igual a um id inexistente);
2. consentimento `ai_processing` ativo (senão 403);
3. limites por minuto e por dia (senão 429 com `Retry-After`; a recusa é registrada
   como `refused` e não conta para os limites);
4. o orquestrador roda com o histórico recente; falha do provedor vira uma
   mensagem amigável (503, ou 429 se o fornecedor limitou) e fica registrada;
5. pergunta e resposta são gravadas, com o registro da execução (sem conteúdo).
"""

import logging
import time
import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import AppError, FieldValidationError, NotFoundError
from app.integrations.ai.errors import InvalidModelOutput, ProviderError, ProviderRateLimited
from app.integrations.ai.provider import LLMProvider, Message
from app.modules.activities.models import Activity
from app.modules.ai_coach import orchestrator, prompts
from app.modules.ai_coach.context import context_card
from app.modules.ai_coach.models import AiConversation, AiMessage, AiRunLog
from app.modules.ai_coach.schemas import REF_MODELS, ConversationCreate
from app.modules.ai_coach.tools.base import ToolContext
from app.modules.analytics.service import tz
from app.modules.exercises.models import Exercise
from app.modules.sessions.models import WorkoutSession
from app.modules.users.models import ConsentKind, User
from app.modules.users.service import active_consent

logger = logging.getLogger(__name__)

# Mensagens anteriores enviadas ao modelo (só texto de pergunta e resposta).
HISTORY_MESSAGES = 10

ProviderFactory = Callable[[], LLMProvider]

SCOPE_TITLES = {
    "global": "Conversa geral",
    "session": "Sobre um treino",
    "exercise": "Sobre um exercício",
    "muscle": "Sobre um músculo",
    "activity": "Sobre uma atividade",
    "period": "Sobre um período",
}


def _now() -> datetime:
    """Relógio do serviço (separado para os testes controlarem os limites)."""
    return datetime.now(UTC)


class AiConsentRequired(AppError):
    def __init__(self) -> None:
        super().__init__(
            403,
            "consent_required",
            "Consentimento necessário",
            "Para conversar com a IA, autorize o processamento por IA no seu perfil.",
            errors=[{"field": "consent", "message": ConsentKind.AI_PROCESSING.value}],
        )


class AiLimitReached(AppError):
    def __init__(self, code: str, detail: str, retry_after_s: int) -> None:
        super().__init__(
            429,
            code,
            "Limite de perguntas",
            detail,
            headers={"Retry-After": str(max(1, retry_after_s))},
        )


class AiFailed(AppError):
    def __init__(self, error: ProviderError) -> None:
        rate_limited = isinstance(error, ProviderRateLimited)
        super().__init__(
            429 if rate_limited else 503,
            error.code,
            "IA indisponível",
            error.user_message,
            headers={"Retry-After": "30"} if rate_limited else None,
        )


class AiCoachService:
    def __init__(self, db: Session, settings: Settings, provider: ProviderFactory) -> None:
        self.db = db
        self.settings = settings
        self.provider = provider

    # --- conversas ---

    def create(self, user: User, data: ConversationCreate) -> AiConversation:
        ref = self._validated_ref(user, data.scope, data.scope_ref)
        now = _now()
        conversation = AiConversation(
            user_id=user.id,
            scope=data.scope,
            scope_ref=ref,
            title=data.title or SCOPE_TITLES[data.scope],
            created_at=now,
            updated_at=now,
        )
        self.db.add(conversation)
        self.db.commit()
        return conversation

    def list(self, user: User) -> list[AiConversation]:
        return list(
            self.db.scalars(
                select(AiConversation)
                .where(AiConversation.user_id == user.id)
                .order_by(AiConversation.updated_at.desc(), AiConversation.id.desc())
            )
        )

    def get(self, user: User, conversation_id: uuid.UUID) -> AiConversation:
        conversation = self.db.scalar(
            select(AiConversation).where(
                AiConversation.id == conversation_id, AiConversation.user_id == user.id
            )
        )
        if conversation is None:
            raise NotFoundError("Conversa não encontrada.")
        return conversation

    def messages(self, conversation: AiConversation) -> list[AiMessage]:
        return list(
            self.db.scalars(
                select(AiMessage)
                .where(AiMessage.conversation_id == conversation.id)
                .order_by(AiMessage.created_at, AiMessage.id)
            )
        )

    def delete(self, user: User, conversation_id: uuid.UUID) -> None:
        self.db.delete(self.get(user, conversation_id))
        self.db.commit()

    def _validated_ref(
        self, user: User, scope: str, ref: dict[str, Any] | None
    ) -> dict[str, Any] | None:
        if scope == "global":
            if ref:
                raise FieldValidationError("scope_ref", "A conversa geral não tem referência.")
            return None
        if not ref:
            raise FieldValidationError("scope_ref", "Informe a referência do modo específico.")
        try:
            parsed = REF_MODELS[scope].model_validate(ref)
        except ValidationError as error:
            first = error.errors()[0]
            raise FieldValidationError(
                "scope_ref", str(first["msg"]).removeprefix("Value error, ")
            ) from None
        data = parsed.model_dump(mode="json", exclude_none=True)
        # O id vem do cliente: só vale se o registro for da pessoa (ou do catálogo).
        owned = {
            "session": lambda: self.db.scalar(
                select(WorkoutSession.id).where(
                    WorkoutSession.id == data["session_id"], WorkoutSession.user_id == user.id
                )
            ),
            "activity": lambda: self.db.scalar(
                select(Activity.id).where(
                    Activity.id == data["activity_id"], Activity.user_id == user.id
                )
            ),
            "exercise": lambda: self.db.scalar(
                select(Exercise.id).where(
                    Exercise.id == data["exercise_id"],
                    (Exercise.owner_user_id.is_(None)) | (Exercise.owner_user_id == user.id),
                )
            ),
        }
        if scope in owned and owned[scope]() is None:
            raise FieldValidationError("scope_ref", "Registro não encontrado.")
        return data

    # --- perguntas ---

    def _count_since(self, user: User, since: datetime) -> int:
        return (
            self.db.scalar(
                select(func.count())
                .select_from(AiRunLog)
                .where(
                    AiRunLog.user_id == user.id,
                    AiRunLog.created_at >= since,
                    AiRunLog.outcome != "refused",
                )
            )
            or 0
        )

    def _start_of_day(self, user: User, now: datetime) -> datetime:
        local = now.astimezone(tz(user))
        return local.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(UTC)

    def remaining_today(self, user: User) -> int:
        now = _now()
        used = self._count_since(user, self._start_of_day(user, now))
        return max(0, self.settings.ai_daily_limit - used)

    def _check_limits(self, user: User, conversation: AiConversation, now: datetime) -> None:
        if self._count_since(user, now - timedelta(minutes=1)) >= self.settings.ai_per_minute_limit:
            self._refuse(user, conversation, "ai_per_minute_limit")
            raise AiLimitReached(
                "ai_per_minute_limit",
                "Muitas perguntas em sequência. Aguarde um minuto e tente de novo.",
                60,
            )
        start = self._start_of_day(user, now)
        if self._count_since(user, start) >= self.settings.ai_daily_limit:
            self._refuse(user, conversation, "ai_daily_limit")
            tomorrow = start + timedelta(days=1)
            raise AiLimitReached(
                "ai_daily_limit",
                f"Você chegou ao limite de {self.settings.ai_daily_limit} perguntas por dia. "
                "Volte amanhã.",
                int((tomorrow - now).total_seconds()),
            )

    def _log(self, user: User, conversation: AiConversation, **fields: Any) -> None:
        prompt = prompts.load()
        values: dict[str, Any] = {
            "provider": self.settings.ai_provider,
            "model": "",
            "input_tokens": 0,
            "output_tokens": 0,
            "latency_ms": 0,
            "iterations": 0,
            "tool_calls": [],
            "unverified_numbers": 0,
            "error_code": None,
        } | fields
        self.db.add(
            AiRunLog(
                user_id=user.id,
                conversation_id=conversation.id,
                prompt_version=prompt.version,
                prompt_hash=prompt.hash,
                created_at=fields.get("created_at", _now()),
                **{k: v for k, v in values.items() if k != "created_at"},
            )
        )
        logger.info(
            "ai_run",
            extra={
                "outcome": values["outcome"],
                "error_code": values["error_code"],
                "iterations": values["iterations"],
                "tool_calls": len(values["tool_calls"]),
                "latency_ms": values["latency_ms"],
                "unverified_numbers": values["unverified_numbers"],
            },
        )

    def _refuse(self, user: User, conversation: AiConversation, code: str) -> None:
        self._log(user, conversation, outcome="refused", error_code=code)
        self.db.commit()

    def ask(
        self, user: User, conversation_id: uuid.UUID, question: str
    ) -> tuple[AiMessage, AiMessage, bool]:
        conversation = self.get(user, conversation_id)
        if active_consent(self.db, user.id, ConsentKind.AI_PROCESSING) is None:
            raise AiConsentRequired()
        now = _now()
        self._check_limits(user, conversation, now)

        previous = self.messages(conversation)[-HISTORY_MESSAGES:]
        # O histórico começa sempre numa pergunta (exigência comum dos provedores).
        while previous and previous[0].role != "user":
            previous.pop(0)
        history = [Message(m.role, content=m.content) for m in previous]  # type: ignore[arg-type]
        prompt = prompts.load()
        system = "\n\n".join(
            [
                prompt.text,
                context_card(
                    now.astimezone(tz(user)).date(),
                    str(tz(user)),
                    conversation.scope,
                    conversation.scope_ref,
                ),
            ]
        )

        state = orchestrator.RunState()
        started = time.perf_counter()
        provider_name = self.settings.ai_provider
        try:
            provider = self.provider()
            provider_name = provider.name
            result = orchestrator.run(
                provider,
                ToolContext(self.db, user),
                system=system,
                history=history,
                question=question,
                max_tokens=self.settings.ai_max_tokens,
                timeout_s=self.settings.ai_timeout_s,
                state=state,
            )
        except ProviderError as error:
            # A pergunta não é gravada: a conversa fica como estava e dá para repetir.
            outcome = (
                "rate_limited"
                if isinstance(error, ProviderRateLimited)
                else "invalid_output"
                if isinstance(error, InvalidModelOutput)
                else "provider_error"
            )
            self._log(
                user,
                conversation,
                provider=provider_name,
                model=state.model,
                input_tokens=state.usage.input_tokens,
                output_tokens=state.usage.output_tokens,
                latency_ms=round((time.perf_counter() - started) * 1000),
                iterations=state.iterations,
                tool_calls=[t.as_log() for t in state.tools],
                outcome=outcome,
                error_code=error.code,
                created_at=now,
            )
            self.db.commit()
            raise AiFailed(error) from None

        asked = AiMessage(
            conversation_id=conversation.id,
            role="user",
            content=question,
            tools_used=[],
            created_at=now,
        )
        answered = AiMessage(
            conversation_id=conversation.id,
            role="assistant",
            content=result.text,
            tools_used=result.tools_used,
            created_at=now + timedelta(microseconds=1),
        )
        self.db.add_all([asked, answered])
        conversation.updated_at = now
        if (
            not previous
            and conversation.scope == "global"
            and conversation.title == SCOPE_TITLES["global"]
        ):
            conversation.title = _title_from(question)
        self._log(
            user,
            conversation,
            provider=provider_name,
            model=result.model,
            input_tokens=result.usage.input_tokens,
            output_tokens=result.usage.output_tokens,
            latency_ms=round((time.perf_counter() - started) * 1000),
            iterations=result.iterations,
            tool_calls=[t.as_log() for t in result.tools],
            unverified_numbers=len(result.unverified),
            outcome="ok",
            created_at=now,
        )
        self.db.commit()
        return asked, answered, provider_name == "fake"


def _title_from(question: str, limit: int = 60) -> str:
    text = " ".join(question.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"
