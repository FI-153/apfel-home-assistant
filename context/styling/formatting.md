# Formatting and Style

Because this repository is planned as a Homebrew formula wrapping [apfel](https://github.com/Arthur-Ficial/apfel), the style rules below target the two languages that will dominate the codebase: **Ruby** (the Homebrew formula) and **Shell** (any launcher/wrapper scripts).

## Linters

### Homebrew formula

- Tool: `brew audit --strict --online` (built into Homebrew)
- Additional: `brew style` (runs RuboCop with Homebrew's cop configuration)
- Run locally before opening a tap PR.

### Shell scripts

- Tool: `shellcheck`
- Config: `.shellcheckrc` at repo root (TODO — add when first script is written)
- Run: `shellcheck path/to/script.sh`

## Conventions

- TODO — naming conventions (formula class name, executable names, brew service labels).
- TODO — docstring/comment policy for Ruby and shell.
- TODO — file organization (top-level `Formula/` vs a single formula file, `bin/` for wrappers, `libexec/` for helpers).
- TODO — any disabled Homebrew cops and the reason why.
- TODO — shell dialect (`/bin/bash` vs `/bin/sh`) and `set -euo pipefail` policy.
