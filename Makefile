# Makefile — the discoverable entry point for dotfiles-Defense.
# ──────────────────────────────────────────────────────────────────────────────
# This repo had no Makefile, which made it the only repo in the fleet with no way to
# reproduce its own CI gate locally: a contributor had to read .github/workflows/ and
# reconstruct the command list by hand. The gates were all real and all scripted — they
# just had no front door. dotgibson/dotfiles-Defense#196.
#
# NOTE ON SCOPE: dotfiles-core's Makefile is the AUTHORING gate for Core (audit, manifest,
# behavioral suite, release). This one is a CONSUMER's Makefile — it wires the checks this
# repo owns. Anything under core/ is verified upstream and is not re-gated here.
#
# EVERY TARGET BELOW RUNS A SCRIPT THAT EXISTS. That is not a platitude: Offense's Makefile
# was written because its docs named `make` targets that were never defined, and porting its
# target list wholesale would have recreated the same lie here in the other direction —
# `core-sync`/`core-lock`/`companion-*` are Offense-only (Core is pushed INTO this repo by
# dotfiles-core's own `make sync`, and this repo vendors no htpx companion). They are
# deliberately absent rather than stubbed.
#
# ONE deliberate exception to "runs a real script": the fleet `make` vocabulary
# (dotgibson/dotfiles-core#691) requires the canonical names — check, dry-run, packages-check,
# core-verify — to RESOLVE in every repo that vendors Core, so a verb that genuinely does not
# apply here is a documented two-line stub, not an absence. `packages-check` is that stub:
# this repo is distro-agnostic and ships no OS package list. The other three are real —
# `check` aggregates the offline gates, `dry-run` and `core-verify` are the canonical spellings
# of `bootstrap-dry` and `core-check`, which stay as aliases.
#
# Run `make` with no target for the list.
# ──────────────────────────────────────────────────────────────────────────────
.DEFAULT_GOAL := help
# The four canonical fleet verbs (check, dry-run, packages-check, core-verify) sit next to
# this repo's own names; the historical spellings (bootstrap-dry, core-check) are kept as
# aliases so nothing that already calls them breaks. See dotgibson/dotfiles-core#691 and
# VENDORING.md § "The `make` vocabulary, and the test floor" in Core.
.PHONY := help lint shellcheck markdown check test sigma sigma-lint sigma-compile drift \
          methodology validation-gates attack-tags htpx htpx-report dry-run bootstrap-dry \
          packages-check lab-smoke core-verify core-check hooks
.PHONY: $(.PHONY)

# Pinned tool versions come from the vendored Core, so local runs match CI exactly.
CORE_PINS := core/scripts/tool-versions.env
MARKDOWNLINT_VERSION := $(shell sed -n 's/^MARKDOWNLINT_VERSION=//p' $(CORE_PINS) 2>/dev/null)

# Repo-owned sources only — the vendored core/ subtree is gated by its upstream.
MD_FILES := $(shell git ls-files '*.md' ':!:core/**' 2>/dev/null)

# Said once, used by every sigma-dependent target. These gates are HARD in CI, which
# installs the pinned sigma-cli; locally the tool is optional, so they skip with a reason
# rather than fail. A skip that does not say why is indistinguishable from a pass.
#
# TWO SPELLINGS. The PyPI `sigma-cli` package installs its entrypoint as `sigma`, which is
# what CI gets. Distro packages ship the same tool as `sigma-cli` (Debian/Arch both do), so
# probing only for `sigma` reported "not installed" on a machine where it plainly was, and
# the SIEM deploy-form gate then skipped every local run. Resolve once, prefer `sigma`, and
# let the environment override for anything exotic.
SIGMA_BIN ?= $(shell command -v sigma 2>/dev/null || command -v sigma-cli 2>/dev/null)
export SIGMA_BIN
SIGMA_MISSING := neither 'sigma' nor 'sigma-cli' on PATH — CI installs the pinned one; see .github/workflows/sigma.yml

help: ## Show this help
	@grep -hE '^[a-z][a-z0-9_-]*:.*?## ' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

## ── the fleet check verb ─────────────────────────────────────────────────────

# `check` is the fleet's canonical "verify this repo" verb (dotgibson/dotfiles-core#691).
# Here it is the aggregate of every gate that needs neither the network nor a container —
# the offline CI reproduction in one word. The network gates (attack-tags, htpx) and the
# container gate (lab-smoke) stay out on purpose, for the reasons their own targets give:
# folding them in would make `make check` fail on a train, which is how a useful gate gets
# commented out.
check: lint sigma test ## The full offline gate: lint + the offline sigma gates + behavioural tests

## ── static gates ─────────────────────────────────────────────────────────────

lint: shellcheck markdown ## Every static gate that needs no container (shellcheck + markdown)

shellcheck: ## shellcheck + bash -n / zsh -n, at CI's PINNED version
	@# Not a bare `shellcheck` call: tests/lint-shell.sh reads SHELLCHECK_VERSION from
	@# $(CORE_PINS) and the flags from core/.github/workflows/lint-call.yml, then refuses
	@# to run under a mismatched local shellcheck. A distro shellcheck and the pinned one
	@# disagree about which checks exist, so "clean locally, red in CI" is the default
	@# failure without it. Read that script's header before replacing this with a one-liner.
	@./tests/lint-shell.sh

# ONE recipe line. make runs each line in its own shell, so the guard's `exit 0` only
# ended THAT line — this printed "npx not available — skipping markdown" and then ran npx
# anyway, exiting 127. Joining them makes the skip a real skip (dotgibson/dotfiles-core#775).
#
# An unreadable pin FAILS rather than falling back to @latest. "Pinned version, same as CI"
# is this target's whole claim; silently linting under a different version would make a
# local pass mean nothing, which is the failure mode the rest of that sweep is about.
markdown: ## markdownlint repo-owned docs (pinned version, same as CI)
	@if ! command -v npx >/dev/null 2>&1; then echo "npx not available — skipping markdown"; \
	elif [ -z "$(MARKDOWNLINT_VERSION)" ]; then \
	  echo "!! MARKDOWNLINT_VERSION unreadable from $(CORE_PINS) — refusing to lint unpinned"; exit 1; \
	elif [ -z "$(MD_FILES)" ]; then echo "no repo-owned .md"; \
	else npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) $(MD_FILES); fi

## ── detections ───────────────────────────────────────────────────────────────

sigma: sigma-lint sigma-compile drift methodology validation-gates ## The sigma.yml hard gates that run offline

sigma-lint: ## Structural lint over every Sigma rule (hermetic)
	@# --fail-on-issues, exactly as sigma.yml runs it: `sigma check` exits 0 on validator
	@# ISSUES by default and only fails on parse/semantic errors, so without the flag this
	@# target would be quietly weaker than the gate it exists to reproduce.
	@#
	@# Guard and command share ONE recipe line on purpose. Each line of a recipe is its own
	@# shell, so the earlier `guard || { echo; exit 0; }` on its own line ended only THAT
	@# shell — make went straight on to the next line and ran the tool anyway, dying with
	@# 127. The "skip with a reason" this target advertises never actually happened.
	@if [ -z "$(SIGMA_BIN)" ]; then echo "⚠ SKIPPED sigma-lint: $(SIGMA_MISSING)"; exit 0; fi; \
	$(SIGMA_BIN) check --fail-on-issues -c detections/sigma-validation-config.yml detections/sigma/

sigma-compile: ## Compile every rule to Splunk — catches a rule that parses but will not convert
	@# One shell — see the note in sigma-lint. The success line was a separate recipe line
	@# too, so it printed even on the runs that skipped.
	@set -e; \
	if [ -z "$(SIGMA_BIN)" ]; then echo "⚠ SKIPPED sigma-compile: $(SIGMA_MISSING)"; exit 0; fi; \
	./detections/sigma/convert.sh splunk > /dev/null; \
	echo "✓ every rule compiles to Splunk"

drift: ## Are the GENERATED artifacts in step with the rules? (the --check gates)
	@# These are byte-comparisons, not regenerations: each script rewrites its target from
	@# the Sigma corpus and --check fails if the result differs from what is committed. Run
	@# them BEFORE pushing — a drift failure in CI reads as an unrelated red gate.
	@#
	@# gen-siem.sh converts through sigma-cli, so it is gated on the tool; the navigator and
	@# coverage generators read the rule frontmatter directly and run anywhere.
	@#
	@# ONE shell, `set -e`, and an explicit if — deliberately, because the obvious spelling
	@# is wrong. This used to read
	@#
	@#   command -v sigma && ./detections/siem/gen-siem.sh --check || echo "...skipping..."
	@#
	@# and in `A && B || C` a FAILING B runs C. So a genuine SIEM drift failure printed the
	@# skip notice, exited 0, and the recipe went on to print the success tick underneath
	@# it. The gate could only ever report "clean" or "skipped" — never "drifted", which is
	@# the one answer it exists to give.
	@set -e; \
	skipped=""; \
	if [ -n "$(SIGMA_BIN)" ]; then \
	  ./detections/siem/gen-siem.sh --check; \
	else \
	  echo "⚠ SKIPPED the SIEM deploy-form gate: $(SIGMA_MISSING)"; \
	  echo "⚠   it is a HARD gate in CI — this run did not check it"; \
	  skipped=" (SIEM deploy-form gate SKIPPED — see above)"; \
	fi; \
	./detections/navigator/gen-navigator.sh --check; \
	./detections/navigator/gen-coverage.sh --check; \
	./detections/siem/check-splunk-precedence.sh; \
	echo "✓ generated artifacts are in step with the rules$$skipped"

methodology: ## Does DEFENSE-METHODOLOGY.md still describe the rules that exist?
	@./detections/check-methodology.sh
	@./detections/check-readme-gates.sh

validation-gates: ## Every rule has validation coverage, and every fixture has provenance
	@./docker/validation/check-rule-coverage.sh
	@./docker/validation/check-fixture-provenance.sh

attack-tags: ## Are all ATT&CK technique IDs real? (downloads the pinned ATT&CK bundle)
	@# Split out of `sigma` deliberately: this one fetches the pinned ATT&CK release, so it
	@# is one of the two detection gates that need the network (`htpx` is the other). CI
	@# caches the bundle; you will not.
	@./detections/check-attack-tags.sh

htpx: ## Do the htpx entries this repo names still exist? (fetches the pinned htpx commit)
	@# Out of `sigma` and out of `drift` for the same reason attack-tags is: it reads a
	@# corpus from outside this repo, so it needs the network. Grouping it with the offline
	@# gates would make `make sigma` fail on a train, which is how a useful gate gets
	@# commented out. Both halves of the boundary run here — the claim gate and the report's
	@# drift check — because they share the one fetch (detections/htpx-corpus.sh caches it).
	@./detections/check-htpx-pairing.sh
	@./detections/gen-htpx-coverage.sh --check

htpx-report: ## Rewrite HTPX-COVERAGE.md from the rules + the pinned corpus
	@# The bare generator, for after you add a rule or bump detections/htpx.pin. `make htpx`
	@# is the gate; this is the fix-up its failure tells you to run.
	@./detections/gen-htpx-coverage.sh

## ── behaviour ────────────────────────────────────────────────────────────────

test: ## Run the repo's behavioural checks
	@./tests/test-defense.sh
	@echo "✓ tests pass"

dry-run: ## Preview the full bootstrap plan, changing nothing
	@./bootstrap.sh --dry-run

# The historical spelling, kept as an alias so `make bootstrap-dry` still works. No `## `
# help text, deliberately — one entry for this in `make help` is enough, and it is dry-run.
bootstrap-dry: dry-run

packages-check: ## Not applicable — this repo is distro-agnostic and ships no OS package list
	@# A stub, not an omission: the fleet vocabulary (dotgibson/dotfiles-core#691) requires the
	@# canonical name to RESOLVE in every repo, so `make packages-check` answers everywhere. Host
	@# tools come from the OS-native layer; this Role layer installs nothing to package-check.
	@echo "packages-check: not applicable to this repo (no OS package list)"

lab-smoke: ## Bring the validation lab up and smoke-test it (needs docker, slow)
	@./docker/validation/lab-smoke.sh

## ── vendored core/ (subtree of dotfiles-core) ────────────────────────────────

core-verify: ## Is the vendored core/ behind the latest upstream Core release?
	@# No core-sync counterpart, and that is not an omission: Core is pushed INTO this repo
	@# by dotfiles-core's own `scripts/sync-core.sh` (`make sync` there), which opens the
	@# bump PR. There is nothing to pull from this side. This target answers the question
	@# core-drift.yml asks weekly, so you can ask it now instead of waiting for Monday.
	@#
	@# `sed 's/^v//'` is load-bearing and matches core-drift.yml exactly: core.lock stores a
	@# BARE version (4.18.0) while the upstream tags carry the v prefix, so comparing them
	@# raw reports a sync owed on a repo that is perfectly current.
	@#
	@# The gh probe and the query are ONE recipe line. make gives each line its own shell, so
	@# the old `exit 0` ended only ITS line and the query ran anyway — and this target fails
	@# WORSE than the others of its kind (dotgibson/dotfiles-core#775): `gh` erroring leaves
	@# upstream_ver EMPTY, which is never equal to local_ver, so it printed
	@#     • vendored core is 5.4.1, upstream is  — a sync from dotfiles-core is owed
	@# A confidently wrong answer about fleet drift, not a crash. An empty upstream is now
	@# its own branch rather than being compared.
	@if ! command -v gh >/dev/null 2>&1; then \
	  echo "gh not installed — cannot query upstream tags"; \
	else \
	  local_ver=$$(sed -n 's/^core_version=//p' core.lock | head -n1); \
	  upstream_ver=$$(gh api repos/dotgibson/dotfiles-core/tags --paginate --jq '.[].name' \
	    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' | sed 's/^v//' | sort -V | tail -n1); \
	  if [ -z "$$upstream_ver" ]; then \
	    echo "!! could not read upstream tags (gh failed or returned nothing) — drift UNKNOWN, not current"; \
	    exit 1; \
	  elif [ "$$local_ver" = "$$upstream_ver" ]; then \
	    echo "✓ vendored core is current ($$local_ver)"; \
	  else \
	    echo "• vendored core is $$local_ver, upstream is $$upstream_ver — a sync from dotfiles-core is owed"; \
	  fi; \
	fi

# The historical spelling, kept as an alias so `make core-check` still works. No `## ` help
# text, deliberately — the one entry in `make help` is core-verify.
core-check: core-verify

## ── maintenance ──────────────────────────────────────────────────────────────

hooks: ## Install the local core-guard pre-commit hook into this clone
	@bash -c 'source core/lib/ux.sh; source core/lib/bootstrap-lib.sh; blib_install_core_guard "$$PWD"'
