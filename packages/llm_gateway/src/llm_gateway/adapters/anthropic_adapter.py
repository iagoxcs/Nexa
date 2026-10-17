"""Adapter Anthropic (Claude) — único módulo do repositório que importa o SDK `anthropic`."""
from __future__ import annotations

from ..errors import ProviderError
from ..types import ProviderRequest, ProviderResponse, Usage

SERVER_FALLBACK_BETA = "server-side-fallback-2026-07-01"


class AnthropicAdapter:
    name = "anthropic"

    def __init__(self, client=None, *, max_retries: int = 2, timeout: float = 600.0) -> None:
        import anthropic  # import tardio: o SDK só é exigido quando este adapter é usado

        self._sdk = anthropic
        # Retries de transporte (408/409/429/5xx, conexão) ficam a cargo do SDK.
        self._client = client or anthropic.Anthropic(max_retries=max_retries, timeout=timeout)

    def build_kwargs(self, request: ProviderRequest) -> dict:
        output_config: dict = {
            # Saída estruturada: o schema Pydantic é ajustado ao formato aceito pela API.
            # A validação final continua no gateway (A-04).
            "format": {"type": "json_schema", "schema": self._sdk.transform_schema(request.output_model)},
        }
        if request.effort:
            output_config["effort"] = request.effort
        kwargs: dict = {
            "model": request.model,
            "max_tokens": request.max_tokens,
            "messages": [{"role": m.role, "content": m.content} for m in request.messages],
            "output_config": output_config,
        }
        if request.system:
            kwargs["system"] = request.system
        return kwargs

    def complete(self, request: ProviderRequest) -> ProviderResponse:
        kwargs = self.build_kwargs(request)
        sdk = self._sdk
        try:
            if request.server_fallback:
                # Em recusa por política, a API reexecuta no modelo de fallback na mesma chamada.
                # response.model informa o modelo que de fato respondeu (base do custo).
                response = self._client.beta.messages.create(
                    **kwargs, betas=[SERVER_FALLBACK_BETA], fallbacks="default")
            else:
                response = self._client.messages.create(**kwargs)
        except sdk.RateLimitError as exc:
            raise ProviderError(str(exc), provider=self.name, status_code=429, retryable=True,
                                request_id=getattr(exc, "request_id", None)) from exc
        except sdk.APIStatusError as exc:
            raise ProviderError(str(exc), provider=self.name, status_code=exc.status_code,
                                retryable=exc.status_code >= 500,
                                request_id=getattr(exc, "request_id", None)) from exc
        except sdk.APIConnectionError as exc:
            raise ProviderError(str(exc), provider=self.name, retryable=True) from exc

        text = "".join(block.text for block in response.content if block.type == "text")
        u = response.usage
        usage = Usage(
            input_tokens=u.input_tokens or 0,
            output_tokens=u.output_tokens or 0,
            cache_read_input_tokens=getattr(u, "cache_read_input_tokens", None) or 0,
            cache_creation_input_tokens=getattr(u, "cache_creation_input_tokens", None) or 0,
        )
        details = getattr(response, "stop_details", None)
        return ProviderResponse(
            text=text,
            stop_reason=response.stop_reason,
            served_model=response.model,
            usage=usage,
            request_id=getattr(response, "_request_id", None),
            refusal_category=getattr(details, "category", None) if response.stop_reason == "refusal" and details else None,
        )
