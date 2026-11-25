from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Annotated

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


# `fake` e `demo` não saem do servidor; os outros são provedores reais.
AI_PROVIDERS = ("fake", "demo", "groq", "gemini", "anthropic")
LOCAL_PROVIDERS = ("fake", "demo")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
        # Erros de validação sem o valor recebido: uma chave posta na variável errada
        # não aparece no terminal nem nos logs (aconteceu na 4.4).
        hide_input_in_errors=True,
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

    # IA (Fase 4, ADR-011/012). `fake` e `demo` (respostas por regras com os dados
    # reais, ADR-058) funcionam sem chave e sem custo; a chave do provedor real fica
    # só aqui no backend e nunca aparece em logs/repr.
    # Um provedor ou uma lista em ordem de preferência ("groq,gemini"): com cota
    # esgotada ou sobrecarga no primeiro, a pergunta vai ao próximo (ADR-057).
    ai_provider: str = "fake"
    # Chave e modelo de cada provedor. `AI_API_KEY`/`AI_MODEL` valem para o primeiro
    # provedor real da lista quando ele não tem os próprios (compatibilidade, 4.4).
    ai_api_key: SecretStr | None = None
    ai_model: str | None = None
    ai_gemini_api_key: SecretStr | None = None
    ai_gemini_model: str | None = None
    ai_groq_api_key: SecretStr | None = None
    ai_groq_model: str | None = None
    # Chave do Gemini no plano gratuito (ADR-056): o Google pode usar o conteúdo para
    # melhorar os produtos dele. Com isto ligado, o texto livre das limitações (dado
    # de saúde) nunca é enviado, e o app avisa no consentimento.
    ai_free_tier: bool = False
    ai_timeout_s: float = Field(default=30, gt=0, le=120)
    # Limites por pessoa (AI_DESIGN §6): contêm custo e abuso.
    ai_daily_limit: int = Field(default=30, ge=1, le=1000)
    ai_per_minute_limit: int = Field(default=5, ge=1, le=60)
    ai_max_tokens: int = Field(default=1024, ge=64, le=8192)

    @field_validator(
        "ai_api_key", "ai_gemini_api_key", "ai_groq_api_key", "ai_model", mode="before"
    )
    @classmethod
    def _blank_is_none(cls, value: object) -> object:
        """`AI_GROQ_API_KEY=` em branco no .env é o mesmo que não ter a chave."""
        return None if isinstance(value, str) and not value.strip() else value

    @field_validator("ai_provider")
    @classmethod
    def _check_providers(cls, value: str) -> str:
        names = [n.strip() for n in value.split(",") if n.strip()]
        unknown = [n for n in names if n not in AI_PROVIDERS]
        if not names or unknown or len(set(names)) != len(names):
            # Sem repetir o valor: uma chave colada aqui por engano não vai para o erro.
            raise ValueError(
                "AI_PROVIDER deve ser um provedor ou uma lista sem repetição de: "
                + ", ".join(AI_PROVIDERS)
            )
        return ",".join(names)

    @property
    def ai_providers(self) -> tuple[str, ...]:
        return tuple(self.ai_provider.split(","))

    def _first_real(self) -> str | None:
        return next((n for n in self.ai_providers if n not in LOCAL_PROVIDERS), None)

    def ai_key_for(self, name: str) -> SecretStr | None:
        own = getattr(self, f"ai_{name}_api_key", None)
        return own or (self.ai_api_key if name == self._first_real() else None)

    def ai_model_for(self, name: str) -> str | None:
        own = getattr(self, f"ai_{name}_model", None)
        return own or (self.ai_model if name == self._first_real() else None)

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
