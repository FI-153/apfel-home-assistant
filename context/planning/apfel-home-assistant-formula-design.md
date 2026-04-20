# Plan: apfel-home-assistant Homebrew Formula

> **Date**: 2026-04-20
> **Scope**: Design for the first shipped artifact — a Homebrew formula that wraps
> [`apfel`](https://github.com/Arthur-Ficial/apfel) with Home-Assistant-friendly defaults, plus a
> small bash CLI that handles first-run setup (token, port, HA integration snippet).
> **Prerequisite**: apfel is available via `brew install Arthur-Ficial/tap/apfel` and is runnable on
> the target Mac (macOS 26 Tahoe, Apple Silicon).

---

## Context

Home Assistant can already use any OpenAI-compatible endpoint as a conversation backend via the
third-party **OpenAI Extended Conversation** integration. apfel already exposes exactly that
endpoint and does 95% of the work. The remaining friction is purely configuration:

- Apfel's defaults (loopback-only, no token) don't suit Home Assistant running on a separate
  device (HA Yellow, NUC, Raspberry Pi) — the common case.
- A working server alone isn't enough: the user also needs to know the **base URL**, **API key**,
  and **model ID** to paste into HA's integration form.
- `brew services start apfel` is the right mental model, but it configures apfel for arbitrary
  use, not specifically for HA.

The goal of `apfel-home-assistant` is to collapse "install → paste three values into HA → done"
into the shortest possible path, distributed as a native Homebrew formula so installation feels
identical to every other service on a Mac.

Non-goals for this first iteration:

- MCP tool-calling bridges to the Home Assistant API.
- A bespoke HA custom component — we deliberately reuse **OpenAI Extended Conversation**.
- Advanced topologies (multiple apfel instances, reverse proxies, TLS termination).
- System prompt customization beyond apfel's defaults.

These are deferred and explicitly accommodated by the config shape described below so they can be
added without breaking changes.

---

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Homebrew formula: apfel-home-assistant                     │
│  Lives in: github.com/FI-153/homebrew-tap/Formula/          │
│                                                              │
│  depends_on: "arthur-ficial/tap/apfel"                      │
│  depends_on: macos: :tahoe                                  │
│                                                              │
│  Installs:                                                   │
│  ├─ bin/apfel-home-assistant         (user CLI)             │
│  ├─ libexec/apfel-home-assistant-run (launcher, invoked by  │
│  │                                    brew services)        │
│  └─ etc/apfel-home-assistant.conf    (seeded on install if  │
│                                       absent; TOKEN blank)  │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ brew services start apfel-home-assistant
                         ▼
            ┌────────────────────────────────┐
            │  launchd → apfel-home-assistant│
            │              -run              │
            │    │                           │
            │    ▼                           │
            │  exec apfel --serve            │
            │    APFEL_HOST=0.0.0.0          │
            │    APFEL_PORT=<from conf>      │
            │    APFEL_TOKEN=<from conf>     │
            │    (origin check left ON)      │
            └────────────────────────────────┘
                         │
                         │ http://<mac-lan-ip>:PORT/v1
                         ▼
              ┌─────────────────────────┐
              │  Home Assistant         │
              │  "OpenAI Extended       │
              │   Conversation" add-on  │
              └─────────────────────────┘
```

User lifecycle:

```
brew install FI-153/tap/apfel-home-assistant
apfel-home-assistant setup           # one-time: picks port, mints token, prints HA config
brew services start apfel-home-assistant
# ...paste Base URL + API Key + Model into HA integration UI...
```

---

## Design

### Repository split

Two repos, already existing:

- **`apfel-home-assistant/`** (this repo) — source of truth for the wrapper scripts, default
  conf template, docs. Releases are tagged source tarballs; the formula URL points at these.
- **`homebrew-tap/`** (`../homebrew-tap`) — tap that publishes `Formula/apfel-home-assistant.rb`.
  The existing `wyoming-apple-stt.rb` in the same tap is the structural precedent and is followed
  closely (see "Formula" subsection).

Source-repo layout:

```
apfel-home-assistant/
├── bin/
│   └── apfel-home-assistant         # user-facing CLI
├── libexec/
│   └── apfel-home-assistant-run     # launcher invoked by launchd
└── ...                              # README, LICENSE, Makefile for release packaging
```

The default conf contents live **inline in the formula** (heredoc in the `install` block),
matching the `wyoming-apple-stt.rb` pattern. Shipping a separate template file in the source
tarball adds no value — nothing else in the source tree needs to read it.

### Components

Three executables / artifacts, each with a single responsibility. This separation exists so the
CLI can evolve (new subcommands) without touching the launchd-visible surface, and the launcher
stays minimal enough to audit at a glance.

#### `bin/apfel-home-assistant` — user CLI

Bash script. The only interactive surface. Subcommands:

| Subcommand | Purpose |
|---|---|
| `setup` | First-run configuration: pick an available port, generate a token, write the conf, print the HA integration block. Refuses to overwrite an existing conf that has a non-empty `TOKEN` unless `--force` is passed. |
| `show-config` | Re-prints the HA integration block (base URL, API key, model ID) from the current conf, without modifying anything. Safe to run any time. |
| `rotate-token` | Replaces `TOKEN=` in the conf with a fresh `openssl rand -hex 32`. Prints the new HA block and a reminder to `brew services restart apfel-home-assistant` plus update the HA integration. |
| `--help` / `-h` | Usage. |

Never touches `launchctl` directly. Never starts or stops the service. Lifecycle belongs to
`brew services`.

Dependencies: `openssl` (macOS system), `lsof` (macOS system), `ipconfig` (macOS system). No
Homebrew-installed runtime deps.

#### `libexec/apfel-home-assistant-run` — launcher

Bash script invoked by launchd via the formula's `service do` block. Responsibilities:

1. `set -euo pipefail`.
2. Source `$(brew --prefix)/etc/apfel-home-assistant.conf`.
3. Validate: `TOKEN` must be non-empty; `PORT` must be a number; `HOST` must be set. On any
   validation failure, emit a clear stderr message pointing the user at `apfel-home-assistant setup`
   and exit non-zero so launchd's failure is loud rather than a silent-restart loop.
4. Export `APFEL_HOST`, `APFEL_PORT`, `APFEL_TOKEN`.
5. `exec apfel --serve` with no further flags — all configuration flows via env vars.

No interactive I/O. No writes to the conf. No token generation. If the conf is missing or
incomplete, the launcher fails fast rather than generating defaults — that silent mutation would
be hostile in a service context.

#### `etc/apfel-home-assistant.conf` — default conf (written by formula)

```
# apfel-home-assistant configuration
# Edit manually only if you know what you're doing.
# Normal workflow: `apfel-home-assistant setup` / `rotate-token`.
# Restart after editing: `brew services restart apfel-home-assistant`.

HOST=0.0.0.0
PORT=11434
TOKEN=
```

The formula writes this inline via heredoc on install, guarded by `unless conf.exist?` — same
pattern as `wyoming-apple-stt.rb`. An existing conf is never overwritten by `brew install` or
`brew upgrade`. Mode `0600`: the file holds a bearer token once `setup` has run.

### Formula (`homebrew-tap/Formula/apfel-home-assistant.rb`)

Mirrors the structural pattern of `wyoming-apple-stt.rb` in the same tap. Key differences:

- **`depends_on "arthur-ficial/tap/apfel"`** — cross-tap dependency, so `brew install` of this
  formula transitively installs apfel.
- **`depends_on macos: :tahoe`** — apfel's minimum is macOS 26 Tahoe; we inherit it.
- **No Python / virtualenv block** — this is a bash wrapper.
- **`install` block** — installs `bin/apfel-home-assistant` and `libexec/apfel-home-assistant-run`,
  writes the default conf if absent.
- **`service do` block** — `run [opt_libexec/"apfel-home-assistant-run"]`, `keep_alive true`,
  `log_path var/"log/apfel-home-assistant.log"`, `error_log_path var/"log/apfel-home-assistant.log"`.
- **`test do` block** — `assert_match /Usage/, shell_output("#{bin}/apfel-home-assistant --help")`
  plus a check that the launcher script exists and is executable.

### `setup` flow — canonical output

```
$ apfel-home-assistant setup
→ Checking port 11434... in use (apfel is already bound there).
→ Checking port 11435... free.
→ Selected port: 11435
→ Generating token...
→ Writing /opt/homebrew/etc/apfel-home-assistant.conf (mode 0600)
→ Detected LAN IP: 192.168.1.42

Next steps:
  1. Start the server:
       brew services start apfel-home-assistant

  2. In Home Assistant, add the "OpenAI Extended Conversation" integration with:
       Base URL:  http://192.168.1.42:11435/v1
       API Key:   3f9a1d...c0b2    (64 hex chars — actual value printed in full)
       Model:     apple-foundationmodel
```

The API key is printed **in full**, unmasked. This is a local-LAN bearer token that the user
needs to copy-paste; masking would defeat the purpose. `show-config` reprints the same block on
demand if the user loses their terminal scrollback.

### Port probe

`lsof -iTCP:<port> -sTCP:LISTEN -nP -t`. Walk the sequence **11434 → 11435 → 11436 → 11437**; the
first free port wins. If all four are taken, abort with a clear error and instruct the user to
edit the conf manually. Four attempts is a deliberate YAGNI bound — if the user has three other
LLM servers running, they can set `PORT=` by hand.

### LAN IP detection

`ipconfig getifaddr en0`, falling back to `en1` on `en0` failure. If both fail (unlikely on a Mac,
but possible with VPNs or bridged network setups), print `<your-mac-lan-ip>` as a literal
placeholder and append a one-line hint telling the user to substitute it manually. `setup` does
not fail on IP-detection failure — the conf is still written correctly.

### HA integration

Target integration: **OpenAI Extended Conversation** (the community custom component), not the
built-in `openai_conversation`. The three fields the user fills in:

| HA field | Value |
|---|---|
| Base URL | `http://<LAN-IP>:<PORT>/v1` |
| API Key | 64-hex token from the conf |
| Model | `apple-foundationmodel` |

The model string is hardcoded in the `setup` / `show-config` output for now. If apfel ever
exposes more than one model ID, we add a `MODEL=` line to the conf and echo it through.

---

## Edge Cases & Constraints

### Re-running `setup`

`setup` checks whether the existing conf already has a non-empty `TOKEN=`. If so, it refuses to
overwrite without `--force`. This prevents the most damaging user error: running `setup` twice
and silently invalidating the token that HA is already using. `show-config` is the right tool for
"I forgot what I copied into HA."

### Coexistence with a standalone `brew services start apfel`

Fully supported. The port probe will step past any already-bound apfel instance. The two services
run independently; both depend on the same `apfel` Homebrew package, so there's no binary
duplication.

### Coexistence with Ollama on 11434

Same mechanism — port probe catches it. Documented in the README as a known scenario so users
know why their apfel-home-assistant ended up on 11435.

### Token rotation

`rotate-token` overwrites `TOKEN=` in place and prints the new HA block. The user must (a)
`brew services restart apfel-home-assistant` and (b) update the HA integration. Both reminders
are in the command's stdout; there is no automated HA-side update (out of scope — HA integrations
are configured in HA, not by external processes).

### Upgrades

`brew upgrade apfel-home-assistant` must **never** clobber `etc/apfel-home-assistant.conf`.
Homebrew's standard `etc/` semantics protect this automatically (same as `wyoming-apple-stt`); we
rely on `unless conf.exist?` in the formula's install block.

### Uninstall

`brew uninstall apfel-home-assistant` leaves the conf file in place. This is standard Homebrew
behavior for `etc/` and is a feature here: a user who uninstalls and reinstalls keeps their token
and any HA-side configuration continues to work.

### Launcher failure modes

The launcher's only responsibility is to source + validate + exec. Every failure mode (missing
conf, empty token, invalid port) produces a single stderr line and a non-zero exit, letting
launchd's restart-loop log a clear cause in `var/log/apfel-home-assistant.log`. It does **not**
attempt to self-heal — silent mutation from a launchd-invoked process would be a support
nightmare.

### apfel endpoint contract drift

apfel is external and may evolve. In particular, if apfel starts accepting model IDs other than
`apple-foundationmodel`, the hardcoded value in `setup`/`show-config` becomes stale. Mitigation:
document in the knowledge base that model ID is defined by upstream apfel, and keep
`context/knowledge/apfel-openai-endpoint.md` in sync with apfel's `docs/openai-api-compatibility.md`.

### Security posture (explicit)

- `APFEL_HOST=0.0.0.0` — LAN-exposed. Any device on the same network can reach the port.
- Bearer token (`APFEL_TOKEN`) is the **only** gate. The formula cannot be configured without
  one; the launcher refuses to start if `TOKEN=` is empty.
- Origin check stays **on** (we do not pass `--no-origin-check`). Verified by the apfel server
  security notes: HA's server-to-server requests carry no `Origin` header, so the origin check is
  a no-op for the real traffic and still blocks hypothetical browser-origin abuse.
- `etc/apfel-home-assistant.conf` is mode `0600` on write. The token is in a file readable only by
  the owning user.

### MCP / future extensions

The conf format is shell-sourced `KEY=VALUE` with room for additional keys. Extending to MCP
requires: (a) adding `MCP_SERVER=` (and optionally `MCP_TIMEOUT=`) to the conf template, (b)
making the launcher export `APFEL_MCP` / `APFEL_MCP_TIMEOUT` when set, (c) extending `setup` to
optionally configure an MCP server path. No breaking changes to users who don't set these keys.
