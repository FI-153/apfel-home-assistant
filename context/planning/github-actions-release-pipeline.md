# Plan: GitHub Actions Release Pipeline

> **Date**: 2026-04-22
> **Scope**: Automate the full release path for `apfel-home-assistant` — on tag push, the CI builds a tarball, creates a GitHub release, renders a Homebrew formula from a template in this repo, and pushes the updated formula to `FI-153/homebrew-tap`. Model the shape on `../wyoming-apple-stt/.github/workflows/release.yml`.
> **Prerequisite**: v0.1.0 already shipped manually; the formula currently lives hand-maintained in the tap.

---

## Context

Today, shipping a new version is a five-step manual ritual:

1. Build the tarball (`make tarball`).
2. Compute sha256 (`make sha256`).
3. Create the GitHub release with `gh release create v<X.Y.Z> dist/....tar.gz`.
4. Edit `FI-153/homebrew-tap/Formula/apfel-home-assistant.rb`: bump `url` + `sha256`.
5. Commit and push the tap.

Every step is scriptable, but right now it's manual — which invites drift between the tag, the release asset, and the formula. `wyoming-apple-stt` already solved this for its own release path and is a strong template: the sibling repo is the source of truth for its formula (via `packaging/formula.rb.template`), and the tap is a downstream consumer that CI overwrites.

We want the same shape here. It's simpler than STT's case because:
- No compiled artifacts (pure bash CLI + launcher → `git archive` is the tarball).
- No Python/Swift resources to pin.
- The formula has no dynamic content other than `url`, `version`, `sha256`.

---

## Overview

```
            ┌──────────────────────────┐
  git tag → │ apfel-home-assistant      │
  v0.1.1 →  │  .github/workflows/       │
            │    release.yml            │
            └──────────┬───────────────┘
                       │
       ┌───────────────┼────────────────────────┐
       ▼               ▼                        ▼
  make tarball   gh release create       render formula from
  (dist/*.tar.gz)  (attach tarball)      packaging/formula.rb.template
                                         + url + sha256
                                                │
                                                ▼
                                  git push to FI-153/homebrew-tap
                                  (Formula/apfel-home-assistant.rb)
```

Tag push (`v*`) is the sole trigger. The job runs on `macos-26` so `brew audit` can evaluate a formula with `depends_on macos: :tahoe`. All secrets stay in GitHub; nothing leaves CI.

---

## Design

### 1. New file: `.github/workflows/release.yml`

Modelled on `wyoming-apple-stt/.github/workflows/release.yml`. Key differences from the STT workflow:

- **No Swift build step**, no `swift-test` make target.
- **Tarball build uses `make tarball`** instead of a bespoke `packaging/build-release-tarball.sh` script (our `Makefile` already does the right thing — `git archive` with the version-pinned prefix).
- **No `python-resources.rb`** to inline into the template.

Workflow outline:

```yaml
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    runs-on: macos-26
    permissions:
      contents: write
    steps:
      - Checkout                 (actions/checkout@v4)
      - Resolve version          (strip leading `v` from GITHUB_REF_NAME → VERSION)
      - Smoke test               (./test/smoke.sh — no apfel needed)
      - Build tarball            (make tarball VERSION=$VERSION)
      - Compute sha256           (shasum -a 256)
      - brew audit --strict      (render formula to a temp tap, audit it)
      - Create GitHub release    (gh release create, attach tarball, --generate-notes)
      - Render & push formula    (template → tap repo → git push)
```

### 2. New file: `packaging/formula.rb.template`

The canonical formula source moves from the tap into this repo. The template mirrors the current tap formula verbatim, with only the three fields placeholdered:

```ruby
class ApfelHomeAssistant < Formula
  desc "Run apfel pre-configured as a Home Assistant conversation backend"
  homepage "https://github.com/FI-153/apfel-home-assistant"
  url "{{URL}}"
  version "{{VERSION}}"
  sha256 "{{SHA256}}"
  license "MIT"

  depends_on "apfel"
  depends_on macos: :tahoe

  def install
    bin.install "bin/apfel-home-assistant"
    libexec.install "libexec/apfel-home-assistant-run"

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

  def caveats
    # unchanged
  end

  service do
    run [opt_libexec/"apfel-home-assistant-run"]
    environment_variables APFEL_HA_CONF: etc/"apfel-home-assistant.conf",
                          PATH:          "#{HOMEBREW_PREFIX}/bin:/usr/bin:/bin"
    keep_alive true
    log_path var/"log/apfel-home-assistant.log"
    error_log_path var/"log/apfel-home-assistant.log"
  end

  test do
    # unchanged
  end
end
```

**Template rendering**: simple `python3` substitution in-workflow, same idiom as STT. The three placeholders are `{{URL}}`, `{{VERSION}}`, `{{SHA256}}`. A stray `version "..."` line would fail `brew audit --strict` (we hit that during v0.1.0 shipping), so `{{VERSION}}` — which is embedded in the URL — must not be duplicated as a standalone `version` field. **Decision: drop the `version` line entirely from the template**, relying on Homebrew's auto-derivation from the filename.

### 3. Makefile change: accept `VERSION` override

Today:
```make
VERSION := $(or $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'),0.0.0)
```

A tag-push workflow does have the tag checked out, so `git describe --tags --abbrev=0` works. No change strictly required. But to make CI invocations explicit and local `make tarball VERSION=0.1.1` calls possible, change to:

```make
VERSION ?= $(or $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'),0.0.0)
```

(`:=` → `?=` — honours `VERSION` from the environment if set.)

### 4. Tap side: `FI-153/homebrew-tap/Formula/apfel-home-assistant.rb`

**No preparatory change needed.** CI overwrites this file on every release. The current hand-maintained formula content is identical to what the template will render for v0.1.0, so the first CI-driven release (v0.1.1) will produce a clean diff — only `url` and `sha256` change, plus the removed redundant `version` line.

### 5. Secret: `TAP_PUSH_TOKEN`

Required: a GitHub Personal Access Token (fine-grained) with `contents: read and write` on `FI-153/homebrew-tap`. Add to this repo's secrets as `TAP_PUSH_TOKEN`. The workflow uses it to clone + push via `https://x-access-token:${TAP_PUSH_TOKEN}@github.com/FI-153/homebrew-tap.git`, exactly like STT.

`GITHUB_TOKEN` (auto-provisioned) is sufficient for the release creation step.

### 6. Quality gates

- **Smoke test** (`./test/smoke.sh`): fast, no Apple Intelligence required, catches broken CLI / launcher. Gate release on it.
- **`brew audit --strict`**: render the template into a scratch tap directory, run `brew audit --strict --formula ./path.rb`. Catches the class of problem we already hit once (redundant `version` field). If audit fails, abort before creating the GitHub release.
- **No install test in CI**: `apfel` itself depends on Apple FoundationModels (macOS 26 runtime + Apple Silicon). The `macos-26` runner should be Apple Silicon, but `apfel --serve` requires an entitlement-bearing binary and on-device model availability that's fragile on CI. Skip. The smoke test covers our wrapper; `brew audit` covers the formula syntax.

---

## Edge Cases & Constraints

- **Re-running the same tag**: `gh release create` fails if the release already exists. CI will error, which is the right default — a successful release shouldn't be silently re-published. If we need to re-push the formula without a new tag, that's a manual fallback.
- **Tap conflict**: if a human edits `Formula/apfel-home-assistant.rb` in the tap between CI runs, the push will conflict. CI will fail loudly. Acceptable — manual tap edits to this specific formula are now discouraged.
- **`macos-26` availability**: GitHub Actions rolled `macos-26` while we were shipping v0.1.0 (STT is already using it). If the image is ever deprecated, fall back to `macos-latest` and pin `macos: :tahoe` compatibility in the formula.
- **Missing `TAP_PUSH_TOKEN` secret**: first run after adding the workflow will fail at the push step with a 403. Document setup in the plan's implementation notes (once approved).
- **Version drift**: the only authoritative version in the pipeline is the git tag. `Makefile`'s `VERSION ?= ...` derives from the tag; the workflow extracts `${GITHUB_REF_NAME#v}` and passes it explicitly. The template URL is built from the same variable. Single source of truth.
- **Tag before formula is ready**: if someone pushes a tag but the template is broken, `brew audit` catches it before the release is created — so no GitHub release is minted from a broken formula. Good.
- **Homepage vs. homebrew-core `apfel`**: `depends_on "apfel"` relies on the name matching in homebrew-core. If homebrew-core ever moves or renames, the formula breaks. Out of scope here — same constraint we accepted for v0.1.0.

---

## Implementation

- [x] **Step 1:** Create `packaging/formula.rb.template` — identical to the current tap formula, except: `{{URL}}` / `{{SHA256}}` placeholders, no standalone `version` field (derived from URL filename).
- [x] **Step 2:** Relax `Makefile` so `VERSION` honours the environment: change `VERSION := ...` to `VERSION ?= ...`.
- [x] **Step 3:** Create `.github/workflows/release.yml` with the job shape from the Design section: checkout → resolve version → smoke test → build tarball → compute sha256 → render formula to a scratch path and run `brew audit --strict` → create GitHub release → render + push formula to tap.
- [x] **Step 4:** Render the template locally to a temp file using the same `python3` substitution the workflow uses, and `diff` against the current tap formula (ignoring the soon-to-be-removed `version` line). The diff must be empty aside from URL/sha changes. *Verified: with v0.1.0 values, the rendered template is byte-for-byte identical to the current tap formula.*
- [x] **Step 5:** Run `./test/smoke.sh` against the working tree to confirm nothing upstream broke. *Verified: all 7 smoke checks pass.*
- [x] **Step 6:** Report handoff — what the user still has to do: add the `TAP_PUSH_TOKEN` secret in the apfel-home-assistant repo settings, then commit + push these files, then cut `v0.1.1` to exercise the pipeline.
