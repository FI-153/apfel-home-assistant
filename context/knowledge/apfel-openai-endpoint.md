# apfel's OpenAI-Compatible Endpoint

When apfel runs as a background service, it exposes an OpenAI-compatible HTTP surface that Home Assistant (and any OpenAI SDK) can target via `base_url`.

Upstream reference: [`apfel/docs/openai-api-compatibility.md`](../../../apfel/docs/openai-api-compatibility.md).

## Base URL

- `http://127.0.0.1:11434/v1` (default — loopback, same machine as apfel)
- `http://<mac-ip>:11434/v1` when started with `APFEL_HOST=0.0.0.0` (token auth required in practice)

## Model identifier

Always `apple-foundationmodel`. `GET /v1/models` returns exactly this one entry. Requests that specify a different model are rejected.

## Supported features

| Feature | Status | Notes |
|---|---|---|
| `POST /v1/chat/completions` | Supported | Streaming + non-streaming |
| `GET /v1/models` | Supported | Returns `apple-foundationmodel` |
| `GET /health` | Supported | Reports model availability, context window, supported languages |
| Tool calling | Supported | Native `ToolDefinition` + JSON fallback detection |
| `response_format: json_object` | Supported | System-prompt injection; markdown fences stripped from output |
| `temperature`, `max_tokens`, `seed` | Supported | Mapped onto FoundationModels `GenerationOptions` |
| `stream: true` | Supported | SSE; final usage chunk only when `stream_options: {"include_usage": true}` |
| `finish_reason` | Supported | `stop`, `tool_calls`, `length` |
| Context-strategy hints | Supported | `x_context_strategy`, `x_context_max_turns`, `x_context_output_reserve` extensions |
| CORS | Supported | Enable with `--cors` / `APFEL_CORS=1` |
| `Authorization: Bearer …` | Supported | Required when `APFEL_TOKEN` is set |

## Not supported

| Request | Response |
|---|---|
| `POST /v1/completions` (legacy) | `501 Not Implemented` |
| `POST /v1/embeddings` | `501` — no embeddings on-device |
| `POST /v1/responses` | `501` — use Chat Completions |
| `logprobs=true`, `n>1`, `stop`, `presence_penalty`, `frequency_penalty` | `400` — rejected explicitly (`n=1` / `logprobs=false` are accepted no-ops) |
| Multi-modal image messages | `400` — rejected with a clear error |

`apfel-home-assistant` must only invoke Chat Completions and must not rely on embeddings, legacy completions, or the Responses API.

## Context window

The on-device model's context window is finite (4096 tokens at time of writing). apfel exposes multiple context-trimming strategies; HA conversation history should either stay small or set an explicit `x_context_strategy` hint.

## Health check pattern for HA

HA's integration should probe `GET /health` before issuing a chat request, to avoid surfacing obscure errors when apfel is stopped or the on-device model is unavailable (e.g. user disabled Apple Intelligence).

```bash
curl -sf http://127.0.0.1:11434/health
# => 200 OK  {"status":"ok","model":"apple-foundationmodel",...}
```

On loopback, `/health` stays public even when `APFEL_TOKEN` is set, which makes it ideal as a lightweight readiness probe. On non-loopback binds with `APFEL_TOKEN` set, `/health` also requires the token unless `--public-health` is passed.

## Client-side shape

Any OpenAI SDK works with `base_url="http://127.0.0.1:11434/v1"`:

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:11434/v1", api_key="ignored")
resp = client.chat.completions.create(
    model="apple-foundationmodel",
    messages=[{"role": "user", "content": "Turn off the kitchen lights"}],
)
```

When `APFEL_TOKEN` is set, pass the token as `api_key` instead of `"ignored"`.
