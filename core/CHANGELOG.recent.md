# Changelog — recent releases

GENERATED FILE — do not edit by hand. `scripts/gen-changelog-recent.sh` rewrites it
wholesale, `scripts/release.sh` runs that generator on every release, and
`scripts/audit-core.sh` §9e fails when this file is not byte-identical to a fresh
render. To fix a conflict or a stray edit, re-run the generator — never patch it.

The last 8 released sections of `CHANGELOG.md` (v7.4.2 … v7.0.0), vendored into every OS repo's
`core/` by `core.vendor` so `core whatsnew` can answer offline. The full changelog is
repo-meta and stays upstream:
[dotgibson/dotfiles-core/CHANGELOG.md](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md).

## [v7.4.2] - 2026-09-13

### Fixed

- **openSUSE is recorded on the `blib_install_core_guard` row — the row closes at 9/9** (#986;
  follow-up to #992). A `blib_main` caller is credited with the whole helper contract, and the
  driver installs the Core guard openSUSE's own bootstrap never had, so §5f read the repo as
  `advanced` on that row the moment dotgibson/dotfiles-openSUSE#186 merged — the state the
  v7.4.1 fan-out audit meets. Same shape as Defense in #988. (`scripts/audit/40-fleet-registers.sh`)

## [v7.4.1] - 2026-09-13

### Fixed

- **`blib_main` always exports `BLIB_DRY` as 0 or 1, and `BOOTSTRAP_SU=lazy` also skips the
  driver's sudo keepalive** (#990, #991 — two defects in #985, each found by the next adopter).
  The driver exported `BLIB_DRY` only on a dry run, so a hook written `((BLIB_DRY)) || return 0`
  — valid bash, clean under every linter — died with `unbound variable` under `set -u` on the
  first REAL run: the stubbed full-provision CI leg, the one path a dry-run test cannot cover
  (dotgibson/dotfiles-Debian#78's first run). And `lazy` told the driver not to resolve an
  escalator but still wrapped `bootstrap_provision` in the keepalive, which would prime sudo
  on a repo whose run may never need it (Offense without `--install`) and fail outright where
  the escalator is not sudo. Both knobs are now always 0/1 and lazy means the hook owns
  escalation end to end; the fixture in `scripts/test/37-bootstrap-driver.sh` reads
  `BLIB_DRY` bare on purpose and runs a lazy case with `BLIB_SU` unset. (`lib/bootstrap-lib.sh`)

### Changed

- **openSUSE is on the bootstrap driver — the `blib_main` row reads 4/9** (#986;
  dotgibson/dotfiles-openSUSE#186). The repo whose closing report exits 2 whenever an optional
  install did not complete now declares that contract (`BOOTSTRAP_STRICT_DEFAULT=1`,
  `BOOTSTRAP_FAIL_EXIT=2`, `--tolerate-failures` flipping the default off through
  `bootstrap_flag`) instead of wrapping the driver's report in a private one; its OS check,
  the `--only`/`--skip` exclusion and the links-only WSL note are `bootstrap_guard`, zypper
  provisioning is `bootstrap_provision` with the body unchanged, and the Leap capability
  re-link takes the pre-loader slot. 716 → 657 lines. (`scripts/audit/40-fleet-registers.sh`)

- **Fedora and Debian are on the bootstrap driver — the `blib_main` row reads 3/9** (#986;
  dotgibson/dotfiles-Fedora#181, dotgibson/dotfiles-Debian#78). The two the survey called the
  driver's shape verbatim: each keeps its OS guard and preflight as `bootstrap_guard`, its
  package phase as `bootstrap_provision` with the body unchanged, its dry-run preview as
  `bootstrap_check`, and its own flags through `bootstrap_flag`; Debian also uses the
  pre-loader slot for the distro tier's capability re-link and the closing hook for its
  shadowed-tools report — the two slots the survey said had to exist. Fedora's `make check`
  ran the vendored links gate through the driver on a Fedora box and a real `--dry-run`
  printed the 38-package plan and wrote nothing. Together with Defense that is 753 + 962 + 270
  → 660 + 876 + 205 lines. (`scripts/audit/40-fleet-registers.sh`)

- **Defense is the first repo on the bootstrap driver — the §5f ledger records it** (#986;
  dotgibson/dotfiles-Defense#292, after v7.4.0 vendored `blib_main` there). Its `bootstrap.sh`
  now declares what it is and hands over to the driver, so `blib_main` gets its first ledger
  entry and `blib_install_core_guard`, the row Defense had always been short on, is satisfied
  by the driver installing the guard on a fresh clone. The scanner credits a `blib_main` caller
  with the whole helper contract, so every other row it held stays `ok` with the names gone from
  the file. (`scripts/audit/40-fleet-registers.sh`)

## [v7.4.0] - 2026-09-13

### Fixed

- **`RELEASE-STRATEGY.md` promised a "predictable monthly rhythm" the tags have never
  shown.** The summary, the §2 cadence table and the whole _"Tagged releases (monthly +
  security)"_ subsection said Core is cut _"once a month on a fixed day"_ and argued why
  monthly beats weekly and quarterly. Measured from `v1.0.0` (2026-06-18) to `v7.3.0`
  (2026-09-09): **78** `vX.Y.Z` releases in 87 days, one every day or two, with **seven
  majors**, the last three within ten days of each other. `V8-PROPOSAL.md` §6 flagged the
  gap and offered the choice — move the claim to the practice, or declare the practice a
  deviation. The claim moved. The section is now _"Tagged releases (on demand)"_: cut when
  `[Unreleased]` holds something a host should receive and the audit is green, `X.0.0`
  when it holds a breaking bullet (which `tag-release.sh` enforces anyway), preferably
  after Monday's freshness PR has baked — a guideline, not a gate. It keeps the measured
  history as the evidence and says why the fan-out churn the monthly argument feared never
  arrived: `sync-fanout.yml` opens the nine PRs unattended and a host relinks only when a
  major says so, so a small release is a small sync, and releasing _more_ often is what
  keeps a sync boring. `monthly` appeared in no other document, so nothing else moved.
  The proposal's own numbers were wrong the way §2 of that document warns about — it
  said 84 tags and the last _four_ majors; the count included alias tags — and are
  corrected there in the same change. (`RELEASE-STRATEGY.md`, `V8-PROPOSAL.md`)

- **`lint-call.yml`'s owned-block remediation text pointed at the wrong file.** A failing
  caller was told the gh/uv/ty completions run from `core/zsh/45-plugins.zsh`; #579 moved
  them to `00-tools.zsh` (`_cache_completion`, generated into fpath before compinit), and
  `_core_owned_block_owner` already said so. The message now names `00-tools.zsh` for all
  four. (`.github/workflows/lint-call.yml`)

- **`RELEASE-RUNBOOK.md` told you to tag the new major alias at the merged tip; every other
  source says the release commit.** Four sites, one defect. §1.1 step 5's inline comment
  claimed `make publish` _"creates vX.Y.Z AT origin/main"_; the MAJOR bullet said the new
  alias is _"created fresh at the merged tip"_; the worked v4→v5 example handed you a
  copyable `git tag -fa v5 origin/main -m v5`; and `tag-release.sh --help` repeated
  _"moves the vN alias AT origin/main"_, with its own failure message naming origin/main for
  a tag it creates somewhere else.

  **The code has been right the whole time, and says why at length.**
  `scripts/tag-release.sh` resolves `RELEASE_SHA` by walking `origin/main` for the commit
  that SET `core.version` to this value — _"THE guard, and it must identify the RELEASE
  COMMIT — not merely today's tip"_ — because `core.version` does not change again until
  the next release, so _"origin/main carries this version"_ stays true for every commit that
  lands afterwards. Tag the tip and you sweep work still sitting under `[Unreleased]` into a
  release whose GitHub body `release.yml` then builds from the `[vX.Y.Z]` section, leaving
  those changes shipped and undescribed. `--publish` already prints
  `origin/main has advanced N commit(s) since the release — tagging the release commit, not
  the tip` when it happens.

  `RELEASE-STRATEGY.md` was already correct (`git tag -fa vN vN.0.0^{commit}`), which is what
  makes this the shape the runbook's own header warns about: _"When they disagree,
  `RELEASE-STRATEGY.md` wins; fix this"_ — and the one handing out commands was the wrong
  one. On a MAJOR the consequence is the sharp end: `vN+1` lands on later unrelated work
  while the immutable `vN.0.0` points at the release, two refs for one release disagreeing,
  and every caller pinned `@vN+1` follows the wrong one. `main` is 2 commits past `v7.3.0`
  as this lands, so the window is open now rather than hypothetical.

  The worked example also gains the `^{commit}` peel and the reason for it — the release
  tags are annotated, so an unpeeled name makes the alias a _nested_ tag instead of the
  direct-to-commit ref `make publish` creates.

  Found by inspecting `fix/runbook-major-alias-release-commit`, a branch pushed 2026-08-17
  that never opened a PR and was still correct a month later.

- **`PORTING-MATRIX.md` was blind to openSUSE Leap 16 in three places, from the
  `/os-package-availability` routine (dotfiles-openSUSE#178, #962).** Footnote ³³'s neovim
  table exempted openSUSE by name — _"its neovim row is not currently affected"_ — and Leap
  16.0 ships `neovim` **0.11.3-bp160.2.1**, below the 0.12 floor nvim-treesitter's `main`
  hard-requires, while Leap 16.1 (0.12.4) and Tumbleweed (0.12.5) clear it. That is the
  concurrently-supported-branches shape the footnote attributes to Alpine, so it now names
  **four** targets, carries the three openSUSE rows, and records the remedy
  dotfiles-openSUSE#181 shipped (`# min:0.12.0`, a warn-only `NEOVIM_FLOOR`, a floor gate in
  its package test). The openSUSE cell in the neovim row moved to `` `neovim` ≥ 0.12.0 `` on
  the same regen — derived from that `# min:`, not hand-typed.

  Footnote ³⁴'s generated jq table had one openSUSE Leap row, **15.x at 1.6**, probed through
  `repology:opensuse_leap_15_6` — a release EOL since 2026-04-30 and the only Leap Repology
  indexes at all, so `make update-fleet-versions` could never move it and the table was
  silent about both releases openSUSE users are on. `scripts/fleet-package-versions.tsv` now
  carries Leap 16.1 (1.8.2, at or above) and Leap 16.0 (1.7.1, below _by version_), read from
  `download.opensuse.org` with a `-` probe, so the weekly bot reports them as needing a
  human rather than re-stamping an EOL row. The _"do not build a guard on `jq --version`"_
  paragraph names openSUSE Leap as a second backport lane beside the Debian family: 16.0's
  `1.7.1-160000.4.1` is openSUSE-SU-2026:21318-1 (CVE-2026-49839), a security rebuild that
  did not bump the version.

  Footnote ²⁴'s _"every distro in the table above ships lnav"_ is softened — lnav is
  Tumbleweed-only on openSUSE, absent from Leap 16.0 and 16.1 — and its openSUSE row gains
  the `(Tumbleweed; **not** Leap 16.0/16.1)` hedge footnote ¹⁰ already uses for difftastic.
  Footnote prose and a data file, so nothing in the Tool column's marks moved.

### Added

- **`blib_main` — the bootstrap driver, and the per-repo hook `V8-PROPOSAL.md` §4.2(3)
  named** (#976). Every `bootstrap.sh` in the fleet hand-rolled the same skeleton around its
  genuinely OS-specific part: the flag loop, the `core/` guard, the two `source` lines,
  `blib_select`, the PATH prelude, the `blib_resolve_su` branch, the wiring sequence and the
  closing report — measured at ~1,290 of the fleet's 7,390 bootstrap lines, in nine copies
  that agree until they do not (Defense could not parse `--only zsh,git`; four repos rendered
  `--help` four different ways). The driver owns that skeleton once — `--links-only`,
  `--dry-run`/`-n`, `--strict`, `--only`/`--skip` in both spellings, one `--help` — and calls a
  small set of NAMED hooks the repo defines: `bootstrap_guard`, `bootstrap_check` (report-only,
  skipped under `--links-only`), `bootstrap_provision` (a full run only, never faked under
  `--dry-run`, under a resolved escalator and the sudo keepalive), `bootstrap_wire_pre_loader`
  and `_post_loader` (two slots, because Alpine's `~/.zshenv` must follow the managed `~/.zshrc`
  while a distro tier's capability re-link must precede it), `bootstrap_closing`,
  `bootstrap_flag` (a repo flag, with a return code for one that takes a value) and
  `bootstrap_usage`. Declarations carry the rest: `BOOTSTRAP_OS` / `BOOTSTRAP_ROLE` (which
  overlays to wire), `BOOTSTRAP_SU=lazy` (Offense resolves inside `--install`),
  `BOOTSTRAP_SU_PREFER=doas` (Alpine), `BOOTSTRAP_LOGIN_SHELL=0` with the new
  `blib_login_shell_hint` (the report-only guard Defense and Offense each carried),
  `BOOTSTRAP_STRICT_DEFAULT` and `BOOTSTRAP_FAIL_EXIT` (Arch's always-exit-1 and openSUSE's
  documented exit 2 survive adoption unchanged). Nothing new is linked onto a host and nothing
  a host reads changes meaning — the driver calls the same helpers in the same order the repos
  already call by hand, which is why §4.4 chose this over an overlay and why it ships as a
  minor. `scripts/test/37-bootstrap-driver.sh` drives it end to end against a fixture repo
  (hook order under each flag, dry-run inertness, the tally and `--strict`, the declared exit
  policy, selection reaching `blib_select`, a value-taking repo flag). §5f credits a
  `blib_main` caller with the whole helper contract and adds `blib_main` as a ratchet row.
  MacBook stays outside the driver by design: its `--json` / `--uninstall` / `--quiet` surface
  is a consumed contract, and the driver's job is to absorb the other eight. Defense is the
  pilot (dotgibson/dotfiles-Defense#292, after this ships and syncs). (`lib/bootstrap-lib.sh`,
  `scripts/audit/40-fleet-registers.sh`, `scripts/test/37-bootstrap-driver.sh`, `V8-PROPOSAL.md`)
- **Audit §5l: a vendored `scripts/*.sh` entry must have a consumer that actually RUNS it**
  (#975; `V8-PROPOSAL.md` §10 Q3). `core.vendor`'s own header calls its `scripts/` block "the
  five things an OS repo actually runs from core/", and §1e walks the closure from the
  `# entry` roots so a vendored script cannot reach an unvendored file — but nothing checked
  the other direction. `scripts/check-links.sh` showed the cost: vendored in #852 with its
  consumer named "as intent rather than as a file" (the four Makefiles that inlined the block
  would switch "on the next sync"), it then rode nine releases into nine repos with no caller,
  and no gate could say so. The four Makefiles have now switched (dotgibson/dotfiles-Fedora#179,
  dotgibson/dotfiles-Debian#76, dotgibson/dotfiles-Gentoo#185, dotgibson/dotfiles-openSUSE#184
  — Fedora's ran green for real: 25 links, 1 seeded), the entry names them as files, and the
  new gate reads each checked-out sibling's Makefile, pre-commit config, workflows, `test/`,
  `tests/` and top-level scripts — comment lines and prose excluded — through
  `_core_vendor_consumer_hits` in `scripts/lib/common.sh`, fixture-tested in both directions.
  It blocks only on a fully cloned fleet and records an environment skip otherwise, the same
  posture as §5f and §5g; the per-script consumer counts print either way. (`scripts/audit/40-fleet-registers.sh`,
  `scripts/lib/common.sh`, `scripts/test/90-policy-gates.sh`, `core.vendor`, `V8-PROPOSAL.md`)

- **`V8-PROPOSAL.md` — the design record for the next major.** Core is at `7.3.0` with an
  empty backlog, no open PRs, and a Breaking Backlog milestone holding zero issues, so a
  major had no content to find. Same situation `V5-PROPOSAL.md` was written into, and the
  same answer: write the content down where it can be argued with. The thesis is **the OS
  repo stops carrying code Core owns** — v5 made the OS layer declare, v6 made the vendored
  payload only Core, v7 deleted the last fallbacks, and what is left is the other
  direction: portable logic stranded OUTSIDE Core, hand-maintained N times, which no gate
  has ever been allowed to fail on.

  What earns the major is the one thing neither the roadmap nor `V5-PROPOSAL.md` names:
  three legs of `lint-call.yml` ship advisory with a promise to flip, two of them printing
  `This warning becomes a BLOCKING failure in the next Core release` to users since
  2026-08-21 and 2026-09-06 — and three releases have passed without flipping them. Not
  neglect. Callers pin `@v7`, a MOVING major tag, so a flip on a minor turns every OS repo
  red the moment `auto-tag` advances it, before a maintainer could act; `lint-call.yml:297`
  calls that _"red-on-arrival by construction"_. A MAJOR is the only mechanism the fleet
  owns that dissolves it: `RELEASE-RUNBOOK.md` §1.1 step 5 mints `v8` fresh and leaves `v7`
  **frozen**, so one simultaneous fleet-wide break becomes nine independent opt-ins, each
  repo adopting on the day it merges its own bump PR.

  **Two claims the release was expected to rest on did not survive contact, and the
  proposal records both rather than quietly correcting them.** The roadmap asserts that
  consolidating `bootstrap.sh` _"changes the symlink contract, so every host
  re-bootstraps"_; it does not — that contract IS `blib_link_core` / `blib_link_os_layer` /
  `blib_link_role_layer` (`lib/bootstrap-lib.sh:558,718,826`), which already live in Core
  and which every repo already calls. v5 earned its major there because #663 added a NEW
  overlay, and absent one this is a large refactor of OS-repo-owned code, which the bump
  table calls MINOR however many lines it touches. Whether the per-repo hook becomes an
  overlay is left OPEN, as §4.4, with the smaller claim recommended. The second: the
  `audit-core.sh` split was expected to change what a consumer receives in the #676 mould,
  and `scripts/audit-core.sh` is absent from `core.vendor` — it ships to nobody, so it
  rides along and earns nothing.

  Measurements the proposal is built on, all re-derived rather than inherited: §5f's
  ledger has **four helpers at 1/9**, every one adopted by `dotfiles-Gentoo` alone, and
  `dotfiles-MacBook` — the reference implementation — is absent from four of eight rows
  while being the size outlier at 1,604 lines against Arch's 418 (it was 1,505 when
  `V5-PROPOSAL.md` §11 deferred this; nothing was done and it grew). `audit-core.sh` is
  3,059 lines over 47 sections that run `1 1c 1d 1e 1b 1c …` — **`1c` is defined twice**,
  `1b` runs after `1e`, `5l` is deliberately skipped — which is verbatim the condition
  `test-core.sh`'s header cites for the #699 split, one file later; splitting it four ways
  costs **698 ms against the whole file's 2,405 ms** of ShellCheck on identical content.
  And `dotfiles-MacBook` calls no `lint-call.yml` at all, so the canary cannot canary the
  gates this release flips.

  Recorded as a proposal, not a plan: nothing here has shipped, and §10 carries the
  non-goals (the non-mutable host as the right NEXT major, the nvim split needing its own)
  plus the finding that the "one source, generated outward" milestone has already shipped
  as minors and should be closed rather than scheduled.

### Changed

- **Defense closes the last row — the four `bootstrap-lib` helpers are compliant fleet-wide,
  and #973 is done** (dotgibson/dotfiles-Defense#291). A report-only bootstrap that installs
  nothing and escalates nothing has no best-effort step of its own to ledger and nothing to
  resolve an escalator for, so `blib_note_fail` and `blib_resolve_su` are exempt for this repo
  with those reasons written into the §5f case — the same standard the day's other two
  exemption changes were held to (Offense lost one, MacBook gained one). It does adopt
  `blib_failures_report`: the scaffold it calls can still record a tpm-clone failure, and a
  closing "complete" over that was the exact silence the ledger exists to end; a new
  `--strict` there turns a non-empty tally into exit 1. The header's measured figures now
  read 9/9 compliant on all four rows, against 1/9 when the day started. (`scripts/audit/40-fleet-registers.sh`,
  `V8-PROPOSAL.md`)

- **MacBook adopted the ledger helpers and the `lint-call.yml` caller — the §5f rows read
  8/9, and the ratchet `V8-PROPOSAL.md` §4.2 named is done in a day** (#973;
  dotgibson/dotfiles-MacBook#247, #248). The proposal called MacBook's row the single
  highest-value one: the reference implementation carried a private `FAILURES`/`fail_note`/
  `print_ledger` that already half-bridged to the lib — resetting `BLIB_FAILED` before the
  wiring step and folding it back after — plus one bare `sudo tee`. `fail_note` is now a
  shim over `blib_note_fail`, the closing tally is `blib_failures_report`, the reset and
  fold are gone (the reset would have dropped a miss recorded before wiring), `warn_note`
  stays local because the lib has no warnings channel, and the one `tee` runs through
  `blib_resolve_su` / `blib_priv`. Its keepalive row is **exempt**, with the reason in the
  fragment: `os/macos.capabilities` declares nothing privileged and a refresher loop around
  one write behind an interactive confirm would be theatre — the opposite reason to the
  role-repo exemption Offense just lost. §10 Q4 is answered too: MacBook calls
  `lint-call.yml` (SHA-pinned like its other callers), so #961's "eight is the whole
  denominator" is nine; its four repo-owned zsh files measured clean on all three legs
  first. Seven repos adopted in one day against a tracker that had read 1/9 for a week
  after #867 closed; Defense, which installs nothing, is the one gap left on three rows.
  (`scripts/audit/40-fleet-registers.sh`, `V8-PROPOSAL.md`)

- **Offense adopted the four `bootstrap-lib` helpers — the §5f rows read 7/9, and its
  keepalive exemption is gone** (#973; dotgibson/dotfiles-Offense#326). The role repo had been
  exempt from `blib_sudo_keepalive_start` on the reasoning that a role layer installs no long
  package sets. Its own `--install` says otherwise: the Kali route runs the whole offensive apt
  list — "go get coffee", the comment reads — behind a one-shot `sudo -v` that primed once and
  expired mid-run, the exact hang the helper exists for. That is the second time the
  "installs no packages" claim was wrong for this repo (#748 was the first, for
  `blib_user_bindirs_on_path`), so the exemption is retired and the rationale comment now says
  why an exemption is a claim the repo's own file can contradict. Defense keeps both of its
  exemptions: it installs nothing and probes nothing. The ledger lines in
  `scripts/audit/40-fleet-registers.sh` add `dotfiles-Offense`, the header figures move to 7/9,
  and MacBook is the one repo left. (`scripts/audit/40-fleet-registers.sh`, `V8-PROPOSAL.md`)

- **Arch adopted the four `bootstrap-lib` helpers — the §5f rows read 6/9** (#973;
  dotgibson/dotfiles-Arch#171). The repo with no root check at all: it leaned on the lib's
  default of `sudo` through `_blib_priv`, an underscore-private symbol, which is the shape the
  fleet's `HAVE_*` and owned-block legs exist to catch in zsh and nothing caught in bash.
  `blib_resolve_su` now pins the escalator up front, the five calls go through the lib's public
  `blib_priv`, the keepalive pair spans the go builds, and `blib_note_fail` records the
  per-package misses, the go installs and the Flathub remote where `PROVISION_FAILED` held one
  kind of miss and `|| true` swallowed the rest. Arch's exit-1-on-any-miss contract is kept
  around `blib_failures_report`. The ledger lines in `scripts/audit/40-fleet-registers.sh` add
  `dotfiles-Arch` and the header figures move to 6/9; the two repos left are Offense (exempt
  from the keepalive) and MacBook. (`scripts/audit/40-fleet-registers.sh`, `V8-PROPOSAL.md`)

- **Alpine adopted the four `bootstrap-lib` helpers — the §5f rows read 5/9** (#973;
  dotgibson/dotfiles-Alpine#191). The repo #879 was written for: its `bootstrap.sh` had kept a
  hand-rolled doas-first probe with a comment explaining that `blib_resolve_su` resolved sudo
  before doas and naming `--prefer` as the unblocker, and this is the adoption that comment
  promised. It is also the first repo in the ratchet that had **no failure ledger at all** —
  every best-effort install was `|| true` or an indented `echo`, and the script exited 0
  regardless — so `blib_note_fail` now records the apk per-package misses, the three
  upstream installers, seven musl cargo builds, the go installs and `op`, `blib_failures_report`
  prints the tally, and a new `--strict` turns it into exit 1 like Debian, Fedora and Gentoo.
  Its `test/check-root-probe.sh` gate, which extracted the root condition from `bootstrap.sh`
  and evaluated it with `id` stubbed, now extracts it from the vendored lib's
  `blib_resolve_su` instead — a Core sync that changed the rule changes what it evaluates —
  and pins that `bootstrap.sh` delegates doas-first. The ledger lines in
  `scripts/audit/40-fleet-registers.sh` add `dotfiles-Alpine` and the header figures move to
  5/9. (`scripts/audit/40-fleet-registers.sh`, `V8-PROPOSAL.md`)

- **openSUSE adopted the four `bootstrap-lib` helpers — the §5f rows read 4/9** (#973;
  dotgibson/dotfiles-openSUSE#183). The third repo in the ratchet, and the first whose ledger
  had its own contract to keep: `_report_failures` exits **2** (documented in `--help` and the
  README as "completed but optional tools failed") and honours `--tolerate-failures`, so it
  now _wraps_ `blib_failures_report` instead of being replaced by it — the lib's return
  decides whether there is anything to report, the repo decides what that costs. Its old
  `_priv_preflight` was the fleet's clearest case for `blib_sudo_keepalive_start`: a one-shot
  `sudo -v 2>/dev/null || true` that primed the cache once and let it expire mid-cargo-build,
  the invisible-prompt hang the helper exists to prevent. `_note_fail` was silent until the
  closing tally; as a shim over `blib_note_fail` it now warns at the moment of the miss as
  well. The ledger lines in `scripts/audit/40-fleet-registers.sh` add `dotfiles-openSUSE` and
  the header figures move to 4/9. (`scripts/audit/40-fleet-registers.sh`, `V8-PROPOSAL.md`)

- **Debian and Fedora adopted the four `bootstrap-lib` helpers the §5f ledger had reported at
  1/9 since #748** (#867, #973; dotgibson/dotfiles-Debian#75, dotgibson/dotfiles-Fedora#178).
  #867 closed as completed on 2026-09-06 when #879 (`blib_resolve_su --prefer`) merged — but
  #879 was the unblocker, not the adoption, and measured on every sibling's `origin/main` a
  week later all four rows still read Gentoo only. `V8-PROPOSAL.md` §4.2(1) names the ratchet
  as "the whole of the change that is ready"; the two lowest-friction repos took it first: both
  carried the same hand-rolled root/sudo/doas probe, a `note_fail`/`FAILED_STEPS` ledger and a
  private sudo-keepalive loop with its own `EXIT` trap. Each `bootstrap.sh` now calls
  `blib_resolve_su` (`--require` only on the provisioning path, so `--dry-run` needs no
  escalator), `blib_sudo_keepalive_start`/`_stop` with `provision()` owning the trap, a
  one-line `note_fail() { blib_note_fail "$@"; }` shim over the untouched call sites, and
  `blib_failures_report` for the closing tally — which also surfaces the failures the shared
  lib records _itself_ (the tpm clone, `blib_install_system_file`) that both scripts used to
  drop. Output and `--strict` semantics are unchanged. The four `_ha_ledger` lines in
  §5f (`scripts/audit/40-fleet-registers.sh` since #970) now read
  `dotfiles-Debian dotfiles-Fedora dotfiles-Gentoo` and the header's measured figures say 3/9; landing order was sibling-first, ledger-second, because
  `_core_helper_verdict` fails `regressed` the other way round and `sync-fanout.yml` is where
  §5f meets real siblings. #973 tracks the remaining five repos with each one's measured
  friction (openSUSE exits 2, Alpine needs `--prefer doas`, Arch calls the underscore-private
  `_blib_priv`, Offense hardcodes `sudo`, MacBook has a `warn_note` channel and exits 3); #975
  (`check-links.sh` vendored with zero callers across all nine repos, §10 Q3) and #976 (the
  per-repo hook, §4.2(3)) carry the rest of what the proposal still owed, none of which was
  tracked anywhere — the split (§5) was filed as #974 the same afternoon #970 shipped it, and
  closed as superseded. (`scripts/audit/40-fleet-registers.sh`, `V8-PROPOSAL.md`)
- **The audit is 48 named sections in `scripts/audit/`, not one 3,064-line file (#970).** The
  gate got the #699 treatment, for the reasons #699 gave. ShellCheck's cost is superlinear
  in file length: linting this one file cost **2.50 s of CPU / 3.1–3.4 s wall** on every CI
  leg for any PR touching any shell file; the dispatcher plus sixteen fragments, linted the
  way §5 lints them — one process per file — cost **1.47 s / 1.65 s**, the same lines and
  the same rule set. About 2×, and stated as measured rather than as the 3.4× the proposal
  estimated from four equal parts without process startup. The sections now live in
  **`scripts/audit/NN-name.sh`**, one numbered fragment per subject, and `audit-core.sh` is
  a 579-line dispatcher that globs them in `NN` order and **sources** them into its own
  shell — one set of PASS/SKIP/FAIL counters, one summary, one exit code, one EXIT trap.
  `--quiet`, `--json`, `--scope`, `--changed`, `--strict`, `--require-siblings`, the exit
  codes, the `audit-core` pre-commit hook, `make audit` and every script that calls the
  path (`sync-core.sh`, `tag-release.sh`, `release.sh`, `setup.sh`) are untouched.

  **A move, not a rewrite.** The fragments rejoin to the old file's lines 399–2912 **byte
  for byte** — the whole cut is two hunks, the renamed banner and one case arm — and the
  251 pass/skip/fail label strings come back identical in text and order, with only the
  shape gate's seventeen added at the head. The comments travel with their sections: the
  file was 48% comment and that prose carries the issue numbers, the measurements and the
  "why it blocks vs reports" policy that exists nowhere else, so none of it was summarised
  away. Section 10 — the wait on the behavioral suite the dispatcher backgrounds at the
  top — stays in the dispatcher, because it is the collect half of that launch and the
  EXIT trap that reaps it, and because "last" has to be structural rather than a matter of
  `NN`.

  **The `§`-ids are the stable part and did not move.** The proposal said the `NN-` prefix
  would _replace_ the letters; it carries run order instead, and `§5c` is still `§5c`.
  Some 330 prose references in 67 files cite gates by id — `CLAUDE.md`, `CONTRIBUTING.md`,
  `VENDORING.md`, `PORTABILITY.md`, `lint-call.yml`, `common.sh`, the doc-audit routine —
  and two of those files are vendored to nine repos (`core.vendor`'s comments and the
  generated `CHANGELOG.recent.md` header), so renaming would have been a fleet-wide churn
  for no gate value. The ids had drifted because letters are addition order within a
  family and were never meant to sort: `1b` ran fifth, `5k` between `5e` and `5f`, `9c`
  before `9b`, and the file's own header indexed 23 of the 48. Filenames fix the ordering
  by construction. **One id had to change:** `1c` named two unrelated gates — the
  `core.vendor` existence check (#676) and the unreferenced-`.claude/`-files scanner (#700,
  #905) — and the second is now **`§1f`**, the next free letter in its family. The shipped
  release notes for #700 and #905 still say `§1c`; they are history and were left alone,
  which is why this sentence exists.

  **`scripts/audit/05-shape.sh` keeps it from recurring.** It runs first and fails the run
  if any two fragments share a banner id, if a `*.sh` lands there without the `NN-` prefix
  (the glob would skip it in silence while the audit reported OK), if a fragment is
  executable, untracked, or carries no section banner at all. The empty-glob refusal —
  `exit 2` rather than an `audit OK` over zero gates — is **driven** rather than believed,
  from the new `scripts/test/23-audit-shape.sh`, because the audit has no sandbox of its
  own to stage a tree in and a fragment must never install a second EXIT trap. That test
  also asserts the suite's own view of the audit resolved: `scripts/test-core.sh` now
  assembles `_audit_src` — the dispatcher plus every fragment — once, and the fifteen
  static assertions that used to grep one file (`36-bootstrap-lib.sh`, `20-scanners.sh`,
  `21-guards.sh`, `42-gen-hero-tape.sh`, `56-fleet-vocabulary.sh`,
  `58-fleet-release-triggers.sh`, `90-policy-gates.sh`) grep that set through
  `_audit_grep` / `_audit_cat` / `_audit_frag`. Widening them is not cosmetic: the
  `_tool_skips` binding's sharpest assertion is a must-NOT-match, and a narrow file list
  passes it by looking away. Three of those tests needed design rather than a rename. The
  `--json` guard in `36-bootstrap-lib.sh` scans a **line range** between the `5f.` and `5i.`
  banners, so §5f–§5i are kept contiguous in `40-fleet-registers.sh` and the guard now
  fails, naming both files, if they ever separate. `22-ci-classify.sh`'s enumeration
  tripwire held `audit-core.sh:11:5` exactly; it now holds the dispatcher at `0:1` and the
  fragments as a **globbed sum** of `11:4` — a per-fragment table would be a second
  registry that never counts a new fragment and reds on a pure move, while a sum keeps the
  exactness the rule defends and is invariant to regrouping. And `90-policy-gates.sh`'s
  gitleaks self-check, which looped over a hand-named file list, would have gone green
  over files that no longer call gitleaks; it sweeps the audit's source set and now also
  asserts the set _contains_ an invocation.

  §2 learns that `scripts/audit/*.sh` are sourced libraries (`100644`), the same arm
  `scripts/test/*.sh` got in #699. `scripts/` was already a `META_PREFIXES` entry, so the
  new directory needed no allowlist edit; `META_ALLOWLIST` itself stays in the dispatcher
  because five citations, two in vendored files, name it there. `scripts/lib/common.sh` did
  not move — it is in `core.vendor` and `dotfiles-MacBook` sources it directly. Nothing
  outside this repo changes: `audit-core.sh` is in neither `core.manifest` nor
  `core.vendor` and ships to no machine, which is why this is a minor and why
  `V8-PROPOSAL.md` §5 carries a status note rather than a breaking bullet. Four stale
  references found on the way are fixed in the same change: `CONTRIBUTING.md` cited
  `audit-core.sh:583` for a sentence at `:907`, `gen-theme.sh` cited `audit-core.sh:80`
  for a note at `:101`, the audit's own note cited "line 48" for a `cd` on line 74, and
  `.gitattributes` credited the changelog-digest gate to `§9c` (it is `§9e`).
  (`scripts/audit-core.sh`, `scripts/audit/`, `scripts/test-core.sh`, `scripts/test/`,
  `scripts/lib/common.sh`, `CLAUDE.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`,
  `V8-PROPOSAL.md`, `.gitattributes`, `scripts/gen-theme.sh`)

- **`V8-PROPOSAL.md` is decided, and no major comes out of it.** The document was written
  two days ago as the content of a major that had none to find, resting on three changes.
  Change 1 — the three advisory lint legs flip — shipped as minors in #960 and #961 once
  the fleet measured clean, which the proposal's own §3 status note already recorded.
  That left one open decision carrying the whole bump class: §4.4, whether the
  `bootstrap.sh` consolidation's per-repo hook becomes a **declared overlay** that
  `blib_link_os_layer` symlinks into `$ZDOTDIR` (MAJOR — every host relinks) or stays a
  **repo-internal function** Core's driver calls (MINOR — nothing on a host changes
  meaning). **Decided: the hook.** No consumer for a second overlay emerged; nothing but
  `bootstrap.sh` reads provisioning facts, and a symlink only its author reads is a file
  in a different directory, not a contract. If one ever does, extending `os.capabilities`
  — already KEY=value, read-never-sourced, linked and validated — is cheaper than a second
  overlay. The symlink contract itself is `blib_link_core` / `blib_link_os_layer` /
  `blib_link_role_layer`, already in Core and already called by every repo; consolidation
  moves provisioning, which no host sees — the proposal's §2 had already shown that the
  roadmap's _"changes the symlink contract"_ claim did not follow.

  So the status header goes from _PROPOSED — awaiting a verdict_ to _DECIDED — no major
  comes out of this proposal_. No section writes a breaking bullet, `tag-release.sh` never
  mints a `v8` alias from this content, and what remains — the §4.2 ratchet of four
  helpers still at 1/9 (re-measured 2026-09-13: unchanged; MacBook still 1,604 lines with
  19 `fail_note`/`print_ledger` references; openSUSE grew 667 → 716; Debian, omitted from
  the original table, is 1,003), the §5 audit split (now 3,064 lines and 49 banners, `1c`
  still defined twice), and §10 question 3 — ships as minors needing no coordinated
  event. The next major's content is the one §10 already names: the non-mutable host.
  §6's five ride-alongs each carry their outcome (three landed within a day of being
  written down, in #957 and #960; two land here), §7–§9's rollout costs are kept for
  whichever major does come, §8's clean-up step is marked already done fleet-wide, and a
  fourth open question is added — `dotfiles-MacBook` adopting the `lint-call.yml` caller,
  no longer a canary problem but still the only way its repo-owned zsh gets the same three
  checks the other eight repos get.

  `V5-PROPOSAL.md` closes in the same pass. Its header still said #690 and #694 were
  _"still open"_; both landed in `v7.0.0` (`PORTABILITY.md` §5 is the `HAVE_*` surface
  #694 declared), so it is now _SHIPPED — a closed record_. Its §10 question 1 —
  _`CHANGELOG.md`: dropped or promoted?_ — is struck as **promoted**: #680 shipped
  `core whatsnew`, `CHANGELOG.recent.md` is in `core.vendor` as its backing store, and
  the full file stays repo-meta. Its question 4, the `core.vendor` consumer list, is
  marked carried forward to the v8 record, where it is still open. Two proposals, both
  now records; the next one starts from a roadmap theme, not from an empty backlog.
  (`V8-PROPOSAL.md`, `V5-PROPOSAL.md`)

- **`test-core.sh`'s owned-block fleet sweep reds a dirty sibling instead of skipping it,
  and reads the population the lint leg reads (#966).** It had skipped as _"fan-out
  pending"_ since #449 — right while the fan-out was pending, and a coverage-shaped silence
  once #961 flipped `lint-call.yml`'s leg to blocking. The sweep now enumerates
  `git ls-files '*.zsh' zsh/zshenv zsh/zshrc zsh/zprofile ':!:core/**'` per sibling instead
  of globbing `os/*.zsh` — the set the fleet is actually gated on, which the old glob
  undercounted: **13** repo-owned zsh files across the nine siblings, not 9;
  `dotfiles-Alpine`'s `zsh/zshenv.zsh`, the Defense/Offense role files and
  `dotfiles-MacBook`'s three entry files were invisible — and the pass line counts files, so
  a one-file sweep of a two-file repo shows. A red names the repo, lists every hit as
  `repo/file:line:rule` under the ✗, and says to pull first: a clone behind its fan-out PR
  is indistinguishable from a regression until it is pulled, and the verdict is red either
  way. A sibling that is a directory but not a clone, or absent, is still not-checked-out;
  a box without `git` skips by name; and CI — which checks Core out alone — still skips.

  The first run found one. `dotfiles-MacBook` is in `os-repos.txt`, so this sweep reads
  it, but it calls no `lint-call.yml`, so #961's _all eight callers clean_ never measured
  it: `os/macos.zsh` still carried the direnv/gh/uv/ty block, both arms, **8 hits** — every
  one of which Core `v7.3.0`, the tag MacBook vendors, already provides from
  `zsh/00-tools.zsh`. dotfiles-MacBook#244 deleted it before this landed, so the flip reds
  nobody. (`scripts/test/20-scanners.sh`, #966)

- **nvim plugin pins move forward for six plugins.** `crates.nvim`, `friendly-snippets`,
  `nvim-dap`, `nvim-lspconfig`, `nvim-treesitter` and `schemastore.nvim` advance to upstream
  HEAD — the set a 2026-09-12 re-run of the fleet health board's signals (#794) found stale,
  three days after #949 rolled the previous one. The other three signals were green on the
  same run: every repo, Windows included, on Core `v7.3.0`; all nine vendored `core/` trees
  pristine; all eight zsh plugin pins current.

  Every new SHA is a strict fast-forward of the one it replaces (`status=ahead`,
  `behind_by=0` in all six), and each range was read before promotion:

  - **`crates.nvim`** `b8281be` → `7039bc1`, 1 commit: a CI workflow tweak. No Lua touched.
  - **`friendly-snippets`** `6290e13` → `b4d01b0`, 3 commits: C# MSTest snippets and a
    snippet-definition validator under `debug/`. Core loads it only as blink.cmp's snippet
    source.
  - **`nvim-dap`** `c9a0738` → `cfa2d58`, 2 commits: child-session lookup when handling
    source buffers, and a `winfixbuf` guard when `switchbuf` contains `uselast`. Internal to
    `_cmds.lua`/`session.lua`; every entry point Core binds (`continue`, `step_*`,
    `toggle_breakpoint`, `set_breakpoint`, `run_last`, `terminate`, `repl.toggle`/`close`,
    `ui.widgets`) keeps its signature.
  - **`nvim-lspconfig`** `84b6b6c` → `ac9d2f7`, 3 commits: a new `jetls` server config and
    its generated docs. Core does not configure it.
  - **`nvim-treesitter`** `5cb0114` → `9a168f6`, 3 commits: the `kdl` parser and queries
    updated (marked `feat!` upstream — a query rewrite for that one language), query
    maintainers dropped from `parsers.lua`, and a parser-revision bot bump. Core's
    `ensure_installed` does not include `kdl`, and Core reads nothing from the parser
    metadata table; `setup()` and `get_installed()`, the two calls it makes, live in files the
    range does not touch.
  - **`schemastore.nvim`** `10c76a6` → `05e938c`, 4 commits: catalog refreshes, data only.

  Nothing renames or removes an API Core calls. (`nvim/lazy-lock.json`, #794)

- **Two of `lint-call.yml`'s three advisory legs now block, and the third cannot yet — the
  difference is measured rather than assumed.** The undeclared-`HAVE_*`-reads leg (#892) and
  the missing-`os.capabilities` leg (#663/#667) shipped warning-only because callers pin
  `@vN`, a MOVING tag: a leg that lands blocking is red-on-arrival for every repo the moment
  `auto-tag` advances the alias, before a maintainer could act. Both flips were gated on the
  fleet being clean, and both fleets are.

  All **eight** `lint-call.yml` callers were scanned with the legs' own helpers rather than
  by eye. `HAVE_*`: the only flag any repo reads is `HAVE_ATUIN`, which is the single row
  `zsh/have-api.txt` declares — **0 of 8** would fail. `os.capabilities`: every caller with
  an `os/` band carries a declaration, and the two carrying none (`dotfiles-Defense`,
  `dotfiles-Offense`) have no `os/` band either, which the leg's `[ ! -d os ]` arm already
  exempts — **0 of 8** would fail. `dotfiles-Debian` was measured through the GitHub API
  rather than skipped for not being checked out locally; a partial sweep omits exactly the
  case that would have made this wrong.

  **The owned-block leg stays advisory, and the measurement is why.** It is the one that is
  genuinely red-on-arrival: `_core_owned_block_hits` finds **6 of 8** callers still
  hand-rolling the WSL predicate Core took over in #449 — `dotfiles-Alpine`, `-Arch`,
  `-Debian`, `-Fedora`, `-Gentoo` and `-openSUSE` each carry a local `_IS_WSL` plus the
  `/proc/version` read that `core/zsh/00-tools.zsh :: _core_is_wsl` already provides. Its
  stated precondition — _"once fleet-drift shows all nine clean"_ — is unmet, so flipping it
  would red six repos on the next alias move. Six OS-repo PRs deleting the duplicate are the
  work that unblocks it, not a change here.

  **This narrows `V8-PROPOSAL.md`'s argument, and the correction belongs on the record.**
  That document reasons that three advisory legs each need a MAJOR, because a frozen
  outgoing alias is the only mechanism that turns one simultaneous fleet-wide break into
  nine independent opt-ins. That holds for the owned-block leg and for it alone: the other
  two break nobody today, so they need no major and take none. The proposal's mechanism is
  right; its count was three and is one.

  The `os.capabilities` warning text expired too and is corrected in the same change: it
  said Core _"is running its built-in fallback rows here"_. Since #763 there are none — an
  undeclared box does not get a quiet default, `up` refuses and names `--links-only` — so an
  absent declaration is a hard break rather than a degradation. The markdown leg's own
  comment still read _"ADVISORY IN THIS RELEASE, BLOCKING IN THE NEXT"_ having blocked since
  #592; its measurement is kept but relabelled as the pre-flip state it describes.

- **`lint-call.yml`'s last advisory leg blocks: the Core-owned-block scan now fails a caller
  that re-implements a block Core owns (#961).** #960 left it warning because its own
  measurement found **6 of 8** callers still hand-rolling the WSL predicate Core took over
  in #449. Those six repo PRs landed 2026-09-12 (Alpine#185, Arch#168, Debian#71, Fedora#171,
  Gentoo#177, openSUSE#179), and the flip was gated on a re-measurement rather than on the
  issue states: all **eight** callers — nine repo-owned zsh files, `dotfiles-Alpine`'s two
  and one each elsewhere — scanned with `_core_owned_block_hits` through the GitHub API,
  **0 hits, 0 download failures**. `dotfiles-MacBook` and `-Windows` call no `lint-call.yml`,
  so eight is the whole denominator.

  Two corrections to the sweep #961 was filed from. It called `dotfiles-Gentoo`'s predicate
  dead code; it gated `open`/`xdg-open`/`cdwin` exactly as Debian's did, so the fix there
  was a swap to `_core_is_wsl`, not a deletion. And it undercounted: it printed two hits per
  file, the WSL lines filled both, and `dotfiles-Fedora`'s direnv/gh/uv/ty init block — the
  other half of #449 — went unlisted until Fedora#176 removed it (closed 2026-09-13).

  Not a MAJOR, for the reason #960 gave: no caller is in the failing state, so nothing a
  consumer relies on changes meaning, and `tag-release.sh` would force `X.0.0` on a
  breaking-change bullet — the wrong number for a gate that reds nobody. `V8-PROPOSAL.md`'s
  count of advisory legs needing the frozen-alias mechanism went three → one in #960 and is
  now **zero**; §3 carries a status note and Change 1 drops out of the v8 case. Stale prose
  fixed alongside: `PORTABILITY.md` §5 still said the caller-side `HAVE_*` leg _"does not
  yet run"_ (running since #892, blocking since #960); the `scripts/test/20-scanners.sh`
  comment and the Makefile header `new-os-repo.sh` scaffolds both still called this leg
  advisory; and the `os.capabilities` step kept an _"ADVISORY, not blocking"_ comment above
  the `exit 1` #960 gave it.

- **The README hero ceiling drops from 2 MiB to 1.5 MiB (#698).** §9k's number was sized in
  #698 around a ~1.8 MB clip that no longer exists — the shortened template plus the
  gifsicle pass took the hero to about half of it. A ceiling at twice the size of the thing
  it guards is not a gate, it is a formality, and `assets/hero-repos.txt` now registers
  **ten** heroes rather than one, which is the difference between a preference and a policy.

  **The binding case is not this repo**, which is the correction that matters here.
  Measured across all ten registered heroes: Debian 0.80 · Fedora 0.89 · Gentoo 0.94 ·
  Arch 0.97 · Alpine 1.01 · core 1.02 · Defense 1.06 · openSUSE 1.12 · MacBook 1.18 ·
  **Offense 1.34** MiB. Offense sets the floor under any tighter number — its tour ends on
  the provenance panel with a role layer stacked over an OS layer, so there are more
  distinct frames to redraw — and 1.5 MiB leaves it ~161 KiB. Core's own gif, at 1.02 MiB,
  would have supported a far tighter ceiling and is the wrong thing to size against.

  **Two of the ten skip on a local run, and one of them is the binding case.**
  `--check-size --fleet` reports `dotfiles-Debian` and `dotfiles-Offense` as not checked
  out (Offense's clone carries its pre-rename directory name), so a green local sweep
  weighs eight gifs and silently omits the tightest. Both were measured out-of-band against
  the GitHub API before this number was chosen rather than inferred from the eight that did
  run — an environment SKIP that reads as coverage is exactly what the fleet gates warn
  about elsewhere.

  1 MiB was considered and rejected on cost, and the reasoning is recorded beside the
  constant: the two free levers are spent (`Set Framerate 24` against VHS's default 50, and
  gifsicle `--colors 64`), and everything left degrades what a reader sees — narrowing
  Width wraps `glog` subjects past 90 characters, shortening Height truncates the `bat` and
  `core status` panels, and dropping a tour step removes a marquee moment. It would also
  put Offense under the line by shaving exactly what its gif exists to show.

  Found on `gerrrt/hero-ceiling-1-5-mib`, pushed 2026-09-04 and never opened as a PR. Its
  number was right and its arithmetic was not: it cited a 1.31 MiB re-render and ~200 KB of
  headroom, both measured against Core's gif five days before the nine sibling heroes were
  filmed (#948). Re-authored against what the fleet actually weighs today.

- **`--scope none` gates the cross-cutting tooling fragments, and is 86% faster (#467).**
  The scope vocabulary has three axes — `shell`, `nvim`, `atuin` — and the bash-tooling
  fragments belong to none of them, so they were gated by **nothing**: five of them
  (`56-fleet-vocabulary` 141.8s, `40-gen-theme-aliases` 75.0s, `41-gen-matrix-parity` 38.0s,
  `35-new-os-repo` 35.5s, `32-sync-core` 21.5s) were **311.9s of the 375.3s** that the
  scope documented as _"the cheapest"_ actually cost. They now honour `SCOPE_TOOLING`.

  **It is DERIVED from the three axes, deliberately not a fourth token** — on for ANY area,
  off only for the explicit minimal run. A token would have to be threaded through
  `ci-classify.sh`'s output, whose exact three-line format `scripts/test/22-ci-classify.sh`
  pins, and through three separate scope assemblies in `ci.yml`: a five-file coordinated
  change whose failure mode is a silently narrowed CI run. Derived, the two fail-safe arms
  carry it for free — an unknown token and an empty scope already force all three axes on,
  so they force this on too.

  **CI coverage does not move**, and that is the property the rule was chosen for:
  `ci-classify.sh`'s `scripts/*` arm sets `shell=true`, so every diff that can reach this
  tooling still selects an area and still runs it. The one case that changes is a docs-only
  diff, where the classifier yields no area and `ci.yml` passes `none` — there the five
  fragments now skip. What they test is generator _behaviour_; the generators' **output**
  is held by `audit-core.sh` §9d/§9g/§9h/§9i/§9j, static sections outside the scope system
  entirely, so a markdown edit is still covered by the gates that can actually see it.

  Measured, same box: the full suite **1,125s → 856s** and `--scope none` **733s → 155s**.
  Against `v7.3.0` before any of this work, that is **1,536s → 856s (−44%)** and
  **1,119s → 155s (−86%)**. The remaining real self-run in
  `scripts/test/52-atuin-autostart.sh` invokes `--scope none`, so it got cheap as a side
  effect — which was the point.

- **`_set_scope` has a test now, and it is the one function whose bugs were invisible by
  construction.** Nothing exercised the scope parser, and getting it wrong makes the suite
  _smaller_ — a smaller suite still reports green, which is the exact failure the dispatcher
  refuses an empty glob to prevent. `scripts/test/06-scope-contract.sh` pins the truth table
  for all four flags, both fail-safe arms (widen to everything **and** say so on stderr, so a
  typo'd scope is not silently honoured), that `none` beside a real area does not cancel it
  — CI builds its list by appending — and that the cases, which run in subshells, did not
  re-scope the live run they are part of.

  `scripts/lib/common.sh` is vendored (`core.vendor`), so this reaches the nine repos on the
  next sync. Purely additive: one new variable, no change to what any existing caller reads.

- **The `--json` contract fixture ran the whole suite twice; it now runs it once, and the
  suite is 27% faster (#467).** `scripts/test/52-atuin-autostart.sh` proves two things
  about `--json`: that stdout carries exactly one parseable object, and that the mode does
  not change the VERDICT (#511). Each was checked by re-running the real suite at
  `--scope none`, on the belief written into the fixture that this is _"the cheapest scope,
  a few seconds"_. It is not, and the arithmetic is the tell: measured at `7.3.0` on macOS,
  a `--scope none` run is **1,119s** of which **743.7s is this one fragment** — because a
  nested run IS a base run (375.3s base, 371.9s per nested run). The fixture **tripled**
  every `--scope none` invocation, `audit-core.sh`'s scoped runs included, and made one
  fragment **61.5% of a 1,536s full run**.

  The verdict property is about the MODE, not about the real fixtures, so it no longer
  needs the real suite: it now runs against a staged throwaway suite of one fragment —
  `05-suite-shape.sh`'s pattern, two fragments up — in ~60ms. **The first run stays real,
  deliberately.** Failure shape 1 in that section's own header, _"a fixture leaking to
  STDOUT"_ (last seen as a no-op `git commit` printing "nothing to commit"), is only
  observable when the actual fixtures run; staging both would have left the gate asserting
  against its own fixture and deleted the coverage it exists for.

  It also checks MORE than before. A staged suite can be made to fail on purpose, so
  agreement is now asserted for **both** verdicts; the old comparison only ever exercised
  `ok`, because the real suite is green whenever anyone runs it — the `failed` half of a
  gate about verdicts had never once been executed.

  Measured, same box, before → after: the full suite **1,536s → 1,125s** and `--scope none`
  **1,119s → 733s**, both green, with one assertion more than before.

  **This also corrects the record on #467**, closed `not_planned` as _"`test-core.sh` hangs
  on macOS"_. It does not hang — it completes, `pass 2074 fail 0`. Both nested runs
  captured their output, so the parent printed nothing for 15.8 minutes, and that silence
  is what every report of a hang has been looking at. What remains open there is the other
  half: `--scope none` gates `shell`/`nvim`/`atuin` and nothing else, so five un-gated
  fragments (`56-fleet-vocabulary` 141.8s, `40-gen-theme-aliases` 75.0s,
  `41-gen-matrix-parity` 38.0s, `35-new-os-repo` 35.5s, `32-sync-core` 21.5s) are **83%** of
  its 375.3s base. Making the cheapest scope actually cheap would make the one remaining
  real self-run nearly free as a side effect.

## [v7.3.0] - 2026-09-09

### Added

- **The vocabulary register reads `dotfiles-Windows` — the same seven verbs, spelled
  `.\task.ps1 <verb>` (#855, a #691 follow-up).** #691's promise is that a contributor
  moving between repos re-learns nothing, and the one repo still outside it was the
  fleet's most-tested: no Makefile, no runner, bare scripts, in exactly the place where
  "reproduce the CI gate locally" has the most to offer. Windows is deliberately absent
  from `scripts/os-repos.txt` (that list drives the fan-out, and Windows vendors no
  `core/`), so the register now names it the way `fleet-drift.sh` does — **an outlier row
  read by name**, last in the table, with `task.ps1` beside the repo so the `make <verb>`
  headers stay the contract's names — and `os-repos.txt` stays Windows-free, which the
  suite pins. `make` is not a given on a Windows host and `just` would be a new dependency,
  so the shim is PowerShell: a dispatcher over the repo's existing entry points, landing in
  `dotfiles-Windows` as `task.ps1`.
  The read is **static**, like the Makefile read: a verb is a quoted key of `Get-TaskVerbs`
  alone at the start of its line — a key on a comment line or inside a string declares
  nothing — and `test` is credited only when its entry names the suite runner under the
  populated `tests/` by path (either separator), else **no-op**; a Windows clone without the
  shim renders **no task.ps1** across its row, the way a fleet repo without a Makefile
  renders **no Makefile**. The test-floor column is the same reader as everywhere else,
  which already credited a `shell: pwsh` step running `./tests/Invoke-Tests.ps1`. The
  per-verb cell logic that was inline in the fleet loop is one function shared by both row
  kinds, so a label cannot drift between them.

- **The CI floor now bans blanket `permissions:` grants — `banned_permission_values`.** Rule 5
  requires every workflow to declare a `permissions:` block but never looked at its value, so
  `permissions: write-all` — the maximal token grant, strictly worse than omitting the block —
  satisfied a rule named for least privilege. A new dimension (5b) in `scripts/check-modern.sh`
  reads the value: at any indent, so the job-level form is caught too (a job grant that widens
  to everything narrows nothing); bare or quoted; and with a trailing `# comment` tolerated, so
  a rationale beside the grant is not the way past the gate. It is anchored to the key and the
  line end, which is why it is its own dimension rather than a `banned_patterns` entry: that
  list is a blind `grep -F`, under which the word could never appear in a workflow comment at
  all — not even to explain why a grant is narrow. `read-all` is deliberately not banned; it is
  not a token-abuse vector, and banning it buys noise.

  Like rule 8, this is not deprecation-driven, and the baseline says so plainly. The fleet is at
  zero occurrences, so it is adopted at zero fix-first cost — and Core owns the `*-call.yml@vN`
  reusable workflows the OS repos actually execute. Both directions are covered by fixtures in
  the hermetic `check-modern` harness: the workflow-level, job-level and quoted-with-comment
  forms are each caught, while the word in a comment, `read-all`, and a named-scope `write`
  are not. (#816)

### Fixed

- **starship drew a dragon emoji on Kali** (#948, the Offense and Defense heroes, which film on
  Kali). `[os.symbols]` had no `Kali` entry, so starship fell through to its own default — the
  same gap openSUSE had until #950, with the same tofu wherever no colour-emoji font is
  installed. `Kali` now gets the Nerd Font Kali glyph.

- **`up -n`'s spinner painted a healthy dry run red** (found filming the nine OS/role README
  heroes, #948). The spinner reports the exit of `_pkgup_list_to`, which is the COUNT VERB's —
  and most archives overload it: `dnf check-update` exits 100 when updates _exist_,
  `checkupdates` exits 2 when there are _none_. The list path was documented to ignore that
  status (a partial list is still a better preview than none) but the spinner was not, so
  every OS repo's signature moment read `x checking pacman for upgradable packages (exit 2)`
  over a green "nothing to upgrade". The helper now answers 0 unless the archive declared its
  exit meaningful (`PKG_COUNT_EXIT_TRUSTED`, Gentoo's case), where it still propagates.
  Pinned both ways in `scripts/test/70-detection.sh`.

- **starship drew a lizard emoji on openSUSE** (same hunt, #948). starship names SLES `SUSE`
  and Leap/Tumbleweed `openSUSE`; `[os.symbols]` declared only the first, so an openSUSE
  prompt fell through to starship's own default for the second — 🦎, which renders as tofu
  wherever no colour-emoji font is installed, which is every terminal this palette targets.
  `openSUSE` now gets the same Nerd Font glyph as `SUSE`.

- **Every prompt on Debian 13 died with "maximum nested function level reached"** (found
  filming dotfiles-Debian's README hero, #948). zsh-vi-mode's default is a lazy init from the
  first precmd — after every rc file, so after the transient prompt has registered
  `zle-line-finish` — at which point zvm wraps that widget, and `zvm_reset_prompt` reads the
  wrapper's dynamically-scoped `$rawfunc` and calls the widget straight back into itself.
  `45-plugins.zsh` now sets `ZVM_INIT_MODE=sourcing` before loading zvm, so the load order
  means what its comments always said: zvm first, the transient prompt last, and last wins
  `zle-line-finish`. Late `bindkey`s (50+, OS, role layers) now also land after zvm's reset
  instead of under it. Pinned in `scripts/test/60-loader.sh`.

- **Rule 2 of the CI floor now sees the `runs-on:` mapping form.** The matcher required the
  banned label on the same line as `runs-on:` or `os:`, so `runs-on:` alone on its line with
  the label on a nested `labels:` child — the runner-group syntax — walked straight through
  the ban. The alternation gains `labels:`; no baseline change, and a fixture pins the shape.
  Latent rather than live — the fleet uses no runner groups or self-hosted labels — and a
  matrix key named anything other than `os:` still escapes, deliberately: catching it means
  dropping the key prefix, which would then fire on every comment in the tree that names a
  label. (#816)
- **The atuin daemon guard probes the `/tmp` socket the 18.21.0 client gained (#941).**
  Upstream PR atuinsh/atuin#4036 (merged 2026-08-31, in 18.21.0) makes the client try
  `$TMPDIR/atuin-$UID/atuin.sock` and _then_ `/tmp/atuin-$UID/atuin.sock` even when `$TMPDIR`
  is set, because the daemon and the shell need not agree on `$TMPDIR`: a systemd user unit
  starts without one and binds `/tmp`, while a shell that exports one — a `99-local`, a tmux
  server started under a different environment, a unit with `PrivateTmp=` — resolved only its
  own. `_core_atuin_daemon_guard` probed that path, found nothing, exported
  `ATUIN_DAEMON__ENABLED=false` at the first precmd and unhooked for the life of the shell with
  **no warning**, because `_CORE_ATUIN_DAEMON_WAS_UP` is never set on that path — one candidate
  short of where atuin's own client would have connected. The candidate list now appends the
  `/tmp` path whenever `$TMPDIR` is set and is not `/tmp`, in upstream's order, still by
  parameter expansion alone; the common case pays one connect as before. The suite gained the
  case, which skips rather than clobbers when a real daemon already owns that inode on the box
  running it. The finding came from the 2026-09-01 `/tool-scout` run, whose report was lost to
  a filing error (#932). Both `VERIFIED_AGAINST` anchors in `zsh/00-tools.zsh` move from
  `18.19.0` to `18.21.0` in the same change — a claim of re-measurement, not a version bump:
  `atuin-guard-verify` was dispatched three times on 2026-09-03 against upstream's then-latest
  and reported `holds` on both premises.
- **The weekly routines no longer file a stub as the report when their subagent outlives the
  main turn (#932).** Headless `claude -p` prints only the final turn, and it waits for
  background work for a bounded 600 s before killing it and emitting whatever text it has.
  `/tool-scout` delegates its research to a subagent; on 2026-09-08 that delegate was still
  researching when the main turn ended, the ceiling fired, and `file-routine-issue.sh` filed
  the "I'll relay its proposal when it lands" preamble as the scan — a report that reads as
  "nothing found" to anyone who does not open the run log. `claude-routines.yml` now sets
  `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` for every job, so each job's `timeout-minutes` is
  the only ceiling and overrunning it is a red job that `notify-failure` reports, not a green
  one with a hollow issue. The two delegating routines (`/tool-scout`, `/doc-audit`) also now
  say to wait for the delegate in the foreground, so the fix does not rest on one env var.
  `/tool-scout` additionally learns how to check for an open `atuin-guard-verify:` verdict
  without `Bash` — WebFetch the issue search — instead of reporting `gh` as unavailable every
  week, which it always will be in that job.
- **`gen-theme.sh --check` passed green over a sibling that was checked out but missing
  its registered file (#933).** The sibling arm decided "can I reach this row?" on the
  **directory**, so when `dotfiles-MacBook/` existed without `sketchybar/colors.sh` — the
  sibling has not landed the palette yet, the zebar path moved, someone deleted it — no
  `SKIPPED` line was printed, `preflight` and the render loop each took their partial-tree
  `continue`, and §9d recorded a pass over a file nobody opened: coverage loss reading as
  health, in the gate whose own comment says it exists to prevent exactly that. Both CI
  legs that clone the fleet reliably have the directory, so that was the shape the failure
  would have taken there. The row is now tested on the **file**; a present-but-incomplete
  sibling is reported on its own `SKIPPED —` line, by file, and exits 3 like an absent one
  (Core-relative rows keep the documented partial-tree `continue` — a different fact). §9d
  collects its skip label from every `SKIPPED —` line rather than stripping at the first
  phrase, and the suite gained the case the old one lacked: repo present, file absent.
- **`Alt+C` could not reach hidden directories, and was a second, weaker copy of `fcd`
  (#933).** `_fzf_cd_dir` re-implemented `fd | fzf` inline without `--hidden`, so the
  widget skipped `.config`, `.github`, `.claude` and `.ssh` — the interesting directories
  in a dotfiles tree, which `fcd` reached — and refused outright without fd where `fcd`
  falls back to `find`. Its `--exclude .git` was dead config too: without `--hidden`, fd
  already skips `.git` for being hidden, while the comment above it claimed the flag kept
  the object store out of the list. The widget now **delegates to `fcd`**, which carries
  the prompt and preview the widget used to have alone, so "cd into a subdirectory" has
  one definition on both entry points. The widget's guard needs only fzf now.
- **`Alt+C`'s collision with vi's change operator is stated (#933).** In viins `^[` is
  `vi-cmd-mode` and `c` is `vi-change`, and a terminal sends Alt+C as exactly those two
  bytes. The binding is kept — Core loads zsh-vi-mode, whose NEX engine disambiguates Esc
  with `ZVM_ESCAPE_KEYTIMEOUT` (30 ms, not the 0.4 s `ZVM_KEYTIMEOUT`), which a terminal's
  chord lands inside and a human's `Esc` `cw` almost never does; and the parity row that
  justifies the key has no such problem, since PSReadLine is not in vi mode. The widget's
  comment now owns that tradeoff instead of omitting it.
- **`freshness.yml`'s apply step could not take the exit 3 the updater grew for it (#933).**
  `update-fleet-versions.sh` exits 3 so an absent fleet stops reading as a defect (#917),
  but its only caller ran it bare under `set -euo pipefail`, where 3 reds the step exactly
  as 2 did — the check-mode step forty lines above already branched on the code, which
  made the omission visible by contrast. The apply step now branches too: 3 is a summary
  line and exit 0. The fleet-clone loop above it is tolerant as well: one repo that cannot
  be cloned anonymously is warned by name and skipped, rather than aborting the loop
  before either graceful path downstream could run.
- **`render_fleet_versions` ran TSV data through `printf '%b'` (#933).** Rows were
  accumulated with a literal `\t` and emitted with `%b`, which reinterprets escapes in the
  fields as well as the separators — a backslash in any field would have been rewritten,
  and a `\c` would have truncated the rest of the table silently. It now joins with the
  `$TAB` the script already defines and emits with `%s`, removing the class.
- Suite: the "an unterminated `/*` is not treated as a marker" case renders the fixture
  before appending the line, so its `!= 2` assertion can actually fail — on an unrendered
  stub `--check` was already 1, and the case passed whatever the parser did. Also dropped a
  duplicated 12-line comment paragraph in §9d (#933).
- **`/doc-audit`'s 2026-09-01 fleet sweep (#811) — the Core-side drift that survived the
  v7 cut.** The sweep was filed against 6.0.0 and most of its findings were overtaken by the
  v6→v7 release work (the `refs/tags/v5` vendoring commands, the Fedora `sudo dnf
  check-update` and Gentoo `gentoo-pkg-pending` cells, the tree-sitter-cli orphaning hedge and
  the Offense repo-status row were all already right). What was not: `CLAUDE.md` and
  `RELEASE-RUNBOOK.md` still named `@v5` as the fleet's _current_ caller alias while every
  caller is `@v7`; `PORTING-MATRIX.md` said `dotfiles-Gentoo` cargo-installs `ouch` in two
  places while its own table cell, footnote ¹² and the repo's `bootstrap.sh` all say
  `guru_extras_install app-arch/ouch` (dotgibson/dotfiles-Gentoo#133); `ARCHITECTURE.md` and
  the matrix's Offense paragraph still described `dotfiles-Offense` as carrying its own apt OS
  layer (it ships no `os/` at all — band 80 comes from `dotfiles-Debian`, which accepts
  `ID=kali`), and the paragraph quoted the pre-v4 loader chain (`… os offensive local`) for
  what is now `80-os → 85-offensive → 99-local`.
- **`core.vendor`'s line-number citations rotted a second time in a week, so the cross-repo
  ones are gone.** The same-repo `zsh/30-functions.zsh` cite for the `PORTING-MATRIX.md` hint
  string had moved 1224 → 1382 (the sweep found it stale at 765 a week earlier), and 27 of
  the 43 cross-repo `file:line` cites — every one of the seven into `dotfiles-MacBook`'s
  `ci.yml`, all seven `check-capabilities.sh` Makefile lines — pointed at the wrong line.
  Those files move independently of Core, so the numbers can never stay right; the
  annotations now name the consumer file and keep the exact line only for cites into this
  repo, which is what `audit-core.sh` §1e can hold to reality. (#811)

- **The README hero is re-rendered from the current tape, and the render-date check is wired
  in as `audit-core.sh` §9l (#877 items 1 and 2, the last of #698's original defect).**
  `assets/demo.gif` on `main` was still the blob committed on 2026-07-06: a `dotfiles-MacBook`
  tree walked through `z dotfiles` and `core help`, two months before #862 rewrote the tape to
  film a `dotfiles-core` checkout, and two releases after #870 landed `--check-render` red and
  deliberately un-wired. The front page showed the very thing #698 was filed about the whole
  time. The gif is now the current tape's tour — `ll`, `cat README.md`, `glog -8`,
  `core status`, `core-version` — filmed on a Core host over a clean `main` checkout, then put
  through the `gifsicle -O3 --lossy=80 --colors 64` pass `assets/README.md` documents.
  **§9k's ceiling was never tested against this tape until now**: `assets/hero.tape.in`'s own
  comment records the first shortened cut at 2.46 MB, so the byte count is in the PR, not in
  prose. `make check-hero-render` flips green on the uncommitted gif and stays green once the
  gif and this entry land in the same commit, which is the only order §9l accepts.
  **§9l is the one block #870's entry promised.** It mirrors §9k's shape — exit 1 is a stale or
  missing gif with the script's own per-row remedy carried through `fail_detail`, exit 2 is
  "could not run", and exit 3 (no usable history: shallow, not a checkout, unrelated
  histories) is an **environment skip** in §9h's posture, never a pass, which is #821's lesson.
  Always on and not scope-guarded, for §9j's reason: a `.tape` and a `.gif` are both inert to
  `ci-classify.sh`. `scripts/test/42-gen-hero-tape.sh` pins the third leg as wired, exactly
  as it pins the first two. Item 3 — the nine sibling heroes — stays open on #877: the tapes
  are written by `make gen-hero-tape-fleet` today, but `@@HOSTGUARD@@` requires each to be
  filmed on the distro its row is about, so that is nine boxes, not one.

- **The hero render can no longer be hijacked by the OS layer's tmux auto-attach (#877).**
  The tape's hidden setup sources `~/.config/zsh/.zshrc` from inside vhs — an interactive TTY —
  and every OS layer attaches (or creates) a `main` tmux session for one. The `source` then
  never returns: the rest of the tour is typed into the pane, the `cd` never lands, and the gif
  films a tmux status bar over the wrong directory, which is exactly how the first #877 render
  came out. The fleet already had an opt-out, spelled two ways — `DOTFILES_NO_AUTOTMUX` on
  MacBook, openSUSE and Gentoo, `DEBIAN_NO_TMUX` on Debian — and nothing at all on Alpine, Arch
  and Fedora. **`DOTFILES_NO_AUTOTMUX` is now the one name**: the template exports it before the
  source, the four repos that did not read it gain the guard (Debian keeps its own name working
  alongside), and `gen-hero-tape.sh` **refuses to render a row whose shell layer auto-attaches
  without honouring it** — exit 2, the cannot-run leg, scanning that repo's own `os/` and
  `zsh/` (never the vendored `core/`) with comment lines dropped in both directions, so
  Alpine's prose about an inline attach it does not do is not an attach, and a knob that is only
  mentioned guards nothing. The `.` row scans Core's own `zsh/`, so the check is never vacuous.
  Deliberately **not** an in-tape `[[ -z $TMUX ]] || exit 1` after the source: on an unguarded
  host that line would be typed into the attached pane and `exit 1` a shell in a real session.
  The tape changed, so the gif is re-rendered in the same commit — the only order §9l accepts.

### Changed

- **nvim plugin pins move forward for three plugins.** `friendly-snippets`, `gitsigns.nvim` and
  `nvim-lspconfig` advance to upstream HEAD — the set a re-run of the fleet health board's
  signals (#794) found stale on 2026-09-09, the day after #938 and the freshness bot's Monday
  refresh (#946) had rolled the previous set.

  Every new SHA is a strict fast-forward of the one it replaces (`status=ahead`, `behind_by=0`
  in all three), and each range was read before promotion:

  - **`friendly-snippets`** `30bfd47` → `6290e13`, 6 commits: snippet data only — React
    `className`, Python async, Kubernetes kustomization/helm/namespace and Unity
    `SerializeField`/`RequireComponent` snippets, a Perl tabstop fix, and one `package.json`
    line mapping `typescriptreact` onto the HTML snippets. Core loads it only as blink.cmp's
    snippet source; no Lua API is involved.
  - **`gitsigns.nvim`** `5be654f` → `f2421c5`, 6 commits: a new repository diff panel (an
    additive `diff` action with its own `actions/diff.lua`, `git/diff.lua` and
    `git/commit.lua`), a `diffthis` cleanup that ignores already-closed source windows, a
    `show` fix that reads the requested revision's path, and an attach guard for a buffer
    wiped while `on_attach_pre` yields. Core sets `on_attach`, not `on_attach_pre`, and the
    actions its keymaps call (`nav_hunk`, `stage_hunk`, `reset_hunk`, `stage_buffer`,
    `preview_hunk`, `blame_line`, `diffthis`, `select_hunk` via `:Gitsigns`) keep their
    signatures — the only new signature is the internal `create_revision_buf` helper.
  - **`nvim-lspconfig`** `19576de` → `84b6b6c`, 2 commits: a new `laravel_lsp` server config
    and its docs. Core does not configure it; nothing under Core's `servers/` tree is affected.

  Nothing renames or removes an API Core calls. (`nvim/lazy-lock.json`, #794)

- **The README hero tour's wait after its signature command is a registry column** (#948,
  the nine sibling heroes): `assets/hero-repos.txt` gains an optional seventh field, `sigwait`,
  a vhs duration that lands after `Sleep` on the signature line, 4s when absent (it was a
  fixed 2.2 s). `dnf --refresh check-update` re-validates every enabled repo's metadata before
  it answers — ~3 s on a warm cache — and at 2.2 s the first Fedora render typed the proof line
  into the spinner and cut before the answer; Portage resolves `emerge --pretend` in ~10 s, so
  Gentoo's row says `15s` and nobody else's says anything. `gen-hero-tape.sh` validates the
  field (a duration vhs can parse; an empty seventh column is refused) and the suite pins it.
  Every tape and this repo's own gif are re-rendered. Eight of the nine sibling heroes are now
  filmed and committed in their repos — Fedora, Alpine, Arch, Debian, Gentoo, openSUSE, Offense
  and Defense, each on a rootless chroot of its distro; `assets/README.md` records the recipe
  and the five traps; MacBook's was filmed on a Mac, which closes the set.

- **nvim plugin pins move forward for five plugins.** `friendly-snippets`, `nvim-lspconfig`,
  `nvim-tree.lua`, `nvim-treesitter` and `schemastore.nvim` advance to upstream HEAD — the set
  the 2026-09-07 fleet health board (#794) reported as stale, one day after the freshness bot's
  Monday refresh (#916) had rolled the previous set.

  Every new SHA is a strict fast-forward of the one it replaces (`status=ahead`, `behind_by=0`
  in all five), and each range was read before promotion:

  - **`friendly-snippets`** `6cd7280` → `30bfd47`, 16 commits: snippet-data fixes and additions
    (markdown todo variants, django template tags, a Java class fix, zig 0.15 `buildExe`) plus a
    repo-wide Prettier/StyLua reformat that accounts for most of the 76 touched files. Core loads
    it only as blink.cmp's snippet source; no Lua API is involved.
  - **`nvim-lspconfig`** `615d7b2` → `19576de`, 6 commits: fixes to `robotcode`, `powershell_es`
    and `phpantom_lsp` — none of which Core configures — and a `plugin/lspconfig.lua` refactor
    that moves legacy-only code below its version check. Nothing under Core's `servers/` tree is
    affected.
  - **`nvim-tree.lua`** `b2aadda` → `882c54f`, 1 commit: an "invalid 'line'" renderer fix for an
    empty tree with `hidden_display` set. Core calls `setup()` and `api.tree.open()`, both public
    and unchanged.
  - **`nvim-treesitter`** `32dbd2e` → `5cb0114`, 1 commit: type-annotation tightening in
    `async.lua`; the three `install.lua` lines it touches are `---@type` comments, so the
    `install()` Core calls has the same signature.
  - **`schemastore.nvim`** `4a0e1b7` → `2224119`, 2 commits: catalog refreshes only.

  Nothing renames or removes an API Core calls. (`nvim/lazy-lock.json`, #794)
- **Bumped two pins in `scripts/tool-versions.env` on the weekly freshness review; held the
  third (#813).** This is the class no bot covers — the CLI gate pins sit between
  `/freshness-triage`'s plugin locks and Renovate's manifests — so the routine re-audited all
  ten against upstream and found seven still current:

  | Pin | Was | Now | |
  | --- | --- | --- | --- |
  | `NVIM_VERSION` | 0.12.4 | **0.12.5** | one patch on the 0.12 line |
  | `CLAUDE_CODE_VERSION` | 2.1.222 | **2.1.265** | the routine bots' own CLI |
  | `SHFMT_VERSION` | 3.13.1 | 3.13.1 | **held** — 3.14.x changes formatting output, see below |

  nvim 0.12.5 is fixes-plus-features on a line whose breaking changes (diagnostic sign config,
  `vim.diagnostic.disable()`, `vim.diff` → `vim.text.diff`, the `'shelltemp'` default) all
  landed at 0.12.0 and were absorbed by the 0.12.4 pin; nothing new to adapt to.
  `NVIM_SHA256` recomputed with `make update-tool-checksums` and **cross-checked against the
  `digest` GitHub reports for the release asset** rather than trusted from our own download —
  the four unbumped hashes re-derived byte-identical, which is its own integrity signal.

  **shfmt stays at 3.13.1 deliberately.** 3.14.0 changed _output_, not just behaviour — a space
  after `!` in arithmetic, nested closing parens spaced like the opening ones, no `;`-joined
  `then`/`do` when a heredoc is pending — and 3.14.1 followed a week later with heredoc
  indentation fixes. Core's own audit does not gate shfmt, so a green tick here proves nothing
  about it; the pin exists only so `setup-core-tools` installs one verified shfmt for MacBook
  and the distro/role lint workflows, where a bump can newly flag files that pass today with
  no diff in this repo to warn you. The consumer step is advisory (`::warning::`, not red), so
  it would not break them — but it would start nagging on every run until each repo reformats.
  Bump it alongside a reformat pass across the consumers, not on its own.
- **Every mint step passes `client-id`, not the deprecated `app-id`, and reads a new
  `FLEET_APP_CLIENT_ID` org variable (#831).** Our pinned `create-github-app-token` (v3.2.0)
  carries `deprecationMessage: "Use 'client-id' instead."` on `app-id`, and all five mints
  here — `notify-web.yml`, the reusable `notify-web-call.yml`, `sync-fanout.yml` and
  `freshness.yml`'s three — passed it.
  **It is not a one-line swap, which is why it needed its own change.** `FLEET_APP_ID` holds
  the App **ID**; the new input wants the App's **Client ID**, a different value on the same
  settings page (and a public one: `gh api /apps/dotgibson-fleet-sync --jq .client_id`). So the
  variable is a **new** one rather than a repurposed one — the two names never hold different
  meanings mid-rollout — and the `if:` guards move in the same commit as the input, because a
  guard still testing `vars.FLEET_APP_ID` against a step reading `FLEET_APP_CLIENT_ID` would
  keep gating on a variable the mint no longer uses.
  **Precondition, not a follow-up: the org variable must exist before this merges.** With it
  unset, every guard is false, `sync-fanout`'s preflight goes red (the loud half) and the
  `notify-web` dispatch degrades to a `::warning::` and skips (the quiet half) — the exact
  failure shape #831 was written to avoid.
  **`FLEET_APP_ID` is retired here but must not be deleted yet.** The nine OS-repo callers
  execute `notify-web-call.yml` at the `@v7` alias, which reads the old variable until the next
  release advances it; `htpx`'s fan-out and `dotfiles-Windows`' inline notifier still pass
  `app-id` and are tracked in their own repos. `GITHUB-APP-AUTH.md` carries the retirement
  note with the grep that derives the remaining readers, its _Re-creating or re-keying_ section
  now tells you to collect the Client ID, and the known-gaps callout shrinks to the one gap
  left (scope the verbs).
- **Rule 1's node20 rationale carries the final date.** The ban was already correct; the
  comment said "fall 2026". Node 20 leaves the runners on **2026-09-23** — the 2025-09-19
  deprecation changelog, its date fixed by an editor's note of 2026-08-25. No fix-first work:
  every external action in the tree (`actions/checkout`, `actions/cache`,
  `actions/create-github-app-token`) already resolves to `using: node24` at its pinned SHA.
  (#816)

## [v7.2.0] - 2026-09-08

### Added

- **The `core:theme:gen` marker grammar learns a second comment syntax, so the zebar palette
  — the last hand-authored copy of Core's colours — is generated too (#926, closing #857).**
  Every consumer up to #857 was `#`-commented (toml, yml, zsh, sh, conf), so the grammar was
  written for `#` and that looked like a property of the tool rather than an accident of which
  files happened to carry blocks. **CSS has no `#` comment** — `#` there begins an id selector
  — so `dotfiles-Windows`' `styles.css` could not carry a marker in any form.
  **The style is registered nowhere, which is the whole shape of the change.** `build_file`
  echoes both markers **verbatim** — it never writes them — so the generator never needs to
  know which syntax a file uses. Only the matchers do, and they simply accept either. The
  fourth registry column #926 first proposed would have stored a fact in two places, and the
  copy in the file is the one that decides.
  The pattern was restated in **three** greps; it is defined once now, which is how the
  `#`-only assumption survived unnoticed in the first place.
  **Two defects surfaced only by running it.** `*.css` was missing from the reverse scan's
  file set, so a stray CSS marker was invisible to the gate that exists to find exactly that.
  And the scan took the block id as the last whitespace-separated field — which on this syntax
  is the closing `*/`, so every CSS block would have reported as unregistered under a name no
  registry could ever carry.
  An unterminated `/*` is deliberately **not** a marker: a line opening a comment it never
  closes would swallow the generated block into it, leaving a file that still parses while
  rendering nothing.
  Nothing drifted — all eleven values already agreed, so this is pure gating, and a
  hand-edited hex in the bar now exits 1.

- **`Alt+C` — cd into a subdirectory — is real on both shells, after years of being advertised
  and bound by neither (#808).** `PARITY.md` listed it as `aligned` beside `Alt+Z`; #682
  established that **zsh had never bound `^[c`** and never sourced fzf's own key-bindings (the
  `FZF_ALT_C_*` exports that would have configured fzf's stock widget were deleted in v6.0.0 as
  dead config), and that `dotfiles-Windows` set only the provider and reverse-history chords.
  #682 deleted the claim rather than implementing it; this implements it.
  **It is not a second key for `Alt+Z`.** `Alt+Z` is a frecency jump to anywhere zoxide has
  seen; `Alt+C` is scoped below `$PWD` and finds directories zoxide has never visited. Different
  intents, and an operator arriving from stock fzf or PSFzf expects the latter here.
  `_fzf_cd_dir` follows the three sibling widgets exactly, including the guard: bound
  unconditionally, so it warns in Core's voice rather than piping an unset `$FD_BIN` into a
  missing fzf. `.git` is excluded for the file picker's reason — a repo's object store is
  thousands of directories nobody wants to cd into.
  **It gets its own `PARITY.md` row, not a widened `Dir jump`.** #808 predates #809, which made
  every row a single claim precisely so a row could not outgrow its needles; folding `Alt+C`
  back into `Dir jump` would recreate the shape that let `Alt+C` hide behind `Alt+Z`'s needle
  for years. The pwsh needle greps the **`Set-PsFzfOption` argument**, not the chord string:
  `Alt+c` also appears on the lazy-load stub's line, so a chord match would stay green if the
  real binding were deleted.
- **`core status --deep` — verify the COMMITTED `core/` against upstream, not just against
  HEAD (#797).** The existing Integrity row compares the **worktree** to HEAD: it catches the
  hazard operators actually hit (a hand-edit the next `make sync` clobbers) and is offline and
  instant, which is most of `core status`'s value. It cannot catch an edit that was
  **committed** — a bad `git subtree pull`, a hand-edit that got committed, a conflict resolved
  wrongly. `--deep` fetches the pinned `core_sha` and answers that half.
  **Tree OIDs, not a file-by-file diff.** `core-integrity.sh` already frames the question as
  _"the git tree object of `HEAD:core`"_, and git trees are content-addressed — so an OID
  computed in the fetched clone equals the local one exactly when the content does. No
  materialisation, no `checkout-index`, and no diff binary (#572).
  **The filter comes from the fetched commit, never from anything vendored.** #676 removed
  `core-vendor.sh` from the vendor set because a gate resolving trees in Core's object store
  cannot run in a repo that has none; reading it out of the commit just fetched sidesteps that,
  and a `core_sha` predating the allowlist carries no such file, so the comparison falls
  through to the whole tree and spans the migration with no flag day.
  **Opt-in, and never on the default path** — it is the only row that touches the network, and
  it carries a 20s ceiling. It **degrades, never errors**: offline, no git, a sha upstream will
  not serve → a stated `unverifiable` and exit 0. The one exception is a malformed `core.lock`,
  which is `broken`: a `core_sha` that is not 40 hex characters is a defect in the checkout,
  not a fact about the network, and reporting it as "could not check" would launder it.
  `--json` grows `.integrity.deep` as a **sibling** key with its own token set
  (`verified`/`differs`/`broken`/`na`/`unverifiable`), leaving `.integrity.status` untouched —
  the never-widen rule `_core_doctor_json` established. It is `null` when `--deep` was not
  asked for, so "we did not look" stays distinguishable from "we looked and it was fine".
- **`gen-theme.sh` reaches `dotfiles-MacBook`'s sketchybar palette, so the last hand-authored
  copy of the Tokyo Night values is generated (#857).** `theme/palette.toml` is meant to be the
  only place a hex is authored — the rule `CLAUDE.md` states and `audit-core.sh` §9d enforces.
  `sketchybar/colors.sh` sat outside it entirely: no `core:theme:gen` block, so §9d had never
  looked at it, held in step with Core by its own third line reading _"matched to
  core/starship + core/tmux"_. That is the construction #693 and #682 exist to end, and #679's
  own note (_"a comment is not a gate"_) was written about this very palette.
  **Nothing drifted.** All twelve values already agreed with the palette, verified before and
  after — this is pure gating, which is the good moment for it. A hand-edited hex in the bar
  now exits 1 where previously nothing anywhere read the file.
  The registry gained a third column naming the sibling repo a row's path is relative to
  (empty = Core, which is every pre-existing row), and `--fleet DIR` says where the siblings
  live — defaulting to Core's parent, the convention `gen-porting-matrix.sh` and
  `parity-check.sh` already use. `emit_sketchybar_colors` renders sketchybar's `0xAARRGGBB`
  form, with the alpha **per entry** rather than constant: the bar background is deliberately
  translucent (`0xee`) over the storm black.
  **An absent sibling is a reported skip, never a silent pass.** `--check` returns **3** and
  names the repo it could not open; §9d classifies that through `skip_env`, the way §9h and §9i
  already classify theirs, so `--strict` reads it as "clone the sibling" rather than "install a
  tool". Real drift outranks it — 3 is only returned when nothing else went wrong — and that
  precedence is pinned by a test, because a gate that reported the environment while a defect
  sat in the tree would be worse than one that reported neither.

### Changed

- **`dotfiles-Windows`' zebar palette is NOT covered by #857, and the reason is worth
  recording.** The marker grammar is `#`-comment-only —
  `^[[:space:]]*#[[:space:]]core:theme:gen …` — which every current consumer satisfies (toml,
  yml, zsh, sh, conf). CSS has no `#` comment, so `styles.css` cannot carry a marker at all.
  The issue's own scope note asked whether the **renderer** set covered both forms; the actual
  obstacle is one layer down, in the grammar that `marker_id`, `marker_indent`, preflight and
  #906's reverse scan all share. Split out rather than bolted on.

### Fixed

- **`PORTING-MATRIX.md`'s `fleet-versions` table was the one generated block that was not a
  prettier fixed point, so two gates disagreed about it (#836).** `gen-porting-matrix.sh`'s own
  header states the rule — markdown is emitted in prettier's **aligned** form because conform
  runs prettierd on save, _"so an unpadded table would be re-padded on the next save and read
  as drift"_ — and `_table` exists to do it. `render_fleet_versions` (#914) printed raw
  `printf '| %s | … |'` rows instead, bypassing it.
  The consequence was a loop, not a cosmetic wart: open `PORTING-MATRIX.md` in Core's own
  nvim, save, and prettierd re-pads the block; §9h then calls that drift; `make
  gen-porting-matrix` puts it back unpadded; prettierd re-pads it again. Each gate correct on
  its own terms. `prettier --check` now reports the file clean and `--check` is green on the
  same bytes.
  **This supersedes what #836 recorded.** That issue described "two pre-existing non-fixed-point
  spots in the hand-written prose … unrelated to the generated regions". Both prose spots are
  gone, and every remaining complaint was inside a generated block that did not exist when the
  issue was filed. Three of #836's five items had likewise been closed in passing — the
  openSUSE `uv` cell now carries its ²¹ mark, `_CORE_DOCTOR_OPTIN` is gated by §9p plus
  `test/65-functions.sh`, and `dotfiles-Debian`'s workflow no longer hard-codes a footnote
  number.
  The regression guard asserts alignment **without prettier**, which the suite cannot depend
  on: in an aligned table every row of a block renders to the same width, so one unpadded row
  shows up as a second distinct width. Counted in code points rather than bytes, because the
  packages table's superscripts would make a byte count call that table ragged the moment the
  helper is reused. Reverting the generator gives 5 distinct widths and reds.
  The fleet-versions row assertions also stop matching fixed strings: padding widths move
  whenever any value in a column changes length, so the test now asserts **cells**, which is
  what it always meant.

- **The freshness bot's `fleet-versions` job could never finish on a runner (#917).** #914 added
  a job that re-probes the recorded fleet package versions, writes
  `scripts/fleet-package-versions.tsv`, then regenerates `PORTING-MATRIX.md` from it. The
  regeneration reads the **sibling OS checkouts**, defaulting to this repo's parent directory —
  which on a CI runner is empty. Its first scheduled run probed all 16 rows successfully and
  then died:
  `gen-porting-matrix: not checked out under /home/runner/work/dotfiles-core: … !! regeneration failed`.
  The job now clones the fleet first, public/anonymous/shallow — the idiom `parity-check.yml`
  already uses — and the list comes from `scripts/os-repos.txt` rather than being spelled in the
  workflow, because that file is the one place fleet membership lives and a second copy in YAML
  is the kind that goes stale unnoticed. `update-fleet-versions.sh` gained `--fleet DIR` to pass
  it through.
  **Two smaller defects were underneath it.** The updater collapsed every non-zero exit from the
  generator into one message, discarding the split `gen-porting-matrix.sh` goes out of its way
  to make — exit **3** for "the fleet is not here" versus **2** for a structural fault — the same
  split `audit-core.sh` §9h relies on to record an absent fleet as an environment skip rather
  than a defect. And it wrote the TSV **before** regenerating, so a failed regeneration left the
  tree carrying a new TSV against a stale matrix: drift that reds §9h for the next person who
  runs it beside the fleet. The write is now staged behind a backup and rolled back if the
  matrix cannot follow it, so the two halves of one artifact move together or not at all.

## [v7.1.2] - 2026-09-07

### Fixed

- **v7.1.1 was staged and never published — this release carries its content.** The cut promoted an empty `[Unreleased]`, because #920's entries had been filed under `[v7.1.0]` by mistake and the section they should have landed in was bare. `tag-release.sh` refused to tag it: `release.yml` builds the Release body from that section, and an empty body on an immutable tag burns the version. No `v7.1.1` tag was ever created and no repo vendored it, so the number is simply skipped — the same outcome `RELEASE-RUNBOOK.md` records for v4.11.0. The two entries below are unchanged.

- **`maint-status` reported a clean listing on a box where nothing was installed (#918).** Its
  systemd arm ran `list-timers` (header + `0 timers listed` on **stdout**, exit 0) and
  `status` (`Unit … could not be found` on **stderr**, discarded by `2>/dev/null`). The one
  call that knew the unit was missing was the one whose output was thrown away, so the arm
  rendered output indistinguishable from a healthy box.
  Found on a live Proxmox node: `maint-install` had written nothing, both unit files were
  absent, `is-enabled` said `not-found`, there was no crontab entry — and `maint-status`
  looked fine. The operator reasonably believed the daily run was scheduled.
  **The bug is an asymmetry, not an oversight in one line.** `launchd` has carried
  `|| echo "not loaded"` and `cron` `|| echo "no cron entry"` all along; **systemd was the
  only arm of the three without an absence branch**, and it is the arm Debian, Fedora, Arch,
  openSUSE, Defense and Offense all take.
  It now reports **three** distinguishable states, because they fail independently and
  `list-timers` renders all of them as the same empty output: no `SCHEDULER_UNIT_DIR`
  declared (nowhere to write — #763's rule), declared but no unit file (not installed), and
  installed but not enabled (exists, will never fire). Naming only the second would have
  pointed at the wrong repair for the other two.
  The same failure family as #829, where `nvim --headless` exited 0 over a session in which
  nothing ran: a status command that cannot report absence turns an unanswered question into
  a wrong answer, and the next signal is noticing weeks later that nothing has updated.

- **A maint step whose output lacked a trailing newline swallowed the front of the next log
  record — including its `✗` (#919).** `log()` used `echo`, which emits a trailing newline
  but no **leading** one, so a record only began on a fresh line if whatever wrote last
  happened to end with one. `step()` pipes each command's raw output into `$LOG` — through
  `tee` on the tty arm, `>>` on the scheduled one — and neither can promise that. Observed
  on a live box as `Successfully updated 1 registry.2026-09-07 12:17:26  ✓ neovim: …`.
  Harmless for a `✓`. For a `✗` it moves the **only** record that anything failed out of
  column 0, where a timestamp-anchored scan and an operator's eye both miss it — and
  `step()` deliberately continues past failures with the process still exiting 0, so that
  log line is the entire error contract. **Not foreground-only**: the scheduled arm has the
  same shape, so an unattended 3am run corrupts its log with nobody watching.
  Fixed in `log()` rather than `step()`, because `step()` is not the only writer (the mise
  bump probe and the zsh-plugin loop also append) and `log()` is the one place every record
  passes through. The newline goes to the **file only** — the terminal's column is not
  knowable, and at the start of a run the log may end mid-line from a previous run while the
  terminal is fresh, so emitting to both would print a spurious blank line every time. The
  guard is conditional, asserted by a case that fails if consecutive records ever gain a
  blank line between them.

## [v7.1.0] - 2026-09-06

### Added

- **`scripts/fleet-vendor-guidance.sh` — the vendoring hint every repo prints was wrong in
  eight of nine, and one repo had been right the whole time.** When `core/` is missing or
  half-vendored, each OS repo prints a hint. Seven printed
  `git subtree add … main --squash` to create and `git subtree pull` to update. A branch is
  not the commit the fan-out pins, so `core-integrity` reports the fresh repo as **TAMPERED**
  before it has done anything wrong; `subtree pull` moves `core/` without `core.lock` and
  merges upstream's whole tree rather than the vendor set (#676). The hint fires precisely
  when someone is already repairing a broken clone, so it handed them the two commands that
  make it worse. `dotfiles-Defense` shipped the same text in a **weekly workflow** that files
  a drift issue, pointing at `git subtree pull` and a `make core-lock` target that repo does
  not define.
  **The finding is not that eight repos were wrong — it is that the fix existed and did not
  propagate.** `dotfiles-MacBook` has carried "take the RELEASED tag (never main, or
  core-integrity reports the fresh subtree as TAMPERED)" for years, and nothing read the
  other eight to notice they disagreed. Then MacBook's own hint went stale at
  `refs/tags/v4` against a v7 fleet, landing in the same TAMPERED state its warning exists to
  prevent: correct advice, defeated by a hardcoded number nothing checked.
  So the register asserts the guidance is **right** (a tag not a branch — `branch`; the
  moving major tag not a point tag — `non-major-tag`; `add` not `pull` — `subtree-pull`) and
  **current** (`stale-vN`, against a major **derived from `core.version` at run time**, so the
  day Core cuts v8 every stale `v7` hint in the fleet reports itself instead of waiting to be
  discovered). Each defect class gets its own label, because a register that says "wrong"
  without saying how is one nobody acts on.
  Two scoping decisions are load-bearing. It matches **`--prefix=core` only**: `git subtree`
  is not banned fleet-wide, and `dotfiles-Offense` vendors `offensive/companion` from
  `dotgibson/htpx`, which genuinely is a subtree whose `sync-companion.sh` runs `subtree pull`
  on purpose — flagging it would train people to ignore the gate. And it matches **commands,
  not prose**, since these repos discuss `git subtree pull` correctly and constantly; the
  discriminator is a `--prefix` naming `core`.
  Wired as `make fleet-vendor-guidance` and as an advisory §5h section of `audit-core.sh`,
  alongside the coverage, vocabulary and release-trigger registers — advisory for their
  reason, that a sibling can drift without Core changing. **Core counts its own row but not
  toward the sibling total**: it is the repo the script lives in, so it is always present, and
  a naive count would report "every hint is current" off `VENDORING.md` alone while reading no
  fleet at all — the green-because-absent result `skip_env` exists to avoid.
  Green on arrival across all ten repos, following the fleet sweep in
  dotgibson/dotfiles-Arch#158.

- **`audit-core.sh` §9p — `TOOLS_OPTIN` was the third copy of one set, and the only ungated
  one (#890, out of #836).** `PORTING-MATRIX.md`'s ²¹ marks are the human contract; Core's
  `_CORE_DOCTOR_OPTIN` is the **row-level** set, already re-derived and asserted by
  `test/65-functions.sh`; each OS repo's `TOOLS_OPTIN` carries the **cell-level** marks and
  was checked by nothing. **The miss already happened and was found by eye**: `uv` is in
  `_CORE_DOCTOR_WIRED`, `dotfiles-openSUSE` installs none and declared no `TOOLS_OPTIN`, so
  it fell back to Core's default — which does not list `uv` — and `core-doctor` rendered a
  false `✗` on every openSUSE box.
  The rule is exact, and the fleet already satisfies it: _a repo whose matrix column carries
  cell-level ²¹ must declare `TOOLS_OPTIN` as Core's row-level set **plus** those tools; a
  repo with no cell-level mark may omit it_. The "plus" is the whole set repeated, because a
  declared list **replaces** the default rather than adding to it — declaring only the delta
  would trade one false `✗` for nine, which is its own test case.
  **Blocking, unlike §9o**, and the difference is the fleet's state rather than a change of
  heart: every covered repo passes today, so it can red on a regression without reddening
  anything that exists.
  Two maps are **explicit because neither is derivable**, and both had a trap behind them.
  `Kali (apt)` and `Debian/Ubuntu` are two columns of **one repo**, so a header-to-directory
  guess would invent a `dotfiles-Kali` or drop Kali's marks. And a parenthetical in the Tool
  cell is not reliably a binary name — `jujutsu (jj)` is an alias, `op (1Password)` is a
  description — so an unknown one is **reported rather than guessed at**. The derivation also
  stops after the first table: footnote 21 carries a coverage table of its own whose first
  column is backticked tool names (`PORTING-MATRIX.md:653`), and a scan that stays armed
  sweeps `` `gping` `` in twice and invents a flag. Both traps are asserted, and both were
  live bugs in the first draft — caught by running it against the real fleet rather than
  against fixtures. Five repos, not nine: `dotfiles-MacBook`, `-Fedora`, `-Offense` and
  `-Defense` have no column, so the gate is **silent** about them rather than inventing a
  verdict for a repo the matrix cannot see.
- **`audit-core.sh` §9o — `core/` described as a `git subtree` is a checked fact now (#891,
  the gate #774 asked for).** #587 replaced the fan-out's `git subtree pull --squash` with a
  pinned fetch plus `git read-tree --prefix=core/`; #668 retired the framing from Core's docs;
  #774 swept the eight OS repos' `CLAUDE.md` by hand. This is what makes the next recurrence
  visible. The framing matters because it is what leads a reader to reach for
  `git subtree pull`, which moves `core/` but **not** `core.lock` and leaves `core-integrity`
  reporting `TAMPERED` — precisely what `VENDORING.md:154` forbids.
  **Running it once found twenty-one more sites.** #774 scoped itself to `CLAUDE.md`; the
  same stale claim is live in `README.md`, `CONTRIBUTING.md`, `SECURITY.md` and the PR
  templates across **all nine repos** — including one line in `dotfiles-Defense` that manages
  to say both, calling `core/` _"a vendored subtree, materialized by dotfiles-core's own"_.
  A hand sweep scoped to one filename missed them precisely because it was scoped to one
  filename, which is the whole argument for the gate.
  Those 21 landed as nine PRs in the same pass, so this ships **blocking** rather than
  advisory — and the flip was made against the **tree**, not the PR list: re-checked against
  every repo's `origin/main` (0 of 21 remaining, nine repos), because a repo can regain a line
  and an environment skip with no siblings cloned looks exactly like a pass. **Keyed on the claim, not the token**, and that is forced rather than fastidious: two
  `git subtree` mentions in `dotfiles-Offense` are correct — one of them a sentence arguing
  this gate's own position, the other the `offensive/companion` subtree, which genuinely is
  one — and a blanket scan would red both. Nine cases, every fixture **real text**: the
  positives lifted from the repos #774 corrected, the negatives from what replaced them.
  Stated limit, because a gate that overstates its reach is the defect it exists to prevent:
  the **prohibition** shape (`dotfiles-MacBook`'s old _"a manual `git subtree pull` is not
  supported"_) is invisible to it, since `core/` follows `subtree` there rather than being its
  subject — and separating that from a legitimately negative sentence needs semantics a line
  matcher does not have.
- **The `HAVE_*` contract is enforced caller-side now, so direction 2 is not advisory
  (#866).** `audit-core.sh` §5j direction 2 — _no OS or role repo reads a Core `HAVE_*` flag
  `PORTABILITY.md` §5 does not declare_ — **never fired in any CI**. Core's own CI checks out
  this repo alone, so it recorded an environment skip on every run (the right posture, the
  same one §5f and §5h take), which left it exercised only by a maintainer's local
  `make audit`. So an OS-repo PR could add `${HAVE_LNAV:-}` — a flag Core no longer sets —
  and merge green, with the break surfacing later as a shell function quietly not firing:
  exactly the failure #694 existed to prevent, one repo over.
  The blocker was transport. The rule has lived in `_core_have_read_hits` for a while, with
  thirteen fixtures; what a caller could not have was the **declared table**, since
  `PORTABILITY.md` is not vendored. Of the three routes #866 weighed, this takes the one it
  called the house idiom: **`scripts/gen-have-api.sh` renders §5's machine-readable half into
  `zsh/have-api.txt`**, which _is_ vendored. Vendoring the doc itself would have been a
  `core.vendor` allowlist change — which `V5-PROPOSAL.md` §4 treats as a major-version
  concern of its own — to ship 270 lines of prose the OS repos have never needed; declaring
  it in `common.sh` needed no generator but inverts _"the doc is the contract"_, which #860
  deliberately chose. So the doc stays authoritative and only the part a gate reads travels.
  **The new gate guards the twin, not the rule**: §5m fails when `have-api.txt` and §5's
  table drift, because two parsers for one table is the defect one level up from the one
  this closes — and a test asserts the generator's awk is **character-identical** to §5j's
  rather than merely equivalent, since equivalence holds right up until someone "clarifies"
  one copy. The refusal to render an **empty** contract is load-bearing in the opposite
  direction from §5j's: an empty twin would mark every downstream read undeclared and red
  nine repos at once, for a defect in Core.
  **The leg lands warning-first**, as #866's adoption note asks and as the block-duplication
  leg did: callers pin a moving major, so every OS repo sees it the moment auto-tag moves,
  including a repo with a branch in flight that predates the rule. Verified clean across all
  nine repos first — the only cross-repo read is `HAVE_ATUIN`, which §5 declares — and
  verified to fire on an injected `${HAVE_LNAV:-}`. A caller whose `core/` predates the file
  is told to sync rather than judged against an allowlist it never received.

- **`audit-core.sh` §9n — the fleet's caller pins are checked now, not remembered (#804).** The
  v5 → v6 caller sweep was **45 pins across 8 repos, done entirely by hand**, and nothing
  would have reported a repo that was missed. Two gates looked adjacent and neither covered
  it: §8a's `_core_workflow_ref_hits` is called as `. "$major"`, so its scope is **Core's own**
  `.github/workflows/`; `fleet-drift` reads each repo's recorded `core.lock` provenance, a
  different axis entirely. #736 predicted this and expected #672 to close it — #672 closed as
  _"done and now gated"_, but the gating it refers to is §8a. So the fleet half was never
  covered by anything.
  **A missed repo is worse than an ordinary stale pin**: it runs the _outgoing_ major's
  reusable workflows, and on a major that changes what `core-integrity` expects — #676 is
  exactly one — its CI reports `TAMPERED` against a tree nobody touched and its fan-out PR
  cannot merge. It is also self-healing in the **wrong** direction, staying quiet until the
  pinned workflow is deleted or diverges, so the failure surfaces long after the release that
  caused it.
  `_core_caller_pin_hits` is the third half of a check that had two: §8a reads `ref:` keys,
  §8b reads comment examples, and this reads the live `uses:` an OS repo actually executes.
  It shares the sibling matcher exactly — owner plus left boundary, so `notdotgibson/…` and
  `someone/not-dotfiles-core/…` are not judged — and **only `@v<digits>` is judged**:
  `dotfiles-MacBook` pins by SHA on purpose, and answering "which pinning style" is
  `check-modern.sh`'s job, not a second opinion here. Nine cases, and the sharpest drives all
  three helpers over one fixture to assert that a stale live caller is invisible to both
  siblings and visible only to this one — #804's gap stated as an assertion rather than as
  prose. `RELEASE-RUNBOOK.md` §2 now says the sweep is checked, and records that
  `dotfiles-Windows` stays a hand check **because** it is not in `scripts/os-repos.txt` —
  widening the gate past the fleet list would put the list and the gate in disagreement, and
  #805 is what that blind spot costs when nobody checks it.
- **`audit-core.sh` §9m — the fan-out count is a gate now, not a number five files got wrong
  (#770).** `scripts/os-repos.txt` is the canonical fleet list and its own header says so
  (_"THIS FILE IS THE ONLY EDIT"_), but nothing read it against the prose that states how many
  repos a Core change reaches. Five sites said **eight** against ~20 saying nine, and two of
  the five were Core files — so the wrong number was replicated nine ways on every sync. #668
  had found one of them a year earlier and _deliberately left it_, because correcting one of
  several inconsistent sites makes the tree no more correct. That is the argument for a gate.
  **Keyed on the CLAIM, not the number.** Three different numbers are correct here about three
  different sets — 9 Core-vendoring, 8 OS-native (including `dotfiles-Windows`, which vendors
  nothing), 11 for the whole system — so "eight" was never simply a stale nine: it is someone
  correctly counting OS repos and attaching it to the **fan-out**, which is a different set. A
  check on the bare number would red on `85-escalation.sh`'s _"eight repos rely on sudo-first"_
  (nine minus Alpine) and on #775's _"eleven defects across eight repos"_ (the lint-call
  callers) — noise, and noise is how a check teaches the fleet to ignore it. So
  `_core_fanout_count_hits` fires only where a **fan-out verb governs the count**. Measured
  against the tree: 23 such claims, and exactly the two genuine defects among them.
  **It carries one line of memory**, because that is how the `ci.yml` survivor hid — the verb
  on one comment line, `8 repos` on the next, so a line-based check read neither half as a
  claim while a hand-sweep looked straight at it. The finding is reported against the line
  holding the **number**, which is the line an author edits. `CHANGELOG*`/`V*-PROPOSAL.md` are
  excluded (a historical record is correct for when it was written), untracked files are not
  judged, and a per-line `# core:fanout-fixture` marker lets `test/90-policy-gates.sh` hold the
  wrong claims verbatim — the trap that once made `_core_make_gate_hits` report Core as the
  repo missing its own rule. Thirteen cases, and the negative ones carry as much weight as the
  positive: they are the legitimate other-set lines, copied out of the tree.

- **`blib_resolve_su --prefer TOOL` — the escalator order is not a universal fact (#867).**
  `blib_resolve_su` has resolved sudo-then-doas since it was written, which is right for eight
  repos and **wrong for `dotfiles-Alpine`**: its `os/alpine.capabilities` declares _"DOAS, NOT
  SUDO — the Alpine fact this file exists to declare"_, and says so explicitly for "the rare
  Alpine box that installs sudo as well". So adopting the helper there would have silently
  inverted a declared OS fact — and the repo kept its hand-rolled probe instead. That probe is
  `[[ "$(id -u)" -eq 0 ]]`, the arithmetic comparison an **empty** `id` output satisfies:
  demonstrated here concluding "we are root" while running as an unprivileged user, which on
  Alpine means every `apk add` runs unescalated. **A helper the fleet cannot adopt without a
  behaviour change is a helper the fleet does not adopt**, so this is the prerequisite for
  closing that gap rather than a convenience. `--prefer` puts a named tool at the front of the
  same `_blib_su_path` discipline as the defaults — absolute path, real executable, never a
  shell function — so `--prefer pkexec` works too, and a preference that is absent falls back
  rather than failing. The argument parse became a real loop in the process: it read only
  `$1`, so `--prefer doas --require` would have dropped the requirement, and an unknown flag
  now returns 2 instead of being ignored — a mistyped `--require` silently downgrading to a
  warning is the direction that hurts. Six cases in `test/85-escalation.sh`, including the
  default order itself, since eight repos depend on sudo-first and nothing else pinned it.
  `VENDORING.md`'s helper table records when to reach for it.
- **`_core_make_gate_hits` R5 — a local markdown gate must run the PINNED linter (#876).**
  The Makefile-gate guard already had four rules, and `lint-call.yml`'s `make-gates` leg
  already runs them against every caller — a skip that cannot skip, a check that cannot fail,
  a blocking CI leg with no local mirror, and a scope narrower than the gate. #873 walked
  straight past all four: six repos probed for a **global** `markdownlint-cli2` that nothing
  in their bootstrap installs, so on an ordinary box the guard fired every time and the
  target skipped — correctly, at exit 0, forever. R3 could not see it because the Makefile
  plainly spelled the tool; R1 could not, because the skip was honest. **A local mirror of a
  blocking gate that never runs is not a mirror**, and the four existing rules all judge a
  target that runs. R5 judges _which_ linter runs: an invocation must carry
  `markdownlint-cli2@` plus a version, because the gate installs `MARKDOWNLINT_VERSION` from
  the vendored `core/scripts/tool-versions.env` and a global binary is whatever npm last put
  there — so a rule that changes across a bump reds a required check against a green local
  run. Proven on the real thing in both directions: R5 fires on all six pre-#873 Makefiles,
  naming each repo's own target (`markdown`, `md`, `lint-md`), and is silent on all nine
  post-#873 plus Core — **green on arrival**. Two deliberate exclusions, both the
  prose-is-not-a-command rule `tool_runs` already applies fleet-wide: a comment naming the
  bare binary it replaced is not an invocation (every converged recipe carries one, and a
  gate that reds its own rationale gets turned off), and a _quoted_ invocation reads as prose
  — which under-checks `dotfiles-MacBook`, the one repo that writes its pin that way, and is
  pinned regardless. `test/90-policy-gates.sh` pins all of it, including the historically
  honest pair: the post-#38 Debian recipe is clean under R1–R4 **and** a finding under R5,
  which is exactly the eighteen months #873 spent invisible.

- **`audit-core.sh` §5k — the bash 3.2 floor is a gate now, not ten comments (#874).**
  `PORTABILITY.md` §1 has put the shell floor at bash 3.2 since it was written, because macOS
  ships 2007's bash and the audit matrix runs a `macos-latest` leg. **Ten** scripts here carry
  a comment saying so — `audit-core.sh`, `gen-theme.sh`, `gen-aliases.sh`, `parity-check.sh`,
  `check-modern.sh`, `nvim-reachability.sh`, `update-plugins.sh`, `lib/common.sh`,
  `lib/core-lock.sh`, `research/lib/atuin-db.sh`. Ten comments and zero checks, so the
  convention was enforced only by a CI leg that answers in seventeen minutes, on one platform
  of four, after the fact. #871 is what that costs: it added one `mapfile` call and **every**
  local gate stayed green — the line is valid syntax so §3's `bash -n` passes, ShellCheck does
  not model bash versions so §5 passes, the suite runs on bash 5 here so §10 passes — and the
  ubuntu, alpine and arch legs passed too. macOS alone failed, and took the whole behavioural
  section down with it (`pass 388 skip 17 fail 1`). §5k is four seconds and runs everywhere.
  It enforces `PORTABILITY.md` §1's banned table **entry for entry**, so the doc and the gate
  cannot disagree — the array-reading builtins, associative arrays, case-conversion expansion,
  `&>>`, `|&` and `wait -n` — and the finding names the construct, because they fail
  differently and two of them (`&>>`, which bash 3.2 parses as a control operator and so
  **backgrounds** the command, and `wait -n`, which silently waits for _all_ jobs) fail with
  no error at all. The judgment is one testable function, `_core_bash4_hits`
  (`scripts/lib/common.sh`), driven by `test/20-scanners.sh` in both directions across
  thirteen cases — the same split as the `_core_pipefail_hits` and `_core_return_trap_hits`
  scanners beside it. **Green on arrival**: 92 tracked shell files, zero findings, which is
  the property #748's ledger insists on. Three narrowings are deliberate and documented rather
  than quietly absent, because a gate that fires on working code is one someone turns off:
  comments are stripped (nine of those ten references are prose _about_ the rule, and a gate
  that reds its own documentation would not survive the week); `typeset -A` is out of scope
  because it is the **zsh** spelling and `test/65-functions.sh` alone embeds ten legitimate
  `typeset -gA` lines for a zsh child; and `|&` requires a following space, because the bare
  two-character sequence occurs five times in this tree inside awk regexes and bracket
  expressions. `PORTABILITY.md` §1 now says the table is a gate and names what it
  under-checks.

- **The README hero gif is dated against the tape that renders it (`--check-render`, #698).**
  #862 rewrote `assets/demo.tape` to film a `dotfiles-core` checkout — #698's first finding,
  that the keystone repo's hero was shot inside a `dotfiles-MacBook` tree — and the tape has
  been right ever since. **The gif was never re-rendered.** `assets/demo.gif` at HEAD is
  byte-for-byte the blob committed on 2026-07-06, two months before that rewrite: it still
  walks `~/code/dotfiles/dotfiles-MacBook` through `z dotfiles` and `core help`, commands the
  current tape does not contain. `README.md`'s `[product-screenshot]` points at that file, so
  the defect #698 was filed about is still on the front page.

  Both gates were green over it, and correctly so — §9j compares the tape to
  `assets/hero.tape.in`, §9k weighs the gif's bytes and checks it exists, and **nothing tied
  the gif to the tape**. A generated script whose OUTPUT nobody dates is generated in name
  only: the property `assets/README.md` advertises — "re-run the command after any prompt or
  tooling change and the hero updates" — was the one thing neither gate checked.
  `gen-hero-tape.sh --check-render` (`make check-hero-render`) now checks it, and names both
  ends: `assets/demo.gif is STALE — rendered 51b691b (2026-07-06), but assets/demo.tape was
  rewritten later 202d632 (2026-09-04)`.

  **Git history is the clock, not mtime** — mtime does not survive a clone, so on a fresh CI
  checkout every hero would date to the second it was written. The audit job already takes
  `fetch-depth: 0`, and a tree without usable history SKIPS LOUDLY (exit 3) instead of passing
  green because the evidence was absent, which is #821's standing lesson. The working tree
  outranks history in both directions: an uncommitted gif was just rendered here and passes,
  while a modified tape beside a clean gif is exactly the defect and fails.

  **Deliberately not wired into `audit-core.sh` yet.** The check is correct and red today, and
  greening it needs `vhs` on a host matching the row — so landing it as §9l is a one-block
  follow-up once `assets/demo.gif` is re-rendered, rather than blocking every unrelated
  `make sync` in the meantime.

### Changed

- **`PARITY.md` gives every claim its own row, so the coverage gate that was row-level is now
  claim-level (#809, out of #682/#807).** `parity-check.sh` proved that every `aligned` row
  had a needle. It did not prove that every claim _inside_ a row did — and a row whose cells
  named several triggers was not forced to carry several needles. **That is exactly how
  `Alt+C` survived**: `PARITY.md` claimed `Alt+Z` _and_ `Alt+C` while the needle tested only
  `Alt+Z`, and the gate ran green for years. #807 removed the false claim; the mechanism that
  let a row outgrow its needles was untouched.
  **Fixed by moving the table, not the gate.** Word nav becomes two rows, and each utility
  function and fuzzy-git verb becomes its own row — so row-level and claim-level coincide and
  the existing one-to-one gate reaches every claim with **no new machinery**. 20 aligned rows
  became 29; `CHECKS` row-keys move with them.
  **The rejected alternative is recorded, because it looks like the obvious one.** #809
  proposed declaring a claim **count** per row (`<!-- claims:2 -->`) and asserting it against
  the needle count, and called it the option that "catches the widening case exactly". It does
  not: the count only fires if whoever widens the cell also bumps it. Widen it and leave the
  number alone — which is precisely what the `Alt+C` author did with the needle — and the gate
  stays green. It gates count-vs-needles, not widening. Splitting rows instead makes the
  natural editing act, _add a row_, the act that is already gated.
  Still ungated, and now said plainly in both the file and the script instead of deferred to
  an issue: a cell that grows a second trigger **in place**. Nothing short of a
  machine-readable claim list catches that, and `PARITY.md` is written for people first — what
  changed is that there is no longer a multi-claim row there to imitate.
  Two rows keep several checks and are not multi-claim rows: **History search** and
  **Maintenance**, where _one_ claim needs several pieces of evidence. The distinction is now
  written down where the row-key convention is defined.
  `90-policy-gates.sh`'s parity fixtures re-anchor from `Word nav` (a row this change splits)
  onto `Autosuggest toggle`. A fixture whose anchor stops matching inserts nothing, leaves the
  gate green, and passes every negative case for the wrong reason — so the anchor deliberately
  sits on a row with no reason to move.

### Fixed

- **The maint runner's stdin-discipline claim counted one site and there were two, and three
  network steps had no ceiling at all (#899, out of #820 F1/F4).** `maint/dotfiles-maint.sh`
  is a file whose comments are its contract, and one of them said the `mise outdated` probe
  was "the one command in the run that inherits the caller's stdin". It never was: the
  zsh-plugin loop is not a `step()` call either, and its `git fetch`/`git pull` put **stdout
  and stderr into `$LOG`** — invisible _and_ blocking, which the file itself calls the worst
  shape available.
  **The repair is not another `</dev/null`.** git asks for credentials on `/dev/tty`, not
  stdin, so an EOF leaves the prompt exactly where it was. `export GIT_TERMINAL_PROMPT=0` is
  what actually answers it, and it is set for the whole runner rather than per call site
  because the git invocations are not all ours — TPM shells out to git for every plugin it
  clones. Left honest rather than half-fixed: an SSH remote whose key wants a passphrase
  prompts through **ssh**, which that variable does not reach; the new ceiling bounds it.
  **F4 is a risk, and it is treated as one.** `step()`'s tty arm pipes through `tee`, which
  returns only when _every_ writer closes the pipe — so a step leaving a background process
  on stdout blocks `maint-run` after its own work is done, in the very command the tty arm
  exists to stop looking wedged. Nobody has reproduced a specific step leaking the fd, so the
  fix is a ceiling rather than a redesign of the mirror: `_to` on `brew cleanup` and the two
  TPM steps (the likeliest to leave a tmux server holding the pipe), plus new
  `MAINT_GIT_TIMEOUT` and `MAINT_TPM_TIMEOUT` knobs.
  **The new test asserts an inventory in both directions, not three spot checks.** It derives
  the set of `step()` calls with no ceiling and compares it to the set allowed to have none —
  so a fourth unwrapped network step fails, and wrapping a listed one fails too. The four that
  stay unbounded are declared with reasons: byte-compilation is local CPU, and `system:
  refresh`/`upgrade`/`cleanup` are privileged package-manager **transactions**, where a
  ceiling would trade a slow run for a half-configured box. Neither finding is reproducible in
  the suite — F1's live case needs a remote demanding credentials, F4's needs a step that
  actually leaks the fd — so the assertions are textual, and say so.
- **`audit-core.sh` §1c walked other sessions' worktrees, so `make audit` reported 1002
  findings about files no commit here owns (#905).** `_core_claude_untracked_hits` answers
  "is a file sitting under `.claude/` that git will never ship" by walking the filesystem —
  it has to, because its whole subject is the file `git status` refuses to mention. Claude
  Code parks a full checkout at `.claude/worktrees/<name>/`, so the walk descended into
  every other session's tree and reported all of it: `pass 431 skip 1 fail 1004`, of which
  **1002 were other people's worktrees** and none were about the tree under test.
  **This reds only where it is required to be green.** CI checks out the repo alone and has
  no worktrees, so the gate passed on all four platforms while being unusable on a
  maintainer's machine — the one place `RELEASE-RUNBOOK.md` §1.1 step 0 demands a green
  `make audit` before a tag. The remedy each finding printed ("negate it in `.gitignore`")
  was wrong twice over: those files are already tracked at their real path, and nothing in
  this checkout can change a verdict about another one.
  `_core_nested_worktrees` asks **git**, not the filesystem — `git worktree list
  --porcelain` is the registry git maintains itself, so a vendored `core/` or a stray
  directory cannot be mistaken for a checkout — and §1c `-prune`s what it names. Pruning
  rather than filtering afterwards is the point: the walk spends a `git check-ignore` per
  file, so descending into a worktree bought a thousand subprocesses to produce a thousand
  wrong answers (3.1s → 0.02s on the real tree).
  **Not `_audit_ls`, which is how #906 fixed the same blind spot one function over.** That
  scan could switch to git-aware discovery because it hunts shippable consumers; this one
  cannot, because every git-derived listing returns nothing for an ignored file and would
  turn the gate green by seeing less. The two halves of #905 needed opposite fixes.
  The behavioral cases assert **both directions against the same tree**: a hidden file
  inside the nested worktree is not a finding, and the host's own hidden file still is —
  so the cheap wrong answer (stop walking `.claude/`) fails rather than passing quietly.

- **`gen-theme.sh`'s reverse scan walked the filesystem, so it audited other repositories
  (found while auditing #904, never filed).** `preflight()`'s reverse half — the one that
  catches a `core:theme:gen` marker the registry does not know about — discovered files with
  `grep -r . --include=…`, excluding only `.git/` and `scripts/`. A filesystem walk does not
  consult `.gitignore`, so it descended into `.claude/worktrees/`, where Claude Code parks a
  full checkout per session: **57 phantom failures against a tracked tree with no drift at
  all**, on any box with a worktree present.
  The failure mode is the reason this is a `fix` and not a tidy-up. `make audit` printed
  `gen-theme.sh --check could not run (exit 2) — the drift gate checked NOTHING this run`
  and `the real tree has drifted — run: make gen-theme` **together**, and the second is
  actively harmful advice: the tree had not drifted, and regenerating consumers from a scan
  polluted by unrelated checkouts is worse than the gate not running at all.
  The primitive was already here and the comment above the scan already **claimed** it —
  "_audit_ls-style discovery so an UNTRACKED consumer about to be committed is caught too".
  `_audit_ls` is `git ls-files` plus `git ls-files --others --exclude-standard`, which keeps
  exactly the untracked-consumer property that motivates the scan while inheriting git's
  exclusions (`.claude/*` is ignored). The code was imitating its own comment.
  Note what this is **not**: a switch to plain `git ls-files`, which lists only TRACKED files
  and would silently drop that property — trading a loud wrong answer for a quiet one. The
  new `_theme_scan_files` therefore keeps a filesystem fallback, and that fallback is **not**
  belt-and-braces: `scripts/test/40-gen-theme-aliases.sh` builds `$SANDBOX/themerepo` by hand
  with no `git init`, so git-only discovery would enumerate zero files there and report
  success — coverage loss reading as health, the exact failure this preflight exists to end.
  The git path is taken only when the work-tree root **is** the directory being scanned, so a
  fixture under a `$TMPDIR` that happens to sit inside another repo cannot inherit its list.
  `audit-core.sh:1602` is the only other recursive walk in the gate scripts and does **not**
  share the blind spot — it targets `$HERE/zsh`, a tracked subdirectory, not `.`.

- **Two openSUSE claims in `PORTING-MATRIX.md`'s footnotes, from the
  `/os-package-availability` routine (dotfiles-openSUSE#164).** Both are footnote prose, not
  matrix cells, so nothing generated moved and no `make gen-porting-matrix` run is implied.
  Both were re-verified against OBS's anonymous API before editing — it answers on **binary**
  package names, which is what `zypper in` matches, so it is the index that decides these:
  `.../_repository?binary=<name>`, returning a `<binary filename="…rpm" size="…"/>` on a hit
  and a zero-size stub on a miss.
  **Footnote ⁵ — the tree-sitter shared library is `libtree-sitter0_26`, not
  `tree-sitter0_26`.** `binary=tree-sitter0_26` resolves on **none** of the three openSUSE
  targets (Factory, and the Backports ∪ SLFO unions behind Leap 16.0 and 16.1);
  `binary=libtree-sitter0_26` resolves on all three, at 0.26.8. Nothing installs the library,
  so nothing was broken — but that footnote exists **precisely** to stop the next reader
  reaching for a wrong name, with the dotfiles-openSUSE#113 autopsy (`tree-sitter-cli`, the
  Arch/Alpine split name, cargo-built on every box for want of the right one) two sentences
  above it. A signpost that hands the reader the same class of wrong name it is warning about
  is worse than no signpost. The same word was wrong in `dotfiles-openSUSE`'s own
  `install/packages.txt` comment, fixed there in the same pass.
  **Footnote ¹⁰ — difftastic's `openSUSE` is Tumbleweed-only.** `binary=difftastic` resolves
  on `openSUSE:Factory` and on **none** of the four Leap 16 sources (Backports SLE-16.0 and
  SLE-16.1, SLFO 1.2 and 1.3), so on Leap the documented route is the footnote's own
  `cargo install difftastic`, not `zypper`. The **cell** is right as it stands — the column is
  Tumbleweed-named by the convention footnote ¹⁸ states — and the footnote is where the
  qualification belongs; its neighbour ²⁴ already does exactly this for lnav, which is
  Tumbleweed-only for the same reason and correctly labelled.

- **Two silent-failure shapes in the gate scripts, from #820's shell review (F2, F3).** Both
  reproduced before fixing, because a report is a claim until it is run.
  **F2 — `gen-theme.sh`'s PARITY.md style guard anchored at column 0.** CommonMark allows one
  to three leading spaces on a table row, so indenting PARITY.md's Theme row made
  `grep -qE '^\| (Theme|FZF palette) '` go false — and because the block only fires _"when
  PARITY.md exists AND names a style"_, the cross-repo style contract **stopped being checked
  with `gen-theme --check` still green**. Silent-disable, not a false alarm, which is the
  worse direction. It is exactly the bug #682 fixed in `parity-check.sh`'s own row parser, in
  a sibling that did not get the memo. Four cases now pin both directions: 0–3 spaces is a
  row, four is an indented code block and still ignored.
  **F3 — `parity-check.sh` parsed every pipe table in the file.** It took `cap = $2` and
  `status = $(NF - 1)` from any row and skipped only separators, so tabulating PARITY.md's
  status vocabulary — prose today, valid Markdown, passes markdownlint — would parse
  `aligned` as a capability. Reproduced: the old parser reported ``row `aligned` has status
  `the` ``, on a **blocking, deliberately un-scope-guarded** gate, with a message pointing
  nowhere near the cause. The header now **arms** the table rather than being skipped: a
  table whose first column is not `Capability` is not a contract table.
  Worth recording that the first fix for F3 **introduced a second bug of the same class** —
  making a 4-space line clear the table state dropped every row after it, silently reducing
  coverage. The existing case 7 caught it, which is the argument for pinning both directions
  of a bound rather than only the one you are fixing.

- **Five doc-consistency findings from #811's sweep, verified live before fixing.** The
  routine reported nine; four had already been closed by work since (#885 took the
  `tree-sitter-cli` hedge, the Gentoo `ouch` prose is past-tense and correct, and the
  generated package-manager table self-corrected once #686 made it render from
  `os/*.capabilities`). These five were still true:
  **D7** — `PORTING-MATRIX.md`'s footnote 35 said Fedora's refresh is `dnf check-update`
  while the **generated cell** two hundred lines above it and `fedora.capabilities` both say
  `sudo dnf check-update`. The two halves of one file disagreed, which is the shape that
  becomes possible once half a file is generated and half is not.
  **D8** — footnote 37 explains at length why Gentoo's `count-pending` is a real resolve
  rather than `eix -u`, and never says what the cell **is**: `gentoo-pkg-pending`, a wrapper
  `dotfiles-Gentoo` ships. It is the one row whose declared value is a script rather than an
  invocation, because the `-1` sentinel cannot be expressed as a pipeline.
  **D5** — `PORTING-MATRIX.md` called Offense _"the one repo that isn't stamped from
  Fedora"_ while two other sites in the same file correctly say Offense **and** macOS.
  **D4** — `ARCHITECTURE.md`'s repo table gave `dotfiles-Offense` an _"apt OS layer"_. It has
  no `os/` directory at all; it is a pure role layer taking its OS band from
  `dotfiles-Debian`.
  **D9** — `core.vendor`'s same-repo line citations had rotted. The report named two; there
  were **four** — `zsh/30-functions.zsh:765` (actually `:1224`), `zsh/02-capabilities.zsh:114`
  (`:126`), `zsh/55-maint.zsh:488,528` (`:462,503`) and `zsh/60-update.zsh:762` (`:526`). Paths
  are what `audit-core.sh` §1e enforces, and every path was right; the line numbers are
  checked by nobody, which is why they drift.

- **Minted tokens carried the installation's full grant set; every consumer scopes its verbs
  now (#830).** `repositories:` bounds **where** a token works and `permission-*` bounds
  **what** it may do there — independent axes, and only the first was ever set. So the
  `notify-web` dispatch held a token that could rewrite `dotfiles-web`'s workflows in order
  to `POST` one `repository_dispatch`. All five mint steps are narrowed to what their job
  actually calls:
  `notify-web-call.yml` and `notify-web.yml` take **`contents: write`** and nothing else —
  that is precisely what `POST /repos/…/dispatches` needs. `freshness.yml`'s two mints take
  **`contents` + `pull-requests`**: they push a bump branch and open its PR, and they set
  neither `owner:` nor `repositories:`, which already scopes them to this repository.
  `sync-fanout.yml` takes **`contents` + `pull-requests` + `workflows`**, and keeps its
  deliberately unbounded reach — the install list is the one place scope lives, and a second
  copy of `scripts/os-repos.txt` there would drift and 403 a newly-added repo.
  **`workflows: write` is the interesting one.** `sync-fanout` genuinely needs it: a sync
  branch can carry `.github/workflows/*` pin moves and GitHub refuses the _whole_ push
  without it. `freshness.yml` deliberately does **not** take it — a pin bump touches `zsh/`
  and `nvim/lazy-lock.json`, never workflows, so if that ever changes the push fails loudly
  rather than the token having quietly been able to rewrite CI all along. That asymmetry is
  the point of scoping rather than pasting one block everywhere.
  **Under-scoping fails loudly**, which is the failure mode to prefer here: a missing verb
  is a 403 at the call site, never a silent downgrade. `GITHUB-APP-AUTH.md`'s two
  known-gaps bullets said the opposite and are replaced by a per-consumer table; the
  new-consumer template already told newcomers to scope, so it needed no change — it was
  the existing consumers that had not caught up.

- **`PORTING-MATRIX.md`: the openSUSE `uv` cell asserted a name for a package the repo does not
  install, and the file was not a prettier fixed point (#836).** Two of the five findings that
  issue parked while wiring the generator.
  The `uv` row's openSUSE cell names `python3-uv` as an asserted literal in `PKG_ROWS`, but
  `dotfiles-openSUSE/install/packages.txt` carries no `uv` at all — Arch, Alpine and Gentoo do
  install theirs. So the cell now carries **²¹ ("available, not installed")**, which is the
  convention the matrix already has for exactly this, and footnote 30 says so rather than
  leaving the reader to infer it from a name that reads like an install. The derivation check
  in `test/65-functions.sh` still passes because ²¹ here is **cell-level**, not row-level, and
  a cell-level case belongs to the repo whose cell it is — the rule that array's own comment
  states.
  And the file is now a **prettier fixed point**, which it was not on `main`. That is not
  cosmetic: Core's nvim formats markdown with prettierd on save, so anyone who opened this file
  got a surprise 19-line reformat mixed into their diff — the mechanism that let the desktop
  `PARITY.md` pair drift 3.5 KB apart in #693. Two of the three spots were **multi-line code
  spans inside indented list items**, where prettier's de-indent silently changes what the span
  contains; both are rewritten to single-line spans, so the fix removes the ambiguity rather
  than accepting a reflow of the rendered text. The third was table padding around `✔`, now
  accepted. `gen-porting-matrix.sh --check` and `prettier --check` are both green, and the
  generator reproduces prettier's padding exactly — so the two cannot fight on the next
  regeneration.
- **`theme/palette.toml` said nobody consumes it; `dotfiles-Windows` has since 2026-08-31
  (#798).** The file's header and `audit-core.sh`'s `META_ALLOWLIST` comment both justified
  keeping it out of the shipped set with _"nothing symlinks it and no OS repo reads it out of
  `core/`"_. That premise no longer holds: dotgibson/dotfiles-Windows#229 vendors **this
  file** — `theme-sync.ps1` copies it beside a `theme/.core-ref` pinning the Core commit, CI
  hash-gates the pair (`tests/Assert-ThemeParity.ps1`), and its own `gen-theme.ps1` renders
  nine blocks across `powershell/core/` and `psmux/` from it. **Not** added to
  `core.manifest`, which is what the issue asked about and offered to be argued out of: the
  manifest is the set `sync-core.sh` materializes into each OS repo's `core/`, so a row there
  would ship a generation-time input into nine trees where nothing reads it, in order to
  describe a dependency held by the **one repo that has no `core/` at all**. That makes the
  manifest less true, not more. The dependency is recorded where it can be acted on instead —
  in the file's own header and the allowlist comment, both of which now say plainly that
  moving or renaming the path **breaks a downstream CI gate**, which is a fleet contract
  change and not a local refactor. `desktop/PARITY.shared.md` is the same shape and the
  precedent. (Checked while here: Windows' pin `a85622e` is current — `theme/palette.toml`
  has not moved since.)
- **`PARITY.md`'s accent `gap` was right but imprecise (#798).** pwsh is no longer missing the
  _primitive_: `Get-DotAccentSpec` (dotgibson/dotfiles-Windows#229) is generated from this
  same palette — truecolor tier keyed on `$COLORTERM` exactly as `zsh/05-ui.zsh` does, both
  raw-SGR and bare-spec forms mirroring Core's two rendering paths, and the 256-colour
  fallbacks carried verbatim including their deliberate SGR-vs-spec disagreement. **Nothing
  consumes it yet**, so the row stays a `gap` — this file's bar for `aligned` is that both
  shells actually _render_ with the capability, not that both could. Promoting it would mean
  a needle proving the function _exists_, which is the certifies-less-than-it-looks-like
  shape that section exists to stop. What closes the row is a pwsh consumer, not another
  assertion here; the note now says which.
- **`new-os-repo.sh`'s pin floor was v4.1.0 and should have been v4.15.1 — the scaffold and
  its own recipe disagreed (#851).** The floor existed for the `repos:` footer the recovery
  verdict reads, which arrived in v4.1.0. But the scaffold **materializes** `core/`
  (`core_vendor_materialize` — a plain tree with no subtree metadata), and releases v4.1.0
  through v4.15.0 sync with `git subtree pull --squash`, which on such a tree dies with
  `fatal: can't squash-merge: 'core' was never added` — **reproduced**, not inferred. So on
  every pin in that range the registration command the scaffold **itself prints** could never
  stamp `core.lock`. v4.15.1 is the first release whose `sync-core.sh` materializes
  (`_sync_materialize_core`, _"replaces `git subtree pull --squash`"_); v4.15.0 still pulls —
  confirmed by reading both tags. The constant is renamed `_footer_floor` → `_pin_floor`,
  since it now encodes two constraints and the newer one binds, and the refusal message names
  **the mechanism** rather than the footer: the old wording was true of v4.0.2 and false of
  v4.10.0, and a refusal that misdiagnoses itself sends the reader to fix the wrong thing.
  `v4.10.0` accordingly **moves sides** in `test/35-new-os-repo.sh`'s F7c lists, from accepted
  to refused, which is the regression the case now pins. The floor is restated in `--help`,
  the two stale in-script references, and the three recipe copies (`ARCHITECTURE.md`,
  `VENDORING.md`, `PORTING-MATRIX.md`). The v7.0.0 entry's "since v4.1.0" line is **left
  alone**: it was true when written, and the historical record is not the place to fix a
  floor.
- **Two generated claims in the scaffold overstated what they describe (#851).** The
  generated README said `test.yml` "runs on every push"; its filter is
  `branches: [main, master]`, so a feature-branch push with no PR open runs **nothing** — it
  now says default-branch pushes and pull requests, and names the filter. And the generated
  `test/check-links.sh` header said it "needs only bash", while its mise-seed assertion shells
  out to `git hash-object` and the body uses `find`, `ls`, `readlink`, `cksum`, `awk`, `sort`
  and `stat`. Both are true of any runner that could have cloned the repo, which is the point
  worth making — so the header now says that, instead of a portability claim that is not quite
  true.
- **`core help` understated `core-whatsnew`'s interface — one of its two flags (#806).**
  The verb takes `--full` **and** `--all` (`_core_usage` and `zsh/completions/_core-whatsnew`
  both say so), but the cheat sheet's row keyed it `core-whatsnew [--full]` and the front
  door's dispatch comment did the same. `aliases.md`'s row was the site the issue named, and
  it is already right — #834 made that table _generated_ from the `_core_help` call, which
  carries both flags — so the hand-written surfaces were the ones left behind, which is the
  argument for generating them in the first place. **The flags moved to the description, not
  into the key**, on purpose: `_core_help_render` sizes its key column to the widest key, so
  spelling both out there would have shifted every row on the sheet eight columns right to
  document one verb. The index already elides flags this way (`core-status`, whose real usage
  takes `[--json]`), and the description now names both — strictly more than the key said.
- **`PORTING-MATRIX.md` footnote 5: `tree-sitter-cli` is maintainer-needed on Gentoo, and the
  arch claim was narrower than the truth (#780).** The footnote closes with its own standing
  instruction — _"re-query this row on every stamp"_ — and this is that re-query, re-confirmed
  against the live `.json` endpoint on 2026-09-06. `dev-util/tree-sitter-cli`'s `metadata.xml`
  carries **no `<maintainer>` element at all**; availability is unchanged — 0.26.11 is still
  stable and still clears the ≥ 0.26.1 floor — but orphaning is what precedes a treeclean, and
  `dotfiles-Gentoo` already carries exactly this hedge on `w3m` and `lnav`. And "stable on
  amd64" understated it: the keyword line is
  `amd64 arm arm64 ~loong ~mips ppc ppc64 ~riscv ~s390 ~sparc x86`, so it reads as an
  amd64-only guarantee while `dotfiles-Gentoo` is tightening exactly what it claims per-arch.
  Two things added beyond the report: **0.26.12 exists but is `~`-keyworded on every arch**,
  so a future reader does not "update" the claim to a version nothing has stabilised; and the
  warning that `packages.gentoo.org`'s rendered arch table is unreliable — it reported
  `app-shells/starship` as having no stable amd64 keyword where the ebuild says
  `KEYWORDS="amd64 arm64"`. The `dotfiles-Gentoo` half is already done
  (dotfiles-Gentoo#145), and its `packages.txt` comment points **here** for this half,
  because `core/` is vendored read-only there and the same edit made in the OS repo is
  overwritten on the next `make sync`.
- **The recovery runbook's caller-discovery grep could not see Core's own caller (#832).**
  `GITHUB-APP-AUTH.md`'s Recovery section — the incident path — tells the operator to
  **derive** the caller list rather than trust a written one, and then handed them
  `grep -rn 'notify-web-call.yml@' ../dotfiles-*/.github/workflows/`, which matches only the
  **remote** `uses:` form. Core's own caller is **local**: `release.yml` reads
  `uses: ./.github/workflows/notify-web-call.yml`, no `@`. Step 6 then says to use step 5's
  derived list, so an operator following the procedure omitted Core's `release.yml` mapping
  and the release-path dispatch lost its restored fallback the moment step 7 disabled the
  App. **This was a defect in a fix**: the "derive it, do not freeze it" instruction was
  itself added to close an earlier review finding, so the derivation was made _authoritative_
  before it was made _correct_ — worse than the frozen list it replaced, because the next
  step instructs the operator to trust it. Both commands now anchor on `^\s*uses:` and match
  either form (which also skips the reusable's own documentation comment, not a caller), and
  the step-2 visibility grep is held to the same standard. **Both commands are plain POSIX
  BRE with two `-e` patterns, not one `-E` alternation**: the first draft used the
  alternation and it did not match under **busybox grep**, which the Alpine audit leg caught
  — and Alpine is a machine in this fleet, so it is a box someone could be running this
  recovery from. A recovery command that works on the maintainer's laptop and not on Alpine
  is the same class of defect as one that cannot see Core's own caller. **A derivation nothing exercises
  is a frozen list that looks live**, so `test/90-policy-gates.sh` now reads the patterns
  _out of the runbook_ and runs them against Core's own tree, asserting they find the caller
  that is actually there — with Core's local caller asserted separately, so the check cannot
  pass vacuously if that caller ever goes away. Verified: the old pattern fails it.
- **`GITHUB-APP-MIGRATION.md`'s permission-status pointer led to a section that did not hold
  it (#832).** The frozen record defers _"whether that is still true"_ about verb scope to
  _What the fleet runs today_ — a section covering **repository** scope only, while the live
  statement that consumers still inherit the installation's full grant set sat two sections
  away under _Adding a new consumer_. A reader following the deferral could not determine
  whether the historical limitation still applied, which is the one thing the deferral exists
  to let them do. Fixed at the target rather than the pointer: _What the fleet runs today_
  now carries **"Neither shape scopes verbs"** — the dimension the migration did not narrow,
  still true, still tracked as #830 — so the section that claims to describe today stops
  omitting it.
- **Word nav's pwsh half stops being a skip — the gate's last unasserted row (#849).**
  `scripts/parity-check.sh` carried two `-` sentinels, both on **Word nav**: pwsh got
  `Ctrl+←/→` from a PSReadLine **default**, so there was no string to grep and the check
  asserted Core's half and _reported_ pwsh's rather than inventing a needle that could not
  fail. dotgibson/dotfiles-Windows#238 binds the chords explicitly, so both halves are now
  real assertions — `count:2:-Key Ctrl+RightArrow -Function NextWord` and its `Ctrl+LeftArrow`
  / `BackwardWord` mirror. **`count:2` is the point**, not decoration: a bare `-Key` under
  `-EditMode Vi` binds the **Insert** table only, so a single binding would leave `vicmd`
  resting on the very default the upstream fix exists to stop depending on — the mirror of
  Core's own `bindkey -M viins` + `bindkey -M vicmd` pairs. pwsh binds `NextWord`, **not**
  `ForwardWord`, and that is not drift: PSReadLine's `ForwardWord` moves to the _end_ of the
  current word while `NextWord` moves to the _start_ of the next one, which is what zsh's
  `forward-word` does. The row stays honestly `aligned`; only the function _name_ differs.
  With its only user gone, **the sentinel machinery is retired with it** — the `pneedle == "-"`
  branch, the `UNASSERTED` counter and its qualified summary, `_core_parity_verdict`'s
  `ok-defaults` verdict and §9f's render arm for it. A verdict no run can return is a claim no
  test can hold to account. `skip_note` itself stays: the NOTE skip class has live callers in
  `gen-hero-tape.sh` and the bench gate, and `test/36-bootstrap-lib.sh`'s binding assertion
  now points at one of those instead of the §9f call site it used to guard. The Windows-present
  case in `test/90-policy-gates.sh` inverts accordingly: it now proves the run asserts **every**
  pwsh half and skips none, where it used to prove it refused to certify two.
- **The fleet's repo count contradicted itself — five sites said eight, the manifest says nine
  (#770).** `CODEOWNERS:1`, `audit-core.sh`, `.github/workflows/ci.yml` and
  `nvim/.../claudecode-nvim.lua` all described the fan-out set and were off by one
  (`sync-core.sh:293`, the fifth, had already been corrected). Two of them are Core files, so
  the wrong number reached nine repos on every sync. Fixed, and **the phrasing with them**:
  the fan-out claims now read _"the nine **Core-vendoring** repos"_ rather than _"nine OS
  repos"_, which is wrong in kind and not merely in count — two of the nine (`dotfiles-Offense`
  and `dotfiles-Defense`) are **Role** repos, and that ambiguity is exactly what made the drift
  self-renewing, since both numbers are right about something and the prose rarely said which.
  `PORTING-MATRIX.md` already modelled the phrasing; it is now the fleet's. §9m above keeps it.
- **`check-links.sh` verified `loader.zsh` and none of the modules it loads (#854).** The gate
  asserted seven Core-owned links, including `.config/zsh/loader.zsh`, and — since #853 —
  that each resolves to the _right_ file. But `blib_link_core` links the **whole** directory
  (`for f in "$dotfiles"/core/zsh/*.zsh`), and the loader then globs `NN-*.zsh` in the
  destination. So a bootstrap that wired `loader.zsh` and **none of the fragments** passed
  with the loader having nothing to load — a shell that starts clean and is configured with
  none of Core, certified as a healthy graph. `scripts/test-core.sh` already treats the
  complete flat set as load-bearing, so the contract existed; the gate just did not check it.
  **Derived, not listed**, and from the repo being checked rather than from Core's own tree:
  a hardcoded list drifts every time a module is added — the argument the loader's own glob
  and `test-core.sh`'s fragment glob already make — and the vendored `core/zsh` is right
  there, which is what `blib_link_core` itself reads. An **empty** derivation is a finding in
  its own right (exit 2, naming "nothing to load") rather than a quiet pass, because vacuous
  is the state this closes. Five cases, and the fake bootstrap in the suite was **itself an
  example of the incomplete graph** — it wired `loader.zsh` alone, and now runs
  `blib_link_core`'s loop verbatim so the stub cannot drift from the linker it stands in for.
  Verified against the fleet: `dotfiles-Fedora`, `-Offense` and `-Defense` each go from 7
  links checked to **21, fourteen of them derived fragments**, all green.

- **A linked-worktree OS repo was classified as "not cloned", and under `--strict` that skip
  was exit 1 (#850).** `sync-core.sh` asked "is this a clone?" with `-d "$path/.git"` at three
  sites — the staleness pre-flight, the parallel prefetch loop and the per-repo fan-out. A
  linked worktree (and a submodule checkout) has a `.git` **file**, not a directory, so a
  perfectly good target was skipped; once `--strict` (#848) turned a skip into a failure, a
  targeted sync over a worktree checkout did not merely under-report, it **refused**. The
  repository's established form is `-e`, and `resolve_repo_dir` — the helper every one of
  these call sites goes through first — already carries the comment explaining why. Swept the
  other three sites that ask the same question the same wrong way rather than fixing only the
  two the report named: `audit-core.sh`'s secret-scan policy adoption and its os.capabilities
  fleet coverage, and `scripts/fleet-coverage.sh`'s row loop, each of which would silently drop
  a worktree sibling out of a fleet count. There is now no `-d "$…/.git"` left in `scripts/`.
  `test/32-sync-core.sh` covers a real `git worktree add` target against `--strict`, asserting
  both that the run exits 0 and that "not cloned" never appears — verified red against the
  pre-fix script, which reports exactly the symptom in the report
  (`– dotfiles-Worktree (not cloned at …)`, `rc=1`).
- **The maint job's neovim step reported ✓ over a session in which nothing ran (#829).**
  `nvim --headless` exits **0** when a `-c` command fails — the error goes to stderr and the
  process still succeeds — so `step()` read a 0 and logged a green tick for a run that had
  updated no plugins, no parsers and no registry. `step()` was not at fault:
  `rc=${PIPESTATUS[0]}` is the right status to read; the problem was that the status carried
  no information about whether the commands ran. On an Ubuntu 24.04 box whose apt `nvim` was
  0.9.5, the config aborted at load on a 0.11+ option, `lazy.nvim` therefore never loaded,
  `:Lazy! sync` did not exist — and the step had been green for as long as the editor had been
  broken. It surfaced only because a stderr traceback happened to land in a terminal someone
  was reading; under the systemd timer, which is the designed mode, nothing would ever have
  shown it. **Every arm is now a `pcall` that records its failure, and a final `-c` turns a
  non-empty record into a real exit status with `:cq`** — the documented way to make nvim exit
  non-zero. The sentinel is fail-**closed**: an unset record means the setup `-c` itself never
  ran, which is the same false green in a smaller box, so that counts as a failure too.
  Reaches every OS repo that vendors Core, on every box, whatever the cause — a config error,
  a missing plugin, a renamed command all produced the identical false ✓.
- **`MasonUpdate` had never actually run in that step (#829).** mason.nvim is a _dependency_ of
  nvim-lspconfig / conform / nvim-lint, every one of which loads on a buffer event that never
  fires in a headless session — so `:MasonUpdate` did not exist there and `+silent! MasonUpdate`
  swallowed the `E492` on every single run since the step was written. Found while making the
  arms loud: with the failure recorded instead of silenced, the arm reds immediately. The step
  now `require("mason")` first, pulling the plugin in through lazy's require shim so the command
  exists; a live run confirms `Successfully updated 1 registry`. Same class as the `:TSUpdateSync`
  note already in that block — a `silent!` that outlived the command it was protecting.
  `test/73-maint-runner.sh` covers both directions against the **shipped** argv (extracted by
  sourcing the real step invocation with `nvim` stubbed, so a hand-written copy cannot drift):
  every arm runnable → 0, the `:Lazy` command absent → non-zero.

## [v7.0.0] - 2026-09-04

### Added

- **Helper adoption is a ratchet now, and `blib_user_bindirs_on_path` went 1/9 → 7/9 callers (#748).**
  `audit-core.sh` §5f has reported which OS repos are short of the `lib/bootstrap-lib.sh`
  contract since #516, as a bare fraction, deliberately advisory. `blib_user_bindirs_on_path
  1/9` sat in that report while the gap it names shipped a **live defect**: openSUSE's
  `bootstrap.sh` probed `command -v mise` for a mise that `mise.run` had written to
  `~/.local/bin` moments earlier — a directory only the **shell** layer prefixes, never the
  bash a bootstrap runs in — so both arms of its Go fallback missed, the `else` branch
  announced "needs a Go toolchain" on a box that had one, and the run exited 2 on **every**
  bootstrap. No gate could see it: a stubbed run installs nothing, so a check that a tool is
  present afterwards can never fail under a stub. `dotfiles-Alpine` carried the identical
  probe, harmless only because an apk-installed `go` won the first arm and the broken one was
  never reached. **A number nothing acts on is where a defect hides in plain sight.** So §5f
  now keeps a **ledger** of the `(repo, helper)` pairs that have adopted, and both movements
  block: a repo that **drops** a helper fails, and a repo that **adopts** one nobody recorded
  also fails until the ledger is edited — which is the only thing that ever tightens the
  ratchet. An unclaimed gap stays advisory, because most of the fleet is short today and a
  gate red on arrival is a gate someone turns off. Same shape as `gen-porting-matrix.sh`'s
  `PKG_ROWS`. The judgment is one testable function, `_core_helper_verdict`
  (`scripts/lib/common.sh`), driven directly by `test-core.sh` — replacing an assertion on
  the section's source text ("it contains no `fail`") that was green for the whole life of
  the bug it should have caught. **Adoption now means a call, not a mention**
  (`_core_helper_called`): the section read the fleet with a bare `grep`, which counted a
  _comment_ — so three rows were credited purely from prose (`dotfiles-MacBook` for
  `blib_note_fail` + `blib_failures_report`, `dotfiles-Fedora` for `blib_resolve_su`, now
  corrected to honest gaps), and since an adoption PR's shape is "add the call, explain why",
  deleting a call while leaving its paragraph would have kept the ledger green forever — the
  exact regression it exists to catch, invisible in the files it had just been taught to
  watch. Strings and **heredoc bodies** are excluded for the same reason, and the heredoc
  case is live rather than theoretical: `dotfiles-Arch`'s `usage()` heredoc documents
  `BLIB_DRY`, so its row would have gone on reading `ok` off help text alone if the two real
  references were ever dropped. The `--json` fleet-printf guard's hardcoded `NR>=860 &&
  NR<=1045` window is derived from the §5f→§5i banners now; it had drifted off the sections
  it was meant to cover and never reached §5g or §5h at all. `VENDORING.md` carries the
  contract. Six companion PRs adopt the helper — `dotfiles-Alpine` (the live twin),
  `-openSUSE` (retiring the local `_mise_bin` fork), `-Fedora`, `-Debian` and `-Offense`
  (retiring three hand-rolled `export PATH=` preludes) and `-Arch` — and the ledger records
  that state, so **land them before this one**. `dotfiles-Offense` also loses its exemption:
  the "role repos install no packages" reasoning was never true of a `--install` that does
  `pipx` and `go install` into `~/.local/bin`, which is exactly why it had hand-rolled the
  prelude. `dotfiles-MacBook` and `dotfiles-Defense` genuinely have no such probe and stay
  unadopted/exempt — which is why the headline reads **7/9 callers** rather than 8/9: seven
  repos call it, `dotfiles-Defense` is exempt (so 8/9 compliant), and `dotfiles-MacBook` is
  the one standing gap. §5f reports both numbers now, because collapsing them is what
  overstated the count in the first place.

- **The README hero is generated from one tape, and its bytes are capped (#698).** Ten public
  repos open with the same shields template and **no visual at all** — no `assets/`, no hero,
  no image — while the one repo that _has_ a hero is `dotfiles-core`, which nobody installs
  directly. Worse, that hero filmed the wrong tree: `assets/demo.tape` typed
  `cd ~/code/dotfiles/dotfiles-MacBook` from inside `dotfiles-core`. Nothing could catch it,
  because nothing derived the tape from anything — even though `assets/README.md` already
  asserted the property that makes the fix cheap ("re-run the command after any prompt or
  tooling change and the hero updates — no manual re-recording"). The tape is now **rendered**
  by **`scripts/gen-hero-tape.sh`** (`make gen-hero-tape`) from three sources:
  **`assets/hero.tape.in`** (the shared body — every command, every `Sleep`),
  **`assets/hero-repos.txt`** (the per-repo delta: the `cd` path and the one signature
  command) and **`theme/palette.toml`**. That last one closes a second defect in the same
  file: `Set Theme "TokyoNight"` was a **fourth place the theme was named by hand**, and the
  only one naming an upstream preset rather than the resolved table every other consumer is
  generated from — so the hero could stay "Tokyo Night" while Core's chrome moved. It is now a
  full `Set Theme { … }` block rendered from the palette, which means a palette edit reds the
  hero gate as well as §9d. `--check` is wired into **`audit-core.sh` §9j** with no
  environment SKIP: unlike §9h/§9i, the default scope is this repo's own files, so it can
  always answer.
- **A byte ceiling on the hero, because one heavy gif is a preference and ten is a policy
  (#698).** `assets/demo.gif` is 1.8 MB for a ~25-second clip, and `assets/README.md`
  documented the `gifsicle -O3 --lossy=80` remedy that nothing applied.
  **`audit-core.sh` §9k** (`make check-hero-size`) now weighs the file each tape's `Output`
  line names — following the tape, so a renamed output cannot slip past a hardcoded path —
  and fails over **2 MiB**. The template is shortened to the ~15 s its own header asks for:
  `CORE_NO_PAGER` and `GIT_PAGER=cat` in the hidden setup drop the four `q` keystrokes the
  old tour needed, which is most of the difference between ~27 s and ~13 s. **The committed
  `demo.gif` still predates the shortened tape** — re-render with `vhs assets/demo.tape` and
  optimize to bring it under the ceiling.
  The behavioral coverage moved with #699's split: it is now
  `scripts/test/42-gen-hero-tape.sh`, numbered beside the other generator suites (40 theme +
  aliases, 41 porting matrix + desktop parity). The tape captures at **24fps** rather than
  VHS's default 50, because the first shortened
  cut proved bytes track REDRAWS rather than seconds: at ~13 s against the old ~25 s it came
  out **bigger** (2.46 MB vs 1.84 MB), since GIF pays per changed pixel and this tour has
  four full-screen colour repaints where the old one had pager quits and a `clear`. The
  documented optimize pass gains `--colors 64`, which is visually free on a 20-colour
  palette.
- **The nine other heroes are registered, not yet rendered (#698).** `assets/hero-repos.txt`
  carries **ten rows** — this repo plus the nine Core-vendoring OS and role repos — and `make gen-hero-tape-fleet` writes the other nine tapes
  into their own checkouts. Their signature command is deliberately the _same three
  characters_ everywhere — `up -n` — because the point is what it **resolves** to: `dnf` on
  Fedora, `pacman` on Arch, `apk` on Alpine, `emerge` on Gentoo, and `zypper dup` (**not**
  `up`, the distinction that half-updates a box) on Tumbleweed. The trailing note is derived
  from each repo's own `os/*.capabilities` `PKG_UPGRADE`, so it can never claim a verb the
  repo does not declare. Rendering and committing those nine gifs, and adding the hero block
  to each README, is the **follow-up**, sequenced after `os.capabilities` (#667) exactly as
  #698 asks — nine heroes of the same Core verbs would be nine near-identical gifs.
  `dotfiles-Windows` is **deliberately not registered**, so those ten rows are not the ten
  repos #698 counted: its host layer is PowerShell and it vendors no `core/`, so the shared
  zsh body has nothing to say there. It stays the one public repo this change does nothing
  for, and a hero for it needs its own tape and recorder. The
  hidden `cd` carries `|| exit 1`: it runs inside `Hide`, so a checkout path that does not
  exist on the rendering box would otherwise print into unrecorded frames and film `$HOME` —
  the wrong-tree defect wearing a different hat, and invisible in the committed gif. Each OS
  row also types a **`proof`** line that prints the resolved verb, because neither of the two
  things that look like they show it actually do: the `# one verb → …` note is a _tape_
  comment VHS never renders, and `up -n` prints `via zypper` — the manager, not the verb —
  so neither can distinguish `up` from `dup`. The proof line reads `PKG_UPGRADE` and never
  applies it. Three further holes the review found are closed with it: a registry with no
  `.` row now exits 2 on both legs (deleting that row would otherwise leave every remaining
  row a sibling, every sibling out of scope, and both gates green over a tape nobody looked
  at), a **missing** `assets/demo.gif` now fails rather than skipping (`README.md`'s hero
  points at it; a sibling's stays a note skip), and the eight-line provenance banner is
  printed by bash rather than passed through `awk -v`, which the macOS one-true-awk rejects
  outright ("newline in string") while gawk and busybox awk accept. The registry is
  validated **whole, before anything is written**: a count-only check passed a row with an
  empty checkout (awk counts the empty span between two tabs), which rendered `cd  || exit 1`
  — and a _bare_ `cd` succeeds into `$HOME`, reintroducing the wrong-tree hero through the
  guard meant to prevent it; and a malformed row late in the file used to leave every tape
  above it already rewritten. Empty fields, duplicate repos and a bad `note:`/`caps:` prefix
  are all rejected up front, all findings at once — as are a `"` or a `>`/`<` in any field
  substituted into the template's `Type "…"` (a quote closes that VHS string; a redirection
  is real in the shell VHS drives), and a `.` row that films any **other** registered repo,
  which is #698's original defect restated as a machine check rather than a fixture. And
  substitution is literal (`index`/`substr`): awk's `gsub` expands `&` in the REPLACEMENT to
  the matched text, so a value like `check && report` rendered as
  `check @@SIGCMD@@@@SIGCMD@@ report` — `-v` protects a value on the way in, not on the way out.
- **Matching-host rendering is a checked precondition, not an assumption (#698).** Core reads
  the capability declaration **once, at shell startup**, from the _host's_ linked
  `~/.config/zsh/os.capabilities` (`zsh/02-capabilities.zsh`) — `cd`-ing into a repo does not
  switch it, and `up -n` probes `$PATH`. So an OS hero filmed on the wrong box records that
  box's package manager under a comment naming the row's: the Fedora tape rendered on a
  MacBook says `brew upgrade` while the tape says `dnf`, which is #698's wrong-tree defect
  moved from the filesystem to the environment. Every OS tape now opens, inside `Hide`, with
  `[[ $(_core_cap PKG_UPGRADE) == '<declared>' ]] || exit 1`, so a mismatched host **fails the
  render** rather than publishing a hero that contradicts itself. It costs the clip nothing,
  the guard and the visible note are derived from one declaration and asserted to agree, and
  a `note:` row gets a no-op. Both path columns are confined to their checkout too: write
  mode resolves the output as `$dir/$out` and atomically replaces it, so a row naming
  `../README.md` overwrote a file **outside** the target repo — an absolute path, a leading
  `~` and any `..` component are now refused, per path component so a legitimate
  `my..tape` still passes.
  `scripts/test-core.sh` covers the generator hermetically in **F11b**: the wrong-repo `cd`
  and the named-theme preset are both pinned as regressions, drift outranks an absent sibling
  (severity 2 > 1 > 3 > 0, which is not numeric order), a malformed registry row is exit 2
  rather than drift, the verdict survives a host with no working `diff`/`cmp` (#572), and
  both audit legs are asserted to actually be wired.

- **The desktop-bar parity pair is generated and gated, not asked nicely (#693).**
  `dotfiles-Windows/desktop/PARITY.md` and `dotfiles-MacBook/sketchybar/PARITY.md` were an
  admitted verbatim pair whose only mechanism was the sentence _"Edit both together"_. It did
  not hold — they sat **3.5 KB apart**. The split matters: ~4.4 KB of it was a one-sided
  Markdown reformat with no semantic content, and **947 bytes was a real Windows-only block**
  (the psmux battery-scale note) that had never been marked as a deliberate divergence. The
  shared contract is now authored once in **`desktop/PARITY.shared.md`** and rendered between
  the `<!-- desktop-parity:gen -->` and `<!-- desktop-parity:end -->` markers into both repos
  by **`scripts/gen-desktop-parity.sh`** (`make gen-desktop-parity`), the `gen-views.sh`
  idiom: everything outside the markers is hand-authored and untouched, which is where the
  psmux note now lives — labelled `deliberate` in the `aligned`/`deliberate`/`gap` vocabulary
  Core's own `PARITY.md` uses. `--check` is the drift gate, wired into **`audit-core.sh` §9i**
  and the weekly **`parity-check.yml`**, which now clones both desktop repos. An absent
  sibling is an environment SKIP (exit 3), never a green over an un-inspected copy. The source
  is deliberately a **prettier fixed-point**: Core's nvim maps `markdown = { "prettierd" }`,
  formatting one copy is the most likely way the pair drifted in the first place, and
  authoring the block in prettier's own output form makes that keystroke a no-op instead of
  drift. `desktop/README.md`'s "an identical copy sits in…" claim is corrected in the
  companion PR (dotgibson/dotfiles-Windows#242) — the two files are deliberately _not_
  identical. **Land the two companion PRs before this one:** they add the markers this gate
  reads, and until they do, a weekly run against fleet `main` would red on copies that have
  none. `scripts/test-core.sh` covers the generator hermetically — clean render,
  byte-identical blocks, preservation outside the markers, one-sided drift, absent and
  not-a-repo siblings, sticky severity, malformed markers, idempotence, a host with no working
  `diff`/`cmp`, an unwritable target, temp-file hygiene, the 0644 file mode an atomic rename
  would otherwise drop to 0600, an empty `--root`, and a box with no git — and pins the
  workflow's `--check`, without which the gate would rewrite the clones and pass forever. The
  verdict is `core_files_identical` (git-hash based), never `cmp`/`diff`: those ship in
  diffutils, which this fleet does not assume, and a missing binary exits non-zero exactly
  like "the files differ" (#572).

- **The hermetic `--links-only` gate is Core-owned now: `scripts/check-links.sh` (#852).**
  Four repos' `make check` ran the same block — make a throwaway HOME, run
  `bootstrap.sh --links-only` into it, assert the symlink graph Core's loader expects —
  and each of `dotfiles-Fedora`, `-Debian`, `-Gentoo` and `-openSUSE` carried its own copy
  (Arch, Alpine and the two Role repos run no links-only leg at all). They drifted the way
  copies do: the same defect turned up in **three of the four at once**. `HOME="$tmp"` alone is not hermetic,
  because `bootstrap.sh` resolves `CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"` and
  `lib/bootstrap-lib.sh` defaults `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME`,
  `XDG_DATA_HOME` and then `ZDOTDIR` the same way — and a `:-`/`:=` default applies **only
  when the variable is unset**. For anyone who exports `XDG_CONFIG_HOME`, the gate wired
  Core into their **live config tree** and then failed its own assertions, which look
  under the temp dir bootstrap never touched: it mutated the box it was only supposed to
  inspect, then blamed the tree. Reproduced on Fedora 44 — `zsh/`, `nvim`,
  `starship.toml`, `tmux`, `git`, `mise`, `lazygit`, `atuin`, `jj`, `sesh` and `tealdeer`
  all landed in the exported `XDG_CONFIG_HOME`. `dotfiles-openSUSE` had already found and
  fixed it locally and nothing could tell the others; the fix was then applied by hand
  three more times (dotgibson/dotfiles-Fedora#153, dotgibson/dotfiles-Debian#53,
  dotgibson/dotfiles-Gentoo#159). This is the last time it needs applying anywhere.
  One script, vendored through `core.vendor`, the same argument
  `scripts/check-capabilities.sh` makes for the capability schema. It scrubs the five
  variables the bootstrap path actually consults and passes the rest of the environment
  through (so `BLIB_SU=true core/scripts/check-links.sh` still works on a container
  without sudo), guards `mktemp -d` — unguarded, an empty `$tmp` makes the next line write
  `/.config/…` on the real filesystem — and cleans up through a trap, interrupts included.
  Core asserts only what `blib_link_core` wires everywhere; a repo's own additions are
  arguments (`--require .config/zsh/80-os.zsh` for an OS band-80 overlay,
  `--require .config/defense/templates` for a Role layer), because Core asserting a Role
  path is how the copies drifted in the first place. Three exit codes a caller can tell
  apart: 0 the graph is right, 1 it could not run (bootstrap's own output is printed), 2
  the graph is wrong. The suite drives it against a fake repo whose bootstrap is a stub
  that records the environment it was handed, and pins the scrub, that the scrub takes the
  five and nothing else, each failure mode's exit code, the trap, and the two `.zshrc`
  assertions — including the grep the old recipes shipped, which accepted a
  **commented-out** `source` line and matched `loaderXzsh` besides. It also asserts two things
  the copied recipes never did: that EVERY link resolves, not just `loader.zsh` — a
  renamed Core file behind any other link used to read as a healthy graph — and that each
  Core-owned link resolves to the **right** file, since a graph with `starship.toml` wired
  to `tmux.conf` is complete, resolvable and wrong. Caller-supplied `--require` paths keep
  existence-only semantics: Core has no business asserting what a Role layer's paths point
  at.
  **The four repos switch over on the next sync**, not now: they can only call
  `core/scripts/check-links.sh` once a release has vendored it, so the script ships first
  and the Makefiles follow. Until then their inlined copies (now all fixed) keep running,
  and the four repos without a links-only leg may adopt the gate or not.

- **A scaffolded OS repo is born meeting the `make` vocabulary and the test floor
  (#691).** `scripts/new-os-repo.sh` is the other way a repo enters the fleet (the first is
  `cp -r dotfiles-Fedora`), and it stamped no `Makefile` and no `test/` — so a greenfield
  repo was **missing** across its whole row of the vocabulary register the day it joined
  `scripts/os-repos.txt`, and nothing inside it would ever notice. It now writes, beside the
  entry files and the capability declaration it already stamps for the same reason: a
  `Makefile` defining all seven canonical verbs (`lint` runs the reusable gate's blocking
  legs — shellcheck, `bash -n`, `zsh -n`, RETURN-trap discipline, the capability
  schema, markdownlint, actionlint, gitleaks and the Makefile-gate check — reading the
  vendored `core/scripts/lib/common.sh` scanners, Core's `gitleaks.toml` and a scaffolded
  `.markdownlint.jsonc` carrying Core's rule choices, since the gate lints against the
  caller's own; every tool leg, shellcheck included, says so and skips when its tool is
  absent, never silently, and the capability leg skips when the vendored validator
  predates v4.19.0, as the gate's own leg does; the gate — pinned tool versions, plus its
  advisory legs — stays the verdict; `check` =
  lint + the hermetic links run; `dry-run`;
  `core-verify` in Arch's `core-integrity.sh --self` shape; `packages-check` as the
  contract's stub until the repo has a package list; `test`), with every guard on the same
  recipe line as its tool so it clears the #775 make-gate rule from birth; a **real**
  `test/check-links.sh` — `--dry-run` writes nothing, a run links every repo-owned file
  (and every Core-provided one — each zsh module, both tmux files, starship, nvim, git —
  when `core/` carries it), a second run changes nothing —
  rather than an `exit 0` stub, because a floor met by a script that asserts nothing is not
  a floor; and a `.github/workflows/test.yml` that runs `make test`, the floor's "CI runs
  it" rung. The scaffolded `bootstrap.sh` grows `--dry-run`, `--links-only` and `--help` so
  those verbs are honest, and its mise seed is guarded on the source existing. The
  scaffold is born on `main` whatever the author's `init.defaultBranch` says, so the
  workflows' fleet-standard `[main, master]` push filter cannot miss the repo's own pushes
  (a repo born on `trunk` would otherwise have had no push-triggered CI at all).
  `test-core.sh` F7b pins all of it — as generated
  with `--no-vendor` (no `core/`) the suite must fail loudly and name the missing
  `core/`, and against a `core/` seeded from Core's own tree it must assert every Core
  link — and judges the scaffold with `fleet-vocabulary.sh --check` itself
  against a fake fleet root — the same verdict the nine repos are held to — plus the proof
  the suite can fail (a bootstrap that re-links on every run goes red). Dev tooling only —
  the OS repos receive nothing from this entry.
- **One Makefile vocabulary for the fleet, and a test floor — declared once in Core,
  reported by the audit (#691).** Nine repos had nine `make` dialects: "dry run" was
  `dry-run` in four repos and `bootstrap-dry` in four, "verify core" had five spellings,
  "check packages" two, and only `help` was common to every Makefile — a contributor
  re-learned the verbs in each repo and no gate noticed. `scripts/make-vocabulary.txt`
  declares the seven canonical verbs (`help`, `lint`, `check`, `dry-run`, `packages-check`,
  `core-verify`, `test`); `scripts/fleet-vocabulary.sh` (`make fleet-vocabulary`) reads
  each sibling's Makefile and renders a verb × repo register, and `audit-core.sh` §5h
  reports it beside the gate × repo register with the same advisory posture and the same
  absent-sibling environment skip. The requirement is that the canonical NAME resolves in
  every repo — a repo keeps its historical spelling as a two-line alias, and a verb it
  genuinely lacks is a two-line stub target that says so and exits 0, never declared
  away. The register's last column is the test floor, with no waiver line: a
  `test/` (or `tests/`) directory with content, run from a `run:` step in a workflow GitHub
  loads — `make test`, the directory by path, or a `make` target whose recipe runs it, so
  `make test-repo` counts and a path filter or comment does not. Five of nine repos are
  under it today, `dotfiles-Fedora` — the template every Linux repo is copied from — among
  them; the first run reports 32 missing verb cells, which is the migration each OS repo
  now owes (aliases, not renames, so nothing calling the old targets breaks). The suite
  drives the script against a fake fleet root and pins that an alias alone does not fill a
  cell, that a stub target does, each rung of the floor, and
  that an unreadable vocabulary is a loud exit 2 rather than an empty register. Review of
  the same PR found `scripts/fleet-coverage.sh`'s report mode exiting 1 whenever there were
  no footnotes to print (its last command was a `[[ -n notes ]] && printf`); fixed and
  pinned alongside. Dev tooling
  only — the OS repos receive nothing from this entry until they adopt the verbs.

### Removed

- **BREAKING: `notify-web-call.yml` stops declaring `WEBHOOK_SECRET`, the removal this
  major was the window for.** The credential itself was deleted when G2 finished (#683) and
  nothing has read the input since; what kept it **declared** was the published
  `workflow_call` contract — removing an accepted secret fails workflow validation for any
  caller still passing it, before that caller's own code runs. `GITHUB-APP-AUTH.md` recorded
  it as a live constraint waiting on a MAJOR, and this is that MAJOR.

  **Two conditions had to hold, and both were checked rather than assumed.** No caller was
  still passing it — the nine OS-repo callers stopped at #819, re-verified here across all
  eleven fleet repos plus `htpx`. And a MAJOR does not push the change onto existing
  callers: per `RELEASE-RUNBOOK.md` §1.1 it mints `vN+1` and leaves the outgoing alias
  **frozen**, so `@v6` callers keep the contract they were published against and meet the
  removal only when they explicitly adopt `@v7`. On a PATCH or MINOR the alias advances in
  place and every tracker would have taken it with no adoption step — the case this waited
  to avoid. `GITHUB-APP-AUTH.md`'s section is rewritten from a standing constraint to a
  discharged one, keeping the reasoning because the re-provisioning recovery depends on it
  (its step 4 is now the live branch, not a no-op). `GITHUB-APP-MIGRATION.md` is unchanged
  by design — it is a dated record that deliberately does not track whether this happened.

- **Core's built-in capability fallbacks are deleted; the declaration is the only source
  (#763).** #667 stamped `os.capabilities` across the fleet but deliberately left three
  blocks in Core marked _"DELETE THIS BLOCK"_, because a declaration only reaches a box once
  `bootstrap.sh` has **linked** it — a separate event from the Core fan-out that delivers the
  file, and deleting the fallbacks in the same change would have broken `up` on every box
  that had pulled and not yet re-run `./bootstrap.sh --links-only`. This is the second event.
  Gone — the three marked blocks, and a fourth that carried no marker but existed for the
  same reason:

  - `zsh/60-update.zsh`'s `_CORE_CAP_FALLBACK` table and `_pkgup_fallback` — seven archives'
    upgrade/count/cleanup verbs, the `checkupdates` probe, the `_pkgup_emerge_pending`
    Portage resolve, and the **`grep -qi tumbleweed /etc/os-release`** that chose
    `zypper dup` over `zypper up`. That probe was the single most-cited example of OS
    knowledge in Core, and it is what `os.capabilities` existed to retire.
    `_pkgup_verb` loses its second arm and now reads `_core_cap` only.
  - `zsh/55-maint.zsh`'s `_maint_unit_dir_default` — **the last OS-absolute path in Core**.
    `_maint_unit_file` reads the declared `SCHEDULER_UNIT_DIR` and nothing else.
  - `zsh/30-functions.zsh`'s `_core_install_prefix` `case` — the doctor and the
    command-not-found handler read `PKG_INSTALL` only. Both call sites drop their
    `$+functions[_pkgup_mgr]` guard, which existed solely to feed the mapping a manager
    token.
  - `maint/dotfiles-maint.sh` — a **fourth** block, which #763 did not enumerate but which
    exists for the same reason and would have left the demolition half-done. The scheduled
    runner kept a seven-arm `have brew / checkupdates / pacman / dnf / zypper / apt-get /
    apk` count ladder behind its `cap_declared` test, a four-arm `sudo -n` apply ladder, and
    the guards in front of them: an **`/etc/os-release` read** for the Kali refusal — the
    last one in Core — and `have pacman || have emerge` standing in for "is this a rolling
    distro", which is a probe for a BINARY asserting a claim about a DISTRO and is true on
    any box with pacman installed for other reasons. Kali, Arch and Gentoo already decline
    by declaring no `MAINT_UNATTENDED_UPGRADE`, so the guards were duplicating a claim the
    repos now make about themselves. `_pkgcount` went with its only callers, leaving
    `_pkgcount_decl` as the single counter. An undeclared box logs `count UNAVAILABLE (no
    os.capabilities linked — run ./bootstrap.sh --links-only)` and skips the apply with a
    log line naming the same fix.

  **`audit-core.sh` §5c's per-file exception retires with them**, so every manifested Core
  file is now scanned for OS-absolute paths with no carve-out at all — `ARCHITECTURE.md`'s
  "deliberate exceptions" section reaches **zero**, and `PORTABILITY.md`'s says so too.

  **What an undeclared box does now is degrade visibly, at each caller's own message**,
  which is the point of removing a silent substitution: `up` says no upgrade verb is
  declared and names `--links-only` as the fix, `maint-install` refuses on systemd/launchd
  rather than writing a unit to a directory Core guessed at, `core-doctor` prints no install
  line, and `core-status`'s OS row says the declaration is not linked (it used to say
  "built-in defaults", a note about which source answered — now it carries the remedy).
  `02-capabilities.zsh`'s warning **stays opt-in** (`CORE_CAP_LOUD=1`) for the reason #715
  established: two lines of stderr on every interactive shell and every tmux split is how an
  operator learns to ignore stderr, and that warning can only say a table is empty where
  each consumer can name what actually broke.

  **`up` refuses in every mode, including the read-only ones**, and that is a fix this
  change needed rather than a consequence of it. The `PKG_UPGRADE` guard used to sit at the
  dispatch, after `-n` and `-i` had already returned — so on an undeclared box `up -n`
  resolved no `PKG_COUNT_PENDING`, read the empty list as an empty **answer**, and printed
  "nothing to upgrade": the box asserted up to date when nothing was measured, which is the
  0-vs-unknown confusion the `-1` sentinel exists to prevent in `_pkgup_count` arriving
  through a different door. The guard now runs immediately after manager detection, where it
  belongs — a missing REQUIRED verb is a fact about the box, not about the mode you asked
  for. `maint-install`'s two refusals name `--links-only` alongside the declare-it hint for
  the same reason: the likelier cause is a declaration that exists but was never linked.

  `scripts/check-capabilities.sh` keeps its schema unchanged — it is the validator, not a
  fallback — though its "absent means Core's built-in default applies" note is corrected:
  since this change an omitted optional key **is** the statement, and `TOOLS_OPTIN` is the
  one key that still falls back to a Core-side default. What changes for a consuming repo is
  that **`./bootstrap.sh --links-only` is required, not merely advisable**, in the three
  cases where the SYMLINK is what changes: adopting a declaration, a box that has never
  relinked since one was authored, and switching which file is selected (a Kali or Leap tier,
  say). _Editing_ an already-linked declaration needs nothing — the symlink points at the
  file in the repo, so a box reads the edit on its next shell. `VENDORING.md` says so where
  it used to say absence is not fatal. `scripts/test-core.sh` moves with the code: the
  per-manager count/list cases now seed the declaration each OS repo actually ships instead
  of leaning on Core's copy of it (which is the stronger test — it pins the values a real
  box runs), the maint cases declare `SCHEDULER_UNIT_DIR` alongside the scheduler they stub,
  and a new case pins the undeclared box reporting the `-1` sentinel rather than a guessed
  row.

- **BREAKING: fourteen `HAVE_*` globals no code reads, and the `HAVE_*` contract is declared
  and gated (#694).** `zsh/00-tools.zsh` set **42** `HAVE_<TOOL>` flags into every interactive
  shell. Fourteen of them — `HAVE_ASTGREP` · `HAVE_DELTA` · `HAVE_GRON` · `HAVE_GUM` ·
  `HAVE_HYPERFINE` · `HAVE_JNV` · `HAVE_JQ` · `HAVE_LNAV` · `HAVE_SD` · `HAVE_SESH` ·
  `HAVE_SHELLCHECK` · `HAVE_SHFMT` · `HAVE_WATCHEXEC` · `HAVE_YQ` — were read by
  **nothing**, in Core or in any
  of the thirteen repos. **Why this is breaking, and the only reason it is:** a gitignored
  host-local `99-local.zsh` could reference one, and that is unknowable from here. Nothing
  Core ships, and nothing any OS or role repo ships, is affected.
  **`core-doctor` is not affected either, which is the part worth reading before you worry:**
  the `_have <tool>` **call stays on every one of those lines**. It is what writes
  `_CORE_PROBED[<tool>]`, and the ledger — never a flag — is what `core-doctor`,
  `_core_doctor_stale` and `_core_doctor_unwired` read. Only the `&& HAVE_X=1` half is gone.
  Detection coverage is byte-for-byte what it was.

  **The flags are now a declared surface.** `PORTABILITY.md` gains **§5**: the naming rule
  (`HAVE_` + canonical tool name, `-` → `_`), that `_CORE_PROBED` is the authoritative ledger
  and `HAVE_*` the convenience alias, that a flag exists **only where band-00 detection ran**
  (so read `${HAVE_X:-}`, never bare), and a table of what downstream may use. The answer to
  the open question `V5-PROPOSAL.md` §5.2 posed is **supported, but enumerated**: the table
  holds `HAVE_ATUIN` and nothing else, because that is what the fleet actually reads
  (`dotfiles-Alpine`, `-Debian`, `-Fedora`, in `os/*.zsh`, to gate the atuin daemon exports).
  Starting there rather than at "all of them" is deliberate — widening a declared surface is a
  one-line PR and narrowing one is a breaking change. `VENDORING.md` carries the same fact
  from the OS-repo author's side; `core.manifest`'s charter line for `00-tools.zsh` now names
  it alongside `_cache_eval` and `_core_is_wsl`.

  **`audit-core.sh` §5j** is what stops this recurring, in three directions: **declared ⊆ set**
  (a doc row Core no longer sets is a stale promise — the exact wreckage a rename leaves);
  **fleet reads ⊆ declared** (an OS or role repo reading a Core flag it does not itself set is
  coupled to Core's internals); and **set ⇒ has a reader** (the direction the issue did not ask
  for, and the one that keeps fourteen dead flags from quietly reaccumulating). It matches a
  read by its **`$` sigil** rather than by the bare name, which is how it tells `${HAVE_ATUIN:-}`
  in code from `HAVE_ASTGREP` in a comment without needing a parser for five grammars — the
  trap `PORTABILITY.md` §3 documents. It subtracts each repo's own assignments first, so the
  ~20 flags `dotfiles-Offense` and `dotfiles-Defense` each define for themselves are ignored;
  the contract is only ever about reading a name you did not set. Whole-line comments are
  dropped on top of the sigil rule, on **both** sides — the assignment side matters more,
  since a `# HAVE_X=1` read as an assignment would mark the flag owned and silently
  **suppress** a real undeclared read of it. No `--exclude-dir` and no `-I` anywhere in it —
  both are GNU extensions busybox grep rejects, the trap that once made
  `_core_make_gate_hits` report Core as the repo missing its own rule — so the vendored
  `core/` subtree (which would otherwise answer for Core in every OS repo and make the fleet
  direction vacuous) is pruned with `find`. The fleet half takes §5f/§5h's `skip_env`
  posture: CI checks out this repo alone, and a gate that only passes on a laptop with the
  fleet beside it is a gate nobody trusts.

  **"Reader" means a zsh module, and that precision is what makes direction 3 worth having.**
  A `HAVE_*` flag is a shell parameter that is never exported, so only code **sourced into
  the same shell** can read one: `zsh/*.zsh` here, and the OS/role layers downstream.
  `bin/`, `scripts/`, `maint/` and `tmux/scripts/` run as child processes where the flag does
  not exist, and nvim's lua cannot see a zsh parameter at all — every `HAVE_*` mention in
  those trees is prose about Core, not a read of it. The first implementation scanned them
  anyway, which let `scripts/test-core.sh` count as a consumer and kept `HAVE_GRON` alive on
  the strength of one negative fixture; review caught it. A test is not a consumer, so the
  flag is pruned and that fixture asserts `_CORE_PROBED[gron] == 0` — which is what it
  always meant, and is strictly the stronger claim.

  **The issue's own numbers were wrong in three places, and `V5-PROPOSAL.md` §5.1 now records
  why** rather than quietly correcting them, because the shape of the error is the argument for
  the sigil match. It said 43 globals (42), nine dead (fourteen — its nine included
  `HAVE_DIRENV`, which has never existed, and `HAVE_MISE`, which `00-tools.zsh` reads at its own
  `mise activate` line), and five genuine downstream consumers (**one**: of the other four,
  `HAVE_ASTGREP`/`HAVE_JNV`/`HAVE_SHELLCHECK` appear in a single `dotfiles-Offense` **comment**,
  and `dotfiles-Defense` **sets** `HAVE_JQ` itself). Every one of those came from grepping bare
  names and reading prose as code. The flags were also never `export`ed — they are shell
  parameters, so they never reached a child process.

  `scripts/test-core.sh` pins the parts a static gate cannot: that **every bare `_have` probe
  still writes its ledger row** (derived from the source, floored at 14 — the regression here is
  a _reading_ one, where the next person sees a probe whose result is discarded and deletes the
  line, silently blinding the doctor on fourteen tools); that the fourteen flag names stay unset;
  and that `HAVE_ATUIN` is set with atuin present and unset — with the ledger reading `0`, not a
  missing row — when it is absent, hermetically, in both directions.

  The gate's own matcher is tested too, rather than only hand-verified: the fleet scan is
  extracted as **`scripts/lib/common.sh :: _core_have_read_hits`** and driven by sixteen
  fixture repos. Seven must FIRE: a plain read, the braceless `$HAVE_X` form, a `.sh` outside
  `os/`, zsh's existence form `${+HAVE_X}`, a parenthesised expansion flag `${(t)HAVE_X}`,
  and the **no-sigil arithmetic** form `(( HAVE_X ))` — inside `(( ))` a shell resolves a
  bare name as a parameter, and this tree gates on booleans exactly that way
  (`((UPDATE_CHECK_ENABLED))`, `((CORE_CNF_ENABLED))`), so an OS layer writing it is
  following house style — plus a **double-quoted** read, the commonest real form in the
  fleet, which guards the rule below. Nine must stay SILENT: a read inside a vendored `core/` (pruned), a flag
  the repo sets itself, ownership spread across two files, a bare name in a comment, a
  **sigil** form in a comment, and two shapes that must not confer **ownership** — a
  commented-out `# HAVE_X=1`, and one written as data by a fragment generator
  (`printf 'HAVE_X=1\n'`). Both are the same false-negative: a bogus "this repo owns the
  flag" silently suppresses a real undeclared read of it. Its mirror is there too — a **read**
  written as data by a generator (`printf '${HAVE_X:-}\n'`), which would be a false _finding_
  and red a clean repo. Plus a repo with no shell files.

  Those last two are one character of lookbehind each, and the asymmetry between them is the
  interesting part: an assignment is rejected next to **any** quote, a read only next to a
  **single** one. A single quote suppresses expansion so the text is literal; a double quote
  does not, and `[[ -n "${HAVE_ATUIN:-}" ]]` is the commonest real read in the fleet —
  rejecting on any quote would have made it invisible. The helper states where this floor
  sits rather than implying there is none: a quoted heredoc, `echo "note: HAVE_X=1"`, and a
  quoted arithmetic literal all still fool it, and separating those needs the shell grammar —
  the trap §3 of `PORTABILITY.md` documents at length. Every fixture carries a vendored `core/` that both sets and
  reads the whole flag set, so if the prune ever breaks, all sixteen go silent at once. The silent directions are the ones worth pinning: an over-reporting scanner
  reds a clean fleet and gets turned off, but an under-reporting one passes forever while the
  contract rots. Three of those silent misses were review findings against earlier drafts,
  and all three are now fixtures: zsh's **existence form** `(( ${+HAVE_X} ))` and its
  **parenthesised expansion flags** `${(t)HAVE_X}` — both perfectly ordinary ways to gate on
  or inspect a flag, both used by this tree itself (`(( ${+_CORE_PROBED} ))` in
  `30-functions.zsh`, `${(t)GIT_EXEC_PATH}` in `00-tools.zsh`), and both walked straight past
  by a matcher demanding `HAVE_` immediately after the brace; and a **commented-out
  assignment** conferring ownership, which would have suppressed a real undeclared read of
  the same flag.

  The fleet scan deliberately reads `*.sh` as well as `*.zsh`, even though §5j's scan of
  Core's own modules is `.zsh`-only. The two directions **err in opposite directions on
  purpose**: direction 3 asks "does anything read this flag?", where counting a non-reader
  keeps a dead flag alive, so it is strict; direction 2 asks "does this repo read a flag it
  should not?", where missing a reader lets an undeclared coupling through silently, so it is
  broad. **Direction 2 is, today, advisory** — Core's CI checks out this repo alone so it
  records a skip on every run, and the reusable `lint` workflow the OS repos call does not
  run it, so an OS-repo PR adding an undeclared read can still merge green. Closing that
  needs a caller-side leg in `lint-call.yml` and the declared table reachable from a vendored
  checkout, which `PORTABILITY.md` is not — an allowlist change with its own nine-repo blast
  radius, filed as #866 rather than smuggled in here. Directions 1 and 3 block on every run. A downstream `.sh` may be sourced from a zsh fragment, and where it is a plain child
  process a `$HAVE_X` in it is a read that can only ever be empty — its own defect, worth
  surfacing. Each direction is tuned to find problems rather than to be symmetrical.

  §5j also **fails closed when it parses no declaration at all.** Rename or delete §5's
  heading and the declared set comes back empty — direction 1 goes vacuous, direction 2 skips
  on every CI runner (no fleet beside it), and direction 3 still passes because `HAVE_ATUIN`
  has an internal reader in `00-tools.zsh` too. The section would have reported green over no
  declared surface whatsoever, which is exactly the shape #682 named: a drift gate that
  checked nothing must never report green.

  Two shape-parsing tests needed teaching, not weakening. `#447`'s doctor-vs-flag agreement
  check pairs on the assignment by design (a tool with no flag has nothing to compare), so its
  floor moves 30 → 24. `"every core-doctor row has detection behind it"` parsed two line
  shapes and this change introduced a third, dropping fourteen tools out of its set and
  tripping its floor at 29 — it learns the bare `_have` shape instead, because a bare probe
  **is** detection in the sense that test means: it writes the ledger row the doctor keys on.
  Lowering that floor would have let fourteen doctor rows read as undetected while detection
  was untouched.

  `PORTING-MATRIX.md`'s footnotes for every affected tool are corrected in the same change,
  as are the three stale in-code references review turned up — `zsh/05-ui.zsh` advertised
  `HAVE_GUM` as the flag it deliberately does not use, and `scripts/bench-core.sh` named
  `HAVE_HYPERFINE` twice, once in a user-facing skip message.

### Changed

- **A `scripts/` change no longer drags the atuin harness onto every CI leg (#699 leftover).**
  `scripts/ci-classify.sh` forced the **full** run — shell, nvim _and_ atuin — for anything
  under `scripts/`, on the reasoning that the premise detector lives there and infra is
  cross-cutting. True of the detector; false of the forty-odd scripts beside it. The atuin
  gate is the hermetic self-test of `scripts/research/verify-atuin-guard.sh`, **197s of a
  286s behavioral suite — 68% of it, and the largest single cost on the CI critical path**,
  and **every one of the last seven merges to `main` touched `scripts/`**, so every one paid
  it on all four legs for a gate the change could not reach. #687 archived that apparatus as
  on-demand research; its _test_ stayed on the push path of unrelated work.
  What can move the self-test is checkable rather than a judgement call, **because the test
  is hermetic**: it stubs `atuin` and doctors a _sandbox_ copy of `zsh/00-tools.zsh`, so the
  real tree is not an input. Its reachable set is exactly `scripts/research/` (the script
  under test and its lib), `scripts/lib/` (`common.sh`), `scripts/test/` + `test-core.sh`
  (the harness), and `ci-classify.sh` itself, which decides the scope — those still force the
  full run. Everything else under `scripts/`, plus `.github/`, `.claude/` and the repo-meta
  config, now forces **shell and nvim but not atuin**; they remain genuinely cross-cutting for
  the shipped modules. `zsh/00-tools.zsh` and `atuin/` are untouched and still gate it.
  **`scripts/gen-theme.sh` is the case that makes this real rather than pedantic:** it writes
  a generated block _into_ `zsh/00-tools.zsh` (`gen-theme.sh:210`), the module carrying
  `_core_atuin_daemon_guard` — so it reaches the guard, and still cannot reach the guard's
  test. It forces shell and nvim, not atuin.
  The new arm is **derived, not hand-kept**: `scripts/test/22-ci-classify.sh` reads the two
  atuin fragments, extracts every `$HERE/scripts/…` path they actually reach for, and fails
  naming any that no longer classifies as `atuin=true` — so adding a dependency reds the gate
  at the moment the arm needed widening. A hand-kept exception list inside a fail-closed gate
  is what `CONTRIBUTING.md` records being deleted from audit §5c, for exactly this reason.

- **The behavioral suite is 36 named fragments, not one 18,700-line file (#699).**
  `scripts/test-core.sh` had grown to **18,747 lines**, and ShellCheck's cost is superlinear
  in file length: that one file was **42.6s of the audit's 65.9s** of ShellCheck — **65% of
  the lint surface in one file** — re-linted in full on all four CI legs by any PR touching
  any shell file, with `audit (macos-latest)` setting the wall clock for the whole PR. The
  suite now lives in **`scripts/test/NN-name.sh`**, one numbered fragment per subject, and
  `test-core.sh` is a thin dispatcher that globs them in `NN` order and **sources** them into
  its own shell. The suite's own share of the sweep goes from **42.6s to 9.7s**, taking the
  whole gate from **65.9s to 31.7s — a 34.2s saving on every leg, 52% of it.** It is a move,
  not a rewrite: the fragments rejoin to the old file's lines 190–18740 **byte for byte** (bar
  the trailing blank lines `end-of-file-fixer` trims at each cut), and **all 1,772 assertions
  the suite already had come back identical in text and order**, verified line-by-line against
  a pre-split run. Five are added — see `05-suite-shape.sh` below — and three labels are
  reworded (the two self-reference guards, and one that cited a section ID the split
  removed); nothing else in the stream differs. `--quiet`, `--json`, `--scope` and the
  exit-code contract `audit-core.sh` reads are untouched. The second win is
  organisational: the sections were lettered **A–L**, and the letters had drifted into **two
  different "E"s** and an `A` that ran after `J`, while the file's own header still described
  it as _"Two sections"_ — names fix that by construction. Adding a section is adding a file;
  the glob has no registry to forget, and an empty glob is a **hard exit 2** rather than a
  green run that asserted nothing. Two guards that scanned only `scripts/test-core.sh` for
  their own fixtures — the RETURN-trap and conflict-marker self-reference checks — now sweep
  the dispatcher **and** every fragment, so they cannot go vacuous as fixtures move; and the
  bare-box ending, which was a verbatim copy of the normal one, is now one
  `_core_test_finish`. `audit-core.sh`'s exec-bit gate learns that `scripts/test/*.sh` are
  sourced libraries (`100644`), the same arm as `scripts/lib/`. The glob buys "no registry"
  at the price of one new way to write assertions that never run — an unnumbered file beside
  the others is skipped in silence — so **`scripts/test/05-suite-shape.sh`** asserts the
  layout instead of assuming it: every fragment carries the `NN-` prefix, none is executable,
  all are tracked, and the empty-glob refusal is **driven** against a staged tree rather than
  believed. Those five are the only assertions the split adds — **+5 and no pre-existing one
  changed**, stated as a delta rather than a pair of totals because `main` keeps adding
  assertions underneath this branch (it was `1772 → 1777` when measured, `1788 → 1793` after
  merging #863 and #864), and a total pinned here would be wrong by the time it shipped.

- **The startup budget is ratcheted from 120 ms to a committed 48 ms — 2× the measured
  baseline — and CI reads it from `scripts/bench-baseline.env` (#688).** The `bench` job's
  `CORE_BENCH_BUDGET_MS=120` existed only in `ci.yml`, beside a comment guessing "~25 ms";
  194 runs of that job (2026-08-26 → 09-03, ubuntu-latest, 50 warmed runs each) actually
  measured 11.8–31.9 ms (bimodal by runner host; ordinary hosts ~24 ms, two runs above
  30 ms, none above 36), so 120 was 5× the baseline and 3.8× the worst run ever seen, and a regression the size of
  the biggest win on record — re-sourcing the gh/uv/ty completions per shell, +35 ms —
  passed green. Three fixes. (1) `scripts/bench-baseline.env` commits
  `CORE_BENCH_BASELINE_MS=24` and `CORE_BENCH_BUDGET_MS=48` next to the script they govern,
  with the calibration, the 2× policy and the re-baseline recipe in its header; `ci.yml`
  carries no budget literal any more, and `scripts/test-core.sh` pins that, pins
  `BUDGET == 2 × BASELINE` (so widening the budget to green a run is a red audit), and
  proves the gate through a stub hyperfine: a 100 ms mean exits 1, a 20 ms mean passes,
  the env override wins and is labelled, report mode never fails. A budget nobody has seen
  fail is not known to work; this one fails in the suite on every audit. (2)
  `bench-core.sh --gate` (`make bench-gate`, what CI runs) reads the file FAIL-CLOSED — a
  missing or malformed file, a budget that does not exceed the baseline, or a missing
  zsh/hyperfine/python3 is exit 1, never a skip — and on a breach prints the per-module
  `--profile` breakdown so the red log names the module, not just the aggregate (single-
  sample module timings stay informational; a per-module ceiling would gate noise). That
  profile now runs its zsh child with `NO_RCS`: since the v4 sandbox, `--profile` had let
  the child source the sandbox `.zshrc` — and so the whole chain — before timing anything,
  so it measured a warm re-source and could name the wrong module; it now times a cold
  first sourcing, and it covers `02-capabilities`, which the loader globs but the module
  list omitted. It is a gross-regression gate, not an additive threshold: runner hosts are
  bimodal, so the +35 ms that fails from an ordinary host's 24 ms can pass from a fast
  host's 12, and the re-baseline recipe therefore samples ~20 jobs and takes the
  ordinary-host mode, never one run. The
  mean is still the gated statistic (every recorded measurement is a mean); the median
  prints beside it, and a breach whose median is within budget is labelled as a skewed or
  intermittent slowdown, not diagnosed as noise. (3) The report and gate modes — plain `make bench` included — now print the mean against
  the committed baseline (`CI baseline 24 ms, −1%`), so a local run shows the trend —
  though the number that gates is CI's: a laptop or WSL2 box measures 1–3× ubuntu-latest,
  so compare before/after locally rather than reading a local `make bench-gate` red as a
  verdict. The trigger is unchanged: the issue asked to add `starship/` and `nvim/`, but
  `starship/` and `tmux/` already sit in the classifier's `shell` bucket and bench today,
  and nothing on the zsh startup chain reads `nvim/`. Dev tooling only — the OS repos
  receive nothing from this entry.

### Fixed

- **`pr-link-check` gates `feat(…)` too — the scope that let #852 sit open (#852).**
  The rule "a fix closes an issue or says why not" was `fix`-titled PRs only, and
  `scripts/ci-pr-link.sh` argues for that strictness at length — but the argument is
  entirely about `fixup:` versus `fix:` and says nothing about `feat:`. The omission had
  a cost, in the exact shape the gate exists to prevent. **#852**
  (`fix(fleet): make check is not hermetic…`) was resolved by **#853**, titled
  `feat(check): one Core-owned hermetic links gate`, plus three consumer PRs in Fedora,
  Gentoo and openSUSE. Every part merged on 2026-09-03/04. Nothing closed the issue, and
  it sat OPEN looking like a live defect — reached through the resolving PR's _title_
  rather than its body, which no amount of care about `Closes #N` would have caught. An
  issue does not know how the PR that resolves it will be typed. Measured over the 100
  PRs merged since the gate landed on 2026-08-17: **29 gated, 71 not, and 41 of those 71
  cited an issue in the body and closed none.** The set now stops at `fix|feat`, on the
  same reasoning that keeps `fixup:` out: `chore(core): sync Core → vX.Y.Z` and
  `docs(changelog): release vX.Y.Z` are mechanical and close nothing by design, so gating
  them would teach `No-Issue:` as a reflex — and an escape hatch taken by habit is a gate
  that has stopped working. The suite covers all four `feat` shapes (scoped, unscoped,
  breaking, breaking-scoped), the `No-Issue:` exemption on a `feat`, `feature:` and
  `featuring` staying out on the delimiter rule, and the four mechanical types staying
  ungated. One existing case flipped rather than broke: the "out of scope whatever the
  probe did" assertion used `feat(x): y` as its example and now uses `chore(deps):`.

- **Two CLI help texts now match the code they describe (#693 follow-up).**
  `gen-desktop-parity.sh --help` listed `--check`/`--root`/`--strict` but not `--quiet`,
  `--color WHEN` or `-h`/`--help` — all of which its own parser accepts, and `parity-check.yml`
  already passes `--color never`. `--quiet` is also described accurately now: it silences the
  header and every success line, the final summary included, not just the per-target ones. And
  `audit-core.sh --require-siblings` enumerated the fleet-wide gates it reds on, and the list
  had drifted — it named four of the eight that declare an absent sibling through `skip_env`.
  Rather than extend a list that must be hand-updated whenever a gate is added, the flag now
  describes the class and points at the run summary, which names every environment skip the
  run actually recorded. Documentation only; no behaviour change.
- **OS-repo tags fired only on Core syncs — native work was released by coincidence, and
  nothing had ever bumped past patch (#696).** Every consumer's `auto-tag.yml` triggered on
  `paths: ['core/**']`, the vendored subtree and nothing else, so the repo's own `vX.Y.Z`
  advanced when **Core** moved and at no other time. Measured on `dotfiles-Fedora`: its
  last seven releases were its last seven Core syncs, one for one, while **six native
  commits cut nothing** — including dotgibson/dotfiles-Fedora#122, which wired a
  package-name gate that had never run on any PR, and dotgibson/dotfiles-Fedora#116, which
  removed a tracked file. Both sat unreleased until an
  unrelated fan-out swept them up hours later and attributed them to a tag whose whole
  meaning was "Core moved". So `v1.3.68` meant "68 Core syncs received", which `core.lock`
  already answers precisely and offline. The release **notes** were never wrong —
  `auto-tag.sh --notes-file` groups Conventional Commits over the entire range since the
  last tag, so those two are both in `v1.3.68`'s body — the trigger and the
  granularity were. Had Core paused releases for a month, every OS repo's releases would
  have paused with it regardless of what those repos did. **Core's own caller example was
  the source**: `auto-tag-call.yml` documented the core-only shape, and two repos had
  already diverged from it and written down why (`dotfiles-MacBook`, where eight merged
  PRs of install-path work produced zero tags; `dotfiles-openSUSE`, where a 971-line
  `bootstrap.sh` rewrite produced zero) — one of them carrying a standing
  _"please don't restore the upstream shape on a future sync"_ note. That correction is now
  the documented shape: a **denylist** over the installable surface (`**` minus docs, CI,
  and author-time config), because an allowlist fails the same way — add a new installable
  directory, forget to list it, releases silently stop — while a denylist's failure mode is
  a spurious patch tag, noisy rather than wrong.

- **The `bump` input existed from day one and no caller had ever passed it (#696).**
  `auto-tag-call.yml` has always accepted `bump: patch|minor|major`; every `bump` string in
  all nine repos was a **comment describing the default**. A tag that can only ever patch
  is a build counter in a SemVer costume, and it showed: the v5 rollout gave every OS repo
  a new file, a new symlink and a mandatory re-bootstrap, and produced nothing but
  `1.3.x`. The documented caller now carries a `workflow_dispatch` with a `bump` choice
  and passes `bump: ${{ inputs.bump || 'patch' }}` — empty on a push, chosen on a
  dispatch, one caller for both flows — so a deliberate minor/major is Actions → Run
  workflow rather than a workflow edit. `RELEASE-RUNBOOK.md` §2 has the flow, including
  the ordering constraint that idempotency implies: dispatch and fan-out merge cannot both
  tag the same commit, so run the dispatch on one the automatic patch has not already
  claimed.

- **The reusable normalises an empty `bump` to its documented default (#696).** The
  fleet's callers pass the dispatch input falling back to the literal `patch`, so one caller
  serves both a push (where the `inputs` context is empty) and a `workflow_dispatch`. Had
  that fallback ever resolved to `""` rather than `patch`, the runtime allowlist would have
  failed **every push-triggered tag run in every consumer repo at once** — loudly, but
  fleet-wide, and only after merge. An unsupplied optional input means its documented
  default, so `auto-tag-call.yml` says so before the allowlist rather than resting the whole
  fan-out on an expression detail. Not a hole in it: `""` is not a misspelling of a
  component, and a hostile value still fails. The suite also pins that **no `${{ }}` appears
  inside that step's `run:` body** — a block scalar is interpolated before the shell sees
  it, so an expression written there, even in a comment, is the caller-input splice the
  step's own `env:` indirection exists to prevent.

- **`scripts/fleet-release-triggers.sh` — the release-trigger register (#696).**
  `fleet-coverage.sh` already tracked `auto-tag-call` and reported `reusable` for all nine
  repos: green, while six of them released only on Core syncs. Right answer, wrong
  question — calling a gate is not the same as the gate releasing anything the repo owns.
  The new register asks the second question, reading each sibling's `auto-tag.yml` for two
  columns: whether its filter watches anything outside `core/`, and whether a non-patch
  bump is reachable without editing the file. Wired into `audit-core.sh` §5h and
  `make fleet-release-triggers`, **advisory** like the coverage and vocabulary registers
  (this is fleet drift, not a regression in the commit under test) and an environment SKIP
  when no sibling is checked out. It refuses to bluff: a file whose `on:` block its
  deliberately crude reader cannot parse is reported `unparsed`, never given a verdict.
  Its one stated blind spot is a **second** vendored subtree — `dotfiles-Offense` also
  carries `offensive/companion/` from htpx, whose paths Core cannot derive — so the
  `core-only` column is a floor that catches the shape Core itself shipped, not a proof.

- **The register's own reader had three false-green shapes, found in review (#696).**
  A register that certifies the wiring it exists to detect is worse than none, so: (1) the
  path parser was not scoped to `on.push` and read `paths-ignore` entries as watched
  paths, which **inverts** the verdict — `push.paths-ignore: ['core/**']` runs on
  everything _except_ the vendored subtree, the own-layer shape, and was reported
  `core-only`; a `pull_request` filter could likewise decide a push verdict. It now reads
  the `push` mapping alone, gives `paths-ignore` its denylist meaning, reports a workflow
  with no push trigger as `dispatch-only`, and abstains (`unparsed`) on the
  paths-plus-paths-ignore combination GitHub itself rejects. (2) The `bump` column grepped
  for a `workflow_dispatch:` and a bare `bump:` anywhere in the file, which passes on both
  shapes that cannot cut a non-patch — an input declared for the chooser that the job
  never forwards, and a forwarded **constant** (`with: {bump: patch}`). It now requires
  the forwarded value to reference the dispatch input. (3) Sibling detection used `-d
  "$dir/.git"`, so a linked worktree or submodule checkout — where `.git` is a **file** —
  was skipped, and a fleet of worktrees reported "no sibling repo checked out", which is a
  green; `-e` now, matching `scripts/lib/common.sh` and `fleet-vocabulary.sh`. Also: the
  no-sibling guard ran only under `--check`, so the default render and `make
  fleet-release-triggers` printed a headers-only table indistinguishable from a healthy
  fleet, and `--help` read a fixed line range of the file header that had already
  truncated once when the banner grew — a heredoc `usage()` now, per `check-links.sh` and
  `sync-core.sh`. Every one of these has a regression fixture.

- **Three more, one of them reachable only on macOS (#696).** (1) The comment stripper
  used `[[:space:]]\+` — a **GNU BRE extension** that BSD `sed` reads as a literal plus, so
  on the macOS audit leg trailing comments survived and a constant
  `bump: patch  # dispatches pass inputs.bump` read as dispatch-capable. A false green on
  one platform only, which is the kind that survives review; `PORTABILITY.md` names the
  class. POSIX `[[:space:]][[:space:]]*` now. (2) A **multi-line flow sequence** —
  `paths: [` with its values on following lines — matched the flow branch, found no
  closing bracket, emitted no path records, and left `has_paths` false, so a core-only
  workflow reported `unfiltered`. The guard keys on the path **key** now, not on whether
  values came back. (3) A **bare `workflow_dispatch:`** with no inputs, plus a job
  forwarding `inputs.bump`, satisfied the two-fact check while rendering no chooser at
  all — every dispatch resolved to the empty input and patched silently. The `bump` input
  must now be _declared_ under `workflow_dispatch.inputs`, read with event scope rather
  than grepped for globally (`bump:` also appears on the forwarding line). Each has a
  fixture, and one asserts no `sed` invocation carries a GNU-only BRE — the defect is
  invisible on a Linux runner, so a Linux-only test would not have caught it.

- **Two more false greens in the reader, and `auto-tag.sh`'s own docs (#696).** An
  **inline** event mapping — `push: { branches: [main], paths: ["core/**"] }`, valid YAML
  the fleet does not currently use — carries its filter after the colon, where the
  block-form rules never look. The reader discarded it, `_trigger` saw no path key, and
  the verdict was `unfiltered`: a green for a workflow still releasing only on Core. It now
  detects a non-empty `push:` value and abstains. Separately, `scripts/auto-tag.sh`'s
  header and its public `--help` still said it tags "after a Core fan-out" / "for an OS
  repo whose vendored `core/` just advanced" — the obsolete contract, shown to anyone
  running the shared implementation by hand. The script never cared what triggered it; that
  is the caller's business, and it now says so. Also: a `\s` in one new assertion, which is
  not portable ERE — this suite runs on macOS, where BSD `grep` would have failed it even
  with `usage()` present. `[[:space:]]`, per the rest of the suite.

- **`RELEASE-RUNBOOK.md` §2 documented an ordering for the deliberate bump that cannot
  work (#696).** It claimed either order was fine — dispatch before the fan-out merge and
  the merge no-ops, or dispatch after. Neither: a `workflow_dispatch` runs against a
  **ref**, so dispatching pre-merge tags the _pre-merge_ HEAD and the merge then cuts its
  own patch on top (`v1.4.0` on the commit before the change, `v1.4.1` on the change),
  while dispatching post-merge finds HEAD already tagged and no-ops. The corrected recipe
  uses the denylist this same change introduces: a docs-only commit cuts no tag, so
  landing the release note leaves the untagged HEAD a dispatch needs — merge, let the
  patch settle, land the note, dispatch there. The minor marks the note rather than the
  code commit, the same shape `dotfiles-Windows` §3b already has, and the doc now says so
  instead of implying the tag lands somewhere it does not.

- **A scaffolded OS repo was born with no `auto-tag.yml` at all (#696).**
  `new-os-repo.sh` stamped `lint.yml` and `test.yml` and no release caller, so a new repo
  never cut a single tag of its own — the collapsed version line in its most complete
  form. It now stamps the corrected caller, pinned to `core.version`'s major the same way
  the lint caller is (audit §8a-ter), with the denylist and the `bump` dispatch. The suite
  asserts the scaffold passes the register itself rather than grepping for the paths — a
  grep would go green on a file the register still calls `core-only`.

- **`RELEASE-STRATEGY.md` claimed the OS repos are "not independently versioned" while
  §3 documented the tags they cut (#696).** §1 also defended the design on the grounds
  that "the OS layer is a thin shim over package manager, clipboard, and paths". That was
  true when written and stopped being true at #663/#667, when the OS repo took ownership
  of `os.capabilities` — the dispatch table deciding how `up`, `clip`, `maint-*` and
  `core-doctor` behave on that box. A wrong entry there is a host-visible defect Core
  cannot cause and Core's version cannot describe. §1 now says what each of the two
  version lines actually answers, and keeps the part of the old rationale that survives:
  Core is still the only thing released on a **planned cadence**, and `core.lock` still
  beats any repo tag at "what Core am I on?". This is not a move to full independent
  SemVer across nine repos. `RELEASE-RUNBOOK.md`'s header table carried the same stale
  "not versioned" claim and is corrected with it.

- **`sync-core.sh --strict` — a failed target becomes the exit status.** By default a
  per-repo failure is a summary line and exit 0, and that default stays: the fan-out
  runs the script bare inside a `bash -e` step and then does per-repo push and PR work,
  so a default non-zero exit would abort that step for every repo when one fails. A
  single-target caller wants the opposite — a status it can chain on — and a matching
  `core.lock` line is no proof either, since the lock can be written before a later pin,
  commit or verification step fails. `--strict` returns 1 whenever a targeted repo
  failed **or was skipped** (not cloned, or no `core/` yet — a wrong name or
  `REPOS_ROOT` must not read as success). The scaffold's `--no-vendor` recovery command
  and the first-vendor recipe in `ARCHITECTURE.md`, `VENDORING.md` and
  `PORTING-MATRIX.md` cannot use it: they run the **released** script from a worktree at
  the pinned tag, which may predate the flag, so they read the released script's own
  summary line instead and count only `updated 1   skipped 0   failed 0`. `test-core.sh`
  F6 pins the default and strict contracts on the same dirty, missing and core-less
  targets. Dev tooling only — the OS repos receive nothing from this entry.
  The recovery command is also **resumable**: its one-time `git subtree add` is skipped
  once `HEAD` already carries `core/` (`cat-file -e HEAD:core`), so rerunning the exact
  command after a failed sync goes straight back to the sync instead of stopping at
  "prefix 'core' already exists"; and a `--dry-run` target that does not exist yet is
  embedded anchored to the invocation directory, because the chain `cd`s into the Core
  checkout, where a relative `REPOS_ROOT` would make the sync skip the very repo the hint
  was written for. Both are fixture-driven in `test-core.sh` (a second run of the
  materialize half, and a dry run of a relative, not-yet-existing target). And because
  that verdict reads the `repos:` footer, which exists since v4.1.0 (v4.0.2 and older
  print a per-check count a successful single-target sync would fail against), the
  scaffold now refuses a `CORE_BRANCH` naming an older release before it writes anything,
  and the three recipes state the same floor.
- **A greenfield OS repo no longer vendors a retired Core by default, and the
  first-vendor pin is now held to `core.version`'s major (#691 follow-up).**
  `scripts/new-os-repo.sh` defaulted `CORE_BRANCH` to `refs/tags/v5` — and its `--help`,
  `sync-core.sh`'s header and usage, and the copyable first-vendor recipe in
  `ARCHITECTURE.md`, `VENDORING.md` and `PORTING-MATRIX.md` all still said `v5` — two
  releases after the fleet moved to v6, so a repo scaffolded in that window carried a
  retired major and the docs told a human to do the same. This is the same rot the v4 → v5
  cut fixed by hand in three separate entries, which is the reason it is now a gate rather
  than a fourth: `scripts/lib/common.sh :: _core_vendor_pin_hits` reads the three recipe
  shapes (`refs/tags/vN`, `git checkout vN`, `vN^{commit}`) plus the scaffold default out
  of the root docs and `scripts/`, and **§8a-ter** of `audit-core.sh` holds every one to
  `core.version`'s major — the treatment §8a gives the `ref:` keys and §8a-bis the caller
  examples, one recipe over. The docs keep a **concrete, copyable** major rather than
  "the current alias", the decision the last cut recorded (a ref the reader pastes is not
  a claim they read); the gate is what makes that safe to promise. Exemptions are the true
  sentences a blunter scan would red on: CHANGELOG history, `test-core.sh`'s fixture tags,
  an exact `vN.M.P` freeze, and another repository's tag behind an API path. Fixture-tested
  both directions in `test-core.sh`, including the inverse on this tree and the proof that
  at the next major the scaffold default itself is what surfaces. While correcting that
  recipe, the same four passages (`ARCHITECTURE.md`, `VENDORING.md`, `PORTING-MATRIX.md`,
  the scaffold's own header and `--help`) stopped claiming the scaffold runs
  `git subtree add`: it has materialized the filtered vendor set since #676, and the
  subtree add is the manual fallback that copies the whole tree. Dev tooling only — the
  OS repos receive nothing from this entry.
- **`optoken` no longer leaves a live TOTP in a tmux paste buffer; `clip` grows a
  `--sensitive` mode (`CLIP_SENSITIVE=1`) that it uses (#690).** On a box with no real
  clipboard backend — the headless-over-ssh shelf that is the documented norm for part of
  the fleet — `clip` falls through to OSC 52, and under tmux with Core's own
  `set-clipboard on` that path left the code in a tmux paste buffer, readable by anything on
  the socket via `tmux show-buffer`, for as long as the buffer lived; the only warning was a
  source comment, and the user saw `TOTP sent to the clipboard`. The plain OSC 52 write is
  the leak, not just the `load-buffer` arm: with `set-clipboard on` tmux does not merely
  forward a pane's OSC 52, it also `paste_add`s the payload as an unnamed buffer — so the
  issue's "write the escape straight to the tty" idea would have left the secret exactly
  where the flag promises it will not be. `--sensitive` under tmux therefore never writes a
  plain OSC 52 to the pane: when the pane's `allow-passthrough` is `on`/`all` it wraps the
  sequence in a DCS passthrough, which tmux hands to the outer terminal without parsing, so
  no buffer ever exists; otherwise it loads a **named** buffer with `-w` and deletes that
  buffer in the same breath — a signal landing in that instant deletes it too, by trap — and
  says so on stderr at the moment it matters (with the `allow-passthrough on` line that
  closes the remaining instant). A transient buffer that survives `delete-buffer` is exit 1
  naming the buffer to delete, never a "sent". Outside
  tmux the flag is a no-op on the wire, the real backends (clip.exe/pbcopy/wl-copy/xclip/xsel)
  ignore it, and the default path — nvim's provider, tmux copy-pipe, `pbcopy` — is
  byte-for-byte what it was; `scripts/test-core.sh` §C asserts each of those on the wire
  format, including that the default pane path under tmux (a writable tty) still never
  invokes tmux — the copy-pipe shape with no controlling terminal keeps its `load-buffer -w`
  arm, as before. One limit stays: under nested tmux the outer tmux parses whatever the
  inner one forwards, so the outer server can still hold a buffer. `clip` now
  refuses an unknown argument (exit 2) rather than hanging on stdin; nothing in Core passes
  one. `clip-paste` and `opsecret` are untouched: the first has no OSC 52 read path by
  design, the second prints via `op read` and never touches `clip`. Not tagged BREAKING:
  #690 assumed the default tmux path would change, and it does not — no host adapts.
