import logging
import re
import uuid

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.errors import internal_error_response
from app.core.request_context import reset_request_id, set_request_id

logger = logging.getLogger(__name__)

REQUEST_ID_HEADER = "X-Request-ID"
# Aceita o ID enviado pelo cliente só se for curto e seguro para logs.
_SAFE_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


class RequestContextMiddleware:
    """Middleware ASGI mais externo da aplicação.

    Define o request_id e converte exceções não tratadas em problem+json. Isso precisa ficar
    aqui: o handler genérico do Starlette roda fora dos middlewares, quando o request_id já
    não existe mais.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming = dict(scope["headers"]).get(REQUEST_ID_HEADER.lower().encode())
        candidate = incoming.decode("latin-1") if incoming else ""
        request_id = candidate if _SAFE_ID.match(candidate) else uuid.uuid4().hex
        token = set_request_id(request_id)
        response_started = False

        async def send_with_id(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
                message.setdefault("headers", []).append(
                    (REQUEST_ID_HEADER.lower().encode(), request_id.encode())
                )
            await send(message)

        try:
            await self.app(scope, receive, send_with_id)
        except Exception:
            # Nunca devolve stack trace ao cliente; o log mantém o request_id para rastrear.
            logger.exception("unhandled_error")
            if response_started:
                raise
            await internal_error_response()(scope, receive, send_with_id)
        finally:
            reset_request_id(token)
