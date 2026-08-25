---
description: Research the modern-CLI stack for newer/better tools worth adopting
argument-hint: "[tool, category, or theme — optional]"
allowed-tools: Task, Read, Grep, Glob, WebSearch, WebFetch
---

# /tool-scout

Surface **cutting-edge tools and methods** the system does not yet use — the chore
no script can do, because it needs live research and taste. The goal is a
reviewable proposal, not a blind upgrade.

Focus for this run: **$ARGUMENTS** (empty = scan the whole modern-CLI stack).

Delegate the web research to the `tool-scout` subagent (it has WebSearch/WebFetch
and its own context) and relay its ranked proposal.

## Establish the baseline first

Before researching, read what the system already ships so you do not "discover"
something already in use:

- `PORTING-MATRIX.md` — the modern-CLI stack and per-distro package names.
- `zsh/00-tools.zsh`, `zsh/20-aliases.zsh` — what is detected and aliased.
- `mise/config.toml` — pinned language runtimes.
- `zsh/45-plugins.zsh`, `nvim/lazy-lock.json` — pinned plugins.

Those five describe what Core **has**. One more describes what it has already **turned down**:

- `.claude/tool-decisions.md` — tools considered and declined, with the reasoning and the issue.

**Read it before ranking anything, and state per candidate whether a prior decision exists.**
A tool on that list is not automatically dead, but it may only be re-proposed *against* the
recorded reasoning, naming what changed — and "it is good" is not what changed. Without this the
five baseline files make a declined tool indistinguishable from one never evaluated, which is how
`hexyl` came back ranked "adopt" six days after #395 closed it (#634).

## What to research

1. **Direct upgrades.** For each tool in the stack (eza, bat, fd, ripgrep, zoxide,
   fzf, git-delta, btop, starship, atuin, yazi, tealdeer, duf, jq/yq, hyperfine,
   ouch, lazygit, sesh, mise), is there a major new release or feature worth
   adopting — or a newer tool that has overtaken it?
2. **New categories.** Tools/methods that fit this stack's philosophy (fast, modern
   replacements for classic Unix tools; ergonomic shell/tmux/nvim workflow) that
   the system has no equivalent for yet.
3. **Method shifts.** Better ways to do what the repo already does (e.g. plugin
   management, runtime pinning, prompt, history, session management).

For each candidate, verify it is real and current (check the project's repo and
latest release date — do not trust a single blog post), and note its packaging
across the distros in `PORTING-MATRIX.md` (this decides how hard it is to adopt).

## Standing re-verification: workarounds premised on upstream behaviour

Some Core code is not a preference but a **workaround for a specific upstream bug**,
and its justification expires when upstream changes. For these, "is there a newer
release?" is the wrong question — the right one is **"does the premise still hold?"**,
and only a measurement answers that; a changelog that does not mention the bug is not
evidence the bug is gone. Check the list below on every run. A version bump past the
one a workaround was verified against is a finding in its own right, not a footnote.

- **atuin — `_core_atuin_daemon_guard` (`zsh/00-tools.zsh`).** Verified against
  **18.19.0**: with the daemon enabled and its socket absent or stale, `atuin history
  start` exits 0, prints a well-formed history id, writes nothing to stderr, and
  **discards the entry** (`atuinsh/atuin#3561`). The guard's throttled re-probe, its
  one-way degrade, and every millisecond it spends on the prompt path are justified by
  that single fact — and it has already changed once, in the direction that makes it
  harder to notice (18.16.1 failed loudly; 18.19.0 fails silently).

  **The measurement is automated, and this command must not re-implement it.**
  `.github/workflows/atuin-guard-verify.yml` runs `scripts/verify-atuin-guard.sh` every
  Tuesday at 13:00 UTC against **whatever atuin upstream ships that week** — resolved and
  downloaded at run time, checksum- and provenance-verified in a job that executes nothing,
  then measured in a job that holds no token.

  **TWO premises, measured separately, one verdict and one issue title each** — because their
  remedies differ and a reader must never act on prose written for the other one. Three
  verdicts apiece; two of the three file a deduplicated issue:

  | premise | verdict | meaning | filed as |
  | --- | --- | --- | --- |
  | discard | `holds` | delta 0, rc 0, empty stderr, id printed — on **both** the absent-socket and stale-socket shapes | nothing (job summary only) |
  | discard | `moved` | anything else — `zsh/00-tools.zsh`'s rationale is now overclaiming | `atuin-guard-verify: the silent-discard premise has MOVED` |
  | discard | `unmeasurable` | the apparatus could not be trusted — **never** reported as `holds` | `atuin-guard-verify: the premise could not be measured` |
  | autostart | `holds` | every arm spawned a daemon and landed exactly one row, from both unreachable shapes | nothing (job summary only) |
  | autostart | `moved` | no daemon appeared, or the entry did not land — the stand-down is now unbacked | `atuin-guard-verify: the autostart self-healing premise has MOVED` |
  | autostart | `unmeasurable` | including the manual-spawn control failing, i.e. the runner could not host a daemon at all | `atuin-guard-verify: the autostart premise could not be measured` |

  The `autostart` leg (`--premise autostart`, `make verify-atuin-guard-autostart`) spawns a
  real daemon and owns its teardown, so it runs as its own job. If it reports `moved`, read
  the report's remedy paragraph before proposing anything: the obvious fix — make the guard
  stop standing down — is the one that breaks Alpine and macOS, because the degrade path sets
  `ATUIN_DAEMON__ENABLED=false` and under autostart that deletes the spawn itself.

  There used to be a copy of the recipe here. It is gone on purpose, and the reason is the
  point of the third verdict: it seeded its DB through the unreachable-daemon path, so on a
  build that discards, the DB was never created, every row count fell back to `0`, and it
  printed *"the premise holds"* from an apparatus that had never written a row. It was right
  by luck. A second copy of a measurement is a second thing to get wrong, and this one
  shipped wrong. The script seeds with the daemon **off**, runs a daemon-off control arm that
  must write exactly one row before any verdict is allowed, and **proves** each socket is
  unreachable before believing a delta of zero.

  **So what is left for THIS command is the part a script cannot do:** judgment, and the
  version signal.

  1. **Compare versions.** Grep the anchor out of `zsh/00-tools.zsh` — one machine-readable
     line, `# CORE_ATUIN_GUARD_VERIFIED_AGAINST=<version>` — and compare it to atuin's latest
     release, which you are already looking up for "Direct upgrades". A release past the
     anchor is a finding in its own right. Deliberately *not* keyed on the atuin installed
     here: you have no `Bash` in `allowed-tools`, atuin is installed per-OS across eight
     machines, so there is no single "version in use", and the fleet-correct question is
     whether a newer atuin exists that any of them could be on.
  2. **If a verdict issue is open, lead with it.** It is a claim in this repo that has gone
     stale, and a stale one costs history rather than convenience.
  3. **If the premise has `moved`, weigh the remedy** — retire, version-gate, or reshape —
     as an **eight-repo change**: retiring the guard removes a `precmd` hook from every
     interactive shell in the fleet. That is the judgment call the workflow deliberately does
     not make.

  **Two upstream questions the weekly measurement cannot answer**, so they are yours. Each
  is answerable from upstream's docs, source or release notes — none needs a shell, which is
  why they live here and not in the script:

  - **`atuinsh/atuin#3382`** — the accept-but-silent socket: something is listening while the
    daemon behind it is dead, so a `connect(2)` succeeds and no cheap shell-side probe can
    tell it from health. That is the guard's documented blind spot and the reason
    `atuin/config.toml`, `examples/atuin-daemon.service` and `PORTING-MATRIX.md` all steer to
    the plain always-running unit over socket activation. If it is fixed, that steer can be
    relaxed.
  - **Has atuin gained a client-side buffer or queue for the daemon path?** The guard degrades
    a shell **permanently** on the first failed connect, and that is only correct while atuin
    is *discarding* during the outage. An atuin that spools and replays inverts the reasoning,
    and one-way becomes the wrong default. The weekly run probes this only indirectly, with a
    closing daemon-off arm that must land exactly one row — an upstream design note would beat
    that probe, so read for one.

  There used to be a third: *does atuin still health-check its own daemon under `autostart`?*
  It was here because measuring it meant spawning a real daemon, and a question you can only
  answer by reading release notes is the weakest kind of watch — it catches a documented
  change and misses a silent one. #402 built the measurement, so it is no longer yours: the
  `autostart` rows of the verdict table above are what watch it now. What remains genuinely
  unanswerable by measurement is narrower than it first looks, and belongs to the `#3382`
  bullet: every autostart arm must exit 0 and land exactly one row, so a daemon that wedges
  *during* the measured pair already shows up as `unmeasurable` or `moved`. Only one that
  wedges **after** completing the pair escapes — which is the shape upstream reading, not a
  shell, would have to settle.

  Refs #366, #382, #383, #402.

## How to report

Lead with any **required re-verification** from the section above — before the
shortlist, not inside it. It is not a proposal competing for attention on merit; it is
a claim in the repo that may have gone stale, and a stale one costs history rather than
convenience. State the version it was verified against and the newest upstream release you
found — those are the two versions you can actually establish; do not assert what is
installed on this or any other machine, because you cannot see it, and do not paste a
recipe (the measurement lives in `scripts/verify-atuin-guard.sh`). If nothing is due, say
so in one line: silence reads the same as forgetting.

Then a ranked shortlist, each with:

- **Prior decision** — the row in `.claude/tool-decisions.md` if there is one, and what has
  changed since it was written. Say "none" explicitly when there is none: an omitted line reads
  the same as an unchecked one, and the whole point of the ledger is that it was consulted.
- **What it is** and what it replaces or adds.
- **Why it fits** this system's philosophy (or why it does not).
- **Adoption cost** — packaging per distro, config churn, whether it touches the
  load order or the manifest.
- **Recommendation** — adopt / watch / skip, with a one-line rationale.

If a candidate is **declined** on this run, say so in the report and add the row to
`.claude/tool-decisions.md` in the same pass — a decision recorded only in a closed issue is one
the next scan cannot see, which is the failure this file exists to stop.

Propose changes only; do not edit config unless I ask. If I adopt one, the change
is Core (`PORTING-MATRIX.md`, `zsh/`, maybe `mise/`), so keep `core.manifest` in
step, add a `CHANGELOG.md` entry, and `make audit` before the PR.
