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
# Run `make` with no target for the list.
# ──────────────────────────────────────────────────────────────────────────────
.DEFAULT_GOAL := help
.PHONY := help lint shellcheck markdown test sigma sigma-lint sigma-compile drift \
          methodology validation-gates attack-tags htpx htpx-report bootstrap-dry \
          lab-smoke core-check hooks
.PHONY: $(.PHONY)

# Pinned tool versions come from the vendored Core, so local runs match CI exactly.
CORE_PINS := core/scripts/tool-versions.env
MARKDOWNLINT_VERSION := $(shell sed -n 's/^MARKDOWNLINT_VERSION=//p' $(CORE_PINS) 2>/dev/null)

# Repo-owned sources only — the vendored core/ subtree is gated by its upstream.
MD_FILES := $(shell git ls-files '*.md' ':!:core/**' 2>/dev/null)

# Said once, used by every sigma-dependent target. These gates are HARD in CI, which
# installs the pinned sigma-cli; locally the tool is optional, so they skip with a reason
# rather than fail. A skip that does not say why is indistinguishable from a pass.
SIGMA_MISSING := sigma-cli not installed — CI installs the pinned one; see .github/workflows/sigma.yml

help: ## Show this help
	@grep -hE '^[a-z][a-z0-9_-]*:.*?## ' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

## ── static gates ─────────────────────────────────────────────────────────────

lint: shellcheck markdown ## Every static gate that needs no container (shellcheck + markdown)

shellcheck: ## shellcheck + bash -n / zsh -n, at CI's PINNED version
	@# Not a bare `shellcheck` call: tests/lint-shell.sh reads SHELLCHECK_VERSION from
	@# $(CORE_PINS) and the flags from core/.github/workflows/lint-call.yml, then refuses
	@# to run under a mismatched local shellcheck. A distro shellcheck and the pinned one
	@# disagree about which checks exist, so "clean locally, red in CI" is the default
	@# failure without it. Read that script's header before replacing this with a one-liner.
	@./tests/lint-shell.sh

markdown: ## markdownlint repo-owned docs (pinned version, same as CI)
	@command -v npx >/dev/null 2>&1 || { echo "npx not available — skipping markdown"; exit 0; }
	@npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) $(MD_FILES)

## ── detections ───────────────────────────────────────────────────────────────

sigma: sigma-lint sigma-compile drift methodology validation-gates ## The sigma.yml hard gates that run offline

sigma-lint: ## Structural lint over every Sigma rule (hermetic)
	@command -v sigma >/dev/null 2>&1 || { echo "$(SIGMA_MISSING)"; exit 0; }
	@# --fail-on-issues, exactly as sigma.yml runs it: `sigma check` exits 0 on validator
	@# ISSUES by default and only fails on parse/semantic errors, so without the flag this
	@# target would be quietly weaker than the gate it exists to reproduce.
	@sigma check --fail-on-issues -c detections/sigma-validation-config.yml detections/sigma/

sigma-compile: ## Compile every rule to Splunk — catches a rule that parses but will not convert
	@command -v sigma >/dev/null 2>&1 || { echo "$(SIGMA_MISSING)"; exit 0; }
	@./detections/sigma/convert.sh splunk > /dev/null
	@echo "✓ every rule compiles to Splunk"

drift: ## Are the GENERATED artifacts in step with the rules? (the --check gates)
	@# These are byte-comparisons, not regenerations: each script rewrites its target from
	@# the Sigma corpus and --check fails if the result differs from what is committed. Run
	@# them BEFORE pushing — a drift failure in CI reads as an unrelated red gate.
	@#
	@# gen-siem.sh converts through sigma-cli, so it is gated on the tool; the navigator and
	@# coverage generators read the rule frontmatter directly and run anywhere.
	@command -v sigma >/dev/null 2>&1 && ./detections/siem/gen-siem.sh --check \
	  || echo "$(SIGMA_MISSING) (skipping the SIEM deploy-form gate)"
	@./detections/navigator/gen-navigator.sh --check
	@./detections/navigator/gen-coverage.sh --check
	@./detections/siem/check-splunk-precedence.sh
	@echo "✓ generated artifacts are in step with the rules"

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

bootstrap-dry: ## Preview the full bootstrap plan, changing nothing
	@./bootstrap.sh --dry-run

lab-smoke: ## Bring the validation lab up and smoke-test it (needs docker, slow)
	@./docker/validation/lab-smoke.sh

## ── vendored core/ (subtree of dotfiles-core) ────────────────────────────────

core-check: ## Is the vendored core/ behind the latest upstream Core release?
	@# No core-sync counterpart, and that is not an omission: Core is pushed INTO this repo
	@# by dotfiles-core's own `scripts/sync-core.sh` (`make sync` there), which opens the
	@# bump PR. There is nothing to pull from this side. This target answers the question
	@# core-drift.yml asks weekly, so you can ask it now instead of waiting for Monday.
	@#
	@# `sed 's/^v//'` is load-bearing and matches core-drift.yml exactly: core.lock stores a
	@# BARE version (4.18.0) while the upstream tags carry the v prefix, so comparing them
	@# raw reports a sync owed on a repo that is perfectly current.
	@command -v gh >/dev/null 2>&1 || { echo "gh not installed — cannot query upstream tags"; exit 0; }
	@local_ver=$$(sed -n 's/^core_version=//p' core.lock | head -n1); \
	 upstream_ver=$$(gh api repos/dotgibson/dotfiles-core/tags --paginate --jq '.[].name' \
	   | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' | sed 's/^v//' | sort -V | tail -n1); \
	 if [ "$$local_ver" = "$$upstream_ver" ]; then \
	   echo "✓ vendored core is current ($$local_ver)"; \
	 else \
	   echo "• vendored core is $$local_ver, upstream is $$upstream_ver — a sync from dotfiles-core is owed"; \
	 fi

## ── maintenance ──────────────────────────────────────────────────────────────

hooks: ## Install the local core-guard pre-commit hook into this clone
	@bash -c 'source core/lib/ux.sh; source core/lib/bootstrap-lib.sh; blib_install_core_guard "$$PWD"'
