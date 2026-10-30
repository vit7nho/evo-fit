from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Annotated

from pydantic import field_validator
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
    return Settings()  # type: ignore[call-arg]  # database_url vem do ambiente
