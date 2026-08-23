# VENDORING.md — the contract, from the OS repo's side

Every OS repo carries a `core/` directory that is a **vendored copy of this repo**,
delivered by `git subtree`. This document is for the person working in
`dotfiles-Fedora` / `dotfiles-Arch` / `dotfiles-Offense` / … who needs to know what they may
touch, what will be overwritten, and how to get a fix upstream.

`ARCHITECTURE.md` explains _why_ the system vendors. This explains _how to live with it_.
When a rule here drifts from `README.md` or `CONTRIBUTING.md`, those win — fix this.

## The one rule

**Never edit anything under `core/`.** That tree is a copy, and the next `make sync`
**replaces it wholesale** with Core at the pinned commit. Any edit there is simply gone —
committed or not, conflict or not.

That is a deliberate change from how this worked until #587, and the reason is worth
knowing. The sync used to be a `git subtree pull --squash`, i.e. a **merge**, which
located its base by grepping history for the previous sync commit's `git-subtree-split:`
trailer. Every repo squash-merges its fan-out PR, and a squash keeps the original body
only if it happens to be carried over — so the trailer died intermittently, and when it
did, the merge silently fell back to an **older** base and replayed changes the tree
already had. Seven of nine repos lost the marker in the v4.14.3 round, and the v4.15.0
fan-out then failed in all nine at once, conflicting on `core/CHANGELOG.md` and
`core/core.version`.

Merging was never the right operation here. `core/` is a pure copy, so "make it identical
to Core@`core_sha`" has exactly one correct answer and needs no base. The replacement is
also self-healing: a `core/` that drifted for any reason is corrected by the next sync
rather than conflicting against its own drift. What it does **not** do is make editing
`core/` safe — the edit is still lost, just quietly and immediately rather than as a
mid-fleet conflict. That divergence is what the integrity check exists to catch.

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

At the **root** of each OS repo, outside `core/` so a sync cannot clobber it:

```ini
core_version=4.10.0
core_sha=cd4278eb…            # the FULL Core commit that was vendored
core_ref=v4.10.0-release      # the ref that was FOLLOWED — see below
core_tag=v4.10.0              # only once Core carries a tag describing that commit
```

`core_tag` names the **specific release**, never the moving `v4` major alias. Both tags point
at a release commit, and `git describe` used to be free to pick either — so every repo in the
fleet once stamped `core_tag=v4`, a provenance field whose target is deliberately re-pointed on
the next cut (#515). `sync-core.sh` now filters describe to the `vX.Y.Z` shape; when only the
alias exists the field is **omitted**, which is why it is documented as conditional. An absent
`core_tag` is honest, a `v4` is not.

`core_ref` records **what the sync followed**, which is not always a branch:

| How the sync ran | `core_ref` holds |
| --- | --- |
| release fan-out (`sync-fanout.yml`) | the pinned **commit** — each release PR vendors the exact released commit, not a moving `main` |
| ad-hoc `make sync` | the **branch name**, normally `main` |

That distinction is the field's whole value: `core_sha` says _which commit_, `core_ref`
says _how it was chosen_. It was called `core_branch` until #453, which made the lock file
disagree with this document — a fan-out wrote a SHA into a field documented as a branch,
duplicating `core_sha` and adding nothing.

Written by `sync-core.sh` and committed as `chore(core): core.lock → <sha> (v<version>)`
when only the lock moved, or `chore(core): sync Core → v<version> (<sha>)` when the vendored
`core/` tree moved with it. Either form gains `+ N workflow file(s)` when the repo SHA-pins
its reusable callers (see below) — **files**, not pins: one workflow file can carry several
pins, and the number is a count of files rewritten (#491). It exists so the question "which
Core is this box on?" is answerable **offline and in O(1)**, without parsing `git log` for the
subtree-squash marker.

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
| the `core/` subtree | the vendored tree | `core-integrity` |
| `core.lock` `core_sha` | the provenance stamp | `core-integrity` (it resolves this to the tree it compares) |
| the workflow `uses:` pins | which reusable actually executes | the repo's own pin check, if it has one |

Both of the first two rows named a `verify-core` until #454. **No such script has ever
existed in this repo** — it was cited across the docs as a byte-for-byte
split-vs-upstream check, and readers (this one included) took the coverage on faith.
`core-integrity.sh` is the gate that actually runs: it resolves `core.lock`'s `core_sha`
to a tree object and compares it against your `core/`, which answers "has this copy been
tampered with". It does **not** answer "does Core contain a file its manifest never
listed" — that is `audit-core.sh`'s job, upstream, and §4b (nvim module reachability) is
what closed the one place the manifest could not see.

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
  gate for another. This is also why `core_tag` excludes the `v4` alias (#515) — a `# v4`
  comment here would hand Renovate a bump target that never moves.

Nothing else is rewritten — a third-party action pinned in the identical
`@<sha> # <version>` shape is matched on the `dotgibson/dotfiles-core/` prefix and skipped.

**Do not pull the subtree by hand.** A raw `git subtree pull` updates `core/` but not
`core.lock`, so `core-integrity.sh` compares your tree against a commit the lock no longer
describes and reports `TAMPERED` until the lock is regenerated. `sync-core.sh` commits both
together, and `sync-fanout.yml` runs it for you on every release. If you have already done
it by hand, the fix is to re-run the fan-out from Core rather than to patch the lock. See
`RELEASE-STRATEGY.md` on the pinning model.

**And do not reach for a local `make core-lock`.** Four consumers have one — `dotfiles-Arch`,
`dotfiles-MacBook`, `dotfiles-openSUSE` and `dotfiles-Offense` — and only Offense's is a
redirect back to the fan-out. The other three are **independent generators of a format Core
owns**, and they have already drifted from it and from each other: Arch hardcodes
`core_branch=main` (so regenerating a release-pinned lock silently discards which commit was
vendored), openSUSE writes the SHA into that field, and MacBook reads the previous value
back. None of them knows about the `core_ref` rename (#453), so running one now produces a
lock file the fleet's own tooling and this document disagree with.

`sync-core.sh` is the **only** sanctioned writer of `core.lock`. A second generator cannot be
kept in step with it by discipline — that is what these three demonstrate.

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

### What Core already does — do not re-add it

The mirror of that rule, and the one that is easy to get wrong in the other direction: an
OS layer carrying **portable** logic is invisible to every gate the fleet has. `audit-core.sh`
§5c looks for OS-specifics leaking _into_ Core; nothing looked for portable code stranded
_outside_ it, which is how the same block came to be hand-maintained in seven OS repos, in
three drifted variants, until #449. Core owns these now:

| Don't write | Because Core already does it |
| --- | --- |
| `direnv hook zsh` | `core/zsh/00-tools.zsh`, band 00 — loads under every `CORE_PROFILE` |
| `gh completion -s zsh` | `core/zsh/45-plugins.zsh`, after `compinit` and after carapace |
| `uv generate-shell-completion zsh` | same |
| `ty generate-shell-completion zsh` | same |
| your own `_IS_WSL` probe | `_core_is_wsl` (`core/zsh/00-tools.zsh`) |
| your own `ssh/config` | `core/ssh/config` — symlinked to `~/.ssh/config` by `blib_link_core` |

So a WSL nicety is written against Core's predicate:

```zsh
if _core_is_wsl; then
  alias open='explorer.exe'
  command -v wslview >/dev/null && alias xdg-open='wslview'
fi
```

The reusable `lint` workflow fails your repo if it grows one of these back — one rule,
`scripts/lib/common.sh :: _core_owned_block_hits`, shared by every caller. Hooking a tool
that exists on **your** OS and nowhere else is still your business and is never flagged.

### What your `bootstrap.sh` is expected to call

The mirror of the mirror. The section above is a **negative** contract — do not re-add what
Core owns — enforced from your side by the reusable `lint` workflow. This is the **positive**
one, and until #516 it did not exist: `lib/bootstrap-lib.sh` explained what each helper does
but never said a bootstrap had to call it, so a repo still hand-rolling the thing a helper
replaces was not, on paper, doing anything wrong. Helpers get added to that file over time —
usually because one repo hit the bug — and nothing told the other eight.

| Call | Instead of | Because |
| --- | --- | --- |
| `blib_resolve_su` | `[[ "$(id -u)" -eq 0 ]]` + inline `sudo` | that is an **arithmetic** comparison, and bash evaluates an empty `id` output as `0` — a box where `id` is missing or off `PATH` concludes "we are root" and runs every privileged command unescalated. Also handles doas, and the sudo-less container/first-boot-WSL boxes where hard-coded `sudo` dies at exit 127 |
| `blib_priv` | inline `sudo` | one escalator token, resolved once, honouring `BLIB_SU=` (already root) and `BLIB_SU=doas` |
| `blib_sudo_keepalive_start` | nothing | after a long install sudo's timestamp has expired; the re-prompt goes to a discarded stderr and the run hangs with no visible cause |
| `blib_user_bindirs_on_path` | nothing | without `~/.cargo/bin` and `~/.local/bin` on `PATH`, every `command -v` guard misses and the run rebuilds tools it already installed — minutes per invocation on a source-based distro, discarded |
| `blib_note_fail` + `blib_failures_report` | `echo "skipped: …"` | a bare echo cannot be counted. Recording a failure and never reporting it is worse than not recording it: the script ends `complete` and exits 0 on a box that got none of its tooling |
| `blib_wire_summary` | nothing | the `N linked · N seeded · N backed up` tally, without which a re-link is unverifiable |
| `blib_install_core_guard` | nothing | installs the local pre-commit hook that rejects a hand-edit of vendored `core/` — the one rule at the top of this file. Only `sync-core.sh` installs it otherwise, i.e. only on the maintainer's machine, so every other clone has no local guard at all |
| `blib_install_system_file` | `_blib_priv tee` | backs up whatever was at that `/etc` path first and no-ops when byte-identical. Hand-rolled `tee` clobbered a real `/etc/wsl.conf` (#475) |
| `BLIB_DRY` | nothing | a `--dry-run` flag is the only way CI can exercise anything past `--links-only` |

`audit-core.sh` reports which repos are short of this list — **advisory, not blocking**: most
of the fleet is short today, and a gate that is red on arrival is a gate someone turns off.
It reads `scripts/os-repos.txt` and looks at each sibling's `bootstrap.sh`, so it says nothing
in CI, where only Core is checked out. Role repos (`dotfiles-Defense`, `dotfiles-Offense`)
layer on an OS bootstrap and install no packages, so the two keepalive/PATH helpers are
exempt for them.

#### `ssh/config` — the one with a deletion order (#450)

Seven OS repos each shipped `ssh/config` at their **root**, and Core's `blib_link_core`
read it from there — a shared library depending on a file it neither owned nor listed in
`core.manifest`. All seven `Host *` blocks were byte-identical; the only functional
divergence in the fleet was one repo's per-service key names. Core owns the file now.

**Delete your repo's copy only AFTER you have vendored a Core that carries it** (check
`core.lock`). Reversed, the box loses its ssh config entirely — `blib_link_core` links
`core/ssh/config`, and until the sync lands there is nothing at that path. Running both
in the meantime is harmless: the old file is simply no longer read.

Anything host- or OS-specific goes to a drop-in instead of a fork:

| What | Where |
| --- | --- |
| host-local (per-service keys, work bastions, 1Password socket path) | `~/.ssh/config.d/*.conf` — untracked |
| genuinely OS-specific | `ssh/os.conf` in your repo → `~/.ssh/config.d/50-os.conf` |

Core's config `Include`s `~/.ssh/config.d/*.conf` **first**, and ssh is
first-obtained-value-wins, so a drop-in beats the vendored defaults. The exception is
`IdentityFile`, which accumulates: a drop-in's key is tried first and Core's remains a
fallback. That file's header documents both.

A tool that belongs to the whole fleet but isn't listed above is a **Core** change, not an
OS one: send it upstream (below) rather than adding a copy each repo has to maintain.

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
