"""Carga de config/llm_routing.toml e config/llm_pricing.toml."""
from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass
from pathlib import Path

from .errors import ConfigError, RouteNotConfiguredError
from .types import Task

EFFORT_LEVELS = {"low", "medium", "high", "xhigh", "max"}


@dataclass(frozen=True)
class Route:
    task: Task
    provider: str
    model: str
    max_tokens: int
    max_attempts: int
    effort: str | None = None
    server_fallback: bool = False


@dataclass(frozen=True)
class ModelPrice:
    """Preço em USD por 1 milhão de tokens."""

    input: float
    output: float
    cache_read: float | None = None
    cache_write: float | None = None
    long_context_threshold: int | None = None
    input_long: float | None = None
    output_long: float | None = None


@dataclass(frozen=True)
class GatewayConfig:
    routes: dict[Task, Route]
    prices: dict[str, ModelPrice]
    fx_rate_brl: float
    prompts_dir: Path

    def route(self, task: Task) -> Route:
        try:
            return self.routes[task]
        except KeyError:
            raise RouteNotConfiguredError(f"Tarefa '{task}' sem rota em llm_routing.toml") from None

    def price(self, model: str) -> ModelPrice:
        try:
            return self.prices[model]
        except KeyError:
            raise ConfigError(f"Modelo '{model}' sem preço em llm_pricing.toml") from None


def _load_toml(path: Path) -> dict:
    if not path.exists():
        raise ConfigError(f"Arquivo de configuração ausente: {path}")
    with path.open("rb") as f:
        return tomllib.load(f)


def load_config(repo_root: Path, *, fx_rate_brl: float | None = None) -> GatewayConfig:
    """Lê rotas e preços. O câmbio vem do argumento ou de NEXA_FX_RATE_BRL (DC-14)."""
    routing = _load_toml(repo_root / "config" / "llm_routing.toml")
    pricing = _load_toml(repo_root / "config" / "llm_pricing.toml")

    default_attempts = int(routing.get("defaults", {}).get("max_attempts", 3))
    routes: dict[Task, Route] = {}
    for key, spec in routing.get("tasks", {}).items():
        try:
            task = Task(key)
        except ValueError:
            raise ConfigError(f"Tarefa desconhecida em llm_routing.toml: {key}") from None
        effort = spec.get("effort")
        if effort is not None and effort not in EFFORT_LEVELS:
            raise ConfigError(f"effort inválido para {key}: {effort}")
        routes[task] = Route(
            task=task,
            provider=spec["provider"],
            model=spec["model"],
            max_tokens=int(spec["max_tokens"]),
            max_attempts=int(spec.get("max_attempts", default_attempts)),
            effort=effort,
            server_fallback=bool(spec.get("server_fallback", False)),
        )

    prices = {model: ModelPrice(**spec) for model, spec in pricing.get("models", {}).items()}
    for route in routes.values():
        if route.model not in prices:
            raise ConfigError(f"Rota '{route.task}' usa modelo sem preço: {route.model}")

    if fx_rate_brl is None:
        raw = os.environ.get("NEXA_FX_RATE_BRL")
        if not raw:
            raise ConfigError("Câmbio USD→BRL não informado (NEXA_FX_RATE_BRL). Obrigatório para ops.cost_ledger.cost_brl.")
        fx_rate_brl = float(raw)
    if fx_rate_brl <= 0:
        raise ConfigError("fx_rate_brl deve ser positivo")

    return GatewayConfig(routes=routes, prices=prices, fx_rate_brl=fx_rate_brl, prompts_dir=repo_root / "prompts")
