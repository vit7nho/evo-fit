"""Escolhe o provedor pela configuração (`AI_PROVIDER`).

`fake` (padrão) funciona sem chave e sem custo; `demo` (ADR-058) também, e responde
por regras com os dados reais — sozinho ou no fim da lista, quando a cota acaba.
`groq` e `gemini` são os provedores reais (ADR-056/057), cada um com a própria
chave (`AI_GROQ_API_KEY`, `AI_GEMINI_API_KEY`). Uma lista (`groq,gemini`) vira um
`FallbackProvider`: os provedores sem chave ficam de fora (com aviso no log) e, se
nenhum sobrar, dá
`ProviderNotConfigured` na hora de usar — a API sobe normal. `anthropic` continua
previsto, sem adaptador.
"""

import logging

from app.core.config import Settings
from app.integrations.ai.errors import ProviderNotConfigured
from app.integrations.ai.fallback import FallbackProvider
from app.integrations.ai.provider import LLMProvider
from app.integrations.ai.providers.demo import DemoProvider
from app.integrations.ai.providers.fake import FakeProvider
from app.integrations.ai.providers.gemini import GeminiProvider
from app.integrations.ai.providers.groq import GroqProvider

logger = logging.getLogger(__name__)

_KEY_NAMES = {"gemini": "AI_GEMINI_API_KEY", "groq": "AI_GROQ_API_KEY"}


def _build_one(settings: Settings, name: str) -> LLMProvider:
    if name == "fake":
        return FakeProvider()
    if name == "demo":
        return DemoProvider()
    if name == "anthropic":
        raise ProviderNotConfigured("Sem adaptador da Anthropic: use groq ou gemini.")
    key = settings.ai_key_for(name)
    if key is None:
        raise ProviderNotConfigured(f"AI_PROVIDER={name} sem {_KEY_NAMES[name]} (ou AI_API_KEY).")
    model = settings.ai_model_for(name)
    if name == "gemini":
        return GeminiProvider(key.get_secret_value(), model)
    return GroqProvider(key.get_secret_value(), model)


def build_provider(settings: Settings) -> LLMProvider:
    names = settings.ai_providers
    if len(names) == 1:
        return _build_one(settings, names[0])
    built: list[LLMProvider] = []
    for name in names:
        try:
            built.append(_build_one(settings, name))
        except ProviderNotConfigured as error:
            logger.warning("ai_provider_skipped", extra={"provider": name, "reason": str(error)})
    if not built:
        raise ProviderNotConfigured(f"Nenhum provedor de {','.join(names)} tem chave.")
    return built[0] if len(built) == 1 else FallbackProvider(built)
