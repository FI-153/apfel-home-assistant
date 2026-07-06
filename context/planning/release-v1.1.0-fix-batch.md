# Plan: v1.1.0 Fix Batch — Bugs, Test/CI Gaps, Docs

> **Date**: 2026-07-06
> **Scope**: All findings from the 2026-07-06 repo review, grouped in three categories (bug fixes, test/CI gaps, docs), implemented by parallel subagents on disjoint file sets, released as v1.1.0.
> **Prerequisite**: None. Work happens on branch `fix/v1.1.0-batch` (no worktrees, per explicit instruction).

---

## Context

A full repo review (2026-07-06) found ten issues. The launcher contract with apfel v1.8.0
(`APFEL_HOST`/`APFEL_PORT`/`APFEL_TOKEN`, `--serve --permissive`) was verified valid, and the
release pipeline is green through v1.0.0 — but the CLI has four behavioral bugs, the test
suite misses the launcher's core wiring, CI skips pull requests, and the docs have gaps
(stale CLAUDE.md TODOs, uninstall leaves the token on disk).

---

## Overview

```
fix/v1.1.0-batch (branch off main)
│
├── Agent A: bin/apfel-home-assistant          (bug fixes, CLI)
├── Agent B: packaging/formula.rb.template     (bug fix + formula test)
├── Agent C: test/smoke.sh, .github/workflows/test.yml   (test/CI gaps)
└── Agent D: README.md, CLAUDE.md              (docs)
        │
        ▼
verify (shellcheck + ./test/smoke.sh) → commit per category → push branch
        → PR → merge to main → tag v1.1.0 → release.yml publishes
```

Agents run in parallel; file sets are fully disjoint, so no coordination is needed.
The three review categories map to four agents only because `packaging/formula.rb.template`
appears in two categories — it gets a single owner (Agent B) to avoid same-file edits.

---

## Design

### Agent A — `bin/apfel-home-assistant` (bug fixes)

1. **Port stability on re-setup.** Today `cmd_setup` always calls `pick_port`, so a
   `setup --force` while the service is running sees apfel occupying its own port and
   silently drifts to the next one, breaking the Home Assistant base URL. New behavior:
   when the conf already has a `PORT`, reuse it if the port is free **or** the listening
   process is `apfel` itself (checked via `lsof -iTCP:"$port" -sTCP:LISTEN` process name).
   Only pick a new port when the existing one is held by a foreign process, or on fresh setup.
2. **HOST preservation.** `setup --force` currently resets `HOST` to `0.0.0.0`, discarding a
   deliberate `127.0.0.1` (the documented same-host posture in
   `context/knowledge/apfel-server-security.md`). New behavior: keep an existing non-empty
   `HOST`; default `0.0.0.0` only on fresh setup.
3. **LAN IP detection.** `get_lan_ip` only tries `en0`/`en1`; USB-C/Thunderbolt Ethernet
   (`en4`+) gets the placeholder. New behavior: resolve the default-route interface via
   `route -n get default | awk '/interface:/{print $2}'` first, then fall back to
   `en0`/`en1`, then the placeholder.
4. **Integration name typo.** Setup output says `"OpenAI Extended Conversation"`; the correct
   name (used everywhere else, and what users search for) is `"Extended OpenAI Conversation"`.
5. **Restart wording.** Setup's next-steps block says `brew services start`; after a
   re-setup the service is already running and needs `restart`. Since `restart` also starts
   a stopped service, print `restart` unconditionally.

### Agent B — `packaging/formula.rb.template` (bug fix + formula test)

1. **Crash-loop on unconfigured start.** The formula ships a conf with an empty `TOKEN` and
   `keep_alive true`; starting the service before `setup` makes launchd respawn the failing
   launcher every ~10s forever. Change to `keep_alive crashed: true`: restart on real
   crashes, but a deliberate non-zero exit (missing token) stops cleanly with the error in
   the log. `brew audit --strict` in the release pipeline validates the DSL.
2. **Meaningful `test do` block.** Beyond `--help`, run `setup` with `APFEL_HA_CONF`
   pointed into `testpath` and assert the conf is written with a 64-hex token, then assert
   `show-config` prints the model id `apple-foundationmodel`.

### Agent C — `test/smoke.sh` + `.github/workflows/test.yml` (test/CI gaps)

1. **Launcher happy path.** smoke.sh stops before the `exec apfel` line — the product's
   core wiring is untested. Add a stub `apfel` executable in a temp dir prepended to
   `PATH` that dumps its argv and the `APFEL_*` environment to a file; run the launcher
   with a valid conf and assert it received `--serve --permissive` and the exported
   `APFEL_HOST`/`APFEL_PORT`/`APFEL_TOKEN` values from the conf.
2. **PR trigger.** `test.yml` only fires on pushes to `develop`/`main`, so pull requests get
   zero CI. Add a `pull_request:` trigger (keep the existing push triggers).

### Agent D — `README.md` + `CLAUDE.md` (docs)

1. **Uninstall completeness.** `brew uninstall` leaves
   `$(brew --prefix)/etc/apfel-home-assistant.conf` — including the API token — on disk.
   Add the removal line to the README's Uninstall section.
2. **CLAUDE.md TODOs.** Fill the stale sections with what now exists: Build & Run (CLI
   commands, `make` targets), Testing (`make test` → `test/smoke.sh`), Linting
   (`shellcheck` on the three scripts, `brew audit --strict` in the release pipeline),
   Architecture (bin CLI + libexec launcher + etc conf + Homebrew formula + tag-driven
   release pipeline), Key Patterns (bash strict mode, sourced-conf contract, 0600 perms).

### Verification & release

After all agents finish: `shellcheck` on the three scripts, `./test/smoke.sh`, and a manual
diff review. Commits grouped by category (bugs / tests-CI / docs, plus this plan). Then:
push branch → PR → merge to `main` → `git tag v1.1.0` on main → push tag →
`release.yml` re-runs the smoke test, builds the tarball, audits the rendered formula,
creates the GitHub release, and pushes the formula to `FI-153/homebrew-tap`.

---

## Edge Cases & Constraints

- **Existing smoke assertions must keep passing.** Fresh setup still writes
  `HOST=0.0.0.0` and a free port, so `smoke.sh`'s current greps hold after Agent A's changes.
- **Port-reuse check degrades safely.** If `lsof` output is unparsable, the reuse check
  fails closed (treats the port as foreign) and falls back to `pick_port` — worst case is
  today's behavior.
- **`keep_alive crashed: true` trade-off.** apfel exiting non-zero on a transient runtime
  error will no longer be auto-restarted (only genuine crashes are). Accepted: the
  alternative is the infinite respawn loop on a merely unconfigured install.
- **Formula `test do` runs sandboxed.** `pick_port`'s `lsof` may error in the sandbox; the
  script treats that as "port free", so `setup` still completes. The test asserts conf
  contents, not port choice.
- **No worktrees.** All agents edit the same checkout on branch `fix/v1.1.0-batch`; file
  sets are disjoint by construction.
- **Release gate.** The tag must be reachable from `main` — the pipeline verifies this —
  so the branch must be merged before tagging.

---

## Implementation Steps

- [x] Create branch `fix/v1.1.0-batch` off `main`
- [x] Dispatch Agents A–D in parallel (Opus, disjoint file sets)
- [x] Verify: `shellcheck bin/apfel-home-assistant libexec/apfel-home-assistant-run test/smoke.sh`
- [x] Verify: `./test/smoke.sh` passes
- [x] Review full diff against this design
- [x] Commit in category groups (plan, bugs, tests-CI, docs)
- [ ] Push branch, open PR, merge to `main`
- [ ] Tag `v1.1.0` on `main`, push tag
- [ ] Watch `release.yml` to completion (GitHub release + tap formula updated)
