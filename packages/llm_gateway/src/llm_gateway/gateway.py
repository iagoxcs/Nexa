"""LLMGateway — ponto único de chamada a modelos de linguagem (A-01 a A-06)."""
from __future__ import annotations

import json
import logging
import time
from collections.abc import Callable, Mapping

from pydantic import BaseModel, ValidationError

from .adapters import ProviderAdapter, create_adapter
from .config import GatewayConfig
from .costs import CostSink, cost_usd
from .errors import LLMRefusalError, LLMTruncatedError, LLMValidationError
from .prompts import PromptRegistry
from .types import TASK_RUN_TYPE, CostEntry, GatewayResult, Message, ProviderRequest, Task, T, Usage

log = logging.getLogger(__name__)

RETRY_INSTRUCTION = (
    "A resposta anterior não passou na validação do schema. Erros:\n{errors}\n\n"
    "Responda novamente apenas com o JSON completo e válido, sem texto adicional. "
    "Não invente valores: use null quando a informação não estiver no conteúdo fornecido."
)


class LLMGateway:
    """Executa uma tarefa: resolve rota e prompt, chama o adapter, valida a saída e registra custo.

    Garantias:
    - A-03: todo resultado carrega prompt_version (nome@versão#hash).
    - A-04: saída só é devolvida depois de validada pelo modelo Pydantic; inválida após
      max_attempts gera LLMValidationError e nada é devolvido para gravação.
    - A-06: cada tentativa, inclusive as que falham na validação, gera um CostEntry.
    """

    def __init__(
        self,
        config: GatewayConfig,
        cost_sink: CostSink,
        *,
        adapters: Mapping[str, ProviderAdapter] | None = None,
        adapter_factory: Callable[[str], ProviderAdapter] = create_adapter,
        prompts: PromptRegistry | None = None,
    ) -> None:
        self._config = config
        self._sink = cost_sink
        self._adapters: dict[str, ProviderAdapter] = dict(adapters or {})
        self._factory = adapter_factory
        self._prompts = prompts or PromptRegistry(config.prompts_dir)

    def _adapter(self, provider: str) -> ProviderAdapter:
        if provider not in self._adapters:
            self._adapters[provider] = self._factory(provider)
        return self._adapters[provider]

    def complete(
        self,
        task: Task,
        prompt_name: str,
        variables: dict[str, object],
        output_model: type[T],
        *,
        run_id: str | None = None,
    ) -> GatewayResult[T]:
        route = self._config.route(task)
        template = self._prompts.get(prompt_name)
        if template.task != task:
            raise ValueError(f"Prompt {prompt_name} é da tarefa '{template.task}', não '{task}'")
        system, user = template.render(variables)
        prompt_version = template.prompt_version
        adapter = self._adapter(route.provider)

        messages: list[Message] = [Message("user", user)]
        total = Usage()
        cost_brl = 0.0
        request_ids: list[str] = []
        last_errors = ""

        for attempt in range(1, route.max_attempts + 1):
            request = ProviderRequest(
                model=route.model, system=system, messages=tuple(messages), max_tokens=route.max_tokens,
                output_model=output_model, effort=route.effort, server_fallback=route.server_fallback,
            )
            started = time.monotonic()
            response = adapter.complete(request)
            elapsed_ms = int((time.monotonic() - started) * 1000)
            if response.request_id:
                request_ids.append(response.request_id)

            entry = self._record_cost(task, run_id, adapter.name, response.served_model, prompt_version, response.usage)
            cost_brl += entry.cost_brl
            total = Usage(
                input_tokens=total.input_tokens + response.usage.input_tokens,
                output_tokens=total.output_tokens + response.usage.output_tokens,
                cache_read_input_tokens=total.cache_read_input_tokens + response.usage.cache_read_input_tokens,
                cache_creation_input_tokens=total.cache_creation_input_tokens + response.usage.cache_creation_input_tokens,
            )
            log.info("llm_call", extra={
                "task": str(task), "prompt_version": prompt_version, "provider": adapter.name,
                "model": response.served_model, "attempt": attempt, "stop_reason": response.stop_reason,
                "tokens_in": response.usage.input_tokens, "tokens_out": response.usage.output_tokens,
                "elapsed_ms": elapsed_ms, "run_id": run_id, "request_id": response.request_id,
            })

            if response.stop_reason == "refusal":
                raise LLMRefusalError(f"{prompt_version}: solicitação recusada pelo modelo",
                                      category=response.refusal_category)
            if response.stop_reason == "max_tokens":
                raise LLMTruncatedError(f"{prompt_version}: resposta truncada em max_tokens={route.max_tokens}")

            try:
                output = output_model.model_validate_json(response.text)
            except ValidationError as exc:
                last_errors = _summarize(exc)
                log.warning("llm_invalid_output", extra={
                    "prompt_version": prompt_version, "attempt": attempt, "errors": last_errors, "run_id": run_id})
                messages += [Message("assistant", response.text or "{}"),
                             Message("user", RETRY_INSTRUCTION.format(errors=last_errors))]
                continue

            return GatewayResult(output=output, prompt_version=prompt_version, provider=adapter.name,
                                 model=response.served_model, attempts=attempt, usage=total,
                                 cost_brl=round(cost_brl, 6), request_ids=tuple(request_ids))

        raise LLMValidationError(
            f"{prompt_version}: saída inválida após {route.max_attempts} tentativas",
            attempts=route.max_attempts, last_errors=last_errors, prompt_version=prompt_version)

    def _record_cost(self, task: Task, run_id: str | None, provider: str, model: str,
                     prompt_version: str, usage: Usage) -> CostEntry:
        usd, incomplete = cost_usd(self._config.price(model), usage)
        fx = self._config.fx_rate_brl
        entry = CostEntry(
            run_type=TASK_RUN_TYPE[task], run_id=run_id, provider=provider, model=model,
            prompt_version=prompt_version,
            tokens_in=usage.input_tokens + usage.cache_read_input_tokens + usage.cache_creation_input_tokens,
            tokens_out=usage.output_tokens, cost_original=round(usd, 6), currency_original="USD",
            fx_rate_brl=fx, cost_brl=round(usd * fx, 6), pricing_incomplete=incomplete,
        )
        self._sink.record(entry)
        return entry


def _summarize(exc: ValidationError, limit: int = 10) -> str:
    try:
        items = exc.errors(include_url=False)[:limit]
        return "\n".join(f"- {'.'.join(str(p) for p in e['loc']) or '(raiz)'}: {e['msg']}" for e in items)
    except Exception:  # pragma: no cover - defensivo
        return json.dumps(str(exc))[:2000]
