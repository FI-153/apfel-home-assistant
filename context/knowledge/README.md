# Knowledge Index

Reference material about the external systems `apfen-home-assistant` depends on. These are notes tailored to this project — the authoritative sources live in their upstream repos, and each file links back.

## apfel (on-device LLM backend)

- [`apfel-background-service.md`](apfel-background-service.md) — running apfel as an always-on OpenAI-compatible server via `brew services start apfel`; env-var configuration; lifecycle commands; logs.
- [`apfel-openai-endpoint.md`](apfel-openai-endpoint.md) — the OpenAI-compatible API surface apfel exposes, what's supported, what returns 501/400, and the client-side shape HA's integration will use.
- [`apfel-server-security.md`](apfel-server-security.md) — origin check, token auth, CORS, LAN-binding considerations for same-Mac vs remote-HA deployments.
- [`advanced-manual-plist.md`](advanced-manual-plist.md) — escape hatch when `brew services` can't express the needed apfel configuration.

## Home Assistant

*(TODO — add once the HA integration surface is scoped: which integration (`openai_conversation` vs custom component), how `base_url` is configured, voice/assist pipeline wiring.)*
