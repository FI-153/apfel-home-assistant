# apfel as a Background Service

This is the primary deployment mode `apfel-home-assistant` relies on: apfel running as a long-lived, always-on OpenAI-compatible HTTP server, managed by Homebrew services, so Home Assistant can reach it at a stable local endpoint.

Upstream reference: [`apfel/docs/background-service.md`](../../../apfel/docs/background-service.md).

## Quick start

```bash
brew install Arthur-Ficial/tap/apfel     # one-time install
brew services start apfel                # start now, auto-start at login
```

After `start`, apfel listens on `http://127.0.0.1:11434` and auto-restarts on crash or user login.

## Lifecycle commands

| Command | Effect |
|---|---|
| `brew services start apfel` | Start now + register launch-at-login launchd agent |
| `brew services stop apfel` | Stop and unregister launch-at-login |
| `brew services restart apfel` | Stop + start (e.g. after changing env vars) |
| `brew services info apfel` | Show running / loaded / user state |
| `brew services list` | Status of every brew service on the machine |

## Endpoint shape

- **Base URL:** `http://127.0.0.1:11434/v1`
- **Health probe:** `GET http://127.0.0.1:11434/health` (returns 200 when the on-device model is available; stays public on loopback even with `--token`)
- **Model ID:** `apple-foundationmodel` (what `GET /v1/models` reports and what clients must put in `model` fields)
- **Protocol:** OpenAI Chat Completions, including SSE streaming

Home Assistant's OpenAI conversation integration should be pointed at the `/v1` prefix, with `apple-foundationmodel` as the model name.

## Configuration via environment variables

`brew services` launches apfel from a plist; apfel reads configuration from `APFEL_*` environment variables. Set them *before* `brew services start`, then restart on change:

```bash
# Change port (default 11434)
APFEL_PORT=8080 brew services start apfel

# Enable Bearer-token auth (recommended when HA and apfel aren't the same machine)
APFEL_TOKEN="$(uuidgen)" brew services start apfel

# Attach MCP tool servers (colon-separated paths) — enables apfel to call tools
APFEL_MCP="/path/to/server.py" brew services start apfel
APFEL_MCP="/path/a.py:/path/b.py" brew services start apfel

# MCP timeout for slow/remote servers (default: 5s, max: 300s)
APFEL_MCP_TIMEOUT=30 APFEL_MCP="/path/remote-server.py" brew services start apfel

# Pin a system prompt
APFEL_SYSTEM_PROMPT="Be concise" brew services start apfel

# Expose on LAN (always set a token when you do this)
APFEL_HOST=0.0.0.0 APFEL_TOKEN="$(uuidgen)" brew services start apfel
```

The full list is visible via `apfel --help` under the `ENVIRONMENT` heading.

Changing any env var requires `brew services restart apfel` — the plist captures the environment at service-load time.

## Logs

```bash
tail -f /opt/homebrew/var/log/apfel.log
```

Path is `/usr/local/var/log/apfel.log` on Intel Homebrew prefixes. Both stdout and stderr go to the same file.

## Why this matters for apfel-home-assistant

- **Stable endpoint.** HA can be configured once against `http://127.0.0.1:11434/v1` and never need to restart apfel manually.
- **Zero-interaction uptime.** The service survives reboots, logins, and crashes. HA voice/assist pipelines get a dependable backend.
- **No cloud, no API keys, no downloads.** The model is Apple's on-device foundation model, already present on any Apple Silicon Mac with Apple Intelligence.
- **OpenAI-compatible.** HA's existing `openai_conversation` integration (and generic OpenAI tooling) works unchanged.
- **Homebrew-native distribution.** Fits the planned delivery path: an `apfel-home-assistant` formula can declare apfel as a dependency, ensuring the service is present and runnable on `brew install`.

## When NOT to use `brew services`

- You need flags `brew services` doesn't expose (e.g. specific CLI-only switches).
- You need per-invocation env vars without restarting.
- You're orchestrating apfel alongside other processes with a different supervisor (tmuxinator, overmind, a dev Makefile).

In those cases, use the manual `launchctl` plist approach (see [`advanced-manual-plist.md`](advanced-manual-plist.md)) or run `apfel --serve` in a terminal / tmux session for the duration of the work.
