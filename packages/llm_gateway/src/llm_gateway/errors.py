"""Erros da camada llm_gateway. Nenhum erro de SDK de provedor atravessa esta fronteira."""
from __future__ import annotations


class GatewayError(Exception):
    """Base de todos os erros do gateway."""


class ConfigError(GatewayError):
    """Configuração de roteamento, preço ou câmbio ausente/inválida."""


class RouteNotConfiguredError(ConfigError):
    """Tarefa sem rota definida em config/llm_routing.toml."""


class PromptError(GatewayError):
    """Prompt inexistente, malformado ou com variável ausente."""


class ProviderError(GatewayError):
    """Falha de transporte/API do provedor, já normalizada pelo adapter."""

    def __init__(self, message: str, *, provider: str, status_code: int | None = None,
                 retryable: bool = False, request_id: str | None = None) -> None:
        super().__init__(message)
        self.provider = provider
        self.status_code = status_code
        self.retryable = retryable
        self.request_id = request_id


class LLMRefusalError(GatewayError):
    """O modelo recusou a solicitação (stop_reason = refusal). Não há retry."""

    def __init__(self, message: str, *, category: str | None = None) -> None:
        super().__init__(message)
        self.category = category


class LLMTruncatedError(GatewayError):
    """A resposta atingiu max_tokens; a saída está incompleta e não é gravada."""


class LLMValidationError(GatewayError):
    """Saída inválida após esgotar as tentativas (A-04). Nada deve ser gravado."""

    def __init__(self, message: str, *, attempts: int, last_errors: str, prompt_version: str) -> None:
        super().__init__(message)
        self.attempts = attempts
        self.last_errors = last_errors
        self.prompt_version = prompt_version
