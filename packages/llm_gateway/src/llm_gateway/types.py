"""Tipos neutros de provedor trocados entre gateway e adapters."""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Generic, Literal, TypeVar

from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)


class Task(StrEnum):
    """Tarefas roteáveis (DEC-06). O valor é a chave em config/llm_routing.toml."""

    EXTRACTION = "extraction"
    CLASSIFICATION = "classification"
    COUNCIL = "council"
    CRITICAL_REVIEW = "critical_review"


# Mapeamento para ops.cost_ledger.run_type
TASK_RUN_TYPE: dict[Task, str] = {
    Task.EXTRACTION: "extraction",
    Task.CLASSIFICATION: "classification",
    Task.COUNCIL: "council",
    Task.CRITICAL_REVIEW: "council",
}


@dataclass(frozen=True)
class Message:
    role: Literal["user", "assistant"]
    content: str


@dataclass(frozen=True)
class ProviderRequest:
    model: str
    system: str
    messages: tuple[Message, ...]
    max_tokens: int
    output_model: type[BaseModel]
    effort: str | None = None
    server_fallback: bool = False


@dataclass(frozen=True)
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_input_tokens: int = 0
    cache_creation_input_tokens: int = 0


@dataclass(frozen=True)
class ProviderResponse:
    text: str
    stop_reason: str | None
    served_model: str
    usage: Usage
    request_id: str | None = None
    refusal_category: str | None = None


@dataclass(frozen=True)
class CostEntry:
    """Linha pronta para ops.cost_ledger (A-06)."""

    run_type: str
    run_id: str | None
    provider: str
    model: str
    prompt_version: str
    tokens_in: int
    tokens_out: int
    cost_original: float
    currency_original: str
    fx_rate_brl: float
    cost_brl: float
    pricing_incomplete: bool = False


@dataclass(frozen=True)
class GatewayResult(Generic[T]):
    output: T
    prompt_version: str
    provider: str
    model: str
    attempts: int
    usage: Usage
    cost_brl: float
    request_ids: tuple[str, ...] = field(default_factory=tuple)
