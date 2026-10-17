"""Adapter determinístico para testes e desenvolvimento offline (sem rede, sem custo real)."""
from __future__ import annotations

from collections.abc import Iterable

from ..types import ProviderRequest, ProviderResponse, Usage


class FakeAdapter:
    """Devolve respostas roteirizadas, na ordem, e registra cada requisição recebida."""

    name = "fake"

    def __init__(self, responses: Iterable[ProviderResponse | str], *, model: str = "fake-model") -> None:
        self._responses = list(responses)
        self._model = model
        self.requests: list[ProviderRequest] = []

    def complete(self, request: ProviderRequest) -> ProviderResponse:
        self.requests.append(request)
        if not self._responses:
            raise AssertionError("FakeAdapter sem respostas roteirizadas restantes")
        item = self._responses.pop(0)
        if isinstance(item, ProviderResponse):
            return item
        return ProviderResponse(text=item, stop_reason="end_turn", served_model=request.model,
                                usage=Usage(input_tokens=100, output_tokens=50))
