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

---

## Implementation

> Execution conventions:
> - Each step is atomic. Check boxes `- [x]` as they complete.
> - Commit points are marked `COMMIT:` — per project git policy, the assistant asks before
>   running `git commit` each time.
> - `$PREFIX` = `$(brew --prefix)` (i.e. `/opt/homebrew` on Apple Silicon).
> - All paths below are relative to the repo root unless absolute.

### Phase 1 — Source repo scaffolding

#### Task 1.1: Baseline files

**Files:**
- Create: `.gitignore`
- Create: `LICENSE` (MIT — matches `wyoming-apple-stt`)
- Create: `README.md`

- [ ] **Step 1.1.1** — Create `.gitignore`:

```
.DS_Store
dist/
*.tar.gz
```

- [ ] **Step 1.1.2** — Create `LICENSE` (MIT, copyright "Federico Imberti", year 2026).

- [ ] **Step 1.1.3** — Create `README.md` with a minimal quick-start block:

```markdown
# apfel-home-assistant

Homebrew formula that runs [apfel](https://github.com/Arthur-Ficial/apfel) pre-configured as a
conversation backend for [Home Assistant](https://www.home-assistant.io/) via the community
**OpenAI Extended Conversation** integration.

## Install

    brew install FI-153/tap/apfel-home-assistant
    apfel-home-assistant setup
    brew services start apfel-home-assistant

`setup` prints the exact Base URL, API Key, and Model ID to paste into Home Assistant.
```

Keep the README intentionally short; the design doc in `context/planning/` is the reference.

- [ ] **Step 1.1.4 — COMMIT:** `chore: add LICENSE, README, .gitignore`

---

#### Task 1.2: Launcher (`libexec/apfel-home-assistant-run`)

Written first because the CLI's `setup` ultimately produces the inputs this consumes — easier to
reason about the conf contract in the narrow launcher than in the broader CLI.

**Files:**
- Create: `libexec/apfel-home-assistant-run`

- [ ] **Step 1.2.1** — Create `libexec/apfel-home-assistant-run`:

```bash
#!/bin/bash
set -euo pipefail

CONF="${APFEL_HA_CONF:-$(brew --prefix)/etc/apfel-home-assistant.conf}"

if [[ ! -f "$CONF" ]]; then
  echo "apfel-home-assistant: config not found at $CONF" >&2
  echo "Run: apfel-home-assistant setup" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONF"

: "${HOST:?HOST missing in $CONF}"
: "${PORT:?PORT missing in $CONF}"
: "${TOKEN:?TOKEN missing in $CONF — run: apfel-home-assistant setup}"

if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
  echo "apfel-home-assistant: PORT=$PORT is not numeric in $CONF" >&2
  exit 1
fi

export APFEL_HOST="$HOST"
export APFEL_PORT="$PORT"
export APFEL_TOKEN="$TOKEN"

exec apfel --serve
```

Notes:
- `APFEL_HA_CONF` env-var override exists purely for `test/` smoke tests to pass in a throwaway
  conf path; production installs always resolve via `brew --prefix`.
- `source` on an untrusted file is unsafe in general; here the conf is mode 0600 and written
  exclusively by our own CLI, so arbitrary-code-execution risk is equivalent to "the user's own
  shell runs their own shell".

- [ ] **Step 1.2.2** — `chmod 0755 libexec/apfel-home-assistant-run`.

- [ ] **Step 1.2.3** — Manual verification: with no conf present, run the launcher and confirm it
  exits non-zero with the "config not found" message. With a fake conf having `TOKEN=` empty,
  confirm it exits with the "TOKEN missing" message.

- [ ] **Step 1.2.4 — COMMIT:** `feat: add launcher that execs apfel with conf-derived env`

---

#### Task 1.3: CLI skeleton (`bin/apfel-home-assistant`)

**Files:**
- Create: `bin/apfel-home-assistant`

- [ ] **Step 1.3.1** — Create `bin/apfel-home-assistant` with `--help`, `-h`, and subcommand
  dispatch for `setup`, `show-config`, `rotate-token`. Unknown subcommand prints usage to stderr
  and exits 2:

```bash
#!/bin/bash
set -euo pipefail

CONF="${APFEL_HA_CONF:-$(brew --prefix)/etc/apfel-home-assistant.conf}"

usage() {
  cat <<EOF
Usage: apfel-home-assistant <command>

Commands:
  setup           First-time configuration: pick a port, mint a token, print HA block.
  show-config     Print the Home Assistant integration block from the current config.
  rotate-token    Generate a new API token and print the new HA block.
  --help, -h      Show this help.

Config file: $CONF
EOF
}

cmd="${1:-}"
case "$cmd" in
  setup)        shift; cmd_setup "$@" ;;
  show-config)  shift; cmd_show_config "$@" ;;
  rotate-token) shift; cmd_rotate_token "$@" ;;
  -h|--help|"") usage; exit 0 ;;
  *)            echo "unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
```

(The `cmd_*` functions are added by subsequent tasks. The case statement above is the final
shape; later tasks only add function definitions above the case.)

- [ ] **Step 1.3.2** — `chmod 0755 bin/apfel-home-assistant`.

- [ ] **Step 1.3.3** — Verify `bin/apfel-home-assistant --help` prints usage and exits 0.
  Verify `bin/apfel-home-assistant bogus` prints error + usage on stderr and exits 2.

  > At this point `cmd_setup` / `cmd_show_config` / `cmd_rotate_token` don't exist — invoking
  > those subcommands would fail with "command not found". That's expected; they land in the
  > next tasks. Only `--help` and the unknown-command path are exercised here.

- [ ] **Step 1.3.4 — COMMIT:** `feat: add apfel-home-assistant CLI skeleton with subcommand dispatch`

---

#### Task 1.4: `show-config` subcommand

Implemented before `setup` because `setup` ends by calling into `show-config`'s printer, and
having it exist first makes the `setup` implementation a straight compose.

**Files:**
- Modify: `bin/apfel-home-assistant`

- [ ] **Step 1.4.1** — Insert above the `case` block in `bin/apfel-home-assistant`:

```bash
# Print the HA integration block using values from the config file.
cmd_show_config() {
  if [[ ! -f "$CONF" ]]; then
    echo "apfel-home-assistant: no config at $CONF" >&2
    echo "Run: apfel-home-assistant setup" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$CONF"
  : "${HOST:?HOST missing in $CONF}"
  : "${PORT:?PORT missing in $CONF}"
  : "${TOKEN:?TOKEN missing in $CONF — run: apfel-home-assistant setup}"

  local lan_ip
  lan_ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  if [[ -z "$lan_ip" ]]; then
    lan_ip="<your-mac-lan-ip>"
  fi

  cat <<EOF
Home Assistant — OpenAI Extended Conversation integration:

  Base URL:  http://$lan_ip:$PORT/v1
  API Key:   $TOKEN
  Model:     apple-foundationmodel

After changing config, restart the service:
  brew services restart apfel-home-assistant
EOF
}
```

- [ ] **Step 1.4.2** — Manual verification: write a fake conf (`HOST=0.0.0.0`, `PORT=11435`,
  `TOKEN=deadbeef`) to a temp path, `APFEL_HA_CONF=/tmp/fake.conf bin/apfel-home-assistant show-config`,
  confirm output contains `http://<ip-or-placeholder>:11435/v1`, `deadbeef`, and
  `apple-foundationmodel`.

- [ ] **Step 1.4.3 — COMMIT:** `feat: add show-config subcommand`

---

#### Task 1.5: `setup` subcommand

**Files:**
- Modify: `bin/apfel-home-assistant`

- [ ] **Step 1.5.1** — Add helper functions above the `case` block in `bin/apfel-home-assistant`:

```bash
# Return 0 if the TCP port is free (nobody listening), 1 otherwise.
port_is_free() {
  local port="$1"
  ! lsof -iTCP:"$port" -sTCP:LISTEN -nP -t >/dev/null 2>&1
}

# Echo the first free port in the preferred list, or exit non-zero if none free.
pick_port() {
  for p in 11434 11435 11436 11437; do
    if port_is_free "$p"; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

cmd_setup() {
  local force=0
  for arg in "$@"; do
    case "$arg" in
      --force|-f) force=1 ;;
      *) echo "unknown flag: $arg" >&2; return 2 ;;
    esac
  done

  if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    local existing_token=""
    existing_token="$(grep -E '^TOKEN=' "$CONF" | cut -d= -f2- || true)"
    if [[ -n "$existing_token" && $force -ne 1 ]]; then
      echo "apfel-home-assistant: $CONF already has a token." >&2
      echo "Use 'apfel-home-assistant show-config' to view it," >&2
      echo "or re-run with --force to overwrite." >&2
      return 1
    fi
  fi

  local port
  if ! port="$(pick_port)"; then
    echo "apfel-home-assistant: ports 11434–11437 are all in use." >&2
    echo "Edit PORT in $CONF manually, then run: apfel-home-assistant show-config" >&2
    return 1
  fi
  echo "→ Selected port: $port"

  echo "→ Generating token..."
  local token
  token="$(openssl rand -hex 32)"

  local conf_dir
  conf_dir="$(dirname "$CONF")"
  mkdir -p "$conf_dir"

  umask 077
  cat > "$CONF" <<EOF
# apfel-home-assistant configuration
# Edit manually only if you know what you're doing.
# Normal workflow: \`apfel-home-assistant setup\` / \`rotate-token\`.
# Restart after editing: \`brew services restart apfel-home-assistant\`.

HOST=0.0.0.0
PORT=$port
TOKEN=$token
EOF
  chmod 0600 "$CONF"

  echo "→ Wrote $CONF (mode 0600)"
  echo
  echo "Next steps:"
  echo "  1. Start the server:"
  echo "       brew services start apfel-home-assistant"
  echo
  echo "  2. In Home Assistant, add the \"OpenAI Extended Conversation\" integration with:"
  echo
  cmd_show_config | sed -n '/^  Base URL:/,/^  Model:/p' | sed 's/^/    /'
}
```

Note: the second-half block reuses `show-config`'s output to print only the three HA-integration
lines; the full `show-config` output is slightly more verbose (includes the restart reminder),
and `setup` adds its own "Next steps" framing.

- [ ] **Step 1.5.2** — Manual verification on a throwaway conf path:

```bash
APFEL_HA_CONF=/tmp/aha-test.conf bin/apfel-home-assistant setup
cat /tmp/aha-test.conf    # expect HOST=0.0.0.0, numeric PORT, 64-hex TOKEN
stat -f "%p" /tmp/aha-test.conf   # last three digits: 600
```

Re-run without `--force`: expect refusal with "already has a token". Re-run with `--force`:
expect a fresh token. Delete the file when done.

- [ ] **Step 1.5.3 — COMMIT:** `feat: add setup subcommand with port probe and token mint`

---

#### Task 1.6: `rotate-token` subcommand

**Files:**
- Modify: `bin/apfel-home-assistant`

- [ ] **Step 1.6.1** — Insert above the `case` block in `bin/apfel-home-assistant`:

```bash
cmd_rotate_token() {
  if [[ ! -f "$CONF" ]]; then
    echo "apfel-home-assistant: no config at $CONF" >&2
    echo "Run: apfel-home-assistant setup" >&2
    return 1
  fi

  local new_token
  new_token="$(openssl rand -hex 32)"

  # Rewrite TOKEN line, preserving the rest of the file.
  local tmp
  tmp="$(mktemp)"
  awk -v t="$new_token" '
    /^TOKEN=/ { print "TOKEN=" t; next }
    { print }
  ' "$CONF" > "$tmp"
  chmod 0600 "$tmp"
  mv "$tmp" "$CONF"

  echo "→ Token rotated. New config:"
  echo
  cmd_show_config
  echo
  echo "Restart the service to pick up the new token:"
  echo "  brew services restart apfel-home-assistant"
}
```

- [ ] **Step 1.6.2** — Manual verification: after a `setup` into a throwaway conf, run
  `rotate-token`, diff the conf before/after, confirm only the `TOKEN=` line changed and the new
  value is a fresh 64-hex string.

- [ ] **Step 1.6.3 — COMMIT:** `feat: add rotate-token subcommand`

---

#### Task 1.7: Smoke-test script

**Files:**
- Create: `test/smoke.sh`

- [ ] **Step 1.7.1** — Create `test/smoke.sh`:

```bash
#!/bin/bash
# Lightweight end-to-end check for the CLI + launcher, no Homebrew involved.
# Does NOT start apfel; stops at the point the launcher would exec it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export APFEL_HA_CONF="$TMP/conf"

echo "== help"
"$REPO_ROOT/bin/apfel-home-assistant" --help | grep -q "Usage: apfel-home-assistant"

echo "== setup"
"$REPO_ROOT/bin/apfel-home-assistant" setup >/dev/null
grep -q '^HOST=0.0.0.0$' "$APFEL_HA_CONF"
grep -qE '^PORT=[0-9]+$' "$APFEL_HA_CONF"
grep -qE '^TOKEN=[0-9a-f]{64}$' "$APFEL_HA_CONF"
[[ "$(stat -f "%Lp" "$APFEL_HA_CONF")" = "600" ]]

echo "== setup refuses to overwrite"
if "$REPO_ROOT/bin/apfel-home-assistant" setup 2>/dev/null; then
  echo "FAIL: setup should refuse without --force" >&2
  exit 1
fi

echo "== setup --force overwrites"
OLD_TOKEN="$(grep '^TOKEN=' "$APFEL_HA_CONF" | cut -d= -f2)"
"$REPO_ROOT/bin/apfel-home-assistant" setup --force >/dev/null
NEW_TOKEN="$(grep '^TOKEN=' "$APFEL_HA_CONF" | cut -d= -f2)"
[[ "$OLD_TOKEN" != "$NEW_TOKEN" ]]

echo "== show-config"
"$REPO_ROOT/bin/apfel-home-assistant" show-config | grep -q "apple-foundationmodel"

echo "== rotate-token"
BEFORE="$(grep '^TOKEN=' "$APFEL_HA_CONF")"
"$REPO_ROOT/bin/apfel-home-assistant" rotate-token >/dev/null
AFTER="$(grep '^TOKEN=' "$APFEL_HA_CONF")"
[[ "$BEFORE" != "$AFTER" ]]

echo "== launcher rejects missing conf"
rm "$APFEL_HA_CONF"
if "$REPO_ROOT/libexec/apfel-home-assistant-run" 2>/dev/null; then
  echo "FAIL: launcher should reject missing conf" >&2
  exit 1
fi

echo "== all smoke checks passed"
```

- [ ] **Step 1.7.2** — `chmod 0755 test/smoke.sh`.

- [ ] **Step 1.7.3** — Run `./test/smoke.sh` and confirm "all smoke checks passed".

- [ ] **Step 1.7.4 — COMMIT:** `test: add end-to-end smoke script for CLI + launcher`

---

### Phase 2 — Release packaging

#### Task 2.1: `Makefile` for release tarballs

**Files:**
- Create: `Makefile`

- [ ] **Step 2.1.1** — Create `Makefile`:

```make
NAME    := apfel-home-assistant
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)
DIST    := dist
TARBALL := $(DIST)/$(NAME)-$(VERSION).tar.gz

.PHONY: tarball sha256 clean test

tarball:
	@mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=$(NAME)-$(VERSION)/ -o $(TARBALL) HEAD
	@echo "built $(TARBALL)"

sha256: tarball
	@shasum -a 256 $(TARBALL)

test:
	./test/smoke.sh

clean:
	rm -rf $(DIST)
```

- [ ] **Step 2.1.2** — Verify: `make test` passes; `make tarball` produces a `.tar.gz` under
  `dist/`; `make sha256` prints a 64-hex digest.

- [ ] **Step 2.1.3 — COMMIT:** `chore: add Makefile for tarball + sha256`

---

#### Task 2.2: Tag v0.1.0 and cut local tarball

- [ ] **Step 2.2.1** — `git tag -a v0.1.0 -m "v0.1.0 — initial release"` (ask user to confirm
  before tagging; no remote yet, so no push).

- [ ] **Step 2.2.2** — `make sha256`. Record the digest as `V0_1_0_SHA256` — the formula needs it.

---

### Phase 3 — Homebrew formula

> All paths in this phase are in the sibling repo `../homebrew-tap/`.

#### Task 3.1: Formula file

**Files:**
- Create: `../homebrew-tap/Formula/apfel-home-assistant.rb`

- [ ] **Step 3.1.1** — Create the formula, mirroring `wyoming-apple-stt.rb`'s structure:

```ruby
class ApfelHomeAssistant < Formula
  desc "Run apfel pre-configured as a Home Assistant conversation backend"
  homepage "https://github.com/FI-153/apfel-home-assistant"
  url "https://github.com/FI-153/apfel-home-assistant/releases/download/v0.1.0/apfel-home-assistant-0.1.0.tar.gz"
  version "0.1.0"
  sha256 "REPLACE_WITH_V0_1_0_SHA256"
  license "MIT"

  depends_on "arthur-ficial/tap/apfel"
  depends_on macos: :tahoe

  def install
    bin.install "bin/apfel-home-assistant"
    libexec.install "libexec/apfel-home-assistant-run"
    chmod 0755, libexec/"apfel-home-assistant-run"

    conf = etc/"apfel-home-assistant.conf"
    unless conf.exist?
      conf.write <<~EOS
        # apfel-home-assistant configuration
        # Edit manually only if you know what you're doing.
        # Normal workflow: `apfel-home-assistant setup` / `rotate-token`.
        # Restart after editing: `brew services restart apfel-home-assistant`.

        HOST=0.0.0.0
        PORT=11434
        TOKEN=
      EOS
      chmod 0600, conf
    end
  end

  service do
    run [opt_libexec/"apfel-home-assistant-run"]
    keep_alive true
    log_path var/"log/apfel-home-assistant.log"
    error_log_path var/"log/apfel-home-assistant.log"
  end

  test do
    assert_match "Usage: apfel-home-assistant",
                 shell_output("#{bin}/apfel-home-assistant --help")
    assert_predicate libexec/"apfel-home-assistant-run", :executable?
  end
end
```

- [ ] **Step 3.1.2** — Replace `REPLACE_WITH_V0_1_0_SHA256` with the digest from step 2.2.2.

- [ ] **Step 3.1.3 — COMMIT (in `homebrew-tap`):** `feat: add apfel-home-assistant formula`

---

#### Task 3.2: Install from local source + verify

Until the source release is pushed to GitHub, the formula's `url` points at a nonexistent
tarball. Bypass that with `HOMEBREW_NO_INSTALL_FROM_API=1` and a local tap install.

- [ ] **Step 3.2.1** — From anywhere: `brew tap FI-153/tap ~/GitHub/homebrew-tap` (points the
  `FI-153/tap` name at the local checkout).

- [ ] **Step 3.2.2** — `brew install --build-from-source FI-153/tap/apfel-home-assistant`.

  If the `url`/`sha256` aren't yet reachable (no GitHub release published), create a local
  tarball at the expected path via `make tarball` and set `HOMEBREW_ARTIFACT_DOMAIN` to point
  at a `file://` URL for the same path — or just edit the formula's `url` to a local `file://`
  for this verification step only, then revert before publishing.

- [ ] **Step 3.2.3** — `brew audit --strict apfel-home-assistant`. Fix any issues reported.
  Expected common fixes: `desc` wording, license SPDX, homepage scheme.

- [ ] **Step 3.2.4** — `brew test apfel-home-assistant`. Expected: `Usage:` assertion passes,
  launcher executable assertion passes.

---

#### Task 3.3: End-to-end real run

- [ ] **Step 3.3.1** — `apfel-home-assistant setup`. Confirm: terminal shows a port, token,
  Base URL with a real LAN IP, and the model ID. Confirm `$(brew --prefix)/etc/apfel-home-assistant.conf`
  exists with mode 0600.

- [ ] **Step 3.3.2** — `brew services start apfel-home-assistant`. Confirm
  `brew services info apfel-home-assistant` shows status `started`.

- [ ] **Step 3.3.3** — Smoke the endpoint:

```bash
source "$(brew --prefix)/etc/apfel-home-assistant.conf"
curl -sf "http://127.0.0.1:${PORT}/health" | grep -q '"status":"ok"'
curl -sf "http://127.0.0.1:${PORT}/v1/models" \
  -H "Authorization: Bearer ${TOKEN}" | grep -q "apple-foundationmodel"
```

Both should succeed. `/v1/models` without the token should return `401`.

- [ ] **Step 3.3.4** — `tail -f $(brew --prefix)/var/log/apfel-home-assistant.log` shows apfel's
  normal startup line and zero restart loops.

- [ ] **Step 3.3.5** — In Home Assistant (on the separate device), add the **OpenAI Extended
  Conversation** integration with the Base URL, API Key, and Model from step 3.3.1. Send a test
  prompt. Confirm a response comes back.

- [ ] **Step 3.3.6** — `brew services stop apfel-home-assistant`; confirm clean stop.

---

#### Task 3.4: Publish

- [ ] **Step 3.4.1** — Create a GitHub repo `FI-153/apfel-home-assistant`, push `main` + `v0.1.0`
  tag (user runs this step; assistant does not push autonomously).

- [ ] **Step 3.4.2** — Attach `dist/apfel-home-assistant-0.1.0.tar.gz` as the v0.1.0 release
  asset on GitHub. Verify the `url` in the formula resolves.

- [ ] **Step 3.4.3** — If the sha256 of the uploaded asset differs from the local tarball's
  (shouldn't, but verify), update the formula and re-commit in `homebrew-tap`.

- [ ] **Step 3.4.4** — Push `homebrew-tap` changes.

- [ ] **Step 3.4.5** — Clean-machine install test (optional but valuable): on a second Mac, or
  after `brew uninstall apfel-home-assistant && brew untap FI-153/tap`, run:

```bash
brew install FI-153/tap/apfel-home-assistant
apfel-home-assistant setup
brew services start apfel-home-assistant
```

Confirm the same end-to-end path works against the real published tap + release.

---

### Self-review against the spec

- **Config-only vs wrapper+config decision (Section 1, Q1=B):** Task 1.3 onward builds the CLI wrapper. ✓
- **Token lifecycle (Q2=A, setup-time):** Task 1.5. ✓
- **Deployment (Q3=C, LAN + token, origin check on):** launcher (Task 1.2) exports `APFEL_HOST=0.0.0.0` + `APFEL_TOKEN` and passes no `--no-origin-check`. ✓
- **Lifecycle (Q4=A, pure brew services):** Formula `service do` block (Task 3.1), no launchctl calls from the CLI. ✓
- **Port conflict handling:** Port probe in Task 1.5. ✓
- **setup prints token + IP + model:** Task 1.5 delegates to `show-config`, which is fully implemented in Task 1.4. ✓
- **rotate-token / show-config subcommands:** Tasks 1.6 and 1.4. ✓
- **Security: 0600 conf, token not masked:** Task 1.5 `umask 077` + `chmod 0600`; Task 1.4 prints unmasked token. ✓
- **wyoming-apple-stt formula pattern:** Task 3.1 follows it structurally. ✓
- **MCP deferral:** No MCP tasks — matches "deferred" in the design. ✓
