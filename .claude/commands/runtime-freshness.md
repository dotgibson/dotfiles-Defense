---
description: Report which pinned language runtimes are due for a minor/major bump
argument-hint: "[runtime name — optional, e.g. python; empty = all]"
allowed-tools: Task, Read, Grep, Glob, WebSearch, WebFetch, Bash(mise outdated:*), Bash(mise ls:*), Bash(mise current:*), Bash(mise ls-remote:*)
---

# /runtime-freshness

Decide whether the **pinned** language runtimes in `mise/config.toml` are due to
cross a pin — the judgment half of the maintenance job's `mise outdated --bump`
nudge, which can list that a newer minor/major exists but cannot read an upstream
EOL calendar or tell you whether the pentest tooling will survive the jump.

Target for this run: **$ARGUMENTS** (empty = every runtime in `mise/config.toml`).

## Why this is a manual class

`maint-run`'s `mise upgrade` keeps each runtime current only _within_ its pin
(`python = "3.12"` tracks 3.12.x; it never moves to 3.13). That is deliberate:
the config comments call out tooling that wants a specific runtime (impacket /
BloodHound → Python, evil-winrm → Ruby, Burp → Java), so crossing a pin is a
taste call, not a cron job. This routine makes that call _informed_.

Two runtimes are **not** in scope as pins:

- `node`/`pnpm`/`go` float (`lts`/`latest`) — `mise upgrade` already advances them.
- `rust = "stable"` is a rolling channel handled by `rustup update` in the maint
  runner (mise delegates rust to rustup). It has no pin to cross — skip it here.

## Establish the baseline first

Read what is actually pinned before researching, so a verdict maps to a real spec:

- `mise/config.toml` — the `[tools]` pins and the intent comments beside each.
- `mise outdated --bump --no-header` — current vs latest-beyond-pin (read-only;
  the same command the maint job logs). `mise ls-remote <tool>` enumerates
  available versions if you need to see the next minor/major explicitly.

## What to research (per pinned runtime)

1. **Support window.** Where does the pinned line sit on its EOL calendar — full
   support, security-only, or past EOL? Prefer <https://endoflife.date/> (it has
   `python`, `ruby`, `eclipse-temurin`, etc.); confirm against the project's own
   release page. A line entering security-only or EOL is the strongest bump signal.
2. **What the next step is.** The next stable minor (Ruby ships ~yearly on Dec 25;
   Python ~yearly in Oct) or the next **LTS** (Java — stay on LTS, skip interim).
3. **Compatibility risk.** Does the bump break anything the config's intent comment
   names? Check whether the relevant tooling supports the target version before
   recommending the move — the whole reason these are pinned.

Delegate the web research to a subagent if the sweep is broad (it keeps EOL-page
fetches out of this context); relay its findings.

## How to report

Per runtime, a verdict:

- **Bump now** — pin is aging (security-only/EOL) or a needed tool requires the
  next line, and that line is proven. Give the exact edit: `mise/config.toml`
  spec change + `mise up --bump <tool>` (which rewrites the spec) or a manual
  `mise use -g <tool>@<ver>`.
- **Watch** — a newer line exists but the current pin is still in full support and
  nothing forces the move; note the date/trigger to revisit.
- **Hold** — a newer line exists but a pinned tool doesn't support it yet; name the
  blocker.

Propose changes only; do not edit `mise/config.toml` unless I ask. If I adopt a
bump, it is Core — add a `CHANGELOG.md` entry and `make audit` before the PR
(`mise/config.toml` is manifest-tracked, so keep the audit green).
