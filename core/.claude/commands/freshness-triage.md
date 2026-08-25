---
description: Review open dependency-bump PRs against upstream changelogs
argument-hint: "[PR number, optional — defaults to all open bot PRs]"
allowed-tools: Task, Read, Grep, Glob, WebSearch, WebFetch, Bash(./scripts/update-plugins.sh --check), Bash(git log:*), Bash(git diff:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(gh issue list:*), Bash(gh run list:*)
---

# /freshness-triage

Decide whether the automated dependency bumps are **safe to merge** — the judgment
half of the `freshness.yml` bot, which can roll pins forward and open a PR but
cannot read an upstream changelog for a breaking change.

Target for this run: **$ARGUMENTS** (empty = all open automation PRs).

## What the bots produce

- **`freshness.yml`** (weekly) — rolls the pinned zsh-plugin SHAs in
  `zsh/45-plugins.zsh` and refreshes `nvim/lazy-lock.json`, opening PRs on
  `automation/freshness-zsh-plugins` and `automation/freshness-nvim-plugins`.
- **Renovate** (weekly) — bumps third-party GitHub Actions in `.github/workflows/`.
  Configured by the three-line `renovate.json`, which extends the shared org preset
  `local>dotgibson/.github`; the policy lives there, not here. It groups third-party
  action bumps into **one `ci(deps):` PR authored by `app/renovate`** (so look for that
  author, not an `automation/*` branch), maintains the SHA pins rather than un-pinning
  them, and deliberately leaves the fleet's own `dotgibson/**` reusable-workflow refs on
  their moving `@v4` tag. Renovate also keeps a per-repo **Dependency Dashboard** issue, and
  a bump parked there opens no PR — rate-limited, awaiting approval, or grouped-and-pending —
  so an empty PR queue does **not** prove an empty bump queue. **Read it:**

  ```bash
  gh issue list --state open --search "Dependency Dashboard in:title" --json number,title,body
  ```

  Report the parked bumps as a first-class row, not a caveat. An empty PR queue with a loaded
  dashboard and an empty PR queue with an empty dashboard are different states and must read
  differently (#633).

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

## Is the bot even alive?

Zero open PRs is equally consistent with **nothing to bump** and with **the bot never having
run**. Those are opposite situations and the second is the one a freshness routine most needs to
catch, because a silently dead bot degrades exactly like a current tree — quietly, and for as
long as nobody checks.

```bash
gh run list --workflow=freshness.yml --limit 5 --json conclusion,createdAt,event,status
```

`freshness.yml` is scheduled **Mondays 06:00 UTC**. Report the last run's timestamp and
conclusion as a row of its own, and treat this as a **finding in its own right, not a
footnote**:

- **No successful completion in the last 10 days** — one missed run plus slack, so a single
  delayed Monday does not cry wolf. Say so at the top of the report, above the per-PR verdicts:
  a dead updater invalidates the whole "nothing to triage" reading below it.
- **Last run failed** — name the conclusion. `notify-failure` already pages on a scheduled
  failure, so a red run here that produced no page is itself worth flagging.

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
a **separate, manual bump class** — neither `freshness.yml` nor Renovate touches
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

Lead with the two **fleet-level rows** — they qualify everything after them, and a per-PR
verdict list that opens with "nothing to triage" is misleading when either is unhealthy:

1. **Bot liveness** — `freshness.yml`'s last run: timestamp + conclusion, and whether it clears
   the 10-day floor.
2. **Parked bumps** — how many are sitting on the Renovate Dependency Dashboard with no PR.

Both are rows, always present. "Nothing parked" and "not checked" are different answers, and
before #633 this routine could only ever give the second.

Then, per PR, a verdict:

- **Merge** — no breaking changes, CI green; one line on what it brings.
- **Hold** — what specifically would break and the config that needs to change
  first.
- **Security** — call out any bump that fixes a known vuln (merge priority).

Post a comment on the PR or merge only if I ask — default to reporting here.
