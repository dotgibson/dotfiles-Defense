# Makefile — a discoverable façade over the existing entry points.
# ──────────────────────────────────────────────────────────────────────────────
# This adds NO logic: every target shells out to the real script (scripts/*.sh,
# pre-commit), which stay the single source of truth. It exists so a newcomer can
# type `make` and see how to lint, test, audit, and sync — instead of grepping the
# README for scripts/ paths. The audit (`make audit`) is the one gate; CI and
# pre-commit call the same scripts/audit-core.sh, so `make audit` == green CI.
# ──────────────────────────────────────────────────────────────────────────────
.DEFAULT_GOAL := help
.PHONY: help setup doctor audit audit-changed test bench profile lint sync sync-dry fleet-drift core-integrity parity-check freshness-dashboard hooks update-hooks update-plugins update-nvim-plugins update-tool-checksums check-pins check-modern release tag release-notes

help: ## Show this help
	@echo "dotfiles-core — make targets:"
	@grep -E '^[a-z][a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sed -E 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

setup: ## One-command dev bootstrap (pre-commit hooks + version doctor + audit) — start here
	@./scripts/setup.sh

doctor: ## Read-only triage: are the dev tools present and matching the pins? (no install, no audit)
	@./scripts/setup.sh --doctor

audit: ## Run the full Core audit (manifest, exec-bits, syntax, lint, behavioral) — the one gate
	@./scripts/audit-core.sh

audit-changed: ## Audit only what your git diff touches (fast dev loop; same classifier as CI)
	@./scripts/audit-core.sh --changed

test: ## Run only the behavioral tests (load-order smoke + function units)
	@./scripts/test-core.sh

bench: ## Benchmark Core's contribution to zsh startup (needs hyperfine; skips if absent)
	@./scripts/bench-core.sh

profile: ## Per-module zsh startup breakdown (attributes the total cost; slowest first)
	@./scripts/bench-core.sh --profile

lint: audit ## Alias for `audit` (the audit IS the lint+test gate)

sync: ## Subtree-pull Core into every OS repo (THE maintain button) — writes to sibling repos
	@./scripts/sync-core.sh

sync-dry: ## Show what `sync` would do, touching nothing
	@./scripts/sync-core.sh --dry-run

fleet-drift: ## Report which OS repos (+ Windows) lag Core's tip — the vendoring-drift dashboard
	@./scripts/fleet-drift.sh

core-integrity: ## Verify every OS repo's vendored core/ is pristine (not hand-edited) vs its core.lock
	@./scripts/core-integrity.sh

parity-check: ## Verify PARITY.md's aligned rows hold across zsh + pwsh (needs sibling dotfiles-Windows)
	@./scripts/parity-check.sh

freshness-dashboard: ## Compose the weekly fleet-health board (drift + integrity + pins) as markdown
	@./scripts/freshness-dashboard.sh

hooks: ## Install the pre-commit hooks into this clone
	@command -v pre-commit >/dev/null 2>&1 || { echo "pre-commit not found: pip install pre-commit"; exit 1; }
	@pre-commit install

update-hooks: ## Bump pinned pre-commit hook revisions (dependabot has no pre-commit ecosystem)
	@command -v pre-commit >/dev/null 2>&1 || { echo "pre-commit not found: pip install pre-commit"; exit 1; }
	@pre-commit autoupdate

update-plugins: ## Roll the pinned zsh-plugin SHAs in zsh/45-plugins.zsh to upstream HEAD (deliberate bump)
	@./scripts/update-plugins.sh

update-nvim-plugins: ## Roll the pinned nvim plugin commits in nvim/lazy-lock.json forward (deliberate bump)
	@./scripts/update-nvim-plugins.sh

update-tool-checksums: ## Recompute the pinned CI tool SHA-256s in tool-versions.env after a version bump
	@./scripts/update-tool-checksums.sh

check-pins: ## Report whether the zsh-plugin + nvim pins are behind upstream (the weekly freshness gate)
	@./scripts/update-plugins.sh --check && ./scripts/update-nvim-plugins.sh --check

check-modern: ## Check CI meets the modern floor (scripts/modern-baseline.yml) — also run inside `make audit`
	@./scripts/check-modern.sh

release: ## Cut a release: bump core.version + CHANGELOG, run the audit (usage: make release VERSION=X.Y.Z)
	@./scripts/release.sh $(VERSION)

tag: ## Finish the release: commit + annotated tag vX.Y.Z from core.version (PUSH=1 also pushes)
	@./scripts/tag-release.sh $(if $(filter 1,$(PUSH)),--push,)

release-notes: ## Draft a GitHub Release body from Conventional Commits since the last release (needs git-cliff)
	@command -v git-cliff >/dev/null 2>&1 || { echo "git-cliff not found: cargo install git-cliff (or scoop/pkg). Config: cliff.toml"; exit 1; }
	@_from=$$(git log --grep='^release v' --format=%H -1); \
	  if [ -n "$$_from" ]; then git-cliff "$$_from..HEAD"; else git-cliff; fi
