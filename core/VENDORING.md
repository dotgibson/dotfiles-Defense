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

**A sync vendors the commit it resolved, not "whatever the branch says now".** `sync-core.sh`
resolves Core once, up front, and everything downstream is addressed by that **SHA**: the
audit gate refuses unless local `HEAD` is that commit, the fetch asks for it by name, the
tree is materialized as `<sha>^{tree}`, and `core_sha`, `core_tag` and the
`git-subtree-split:` trailer are all stamped from it. Before #556 the vendoring step
re-resolved the _branch_, so a push to Core inside the ~250s pre-fan-out audit gave `core/`
a newer tree than the sha recorded beside it — and the mismatch surfaced later, out of
context, as a `TAMPERED (core/ edited since sync)` verdict on a tree nobody had touched.

Two consequences worth knowing. A fan-out is now consistent **by construction**: repos are
still vendored serially, but every one of them materializes the same commit no matter how
long the loop takes. And the sync **checks its own work** — after each repo it compares
`HEAD:core` against the pinned tree, using the same shared comparison `core-integrity.sh`
makes (`scripts/lib/core-lock.sh`), so a run that somehow still landed inconsistent fails in
the run that caused it rather than in whatever command next happens to check.

If Core cannot be resolved at all — no network _and_ no local clone that knows the ref — the
sync now **refuses outright** instead of vendoring from the branch and skipping `core.lock`,
which was itself a way to produce the `TAMPERED` state with no race required.

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

`bootstrap.sh` calls `blib_link_os_layer`, which wires four files if they exist:

| Your file | Becomes |
| --- | --- |
| `os/<os>.zsh` | `$ZDOTDIR/80-os.zsh` |
| `os/<os>.conf` | `$XDG_CONFIG_HOME/tmux/os.conf` |
| `os/<os>.gitconfig` | `$XDG_CONFIG_HOME/git/os.gitconfig` |
| `os/<os>.capabilities` | `$ZDOTDIR/os.capabilities` |

This is where an OS-absolute path is **correct**: your package manager, your clipboard
backend, your Homebrew prefix, your credential helper. Core is forbidden from naming any
of them — see `PORTABILITY.md`.

`os/<os>.capabilities` is the newest of the four and the odd one out: it is **data, not
config**. Flat `KEY=value`, declaring your package-manager verbs, your scheduler and your
opt-in tool list, so Core can dispatch through them instead of branching on your distro.
Core **reads** it and never sources it, and it is deliberately un-numbered — the other
three are ordered against something, a declaration is read on demand. Copy
`core/examples/os.capabilities.example` and validate with:

```bash
core/scripts/check-capabilities.sh os/<os>.capabilities --packages install/packages.txt
```

Absence is not fatal: Core falls back to its built-in defaults, so a repo adopts this by
adding a file, not by re-bootstrapping in lockstep. The reader is **silent** about a
missing declaration — absence is the normal state during the rollout, and a warning on
every interactive shell and every tmux split was worse than the thing it warned about
(#715). Set `CORE_CAP_LOUD=1` to opt into it.

**Eight required keys**, all package-manager verbs plus `SCHEDULER` (`systemd` \| `launchd`
\| `cron` \| `none` — `cron` is what an OpenRC box gets); the validator is the
schema, so read `check-capabilities.sh` rather than trusting this list to stay current.
Everything else is optional, and optional means _Core's default reproduces what your box
does today_ — declare only what your archive actually needs:

| Optional key | What it is for |
| --- | --- |
| `TOOLS_OPTIN` | tools `core-doctor` reports as OPT-IN rather than MISSING. A declared list **replaces** Core's default rather than adding to it, so re-state everything you still consider optional. The one key where a partial declaration falls back per-key |
| `PKG_ASSUME_YES` | the flag `up -y` appends. **Omit to mean "never auto-confirm"** — the right answer for Arch, Gentoo and Alpine |
| `PKG_UPGRADE_PRE` | run before the upgrade, both paths; **failure aborts** |
| `PKG_CLEANUP` | run after a successful _full_ upgrade (`autoremove`, `brew cleanup`) |
| `PKG_UPGRADE_PARTIAL` | upgrade only named packages. **Omitting it is a safety declaration** — `up -i` refuses without one |
| `PKG_COUNT_REFRESH` | run before `PKG_COUNT_PENDING` in the count path only (Homebrew) |
| `SCHEDULER_UNIT_DIR` | the **directory** your scheduler reads units from. **Required** for `systemd`/`launchd`, forbidden for `cron`/`none`. A directory, not a path — Core appends its own unit name |
| `MAINT_UNATTENDED_UPGRADE` | `1` to let the daily run apply **system** upgrades. **Omitting it refuses**, and that is the safe direction — it is the second of two gates, with the operator's `MAINT_SYSTEM_UPGRADE=1` |
| `PKG_COUNT_EXIT_TRUSTED` | `1` when a non-zero exit from `PKG_COUNT_PENDING` means "could not answer", so the count reports `-1` rather than `0`. Off by default — most archives overload that status |
| `PKG_PENDING_MATCH` | ERE selecting lines that name a package. Default `.` |
| `PKG_PENDING_FIELD` | which field holds the name. Default `1` |
| `PKG_PENDING_FS` | awk field separator. Default whitespace; zypper's table is `\|` |

Two things that bite when authoring one:

- **A `#` inside a value is not a comment.** The reader keeps it, so
  `PKG_OWNS=dnf provides   # owns this` declares a verb that does not exist. The
  validator rejects it; put the note on its own line.
- **An ERE cannot end in a literal space.** Trailing whitespace is trimmed, so write
  `PKG_PENDING_MATCH=^Inst[[:space:]]`, never `^Inst` with a trailing space.

### What Core already does — do not re-add it

The mirror of that rule, and the one that is easy to get wrong in the other direction: an
OS layer carrying **portable** logic is invisible to every gate the fleet has. `audit-core.sh`
§5c looks for OS-specifics leaking _into_ Core; nothing looked for portable code stranded
_outside_ it, which is how the same block came to be hand-maintained in seven OS repos, in
three drifted variants, until #449. Core owns these now:

| Don't write | Because Core already does it |
| --- | --- |
| `direnv hook zsh` | `core/zsh/00-tools.zsh`, band 00 — loads under every `CORE_PROFILE` |
| `gh completion -s zsh` | `core/zsh/00-tools.zsh`, band 00 — generated into an `fpath` dir and autoloaded, with a `compdef` re-assert at band 45 so carapace's bridge does not win |
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

### The gates you run OVER the vendored tree

The contract above is about what your `bootstrap.sh` calls. This is the other half, unwritten
until #623: a repo also runs **its own gates** over `core/`, and those have to agree with
Core's policy or they measure a different thing.

**Secret scanning is the concrete case.** Core's reusable `lint-call.yml` states the rule —
_one policy file, Core's, so every repo is measured the same way and no repo can widen its own
allowlist_ — and passes `-c` accordingly. So must yours:

```sh
gitleaks dir . -c core/gitleaks.toml --no-banner --redact
```

Without `-c`, gitleaks uses the **stock** rule set, where several rules match on
credential-shaped _position_ rather than on content. On the 2026-08-23 sync that flagged the
vendored `core/CHANGELOG.md` in four repos — Core's own explanation of the allowlist read as
a violation of it, on a sync carrying no credential.

**A repo-local `.gitleaks.toml` is permitted, but it must extend Core's, not replace it.**
gitleaks auto-discovers a config at the scan root, so a private one silently governs _every_
scan in that repo — including invocations that pass no `-c` and look, from the command line,
like a stock scan. If you need a distro-specific rule:

```toml
[extend]
path = "core/gitleaks.toml"
```

`useDefault` is not needed and should be omitted: Core's own config already extends the
upstream defaults, and that inheritance carries through. Verified with the pinned gitleaks
8.30.1 — the variable-reference form Core allowlists passes, and a real literal credential in
the same position is still caught.

`audit-core.sh` §5g **fails** on a repo that does neither. It shipped advisory, on the
principle that a gate red from its first run is a gate someone turns off; once the fleet was
clean (#624 — `dotfiles-Alpine` and `dotfiles-Gentoo` each carried a private config that
replaced Core's rather than extending it) that reason expired, and the posture flipped. Still
skipped entirely when the siblings are not checked out, exactly like §5f above — so it is inert
in CI, which clones only Core, and bites locally and in any sweep that clones the fleet.

The reason it is worth blocking on: this failure is **quiet**. A repo running its own rule set
is green, and stays green as that rule set drifts, because nothing compares it to Core's. The
next person to look sees a passing gate — which is worse than a red one, not better.

### Declaring how you satisfy a gate you do not call

Core publishes its CI as **reusable workflows**, and most repos consume them as a 3–5 line
caller. Some do not — usually because they cover _more_, not less. That divergence is
defensible; being **invisible** is the problem.

Coverage used to be inferred by reading each repo's `uses:` lines, and that inference is
wrong for any repo that satisfies a gate its own way. It has misfired twice, identically and
both times in good faith — dotgibson/dotfiles-MacBook#154 and #178 — because a rollout audit
had no way to tell _not covered_ from _covered elsewhere_.

So if your repo does not call one of Core's reusable workflows, say why in
`.github/core-gates.txt`, one line per gate:

```text
<gate> own  <how it is satisfied here>
<gate> none <why this repo does not need it>
```

Only the exceptions need a line — anything calling the reusable is derived from its own
`uses:`. `scripts/fleet-coverage.sh` renders the register, `make fleet-coverage` prints it,
and `audit-core.sh` §5h asserts every gate × repo cell is filled, so a **new** gate cannot
ship without each repo declaring a position on it.

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
git subtree add --prefix=core <core-remote> refs/tags/v4 --squash
```

**A released tag, never `main`.** The fan-out pins each repo to the exact commit a
release tag points at (`sync-fanout.yml` passes `CORE_BRANCH=<sha>`), so `core.lock`
records that commit and `git describe` stamps the named tag. A tree vendored from
whatever `main` happened to be is not that commit, and `core-integrity` — which
validates `core/` against the commit `core.lock` records — reports a freshly
hand-vendored repo as TAMPERED before it has done anything wrong.

`subtree add` writes no `core.lock`. Stamp provenance from a Core checkout, which is
the only sanctioned writer of that file:

```sh
CORE_BRANCH=refs/tags/v4 ./scripts/sync-core.sh dotfiles-<Distro>
```

Then register the repo **here**, which is **one line** in `scripts/os-repos.txt`:

```sh
echo 'dotfiles-<Distro>' >> scripts/os-repos.txt   # then re-sort: MacBook first, rest alphabetical
```

This used to take **four** coordinated edits — that file plus a hardcoded fallback array
in each of `scripts/sync-core.sh`, `scripts/fleet-drift.sh` and `scripts/core-integrity.sh`,
so a repo registered in the file alone silently disappeared from the fan-out in exactly the
situation you were least able to spot it. Those arrays are gone (#669); every fleet script
now reads the file through `load_os_repos` in `scripts/lib/common.sh`, and an unreadable or
empty file stops those three gates outright rather than substituting a stale list.

`dotfiles-Windows` is deliberately absent from the file: it replicates the host config
natively in PowerShell and vendors no `core/` at all.

**The scaffold is a starting point, not the finished contract.** A freshly generated repo
has no `core.lock`, no core-guard hook, and no `core-integrity` workflow — so it carries
no provenance and nothing yet stops a hand-edit to `core/`.
Close all three before treating the repo as part of the fleet: run one `sync-core.sh` from
Core (which writes `core.lock` and installs the guard), and add the `core-integrity` and
`bootstrap` workflow callers. (The generated README used to suggest a raw
`git subtree pull` — the stale-lock path this document warns about — and now points at the
fan-out instead.)
