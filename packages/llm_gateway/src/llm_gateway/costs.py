"""Cálculo de custo por chamada e destino para ops.cost_ledger (A-06)."""
from __future__ import annotations

import logging
from typing import Protocol

from .config import ModelPrice
from .types import CostEntry, Usage

log = logging.getLogger(__name__)
_PER_TOKEN = 1_000_000


def cost_usd(price: ModelPrice, usage: Usage) -> tuple[float, bool]:
    """Retorna (custo em USD, pricing_incomplete).

    pricing_incomplete = True quando houve tokens de cache sem preço configurado;
    nesse caso esses tokens não entram no valor e o registro fica sinalizado.
    """
    prompt_tokens = usage.input_tokens + usage.cache_read_input_tokens + usage.cache_creation_input_tokens
    long_ctx = price.long_context_threshold is not None and prompt_tokens > price.long_context_threshold
    in_price = price.input_long if long_ctx and price.input_long is not None else price.input
    out_price = price.output_long if long_ctx and price.output_long is not None else price.output

    total = usage.input_tokens * in_price + usage.output_tokens * out_price
    incomplete = False
    for tokens, unit in ((usage.cache_read_input_tokens, price.cache_read),
                         (usage.cache_creation_input_tokens, price.cache_write)):
        if tokens:
            if unit is None:
                incomplete = True
            else:
                total += tokens * unit
    return total / _PER_TOKEN, incomplete


class CostSink(Protocol):
    def record(self, entry: CostEntry) -> None: ...


class InMemoryCostSink:
    """Destino para testes e execuções locais."""

    def __init__(self) -> None:
        self.entries: list[CostEntry] = []

    def record(self, entry: CostEntry) -> None:
        if entry.pricing_incomplete:
            log.warning("custo incompleto (tokens de cache sem preço): %s %s", entry.provider, entry.model)
        self.entries.append(entry)
