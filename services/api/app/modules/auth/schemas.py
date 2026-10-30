import re
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, StringConstraints

# Validação estrutural simples; a confirmação de posse do e-mail fica para depois da v1.
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _normalize_email(value: str) -> str:
    email = value.strip().lower()
    if len(email) > 254 or not _EMAIL_RE.match(email):
        raise ValueError("Informe um e-mail válido.")
    return email


Email = Annotated[str, AfterValidator(_normalize_email)]
# Limite só contra abuso; a política (tamanho mínimo, senhas comuns) é aplicada no serviço,
# para que o login aceite senhas antigas mesmo se a política mudar.
Password = Annotated[str, StringConstraints(min_length=1, max_length=128)]


class _Request(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RegisterRequest(_Request):
    email: Email
    password: Password
    display_name: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=60)
    ]
    accept_terms: bool = Field(
        description="Aceite dos Termos de Uso e da Política de Privacidade (obrigatório)."
    )


class LoginRequest(_Request):
    email: Email
    password: Password


class RefreshRequest(_Request):
    refresh_token: Annotated[str, StringConstraints(min_length=1, max_length=200)]


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"  # noqa: S105 — tipo do token, não um segredo
    expires_in: int = Field(description="Validade do access token, em segundos.")
    refresh_expires_in: int = Field(description="Validade do refresh token, em segundos.")
