# llm_gateway

Camada única de acesso a modelos de linguagem do NEXA LAB (SPEC A-01 a A-06, DEC-05, DEC-06).
Nenhum outro pacote importa SDK de provedor; o teste `ProviderBoundaryTest` falha se isso acontecer.

## Uso

```python
from pathlib import Path
from pydantic import BaseModel, ConfigDict
from llm_gateway import LLMGateway, InMemoryCostSink, Task, load_config

class ProductBasics(BaseModel):
    model_config = ConfigDict(extra="forbid")
    canonical_name: str
    volume_value: float | None
    volume_unit: str | None

config = load_config(Path("."))              # lê config/llm_routing.toml, config/llm_pricing.toml e NEXA_FX_RATE_BRL
gateway = LLMGateway(config, InMemoryCostSink())
result = gateway.complete(
    Task.EXTRACTION, "extraction.product_page",
    {"brand": "Ollie", "page_text": "..."},
    ProductBasics, run_id="<crawl_run_id>",
)
result.output          # ProductBasics validado
result.prompt_version  # "extraction.product_page@0.1.0#1a2b3c4d" → gravar junto da saída (A-03)
```

## Fluxo de `complete()`

1. Rota da tarefa em `config/llm_routing.toml` (provedor, modelo, `max_tokens`, `effort`, tentativas).
2. Prompt em `prompts/<area>/<nome>.md`; `prompt_version` = `nome@versão#hash`.
3. Chamada ao adapter com saída estruturada (JSON Schema derivado do modelo Pydantic).
4. Validação Pydantic da resposta. Inválida → nova tentativa com os erros de validação; após `max_attempts` → `LLMValidationError` e nada é devolvido para gravação (A-04).
5. `stop_reason = refusal` → `LLMRefusalError` (sem retry); `max_tokens` → `LLMTruncatedError`.
6. Cada tentativa gera um `CostEntry` no formato de `ops.cost_ledger`, calculado sobre o modelo que efetivamente respondeu (A-06).

## Componentes

| Módulo | Função |
|---|---|
| `gateway.py` | Orquestração, retry de validação, registro de custo |
| `config.py` | Rotas, preços, câmbio (`NEXA_FX_RATE_BRL`, obrigatório — DC-14) |
| `prompts.py` | Leitura e renderização de prompts versionados |
| `costs.py` | Custo em USD/BRL por chamada; `CostSink` (destino) |
| `adapters/base.py` | Interface `ProviderAdapter` |
| `adapters/anthropic_adapter.py` | Adapter Claude (SDK `anthropic` 1.x) |
| `adapters/fake.py` | Adapter roteirizado para testes offline |

## Testes

```bash
python3 -m unittest discover -s packages/llm_gateway/tests      # sem SDK: 2 testes do adapter são pulados
uv pip install -e "packages/llm_gateway[dev]" && pytest packages/llm_gateway   # com SDK
```

## Pendências

| Item | Dependência |
|---|---|
| `CostSink` gravando em `ops.cost_ledger` (Supabase) | Cliente Supabase em `packages/shared` (Fase 1) |
| Adapter de segundo provedor para `critical_review` | DEC-06 — escolha do provedor no benchmark da Fase 1 |
| Modelos e `effort` definitivos por tarefa | Benchmark DEC-06 (Fase 1) |
| Prompts de extração/classificação/Conselho | F1-04, F1-07, F1-14 |
| Streaming para respostas longas (> ~16k tokens) | Necessário quando o Conselho exigir saídas maiores |
