# v5 proposal — the OS layer becomes a contract

> **Status: PROPOSED — not accepted, nothing implemented.** This is a plan, not a
> record. It is the artifact [#662](https://github.com/dotgibson/dotfiles-core/issues/662)
> asks for, and the nineteen other issues on the `v5.0.0` milestone are subordinate
> to what it decides. An issue this proposal rejects should be closed
> `not_planned` with a reason, not left open.
>
> Written in the same RFC "Current → Proposed → What breaks" voice as
> `V4-PROPOSAL.md`. When a claim here drifts from `RELEASE-STRATEGY.md`,
> `CONTRIBUTING.md` or `ARCHITECTURE.md`, **those win** — fix this.

## 1. Summary

Core is at `4.18.0` with an empty `[Unreleased]`, and the whole fleet is synced to
it. This proposes `v5.0.0` as a single coordinated change to one idea:

**the OS layer stops being a convention and becomes a contract.**

v4 did this to the *load order*. Modules stopped being a hand-listed array in each
OS repo's `.zshrc` and became `NN-` prefixed fragments the loader globs and sorts,
so any layer can slot in without Core knowing its name. v5 does the same to
*capability, payload and surface*:

1. **`os.capabilities`** — each OS repo declares what it provides (package-manager
   verbs, clipboard backend, scheduler, opt-in tool split) and Core dispatches
   through the declaration instead of hardcoding 154 package-manager references.
2. **Vendor only what is Core** — `sync-core.sh` materializes `core.manifest` plus a
   declared consumer list, instead of the whole repo. Today 76% of what ships to
   every machine is not Core.
3. **Retire the surfaces nothing uses; declare the ones things do** — delete
   `CORE_PROFILE`, and turn `HAVE_*` from an accidental export into a stated API.
4. **`clip` learns what a secret is** — a sensitive mode, because `optoken` currently
   leaves live TOTP codes in a tmux paste buffer.

They are bundled because they touch the **same three contracts** — the
`bootstrap.sh` symlink set, the load chain, and what a vendored `core/` contains.
Shipping them separately would make every OS repo re-bootstrap four times for one
architectural idea. One `v5.0.0` pays the fan-out cost once — the batching
discipline `RELEASE-STRATEGY.md §2` is built around, and the same argument
`V4-PROPOSAL.md §2` made.

## 2. Why these earn a major (and the doc work does not)

Per `RELEASE-STRATEGY.md:106-109`, a **MAJOR** is chosen by *blast radius on a
host*: reordering the load chain, removing or renaming a public alias / binding /
function, changing the `bootstrap.sh` symlink contract, or dropping a manifest
path.

| change | trigger it clears |
| ------ | ----------------- |
| §3 `os.capabilities` | a new bootstrap symlink **and** a new load-order slot before `20-aliases` |
| §4 vendoring allowlist | changes what a consumer repo receives; `core-integrity` must be retaught in lockstep |
| §5 delete `CORE_PROFILE` | removes a documented public knob |
| §5 declare `HAVE_*` | removes nine public globals |
| §6 `clip --sensitive` | changes observable behaviour of a public binary |

For contrast, §7's ride-alongs — retiring `git subtree` from the docs, deleting
`V4-PROPOSAL.md`, fixing three stale claims — re-vendor with **zero migration**.
They ride along because a major is when the fleet re-reads its own documentation,
not because they need one.

## 3. Change 1 — `os.capabilities`

### 3.1 Current

`CONTRIBUTING.md`'s three-layer test is absolute: *if it changes when the OS
changes, it's not Core*. Core violates it **154 times**:

| file | package-manager references |
| ---- | -------------------------- |
| `zsh/60-update.zsh` | 88 |
| `maint/dotfiles-maint.sh` | 49 |
| `zsh/30-functions.zsh` | 17 |

Including `grep -qi tumbleweed /etc/os-release` to choose `zypper dup` over
`zypper up`. `ARCHITECTURE.md:51-74` names two of these as deliberate exceptions
and defends them:

> It stays in Core because `up` is **one verb with N backends** — structurally
> identical to `bin/clip` — and putting it here means every machine has the same
> muscle memory instead of eight subtly different update commands.

**That defence of the verb is correct and is not in question.** What has expired
is the defence of the *implementation*: one verb with N backends is what a
dispatch table is for. The verb belongs to Core; the backends belong to the layer
that changes with the OS.

Core has already written down that it needs this artifact —
`CHANGELOG.md:927-931`, on `core-doctor` mis-reporting `jj` and `ast-grep`:

> a Core-side list cannot say "opt-in there, expected here", so they stay
> expected. **Fixing that properly needs a per-repo manifest; this is the fallback
> default until one exists.**

The same absence shows up structurally. Nine repos have nine Makefile
vocabularies — two spellings of "dry run", five of "verify core", two of "check
packages", and two repos with no Makefile at all. Five of nine have no
repo-owned tests, **including Fedora**, the template `PORTING-MATRIX.md` §Per-repo
recipe tells you to `cp -r`.

### 3.2 Proposed

A declarative, per-repo `os.capabilities` that each OS repo authors and Core
dispatches through. At minimum it expresses:

- **package-manager verbs** — refresh, upgrade, install, remove, search,
  owns-file, and *count-pending* (the one `up` needs, and the most divergent
  across archives)
- **the upgrade dialect** where a distro has more than one (Tumbleweed `dup` vs
  Leap `up`)
- **scheduler** — launchd vs systemd, today branched inside `zsh/55-maint.zsh`
- **the opt-in vs expected tool split** that `core-doctor` needs

It deliberately does **not** express a **clipboard backend**. This section listed one
until #663 measured the cost: `bin/clip` is re-exec'd by nvim and tmux on *every* yank
and paste, and its WSL probe was already rewritten to avoid forking a `grep` per
invocation (`bin/clip:8-11`). Adding a file read and parse to that path would spend
exactly what that optimisation bought, on a value that changes once per machine. Its
`exec` ladder stays hardcoded.

Most of the content already exists in tabulated form and should be transcribed,
not re-derived — `PORTING-MATRIX.md` §"Package-manager commands" covers all seven
archives, and its ²¹ footnotes carry the opt-in split.

Four decisions the implementation had to make. #663 settled all four:

1. **Format.** Flat `KEY=value`, **read and never sourced** — sourcing a per-repo file
   into a login shell is a code-execution surface, and extraction is not. The precedent
   is `scripts/tool-versions.env`, and the reason is already recorded at
   `scripts/setup.sh:23-26`. Values are multi-word command prefixes; the same shape is
   one `sed` away in bash, which `maint/dotfiles-maint.sh` needs.
2. **Load position.** A new Core fragment at **band 02** (`zsh/02-capabilities.zsh`),
   inside the Core band so every `CORE_PROFILE` loads it — `minimal`'s ceiling is 30,
   and a lean profile must not silently lose the dispatch table. That is the
   load-chain change.
3. **Wiring.** A fifth overlay inside the existing **`blib_link_os_layer`**, not a
   third linker: `os/<os>.capabilities` → `$ZDOTDIR/os.capabilities`, beside the
   `.zsh`/`.conf`/`.gitconfig` it already links. Every OS repo's `bootstrap.sh` calls
   that helper today, so no repo edits a bootstrap to adopt this — it authors a file.
   That is the symlink-contract change.
4. **Absence behaviour.** **Warn once and fall back**, not a hard failure. A hard
   failure at shell startup leaves an unusable interactive shell on a box you are
   likely SSH'd into precisely to fix it. Absence is enforced by the gate
   (`scripts/check-capabilities.sh`, which each OS repo runs on its own declaration),
   not by the login shell.

The Makefile vocabulary is the same contract at the repo level and lands in the
same pass, since [#667](https://github.com/dotgibson/dotfiles-core/issues/667)
already opens a PR in all nine repos. Historical spellings stay as `.PHONY`
aliases — the requirement is that the canonical name **exists**, not that the old
one dies.

### 3.3 What breaks

Every host needs `./bootstrap.sh --links-only` after its repo's sync PR lands —
the new symlink does not exist until it runs. Nothing else a user types changes:
`up`, `clip` and `maint-*` keep working identically.

Two `audit-core.sh` §5c exceptions disappear with the knowledge they excused, and
`ARCHITECTURE.md`'s "two deliberate exceptions" section shrinks to zero.

Covers issues #663, #664, #665, #666, #667, #691, and #631.

## 4. Change 2 — vendor only what is Core

### 4.1 Current

`CONTRIBUTING.md:33-36` states:

> Repo-meta and dev tooling (this file, `LICENSE`, `.github/`,
> `scripts/sync-core.sh`, `scripts/audit-core.sh`, …) are **not** vendored into OS
> repos, so they live in the allowlist in `scripts/audit-core.sh` rather than the
> manifest.

**That is false.** The allowlist keeps them out of `core.manifest`, which only
stops them being symlinked into `~/`. The subtree copies them regardless.

Measured on a synced repo: the `core.manifest` payload is **1.4 MB**; a vendored
`core/` is **5.9 MB**. **76% of what ships to every machine is not Core.**

| shipped to all nine repos | size |
| ------------------------- | ---- |
| `assets/` — README media | 1.8 MB |
| `scripts/` — incl. `test-core.sh` at 741 KB | 1.4 MB |
| `CHANGELOG.md` | 568 KB |
| `.github/` — inert copies; the real `uses:` are remote `@v4` refs | 344 KB |
| `.claude/`, `PORTING-MATRIX.md`, `examples/` | 240 KB |

The largest single item is `assets/demo.gif` at **1.8 MB — larger than the entire
Core payload** — replicated into nine trees where no OS repo's README displays it.

### 4.2 Proposed

Declare the vendored set as **`core.manifest` plus a short, explicit consumer
list**, and filter at materialization. Since #587, `sync-core.sh` no longer
merges — `_sync_materialize_core()` writes `core/` at a resolved commit, so
materializing a subset is the same operation with a filter.

The consumer list is genuinely small. Grepping the nine repos' own files for
`core/scripts/…` and `core/.github/…` finds roughly eight paths in use:
`scripts/tool-versions.env` (five repos), `scripts/audit-core.sh` (two),
`scripts/lib/common.sh`, `scripts/test-core.sh`, `scripts/core-integrity.sh`,
`scripts/verify-atuin-guard.sh`, `scripts/auto-tag.sh` and
`.github/actions/setup-core-tools`. That list is itself uneven — only Alpine calls
the atuin verifier, only MacBook calls `test-core.sh` — and rationalising it is
part of the work.

### 4.3 What breaks

`core-integrity.sh` compares `HEAD:core` against the upstream tree object. A
filtered vendor changes what that comparison is against, so **the integrity check
and `core.lock` semantics must move in the same change** or all nine repos report
`TAMPERED`.

One coupled decision: **`CHANGELOG.md` is either dropped or promoted.** It is
568 KB nothing reads today — unless
[#680](https://github.com/dotgibson/dotfiles-core/issues/680) (`core whatsnew`)
ships, which makes it the backing store. §9 records the recommendation.

Covers issue #676.

## 5. Change 3 — retire what nothing uses, declare what things do

### 5.1 Current

Two exported surfaces, neither with a contract.

**`CORE_PROFILE`** was a v4.0.0 headline feature. Nothing writes
`$ZSH_CFG/profile`, the file it reads. No OS repo mentions it. CI actively
asserts `~/.zshrc` must **not** set it (`bootstrap-test.yml:310-315`). Its only
exercise is `test-core.sh:7617-7646`. Every host runs the `full` default.

It is also what makes the band footgun dangerous. `VENDORING.md:185-192` warns
that an OS repo dropping `22-foo.zsh` into a Core band gap is profile-gated as if
it were Core and *"will silently vanish under `CORE_PROFILE=minimal`"*. The loader
sorts on the `NN` prefix and has no owner metadata, so this is documented
precisely because it cannot be enforced.

**`HAVE_*`** exports 43 globals into every interactive shell. Nine are read by no
code anywhere in the fleet; five are genuinely consumed by OS and role layers; and
the surface is declared in no contract doc — `PORTABILITY.md`, which documents the
Core→OS API, does not mention it. So nothing can be safely removed, nothing tells
an OS-repo author what is safe to use, and nothing stops Core breaking a consumer
silently.

### 5.2 Proposed

**Delete `CORE_PROFILE`.** The footgun goes with it: without profile gating, a
squatted band number is merely unconventional instead of silently destructive. One
removal closes two problems.

The alternative — building the profile-aware discovery surface `V4-PROPOSAL.md` §9
deferred — is real work for a feature with no adopters. `core-help`'s `rows` array
and `_core_suggest`'s candidate list are both static literals advertising band-55
and band-60 verbs that neither reduced profile loads. If the profile is genuinely
wanted, reject this half of the change and file the work to make it real *and*
give at least one repo a reason to set it.

**Declare `HAVE_*`.** Add it to `PORTABILITY.md`'s Core→OS API section: the naming
rule, that `_CORE_PROBED` is the authoritative ledger and `HAVE_*` the convenience
alias, and which flags are supported downstream. Drop the nine nothing reads —
keeping the `_have` call, which populates the ledger *and* gates the init for
direnv, mise and sesh. Add an `audit-core.sh` section asserting that every flag an
OS or role repo consumes is one Core declares.

The open question is whether `HAVE_*` should be a supported downstream API at all,
or an internal detail with `_CORE_PROBED` as the interface. Five existing
consumers argue for supporting it; 43 globals per shell argue for narrowing it.
Either answer is fine — but it must be chosen and written down.

### 5.3 What breaks

A host-local `99-local.zsh` referencing `CORE_PROFILE` or one of the nine dropped
flags. Both are gitignored and unknowable from here, which is exactly why this is
a major and gets a loud CHANGELOG entry rather than a quiet removal.

Covers issues #677 and #694.

## 6. Change 4 — `clip` learns what a secret is

### 6.1 Current

`optoken` fetches a **live TOTP** and pipes it through `clip`. On a box with no
Wayland/X11/macOS/WSL backend, `clip` falls through to `_osc52_copy`, whose tmux
arm uses `tmux load-buffer -w -` — creating a paste buffer readable via
`tmux show-buffer` by anything that can reach the socket.

Three things make this sharper than the honest comment at `zsh/50-op.zsh:70-76`
suggests:

- **Core enables the condition itself.** `tmux/tmux.conf:45` sets
  `set-clipboard on`.
- **The affected boxes are the documented norm.** `dotfiles-Debian/CLAUDE.md`
  describes that fleet as *"laptops on a shelf, reached only over SSH"* with
  clipboard backends deliberately absent — exactly where OSC 52 is the path taken.
- **The warning is in a source comment, not the output.** The user sees
  `TOTP sent to the clipboard`.

The stated rationale for piping through `clip` is that the code *"never lands in
your shell history/scrollback"*. On these boxes that is inverted: it avoids
scrollback and lands somewhere socket-readable instead.

### 6.2 Proposed

Give `clip` a sensitive mode (`--sensitive` / `CLIP_SENSITIVE=1`) that skips the
tmux buffer, or writes and immediately deletes it, and have `optoken` opt in.
Regardless of which mechanism wins, the success message must stop overclaiming
when the backend resolved to OSC 52 under tmux.

`opsecret` is unaffected — it prints via `op read` and never touches `clip`.

### 6.3 What breaks

Observable behaviour of a public binary that tmux `copy-pipe`, `pbcopy`/`pbpaste`
and Neovim's clipboard provider all route through. A host that re-bootstraps gets
different copy behaviour under tmux.

Covers issue #690.

## 7. Ride-alongs

These break nothing and need no migration. They land with the major because a
major is when the fleet re-reads its own docs, and because §4 changes which of
them ship to nine repos.

- **Retire `git subtree` from the record** (#668). #587 replaced subtree-pull with
  pinned materialization, but twelve files plus `Makefile:52` still assert it —
  and `RELEASE-STRATEGY.md` §4 and §5 hand the reader a literal
  `git subtree pull --squash` that `VENDORING.md:154` explicitly forbids. Two Core
  documents contradict each other on the repo's central mechanism, and the one
  giving instructions is wrong. (Line numbers as of the proposal: `RELEASE-STRATEGY.md:194,327`.)
- **Make `os-repos.txt` the single source** (#669). Its own header admits adding a
  target is four coordinated edits.
- **Three stale claims** (#670, #671, #678). `VENDORING.md` describes `core.lock`
  generators that #593 removed; `dotfiles-Debian/CLAUDE.md` says `clip` has no
  headless backend when the OSC 52 fallback shipped long ago; `V4-PROPOSAL.md`
  cites files that no longer exist.

## 8. Combined blast radius

All four changes land in one `v5.0.0`. A host reaches it only through the three
independent opt-in gates from `RELEASE-STRATEGY.md §4` — nothing is pushed:

1. Merged, audited green, and **tagged** `v5.0.0` in `dotfiles-core`.
2. The OS repo **merges its fan-out PR** and commits the new `core.lock`.
3. The host **re-bootstraps** to pick up the new `os.capabilities` symlink.

Skip any gate and the host stays on `v4.x`. Roll back per OS by **reverting** the
v5-adoption commit in that repo and re-bootstrapping.

Two fleet-wide costs specific to this major:

- **The `@v4`→`@v5` caller-pin sweep** (#672). `RELEASE-RUNBOOK.md:256` records
  that `make fleet-drift` compares `core.lock` provenance, *not* workflow `uses:`
  pins, so this is a hand grep. `dotfiles-Windows` is absent from
  `os-repos.txt`, invisible to `fleet-drift`, and its `auto-tag` caller is
  **already six minors stale at v4.12.0** because nothing advances it.
- **`core-integrity` must be retaught in the same commit as §4**, or the fan-out
  reports `TAMPERED` in all nine repos at once.

## 9. Per-OS-repo migration runbook

For each repo in `scripts/os-repos.txt`, after `v5.0.0` is tagged, MacBook first
as the canary:

1. **Merge the fan-out PR** — `sync-fanout.yml` opens `sync/core-v5.0.0`
   automatically. It opens PRs; it never merges.
2. **Author `os.capabilities`** — transcribe from `PORTING-MATRIX.md`'s tables.
   Per-repo specifics that must not be flattened: openSUSE's Tumbleweed-vs-Leap
   dialect, Debian's three targets tiered by `scripts/pkg-filter.sh`, Alpine's
   `doas`, Gentoo's full atoms, MacBook's `Brewfile`. Role repos declare nothing
   and inherit the OS layer's table.
3. **Add the canonical Makefile targets**, keeping historical spellings as aliases.
4. **Re-bootstrap:** `./bootstrap.sh --links-only`, then `make test-repo` where the
   repo has one.
5. **Verify:** `make fleet-drift` in Core confirms convergence; `make
   core-integrity` is clean; `core status` on a real box reports the right OS layer.

**Windows** vendors no `core/` and receives no sync PR. Its `@v4` pins must be
bumped by hand, and it is the one repo where "checked" has to mean a person
looked.

## 10. CHANGELOG entry

The breaking entries land under `## [Unreleased]` in `CHANGELOG.md` — that file is
the single source of truth, and they move under a `## [v5.0.0]` heading when the
release is cut. They are deliberately **not** duplicated here, to avoid the
two-copies drift `V4-PROPOSAL.md §8` also refused.

`RELEASE-STRATEGY.md:109` requires the breaking changes be flagged loudly. The
per-host action — `./bootstrap.sh --links-only` — belongs in the entry in those
words, since it is the "breaking change a host must adapt to" that makes this a
major.

## 11. Non-goals and open questions

**Non-goals (deliberately out of this major):**

- **Renumbering the load-order bands.** Roughly 470 references across 62 files, and
  `V4-PROPOSAL.md` §9 resolved against it: bands are conventions, the 61-69 gap is
  headroom. The band *ownership* problem is real, and §5 closes it by deleting the
  profile rather than by renumbering.
- **Retiring the bare verb names** (`up`, `serve`, `gsync`, `maint-*`) — **decided
  against**, [#692](https://github.com/dotgibson/dotfiles-core/issues/692), closed
  `not_planned`. v5 was the only window (removing a public function name is a MAJOR
  per `RELEASE-STRATEGY.md:106-109`) and it passed deliberately. The additive
  dispatcher in [#684](https://github.com/dotgibson/dotfiles-core/issues/684)
  already buys the coherence — one front door, `core help` as the index, the
  generic verbs reachable under a namespace. Deletion buys namespace purity and
  costs daily friction on the most-typed verbs, plus churn across 28 completions,
  `core-help`'s rows, `_core_suggest`, `aliases.md` and `PARITY.md` (a two-repo
  change). **Revisit only on evidence of a real collision** — `up` and `serve` are
  genuinely collision-prone and a shadowing `up` would fail silently — not on a
  fresh aesthetic objection.
- **Consolidating `bootstrap.sh`.** The spread is real (MacBook 1,505 lines vs Arch
  395) but `audit-core.sh` §5f already reports `blib_*` adoption and is the right
  incremental mechanism.
- **An nvim overhaul.** 6,346 LOC and 61 plugins, but it breaks no public contract
  and re-vendors with zero migration.

**Open questions:**

1. **`CHANGELOG.md`: dropped or promoted?** §4 removes it as freight; #680 makes it
   a feature's backing store. **Recommendation: build #680 first** — it is in the
   earlier `v4.19.0` milestone, it is additive, and it lets §4 inherit a file with
   a stated consumer instead of guessing. If §4 lands first, decide #680's fate in
   that PR rather than after it.
2. **Is `HAVE_*` a supported downstream API, or internal?** See §5.2. If
   "internal", the five existing consumers migrate in this release.
3. **What does `os.capabilities` do on a box that has none?** Hard failure at
   bootstrap, or a one-release fallback to today's hardcoded ladder. The fleet
   re-bootstraps as part of this major anyway, which argues for the hard failure.
4. **Does the consumer list in §4 get rationalised or transcribed?** Only Alpine
   calls `verify-atuin-guard.sh`; only MacBook calls `test-core.sh`. Some of those
   are probably accidents, and this is the moment to find out.
