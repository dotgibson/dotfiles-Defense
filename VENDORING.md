# VENDORING.md — the contract, from the OS repo's side

Every OS repo carries a `core/` directory that is a **vendored copy of this repo**,
delivered by `git subtree`. This document is for the person working in
`dotfiles-Fedora` / `dotfiles-Arch` / `dotfiles-Offense` / … who needs to know what they may
touch, what will be overwritten, and how to get a fix upstream.

`ARCHITECTURE.md` explains _why_ the system vendors. This explains _how to live with it_.
When a rule here drifts from `README.md` or `CONTRIBUTING.md`, those win — fix this.

## The one rule

**Never edit anything under `core/`.** That tree is a copy, and the next `make sync`
merges upstream Core over it. Be precise about what that does: a subtree pull is a
**merge**, not a wholesale replacement — an uncommitted edit is lost, while a committed
one either conflicts (stopping the sync mid-fleet) or survives, and a surviving edit is
worse, because `core/` now silently disagrees with the Core commit `core.lock` pins.
That divergence is exactly what the integrity check exists to catch.

Two things enforce this, and it is worth knowing that neither is complete on its own:

- a **local** `pre-commit` hook installed into `.git/hooks` by `blib_install_core_guard`,
  which rejects any commit touching `core/`. It protects exactly one machine, and is
  skipped if you have set `core.hooksPath` or already have your own pre-commit hook.
- **`scripts/core-integrity.sh`**, run weekly by `core-integrity.yml` and on each PR,
  which compares your `core/` tree hash against the Core commit recorded in `core.lock`.
  This is the durable one — it runs in CI, so it catches an edit made on any machine.

The sanctioned bypass is `DOTFILES_ALLOW_CORE_EDIT=1`, which `sync-core.sh` sets for its
own commits. If you find yourself reaching for it by hand, the change belongs upstream.

## `core.lock` — what Core am I carrying?

At the **root** of each OS repo, outside `core/` so a subtree pull cannot clobber it:

```ini
core_version=4.10.0
core_sha=cd4278eb…            # the FULL Core commit that was vendored
core_branch=main
core_tag=v4.10.0              # only once Core carries a tag describing that commit
```

Written by `sync-core.sh` and committed as `chore(core): core.lock → <sha> (v<version>)`
— or `core.lock + N workflow pin(s) → …` when the repo SHA-pins its reusable callers (see
below). It exists so the question "which Core is this box on?" is answerable **offline and
in O(1)**, without parsing `git log` for the subtree-squash marker.

Two consumers depend on it:

- **`fleet-drift.sh`** reads `core_sha` and compares it against the latest **released
  Core tag** — not against Core's `main`. Being _ahead_ of the tag but on main's lineage
  is the normal between-releases state and is reported as current, not drift.
- **`core-integrity.sh`** resolves `core_sha` to a tree and compares it with your actual
  `core/`, which is how a hand-edit is detected.

## The third reference: reusable-workflow SHA pins

A repo names the vendored Core in **three** places, not two — and the third is the one that
decides which Core's code actually _runs_:

| Reference | What it is | Gated by |
| --------- | ---------- | -------- |
| the `core/` subtree | the vendored tree | `core-integrity` + `verify-core` |
| `core.lock` `core_sha` | the provenance stamp | `verify-core` |
| the workflow `uses:` pins | which reusable actually executes | the repo's own pin check, if it has one |

The pins are not inert: `auto-tag-call` holds `contents: write` and pushes tags, and
`notify-web-call` is handed two secrets. Running a different Core's version of those than
the tree you vendored is the drift `core.lock` exists to prevent, one layer up — and it is
invisible to both existing gates, which read a tree object and a split marker, never a
workflow.

`sync-core.sh` therefore moves the pins in the **same commit** that stamps `core.lock`. Two
rules govern what it touches:

- Only an **existing 40-hex pin** moves. A caller on the mutable `@v4` alias is left alone —
  taking the alias is a deliberate per-repo policy (most of the fleet does, and it is what
  lets a guard fix reach them with no edit), so converting one into a SHA pin would change
  that repo's update model behind its back.
- The trailing **`# vX.Y.Z` comment moves with the SHA**, written as `core_tag` verbatim.
  Renovate reads that comment to pick the next bump, and a pin check compares it against
  `core_tag` independently of the SHA, so moving one without the other just trades one red
  gate for another.

Nothing else is rewritten — a third-party action pinned in the identical
`@<sha> # <version>` shape is matched on the `dotgibson/dotfiles-core/` prefix and skipped.

**Do not pull the subtree by hand.** A raw `git subtree pull` updates `core/` but not
`core.lock`, so `core-integrity.sh` compares your tree against a commit the lock no longer
describes and reports `TAMPERED` until the lock is regenerated — and no per-repo target
regenerates it (`make core-lock` is absent in most consumers, and where it exists it only
prints a redirect back to the fan-out). `sync-core.sh` commits
both together, and `sync-fanout.yml` runs it for you on every release. If you have already
done it by hand, the fix is to re-run the fan-out from Core rather than to patch the lock.
See `RELEASE-STRATEGY.md` on the pinning model.

## Number bands — where your files go

`core/zsh/loader.zsh` globs `$ZSH_CFG/[0-9][0-9]-*.zsh` and sources them in numeric
order. The band decides the owner:

| Band | Owner | Example |
| --- | --- | --- |
| `00`–`69` | **Core** | `20-aliases.zsh`, `60-update.zsh` |
| `70`–`84` | **OS-native** | `80-os.zsh` ← symlinked from your `os/<os>.zsh` |
| `85`–`94` | **Role** | Offense / Defense fragments |
| `95`–`99` | **host-local** | `99-local.zsh` (gitignored, never committed) |

### The footgun: `CORE_PROFILE` gates by NUMBER, not by authorship

The loader has no owner metadata. `CORE_PROFILE` sets a ceiling — `minimal=30`,
`standard=50`, otherwise `69` — and **skips Core-band fragments above it**. Fragments
numbered **≥ 70 always load**, regardless of profile.

So a file you drop in a _gap in the Core band_ — say `22-mytweak.zsh` — is not treated as
yours. It is treated as Core, and it will silently vanish under `CORE_PROFILE=minimal`.

**Claim a number in your own band.** OS work goes at 70–84, role work at 85–94, anything
machine-specific at 95–99.

## Adding your OS layer

`bootstrap.sh` calls `blib_link_os_layer`, which wires three files if they exist:

| Your file | Becomes |
| --- | --- |
| `os/<os>.zsh` | `$ZDOTDIR/80-os.zsh` |
| `os/<os>.conf` | `$XDG_CONFIG_HOME/tmux/os.conf` |
| `os/<os>.gitconfig` | `$XDG_CONFIG_HOME/git/os.gitconfig` |

This is where an OS-absolute path is **correct**: your package manager, your clipboard
backend, your Homebrew prefix, your credential helper. Core is forbidden from naming any
of them — see `PORTABILITY.md`.

## Getting a fix upstream

A bug in `core/` is a bug **here**, in `dotfiles-core`. Two routes:

1. **Preferred** — open a PR against `dotfiles-core`. Green `make audit`, `core.manifest`
   updated if you added a file, `CHANGELOG.md` entry under `[Unreleased]`.
2. **From the OS repo** — `.bin/sync-upstream.sh` (the `gsync` verb) runs
   `git subtree push --prefix=core <core-remote> <branch>` and opens the round trip from
   where you found the problem. It refuses on a dirty tree, and refuses to run from
   `dotfiles-core` itself. Only the `core` prefix can round-trip: splitting a
   subdirectory such as `nvim/` produces a history with no common ancestor.

Then Core releases, and the fix reaches every repo on the next fan-out.

## What a sync looks like from your side

On a Core release, `sync-fanout.yml` opens a PR in your repo titled around
`sync/core-vX.Y.Z`. It contains the subtree squash-merge plus the `core.lock` bump.

**It opens PRs; it never merges them.** Review and merge yourself — the canary
(`dotfiles-MacBook`) first, then the rest, per `RELEASE-STRATEGY.md`. Merging that PR is
also what triggers your own repo's `auto-tag` workflow to cut your next `vX.Y.Z`, because
an OS repo carries two independent version lines: the Core it vendors, and its own.

If `make fleet-drift` shows you `BEHIND`, the fix is to merge that PR — not to touch
`core/`.

## One-time setup for a brand-new OS repo

Use `scripts/new-os-repo.sh`, which scaffolds the layout and runs:

```sh
git subtree add --prefix=core <core-remote> main --squash
```

Then register the repo **here**, which takes **four coordinated edits**, not one:
`scripts/os-repos.txt` (the source), plus the hardcoded fallback arrays in
`scripts/sync-core.sh`, `scripts/fleet-drift.sh` and `scripts/core-integrity.sh`. Those
fallbacks run when the data file is missing or unreadable, so a repo registered in the
file alone silently disappears from the fan-out in exactly the situation you are least
able to spot it. `scripts/test-core.sh` asserts all four agree.

`dotfiles-Windows` is deliberately absent from all four: it replicates the host config
natively in PowerShell and vendors no `core/` at all.

**The scaffold is a starting point, not the finished contract.** A freshly generated repo
has no `core.lock`, no core-guard hook, and no `core-integrity` workflow — so it carries
no provenance and nothing yet stops a hand-edit to `core/`. Its generated README also
suggests a raw `git subtree pull`, which is the stale-lock path this document warns about.
Close all four before treating the repo as part of the fleet: run one `sync-core.sh` from
Core (which writes `core.lock` and installs the guard), add the `core-integrity` and
`bootstrap` workflow callers, and fix the generated README's update instructions to point
at the fan-out.
