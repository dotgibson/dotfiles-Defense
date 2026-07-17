---
description: Review open dependency-bump PRs against upstream changelogs
argument-hint: "[PR number, optional — defaults to all open bot PRs]"
allowed-tools: Task, Read, Grep, Glob, WebSearch, WebFetch, Bash(./scripts/update-plugins.sh --check), Bash(git log:*), Bash(git diff:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*)
---

# /freshness-triage

Decide whether the automated dependency bumps are **safe to merge** — the judgment
half of the `freshness.yml` bot, which can roll pins forward and open a PR but
cannot read an upstream changelog for a breaking change.

Target for this run: **$ARGUMENTS** (empty = all open automation PRs).

## What the bots produce

- **`freshness.yml`** (weekly) — rolls the pinned zsh-plugin SHAs in
  `zsh/plugins.zsh` and refreshes `nvim/lazy-lock.json`, opening PRs on
  `automation/freshness-zsh-plugins` and `automation/freshness-nvim-plugins`.
- **`dependabot.yml`** (weekly) — bumps GitHub Actions in `.github/workflows/`.

For the zsh pins, `--check` is the source of truth for "is it behind" and is safe to run
(it only `git ls-remote`s + `zsh -n` parses — no upstream code runs):

```bash
./scripts/update-plugins.sh --check
```

For the **nvim** pins, do NOT run `update-nvim-plugins.sh --check` here — it runs
`nvim --headless +Lazy! sync`, which executes upstream plugin _build hooks_ inside this
token-bearing job (a supply-chain path to `CLAUDE_CODE_OAUTH_TOKEN`). Read the staleness
from the open `automation/freshness-nvim-plugins` PR the bot already opened — `gh pr diff`
/ `gh pr view` show exactly which pins moved.

## What to do per PR

1. **Identify what moved** — read the diff: which plugin/action, from which pin to
   which.
2. **Read the upstream changelog/release notes** between the old and new ref
   (WebFetch the project's releases/CHANGELOG). Look specifically for: breaking
   changes, removed/renamed options, new required config, and security fixes.
3. **Map impact to this repo** — does the bumped plugin's config in `zsh/`,
   `nvim/`, or the load order rely on anything the bump changes?
4. **Confirm the gate** — note whether CI is green on the PR; a bump that fails
   `make audit` is never mergeable regardless of the changelog.

## CLI tool pins (`scripts/tool-versions.env`)

The pinned gate binaries (shellcheck / actionlint / gitleaks / neovim / shfmt) are
a **separate, manual bump class** — neither `freshness.yml` nor dependabot touches
`tool-versions.env`, so these move by hand. Each one carries BOTH a `*_VERSION` and
a verified `*_SHA256` that `.github/actions/setup-core-tools` checks before install.

When a triaged change bumps a `*_VERSION` here (or you bump one while triaging):

1. **The checksum MUST be refreshed in the same change** — `make update-tool-checksums`
   re-downloads the exact pinned assets and rewrites the matching `*_SHA256`.
2. **A version bump with a stale hash is a trap the audit can't fully catch**:
   `audit-core.sh` only asserts a 64-hex `*_SHA256` is _present_, not that it matches
   the new asset — so a stale-but-well-formed hash passes the audit and then fails
   late at the action's `sha256sum -c` in CI. Treat a diff that moves a `*_VERSION`
   without its `*_SHA256` as **Hold** until the checksum is regenerated.
3. Review the refreshed hashes against upstream's published checksums where available
   (the same trust-anchor step as any pin bump) before merging.

## How to report

Per PR, a verdict:

- **Merge** — no breaking changes, CI green; one line on what it brings.
- **Hold** — what specifically would break and the config that needs to change
  first.
- **Security** — call out any bump that fixes a known vuln (merge priority).

Post a comment on the PR or merge only if I ask — default to reporting here.
