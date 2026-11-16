"""Erros do provedor de IA, independentes do fornecedor (AI_DESIGN §6).

Cada adaptador traduz os erros do SDK/HTTP para estes. `transient` diz se vale
tentar de novo (timeout, 429, 5xx); `user_message` é o texto amigável que o app
mostra — nunca o detalhe técnico, que pode conter dados da requisição.
"""


class ProviderError(Exception):
    code = "ai_provider_error"
    transient = False
    user_message = "A IA não conseguiu responder agora. Tente de novo em instantes."


class ProviderUnavailable(ProviderError):
    """Falha de rede ou erro 5xx do fornecedor."""

    code = "ai_unavailable"
    transient = True
    user_message = "A IA está indisponível no momento. Tente de novo em alguns minutos."


class ProviderTimeout(ProviderUnavailable):
    """O fornecedor não respondeu dentro do tempo limite."""

    code = "ai_timeout"
    user_message = "A IA demorou demais para responder. Tente de novo."


class ProviderRateLimited(ProviderError):
    """Limite de requisições do fornecedor (429)."""

    code = "ai_rate_limited"
    transient = True
    user_message = "Muitas perguntas em pouco tempo. Aguarde um pouco e tente de novo."

    def __init__(self, message: str = "", *, retry_after_s: float | None = None) -> None:
        super().__init__(message)
        self.retry_after_s = retry_after_s


class InvalidModelOutput(ProviderError):
    """Resposta que não dá para usar (vazia, ferramenta com argumentos que não são um
    objeto JSON, motivo de parada desconhecido...). Repetir não ajuda."""

    code = "ai_invalid_output"
    user_message = "A IA respondeu de um jeito inesperado. Tente reformular a pergunta."


class ProviderNotConfigured(ProviderError):
    """Provedor escolhido sem a configuração necessária (chave, adaptador)."""

    code = "ai_not_configured"
    user_message = "A IA ainda não está configurada neste servidor."
