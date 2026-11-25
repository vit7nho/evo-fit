import uuid
from datetime import date, datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.modules.exercises import catalog

Scope = Literal["global", "session", "exercise", "muscle", "activity", "period"]

MAX_QUESTION_CHARS = 2000
Question = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=MAX_QUESTION_CHARS)
]


class _Closed(BaseModel):
    model_config = ConfigDict(extra="forbid")


class SessionRef(_Closed):
    session_id: uuid.UUID


class ExerciseRef(_Closed):
    exercise_id: uuid.UUID


class ActivityRef(_Closed):
    activity_id: uuid.UUID


class PeriodRef(_Closed):
    from_date: date
    to_date: date

    @model_validator(mode="after")
    def _order(self) -> PeriodRef:
        if self.from_date > self.to_date:
            raise ValueError("O início não pode ser depois do fim.")
        if (self.to_date - self.from_date).days + 1 > 366:
            raise ValueError("Use um período de até 366 dias.")
        return self


class MuscleRef(_Closed):
    muscle_id: str
    from_date: date | None = None
    to_date: date | None = None

    @model_validator(mode="after")
    def _known(self) -> MuscleRef:
        if self.muscle_id not in catalog.MUSCLE_NAMES:
            raise ValueError("Músculo desconhecido.")
        if (self.from_date is None) != (self.to_date is None):
            raise ValueError("Informe o início e o fim do período, ou nenhum dos dois.")
        if self.from_date and self.to_date:
            PeriodRef(from_date=self.from_date, to_date=self.to_date)
        return self


REF_MODELS: dict[str, type[_Closed]] = {
    "session": SessionRef,
    "exercise": ExerciseRef,
    "activity": ActivityRef,
    "period": PeriodRef,
    "muscle": MuscleRef,
}


class ConversationCreate(_Closed):
    scope: Scope = "global"
    scope_ref: dict[str, Any] | None = None
    title: Annotated[str, StringConstraints(strip_whitespace=True, max_length=80)] | None = None


class MessageCreate(_Closed):
    content: Question


class ProposalOut(BaseModel):
    id: uuid.UUID
    kind: str
    summary: str
    details: list[str]
    rationale: str
    status: Literal["pending", "accepted", "rejected", "expired", "failed"]
    # Por que falhou; nulo nos outros casos.
    result: str | None
    # A ficha ou a meta afetada, para o app abrir depois de aplicar.
    template_id: uuid.UUID | None
    goal_id: uuid.UUID | None
    expires_at: datetime
    decided_at: datetime | None
    created_at: datetime


class MessageOut(BaseModel):
    id: uuid.UUID
    role: Literal["user", "assistant"]
    content: str
    tools_used: list[str]
    # Propostas que esta resposta trouxe (só nas respostas da IA).
    proposals: list[ProposalOut] = []
    created_at: datetime


class ConversationOut(BaseModel):
    id: uuid.UUID
    scope: Scope
    scope_ref: dict[str, Any] | None
    title: str
    created_at: datetime
    updated_at: datetime


class ConversationDetail(ConversationOut):
    messages: list[MessageOut]


class ReplyOut(BaseModel):
    question: MessageOut
    answer: MessageOut
    # true quando o servidor usa o provedor simulado (sem IA de verdade).
    simulated: bool
    # true quando quem respondeu foi o modo demonstração (regras, ADR-058).
    demo: bool = False
    # Perguntas que ainda cabem hoje (no fuso da pessoa).
    remaining_today: int = Field(ge=0)


class ProviderInfo(BaseModel):
    """Quem processa as perguntas (para o texto do consentimento nomear o operador)."""

    provider: str
    label: str
    # Empresas que podem receber as perguntas, na ordem de uso (vazia sem IA real).
    companies: list[str]
    # Das empresas, as que podem usar o conteúdo para melhorar os produtos (plano
    # gratuito do Gemini).
    content_used_by: list[str]
    free_tier: bool
    # Modo demonstração (ADR-058): respostas por regras, montadas no próprio servidor.
    demo: bool = False
    international_transfer: bool
