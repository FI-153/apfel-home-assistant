# apfel Server Security (knobs relevant to Home Assistant)

Only a small slice of apfel's security surface matters for `apfen-home-assistant`. This file covers it; the full matrix is in [`apfel/docs/server-security.md`](../../../apfel/docs/server-security.md).

## Default posture

Out of the box, `brew services start apfel` gives you:

- Bound to `127.0.0.1:11434` (loopback only — not reachable from the LAN).
- Origin-check enforced: browser requests from foreign origins are rejected with `403`, but curl / SDK requests (no `Origin` header) pass through.
- No token required.
- `/health` public on loopback.

This is exactly right when Home Assistant is running on the **same Mac** as apfel (e.g. HA Supervised, HA Container, or a native install on macOS): HA talks to `http://127.0.0.1:11434/v1` with no extra config.

## Scenario: HA on a different host

If Home Assistant runs on a separate device (a HA Yellow, a NUC, a Raspberry Pi, etc.), apfel has to accept connections from outside loopback. Minimum safe setup:

```bash
APFEL_HOST=0.0.0.0 APFEL_TOKEN="$(uuidgen)" brew services start apfel
```

Then:

1. Capture the generated token from the service env (or set an explicit string you already know).
2. Configure HA's OpenAI conversation integration with:
   - `base_url`: `http://<mac-lan-ip>:11434/v1`
   - `api_key`: the token

apfel's origin check still runs, but HA / curl / SDK requests don't send an `Origin` header, so the check is a no-op for them. Token auth is the actual gate.

## Flags that matter (and the env vars that set them)

| Concern | Flag | Env var | When to use |
|---|---|---|---|
| Bind address | `--host` | `APFEL_HOST` | `127.0.0.1` (default) for same-host HA; `0.0.0.0` for remote HA |
| Port | `--port` | `APFEL_PORT` | Override if `11434` clashes with Ollama on the same Mac |
| Bearer token (fixed) | `--token <secret>` | `APFEL_TOKEN` | Any time `APFEL_HOST != 127.0.0.1` |
| Bearer token (auto) | `--token-auto` | — | Quick setup; token printed in logs on start |
| CORS | `--cors` | `APFEL_CORS` | Only if a browser-based HA add-on makes direct `fetch()` calls to apfel |
| Extra origins | `--allowed-origins` | `APFEL_ALLOWED_ORIGINS` | Same scenario as `--cors` |
| Kill all checks | `--footgun` | — | **Do not use** for production HA |
| Public health on LAN bind | `--public-health` | — | Only if LAN monitoring can't send the token |

## Ollama coexistence

Port `11434` is shared with Ollama. If you already run Ollama as a brew service on the same Mac, pick a different apfel port:

```bash
APFEL_PORT=11435 brew services start apfel
```

…and point HA at `http://127.0.0.1:11435/v1` instead.

## Check order (why origin errors sometimes mask token errors)

apfel middleware runs in this order:

1. `OPTIONS` preflight short-circuits (with CORS headers if `--cors`).
2. Origin check (if enabled) — **foreign origin returns `403` before token check runs**.
3. Token check (if enabled) — missing/wrong token returns `401`.
4. Debug endpoint gate (`/v1/logs*` needs `--debug`, otherwise `404`).
5. Route handler.
6. Response-side CORS headers added.

So when debugging HA integration errors: if HA sends an `Origin` header (some custom components do), a `403` from apfel points to origin config, not token config, regardless of whether the token was right.

## Minimum-viable-security recipes

```bash
# Same-Mac HA, nothing fancy
brew services start apfel

# Remote HA, production
APFEL_HOST=0.0.0.0 APFEL_TOKEN="$(openssl rand -hex 16)" brew services start apfel

# Locked down to a single HA origin + token
APFEL_HOST=0.0.0.0 \
APFEL_TOKEN="$(openssl rand -hex 16)" \
APFEL_CORS=1 \
APFEL_ALLOWED_ORIGINS="http://homeassistant.local:8123" \
brew services start apfel
```
