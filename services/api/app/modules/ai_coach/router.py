import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.integrations.ai.factory import build_provider
from app.modules.ai_coach.models import AiConversation, AiMessage, ChangeProposal
from app.modules.ai_coach.proposals import ProposalService
from app.modules.ai_coach.schemas import (
    ConversationCreate,
    ConversationDetail,
    ConversationOut,
    MessageCreate,
    MessageOut,
    ProposalOut,
    ReplyOut,
)
from app.modules.ai_coach.service import AiCoachService, ProviderFactory
from app.modules.auth.dependencies import CurrentUser

router = APIRouter(prefix="/ai", tags=["ia"])

DbSession = Annotated[Session, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings)]


def get_provider_factory(settings: AppSettings) -> ProviderFactory:
    """O provedor é montado só na hora da pergunta: um provedor mal configurado vira
    uma resposta amigável (e um registro), não um erro ao subir a API. Os testes
    trocam esta dependência por um `FakeProvider` roteirizado."""
    return lambda: build_provider(settings)


def get_service(
    db: DbSession,
    settings: AppSettings,
    provider: Annotated[ProviderFactory, Depends(get_provider_factory)],
) -> AiCoachService:
    return AiCoachService(db, settings, provider)


Service = Annotated[AiCoachService, Depends(get_service)]


def _conversation(c: AiConversation) -> ConversationOut:
    return ConversationOut(
        id=c.id,
        scope=c.scope,  # type: ignore[arg-type]
        scope_ref=c.scope_ref,
        title=c.title,
        created_at=c.created_at,
        updated_at=c.updated_at,
    )


def proposal_out(p: ChangeProposal) -> ProposalOut:
    target = (p.result or "") if p.status == "accepted" else ""
    template_id = p.payload.get("template_id")
    goal_id = target.removeprefix("goal:") if target.startswith("goal:") else None
    return ProposalOut(
        id=p.id,
        kind=p.kind,
        summary=p.summary,
        details=p.details,
        rationale=p.rationale,
        status=p.status,  # type: ignore[arg-type]
        result=p.result if p.status == "failed" else None,
        template_id=uuid.UUID(template_id) if template_id else None,
        goal_id=uuid.UUID(goal_id) if goal_id else None,
        expires_at=p.expires_at,
        decided_at=p.decided_at,
        created_at=p.created_at,
    )


def _message(m: AiMessage, proposals: list[ChangeProposal] = ()) -> MessageOut:  # type: ignore[assignment]
    return MessageOut(
        id=m.id,
        role=m.role,  # type: ignore[arg-type]
        content=m.content,
        tools_used=m.tools_used,
        proposals=[proposal_out(p) for p in proposals],
        created_at=m.created_at,
    )


def _messages(db: Session, user: CurrentUser, messages: list[AiMessage]) -> list[MessageOut]:
    by_message: dict[uuid.UUID, list[ChangeProposal]] = {}
    for p in ProposalService(db).of_messages(user, [m.id for m in messages]):
        by_message.setdefault(p.message_id, []).append(p)  # type: ignore[arg-type]
    return [_message(m, by_message.get(m.id, [])) for m in messages]


@router.post(
    "/conversations",
    status_code=status.HTTP_201_CREATED,
    summary="Cria uma conversa (geral ou sobre um treino, exercício, músculo, atividade "
    "ou período)",
)
def create_conversation(
    data: ConversationCreate, user: CurrentUser, service: Service
) -> ConversationOut:
    return _conversation(service.create(user, data))


@router.get("/conversations", summary="Lista as conversas, da mais recente para a mais antiga")
def list_conversations(user: CurrentUser, service: Service) -> list[ConversationOut]:
    return [_conversation(c) for c in service.list(user)]


@router.get("/conversations/{conversation_id}", summary="Uma conversa com as mensagens")
def get_conversation(
    conversation_id: uuid.UUID, user: CurrentUser, service: Service, db: DbSession
) -> ConversationDetail:
    conversation = service.get(user, conversation_id)
    return ConversationDetail(
        **_conversation(conversation).model_dump(),
        messages=_messages(db, user, service.messages(conversation)),
    )


@router.delete(
    "/conversations/{conversation_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Apaga a conversa e as mensagens",
)
def delete_conversation(
    conversation_id: uuid.UUID, user: CurrentUser, service: Service
) -> Response:
    service.delete(user, conversation_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/conversations/{conversation_id}/messages",
    summary="Envia uma pergunta e devolve a resposta da IA (exige o consentimento "
    "ai_processing; limites por minuto e por dia)",
)
def ask(
    conversation_id: uuid.UUID,
    data: MessageCreate,
    user: CurrentUser,
    service: Service,
    db: DbSession,
) -> ReplyOut:
    question, answer, simulated = service.ask(user, conversation_id, data.content)
    _, answered = _messages(db, user, [question, answer])
    return ReplyOut(
        question=_message(question),
        answer=answered,
        simulated=simulated,
        remaining_today=service.remaining_today(user),
    )


# --- propostas (4.6, ADR-053) ---


@router.get(
    "/proposals",
    summary="Propostas da IA, da mais recente; filtre por status (ex.: pending)",
)
def list_proposals(
    user: CurrentUser,
    db: DbSession,
    status_filter: Annotated[
        Literal["pending", "accepted", "rejected", "expired", "failed"] | None,
        Query(alias="status"),
    ] = None,
) -> list[ProposalOut]:
    return [proposal_out(p) for p in ProposalService(db).list(user, status_filter)]


@router.post(
    "/proposals/{proposal_id}/accept",
    summary="Confirma a proposta: valida de novo e aplica pelo serviço da ficha ou da meta",
)
def accept_proposal(proposal_id: uuid.UUID, user: CurrentUser, db: DbSession) -> ProposalOut:
    return proposal_out(ProposalService(db).accept(user, proposal_id))


@router.post("/proposals/{proposal_id}/reject", summary="Recusa a proposta; nada muda")
def reject_proposal(proposal_id: uuid.UUID, user: CurrentUser, db: DbSession) -> ProposalOut:
    return proposal_out(ProposalService(db).reject(user, proposal_id))
