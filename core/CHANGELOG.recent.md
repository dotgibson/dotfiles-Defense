# Changelog — recent releases

GENERATED FILE — do not edit by hand. `scripts/gen-changelog-recent.sh` rewrites it
wholesale, `scripts/release.sh` runs that generator on every release, and
`scripts/audit-core.sh` §9e fails when this file is not byte-identical to a fresh
render. To fix a conflict or a stray edit, re-run the generator — never patch it.

The last 8 released sections of `CHANGELOG.md` (v7.7.0 … v7.4.0), vendored into every OS repo's
`core/` by `core.vendor` so `core whatsnew` can answer offline. The full changelog is
repo-meta and stays upstream:
[dotgibson/dotfiles-core/CHANGELOG.md](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md).

## [v7.7.0] - 2026-09-15

### Added

- **`bootstrap-test.yml` learns the staged host: the `provisioner:` input, the sweep's
  VM-only skip, the register's `real-bootstrap` gate, and the scaffold's stamps** (#1050,
  runbook step 2 of `NON-MUTABLE-HOST-PROPOSAL.md` §4.6). A container is not the host
  (no `/run/ostree-booted`, a writable `/usr`), so a variant repo's stubbed provision walked
  its mutable branch and never reached the staging path (R6, measured). `provisioner:
  atomic|transactional` (empty = mutable, unchanged) exports `BOOTSTRAP_PROVISIONER` into
  the provision-stub run, shims `rpm-ostree bootc transactional-update snapper btrfs`,
  makes the `rpm` shim answer `-q` with 1 so the variant's base-image filter keeps its
  names, and fails the leg unless the run prints the staged closing line ("reboot to
  apply"). `scripts/fleet-bootstrap-matrix.py` skips such a caller (the unstubbed sweep
  would install down the mutable branch) and names it VM-only via a `::notice::` that
  `real-bootstrap.yml` writes into the run summary. `scripts/fleet-coverage.sh` grows a
  derived `real-bootstrap` gate: `sweep` for a mutable caller, `real-bootstrap none <why>`
  required of a provisioner-only repo, and a caller-less repo inherits its `bootstrap-test`
  declaration. `scripts/new-os-repo.sh` stamps `PROVISIONER` / `PKG_APPLY` /
  `PKG_APPLY_PENDING` as commented examples into the capability stub and shows the staging
  shape of a provision hook in the starter bootstrap. (`scripts/test/{33-bootstrap-matrix,
  35-new-os-repo,56-fleet-vocabulary}.sh`)

## [v7.6.0] - 2026-09-15

### Added

- **`up`, the shell-start nudge, the maint runner and `core-doctor` learn the staged
  host** (#1049, runbook step 1 of `NON-MUTABLE-HOST-PROPOSAL.md` §4.6). Three optional
  declaration keys — `PROVISIONER`, `PKG_APPLY`, `PKG_APPLY_PENDING` (+ `_EXIT`) — are read
  for the first time, and every branch is on a key the nine mutable repos never declare, so
  their behaviour and their nudge cache are byte-identical. On an atomic (bootc) or
  transactional (MicroOS) host: `up` closes with `staged — reboot to apply: <PKG_APPLY>`
  (the verb is printed, never run), `up -n` with no count verb says the host stages instead
  of "nothing to upgrade", and the nudge prints **`󰚰 update staged — reboot to apply`** in
  place of a count. The STAGED question is asked by the refresh (`_pkgup_refresh`, and
  the maint runner after its optional apply) and cached as lines 3–4 of `pkg-updates`
  (`staged`/`idle` + the kernel's boot id), so the per-shell path stays fork-free and a
  reboot silences the line at the next shell. `MAINT_UNATTENDED_UPGRADE` under `atomic`
  is stage-only and logs `staged — reboot to apply (never run by this runner)`;
  `declarative` (NixOS) is treated as mutable, `_pkgup_mgr` answers the `PROVISIONER`
  token when no manager is on PATH (so `up` no longer refuses NixOS), and `core-doctor`'s
  install hint says "reboot to use" over a staged change and "add it to `home.packages` /
  `environment.systemPackages`" on a declarative host. Unit tests are the R5 shim replay:
  the research declarations' package half against stub managers answering with the
  measured exit statuses. (`zsh/02-capabilities.zsh` `_core_cap_staged`,
  `zsh/60-update.zsh`, `maint/dotfiles-maint.sh`, `zsh/30-functions.zsh`,
  `scripts/test/{65-functions,73-maint-runner,74-zsh-helpers}.sh`)

- **The R4 harness for the non-mutable host research, and its answer** (#1004). Two
  prototype patches under `scripts/research/nonmutable/r4/` give `dotfiles-Fedora` and
  `dotfiles-openSUSE` an atomic / transactional _variant_ (a host marker, a second
  declaration relinked by `bootstrap_wire_pre_loader`, a staging path, a "reboot to
  apply" line); `scripts/research/nonmutable-variant.sh` applies and runs them on the
  booted guests, and `research-nonmutable-vm.yml`'s `r4=true` input drives the run,
  reboot and re-run. Measured verdict, in `NON-MUTABLE-HOST-PROPOSAL.md` §5: **variant**
  (118 + 18 and 65 + 10 lines; NixOS stays a new repo). The `trailing-whitespace`
  pre-commit hook now leaves `*.patch` alone — a blank diff context line is a lone space.

- **`PKG_APPLY_PENDING` / `PKG_APPLY_PENDING_EXIT`, the staged-change probe, for the
  non-mutable host research** (R5 of `NON-MUTABLE-HOST-PROPOSAL.md`, #1004).
  `scripts/check-capabilities.sh` accepts the pair (optional; the probe needs `PKG_APPLY`
  beside it, the exit is 1–255) and lets `PKG_COUNT_PENDING` be absent when it is
  declared — on an atomic host the "is there something newer" verb is root-only
  (measured), so the nudge reports the staged state instead. Read by no consumer yet; the
  bootc and MicroOS prototypes under `scripts/research/nonmutable/` declare it. Also the R5
  harness (`scripts/research/nonmutable-r5.sh`, the VM legs' `r5=true`, a registry-backed
  bootc origin). (`scripts/check-capabilities.sh`, `examples/os.capabilities.example`,
  `scripts/test/55-capabilities.sh`)

- **The R6 harness for the non-mutable host research, and the research phase's close**
  (#1004). `scripts/research/nonmutable-r6.sh` runs the reusable `bootstrap-test.yml` legs'
  own recipes inside the three container images against the R4 variant, plus the same
  stubbed run with `BOOTSTRAP_PROVISIONER` forced — the seam the variant patches carry so
  a container can reach the staging path at all; `research-nonmutable.yml`'s `r6=true`
  drives it. `NON-MUTABLE-HOST-PROPOSAL.md` §5 carries the CI matrix a target is born
  with, the VM-only gap list, and the note that every exit criterion is met — the next
  step is the §4 rewrite to PROPOSED.

- **`NON-MUTABLE-HOST-PROPOSAL.md` is PROPOSED** (#1004). §4 is now the proposal — a
  minor, not a major: the six optional capability keys (shipped), three consumer changes
  (`up` and the nudge, the maint runner, `core-doctor`), one CI input
  (`bootstrap-test.yml` `provisioner:`), atomic / transactional variants for
  `dotfiles-Fedora` and `dotfiles-openSUSE`, and a `dotfiles-NixOS` repo with the
  home-manager boundary written down — with §4.6 as the per-repo runbook and every line
  citing §5's measurements. The former §6 and §8 stay as the record of what a major would
  have cost and what was asked.

### Fixed

- **The `~/.zshrc` loader's backup is counted** (#1026). `blib_write_zshrc_loader` backed up
  a pre-existing real `~/.zshrc` and warned about it, but never bumped `BLIB_BACKED`, so the
  closing tally said `0 backed up` on the same run that printed the backup (the R3 research
  run on Fedora exposed it). Every backup site now counts; the bootstrap-lib suite asserts it.

## [v7.5.0] - 2026-09-14

### Added

- **Four prototype `os.capabilities` keys, for the non-mutable host research** (R2 of
  `NON-MUTABLE-HOST-PROPOSAL.md`, #1004). `scripts/check-capabilities.sh` accepts
  `PROVISIONER` (`mutable` | `atomic` | `transactional` | `declarative`), `PKG_APPLY` (the
  verb that makes a staged change live), and `PKG_PENDING_EXIT_SOME` / `_NONE` (a count
  verb whose answer is its exit status) — all optional, all read by no consumer yet — and
  lets `PKG_COUNT_PENDING` be absent under `PROVISIONER=declarative`. Every existing
  declaration validates unchanged. The three prototype declarations they were written for
  live under `scripts/research/nonmutable/`, each validated, with the R2 verdict
  (additive — no schema version, no re-author) in their README. (`scripts/check-capabilities.sh`,
  `examples/os.capabilities.example`, `scripts/test/55-capabilities.sh`)
- **The R3 harness for the non-mutable host research, and its answer** (#1004).
  `scripts/research/nonmutable/home.nix` is a home-manager module that tries to own
  everything the driver wires as out-of-store links into the vendored `core/`;
  `scripts/research/nonmutable-home-manager.sh` applies it, runs the repo's
  `bootstrap.sh --links-only` over the result, switches again and records who owns each
  path. `research-nonmutable.yml` gained a `homemanager` leg (Fedora 42, standalone) and
  `research-nonmutable-vm.yml`'s NixOS guest applies it as a NixOS module. Measured
  verdict, in `NON-MUTABLE-HOST-PROPOSAL.md` §5: **coexist** — the driver overwrites
  home-manager's links silently, home-manager tolerates the driver's links but refuses to
  activate over its zsh entry, so a fleet `home.nix` owns packages, the shell declaration,
  tpm and PATH and declares no files.

### Fixed

- **The sudo keepalive no longer dies on a non-interactive run whose sudo needs no
  password** (#1018, found by the non-mutable-host research on a booted bootc guest). The
  prime was a bare `sudo -v`, and sudoers' default `verifypw=all` makes `-v` prompt unless
  _every_ rule matching the user is NOPASSWD — Fedora's stock wheel rule beside a NOPASSWD
  drop-in is one passworded rule too many, so a run with no terminal ended "authentication
  failed" on a host where every command was passwordless. `blib_sudo_keepalive_start` now
  primes by how the run can answer: `-v` at a terminal; `-A -v` when `SUDO_ASKPASS` is set;
  otherwise `-n -v`, then `-n true`, then a warning that names the actual problem (no
  terminal and a password required) before the driver's "cannot provision packages" line.
  (`lib/bootstrap-lib.sh`, `scripts/test/85-escalation.sh`)

## [v7.4.4] - 2026-09-13

### Changed

- **`new-os-repo.sh` scaffolds the starter bootstrap in the driver form** (#999). A repo
  born from the generator declares what it is (`BOOTSTRAP_NAME`, `BOOTSTRAP_OS`,
  `BOOTSTRAP_LOGIN_SHELL=0` — a starter must not `chsh`), links its ZDOTDIR entry pair in
  `bootstrap_wire_post_loader`, and hands over to `blib_main` — the shape all eight fleet
  repos on the driver have (#986) rather than the one they just left. The starter's hand
  copy of the link step (and of `blib_link`'s backup suffix, "keep the two in step") goes,
  and so does its `zsh/zshrc.zsh` copy of the loader: the driver writes the managed
  `~/.zshrc` and seeds `$ZDOTDIR/.zshrc` as a symlink to it, one definition for the fleet.
  The generated `test/check-links.sh` asserts that shape, stands a placeholder in for the
  tpm clone (the one network fetch in the wiring; the suite tests links, not GitHub), and
  keeps its three idempotency witnesses — which now hold the driver to the same bar.
  (`scripts/new-os-repo.sh`, `scripts/test/35-new-os-repo.sh`)

### Fixed

- **A second bootstrap run invokes no mutating command** (#999, found by holding the
  driver to the scaffold's idempotency witness). `blib_link_core` ran `chmod +x` on Core's
  tmux scripts and `bin/` tools and `mkdir -p`/`chmod 700` on `~/.ssh` on EVERY run, and
  `blib_install_core_guard` rewrote an identical pre-commit hook every time — no-ops on
  disk, but a witness that logs every `mkdir`/`chmod` reads each as a change. Every one
  now asks first (`_blib_ensure_exec`, `_blib_private_dir`, a byte compare against the
  hook text held in `_blib_core_guard_hook`) and the hook's bytes are unchanged.
  (`lib/bootstrap-lib.sh`)

## [v7.4.3] - 2026-09-13

### Changed

- **Alpine is on the bootstrap driver, MacBook is exempt by design — the `blib_main` row
  closes at 8/9 + 1 exempt** (closes #986; dotgibson/dotfiles-Alpine#194, on v7.4.2). Alpine
  declares doas-first (`BOOTSTRAP_SU_PREFER=doas`) and the driver resolves with it; its
  `~/.zshenv` ZDOTDIR shim takes the post-loader slot, and its root-probe test now pins the
  declaration plus the hand-over instead of a literal `blib_resolve_su` call. MacBook's
  `--json`/`--uninstall`/`--quiet` surface and its own reporting channel are a consumed
  contract the driver does not model, so §5f records the exemption with that reason
  rather than a gap — the assertion is that no bootstrap in the fleet is on the pre-driver
  shape by accident. Eight repos run on the driver; the starter that `new-os-repo.sh`
  writes is the one bootstrap still in the old shape (#999).
  (`scripts/audit/40-fleet-registers.sh`)

- **Arch is on the bootstrap driver — the `blib_main` row reads 7/9** (#986;
  dotgibson/dotfiles-Arch#174, on v7.4.2). The rolling-release repo declares its
  exit-1-on-any-miss contract (`BOOTSTRAP_STRICT_DEFAULT=1`) instead of hand-rolling it;
  the Arch check is `bootstrap_guard`, the pacman phase is `bootstrap_provision` with the
  body unchanged, the dry-run preview is `bootstrap_check`, and its `-E` ERR trap stays,
  stepping aside for the driver's own `return` verdicts. 446 → 421 lines.
  (`scripts/audit/40-fleet-registers.sh`)

- **Offense and Gentoo are on the bootstrap driver — the `blib_main` row reads 6/9** (#986;
  dotgibson/dotfiles-Offense#328, dotgibson/dotfiles-Gentoo#187, both on v7.4.2). The two
  lazy-escalation repos: Offense declares `BOOTSTRAP_ROLE=offensive`, no login shell and
  `BOOTSTRAP_SU=lazy`, so only `--install` escalates, inside its own hook; Gentoo declares
  lazy too and keeps its `--user` fallback — the guard resolves an escalator and downgrades
  to user mode when there is none, the provision hook primes the keepalive itself, and
  `provision_user` folds into `bootstrap_provision`. Both keep their package bodies verbatim.
  619 + 1316 → 551 + 1236 lines. (`scripts/audit/40-fleet-registers.sh`)

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
