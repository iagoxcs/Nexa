"""Interface comum dos adapters de provedor (A-02)."""
from __future__ import annotations

from typing import Protocol

from ..types import ProviderRequest, ProviderResponse


class ProviderAdapter(Protocol):
    """Contrato que todo adapter implementa.

    - Recebe um ProviderRequest neutro e devolve ProviderResponse com o texto bruto.
    - Converte erros do SDK em llm_gateway.errors.ProviderError.
    - Não valida o conteúdo: a validação de schema é do gateway (A-04).
    - Não grava nada em banco.
    """

    name: str

    def complete(self, request: ProviderRequest) -> ProviderResponse: ...
