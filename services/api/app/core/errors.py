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
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(detail or title)
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
        self.errors = errors or []
        self.headers = headers


class NotFoundError(AppError):
    def __init__(self, detail: str = "Recurso não encontrado.") -> None:
        super().__init__(404, "not_found", "Não encontrado", detail)


class UnauthorizedError(AppError):
    """401 com o cabeçalho exigido pela RFC 6750 para autenticação Bearer."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(
            401, code, "Não autenticado", detail, headers={"WWW-Authenticate": "Bearer"}
        )


class FieldValidationError(AppError):
    """422 gerado por regras do serviço, no mesmo formato da validação do Pydantic."""

    def __init__(self, field: str, message: str) -> None:
        super().__init__(
            422,
            "validation_error",
            "Dados inválidos",
            "Verifique os campos informados.",
            [{"field": field, "message": message}],
        )


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
    return problem_response(
        exc.status, exc.code, exc.title, exc.detail, exc.errors, headers=exc.headers
    )


# Mensagens em PT-BR para os erros de validação mais comuns do Pydantic; os demais
# mantêm a mensagem original. `ctx` traz os limites (min_length, ge, ...).
_VALIDATION_MESSAGES_PT = {
    "missing": "Campo obrigatório.",
    "string_type": "Deve ser um texto.",
    "string_too_short": "Deve ter pelo menos {min_length} caractere(s).",
    "string_too_long": "Deve ter no máximo {max_length} caracteres.",
    "int_type": "Deve ser um número inteiro.",
    "int_parsing": "Deve ser um número inteiro.",
    "float_type": "Deve ser um número.",
    "float_parsing": "Deve ser um número.",
    "bool_type": "Deve ser verdadeiro ou falso.",
    "bool_parsing": "Deve ser verdadeiro ou falso.",
    "greater_than_equal": "Deve ser maior ou igual a {ge}.",
    "less_than_equal": "Deve ser menor ou igual a {le}.",
    "greater_than": "Deve ser maior que {gt}.",
    "less_than": "Deve ser menor que {lt}.",
    "enum": "Valor inválido. Opções: {expected}.",
    "literal_error": "Valor inválido. Opções: {expected}.",
    "uuid_parsing": "Identificador inválido.",
    "json_invalid": "JSON inválido.",
    "model_attributes_type": "Formato inválido.",
    "dict_type": "Formato inválido.",
    "list_type": "Deve ser uma lista.",
    "extra_forbidden": "Campo não permitido.",
}


def _validation_message(error: dict[str, Any]) -> str:
    ctx = error.get("ctx") or {}
    if error["type"] == "value_error" and "error" in ctx:
        # Mensagem escrita por nós em um validador (ValueError).
        return str(ctx["error"])
    template = _VALIDATION_MESSAGES_PT.get(error["type"])
    if template is None:
        return str(error["msg"])
    try:
        return template.format(**ctx)
    except KeyError:
        return str(error["msg"])


async def _validation_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    errors = [
        {"field": _field_path(e["loc"]), "message": _validation_message(e)} for e in exc.errors()
    ]
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
