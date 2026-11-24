from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Annotated, Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

# .env na raiz do monorepo (evofit/.env); variáveis de ambiente têm precedência.
# No container o arquivo não existe (a árvore é mais rasa) e só o ambiente é usado.
_PARENTS = Path(__file__).resolve().parents
_ENV_FILE = _PARENTS[4] / ".env" if len(_PARENTS) > 4 else None


class Environment(StrEnum):
    DEVELOPMENT = "development"
    TEST = "test"
    PRODUCTION = "production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "EvoFit"
    app_env: Environment = Environment.DEVELOPMENT
    log_level: str = "INFO"
    database_url: str
    cors_origins: Annotated[list[str], NoDecode] = []

    # Autenticação (ADR-005). O segredo vem só do ambiente e nunca aparece em logs/repr.
    jwt_secret: SecretStr = Field(min_length=32)
    access_token_ttl_minutes: int = Field(default=15, ge=1, le=60)
    refresh_token_ttl_days: int = Field(default=30, ge=1, le=90)
    # Versão vigente dos Termos de Uso e da Política de Privacidade aceitos no cadastro.
    terms_version: str = "2026-10"

    # IA (Fase 4, ADR-011/012). `fake` funciona sem chave e sem custo; a chave do
    # provedor real fica só aqui no backend e nunca aparece em logs/repr.
    ai_provider: Literal["fake", "anthropic"] = "fake"
    ai_api_key: SecretStr | None = None
    ai_model: str | None = None
    ai_timeout_s: float = Field(default=30, gt=0, le=120)
    # Limites por pessoa (AI_DESIGN §6): contêm custo e abuso.
    ai_daily_limit: int = Field(default=30, ge=1, le=1000)
    ai_per_minute_limit: int = Field(default=5, ge=1, le=60)
    ai_max_tokens: int = Field(default=1024, ge=64, le=8192)

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @property
    def is_production(self) -> bool:
        return self.app_env is Environment.PRODUCTION


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]  # database_url e jwt_secret vêm do ambiente
