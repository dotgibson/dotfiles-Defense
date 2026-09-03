# Changelog — recent releases

GENERATED FILE — do not edit by hand. `scripts/gen-changelog-recent.sh` rewrites it
wholesale, `scripts/release.sh` runs that generator on every release, and
`scripts/audit-core.sh` §9e fails when this file is not byte-identical to a fresh
render. To fix a conflict or a stray edit, re-run the generator — never patch it.

The last 8 released sections of `CHANGELOG.md` (v6.1.0 … v5.4.0), vendored into every OS repo's
`core/` by `core.vendor` so `core whatsnew` can answer offline. The full changelog is
repo-meta and stays upstream:
[dotgibson/dotfiles-core/CHANGELOG.md](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md).

## [v6.1.0] - 2026-09-02

### Changed

- **The atuin daemon-guard research apparatus is archived under `scripts/research/`, and its
  weekly workflow is dispatch-only (#687).** `verify-atuin-guard.sh` (1,845 lines),
  `bench-atuin-daemon.sh` (1,225) and their shared `lib/atuin-db.sh` measured the premises
  `_core_atuin_daemon_guard` rests on and the daemon's write-latency claim — for a feature
  that ships OFF on every box. They answered those questions once, and the answers are
  recorded in `atuin/config.toml` and `zsh/00-tools.zsh`; what remained was
  `atuin-guard-verify.yml` re-asking a settled question every Tuesday at the cost of five
  repo checkouts, one of five scheduled sweeps firing inside four hours each week. The
  three files move to a clearly-marked `scripts/research/` (with a README stating the
  rules: never vendored, never scheduled, re-measured on purpose), the workflow drops its
  cron and keeps `workflow_dispatch` — the checksum-verified, tokenless live-upstream
  measurement stays one `gh workflow run atuin-guard-verify` away — and its schedule-only
  `notify-failure` job goes with the schedule. The four `make` targets stay as the manual
  invocations. No OS repo gains or loses a file: #676 had already left all three out of
  `core.vendor`, so what a sync carries from this change is the comment and prose repoints
  in `zsh/00-tools.zsh`, `atuin/config.toml` and `PORTING-MATRIX.md` — no behaviour — and
  the one fleet reference (`dotfiles-Alpine/bootstrap.sh` naming `verify-atuin-guard.sh`'s
  `ver_cmp`) is a comment, not a call. `examples/atuin-daemon.service`
  — counted in the issue's 3,730 lines — is deliberately untouched: it is shipped, and two
  bootstraps install it. The runtime guard in `zsh/00-tools.zsh` is untouched too; that is
  the part with a job. The hermetic self-test still drives the archived detector —
  `test-core.sh` §J3-J4 behind the `atuin` scope, and the cheap §J2 bench-harness checks
  unconditionally, as before — and `audit-core.sh` §2 now asserts
  `scripts/research/lib/*.sh` as a sourced lib (mode 100644) like `scripts/lib/`.

- **`bootstrap-test.yml`'s resolve job prints the resolver's own error under each
  unresolved name.** The probe ran with its output discarded, so a red run said only
  which names failed — and a name fails to resolve for reasons only the resolver can tell
  apart: renamed or dropped upstream, a dependency missing from a half-synced mirror, or a
  container snapshot the repo no longer agrees with. dotfiles-openSUSE#149 sat through
  four runs with three names and no reason. The last eight lines of the probe's output now
  follow each `UNRESOLVED:` line; pass/fail is unchanged. Reaches the OS repos at the next
  `@v6` tag.
- **`GITHUB-APP-AUTH.md` split into a live reference and a frozen record (#683).** The
  file mixed three concerns — how the auth works now, the G2 migration that produced it,
  and how to recover when the App is not working — and they drifted apart. That is the
  defect #683 opened on: the top said both PATs were deleted while a paragraph 157 lines
  down said one was "still present", and the recovery procedure was buried _underneath_
  that sentence, inside a heading reading "Step 5 — migrate the consumers". An operator
  reaching for recovery mid-incident had to read a migration runbook to find it, and what
  they found was a migration-era leftover that no longer worked. `GITHUB-APP-AUTH.md`
  keeps its name — every inbound reference stays valid — and now holds only what must
  stay true: what runs today, the permissions the App must hold, where it is installed,
  how to add a consumer, and **Recovery** promoted to a top-level section.
  `GITHUB-APP-MIGRATION.md` takes the history, marked frozen and explicitly not a
  template, since the patterns it prescribes name secrets that no longer exist.
  Two structural fixes came with it: the recovery procedure is now **self-contained**
  rather than pointing at a historical section for the fallback pattern it restores — that
  coupling is what let a live instruction rot when the history around it changed — and the
  numbered `Step N` headings are gone in favour of named sections, because the one inbound
  cross-reference in `sync-fanout.yml` pointed at "Step 1" and would have silently aimed
  at the wrong place. The still-open constraint on `notify-web-call.yml`'s declared
  `WEBHOOK_SECRET` input lives in the **reference**, not the record: it is a current rule
  about a future change, and keeping it in a file marked frozen would be the same drift
  the split removes. The App's registration and private-key handling moved to the reference
  too rather than the record — key rotation is an operational task, not history. The
  recovery procedure also gained an exit: it used to end with broad PATs live and no way
  back, which is the state G2 removed, and worse than pre-G2 because `token-health` — the
  probe that watched those PATs for silent expiry — was retired because nothing depends on
  a minted token surviving (each run mints a fresh one, so there is no expiry date to miss;
  they do expire, in about an hour). Nothing watches a re-provisioned PAT, so it now says so
  and prescribes reversing all seven steps, deleting the PATs, and verifying it.

### Added

- **`PORTING-MATRIX.md`'s two data tables are generated from the OS repos (#686).** The
  package-manager table restated the seven `PKG_*` verbs every `os/<os>.capabilities`
  already declares (and `check-capabilities.sh` already gates), and the package-name
  table restated `install/packages.txt` — including the `# min:` floors that
  `dotfiles-Debian` and `dotfiles-Gentoo` enforce in CI — as a copy nothing checked.
  `scripts/gen-porting-matrix.sh` now renders both into
  `<!-- core:porting-matrix:gen … -->` marker pairs, the way `gen-aliases.sh` renders the
  cheat sheet: verbs verbatim from the declarations (openSUSE's Leap/Tumbleweed pair
  rendered as both, labelled), package names from the lines the repo's own reader would
  install — Debian's list read through its `scripts/pkg-filter.sh` tiers so `only:kali`
  and `skip:kali` land in the right column — with a floor shown as `≥ X.Y.Z`. The table
  was never a plain transposition, and the generator says so rather than pretending: a
  cell the repo installs is _derived_; the footnote-²¹ "available, not installed" names
  and the `asset`/`cargo`/`AUR`/`GURU` routes only `bootstrap.sh` knows are _asserted_ in
  the script's `PKG_ROWS` registry, and a repo that starts installing an asserted one
  through `packages.txt` is exit 2 naming the cell — the one transition on that half the
  generator can see; a changed out-of-band route stays the footnotes' job. The ~1,100 footnote
  lines are untouched. `make audit` gains §9h; because the inputs are sibling clones, an
  absent one is exit 3 → an environment SKIP naming the repos (the §9c posture), never a
  gate that only passes on one laptop, and `--require-siblings` reds it. `Makefile` gains
  `gen-porting-matrix` / `check-porting-matrix`; `--list` prints every cell's provenance;
  `--fleet DIR` points a worktree at the real fleet. Visible cell changes: the four
  floored cells, and the commands table now shows the declared verbs exactly (`-y` /
  `--noconfirm` on install/remove, `sudo dnf check-update`, `gentoo-pkg-pending`).
- **The `core` front door reaches every first-party family: `core maint
  <install|run|log|status|uninstall>`, `core sync` and `core update check` (#684).**
  Core ships two hyphen-namespaced families — `core-help`/`core-doctor`/`core-version`
  and `maint-install`/`maint-run`/`maint-log`/`maint-status`/`maint-uninstall` — and
  only one was wired to the front door, which was the single most visible incoherence
  in the verb surface. The dispatcher's own header gives the reason the namespace
  exists (it keeps the generic-sounding verbs reachable under a form that won't be
  mistaken for some other tool); the same argument covered `maint-*`, `update-check`
  and `gsync`, which were simply never added. Additive only: every bare name keeps
  working exactly as before, and `core update -y` still belongs to `up` — only the
  literal word `check` in first position is intercepted. Retiring the bare names was
  decided against in #692.

  Each new arm carries the same availability guard as `core update`: `maint-*` is
  band 55 and `up`/`update-check` band 60, both after this file, and `gsync` is a
  band-20 function a trimmed `$ZSH_CFG` can drop — so when the twin is not loaded the
  arm NAMES THE FRAGMENT (`55-maint.zsh`, `60-update.zsh`, `20-aliases.zsh`) instead of
  reaching a missing function. A bare `core maint` (or `-h`/`--help`) prints the
  family's usage on stdout and returns 0, the way a bare `core` is the cheat sheet; an
  unknown sub-verb gets its own did-you-mean (`core maint stauts` → `status`) over
  the new `$_CORE_MAINT_SUBCMDS`, the second single source beside `$_CORE_SUBCMDS`.

  `_core` completes the new verbs and delegates to each twin's own completion
  (`_maint-install`'s times, `_maint-log`'s `-f`, `_up`'s flags plus `check`), shifting
  `words`/`CURRENT` so the twin sees itself at `words[1]` — without that, `core maint
  install <tab>` offered nothing. And a new gate in `scripts/test-core.sh` asserts
  `_core`'s describe arrays mirror the two dispatcher lists, because the header comment
  that asked for it was the only thing keeping them in step. `PARITY.md` records
  **Update check** and **Maintenance** as `aligned` rows with `parity-check.sh` needles
  on both shells (dotgibson/dotfiles-Windows#236 adds the pwsh arms and lands first),
  and **Upstream sync** as `deliberate` — Windows replicates Core rather than vendoring
  `core/`, so there is no subtree to push.

- **`aliases.md`'s tables are generated from the zsh sources and gated by `make audit`
  (§9g, #685).** ~200 of the cheat sheet's lines were a hand-copy of data the shell
  already held — the `alias` lines in `zsh/20-aliases.zsh` and `zsh/25-git.zsh`, the
  `hash -d` named directories, the `_core_help` one-liners in `zsh/30-functions.zsh` — and
  the doc said its function descriptions "are the same one-liners those surfaces print".
  One already wasn't: `mkcd` was described three ways in three places. A sentence is not a
  gate, so this is `theme/palette.toml` → `gen-theme.sh` applied to the cheat sheet.
  `scripts/gen-aliases.sh` renders every table between a `<!-- core:aliases:gen … -->`
  marker pair straight from the sources: _Expands To_ is the alias value **verbatim**
  (`$BAT_BIN --paging=never`, `git checkout "$(git_main_branch)"` — what the shell holds,
  not a paraphrase), _Requires_ is the `HAVE_*` flag guarding it, _Note_ is the alias
  line's trailing comment, and _Does_ is the `_core_help` description — so the
  `core-status` / `core-whatsnew` rows shrink to the one-liner `--help` prints, which is
  what makes the doc's claim true. Which alias sits in which table is the one decision
  left to a human and lives in the script's `BLOCKS` registry; coverage is bidirectional
  in the `parity-check.sh` manner, so an alias added to a source and listed nowhere fails
  the audit by name (exit 2, rendered apart from drift's exit 1), as does a listed name
  nothing defines. `--root` drives it against a hermetic fixture (test-core.sh F10b: clean
  render, own-output `--check`, drift inside a block, an edit outside the markers that
  survives regeneration, an unclaimed alias, a deleted end marker, idempotence, and
  `--check` writing nothing). The prose — the `web`/`$BROWSER` explanation, the cdup-vs-up
  footgun, the confirmation note — stays hand-written outside the markers. `core help` is
  deliberately **not** folded into this: it is a curated 40-row index with shorter blurbs,
  a different product for a different moment, and the README no longer calls it "the
  complete one" — for git aliases it lists 14 of 62. Its `mkcd` row did regain "(and
  parents)". A dozen alias lines gained a trailing comment so the rendered Note column
  keeps the glosses the hand-written doc had (`# previous directory`, `# interactive`, …).

- **`make audit` gates the reusable workflows' documented caller examples (§8a-bis, #821).**
  §8a proves the `ref:` keys name the right major. It does not read comments — so at
  v5 → v6 every ref moved correctly while 25 `@v5` references survived in the prose
  describing them, including the copyable `uses:` examples six `*-call.yml` headers hand
  to OS-repo maintainers. Nothing failed, because nothing was wrong in the code; anyone
  standing up a caller from one simply pinned a retired major. Same silent shape §8a
  exists to end, one level up, so it gets the same answer: `_core_workflow_example_hits`
  compares every documented example against `core.version` and fails the audit on a
  mismatch. Scoped to a full `dotfiles-core/.github/workflows/<file>@vN` path, which is
  always a copyable reference and never narrative — a blanket `@vN` scan would be **worse
  than no gate**, because it reds on the true historical sentences (`claude-routines-call.yml`
  narrating the v4→v5 cut; `lint-call.yml` naming the release the os.capabilities schema
  landed in) and would train the next person to falsify them. Bare prose like "pinned to
  v5" is deliberately not judged: indistinguishable from that history without a marker
  convention this does not earn. The match carries the owner and a left boundary so a
  lookalike repository (`someone/not-dotfiles-core/…`) is not attributed to Core and
  cannot red this always-on gate. Driven against the real regression, not only fixtures:
  the suite rebuilds `v6.0.0` and `v6.0.1` — both of which SHIPPED with seven documented
  examples on `@v5` while every `ref:` read v6 — and requires a red on each.
  **The audit job now checks out with `fetch-depth: 0`**, which is what makes that real:
  on the default shallow checkout the tags are absent, so those assertions SKIPPED in CI
  and the suite passed on synthetic fixtures while claiming otherwise. That was already
  true of the sibling guard's v4.0.0 / v5.0.2 cases, which have never once run in CI —
  so this switches on coverage the repo believed it already had.

### Fixed

- **`atuin-guard-verify` reports a verdict past the anchor instead of dying (#826).** The
  first measurement against an atuin newer than the anchored 18.19.0 — the 1 Sep run, on
  18.21.0 — exited 3 with no output and filed "the workflow itself is broken". Two defects,
  one per layer. In the workflow, GitHub's default `bash -e {0}` aborted the measure step on
  the verifier's non-zero exit before the step's own `case` could classify rc 1/3 as
  reports; both measure steps now `set +e`, since that case statement is the error handling.
  In the verifier, `--premise autostart` still waited on the pre-18.20 data-dir socket while
  the sandbox pins `TMPDIR` — so a healthy 18.20+ daemon (which binds under
  `$TMPDIR/atuin-$UID/atuin.sock` since upstream atuinsh/atuin#3910) never "answered" and the
  run was `unmeasurable` by apparatus limit. `SOCK` now follows the measured version, the
  hermetic stub binds where a real daemon of the version it claims binds, and a new
  `test-core.sh` §J4 case (a healing stub claiming 18.20.0) pins it. The runtime guard in
  `zsh/00-tools.zsh` already probed the new path first; only the research apparatus was behind —
  and `PORTING-MATRIX.md`'s socket-path footnote, which still said the move had shipped in no
  release, now says 18.20.0 and records the `0700` rule.
- **`maint-install <tab>` (and now `core maint install <tab>`) no longer throws a parse
  error (#684).** The completion's `_arguments` spec described the operand as
  `(HH:MM, 24h)` with a bare colon, which `_arguments` reads as the message/action
  separator — so every tab threw `parse error near ')'` and offered nothing. Found while
  routing the front door through it; the colon is now escaped.

- **The reusable workflows' caller examples pinned `@v5`, a major behind the tree (#821).**
  Core is v6 and the fleet's callers are on `@v6`, but 25 `@v5` references survived across
  six `*-call.yml` files — including the copyable `uses:` examples in their headers, so
  anyone standing up a new caller from one landed on a retired major. Every actual `ref:` was
  already `v6`; only the prose describing it had drifted, which is why nothing failed.
  `audit-core.sh` §8a validates `ref:` lines against `core.version` and does not read
  comments, so the gate that exists for precisely this class of error could not see it.
  The sharpest illustration is `claude-routines-call.yml`, where the comment warning that
  this line "has now gone stale twice" sat directly above a correct `ref: v6` while itself
  saying `@v5` — the same drift, one level up, inside its own warning. One `@v5` is
  deliberately kept: the sentence narrating the v4→v5 cut, which would be falsified by
  bumping it.

- **The "no dispatch token" warning names the missing credential, not the App's behaviour (#823).**
  Both dispatchers warned `the fleet App minted no token here` when `TOKEN` was empty. The
  mint cannot do that: it is gated on `vars.FLEET_APP_ID != '' && env.HAS_APP_KEY == 'true'`,
  and a mint that is ATTEMPTED and fails errors inside `create-github-app-token`, failing the
  job before the warning branch is reachable. An empty token has exactly one cause — the step
  was **skipped** — so the message now names that: a missing `FLEET_APP_ID` variable or
  `FLEET_APP_PRIVATE_KEY` secret. The reusable's wording differs deliberately, because a
  reusable workflow sees only the secrets its caller hands it, so there the key may simply
  never have been passed — and nine repos execute that copy. This matters more since #683
  removed the fallbacks: with no PAT behind it, this warning is the ONLY signal that a repo
  has silently stopped refreshing the showcase, and pointing an operator at the App's
  installation sent them to the wrong place. `sync-fanout.yml`'s preflight comment carried
  the same loose phrasing and is corrected too. `GITHUB-APP-AUTH.md`'s rollback section had
  the old warning pasted in verbatim and would have gone stale on merge; rather than paste
  the new one, it now **describes** the degradation, since a copied message is exactly the
  kind of duplicated fact this changelog entry exists to stop repeating.

- **The fleet PAT retirement is finished in Core, and the docs now agree about it (#683).**
  `GITHUB-APP-AUTH.md` said "both PATs are deleted" on line 9 and "still present until the
  retire step" on line 166, and three workflows plus two `RELEASE-RUNBOOK.md` sites sided
  with "still present". Exactly one could be true and both readings were bad: either the
  documented rollback was a dead path, or long-lived credentials were live in the fleet
  with the probe that watched their expiry deliberately retired. **Checked against the
  live state (2026-09-01): the PATs really are gone** — `FLEET_SYNC_TOKEN` and
  `WEBHOOK_SECRET` are absent from all twelve fleet repos at repo _and_ org scope, leaving
  `FLEET_APP_PRIVATE_KEY` (org secret) and `FLEET_APP_ID` (org variable) as the only fleet
  auth. So `token-health`'s retirement was justified after all and no expiry check needs
  restoring; what was wrong was the rollback, and every `|| secrets.…` fallback, which had
  been dead code resolving to the empty string. Removed the fallbacks from `sync-fanout.yml`
  (3 sites), `notify-web.yml` and `notify-web-call.yml`, stopped `release.yml` passing
  `WEBHOOK_SECRET`, and
  rewrote the rollback as what it actually is — a deliberate re-provisioning (mint a PAT,
  add the secret, restore the expressions, re-add each caller's `secrets:` mapping, _then_
  unset `FLEET_APP_ID`), not a toggle. The last two steps are not optional: a reusable
  workflow does not inherit its caller's secrets, so with `release.yml` now passing only the
  App key the restored expression in `notify-web-call.yml` would read an empty
  `WEBHOOK_SECRET`; and `app_token || secrets.…` prefers the left side whenever it is
  non-empty, so a still-minting App keeps winning even when its token is too narrow to push,
  while an App that fails to mint fails the step before the fallback is ever evaluated. The verification
  command is recorded in `GITHUB-APP-AUTH.md` so the next reader re-checks rather than
  re-argues. `sync-fanout.yml` now also states that the App's **Workflows: write** grant is
  load-bearing with no safety net: a permission edit awaiting installation approval still
  mints on the old set, failing every fan-out until accepted. **Not** removed:
  `notify-web-call.yml`'s declared `WEBHOOK_SECRET` input, which nothing reads. At the time
  of this entry the nine OS-repo callers still passed it; they have since been bumped
  (#819). Dropping the declaration is a caller-visible break either way — it changes the
  `workflow_call` contract — so it is marked deprecated-and-ignored and comes out on the
  next MAJOR.

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
