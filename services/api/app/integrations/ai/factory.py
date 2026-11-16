"""Escolhe o provedor pela configuração (`AI_PROVIDER`).

`fake` (padrão) funciona sem chave e sem custo. `anthropic` é o recomendado pelo
ADR-012 (ainda “Proposta”: depende da sua conta e chave); o adaptador chega na 4.4,
e até lá escolhê-lo dá `ProviderNotConfigured` na hora de usar — a API sobe normal.
"""

from app.core.config import Settings
from app.integrations.ai.errors import ProviderNotConfigured
from app.integrations.ai.provider import LLMProvider
from app.integrations.ai.providers.fake import FakeProvider


def build_provider(settings: Settings) -> LLMProvider:
    match settings.ai_provider:
        case "fake":
            return FakeProvider()
        case "anthropic":
            if settings.ai_api_key is None:
                raise ProviderNotConfigured("AI_PROVIDER=anthropic sem AI_API_KEY.")
            raise ProviderNotConfigured("O adaptador da Anthropic chega na etapa 4.4.")
    raise ProviderNotConfigured(f"Provedor desconhecido: {settings.ai_provider}")
