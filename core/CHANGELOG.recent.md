# Changelog — recent releases

GENERATED FILE — do not edit by hand. `scripts/gen-changelog-recent.sh` rewrites it
wholesale, `scripts/release.sh` runs that generator on every release, and
`scripts/audit-core.sh` §9e fails when this file is not byte-identical to a fresh
render. To fix a conflict or a stray edit, re-run the generator — never patch it.

The last 8 released sections of `CHANGELOG.md` (v6.0.1 … v5.3.0), vendored into every OS repo's
`core/` by `core.vendor` so `core whatsnew` can answer offline. The full changelog is
repo-meta and stays upstream:
[dotgibson/dotfiles-core/CHANGELOG.md](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md).

## [v6.0.1] - 2026-09-01

### Added

- **`make audit` runs the cross-shell parity contract (§9f, #682).** `parity-check.sh`
  ran only on `make parity-check` and a weekly cron, so a false or unenforced `PARITY.md`
  row merged clean and sat until Monday — which is how the contract promised an `Alt+C`
  dir-jump binding for years with the gate green the whole time. Its most valuable
  assertion is Core-only (the coverage half reads `PARITY.md` and the `CHECKS` array,
  both in this repo), so it belongs on the blocking path; the cross-repo half self-skips
  without a sibling `dotfiles-Windows`, exactly like §9c, and the pass line says which
  half actually ran rather than claiming "zsh + pwsh" on a box that opened no pwsh file.
  Not scope-guarded, for §9d's reason: `PARITY.md` is a `*.md` file and inert to
  `ci-classify.sh`, so the very push that adds an unenforced row arrives as `--scope none`.
  The unassertable half is reported through a new `skip_note` class (`scripts/lib/common.sh`):
  a plain `skip` counts as a missing TOOL, so `--strict` would have failed a
  fully-provisioned box purely because the contract was being honest about a PSReadLine
  default — and would have disagreed with `parity-check.sh --strict`, which accepts the same
  reported default. A gate punished for reporting honestly teaches the next author to stop
  reporting.

### Fixed

- **`scripts/parity-check.sh` proves its one-to-one claim instead of asserting it (#682).**
  The script's own comment said it "mirrors PARITY.md's `aligned` rows one-to-one — every
  aligned row has a check here", and `PARITY.md`'s Enforcement section repeated it. Both
  were false: **21 aligned rows, 18 checks.** Three rows had no check at all
  (**History search**, **Word nav**, and one row covering five functions) and two were only
  half-checked, which is worse than none because the row renders green while half of it is
  fiction — **Dir jump** claimed `Alt+Z` _and_ `Alt+C` while the needle tested only
  `Alt+Z`, and **Fuzzy git** claimed `gaf`/`grf`/`grsf` while the needle tested only
  `gaf`. Honest coverage was **16 of 21**. (#682 reported 17 checks, four unchecked rows
  and 15 of 21 — one release stale: #679 had just added **Theme**'s check. The shape of
  the defect was identical either way.) Every check now carries the row-key of the table
  row it enforces, and the script parses `PARITY.md` to assert the mapping in both
  directions: an `aligned` row with no needle fails, and so does a needle whose row was
  renamed or deleted. (Reclassifying a row does _not_ orphan its check — every status
  populates the known set, and `deliberate`/`gap` rows may keep one, as `cheat` now does.)
  A slug collision fails too, since one row's check would otherwise silently certify
  another's. Several checks may share a row-key, which is what lets the five utility
  functions, the three fuzzy-git verbs and the two word-nav directions each get a needle
  instead of one standing in for the set. Coverage is row-level, not claim-level — a row
  that grows a second trigger is still not forced to grow a second needle, and
  `parity-check.sh` says so rather than overclaiming a second time. Verified the only way
  a gate can be — negatively, in `test-core.sh`: an uncovered row, an orphaned row-key, a
  slug collision, a misspelled status and a reclassified-but-still-checked row each produce
  the right verdict and exit code. The status check matters more than it looks: a typo like
  `aligend` left the row in the known set (so its check was not orphaned) while dropping it
  out of the required set, retiring a contract row from enforcement with the gate green.
  So does the parser's column anchoring: a Markdown-legal row indented one space parsed as
  nothing at all, so a new `aligned` row could sit there unenforced while the gate reported
  full coverage. Up to three leading spaces is now a row (CommonMark's limit); four or more
  is still an indented code block, and both directions are pinned.

  Two needles also proved less than their rows claimed. `Ctrl+R` on pwsh is bound **twice**
  on purpose — PSFzf's lazy stub, then a re-assertion after atuin's init seizes the chord —
  and the two lines are identical but for whitespace, so a presence needle was satisfied by
  either and deleting the re-assertion left the row green while atuin kept `Ctrl+R`. Needles
  may now demand a minimum match count (`count:2:`), which is the only thing that separates
  those two. And key-anchoring the **Session picker** row had dropped its pwsh _behaviour_
  needle, so `Ctrl+G` bound to anything satisfied it; the chord and the target now get a
  needle each under the shared row-key, rather than one replacing the other.

  Two needles proved less than their rows claimed in a subtler way still. `count:2:` shows
  both `Ctrl+R` bindings exist but says nothing about **where**, and the re-assertion only
  means anything _below_ `atuin init` — atuin ignores `ATUIN_NOBIND` on pwsh and seizes the
  chord on init. Hoisting both bindings above the anchor satisfied the count while breaking
  the advertised behaviour at runtime, so needles may now also demand position
  (`after:atuin init:`), which is the one property a count cannot express. And the word-nav
  needles matched the `vicmd` bindings four lines below the `viins` ones, so deleting the
  contractual insert-mode binding left the row green; every keybinding needle now pins its
  keymap (`-M viins '…'`) rather than matching whichever copy survives.

  Two more needles matched something adjacent to their claim rather than the claim.
  `Invoke-DotfilesSessionizer` appears in `10-tools.ps1`'s `provides:` header and its own
  function definition as well as in the `Ctrl+G` handler, so the Session picker's target
  needle proved the function _existed_ and never that the chord invoked it — deleting the
  handler body left both its checks green. It now needles the insertion expression. And pwsh
  restores `Ctrl+R` on **two** runtime paths after atuin — the lazy path re-binds the
  `-Chord` stub, the already-loaded path calls `Set-PsFzfOption` — so deleting the
  already-loaded branch left the `-Chord` count at two and the position check passing while
  atuin kept `Ctrl+R` on that path. Both paths are needled now, each for existence _and_
  position — the already-loaded branch only means anything below `atuin init` too, so
  hoisting it keeps the count at two and still fails.

- **Three `aligned` rows in `PARITY.md` were claiming more than they could show (#682).**
  Found by doing the work above, since a contract nothing checks is a contract nothing
  corrects. The three fail differently: one capability did not exist, one existed on both
  shells but did different things, and one exists on pwsh only as a framework default.
  **`Alt+C` never existed on either side** — the issue assumed pwsh had it via
  PSFzf and zsh had drifted, but zsh never binds `^[c` and never sources fzf's own
  key-bindings (there is no `eval "$(fzf --zsh)"` anywhere in `zsh/` or `lib/`), and
  `dotfiles-Windows` sets only PSFzf's `-PSReadlineChordProvider` and
  `-PSReadlineChordReverseHistory` — `-PSReadlineChordSetLocation` is opt-in and appears
  nowhere in that repo. Not a divergence and not a `gap`; the claim is simply gone, and
  the surviving `Alt+Z` needle is now key-anchored (`'^[z' _fzf_zoxide_jump`) like the
  Ctrl+T row, because the bare widget name it used before passed even if the key moved —
  as does **Session picker**'s, which had the same shape and was missed in the first pass.
  **`cheat` is `deliberate`, not `aligned`** — zsh's is `alias cheat='core-help'`, Core's
  own command index, while pwsh's queries cht.sh; same trigger, different source, and the
  `alias cheat=` needle passed regardless of target. **Word nav** stays `aligned` but is
  explicit that its pwsh half is a PSReadLine _default_, not configuration: nothing in
  `dotfiles-Windows` binds Ctrl+Arrow, so that half reports as a skip carrying the reason
  rather than a needle that cannot fail.

- **`maint-run` no longer looks wedged while a step is working.** `step()` sent every
  command's stdout and stderr to `$LOG` alone, while `log()` teed the `▶`/`✓`/`✗` lines to
  the terminal. A foreground `maint-run` therefore printed `▶ mise upgrade` and then showed
  **nothing at all** until the step ended. That is survivable when a step takes seconds; it
  is not on musl, where mise's `all_compile` default (every prebuilt runtime being
  glibc-linked) means `mise upgrade` COMPILES node/python/ruby from source — tens of minutes
  of dead terminal, against a `MAINT_MISE_TIMEOUT` ceiling of 45 of them **per step**, three
  mise steps deep. Nothing on screen separates "compiling V8" from "hung", so the operator
  interrupts it; mise discards the partial build, nothing is installed, and the next run
  starts the identical compile over. dotfiles-Alpine sat in that loop, rebuilding node
  24.20.0 from scratch daily and never finishing it.

  `step()` now MIRRORS the step to the terminal when stdout is a tty (`tee -a "$LOG"`), and
  keeps the exact log-only path when it is not — so **the scheduled run is unchanged** and
  only the interactive one gains output. Three properties are preserved deliberately:
  `</dev/null` still hands every step an EOF (the guard the comment above `step()` explains);
  the reported rc is `${PIPESTATUS[0]}`, the command's own status, not `tee`'s, because
  `pipefail` would otherwise blame the step for a `tee` that died on a full disk; and stdout
  is a pipe in the new arm and a file in the old — never a terminal — so a step that
  colourizes on `isatty` still sees false and `$LOG` keeps the same clean text.

- **The `mise outdated --bump` probe can no longer block on an invisible prompt.** It is the
  one command in the run that is not a `step()` call, so it alone inherited the caller's
  stdin — a terminal, under `maint-run` — while its stderr went to `/dev/null`. A mise that
  decided to prompt there (an untrusted config path, a credential) asked a question nobody
  could see and blocked until `MAINT_MISE_TIMEOUT` expired. It now takes `</dev/null` like
  every other command in the file, which turns that into the fast non-zero rc the
  "bump check UNAVAILABLE" gate directly below it already knows how to report.

## [v6.0.0] - 2026-08-31

### Changed

- **`V4-PROPOSAL.md` is deleted, and three duplicated doc sections with it (#678).** The
  v4 design record shipped in `v4.0.0` and had been carrying a status block, a reading
  guide, and file-path citations to modules its own rename retired (`zsh/maint.zsh`,
  `zsh/tools.zsh`, `zsh/options.zsh`, …). It was repo-meta, never in `core.manifest` and
  never vendored since #676, so **no OS repo and no host is affected** — the git history
  and the `v4.0.0` tag keep it losslessly. Its two surviving rationale paragraphs moved to
  `ARCHITECTURE.md` § "Load order is load-bearing" first: why bands are a convention rather
  than a partition, and why byte-compiled `.zwc` wordcode stays beside its fragment while
  every other mutable file moved to XDG. The third — why `CORE_PROFILE` did not gate
  bootstrap — died with the profile itself in #677.

  **Three duplicates removed, each of which was the wrong copy:**

  1. `RELEASE-STRATEGY.md` §5 "Checklists" duplicated `RELEASE-RUNBOOK.md` §1.1 while
     **omitting the `git checkout -b release/vX.Y.Z` step** the runbook calls mandatory —
     following it reproduced the tag-before-merge situation that burned `v4.11.0`. The
     runbook is now the only copy; §5's one unique paragraph (a rollback is an ordinary
     sync at an older pin and needs no un-merging) folded into §"Safe deployment".
  2. `RELEASE-STRATEGY.md` §3 "Repository architecture" put architecture in a release-policy
     doc, and its load-order chain **had been missing the `role`/85 band since v4.13**. The
     two designs it rejected (`case "$OS"` branches; a `common/` + `os/<name>/` monorepo)
     moved to `ARCHITECTURE.md` § "The problem this solves".
  3. `PARITY.md` § "Resolved decisions" was a narrative of four shipped keybinding decisions
     — CHANGELOG content living in a contract doc.

  **Two contradictions closed.** `ARCHITECTURE.md` is now the single home of the three-layer
  model; `CONTRIBUTING.md` said _"run the README's test"_ while `README.md` linked back to
  `CONTRIBUTING.md`, and that loop is gone (`CONTRIBUTING.md`'s own table stays — it is the
  _action_ framing). And the fan-out repo count is nine, sourced from `scripts/os-repos.txt`
  rather than restated: `RELEASE-STRATEGY.md` had said "nine" in three places and "eight-OS"
  in four, and `sync-core.sh` said "8 repos" beside its own "nine".

  Also trimmed: `PARITY.md:49` claimed per-shell extras were "noted as gaps below" in a file
  with zero `gap` rows; `README.md`'s Roadmap section was four checkboxes cargo-culted from
  Best-README-Template, two of them meta; and `RELEASE-STRATEGY.md`'s SemVer bullets
  collapsed to the one-sentence policy plus a pointer at `RELEASE-RUNBOOK.md` §1.0, which
  carries the better table and the three tiebreakers. Section citations across the fleet are
  now by **name** (`§"Safe deployment"`) rather than by number, so the next renumber cannot
  silently break them.

- **BREAKING — `CORE_PROFILE` is deleted (#677).** The `minimal`/`standard`/`full` knob
  shipped as one of v4.0.0's three headline features and never acquired a single adopter.
  Nothing in this repo or any of the nine OS repos ever wrote the `$ZSH_CFG/profile` file
  the loader read; no OS repo mentioned the variable at all; and `bootstrap-test.yml`
  asserted that a managed `~/.zshrc` must _not_ set it. Every host has always run `full`.

  `zsh/loader.zsh` now globs `NN-*.zsh`, sorts, byte-compiles and sources — with **no
  ceiling and no filter**. Three consequences, in the order they are likely to bite:

  1. **The loader no longer sets `CORE_PROFILE` in your shell.** It used to leave the
     resolved value behind deliberately. A host-local `99-local.zsh` that branches on
     `$CORE_PROFILE` now silently takes the empty branch — this is the one breakage that
     cannot be detected from here, and the reason this is a major.
  2. **`$ZSH_CFG/profile` is inert.** It is no longer read, and a host that hand-wrote one
     gets no warning that it stopped mattering. Delete it.
  3. **`core update` no longer names a profile** when the updater is missing; it names
     `60-update.zsh`, which is the fact you can act on.

  **It also closes the band-squatting footgun `VENDORING.md` documented but could not
  enforce.** The loader has no owner metadata — everything is flattened into one
  `$ZSH_CFG` — so the ceiling gated by _number_, not authorship: an OS repo filing
  `22-foo.zsh` in a Core band gap was treated as Core and _silently vanished_ under
  `CORE_PROFILE=minimal`. With nothing skipping fragments, a squatted number is merely
  unconventional. Bands remain a reservation convention worth respecting for the reason
  that outlives the gate: a flat directory holds exactly one `22-foo.zsh`, so a number an
  OS repo takes is a number a later Core release cannot.

  The alternative was building the profile-aware discovery surface `V4-PROPOSAL.md` §9
  deferred and never delivered — `core-help`'s rows and `_core_suggest`'s candidates are
  static literals that advertise band-55/60 verbs which `minimal` and `standard` did not
  load. That is real work for a feature with no users.

  `scripts/test-core.sh`'s profile section is **repurposed, not deleted**: eleven of its
  twelve assertions were ceiling-specific, but the glob and the sort are now the loader's
  entire filtering contract, so the section became the loader glob/sort contract — keeping
  the same-NN lexical tiebreak and adding the malformed-prefix, self-exclusion and
  dangling-symlink coverage the loader documented but nothing had ever asserted.

- **`tag-release.sh` refuses a breaking change in a non-major release.** The one rule in
  `RELEASE-STRATEGY.md` that nothing enforced, and the one whose failure is silent and
  fleet-wide: `MAJOR` is derived from the version, so a `BREAKING` entry tagged `X.Y+1.0`
  both files the break as a minor **and** force-moves the `vN` alias onto it — pushing it
  to every caller still pinned `@vN`, which is the whole fleet. It now fails at tag time
  unless the version is `X.0.0`.

  It reads the section for the version being released, not `[Unreleased]`: `release.sh`
  has already promoted the entries under `## [vX.Y.Z]` by then, so scanning `[Unreleased]`
  would read the empty section that was just opened and pass every time.

  No bypass, unlike `TAG_SKIP_AUDIT`. If the check fires and the entry is not really
  breaking, the answer is to reword the entry — a bypass here would be exercised exactly
  once, on the release that needed it most.

- **BREAKING — a vendored `core/` is no longer a copy of this whole repo (#676).**
  `scripts/sync-core.sh` now materializes exactly `core.manifest` ∪ a new **`core.vendor`**
  and nothing else. A vendored tree goes from **285 files / 5.6 MB to 182 files / 1.2 MB**
  — about 39 MB reclaimed across the nine repos.

  `CONTRIBUTING.md` had asserted for years that repo-meta and dev tooling were "**not**
  vendored into OS repos". It was false. The allowlist in `scripts/audit-core.sh` only kept
  those files out of `core.manifest`, which governs **symlinking into `$HOME`** — the
  subtree copied them to disk regardless. `audit-core.sh` said so plainly at the time
  ("'not shipped' means 'not in the manifest', not 'not on disk'") and the two documents
  simply disagreed. The largest single item shipped to every machine was
  `assets/demo.gif` at 1.8 MB — bigger than the entire Core payload, replicated nine
  times, and displayed by no OS repo's README.

  **`core.vendor` is the second list**, in `core.manifest`'s format, and every entry names
  the consumer that reads it from `core/`: `scripts/tool-versions.env` (MacBook, Offense,
  Defense), `scripts/check-capabilities.sh` (seven repos), `gitleaks.toml` (six),
  `.github/actions/setup-core-tools`, `examples/atuin-daemon.service` (Fedora and Debian
  bootstraps), and a handful more. If you cannot name a consumer, it does not belong there.

  **Dropped:** `CHANGELOG.md` (687 KB), `assets/` (1.8 MB), `.claude/`, `.devcontainer/`,
  the root docs, and the authoring half of `scripts/` — release tooling, the fan-out
  itself, benchmarks and dashboards, none of which anything on a box or in an OS repo runs.

  **There is no flag day.** `core_lock_expected_tree()` derives which shape to expect from
  the **pinned commit**: one carrying `core.vendor` is compared against the filtered tree,
  one predating it against its whole tree. On the day this merged, all nine repos still
  pinned older Core, took the whole-tree branch, and stayed `pristine`. The switch flips
  per-repo, exactly when that repo's `core.lock` moves.

- **BREAKING — `dotfiles-Offense`'s `make core-sync` is retired (#676).** It was the one
  sanctioned second writer, and the sanction rested on it stamping `core.lock` from _what
  it actually pulled_. A `git subtree pull --squash` merges the **whole** upstream tree and
  has no way to apply `core.vendor`, so "what it pulled" is no longer what a vendored
  `core/` should contain — the first pull after its lock moved would land all 285 files against
  an expectation of the filtered subset and be reported `TAMPERED`, correctly and with no hand-edit
  anywhere. Offense now takes the fan-out like every other repo. There is one producer:
  `core_vendor_materialize`.

- **`scripts/new-os-repo.sh` no longer vendors with `git subtree add` (#676).** A subtree
  add copies the whole tree, so from the moment `core.vendor` existed it would have
  scaffolded a repo that was `TAMPERED` on its first `make core-integrity`, before anyone
  touched it. It goes through the shared producer, so a new repo is born agreeing with the
  fleet.

- **`core-integrity.sh`'s header stopped overstating itself (#676).** It promised "one
  rev-parse each side, O(1)" and "never writes to a repo". The filtered side now rebuilds
  the expected tree (tens of milliseconds), and does so by writing loose objects that are
  unreferenced and gc-prunable. It now says it never changes a repo's **tracked state**,
  which is the claim that is actually true and the one that matters.

- **`scripts/parity-check.sh` derives the fzf palette needle instead of pinning a hex,
  and `PARITY.md`'s Theme row finally has a check (#679, #682).** The row needled the
  literal `query:#c0caf5:regular` in both shells. Core's half is now generated, so a
  style change rewrites `zsh/35-fzf.zsh` and leaves the hand-maintained
  `dotfiles-Windows` untouched — and the pinned form then failed on **both** halves,
  including the zsh one that had just done exactly the right thing, naming no fix that
  could be made from this repo. The row now tests the property it always meant
  (_both shells set an explicit fzf palette_), and a separate value comparison reports
  the real divergence: _Core is on style=moon (query #c8d3f5); dotfiles-Windows still
  carries #c0caf5_.

  `PARITY.md:27`'s **Theme** row had been marked `aligned` since it was written with no
  check behind it at all — one of the four rows that made PARITY.md's "every `aligned`
  row has a corresponding check" claim false. It has one now, and PARITY.md records
  what that check does and does not prove: it shares its pwsh evidence with the FZF
  palette row, because the fzf `--color` block is the only place `dotfiles-Windows`
  carries tokyonight colours at all. The accent half stays a genuine `gap`.

  `make check-pins` gains a third leg, `gen-theme.sh --refresh --check`, so
  "has upstream restyled tokyonight?" is answered on the weekly report-only path where
  the plugin pins already live — never on a PR's blocking path.

- **Three shell colours now match what nvim actually renders (#679).** Core's shell
  config carried `#27a1b9`, `#16161e` and `#283457` for tokyonight's `border_highlight`,
  `black` and `bg_visual`. Against the pinned tokyonight commit the plugin resolves
  `#29a4bd`, `#1d202f` and `#2e3c64` — so nvim and the shell have been painting different
  colours, and the hand-copied values were simply stale. Visible in fzf's border,
  scrollbar and gutter, and in lazygit's inactive border and selected-line background.
  This is the drift the generator exists to prevent, found by building it.

### Added

- **`core status` — the box can finally answer "am I current?" (#681).** Core shipped two
  provenance reporters, `scripts/fleet-drift.sh` (staleness) and `scripts/core-integrity.sh`
  (tamper), and **both are fleet-side**: they run from a dotfiles-core checkout or CI, never
  from the shell they configure. Meanwhile `core.lock` has been written to the root of every
  OS repo since B1 and **nothing on a box has ever read it**. So a laptop you had not touched
  in a month could tell you whether `bat` was installed (`core-doctor`) and which Core it
  carried (`core-version`, one line), but not whether that Core was current, which layers were
  live, or whether anything under `core/` had been hand-edited.

  `core status` (and the standalone `core-status`) composes what was already on disk into one
  scannable panel — no new vendored file, no network, no second implementation of anything:

  ```text
  dotfiles-core 5.5.0   v5.5.0 · 6a81418e · synced 17 hours ago
  OS layer      fedora  dnf · systemd
  Role layer    none
  Tools         38/41 present · 7/9 wired          core-doctor -v
  Integrity     core/ matches its commit
  ```

  Version from `core.version`; tag, commit and sync age from `core.lock` and its own commit
  date; the OS and role layers from the `80-os.zsh` / `85-<role>.zsh` symlink targets; the
  package manager and scheduler from `os.capabilities` (#663) through `_core_cap`, which is
  what the v5 capability declaration was for and the first place it shows itself to a human.
  The tool counts come from a new `_core_doctor_tally` that walks `_CORE_DOCTOR_GROUPS` and
  `_CORE_DOCTOR_WIRED` through core-doctor's own predicates, so the summary and the report it
  points at cannot disagree — a parity assertion pins the two.

  **`--json`** emits the same facts as one object, for a statusline or a provisioning gate,
  alongside `core-doctor --json`.

  **Every row degrades rather than errors, and the verb returns 0 throughout.** No `core.lock`,
  no git, a tarball deploy, an OS repo that has not re-bootstrapped since the fan-out — each is
  a normal state, not a fault, and each renders a stated "unknown" naming what could not be
  read. A status panel that fails on the box it describes is useless precisely when you need it.

  **Two things it deliberately does not claim.** It does not say how many releases behind you
  are: that needs Core's tags, and a consumer's `core/` is a vendored tree carrying none of
  Core's history, so answering would need the network. It does not reproduce
  `core-integrity.sh`'s `pristine`/`TAMPERED` verdict either: that comparison resolves the
  expected tree inside a **dotfiles-core** object store, which a consumer does not have — and
  `scripts/` is in neither `core.manifest` nor `core.vendor`, so those scripts leave the box
  entirely once #676's filtered vendoring ships. The weaker claim a box **can** make is the one
  the Integrity row makes: whether anything under `core/` has been edited since it was
  committed. That is the hazard operators actually hit, since the next `make sync` clobbers a
  hand-edit silently.

- **`core whatsnew` — a box can finally read what changed in the Core it carries (#680).**
  The verb renders the release-note sections between the version this machine last looked
  at (a state file under `$XDG_STATE_HOME/dotfiles-core/`) and the `core.version` it runs
  now, paged through `_core_page` like `core-help` and `core-doctor -v`. `--full` swaps the
  bullet leads for the prose; `--all` ignores the read mark. A once-per-bump nudge in
  `60-update.zsh` announces `Core moved X → Y` so the verb is discoverable at the moment it
  becomes useful, then stays quiet until the next bump.

  **Its data source is a new generated file, `CHANGELOG.recent.md`** — the last **8**
  released sections, ~49 KB — rendered by `scripts/gen-changelog-recent.sh`, committed, and
  listed in `core.vendor` so it rides along in every OS repo's `core/`.

  **The full `CHANGELOG.md` stays repo-meta and is still not vendored.** #680 rested on it
  already being on every box, and warned that #676 must not land "on autopilot" while this
  issue sat open assuming the file was there — which is exactly what happened. #784 measured
  `CHANGELOG.md` at ~707 KB, **36 % of the entire vendored tree and larger than all of
  `zsh/`**, and dropped it, taking this feature's only data source with it. #680 also
  pre-rejected a truncated changelog because "the vendored file would differ from the
  authored one, which `core-integrity` would have to special-case". That objection was
  correct against the old whole-tree comparison and is **obsolete** against #784's: the
  expected tree is derived from the _pinned commit_, so a file Core generates and commits is
  an ordinary tree entry needing **zero** special-casing. The digest costs 3.7 % where the
  file cost 36 %, and answers entirely offline.

  `[Unreleased]` is deliberately **excluded** from the digest. A box runs a released
  `core.version`, so an `[Unreleased]` entry describes code it does not have — and including
  it would make the digest stale on every changelog bullet, reddening the new audit gate on
  nearly every PR. Excluding it means the file changes exactly once per release, with
  exactly one regeneration site.

  **Three things keep it honest.** `scripts/release.sh` regenerates the digest immediately
  after promoting `[Unreleased]` — that promotion _changes which eight releases are recent_,
  so a release would otherwise fan out a digest describing a different Core than it ships.
  `scripts/tag-release.sh` now commits it alongside `core.version` and `CHANGELOG.md`: its
  pathspec is explicit, so an unlisted third file is not deferred but **silently dropped**
  from the release commit, leaving the worktree audit green and nine repos vendoring a stale
  changelog. And `scripts/audit-core.sh` **§9e** re-renders the digest and compares it
  byte-for-byte, failing with the exact regeneration command — because nothing else could
  catch it: §1c proves only that the path exists, §1e never walks it (it is data, not an
  `# entry` root), and `core-integrity.sh` compares tree hashes, where a consistently-stale
  blob hashes consistently and reads as `pristine` in all nine repos.

- **`scripts/lib/core-vendor.sh` — one definition of the vendored set (#676).**
  `core_vendor_paths` / `core_vendor_keeps` / `core_vendor_tree` /
  `core_vendor_effective_tree` / `core_vendor_materialize`. Three callers needed the answer
  from different sides — `sync-core.sh` and `new-os-repo.sh` produce the tree,
  `core-integrity.sh` verifies it — and two implementations of one filter would have
  re-created #556 one layer down: a producer computing a different subset would pass its
  own post-fan-out assertion and be reported `TAMPERED` by an unrelated command later.

  The filter is read from `${sha}:core.manifest` / `${sha}:core.vendor` — **the commit,
  never a working tree**. That is what makes the producer building inside the consumer and
  the verifier rebuilding inside Core agree by construction.

  The tree is built **additively**, feeding only the kept paths into a temporary index via
  `update-index --index-info`. The subtractive shape ends in
  `xargs -0 … update-index --force-remove`, whose empty-input behaviour is not portable
  (GNU needs `-r`, BSD/macOS differs by release, `-r` is not portable) — and an empty
  keep-set is precisely what a mis-parsed allowlist produces. Additively it is a clean
  no-op. File modes come straight from `ls-tree`, so the exec bits §2 asserts survive.

- **Three audit sections for the second list (#676).** §1c fails a `core.vendor` entry
  naming a path that does not exist (a typo matches nothing and silently shrinks the
  vendored set). §1d fails a path claimed by both lists — a duplicate is harmless to the
  tree today, which is exactly why it would sit there until someone removed the manifest
  line and silently unshipped a Core file that "was still listed". §1e walks the
  **transitive closure** from `# entry` roots declared in `core.vendor` and fails when a
  vendored script reaches a file nobody vendors.

  §1e walks from declared entry points rather than sweeping every vendored script, and the
  distinction is load-bearing: a sweep's first two findings are `scripts/release.sh`
  reaching `CHANGELOG.md` and `gen-release-notes.sh` reaching `cliff.toml`, leaving only
  the choice between handing back 687 KB and starting a suppression list — and a gate whose
  first act is to demand a suppression is a gate someone turns off. `_core_vendor_ref_hits`
  in `common.sh` does the extraction and documents what it deliberately cannot see
  (computed paths, Lua `require`s, YAML); those four paths are hand-listed in `core.vendor`
  with their consumers named, the posture §1b already takes toward `.claude/`.

- **`theme/palette.toml` is the single source of truth for colour, and
  `scripts/gen-theme.sh` renders every consumer from it (#679).** Around ninety hex
  literals were previously kept in step **by comment** across thirteen files —
  `tmux/tmux.conf`, three `tmux/scripts/*.sh` helpers, `starship/starship.toml`,
  `lazygit/config.yml`, five `zsh/*.zsh` modules, `lib/ux.sh` and
  `examples/starship.showcase.toml`. Six of those comments said "kept in sync with
  starship.toml + tmux.conf `@tn_*`" in as many words, and nothing checked any of them:
  a hand-edit to one file was a valid, lintable, shippable change that fanned a
  half-recoloured stack out to nine repos.

  `nvim/` never had the problem — it holds zero hex literals and asks the plugin
  (`nvim/lua/gerrrt/utils/palette.lua`). This applies that argument to everything else.
  Consumers carry marked `# core:theme:gen <id>` regions; everything outside them stays
  hand-authored. `make gen-theme` renders, `make check-theme` reports drift, and
  `audit-core.sh` §9d makes it a blocking gate on every commit and every CI leg.

  The palette is **derived, not typed**: `--refresh` resolves it from the tokyonight
  commit pinned in `nvim/lazy-lock.json`, and refuses to run against an installed plugin
  that is off that pin or a `style` that disagrees with `palette.lua` — which finally
  makes that file's "keep the two in sync" comment a machine check. Style selection is
  **generation-time only**: there is no runtime `CORE_THEME` and none is planned, because
  the consumers are static files (starship and lazygit read fixed config paths) and
  regenerating on a live box would dirty the vendored `core/` tree that
  `scripts/core-integrity.sh` exists to keep pristine.

  `theme/palette.toml` is **not vendored** — it is a generation-time input, accounted for
  in `audit-core.sh`'s `META_ALLOWLIST`. Its outputs ship; it does not.

### Removed

- **Five dead `FZF_*` exports are deleted (#682).** `FZF_CTRL_T_COMMAND`,
  `FZF_ALT_C_COMMAND`, `FZF_CTRL_R_OPTS`, `FZF_CTRL_T_OPTS` and `FZF_ALT_C_OPTS` in
  `zsh/35-fzf.zsh` were read by exactly one thing: fzf's own stock key-binding widgets,
  which Core **never loads** — there is no `eval "$(fzf --zsh)"` anywhere in `zsh/` or
  `lib/`, and `zsh/00-tools.zsh` touches fzf only for `HAVE_FZF` detection. Core defines
  its own widgets, and they ignore every one of these: `_fzf_file_no_hidden` builds its
  own `fd … | fzf --preview "$_FZF_PREVIEW_CMD"` and `_fzf_history_clean` its own
  `--prompt`. Same class as config that looks load-bearing and is inert.

  Deleted here rather than in #682 proper because their values embed palette colours, and
  #679's theme generator would otherwise have carried dead config forward into the new
  mechanism. #682 remains open for its other two bugs (the unbound `Alt+C`, and
  `parity-check.sh`'s unproven one-to-one claim).

## [v5.5.0] - 2026-08-30

### Changed

- **`atuin/config.toml` no longer pins `search_mode`, so a machine can finally choose it.**
  The line asserted `"fuzzy"` — which is atuin's OWN default (`atuin default-config` ships
  it commented out at that value), so it pinned a default rather than choosing anything.
  What it DID do was shadow `ATUIN_SEARCH_MODE`, under the same precedence rule `[daemon]`
  documents at length: atuin builds config as defaults → Environment → **file**, and the
  later source wins, so any key present here beats the environment.

  That blocked the one mode worth opting into. **`daemon-fuzzy`** routes interactive search
  through the atuin daemon, and is meaningful only where that daemon runs — which Core
  ships **off**, per machine, for the reasons already recorded in `[daemon]`. It cannot be
  a fleet-wide assertion: even on a host that opted in, `os/alpine.zsh` deliberately leaves
  the daemon off **inside containers**, and these repos target containers as much as hosts,
  so a blanket `daemon-fuzzy` would apply on precisely the shells with no daemon to talk to.

  **No host changes behaviour.** atuin still defaults to `"fuzzy"`, so an unset key and the
  old assertion are the same thing everywhere — the difference is only that the override
  now reaches. A machine running the daemon sets `ATUIN_SEARCH_MODE=daemon-fuzzy` from its
  OS layer (`os/<os>.zsh`) or host layer (`99-local`), beside the `ATUIN_DAEMON__*` exports
  that turned the daemon on.

  This is the trap `[daemon]` already warned about, found in the block above it: _"The same
  trap applies to any future per-machine key: if a machine is meant to override it via
  `ATUIN_*`, it must not be written here."_ `search_mode` was written here.

### Fixed

- **`make publish` reported a network failure for a stale tag, and hid the evidence.**
  `scripts/tag-release.sh` opened phase 2 with `git fetch -q --tags origin 2>/dev/null`.
  The `vN` major alias is **force-moved to every release**, so any clone that missed one
  carries a stale local `vN` — and a plain `git fetch --tags` REFUSES to move it
  (`! [rejected] v5 -> v5 (would clobber existing tag)`), exits 1, and takes `publish`
  down with it. Nothing was wrong with the network, but with stderr redirected to
  `/dev/null` the only thing the operator saw was `could not fetch origin — publishing
  needs the remote's view of main`, which points at exactly the wrong thing. Hit cutting
  **v5.4.3**, on a clone whose `v4` and `v5` were both behind; the actual repair was a
  one-line tag update.

  The fetch now passes `--force` and no longer swallows stderr, so a real failure names
  its cause (`Could not resolve host: …`) instead of wearing the generic message.
  Forcing is correct rather than merely convenient: `vN` is a MOVING alias whose remote
  value is authoritative by definition, so a local ref that disagrees is stale, never a
  competing truth. Immutable `vX.Y.Z` release tags are unaffected — they never move, so
  `--force` has nothing to overwrite there, and the tag ruleset forbids it regardless.

  Verified both ways: with `v5` deliberately pointed at `v5.4.2`, the old fetch exits 1
  and the new one exits 0 and realigns it, leaving `v5.4.2`/`v5.4.3` untouched; against
  an unresolvable remote it still exits 1, now printing the reason.

## [v5.4.3] - 2026-08-30

### Added

- **A gate for local gates that cannot do what their name says (#775).**
  `scripts/lib/common.sh :: _core_make_gate_hits` reads a repo's `Makefile` and reports
  three shapes, all found by hand across the fleet and none previously catchable:

  - **A skip that cannot skip.** `command -v x || { echo "skipping"; exit 0; }` on one
    recipe line, the tool on the next. `make` gives each recipe line its own shell, so the
    `exit 0` ends only that line — the target announces a skip and then runs the missing
    tool, exiting 127. Found in Debian, Fedora (×2), Offense (×3) and Defense (×2).
  - **A check that cannot fail.** A checker ended with `;` before a success echo: the echo
    runs regardless _and_ becomes the line's exit status, so findings print and the target
    exits 0. openSUSE's `lint-sh` did this while its two siblings used `&&` and
    `|| exit 1` — which is exactly why nobody looked at it.
  - **A blocking CI leg with no local mirror.** A `.markdownlint.jsonc` that only CI ever
    read, for a leg blocking since #592, plus the narrower case where the local target
    globs `'*.md'` (top-level only) while the gate lints `git ls-files` recursively.

  Rendered in two places, because the defect is in the callers and Core's audit can only
  see Core: **§8d** of `audit-core.sh` keeps the authoring repo honest, and a new
  **`make-gates`** leg in `lint-call.yml` judges each caller's own `Makefile`. Both drive
  the shipped function rather than a copy — the discipline `_core_tool_skip_count`
  records, where a test that re-implemented its subject stayed green while the defect it
  existed to catch was fully reintroduced.

  **Blocking**, and only because the fleet was cleared first. #592's markdown leg had to
  ship advisory for a release because seven of nine callers would have gone red before a
  maintainer could act; the nine #775 PRs merged while this was in review, so every
  caller's `main` measures 0 and that staging is unnecessary here. The measurement is the
  precondition, not a formality: a future rule that any caller fails must ship advisory
  the way #592 did, because callers read `lint-call.yml` at the **moving** `@v5` tag and
  meet a new rule the moment `auto-tag` moves — red on arrival, in a repo whose author
  changed nothing. Recorded on the job so nobody loosens the rule to get past a red.

  Three things worth recording about how it was built, because they are the reason to
  trust it:

  - **It found four defects the hand sweep missed** — Offense's `shellcheck` and `secrets`
    (both exit 127 with the tool absent) and Defense's `core-check`, which is the worst of
    the set: it prints its skip notice, runs `gh` anyway, and reports
    `vendored core is 5.4.1, upstream is  — a sync from dotfiles-core is owed` from an
    empty variable. A confidently wrong answer about fleet drift, not a crash.
  - **The false positives shaped the rules more than the true ones.** A first draft used
    "any `exit 0` before the last recipe line" and reported Alpine's `shell`, which guards
    shellcheck and runs it _on the same line_ — a correct skip. It also flagged `lint-zsh`
    and `zsh-syntax`, which handle failure with `|| exit 1` inside the loop. All three are
    pinned as must-not-fire cases: a gate that cries wolf on working code teaches the
    fleet to ignore it.
  - **It was seen failing before being trusted.** The fixtures are the real pre-fix and
    post-fix recipes copied verbatim, not synthetic approximations, and §8d was run
    against a defect injected into Core's own `Makefile`. A guard for a historical defect
    that is never run against that defect is the same category error it exists to fix.

  The `audit-alpine` leg caught the guard doing the thing it hunts. Its markdownlint
  reachability probe used `grep --exclude-dir` and `-I`, both GNU extensions; busybox grep
  rejects the first, so the probe exited 2, that was read as "no mirror", and Core — the
  repo that authors the rule — was reported as the one repo missing it. **A false finding
  produced by an unsupported flag, in the gate whose entire subject is checks that answer
  wrongly.** Neither flag was needed. The probe now also distinguishes "searched, absent"
  from "could not search", and stays silent in the second case: unknown and absent are
  different facts and only one is a defect. Pinned by a fixture that rejects those flags
  exactly as busybox does, so a developer box catches it without an Alpine runner.

  Complements, and does not replace, `dotfiles-MacBook/test/check-skip-guards.sh`, which
  tests the first shape at _runtime_ by rebuilding a PATH without the guarded tool. That
  is stronger evidence per finding but can only judge the repo it sits in; this is the
  static, fleet-portable half.

### Fixed

- **Footnote `¹⁴` said `ouch` was "unpackaged on Alpine outright". It is in
  `edge/testing`, and the matrix already said so one line away.** `PORTING-MATRIX.md`'s
  `ouch` row carries `testing¹⁴` in its Alpine cell; the footnote that cell points at then
  denied it, splitting `ouch` off from `duf`/`glow`/`tealdeer` as a fourth, distinct case.
  Re-queried on pkgs.alpinelinux.org: **`ouch` 0.6.1-r0, `edge`/`testing`**, maintainer
  listed, built 2025-05-28, on x86_64 and aarch64 — and absent from v3.21, v3.22, v3.23 and
  v3.24, each queried individually. That is exactly the other three's shape
  (`duf` 0.9.1-r9, `glow` 3.0.0-r0, `tealdeer` 1.8.0-r0, all `edge`/`testing`, none on
  stable). The footnote now reads `testing`-only and groups all four; the table cell was
  right and is unchanged.

  **How the file came to contradict itself is the part worth recording.** This cell was
  already corrected once, the OTHER way: an earlier `/os-package-availability` stamp set
  Alpine's `ouch` to `testing`. Then #519 flipped `¹⁴` back, citing `dotfiles-Alpine`'s
  `bootstrap.sh` comment ("also unpackaged on Alpine — cargo only") as its evidence — and
  that comment was itself wrong. Two documents agreeing is not two sources; a claim about
  what a distro packages is only ever settled by querying the distro. The `bootstrap.sh`
  comment is corrected in the same sweep (dotgibson/dotfiles-Alpine#146), so the citation
  and the cited now say the same true thing.

  **Nothing operational changes.** `testing` is not enabled on a stable release and `ouch`
  is on no stable branch, so `cargo install --locked ouch --no-default-features` remains
  its real source on Alpine — as does the bzip3/bindgen reason for those flags, which is
  unaffected and kept verbatim. The neighbouring `¹⁷` is also left alone: `jnv` returns no
  results on edge including `testing`, so it is the genuinely-unpackaged one.

- **Footnote `³⁴`'s jq security floor omitted the branch furthest below it.** The fleet
  position named Alpine 3.22/3.23/3.24 (1.8.1) as below the recorded ≥ 1.8.2 floor but
  skipped **Alpine 3.21, which carries 1.7.1-r0** — further below than any Alpine branch
  listed, and a branch the fleet still supports (EOL 2026-11-01; `dotfiles-Alpine`'s
  `install/packages.txt` reasons about it explicitly for `yazi` and `gron`). Now listed with
  the other 1.7.1 builds. Verified alongside the rest: edge 1.8.2-r0, v3.22/v3.23/v3.24
  1.8.1-r0, v3.21 1.7.1-r0.

- **`watchexec` 2.7.0 on Arch and Homebrew — the same bullet, one release later.**
  (`PORTING-MATRIX.md`) Footnote `²⁵`'s Arch/Homebrew bullet read 2.6.1, with `2.6.1-1` as Arch's
  package revision. Both have moved to **2.7.0** (`2.7.0-1`), and the block's `versions
  re-verified` stamp is now 2026-08-30. The `verified 2026-08-12` and `Linux-repo coverage
  re-verified 2026-08-21` stamps beside it are deliberately unchanged: only versions were
  re-checked, not availability or which Linux repos carry it.

  Re-checked against each repo's own package pages, per the convention the footnote declares —
  `formulae.brew.sh` (2.7.0, neither deprecated nor disabled) and `archlinux.org` (2.7.0-1). The
  other four bullets hold unchanged: openSUSE Tumbleweed and nixpkgs 2.5.1, Alpine `community`
  2.5.1-r0, GURU 2.5.0 (still the top non-`9999` ebuild), and Fedora/Debian/Kali packaging it
  nowhere. So the two-way split #611 introduced is still the right shape, and the parenthetical
  explaining it still reads true — Arch and Homebrew moved together again.

  This is the **second** bump of this line in eight days; #611 stamped 2.6.1 on 2026-08-23. That
  cadence is inherent to recording an exact version for a fast-moving upstream, and it is still
  worth recording here, because the cell's whole claim is that Homebrew packages `watchexec`
  while the MacBook `Brewfile` is the one ²¹ entry that deliberately declines it — a reader
  checking that wants a date beside the number. That assertion is unchanged, and so is the
  `Brewfile`: the audit that surfaced this found all 77 entries resolving under their canonical
  names, none deprecated or disabled.

  Surfaced by `/os-package-availability macbook` (dotfiles-MacBook#211).

- **`VENDORING.md` described a resolved `core.lock` defect as a live hazard (#670).** It
  warned, in the present tense, that three OS repos independently generate `core.lock` and
  "have already drifted from it and from each other" — naming Arch's hardcoded
  `core_branch=main`, openSUSE's SHA-in-that-field, and MacBook's read-back of the previous
  value. #593 retired all three more than a release ago. Every one of the four `make
  core-lock` targets in the fleet is now an echo-only redirect that writes nothing and names
  its own retired defect in the past tense (Offense's runs a read-only freshness check and
  points at its own pull). Telling a reader the fleet is in a state it is not in is worse
  than silence: it also spends the credibility of the surrounding warnings, which are still
  live.

  The paragraph now states the rule that survives — Core's `sync-core.sh` is the only writer
  of `core.lock` in a fan-out repo, because it stamps the lock in the same commit that
  materializes `core/` — and records the four redirects as the **enforcement** of that rule
  rather than as breaches of it. The three retired generators stay in the text as the
  evidence for why a second writer cannot be kept in step by discipline; they are no longer
  presented as something to go and fix.

- **The same stale claim stood in a second document.** `RELEASE-STRATEGY.md` also read
  "three consumers carry an independent generator of a format Core owns, and all three have
  already drifted from it", so correcting `VENDORING.md` alone would have left two Core
  documents disagreeing about the repo's own rule — the shape of defect #668 had just
  finished clearing out. Both now say one thing.

- **The runbook told you a patch cut moves `v4`, four lines after saying the fleet pins
  `@v5` (#672).** The v5.0.0 sweep corrected `RELEASE-RUNBOOK.md:183` to "currently `@v5`"
  and stopped there, leaving the bullet 26 lines below it saying a PATCH or MINOR keeps "the
  **same** alias (`v4` today)" and that every caller pinned `@v4` picks the change up. Read
  literally on the next patch cut, that force-advances the **frozen** major — the exact
  motion `RELEASE-STRATEGY.md` §"Pinning reusable workflows" forbids, and the one §8a was
  built to catch on the receiving end. Three more live claims had gone the same way: the
  straggler-hunt command (`grep -rl 'uses:.*@v4'`) now matches nothing fleet-wide and so
  reports a clean sweep by construction, and `RELEASE-RUNBOOK.md` §2/§3a plus
  `RELEASE-STRATEGY.md`'s release-paths table each described `dotfiles-Windows` as
  SHA-pinning "rather than tracking `@v4`" — a contrast drawn against an alias nothing
  tracks.

  **The rest went version-neutral rather than being bumped**, which is the point: an `@vN`
  that names no major cannot go stale, so this is the last time these lines need a sweep.
  That covers `VENDORING.md`'s two live rules, the `freshness-triage` and `modernize`
  routines' descriptions of what the fleet pins, and — deliberately outside the docs — the
  same claims where they are stated in code. `sync-core.sh:370` was a verbatim twin of
  `VENDORING.md`'s sentence about the mutable alias. Fixing the prose alone would have left
  the docs and the code contradicting each other on one rule, which is the defect #668 and
  #670 just finished clearing.

  One site took the opposite treatment, and the distinction is the rule: `sync-core.sh`'s
  `--help` still offered `refs/tags/v4` as the tag to vendor a new repo at — a ref the
  reader **pastes**, not a claim they read, so it is corrected to a concrete `refs/tags/v5`
  rather than genericized. That matches its own file's header, `ARCHITECTURE.md`,
  `VENDORING.md`, `PORTING-MATRIX.md`, and the live default in `new-os-repo.sh`. It is the
  one instance the v5.4.2 sweep missed while correcting its sibling in `new-os-repo.sh`, and
  it was user-facing output the whole time.

  The MAJOR worked example is now `@vN` → `@vN+1`, with the concrete v4→v5 commands kept but
  framed as the historical cut they are. This **supersedes** the v5.0.0 note above declaring
  that block "correct as written": it was, on the day it was written, and it stopped being
  correct the moment `v5` shipped — which is the argument for not writing a present tense
  that has to be swept every major. `CHANGELOG.md`, the proposal docs, the #515 history, and
  the `dotfiles-managed v4` marker chain are untouched; the marker is an architecture
  generation asserted by `bootstrap-test.yml` and the suite, not a tag alias.

### Changed

- **`core_branch` is documented as gone, and the flat "only sanctioned writer" claim is
  qualified (#670).** Two things were true but unwritten. First, `dotfiles-Offense` is a
  real second writer: `make core-sync` runs that repo's own `scripts/sync-core.sh`, a
  `git subtree pull --squash` that stamps all four fields, and Offense's `CONTRIBUTING.md`
  teaches it as the update route there. It is sanctioned — unlike the three retired
  generators it writes Core's format from what it actually pulled, taking `core_sha` from the
  squash commit's `git-subtree-split` trailer and `core_version` from the tree on disk, so
  the lock cannot name a commit its own `core/` does not contain — but an unqualified "only
  sanctioned writer" read as covering it and did not. `VENDORING.md` now names it as the one
  exception, and notes the consequence: Offense has two paths into `core/`, the fan-out which
  replaces the tree and its own pull which merges, and `core-integrity` gates both because
  both stamp the lock.

  Second, the pre-#453 `core_branch` field survives in no `core.lock` anywhere — all nine
  fleet locks are Core-stamped with `core_ref` — so it is now documented as gone as of v5,
  and a lock still carrying it is pre-v5 and fixed by a sync rather than by hand. Offense's
  reader-side fallback (`scripts/sync-core.sh:80-82,183`,
  `test/check-core-freshness.sh:59-63`) is the last consumer of the old name and is dead
  against every lock that exists; retiring it is a `dotfiles-Offense` change, tracked
  separately.

## [v5.4.2] - 2026-08-28

### Fixed

- **The docs still taught `git subtree` as the live mechanism (#668).** #587 replaced the
  fan-out's `git subtree pull --squash` with a pinned fetch plus `read-tree --prefix`, but
  the record never followed. Two Core documents contradicted each other on the repo's
  central mechanism, and the one giving instructions was the wrong one:
  `RELEASE-STRATEGY.md` handed the reader
  `git subtree pull --prefix=core <core-remote> vX.Y.Z --squash` for both adopting a release
  and rolling one OS back — precisely what `VENDORING.md` forbids, because it moves `core/`
  but not `core.lock` and leaves `core-integrity.sh` reporting `TAMPERED`.

  Both recipes are now the real incantation, run from a Core checkout, with the three
  constraints that make it work stated for the first time: `sync-core.sh` refuses unless
  local `HEAD` **is** the pinned commit; it reads `core_version` from the **working
  tree**, so pinning an older tag from `main` writes a silently wrong lock; and the pin
  must be the **peeled commit**, never `refs/tags/vX.Y.Z` — releases are annotated tags,
  and the script resolves its pin with `git ls-remote`, which returns the _tag object_, a
  SHA that can never equal the `HEAD` a tag checkout leaves you on. The three pre-existing
  `CORE_BRANCH=refs/tags/v…` recipes in `ARCHITECTURE.md`, `VENDORING.md` and
  `PORTING-MATRIX.md` carried that same latent defect and are corrected too. The claim that
  a rollback "merges backwards, it does not un-merge" is deleted — materializing replaces
  the tree outright, so an older pin is just an ordinary sync.

  Several surfaces an operator actually reads at runtime were asserting the retired
  mechanism: `make help`, `sync-core.sh --help`, both lines of the core-guard hook's
  refusal message, the README `new-os-repo.sh` writes into every new OS repo, and the
  **fan-out PR body shipped into nine repos on every release** ("Vendors the released Core
  into `core/` via `git subtree pull --squash`"). `.bin/sync-upstream.sh` recommended the
  forbidden command in its own error tip. All corrected, along with the now-false "the
  subtree squash records the exact Core commit" in `ARCHITECTURE.md`, `core.manifest` and
  `zsh/30-functions.zsh` — `core.lock` records it.

  One-line mechanism claims in `CLAUDE.md`, `CONTRIBUTING.md`, `SECURITY.md`,
  `ARCHITECTURE.md`, `README.md`, the PR and issue templates, the `doc-consistency`
  subagent, and the non-Markdown surfaces that carried the same sentence (`ci.yml`,
  `core-integrity.yml`, `sync-fanout.yml`, `core-integrity.sh`, `CODEOWNERS`,
  `.gitattributes`, `.pre-commit-config.yaml`) simply drop the clause: they state the invariant that matters (`core/` is a copy; a defect
  fans out N-way) and leave `VENDORING.md` the single owner of _how_, so no mechanism claim
  can go stale in ten files again.

  What **stays** is the one `git subtree` that is still live: the one-time `subtree add`
  that creates a `core/` where none exists (`scripts/new-os-repo.sh` runs it, and
  `sync-core.sh` skips a repo without one). It is now labelled as initial vendoring and
  never the update path, and its `refs/tags/v4` is corrected to `v5`. `PORTING-MATRIX.md`
  step 5 also stopped instructing an add that could not work: step 1 copies Fedora's
  `core/` across, so `subtree add` there fails with _prefix 'core' already exists_ — the
  step is a re-vendor via `sync-core.sh`.

## [v5.4.1] - 2026-08-28

### Fixed

- **The `os.capabilities` fleet gate deadlocked the fan-out it depends on (#667).** §9c shipped
  BLOCKING on a missing declaration, and `scripts/sync-core.sh` runs `make audit` over a fleet
  checkout **before** it vendors anything — deliberately, so a red tree never reaches nine repos.
  But a declaration cannot merge into an OS repo until that repo has vendored the Core whose
  validator accepts it, and **that vendoring is the fan-out**. So the gate refused to fan out the
  very release that would let the declarations land: v5.4.0 published, `sync-fanout` failed, and
  zero vendor PRs opened.

  The two findings now carry two severities. A **malformed** declaration still blocks — the repo
  authored one and got it wrong, and no release cycle makes that acceptable. **No declaration at
  all** is advisory for one cycle, then flips.

  This is the same red-on-arrival shape §5f and `lint-call.yml`'s owned-block gate both name, and
  both answer the same way. It is also the shape this change's _own_ `lint-call.yml` step already
  got right — that step makes a missing declaration advisory and a malformed one blocking. The
  asymmetry between the two halves was the defect, not the reasoning in the workflow.

## [v5.4.0] - 2026-08-27

### Added

- **The fleet declares (#667).** #663 defined `os.capabilities` and #664/#665/#666 made `up`, the
  maint runner and `core-doctor` dispatch through it — but **nothing had authored one**. All nine
  repos lacked `os/<os>.capabilities`, so `blib_link_os_layer`'s `[[ -f ]]` guard linked nothing,
  `$_CORE_CAP` was empty on every box, and all three consumers ran Core's built-in fallback rows.
  The mechanism was live and unexercised for two releases. **Seven declarations** now exist,
  transcribed from `PORTING-MATRIX.md` §"Package-manager commands" and cross-read against Core's
  built-in rows, so a declaration that behaves differently from the row it replaces is a visible
  diff rather than a silent one.

  **Seven, not nine, and that is the answer to the question #667 left open.** `dotfiles-Offense`
  and `dotfiles-Defense` have no `os/` directory and never call `blib_link_os_layer` — the OS band
  belongs to the repo underneath them — so they declare nothing and inherit the OS layer's table.

- **`audit-core.sh` §9c — fleet coverage.** §9a holds Core's shipped example to the schema; this
  holds the repos that run on real boxes to it. It is the half that matters for the failure above:
  a per-repo `make lint` catches a _broken_ declaration, but only a fleet sweep catches a _missing_
  one — a repo that never authored a file has nothing for a per-repo target to fail on, and the
  absence is invisible from inside it. The Role-repo exemption is **structural** (does this repo
  have an `os/` directory) rather than a name list, so a repo that grows an OS band starts being
  gated automatically, and per-tier declarations are picked up without the gate knowing they exist.

- **`scripts/new-os-repo.sh` scaffolds a schema-valid declaration.** The script already centralised
  the load order _"so a scaffolded repo can never start out of order"_; the capability table is the
  same argument, and a repo scaffolded without one boots onto the fallbacks and **looks fine** —
  which is precisely how the fleet reached nine repos and zero declarations. The stub carries every
  required key (so `make capabilities` is green on day one) with Fedora's values and a banner saying
  they are wrong anywhere else. The optional keys are deliberately **not** stubbed: in this schema an
  omission is a statement, so pre-declaring them would hand every new repo the permissive answer.

### Changed

- **`_core_install_prefix` reads `PKG_INSTALL` (#667).** The last **17** of the 154 package-manager
  references Core carried in portable modules. It also fixes a reach the mapping could not make: the
  `<mgr>` token came from `_pkgup_mgr`, which is band 60 and absent under `CORE_PROFILE=minimal` and
  `standard`, so `core-doctor`'s "install missing" remedy and the command-not-found hint printed
  **nothing** on a lean profile while the `✗` rows they explain stayed. `$_CORE_CAP` is band 02 and
  in every profile, so on a declaring box both now work everywhere.

- **`scripts/new-os-repo.sh` vendors `refs/tags/v5`, not `v4`.** Unrelated to the above and found
  next to it: a repo scaffolded today pinned a Core **a major behind** — one with no capability
  dispatch at all, so the stub it now writes would have had nothing to dispatch through.

### Fixed

- **Two comments that named a key the schema has never had.** `zsh/55-maint.zsh` and its
  `audit-core.sh` §5c note both said `SCHEDULER_UNIT_PATH`; the key is `SCHEDULER_UNIT_DIR`, and the
  DIRECTORY-not-path distinction is the whole reason it exists — Core appends its own unit name so
  the unit it writes cannot be decoupled from the one it enables.

### Note

- **The built-in fallbacks are NOT deleted here.** Three blocks say "DELETE THIS BLOCK IN #667";
  they now say #763. A declaration reaches a box only once `bootstrap.sh` has **linked** it, and
  that is a separate event from the Core fan-out that delivers this release — so deleting them here
  would leave `up` answering "this archive does not offer that" on every host that pulled and had
  not re-run `./bootstrap.sh --links-only`. #763 does the demolition, gated on evidence that the
  fleet has actually re-bootstrapped rather than on elapsed time.

- **No clipboard capability key, superseded rather than skipped.** #667 listed
  `PORTING-MATRIX.md` §"Clipboard packages to install" as a transcription source; #663 had already
  decided otherwise and the schema rejects such a key. `bin/clip` is re-exec'd by nvim and tmux on
  every yank and paste, and its WSL probe was already rewritten once to avoid forking a `grep` per
  invocation — a file read and parse there would give back exactly what that bought, for a value
  that changes once per machine. The matrix now records this so it is not re-opened.

## [v5.3.0] - 2026-08-27

### Changed

- **The scheduled runner dispatches through `os.capabilities` too (#665).** `maint/dotfiles-maint.sh`
  carried **49 package-manager references** — the second-largest concentration of OS knowledge in
  Core, and a second copy of the ladder #664 just removed from `zsh/60-update.zsh`. Two copies of
  one fact drift, and these had: the maint ladder grew **no emerge arm at all**, so a Gentoo box's
  daily run has never counted anything, and its zypper apply says `up` where the interactive one
  says `dup` on Tumbleweed. There is now one.

  `zsh/55-maint.zsh` keeps `_maint_scheduler` as the dispatcher — switching on a capability rather
  than an OS name was always the right shape — but the answer now comes from the OS layer's
  declared `SCHEDULER`, with the probe as the fallback for a box that has not declared.

- **`SCHEDULER` gains `cron`, which was a defect in the schema rather than a judgement about cron.**
  Core's `_maint_scheduler` has had a live cron arm all along — it is what an OpenRC box (Alpine,
  Gentoo) gets, having `crontab` and no systemd — so #663's enum was rejecting a value Core itself
  produces, and `scripts/test-core.sh` asserted that rejection. Alpine's only honest declaration was
  `none`, which means "this box cannot hold a timer", on a box that can.

- **A bash reader for the declaration, which the contract promised and nothing implemented.**
  `examples/os.capabilities.example` and `lib/bootstrap-lib.sh` both said `maint/dotfiles-maint.sh`
  reads the same file with `sed`; it did not. It now does — extracted, never sourced, for the reason
  #663 chose flat `KEY=value`: sourcing a per-repo file into the one process in this system that may
  call `sudo -n` is a code-execution surface, and extraction cannot execute anything. Same strictness
  and the same trailing-whitespace trim as the zsh reader, so the two cannot disagree about one file.

### Added

- **`SCHEDULER_UNIT_DIR` — the key that gets the last OS-absolute path out of Core.**
  `~/Library/LaunchAgents` appeared at **six sites** in `zsh/55-maint.zsh` and was the reason
  `audit-core.sh` §5c carried a per-file exception. It now survives in exactly one place: the
  built-in fallback for a box that has not declared. #667 authors the key across the fleet and
  deletes that block, **and the §5c exception goes with it** — together with #664's sibling
  package-manager fallback.

  A **directory**, not a path, and the split is load-bearing: where units live is an OS fact, but
  what Core calls its own job (`dotfiles-maint.service`, `com.dotfiles.maint`) is Core's identity and
  is what `systemctl enable` and `launchctl` name. A declaration that could rename the file would
  decouple the unit Core writes from the one it then enables — installed, reported healthy, never
  run. The validator rejects a value ending in `.service`/`.plist`/`.timer` for that reason.

  The plist and unit **templates stay in Core**, and are not the exception. They are portable text
  parameterised by paths, selected by `_maint_scheduler`. Pushing them outward would put one systemd
  unit in seven copies with no owner — the hand-maintained N-way drift `VENDORING.md` records as the
  #449 failure. The OS layer owns _where_ the unit goes, not _what it says_.

- **`MAINT_UNATTENDED_UPGRADE`, and the direction of its default is the whole point.** Scheduled
  system upgrades are now gated twice: the operator's `MAINT_SYSTEM_UPGRADE=1` env var **and** the
  repo's declared opt-in. **Omitting it refuses.** A fail-open here silently applies full system
  upgrades on an engagement box, unattended, on a schedule nobody is watching — so `=0` is _rejected_
  by the validator rather than read as "declared", which is how a value written to forbid something
  would have permitted it.

  This replaces two hand-rolled refusals: Kali, read out of `/etc/os-release` (OS knowledge in Core),
  and Arch/Gentoo, inferred from `have pacman || have emerge` — a probe for a **binary** standing in
  for a claim about a **distro**, true on any box with pacman installed for other reasons. Each repo
  now says so itself, and a repo Core has never heard of refuses by default instead of being waved
  through.

### Fixed

- **`XDG_CONFIG_HOME` was never defaulted in `maint/dotfiles-maint.sh`.** It defaults `XDG_CACHE_HOME`,
  `XDG_STATE_HOME` and `XDG_DATA_HOME` but not `CONFIG`, so the new declaration path would have
  resolved to a bare `/zsh/os.capabilities` on a box that does not export it — unreadable, and the
  runner would have silently behaved as though the box declared nothing. Found while wiring the
  reader; it would have been a silent no-op rather than an error.

- **An empty assume-yes vector no longer risks a bash 3.2 `set -u` abort.** Expanding an empty array
  as `"${a[@]}"` is an unbound-variable error on bash 3.2, which macOS still ships and every gate here
  is held to — and an archive that declares no `PKG_ASSUME_YES` (Arch, Gentoo, Alpine) is exactly the
  empty case. Uses the `${a[@]+"${a[@]}"}` guard.

- **`core-doctor` classified opt-in-vs-expected from one Core-side list, so it reported
  healthy boxes as degraded (#666).** A tool that is genuinely optional on one distro and
  expected on another was reported as expected everywhere. `jj` and `ast-grep` are the known
  cases — `PORTING-MATRIX.md` marks them 21 in the **Gentoo and Kali cells only**, while Arch,
  openSUSE and Alpine package them — and `dust` is the same shape on the Debian family. The
  result was a health report showing a degraded integration on a box where nothing was wrong,
  which is the failure mode most likely to train an operator to ignore the report.

  Core recorded this as unfixable without a new artifact and said so in its own words:
  _"a Core-side list cannot say 'opt-in there, expected here' … Fixing that properly needs a
  per-repo manifest; this is the fallback default until one exists."_ #663 landed the
  manifest; this spends it. `core-doctor` now reads the split from the repo's own
  `TOOLS_OPTIN`, and the JSON `expected` object moves with the render so a gate asserting it
  cannot disagree with the glyph a human reads two lines above.

  **A declared list REPLACES Core's default rather than adding to it**, so a repo declaring
  this key must re-state everything it still considers optional — recorded in the example,
  because the failure mode is silent and lands on whoever authors the nine declarations.

  **This key falls back per-key, and that is deliberately unlike `up` and the maint runner.**
  Those treat a declaration as authoritative all-or-nothing because for them an omission is a
  SAFETY statement — no `PKG_ASSUME_YES` means never auto-confirm, no
  `MAINT_UNATTENDED_UPGRADE` means refuse — and answering a refusal with a Core default would
  permit what the repo forbade. `TOOLS_OPTIN` carries no such claim: omitting it says the repo
  has not curated a list, not that nothing is optional. Reading it the other way would mark
  every uninstalled optional tool as degraded and manufacture exactly the alarm fatigue the
  opt-in state exists to prevent.

  #666 flagged that this could disagree with #697's stale-flag reporting, since it changes
  what "expected" means underneath it. They are independent by construction —
  `_core_doctor_stale` runs on both the opt-in and the missing branch — and there is now a
  test pinning that, so a future edit cannot quietly stop checking a reclassified tool.
