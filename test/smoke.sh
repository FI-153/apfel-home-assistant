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

token_of() { awk -F= '/^TOKEN=/{print $2}' "$1"; }

echo "== setup --force overwrites"
OLD_TOKEN="$(token_of "$APFEL_HA_CONF")"
"$REPO_ROOT/bin/apfel-home-assistant" setup --force >/dev/null
NEW_TOKEN="$(token_of "$APFEL_HA_CONF")"
[[ "$OLD_TOKEN" != "$NEW_TOKEN" ]]

echo "== show-config"
SHOW_CONFIG_OUT="$("$REPO_ROOT/bin/apfel-home-assistant" show-config)"
echo "$SHOW_CONFIG_OUT" | grep -q "apple-foundationmodel"
echo "$SHOW_CONFIG_OUT" | grep -q "Extended OpenAI Conversation" \
  || { echo "FAIL: show-config output missing 'Extended OpenAI Conversation'" >&2; exit 1; }

echo "== rotate-token"
BEFORE="$(token_of "$APFEL_HA_CONF")"
"$REPO_ROOT/bin/apfel-home-assistant" rotate-token >/dev/null
AFTER="$(token_of "$APFEL_HA_CONF")"
[[ "$BEFORE" != "$AFTER" ]]

echo "== launcher execs apfel with config"
mkdir -p "$TMP/bin"
export APFEL_STUB_OUT="$TMP/apfel-args"
cat >"$TMP/bin/apfel" <<'STUB'
#!/bin/bash
{
  echo "ARGS=$*"
  echo "HOST=$APFEL_HOST"
  echo "PORT=$APFEL_PORT"
  echo "TOKEN=$APFEL_TOKEN"
} >"$APFEL_STUB_OUT"
STUB
chmod +x "$TMP/bin/apfel"

PATH="$TMP/bin:$PATH" "$REPO_ROOT/libexec/apfel-home-assistant-run"

args_of() { awk -F= '/^ARGS=/{print $2}' "$1"; }
host_of() { awk -F= '/^HOST=/{print $2}' "$1"; }
port_of() { awk -F= '/^PORT=/{print $2}' "$1"; }

[[ "$(args_of "$APFEL_STUB_OUT")" = "--serve --permissive" ]]
[[ "$(host_of "$APFEL_STUB_OUT")" = "$(host_of "$APFEL_HA_CONF")" ]]
[[ "$(port_of "$APFEL_STUB_OUT")" = "$(port_of "$APFEL_HA_CONF")" ]]
[[ "$(token_of "$APFEL_STUB_OUT")" = "$(token_of "$APFEL_HA_CONF")" ]]

echo "== launcher rejects missing conf"
rm "$APFEL_HA_CONF"
if "$REPO_ROOT/libexec/apfel-home-assistant-run" 2>/dev/null; then
  echo "FAIL: launcher should reject missing conf" >&2
  exit 1
fi

echo "== all smoke checks passed"
