"""Formato único de erro da API (RFC 9457, application/problem+json)."""

from http import HTTPStatus
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.request_context import get_request_id

PROBLEM_MEDIA_TYPE = "application/problem+json"
_TYPE_BASE = "https://evofit.local/errors/"


class AppError(Exception):
    """Erro de negócio com status e código estáveis, lançado pelos serviços."""

    def __init__(
        self,
        status: int,
        code: str,
        title: str,
        detail: str | None = None,
        errors: list[dict[str, str]] | None = None,
    ) -> None:
        super().__init__(detail or title)
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
        self.errors = errors or []


class NotFoundError(AppError):
    def __init__(self, detail: str = "Recurso não encontrado.") -> None:
        super().__init__(404, "not_found", "Não encontrado", detail)


def problem_response(
    status: int,
    code: str,
    title: str,
    detail: str | None = None,
    errors: list[dict[str, str]] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    body: dict[str, Any] = {
        "type": _TYPE_BASE + code.replace("_", "-"),
        "title": title,
        "status": status,
        "code": code,
        "detail": detail,
        "errors": errors or [],
        "request_id": get_request_id(),
    }
    return JSONResponse(body, status_code=status, media_type=PROBLEM_MEDIA_TYPE, headers=headers)


def _field_path(loc: tuple[int | str, ...]) -> str:
    # Remove o prefixo "body"/"query"/"path" para que o cliente receba só o nome do campo.
    parts = [str(p) for p in loc]
    if parts and parts[0] in {"body", "query", "path", "header"}:
        parts = parts[1:]
    return ".".join(parts) or "__root__"


def internal_error_response() -> JSONResponse:
    return problem_response(
        500, "internal_error", "Erro interno", "Ocorreu um erro inesperado. Tente novamente."
    )


async def _app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return problem_response(exc.status, exc.code, exc.title, exc.detail, exc.errors)


async def _validation_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    errors = [{"field": _field_path(e["loc"]), "message": e["msg"]} for e in exc.errors()]
    return problem_response(
        422, "validation_error", "Dados inválidos", "Verifique os campos informados.", errors
    )


# Títulos em PT-BR para os erros HTTP que o próprio framework gera (rota inexistente etc.).
_HTTP_TITLES_PT = {
    400: "Requisição inválida",
    401: "Não autenticado",
    403: "Acesso negado",
    404: "Não encontrado",
    405: "Método não permitido",
    409: "Conflito",
    413: "Conteúdo muito grande",
    415: "Tipo de conteúdo não suportado",
    429: "Muitas requisições",
}


async def _http_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    phrase = HTTPStatus(exc.status_code).phrase
    code = phrase.lower().replace(" ", "_").replace("-", "_")
    title = _HTTP_TITLES_PT.get(exc.status_code, phrase)
    # O detalhe padrão do Starlette é a própria frase em inglês; só repassa detalhes próprios.
    detail = exc.detail if isinstance(exc.detail, str) and exc.detail != phrase else None
    return problem_response(exc.status_code, code, title, detail, headers=exc.headers)


def register_error_handlers(app: FastAPI) -> None:
    # Exceções não tratadas são convertidas em RequestContextMiddleware (app.core.middleware).
    app.add_exception_handler(AppError, _app_error_handler)  # type: ignore[arg-type]
    app.add_exception_handler(RequestValidationError, _validation_handler)  # type: ignore[arg-type]
    app.add_exception_handler(StarletteHTTPException, _http_handler)  # type: ignore[arg-type]
