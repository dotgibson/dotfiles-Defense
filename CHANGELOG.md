# Changelog

All notable changes to this repo's own layer — the defensive role layer
(`detections/`, `defense/`, `docker/`, `install/`), `bootstrap.sh`, and the tooling
around the vendored `core/` subtree.

**Not** in scope: changes inside `core/`. That is a vendored copy with its own
changelog
([dotfiles-core](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md)).
A sync that bumps `core.lock` is worth a line here; the upstream contents are not.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**This file starts at the point it was added, and deliberately does not backfill.**
The repo has 69 tags, and every one of them is an automatic patch bump that
`auto-tag.yml` cut in response to a `core/**` push — so the tag history records *what
was vendored when*, not a maintained release line. Reconstructing 69 headings from it
would produce 69 lines of "Core was bumped", which is both untrue as a changelog and
already recorded in `core.lock`. `dotfiles-Offense`, this repo's mirror, reached the
same conclusion: 87 tags, no version headings, and a note saying why. Real entries go
under `[Unreleased]` from here.

## [Unreleased]

### Added

- **`spoolss_pipe_impersonation_sysmon_17` — the one hole where the telemetry was already
  enabled and no rule consumed it (#225).** `detections/sysmon/sysmonconfig-detection-lab.xml`
  has collected Sysmon PipeEvent 17/18 on five pipe names since it was written, with a
  comment saying it exists to corroborate `potato_seimpersonate` — and no Sigma rule
  selected it. Both potato rules told the analyst to "confirm the SYSTEM outcome with
  Sysmon 17/18 on the spoolss/DCOM named pipe", which was an instruction to go read
  telemetry the corpus collected and had no detection for. The ingestion was done ahead of
  the detection and the detection never followed.
  The new rule closes that. Its invariant is ownership rather than content: legitimate
  `spoolss` pipes are created by the print spooler, and PrintSpoofer-class tools stand up
  their *own* pipe and coerce the spooler into connecting to it, so a non-spooler process
  creating one is the anomaly. That is a shape, not an IOC — it survives renaming the
  binary. It is pinned to `EventType: CreatePipe` deliberately: `category: pipe_created`
  resolves to 17 *and* 18, but the only connect the attack generates is the spooler binding
  back, which the rule's own `spoolsv.exe` filter removes — so everything surviving the
  filter on 18 would be ordinary print traffic. Signal on 17, noise on 18.
- **This reverses the standing decision in #223/#224, on the terms that decision set.** Those
  issues declined the TA0005 (Stealth) half of T1134.001 for the `potato_seimpersonate` pair
  because what the pair selects is a service identity spawning a shell — the shape *before*
  the token is stolen — and recorded a reopen condition: a rule that actually detects the
  impersonation "earns the TA0005 half on its own evidence, and should take it". This is
  that rule, and it takes both tactic tags. The pair still declines, and
  `DEFENSE-METHODOLOGY.md` now records the argument as settled rather than pending; the
  4624/4672 token-context half of the reopen condition remains open. Ledger:
  `Stealth TA0005 2 | 2 -> 3 | 3`, `Privilege Escalation TA0004 9 | 11 -> 9 | 12`.

- **`htpx-drift.yml` — a weekly question about the pinned corpus, and a correction to what
  #202 claimed.** Pinning htpx (`detections/htpx.pin`) is what makes `check-htpx-pairing.sh`
  reproducible, and it opens one specific hole: **the gate reads the pinned sha, but the
  `references:` URLs the rules write point at `/blob/main/`.** So if upstream removes or
  renames an entry this repo names, the link is a live 404 for anyone who clicks it while CI
  stays green. Nothing watched for that. This does, weekly, and the report leads with exactly
  those entries.

  **The correction.** #202's commit message and PR said `bloodhound-sharphound` "was renamed
  `bloodhound-collect` upstream". That is wrong, and the distinction matters. Checked against
  htpx's full history: `bloodhound-sharphound`, `bloodhound-sharphound-4662`,
  `archive-staging-rar`, `local-data-collection` and `rogue-account` have **never existed** in
  that repo — not as a file, not as an `id:`, in any commit. All eight dead references were
  ids written *here* that were never right, not upstream drift. The fix was the same either
  way, and `check-htpx-pairing.sh` catches that class permanently at author time. But the
  rename story would have made this workflow look like a response to something that had
  already happened, when the hole it covers has not bitten yet. It is a cheap weekly question,
  not a reaction.

  **It reports on corpus changes, not commits.** A pin behind by a README edit or a
  `.gitignore` commit is behind by nothing — only two gates read this corpus and both read
  `entries/` alone. Verified against real history: two consecutive upstream commits that
  touched no entry produce no issue. Filing for those is the nagging `core-drift.yml`'s header
  says it refuses to do, and a weekly nag becomes a weekly ignored issue.

  Report-only, like `core-drift.yml`: one deduplicated issue via the existing
  `file-routine-issue.sh`, nothing changed. Bumping the pin stays deliberate, because a bump
  moves `HTPX-COVERAGE.md` and that diff is the point.

  `check-htpx-pairing.sh` gained `--list-claims`, a data query printing every entry this repo
  names. The workflow uses it rather than re-implementing "what counts as a claim" in YAML —
  that definition already has two readers, and a third would be how they start disagreeing.

- **The Defense↔htpx link is checked, not just asserted — `check-htpx-pairing.sh` plus a
  drift-gated `HTPX-COVERAGE.md`.** `detections/README.md` opens by promising that each
  rule names the exact Offense fold and **htpx pair** that reproduces it, "so the purple
  loop is closed in the file itself". Rules kept that promise in three places — ~84
  `references:` URLs, an `htpx pair <id>` in each validation note, and 82 cells of the
  `Validate with (Offense fold · htpx pair)` tables — and **nothing verified any of it**.
  htpx is a separate repo on its own release cycle, so an entry renamed there left a rule
  here pointing at a 404, and the only way to find out was for someone to click the link.

  The split is the design decision #196 asked for, and it is deliberate:

  - **Claims are a hard gate.** Naming an entry is a factual assertion about another
    repo — it is true or it is false. `check-htpx-pairing.sh` resolves every named entry
    against the pinned corpus and checks the blue ones still pair back to a red entry
    that points at them.
  - **Gaps are a report.** `HTPX-COVERAGE.md` renders which blue entries this repo
    claims, which it does not, which techniques here the corpus has no attack for, and
    which entries htpx declares unpaired. It never fails on a gap and it is drift-gated,
    so a change in the shape of the boundary arrives as a reviewable diff. htpx spans
    Okta, Workspace, GitHub Actions, GitLab, Jenkins, Harbor, Vault, Terraform Cloud,
    Snowflake, Cloudflare, npm and PyPI; a bidirectional foreign key would be red forever
    and silenced within a week. The issue predicted exactly that.

  **Declared holes are excluded by field, not by an allowlist.** htpx now requires
  `pair_note:` on any entry carrying `pair: null`
  ([htpx#98](https://github.com/dotgibson/htpx/pull/98)), so the report reads the upstream
  reason verbatim instead of keeping a local copy of someone else's decision — which is
  the thing that goes stale.

  **The corpus comes from a pinned commit** (`detections/htpx.pin`), fetched by
  `htpx-corpus.sh`. Same argument as `attack-data.pin`: a check whose answer depends on
  what upstream did this morning is not a gate. No `sha256` field, because the pin names a
  git commit and git's own object hashing already binds it — verifying HEAD against the
  pin *is* the digest check. This repo deliberately does not vendor htpx as a subtree the
  way Offense does; two gates read it, and a ~200-file subtree plus a second sync
  obligation is a steep price for that.

  **Adopted after fixing what it found, in the same PR** — the standard
  `check-rule-coverage` and the Splunk precedence gate were held to. Eight dead names:

  - `bloodhound-sharphound` / `bloodhound-sharphound-4662` were renamed
    `bloodhound-collect` upstream — a dead `references:` URL, a dead validation note, and
    a dead table cell.
  - `archive-staging-rar`, `local-data-collection` and `rogue-account` named entries htpx
    has **never had** — the corpus's Collection and Exfiltration entries are all SaaS-side
    and it has no account-creation entry at all. Those rules now say so in prose rather
    than naming a phantom, which reads as a working cross-reference.

  Half of those were in the README table, which is why the gate reads that column too and
  not just the rules.

- **`host_enum_srvsvc_wkssvc_5145` now cites its htpx blue entry.** The rule's validation
  note has named the red side (`smb-enum-nxc`) since it was written, but the corpus had no
  detection to put beside it —
  [htpx#97](https://github.com/dotgibson/htpx/issues/97) tracked that hole for exactly this
  rule. `entries/blue/smb-enum-5145.md` is now upstream, ported from this rule, and the
  rule references it. It is the first edge the new gate was built to verify, so the gate
  ships with a live cross-boundary link rather than an empty set.

- **The repo hygiene surface: `Makefile`, `CONTRIBUTING.md`, `.editorconfig`,
  `.gitattributes`, and the PR/issue templates.** This repo and `dotfiles-Offense` are
  deliberate mirrors — equal CI weight at 14 workflows each, and Defense carries *more*
  tracked files — but Defense was the only repo in the fleet missing all of these at
  once.

  The `Makefile` is the one with immediate value: every gate here was already real and
  already scripted, but there was no front door, so reproducing CI locally meant reading
  `.github/workflows/` and reconstructing the command list by hand. It wires what
  exists — `tests/lint-shell.sh`, `tests/test-defense.sh`, the four `--check` drift
  gates, the methodology and validation-coverage gates, `lab-smoke.sh` — and reads
  `MARKDOWNLINT_VERSION` from the vendored Core pins so a local run matches CI exactly.

  **Offense's target list was not ported wholesale**, because that would have recreated
  in reverse the exact bug Offense's Makefile was written to fix: `core-sync`,
  `core-lock` and the `companion-*` targets name scripts this repo does not have (Core
  is pushed *into* here by `dotfiles-core`'s own `make sync`, and this repo vendors no
  htpx companion). They are absent rather than stubbed.

  `.gitattributes` is the one with teeth. `dotfiles-Arch/CLAUDE.md` documents what its
  absence costs when a repo is touched from Windows over a UNC share: a `.sh` that
  picks up CRLF gets a shebang of `…/env bash\r` and dies with *"bad interpreter"* —
  text that looks perfectly valid and that both `shellcheck` and `bash -n` accept. It
  also pins `*.rules`, `*.zeek` and `*.pcap`, which are this repo's product and are
  parsed by tools that are not uniformly CRLF-tolerant.

  Adding this file also makes Defense visible to `dotfiles-web`'s changelog feed, which
  derives from each repo's `CHANGELOG.md` and had been skipping this one for want of the
  file. (dotgibson/dotfiles-Defense#196)
