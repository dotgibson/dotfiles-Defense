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

### Fixed

- **The potato rules cited the pre-re-measurement figures, and one of them argued the opposite of
  the record it cites.** `2026-08-token-mismatch-sysmon-1.md` was re-measured over the full corpus
  on 2026-08-30 — 147 Sysmon-1 records became **1491**, and four recognised potato captures became
  **six** — but the rules reading it were not updated with it. Seven hand-written locations still
  said 147 / four captures / 4-of-4, across `token_theft_parent_child_mismatch_sysmon_1.yml`,
  `potato_seimpersonate_sysmon_1.yml`, `DEFENSE-METHODOLOGY.md`, `fixture-provenance.tsv` and
  `docker/LAB-VALIDATION-PLAN.md`. Corrected to 5 of 6 over 1491, with the sixth (PrintSpoofer)
  named and explained rather than absorbed into a count: its operator was already an interactive
  admin, so no service identity appears on that event and neither rule can reach it. The count of
  payloads the pair's `Image` list drops was also stale at two — it is three (`notepad.exe`,
  `whoami.exe`, `nc64.exe`), which is a third of the rule's own detections rather than a quarter.
  The `ParentUser`-availability note in both rules said "only the one from a 2022 host carries
  ParentUser"; four of the 1491 do, two of them the `-` placeholder.
  The one that mattered beyond bookkeeping is the rejected negated-filter variant. The rule
  defended rejecting it on the premise that it "finds the same 4 of 4 on this corpus and nothing
  more, so it buys no coverage here" — i.e. rejected *despite* being equivalent, purely on the
  Splunk `NOT`-on-missing-field conversion hazard. The record says the opposite: over 1491 records
  it matches **8**, not 5, and two of the three extra are arguably wanted, so the decisive
  objection is the third — a `ParentUser` of `-`, which does not contain SYSTEM and so passes a
  negated filter, in a corpus where 401 of 1491 records resolve no parent at all. The rule now
  makes both arguments instead of the weaker one. No detection logic changed; the Splunk deploy
  form is regenerated.

- **The potato field semantics are now settled on a cross-channel join, and both fixtures are
  captured records.** Extends the corpus work in #244: the sweep now covers all 278 EVTX rather
  than the 170 matching `sysmon|proc`, which adds 42 Security 4688 records and two more potato
  captures (RoguePotato, PrintSpoofer — six, not four), and the run record is one account rather
  than two. Three things follow. The `User`-is-the-child reading no longer rests on
  Sysmon-internal inference: the corpus holds one sample carrying
  **both** a Sysmon 1 and a Security 4688 for the same process creation, and there Sysmon's
  `User` matches 4688's *Target* while its `LogonId` matches `TargetLogonId` rather than
  `SubjectLogonId` — a numeric identifier carried independently by two providers. A question a
  `ParentUser` rule quietly depends on is now measured: `CreateProcessWithTokenW` is serviced by
  the Secondary Logon service in `svchost.exe`, so had seclogon created the payload rather than
  the tool, `ParentUser` would read SYSTEM and the rule would be inert — on all six captures the
  parent is the tool, with no reparenting, which also rules out the seclogon route to the Creator
  Subject caveat in `token_theft_process_target_subject_4688.yml`. And both potato fixtures are
  now captured records rather than hand-authored ones: the TP is the `cmd.exe` RogueWinRM spawned
  as SYSTEM from a LOCAL SERVICE context, the TN is a genuine PrintSpoofer run whose operator was
  already an interactive admin, so it changes the `ParentUser` value and nothing else about the
  event shape. `ParentUser` itself is still derived on both, and still says so
  (dotgibson/dotfiles-Defense#239).

- **`potato_security_4688.jsonl` was a three-key skeleton, and `token_theft_4688_*` were never
  checked against a real event.** The 4688 potato fixture carried `NewProcessName`,
  `SubjectUserName` and `SubjectUserSid` and omitted the twelve other fields every real 4688
  carries; it is rebuilt on the captured event-version-2 key set and field order, with the Target
  Subject block left **null on purpose** so it does not pre-judge #230. The `token_theft` 4688
  fixtures needed no change — their key set proved identical to six captured 4688s — and that
  rule **fired on real telemetry for the first time**, on a genuine token swap. Its
  pre-Windows-10 falsepositives note is measured now too: captured event-version-1 4688s carry no
  Target Subject block at all and the rule is correctly silent on them. One observation recorded
  rather than fixed — a captured 4688 can populate `TargetUserName`/`TargetDomainName`/
  `TargetLogonId` while `TargetUserSid` reads the null SID, and `TargetUserSid` is the only one of
  the four that rule can see. Five provenance rows move to `vendor-documented`; none reaches
  `captured`, because none of this is first-party.

- **The "a rule naming both channels' fields nulls under either pipeline" claim was false, in
  all six places it appeared.** Repeated by the `potato_seimpersonate` pair, the T1486
  `mass_file_encryption` pair, `host_recon_command_burst`, and twice in `detections/README.md`
  — where it is cited as precedent — the claim was that a pysigma pipeline unable to resolve a
  field drops the whole rule. Measured with the CI pins (`sigma-cli 3.0.2`, `pysigma 1.5.0`):
  it does not. Such a rule compiles under both pipelines with the unresolvable field passed
  through unmapped, and an `OR` of the two field sets fires correctly on each channel. What
  actually makes one rule insufficient is that **the logsource resolves to one EventID per
  pipeline** — `category: process_creation` becomes `EventID=1` under `sysmon` and `4688`
  under `windows-audit`, whichever rule you compile — so a single compiled search covers a
  single channel regardless of the fields it names. The per-channel split is still correct;
  only the stated reason was wrong, and the corrected reason is now what each rule gives.

- **The correlation rules' grouping rationale re-derived
  (`host_recon_command_burst`, `service_stop_burst`).** Their reason for grouping by
  `Computer` inherited the same false mechanism, plus a second error #239 exposed: it named
  Security-4688 `SubjectUserName` and Sysmon-1 `User` as two spellings of one actor. They are
  different principals — `SubjectUserName` is the creator, `User` is the new process — so the
  fields were never counterparts. Measured behaviour is worse than the claim: `group-by`
  fields are passed through **completely unmapped** by both pipelines (`SubjectUserName`
  survives verbatim under `sysmon`) while detection fields *are* mapped, so an account-keyed
  correlation would compile and then bucket every event under one null key, silently voiding
  the threshold rather than failing visibly. `Computer` is now justified on its merits rather
  than as a workaround: a burst is a host-level phenomenon, one operator's burst spans
  identities (land → recon → escalate → recon, the sequence in the RottenPotato webshell
  capture), and an account key would split it into sub-threshold buckets while handing the
  operator a trivial evasion. Actor grouping is reachable post-#239 (`SubjectUserName` /
  `ParentUser`) but would gate the rules on Sysmon 13+ for a reason unrelated to what they
  detect. `service_stop_burst`, which carried no rationale at all, now states one.

- **`check-fixture-provenance.sh` no longer claims every fixture is `unverified`.** Stale
  since `aa02c28`; the ledger has carried `vendor-documented` rows since. Rewritten to
  describe why the distribution is deliberately not gated, without a count that goes stale
  again.

- **`potato_seimpersonate_sysmon_1` was keyed on the wrong field and had never fired on a
  potato (#239).** The rule and `detections/README.md` described it as the Sysmon half of a
  per-channel pair with `potato_seimpersonate_4688`, one shape on two channels. It was not.
  4688's `SubjectUserName` is the account that *created* the process; Sysmon 1's `User` is the
  account of the *new* process. The two agree on an ordinary service-spawns-shell event, which
  is why the pair looked like a twin and why its fixture passed — and they diverge on a
  successful potato, which is the entire technique. So the rule went silent at exactly the
  moment its twin fired, and a host forwarding only Sysmon read as covered for T1134.001 in
  both `detections/README.md` and `detections/navigator/COVERAGE.md` while seeing nothing.
  Measured rather than argued: replayed against four real potato captures on three hosts
  (RogueWinRM, NetworkServiceExploit, RottenPotato from an IIS webshell, EfsPotato) from the
  pinned EVTX corpus, the shipped rule fired on none of them. The selection moves to
  `ParentUser`, which is `SubjectUserName`'s actual counterpart, and the corrected rule fires
  on the two captures whose payload is a named shell. The pairing claim in both rules and in
  `detections/README.md` is now true rather than merely stated. `ParentUser` needs Sysmon
  13.00+, which is a real ingestion constraint and is written into the rule instead of
  assumed — on an older build the field is absent and the selection is silently unsatisfiable
  rather than noisy. Full measurement, and what it does not settle, in
  `docker/validation/labruns/2026-08-potato-sysmon1-user-semantics.md`. The 4688 half is
  untouched and still unconfirmed on a real potato; the first-party run is tracked as
  dotgibson/dotfiles-Defense#246.
  Fixture corrected to the measured shape (it carried no `ParentUser` key at all) and renamed
  to `potato_sysmon1_tp.jsonl`, and the pair gains its first true negative.

- **`make core-check` reported fleet drift from an empty variable.** It printed
  "gh not installed — cannot query upstream tags" and then queried anyway; `gh` failing
  left `upstream_ver` empty, which is never equal to `local_ver`, so it announced
  `• vendored core is 5.4.1, upstream is  — a sync from dotfiles-core is owed`. A
  confidently wrong answer about drift, which is worse than the `127` the same defect
  causes elsewhere. The guard and the query are now one recipe line, and an empty upstream
  is its own branch: it reports **drift UNKNOWN, not current** and exits 1, rather than
  guessing. Found by `_core_make_gate_hits` (dotgibson/dotfiles-core#775), not by eye.

- **`make markdown` announced a skip and then ran anyway.** Each `make` recipe line runs
  in its own shell, so the guard's `exit 0` only ended that line: without `npx` it printed
  "npx not available — skipping markdown" and then ran `npx`, exiting `127`. Collapsed
  into one recipe line, so the skip is a real skip (dotgibson/dotfiles-core#775 — the same
  defect in six other fleet repos). `MD_FILES` was already correct here, so only the guard
  needed fixing, not the scope. An unreadable `MARKDOWNLINT_VERSION` now **fails** rather
  than silently linting unpinned — "same version as CI" is this target's whole claim.
- `.markdownlint.jsonc`'s header claimed this config was "the local README check" and that
  "CI in this repo gates its own code, not its Markdown". Both were true when written;
  dotgibson/dotfiles-core#592 made the markdown leg blocking and it covers all 21
  repo-owned files, not just the README.

### Added

- **`\pipe\srvsvc` and `\pipe\epmapper` join the PipeEvent include list; EfsPotato and
  RoguePotato stop being unwatched on the mechanism plane.** Measured while gathering evidence for #240: every potato in the pinned
  `sbousseaden/EVTX-ATTACK-SAMPLES` corpus that stands up its own pipe uses the nested
  `\<something>\pipe\<endpoint>` shape, and two of the three do it on names nothing collected —
  EfsPotato on `\dd4c18dc-…\pipe\srvsvc`, RoguePotato on `\RoguePotato\pipe\epmapper`, both
  carrying their own `Image` on the create. `detections/sysmon/sysmonconfig-detection-lab.xml`
  dropped both events before Sigma ever saw them, which is the blocking constraint #240 records.
  The entries are deliberately `\pipe\srvsvc` and `\pipe\epmapper` rather than the bare names,
  and the measurement is the same shape twice: 7 of the 61 PipeEvent records match bare `srvsvc`
  and five are ordinary share enumeration (NetShareEnum, NetSessionEnum) arriving as `\srvsvc`
  from `Image=System`; 3 match bare `epmapper` and one is the legitimate endpoint mapper arriving
  as `\epmapper`. The narrow forms collect 2 apiece and leave the routine traffic out. Wanting
  that traffic is a separate decision and a separate rule.
  Worth recording on the `epmapper` side: that legitimate record is `Image=System`, not
  `svchost.exe`, so the `filter_legit: Image|endswith: '\svchost.exe'` #240 proposed would not
  have filtered it. Narrowing the collection is what does the job the Image filter was expected
  to do.
  **No rule reads either name yet**, which is the telemetry-ahead-of-detection hole #225 and
  #229 each closed one name at a time. Both are filed with the collection rather than after it,
  as dotgibson/dotfiles-Defense#248, and the config's comment block — which tracks which rule
  reads which name and why any name is unread — now distinguishes the two kinds of unread name:
  `lsarpc` because a rule there would be unfilterable volume and that is a decision,
  `\pipe\srvsvc` and `\pipe\epmapper` because the rule is owed. Closes
  dotgibson/dotfiles-Defense#240, whose three open questions carry to #248 — the volume one in
  particular, since no legitimate *create* of either name was observed and none of these captures
  spans a boot. `Ledger: unchanged — collection only, no rule, no tactic or technique count
  moves.`

- **A Sysmon-plane rule for the token swap itself, and the Stealth row widens a third time
  (follow-on to #239).** #239 established that Sysmon 1's `User` is the new process and
  `ParentUser` the creator, then used only the creator half to repair
  `potato_seimpersonate_sysmon_1`. `token_theft_parent_child_mismatch_sysmon_1.yml` (id
  `b7f135f0-c066-4b0b-ac45-3f6bb433be38`) uses both: a child running as SYSTEM whose creator
  was an app-pool / NETWORK SERVICE / LOCAL SERVICE identity. That is token theft stated as two
  fields on one event — a service identity cannot spawn SYSTEM without holding a token it did
  not start with — so unlike the potato pair it observes the outcome rather than the shape
  before it, and it takes the TA0005 half of T1134.001 on the reopen condition #223 wrote.
  `Stealth TA0005` goes `3 | 4` → `3 | 5`; the technique count, which is what measures the
  gap, does not move. It carries **no `Image` constraint** on purpose: measured against the
  four real potato captures in the pinned corpus it fires 4/4 where the potato pair fires 2/4,
  the difference being payloads (`notepad.exe`, `whoami.exe`) that no shell list catches, and
  the shell list removes no noise — its only matches across all 147 Sysmon-1 records swept are
  those four swaps. The tidier variant mirroring the 4688 rule's `filter_same_context` was
  rejected on evidence: it compiles to Splunk as `NOT ParentUser="*SYSTEM*"`, where `NOT` on an
  absent field matches, so on a pre-Sysmon-13 host it would fire on every SYSTEM process
  creation while the zircolite backend the gate runs stays silent — a defect the gate is
  structurally unable to see. Measurement in
  `docker/validation/labruns/2026-08-token-mismatch-sysmon-1.md`, including what it does not
  settle: `ParentUser` was still never observed on a real potato (all four captures predate
  Sysmon 13, so it was derived by `ProcessGuid` linkage), the corpus contains no EDR or RMM
  agent so the zero-false-positive result is "not yet met" rather than "does not occur", and
  the locale exposure is reasoned rather than measured.

- **The token-context half of T1134.001 closes, on a different event than #230 asked for
  (#230).** #223 reserved the Stealth half of T1134.001 for a rule that observes the
  impersonation rather than the shape around it, and named two candidates; #225 answered the
  spoolss one. The other candidate was "a token-context anomaly on 4624/4672", and it is
  declined on evidence: neither event is written by this attack. 4624 generates when a logon
  session is created and 4672 when privileges are assigned to a new one, and no live potato
  variant creates one — the pipe-impersonation majority never authenticates at all, the
  local-relay minority rides NTLM's local-call short circuit instead of calling
  `LsaLogonUser`, and `DuplicateTokenEx` preserves `AuthenticationId` so the resulting SYSTEM
  process reuses logon session 0x3e7. Only HotPotato and GhostPotato ever produced that
  shape, and both died with MS16-075 and CVE-2019-1384. Such a rule would have passed its own
  true positive and its own true negative and then sat inert, which is #149 with a Windows
  event id on it.
  What answers it is `detections/sigma/privilege_escalation/token_theft_process_target_subject_4688.yml`,
  on the plane where the telemetry exists. Event version 2 of 4688 carries a Target Subject
  block that Windows populates only when the creator and target "do not share the same
  logon", so a process whose Target Subject is SYSTEM was created with a token that is not
  its creator's — the theft stated as a field. It carries no `Image` constraint, so unlike
  the potato pair it survives a payload that is not a named shell; and because every variant
  ends in `CreateProcessWithTokenW` or `CreateProcessAsUserW`, it sits downstream of the
  DCOM-coerced variants that leave the spoolss rule silent. It takes both tactic tags on its
  own evidence. One assumption travels with it and is written into the rule rather than
  buried: whether the audit reads Creator Subject from the calling process's token or its
  impersonating thread token is inference from Microsoft's documentation, not a capture.
  Ledger: `Stealth TA0005 3 | 3 -> 3 | 4`, `Privilege Escalation TA0004 9 | 12 -> 9 | 13`,
  `T1134.001 3 -> 4 rules`. Tactic TECHNIQUE counts do not move, exactly as #230 predicted —
  the spoolss rule already took the row.

- **The rest of the Sysmon PipeEvent block gets read (#229).** #225 closed one of the five
  pipe names `detections/sysmon/sysmonconfig-detection-lab.xml` collects and left four
  collected-and-unread — the same telemetry-ahead-of-detection hole, one size smaller. Two
  rules close three of them:
  `svcctl_atsvc_remote_pipe_sysmon_18` (Sysmon 18 / ConnectPipe on `\svcctl` and `\atsvc`
  with `Image` = `System`) and `coercion_efsrpc_pipe_sysmon_18` (Sysmon 18 / ConnectPipe on
  `\efsrpc`).
  **This is corroboration, not new coverage, and the ledger should not be read as wider than
  it is.** The service smbexec/psexec installs over `svcctl` is already caught by
  `service_creation_psexec_7045`; the task atexec schedules over `atsvc` by
  `scheduled_task_suspicious_4698`; efsrpc coercion by `coercion_named_pipes_5145` and the
  Suricata `coercion.rules`. What the pair adds is a second, independent plane: the bind is
  visible on the host where those audit subcategories are never forwarded, and it is the
  request rather than the result, so it fires earlier in the chain. Only T1021.002 is a
  genuinely new technique row, and only because nothing here previously named the
  admin-share access itself.
  The invariant was re-derived, not copied. #225's shape was ownership on pipe *creation*,
  and it transfers to none of these: `svcctl`, `atsvc`, `efsrpc` and `lsarpc` are all created
  once at boot by the OS, and every tool in scope *connects* to a pipe already there — so the
  creation half detects nothing on those names and the new rules take the connect half, the
  opposite trade for the opposite reason. Origin replaces ownership: a remote SMB client's
  pipe open is serviced by the kernel SMB server, so `Image` reads `System` rather than a
  local `sc.exe`/`schtasks.exe`, and that is what separates impacket from administration.
  **`lsarpc` deliberately ships no rule.** Sysmon PipeEvent carries no authenticating
  principal, so `coercion_named_pipes_5145`'s `filter_machine` — the block that makes that
  pipe survivable on 5145 — has no counterpart here, and a coercion bind and a routine domain
  bind arrive as byte-identical events. The decline is argued in `DEFENSE-METHODOLOGY.md` and
  recorded in a form that runs: the efsrpc rule's true negative *is* an `lsarpc` bind. The
  cost is stated rather than buried — PetitPotam's default endpoint is `lsarpc`, so 5145
  stays the primary for coercion.
  Both rules ship with `unverified` fixture provenance on purpose. That Sysmon emits an 18
  for a remote SMB pipe open, attributed to `System`, is derived from where the kernel
  services that open rather than observed — the purple-team run that would confirm it has not
  been done, and until it has, the rules' silence means nothing.

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
