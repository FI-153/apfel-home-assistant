# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Policy

**Never commit code autonomously.** Always wait for the user to explicitly ask for a commit before running any `git commit`, `git add`, or `git push` commands.

## Project Overview

`apfel-home-assistant` is a wrapper around [apfel](https://github.com/Arthur-Ficial/apfel) that connects [Home Assistant](https://www.home-assistant.io/) to Apple Intelligence's on-device foundation model. The goal is to let Home Assistant use Apple's free, local LLM (via apfel's OpenAI-compatible server on macOS) as its conversation/assist backend — no cloud, no API keys, no downloads. Distribution is planned via a Homebrew formula that wraps and configures apfel for the Home Assistant integration path.

## Build & Run

Nothing to compile — everything is bash and runs in place. `bin/apfel-home-assistant` is the
user-facing CLI:

- `apfel-home-assistant setup` — pick a free port, mint a token, write the conf, print the HA block.
- `apfel-home-assistant show-config` — reprint the Home Assistant integration block.
- `apfel-home-assistant rotate-token` — mint a fresh API token.

The `Makefile` wraps the dev/release chores:

- `make help` — list targets (default).
- `make test` — run `test/smoke.sh` against the working tree.
- `make tarball` — build `dist/apfel-home-assistant-<version>.tar.gz` from HEAD.
- `make sha256` — print the tarball's sha256 (builds it first).
- `make clean` — remove `dist/`.

Local install is via the Homebrew tap:

```bash
brew tap FI-153/tap
brew install apfel-home-assistant
```

### Testing

`make test` runs `test/smoke.sh` — an end-to-end check of the CLI and launcher (setup, refuse
overwrite, `--force`, show-config, rotate-token, launcher rejects missing conf). It needs neither
Homebrew nor apfel: it uses `APFEL_HA_CONF` to point at a temp conf and stops at the point the
launcher would `exec apfel`. CI runs the same script via `.github/workflows/test.yml` on pushes to
`develop`/`main` and on pull requests, and again inside the release pipeline before publishing.

### Linting

Run `shellcheck` on the three shell scripts: `bin/apfel-home-assistant`,
`libexec/apfel-home-assistant-run`, and `test/smoke.sh`. CI enforces both linters on every push
and pull request: `.github/workflows/test.yml` runs shellcheck and `brew audit --strict` against
the template rendered with placeholder values; the release pipeline audits again with the real
URL and sha256 before publishing.

## Requirements

- **Platform:** macOS 26 Tahoe or newer, Apple Silicon (M1+) — inherited from apfel's requirements.
- **Dependency:** [apfel](https://github.com/Arthur-Ficial/apfel) installed and runnable (`apfel --serve`).
- **Runtime target:** Home Assistant instance (local or remote) capable of pointing at an OpenAI-compatible endpoint.

## Architecture

The wrapper is a thin layer between `brew services` and apfel:

1. `bin/apfel-home-assistant` (`setup`) writes the conf at
   `$(brew --prefix)/etc/apfel-home-assistant.conf` (`HOST`/`PORT`/`TOKEN`, mode 0600).
2. `brew services` runs the launcher `libexec/apfel-home-assistant-run` (wired up by the formula's
   `service do` block, with `APFEL_HA_CONF` and `PATH` set).
3. The launcher sources the conf, exports `APFEL_HOST` / `APFEL_PORT` / `APFEL_TOKEN`, and
   `exec`s `apfel --serve --permissive`, exposing the OpenAI-compatible endpoint on the configured
   host/port.
4. Home Assistant talks to that endpoint through the **Extended OpenAI Conversation** integration
   (Base URL `http://<mac-ip>:<port>/v1`, the minted token as API key, model
   `apple-foundationmodel`).

Distribution is a Homebrew formula rendered from `packaging/formula.rb.template` (it declares
`apfel` as a dependency and installs the CLI, launcher, and a `brew services` definition). Releases
are tag-driven: pushing a `v*` tag runs `.github/workflows/release.yml`, which verifies the tag is
on `main`, smoke-tests, builds the tarball, renders the formula (filling in URL + SHA256), runs
`brew audit --strict`, creates the GitHub release, and pushes the formula to the
`FI-153/homebrew-tap`.

## Key Patterns

- Bash scripts use `set -euo pipefail` and must stay bash 3.2 compatible (macOS system bash).
- The conf is a sourceable `KEY=value` file; secrets are written with mode `0600`.
- When not sourcing the conf, values are parsed with `awk` (e.g. reading `TOKEN` in `setup`,
  rewriting it in `rotate-token`).
- The Home Assistant integration name is exactly **Extended OpenAI Conversation**, and the model id
  is `apple-foundationmodel`.
- Releases are tag-driven; the formula is a template (`packaging/formula.rb.template`) rendered by CI,
  never hand-edited in the tap.

## Release Process

Releases are cut by pushing a `v*` tag. The `.github/workflows/release.yml` workflow
handles everything from there — no manual `gh release create`, no hand-edit of the
tap.

### Cutting a release
To release a new version and trigger the CI pipeline you must tag the release from `main` and
push to origin. The tag must point at a commit reachable from `main` — CI verifies this and
refuses to release otherwise.
```bash
git checkout main && git pull
git tag v<X.Y.Z>
git push origin v<X.Y.Z>
```

## Planning Workflow

Whenever the user asks Claude to plan a task, Claude **must** write the plan as a `.md` file inside
`context/planning/` before doing any implementation work. File names must be descriptive kebab-case
(e.g., `add-metrics-extraction.md`). After writing the plan, Claude notifies the user of the file
path and waits for explicit approval before proceeding. The user may edit the plan file directly
using `/user <comment>` annotations; When new additions to the plan are made in response to comments
mark them with `/new`; Delete all the `/new` already present in a plan when updating or adding the
todo list; implementation begins only after the user explicitly approves; Plans are committed to
git alongside code for documentation purposes and are never deleted.

**Asking Questions** ALWAYS ask any clarifying questions you need and avoid assumptions unless
asked otherwise.

**Important**: When writing a plan, include ONLY the architectural design and approach — no
implementation checklists or checkboxes. The user will ask for implementation steps separately
after approving the plan. Do not add execution details, step numbering, or checkbox lists unless
the user explicitly requests them.

**Single file per task**: The design spec and the implementation plan must live in the **same file**
in `context/planning/`. The design sections come first, followed by the implementation steps
appended below. Do not create separate files for the design and the plan.

Once a plan is approved and the user asks for implementation steps, Claude must append the
implementation checklist to the same plan file. After implementation begins, Claude must follow the
checklist in order, checking each box (`- [x]`) immediately upon completing the corresponding task.

### Plan file format

```markdown
# Plan: <Descriptive Title>

> **Date**: YYYY-MM-DD
> **Scope**: <what this plan covers>
> **Prerequisite**: <any plans or work that must be done first>

---

## Context

<Why this work is needed. What exists today. What gap this fills.>

---

## Overview

<High-level architecture diagram (ASCII or Mermaid) showing components and data flow.>

---

## Design

<Detailed design: new modules, classes, methods, data models, protocols.
Reference existing code patterns where relevant.>

---

## Edge Cases & Constraints

<Known limitations, error scenarios, performance considerations.>
```

### Comment and annotation conventions

| Marker | Meaning |
|--------|---------|
| `/user <comment>` | User-written feedback inside the plan file |
| `/new` | Marks new content added in response to `/user` comments |
| `- [ ]` | Implementation step (added only after user asks for steps) |
| `- [x]` | Completed implementation step |

## Superpowers Plugin

Claude **must** use the `superpowers` skill set for structured development work:

- **Brainstorming** (`superpowers:brainstorm`): Use before any creative work — creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements, and design before implementation.
- **Writing Plans** (`superpowers:writing-plans`): Use when there is a spec or requirements for a multi-step task, before touching code. Produces a structured plan in `context/planning/`.
- **Executing Plans** (`superpowers:executing-plans`): Use when there is a written implementation plan to execute, with review checkpoints.
- **Systematic Debugging** (`superpowers:systematic-debugging`): Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes.
- **Dispatching Parallel Agents** (`superpowers:dispatching-parallel-agents`): Use when facing 2+ independent tasks that can be worked on without shared state.
- **Code Review** (`superpowers:requesting-code-review`): Use when completing tasks or implementing major features to verify work meets requirements.
- **Verification** (`superpowers:verification-before-completion`): Use when about to claim work is complete — run verification commands and confirm output before making success claims.

## Formatting and Project Structure

See [`context/styling/formatting.md`](context/styling/formatting.md) for the rules to follow
when writing and formatting code in order to conform to the project's standards.
