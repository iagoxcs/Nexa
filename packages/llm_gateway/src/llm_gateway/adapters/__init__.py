"""Registro de adapters por nome de provedor (chave `provider` em llm_routing.toml)."""
from __future__ import annotations

import importlib

from ..errors import ConfigError
from .base import ProviderAdapter

# provedor → (módulo, classe). OpenAI e Google entram como novos módulos nesta pasta (DEC-06).
_ADAPTERS = {
    "anthropic": ("anthropic_adapter", "AnthropicAdapter"),
}


def create_adapter(provider: str) -> ProviderAdapter:
    try:
        module_name, class_name = _ADAPTERS[provider]
    except KeyError:
        raise ConfigError(f"Provedor sem adapter implementado: '{provider}'. Disponíveis: {sorted(_ADAPTERS)}") from None
    module = importlib.import_module(f"{__name__}.{module_name}")
    return getattr(module, class_name)()


__all__ = ["ProviderAdapter", "create_adapter"]
