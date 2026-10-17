"""NEXA LAB — llm_gateway: camada única de acesso a LLMs (SPEC A-01 a A-06, DEC-05, DEC-06)."""
from .config import GatewayConfig, ModelPrice, Route, load_config
from .costs import CostSink, InMemoryCostSink
from .errors import (
    ConfigError,
    GatewayError,
    LLMRefusalError,
    LLMTruncatedError,
    LLMValidationError,
    PromptError,
    ProviderError,
    RouteNotConfiguredError,
)
from .gateway import LLMGateway
from .prompts import PromptRegistry, PromptTemplate
from .types import CostEntry, GatewayResult, Task

__all__ = [
    "ConfigError", "CostEntry", "CostSink", "GatewayConfig", "GatewayError", "GatewayResult",
    "InMemoryCostSink", "LLMGateway", "LLMRefusalError", "LLMTruncatedError", "LLMValidationError",
    "ModelPrice", "PromptError", "PromptRegistry", "PromptTemplate", "ProviderError", "Route",
    "RouteNotConfiguredError", "Task", "load_config",
]
