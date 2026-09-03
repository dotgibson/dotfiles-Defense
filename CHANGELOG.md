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

- **The SUID tripwire tested the wrong argument for the one chmod that matters, and the history
  rule watched a syscall that could never be recorded.** Both are documented auditd rules rather
  than Sigma logic, which is why neither fixture nor gate could see them. `suid_bit_set` shipped
  `-S chmod,fchmod,fchmodat -F a1&04000`, but the mode is `a1` only for `chmod(path, mode)` and
  `fchmod(fd, mode)`; `fchmodat(dirfd, path, mode, flags)` carries it in `a2`, so for every
  `fchmodat` the kernel ANDed a **pathname pointer** against 04000 and recorded or dropped the
  event depending on where the string happened to sit in memory. That is not a corner case:
  `fchmodat` is what coreutils and glibc's `-at` paths call, and it is the only path-based chmod
  that exists on **arm64**, which has no `chmod` syscall at all — so on an arm64 host the whole
  rule rested on the broken predicate. Now split by argument position, four lines instead of two,
  with the arm64 load failure and `fchmodat2` both written down. `history_clearing` had the twin
  defect one layer along: it listed `ftruncate`, which takes a descriptor and emits no PATH
  record, so under `-F dir=` it was never recorded — dead in the list rather than merely noisy —
  while `: > ~/.bash_history`, the canonical clear, is an `open` with `O_TRUNC` and was not in the
  list at all. Replaced with `open`/`openat` O_TRUNC lines (flags in `a1` and `a2` respectively,
  the same split), and coreutils `truncate -s0` is now named as genuinely unreached from the file
  plane rather than silently missed. Neither rule's Sigma changed; both descriptions now predict
  what a lab run must show, including the `truncate -s0` non-result.

- **Three auditd rules assumed an ingestion model nothing stated.** `ssh_authorized_keys_write`,
  `ssh_private_key_read` and `history_clearing` match `key` (SYSCALL record) and `name` (PATH
  record) in one selection, which only works where the pipeline coalesces the records of one
  auditd event into a single document — auditbeat/Elastic and the Splunk auditd TA do, a raw
  line parser does not, and there the three are inert while the key-only rules beside them keep
  working. Stated in each rule and in `detections/README.md`, alongside a note that syscall
  argument positions are per syscall rather than per family.

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

- **The potato runbook now says what it predicts, and four things in it were wrong.** #246 is
  host-bound and stays open — every one of its three items needs a Windows host running a real
  potato, and no second public corpus fills the gap (`OTRF/Security-Datasets` carries no potato
  or SeImpersonate capture at all). But the runbook is what decides whether that eventual run is
  worth anything, and it named a fixture that does not exist (`potato_sysmon1.jsonl`; it is
  `potato_sysmon1_tp.jsonl`), specified a target OS its own tool table cannot run on —
  JuicyPotato's DCOM route was fixed in Windows 10 1809 / Server 2019, which is why RoguePotato
  exists, so on any build modern enough to guarantee 4688 event version 2 the row meant to settle
  the `CreateProcessAsUser` vs `CreateProcessWithTokenW` question would silently not run — and
  asked for no attack producing a **true negative**, so a run following it would have promoted
  each TP to `captured` and stranded its TN at `vendor-documented`: a mixed-tier pair asserting a
  discrimination only half of it can support. It also never stated `check_near_miss`'s
  identical-key-set contract at the capture step, which cannot be satisfied once the host is gone.
  The firing table is now six rows, the three open items carry pre-committed predictions (the
  convention `2026-08-sysmon18-remote-pipe.md` reports against, so the record cannot be composed
  to fit the log), and a `Filing the result` section states per fixture what a result can promote
  — including that #246's own claim that closing it moves `token_theft_sysmon1_*` is wrong by
  citation, because that TP is a synthetic host (`WEB01`) and reaches `captured` only if replaced.
  Adds the `-`-placeholder outcome the runbook did not anticipate despite 401 of 1491 swept
  records hitting it, the missing `evtx-to-fixture.sh` stdout redirects, and the zircolite replay
  commands its sibling runbook already carried.

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

### Changed

- **Five rules matched one spelling of an action that has more than one.** Each was evadable by
  a caller who reached the same outcome through the sibling API, and the corpus review (#261)
  found them together. `gcp_service_account_key_created` selected only
  `CreateServiceAccountKey`, missing `UploadServiceAccountKey` — the caller brings their own
  public key, so the private half never transits Google at all, which is the version an attacker
  prefers. `okta_mfa_factor_reset` did not select `user.mfa.factor.suspend`, Okta's own
  suspected-compromise action, which takes a factor out of use without deactivating it. (The
  review also proposed a singular `user.mfa.factor.reset`; Okta defines no such event type, a
  single-factor reset emits `deactivate`, and the rule now records that so it is not re-raised.)
  `github_credential_backdoor` did not see `integration_installation.create` — installing a
  GitHub App mints an installation token for as long as the install stands, the quietest durable
  credential of the three the rule now covers. `gitlab_token_backdoor` was missing the two
  group-scoped token events, the widest blast radius of the set. `vault_approle_backdoor` matched
  `auth/approle/role/` literally, so a role minted under an already-enabled jwt, kubernetes, aws
  or token backend — the same durable machine identity, one path over — walked past it; it now
  matches the role path under every backend.

- **The Kubernetes escape rule's hostPath branch matched only the literal `/`.** A mount of
  `/var/run/docker.sock`, `/run/containerd`, `/proc`, `/etc`, `/root` or `/var/lib/kubelet` is a
  node takeover on its own and produced no alert. Now the root mount plus a prefix list, with
  `hostIPC` added as a scalar branch beside `hostPID`. `hostNetwork` was considered and declined
  in the rule: it is not an escape by itself and it is precisely the CNI/node-agent request the
  rule's own false positives name. The documented array-traversal caveat is unchanged and still
  governs the two array-keyed branches.

- **`snowflake_network_policy_change` fired on statements that read a policy.** It excluded
  `SHOW` but not `DESCRIBE`/`DESC`. `filter_show` is now `filter_readonly` and covers both.
  `GRANT ... ON NETWORK POLICY` stays selected on purpose — it changes no allowlist, but a
  `GRANT OWNERSHIP` on the enforced policy is the step before an attacker can alter it.

- **Four proposals from the same review were declined, in the rules themselves.** A decline that
  lives only in an issue gets re-proposed next cycle. `sudo_root_shell` keeps `comm` and its
  interpreter list: `exe` resolves symlinks, so an `exe|endswith` list silently loses hosts where
  `/bin/sh` is dash or `python3` is `python3.14`, and dropping the list turns a detection into a
  log of every command run through sudo — the GTFOBins escapes it is accused of missing exec a
  listed shell as a child and are caught there. `k8s_clusteradmin_binding` does not gain
  `verb: [escalate, bind]`: those are RBAC authorization verbs, never the verb of an audit event,
  so the selection would match nothing while reading as coverage. `jenkins_job_backdoor` does not
  add `config.xml`: the Audit Trail plugin's default pattern does not log it, and the logged line
  carries no HTTP method, so the branch could not separate the malicious POST from the routine
  GET. `jenkins_api_token_created` keeps no filter block: this corpus has no verified Jenkins
  actor field, and inventing one produces a filter that passes its own fixture and matches
  nothing in production — the hazard `fixture-provenance.tsv` exists to expose.

### Added

- **T1537 Transfer Data to Cloud Account — `detections/sigma/cloud/aws_snapshot_share_external.yml`
  (#262).** The corpus had no detection for exfil that never crosses an egress boundary. An
  attacker snapshots a volume, grants restore rights to an account they control, and copies it
  from there; the bytes move inside AWS's own address space over AWS's own APIs, so the wire
  plane, DLP, and `aws_s3_bulk_exfil`'s object-read volume signal all stay quiet. Both existing
  Exfiltration rules key on crossing an external boundary — `slack_external_shared_channel` on an
  invite out, `snowflake_data_unload` on `COPY INTO` an external location — and T1537 is
  definitionally the case that does not, so this is the one exfil family that had no
  representative at all rather than thin coverage of a covered one.

  It is the inverse of the two CloudTrail rules beside it. `ModifySnapshotAttribute`,
  `ModifyImageAttribute` and the RDS pair are MANAGEMENT events, in every trail by default, where
  `aws_s3_bulk_exfil` and `aws_data_destruction` both go half-blind without S3 data-event logging.
  So it needs no new telemetry — which is why it was authorable at all, and what separates it from
  every entry in the declined ledger, each of which is blocked on telemetry the estate lacks.

  Two tiers, because only one needs tuning. A grant to `group: all` is public, fires with no
  allowlist, and is correct on day one; a grant to a named account is a finding only once
  `filter_own_accounts` holds your own account IDs. The condition puts the public arm OUTSIDE the
  filter deliberately, which is recorded in `detections/siem/splunk-precedence-allowlist.tsv`
  because the compiled SPL relies on search-command precedence to bind it — traced, not assumed.

  Keyed on the `.add.` path rather than the bare verb, which scopes out two non-events at once:
  `ModifySnapshotAttribute` also sets a description, and the `remove` half of the same call is the
  attacker's cleanup. Both are proven inert by the true-negative fixture, alongside a share to an
  allowlisted account. Its blind spot is stated in the rule: the attacker's `CopySnapshot` runs in
  THEIR account and never reaches the victim's trail — the same geometry that keeps `CopyObject`
  out of the S3 rule — and a share -> copy -> un-share sequence leaves a clean permission list, so
  a posture sweep over currently-shared snapshots is not a substitute for the event stream.

- **`detections/htpx.pin` -> v3.1.0 (`7ea71779365c`).** Carries the
  `aws-snapshot-share-exfil` <-> `aws-snapshot-share-cloudtrail` pair the rule above names.
  Authored red-first upstream (dotgibson/htpx#115) so the purple loop closed before the rule
  existed, rather than shipping the corpus's only unpaired rule.

- **Seven rules that named a benign false positive in prose now carry the filter block to
  suppress it.** Each documented the noise and left the reader to hand-edit the rule:
  `shadow_credentials_keycredentiallink_5136` (`filter_whfb` — the rule prescribed a Windows
  Hello allowlist its detection never implemented, so in any WHfB tenant this `high` rule fired
  on every legitimate key enrollment; the on-prem key-trust self-write, where Subject equals the
  object, is named as needing a SIEM-side comparison Sigma cannot express),
  `gcp_service_account_key_created` (`filter_iac`, for parity with its GCP siblings),
  `harbor_robot_account_created` (`filter_provisioning`), `entra_directory_role_grant`
  (`filter_iga` — PIM/IGA automation, with a note NOT to allowlist the PIM service whose
  operations the rule deliberately selects), `bitlocker_abuse_encryption` (`filter_provisioning`
  on the imaging task-sequence parent), `ldap_recon_explicit_creds_4648`
  (`filter_sweep_principals`, present in its sibling discovery rules but not here — the
  correlation's threshold is no substitute, a scanner clears it every cycle), and
  `github_self_hosted_runner_registered` (`filter_runner_provisioning`). Every one is a
  `DEPLOY-REQUIRED` stub with a true-negative fixture proving the exclusion works, so the
  validation advisory that listed rules with a filter and no true negative is now empty. The
  BitLocker rule's generated Splunk form mixes a top-level OR with the new NOT; the binding was
  traced and recorded in `splunk-precedence-allowlist.tsv` rather than left to precedence.

- **`\pipe\srvsvc` and `\pipe\epmapper` are read at last; EfsPotato and RoguePotato are watched on
  the mechanism plane.** `srvsvc_epmapper_pipe_impersonation_sysmon_17.yml` (id
  `563f2958-0d44-4138-884f-14d338d37cd9`) selects `EventType: CreatePipe` on a `PipeName` whose name
  NESTS either endpoint, closing the telemetry-ahead-of-detection hole #225 closed for `spoolss` and
  #229 for `atsvc`/`svcctl`/`efsrpc`. Two names, **one rule**: they share the invariant, the
  `EventType` pin, the absence of an `Image` key, the technique and both its tactics, and the
  false-positive story, which is the `svcctl`/`atsvc` case rather than the `efsrpc` one, where the
  split existed because the invariant genuinely differed. With this, every name the shipped config
  collects is either read or declined in writing.
  **The three questions #240 carried were re-derived, not inherited**, and the sweep was re-run from
  scratch because the original figures lived only in a config comment — a rule resting on a number
  recorded nowhere a reader could check is the circularity `fixture-provenance.tsv` exists to make
  visible. `docker/validation/labruns/2026-08-srvsvc-epmapper-pipe-creation.md` is the record: all
  278 EVTX of `sbousseaden/EVTX-ATTACK-SAMPLES` @`4ceed2f4`, `chainsaw 2.16.4`, **61 PipeEvent
  records** — the figure reproduces exactly.
  *Creation, not connection*, and for a **third** distinct reason, so neither sibling's argument
  carries across. Every nested pipe in the corpus produces exactly one 17 and one 18, tens of
  milliseconds apart: the 17 carries the tool's own `Image`, the 18 is the coerced service binding
  back as `Image=System` `ProcessId=4`, naming the victim. Dropping the pin takes the rule from 2
  matches to 4 and adds no attack it did not already see — only a misattributed second copy of each.
  So the pin buys deduplication and attribution and costs no coverage, where
  `coercion_efsrpc_pipe_sysmon_18`'s identical-looking pin is load-bearing against *volume* because
  lsass creates `\efsrpc` every boot. Both siblings now say so in their own descriptions.
  *The generic `\<x>\pipe\<y>` shape is rejected*, and the decisive objection turned out to be
  measured rather than argued. It is expressible without regex (`PipeName|contains: '\pipe\'`,
  since Sysmon renders one leading backslash and no `\Device\NamedPipe\` prefix) and on the create
  half it matches 3 of 61, all attacks — but the third is PrintSpoofer's nested `spoolss` pipe,
  which `spoolss_pipe_impersonation_sysmon_17` **already fires on**, so its marginal coverage over
  this corpus is **zero**. The ingestion objection stands separately: it needs unfiltered PipeEvent
  collection, so under the shipped `onmatch="include"` baseline it would see only the seven collected
  names — a much larger decision than a rule may make on the config's behalf. And 3-of-3 measures an
  attack-sample corpus, not an estate. It still misses GodPotato. Reopen condition recorded in the
  rule: if collection is ever widened past an include list, the generic form should *replace* this
  rule rather than sit beside it. For the same reason `spoolss` is deliberately absent from the name
  list — that rule's `contains: 'spoolss'` already matches the nested form, verified against the
  record, so adding it here would double-alert one attack.
  *No `filter_*` block, and the omission is the argument.* The legitimate creators make the **bare**
  `\srvsvc` and `\epmapper`, which the selection does not contain, so the narrowing does the work an
  exclusion would. #240's proposed `filter_legit: Image|endswith: '\svchost.exe'` is confirmed dead:
  the one legitimate `\epmapper` record is `Image=System`. A cosmetic filter would be that defect
  written twice. Consequently no `check-splunk-precedence.sh` row is needed — the compiled Splunk
  form is `EventType="CreatePipe" PipeName IN ("*\\pipe\\srvsvc*", "*\\pipe\\epmapper*")`, an OR
  list with no `NOT` beside it.
  **The fixtures are a provenance first for this repo.** `srvsvc_epmapper_pipe_17_tp.jsonl` is the
  two real create records transcribed **verbatim** from the corpus — the first pipe fixtures here
  whose *values*, not merely whose key set, come from the provider. They stay `vendor-documented`,
  not `captured`: `labruns/README.md` reserves that for first-party capture, and these are 2020–2021
  third-party builds. A true negative ships despite the rule having no `filter_*` — not required by
  any gate, but the `\pipe\` narrowing is the rule's entire thesis and nothing else would prove it
  discriminates; it changes exactly one value per line, `PipeName` nested to bare, holding `Image` at
  the TP's so the nesting is isolated as the sole discriminator.
  **Validation**: sigma efficacy 84/84 passed (42 with a true-negative), run against the pinned
  zircolite v3.7.6 — the new row fires on the transcribed EfsPotato and RoguePotato records and
  stays silent on the near-miss.
  **Two claims this repo was making are corrected.** The bare-`srvsvc` traffic was described as
  "five … ordinary share enumeration … from `Image=System`" — four of the five are `Image=System`
  and the fifth is `wmiprvse.exe`, and they come from three different capture types plus a kekeo
  capture. And "3 of 61 records" for the nested shape counts *pipes*; it is 6 records over 3 pipes.
  The load-bearing half — that no legitimate bind takes the nested form — holds exactly. Drive-by:
  `docker/validation/README.md` said 81 manifest rows / 38 true negatives against a real 84 / 42, and
  `runbook-sysmon18-remote-pipe.md` said "two things still need a host" while listing three.
  **What is not settled**: volume on a live host, in either direction. No legitimate *create* of
  either name appears anywhere in the corpus and none of the captures spans a boot, so the claim that
  a legitimate create would carry the bare name is inference. That half carries to #235, whose
  runbook gains it as item 4 with a pre-committed prediction and EfsPotato/RoguePotato rows in its
  firing table. Closes dotgibson/dotfiles-Defense#248.
  `Ledger: corpus 110 -> 111 rules, 128 -> 129 documents, techniques unchanged at 81. Privilege
  Escalation TA0004 9 | 14 -> 9 | 15, Stealth TA0005 3 | 5 -> 3 | 6, T1134.001 5 -> 6 rules. No new
  technique or tactic row, and no new Splunk precedence allowlist row.`

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
