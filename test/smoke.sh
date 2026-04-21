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
"$REPO_ROOT/bin/apfel-home-assistant" show-config | grep -q "apple-foundationmodel"

echo "== rotate-token"
BEFORE="$(token_of "$APFEL_HA_CONF")"
"$REPO_ROOT/bin/apfel-home-assistant" rotate-token >/dev/null
AFTER="$(token_of "$APFEL_HA_CONF")"
[[ "$BEFORE" != "$AFTER" ]]

echo "== launcher rejects missing conf"
rm "$APFEL_HA_CONF"
if "$REPO_ROOT/libexec/apfel-home-assistant-run" 2>/dev/null; then
  echo "FAIL: launcher should reject missing conf" >&2
  exit 1
fi

echo "== all smoke checks passed"
