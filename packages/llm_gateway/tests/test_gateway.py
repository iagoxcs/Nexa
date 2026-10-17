"""Testes offline do llm_gateway (sem rede, sem SDK de provedor real)."""
from __future__ import annotations

import importlib.util
import re
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path
from types import SimpleNamespace

from pydantic import BaseModel, ConfigDict

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from llm_gateway import (  # noqa: E402
    ConfigError,
    InMemoryCostSink,
    LLMGateway,
    LLMRefusalError,
    LLMTruncatedError,
    LLMValidationError,
    PromptError,
    PromptRegistry,
    RouteNotConfiguredError,
    Task,
    load_config,
)
from llm_gateway.adapters.fake import FakeAdapter  # noqa: E402
from llm_gateway.config import ModelPrice  # noqa: E402
from llm_gateway.costs import cost_usd  # noqa: E402
from llm_gateway.prompts import parse_prompt  # noqa: E402
from llm_gateway.types import ProviderResponse, Usage  # noqa: E402

REPO = Path(__file__).resolve().parents[3]

PROMPT = """---
name: extraction.test_product
version: 0.1.0
task: extraction
description: Prompt de teste
---
## system
Extraia apenas o que estiver no texto. Ausência = null.

## user
Marca: {{brand}}
Texto: {{text}}
"""


class Product(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str
    volume_ml: float | None


def make_env(tmp: Path, routing: str | None = None) -> Path:
    (tmp / "config").mkdir()
    (tmp / "prompts" / "extraction").mkdir(parents=True)
    (tmp / "prompts" / "extraction" / "test_product.md").write_text(PROMPT, encoding="utf-8")
    (tmp / "config" / "llm_routing.toml").write_text(routing or """
[defaults]
max_attempts = 2
[tasks.extraction]
provider = "fake"
model = "m-cheap"
max_tokens = 1000
effort = "low"
""", encoding="utf-8")
    (tmp / "config" / "llm_pricing.toml").write_text("""
[models.m-cheap]
input = 1.0
output = 2.0
[models.m-fallback]
input = 3.0
output = 6.0
""", encoding="utf-8")
    return tmp


class GatewayTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = make_env(Path(self._tmp.name))
        self.config = load_config(self.root, fx_rate_brl=5.0)
        self.sink = InMemoryCostSink()

    def tearDown(self):
        self._tmp.cleanup()

    def gateway(self, responses):
        self.fake = FakeAdapter(responses)
        return LLMGateway(self.config, self.sink, adapters={"fake": self.fake})

    def call(self, gw):
        return gw.complete(Task.EXTRACTION, "extraction.test_product",
                           {"brand": "Ollie", "text": "Stick FPS 50, 15 g"}, Product, run_id="run-1")

    def test_valid_output_first_attempt(self):
        result = self.call(self.gateway(['{"name": "Stick FPS 50", "volume_ml": null}']))
        self.assertEqual(result.output.name, "Stick FPS 50")
        self.assertIsNone(result.output.volume_ml)
        self.assertEqual(result.attempts, 1)
        self.assertRegex(result.prompt_version, r"^extraction\.test_product@0\.1\.0#[0-9a-f]{8}$")
        req = self.fake.requests[0]
        self.assertIn("Marca: Ollie", req.messages[0].content)
        self.assertEqual((req.model, req.effort, req.max_tokens), ("m-cheap", "low", 1000))

    def test_cost_entry_per_call(self):
        self.call(self.gateway(['{"name": "x", "volume_ml": 15}']))
        entry = self.sink.entries[0]
        # 100 tokens in × US$1/M + 50 out × US$2/M = US$0.0002 → R$0.001
        self.assertAlmostEqual(entry.cost_original, 0.0002)
        self.assertAlmostEqual(entry.cost_brl, 0.001)
        self.assertEqual((entry.run_type, entry.run_id, entry.provider), ("extraction", "run-1", "fake"))
        self.assertTrue(entry.prompt_version.startswith("extraction.test_product@"))

    def test_invalid_then_valid_retries_and_records_both_costs(self):
        result = self.call(self.gateway(['{"nome": "errado"}', '{"name": "ok", "volume_ml": 30}']))
        self.assertEqual(result.attempts, 2)
        self.assertEqual(len(self.sink.entries), 2)
        retry = self.fake.requests[1].messages
        self.assertEqual([m.role for m in retry], ["user", "assistant", "user"])
        self.assertIn("não passou na validação", retry[2].content)
        self.assertEqual(result.usage.input_tokens, 200)

    def test_invalid_after_max_attempts_raises_and_returns_nothing(self):
        gw = self.gateway(["não é json", '{"name": 1}'])
        with self.assertRaises(LLMValidationError) as ctx:
            self.call(gw)
        self.assertEqual(ctx.exception.attempts, 2)
        self.assertEqual(len(self.sink.entries), 2)  # custo registrado mesmo sem saída válida (A-06)

    def test_refusal_is_not_retried(self):
        refusal = ProviderResponse(text="", stop_reason="refusal", served_model="m-cheap",
                                   usage=Usage(10, 0), refusal_category="cyber")
        with self.assertRaises(LLMRefusalError) as ctx:
            self.call(self.gateway([refusal]))
        self.assertEqual(ctx.exception.category, "cyber")
        self.assertEqual(len(self.fake.requests), 1)

    def test_truncated_output_raises(self):
        cut = ProviderResponse(text='{"name": "x', stop_reason="max_tokens", served_model="m-cheap", usage=Usage(10, 1000))
        with self.assertRaises(LLMTruncatedError):
            self.call(self.gateway([cut]))

    def test_cost_uses_served_model_after_fallback(self):
        served = ProviderResponse(text='{"name": "x", "volume_ml": null}', stop_reason="end_turn",
                                  served_model="m-fallback", usage=Usage(1_000_000, 0))
        result = self.call(self.gateway([served]))
        self.assertEqual(result.model, "m-fallback")
        self.assertAlmostEqual(self.sink.entries[0].cost_original, 3.0)

    def test_unconfigured_task(self):
        gw = self.gateway([])
        with self.assertRaises(RouteNotConfiguredError):
            gw.complete(Task.CRITICAL_REVIEW, "extraction.test_product", {}, Product)

    def test_missing_variable(self):
        with self.assertRaises(PromptError):
            self.gateway([]).complete(Task.EXTRACTION, "extraction.test_product", {"brand": "x"}, Product)


class ConfigTest(unittest.TestCase):
    def test_fx_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_env(Path(tmp))
            with unittest.mock.patch.dict("os.environ", {}, clear=True):
                with self.assertRaises(ConfigError):
                    load_config(root)

    def test_route_model_needs_price(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_env(Path(tmp), routing='[tasks.extraction]\nprovider="fake"\nmodel="sem-preco"\nmax_tokens=10\n')
            with self.assertRaises(ConfigError):
                load_config(root, fx_rate_brl=5.0)

    def test_repo_config_is_valid(self):
        config = load_config(REPO, fx_rate_brl=5.0)
        self.assertEqual(config.route(Task.COUNCIL).model, "claude-opus-5-5")
        self.assertTrue(config.route(Task.COUNCIL).server_fallback)
        with self.assertRaises(RouteNotConfiguredError):
            config.route(Task.CRITICAL_REVIEW)


class CostTest(unittest.TestCase):
    def test_long_context_tier(self):
        price = ModelPrice(input=0.1, output=0.5, long_context_threshold=100_000, input_long=0.5, output_long=2.5)
        self.assertAlmostEqual(cost_usd(price, Usage(100_000, 1_000_000))[0], 0.01 + 0.5)
        self.assertAlmostEqual(cost_usd(price, Usage(200_000, 1_000_000))[0], 0.1 + 2.5)

    def test_cache_without_price_is_flagged(self):
        usd, incomplete = cost_usd(ModelPrice(input=1, output=1), Usage(0, 0, cache_read_input_tokens=10))
        self.assertTrue(incomplete)
        self.assertEqual(usd, 0)


class PromptTest(unittest.TestCase):
    def test_hash_changes_with_content(self):
        a = parse_prompt(PROMPT, source="a")
        b = parse_prompt(PROMPT.replace("null.", "null!"), source="b")
        self.assertEqual(a.version, b.version)
        self.assertNotEqual(a.prompt_version, b.prompt_version)

    def test_name_must_match_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp) / "extraction"
            d.mkdir()
            (d / "outro.md").write_text(PROMPT, encoding="utf-8")
            with self.assertRaises(PromptError):
                PromptRegistry(Path(tmp)).get("extraction.outro")


class AnthropicAdapterTest(unittest.TestCase):
    """Usa um cliente falso: valida montagem da requisição e normalização da resposta, sem rede."""

    def setUp(self):
        if importlib.util.find_spec("anthropic") is None:
            self.skipTest("SDK anthropic não instalado (extra [anthropic])")

    def _client(self, calls):
        usage = SimpleNamespace(input_tokens=12, output_tokens=7, cache_read_input_tokens=None, cache_creation_input_tokens=None)
        resp = SimpleNamespace(content=[SimpleNamespace(type="text", text='{"name": "x", "volume_ml": null}')],
                               usage=usage, stop_reason="end_turn", model="claude-opus-5-5", stop_details=None,
                               _request_id="req_1")

        def create(**kw):
            calls.append(kw)
            return resp

        return SimpleNamespace(messages=SimpleNamespace(create=create), beta=SimpleNamespace(messages=SimpleNamespace(create=create)))

    def _request(self, **kw):
        from llm_gateway.types import Message, ProviderRequest
        base = dict(model="claude-opus-5-5", system="sys", messages=(Message("user", "oi"),),
                    max_tokens=100, output_model=Product, effort="high")
        base.update(kw)
        return ProviderRequest(**base)

    def test_request_shape_and_response(self):
        from llm_gateway.adapters.anthropic_adapter import AnthropicAdapter
        calls = []
        out = AnthropicAdapter(client=self._client(calls)).complete(self._request())
        kw = calls[0]
        self.assertEqual(kw["output_config"]["effort"], "high")
        self.assertEqual(kw["output_config"]["format"]["type"], "json_schema")
        self.assertFalse(kw["output_config"]["format"]["schema"].get("additionalProperties", True))
        self.assertNotIn("temperature", kw)
        self.assertNotIn("betas", kw)
        self.assertEqual((out.usage.input_tokens, out.usage.output_tokens, out.request_id), (12, 7, "req_1"))

    def test_server_fallback_uses_beta(self):
        from llm_gateway.adapters.anthropic_adapter import SERVER_FALLBACK_BETA, AnthropicAdapter
        calls = []
        AnthropicAdapter(client=self._client(calls)).complete(self._request(server_fallback=True))
        self.assertEqual(calls[0]["betas"], [SERVER_FALLBACK_BETA])
        self.assertEqual(calls[0]["fallbacks"], "default")


class ProviderBoundaryTest(unittest.TestCase):
    """A-02: nenhum SDK de provedor é importado fora de llm_gateway/adapters."""

    SDK_IMPORT = re.compile(r"^\s*(?:import|from)\s+(anthropic|openai|google\.genai|google\.generativeai|mistralai|cohere)\b", re.M)

    def test_no_sdk_imports_outside_adapters(self):
        allowed = REPO / "packages" / "llm_gateway" / "src" / "llm_gateway" / "adapters"
        offenders = []
        for path in REPO.rglob("*.py"):
            parts = path.relative_to(REPO).parts
            if parts[0] in {".venv", "node_modules", ".git"} or allowed in path.parents:
                continue
            if self.SDK_IMPORT.search(path.read_text(encoding="utf-8", errors="ignore")):
                offenders.append(str(path.relative_to(REPO)))
        self.assertEqual(offenders, [], f"SDK de provedor importado fora do llm_gateway: {offenders}")

if __name__ == "__main__":
    unittest.main()
