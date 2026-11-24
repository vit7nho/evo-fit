import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.integrations.ai.factory import build_provider
from app.modules.ai_coach.models import AiConversation, AiMessage
from app.modules.ai_coach.schemas import (
    ConversationCreate,
    ConversationDetail,
    ConversationOut,
    MessageCreate,
    MessageOut,
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


def _message(m: AiMessage) -> MessageOut:
    return MessageOut(
        id=m.id,
        role=m.role,  # type: ignore[arg-type]
        content=m.content,
        tools_used=m.tools_used,
        created_at=m.created_at,
    )


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
    conversation_id: uuid.UUID, user: CurrentUser, service: Service
) -> ConversationDetail:
    conversation = service.get(user, conversation_id)
    return ConversationDetail(
        **_conversation(conversation).model_dump(),
        messages=[_message(m) for m in service.messages(conversation)],
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
    conversation_id: uuid.UUID, data: MessageCreate, user: CurrentUser, service: Service
) -> ReplyOut:
    question, answer, simulated = service.ask(user, conversation_id, data.content)
    return ReplyOut(
        question=_message(question),
        answer=_message(answer),
        simulated=simulated,
        remaining_today=service.remaining_today(user),
    )
