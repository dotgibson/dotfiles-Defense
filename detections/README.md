# detections/ — version-controlled detection content

Detection as code. **Sigma is the portable source of truth** — author once,
compile down to whatever SIEM the lab runs. Each rule carries its ATT&CK
technique, its data source, and a validation note that names the **exact
`dotfiles-Offense` hacktheplanet fold and `htpx` pair** that reproduces it — so the
purple loop is closed in the file itself: run the attack there, confirm the rule
fires here.

| Dir          | Holds                                                   | Start from (upstream)                          |
| ------------ | ------------------------------------------------------- | ---------------------------------------------- |
| `sigma/`     | portable rules (the source of truth)                    | SigmaHQ                                        |
| `sysmon/`    | Sysmon config baseline(s)                               | Olaf Hartong `sysmon-modular`; SwiftOnSecurity |
| `network/`   | Zeek scripts + Suricata rules                           | Zeek pkgs; ET Open ruleset                     |
| `siem/`      | compiled saved-searches, props/transforms, dashboards   | compile from `sigma/`                          |
| `navigator/` | ATT&CK Navigator layer (heatmap) + `COVERAGE.md` report | generate from `sigma/`                         |

Workflow: write Sigma → convert to your backend → stand up the lab (`siemup`) →
run the matching attack from Offense → confirm it fires → tune → commit rule +
validation note. Real IOC values from cases stay in `~/cases/*/iocs`, never here.

## CI gate — the rules are validated as code

The Sigma rules are gated on every change by `.github/workflows/sigma.yml` (the
repo's `lint.yml` only covers shell). Thirteen hard checks, no advisory:

1. **Structural lint** (hermetic) —
   `sigma check --fail-on-issues -c detections/sigma-validation-config.yml`.
   Catches bad YAML, broken conditions, dangling field refs, duplicate ids/titles,
   bad status/level. `--fail-on-issues` is required — `sigma check` otherwise exits 0
   on validator *issues* (only parse/semantic errors fail it by default). The config
   drops only the two validators that need live MITRE downloads, so the gate never
   flakes on a network hiccup.
2. **Compile** — every rule must compile to a real backend (Splunk) via
   `detections/sigma/convert.sh`. A rule that won't convert isn't deployable.
3. **SIEM deploy-form drift** — `detections/siem/gen-siem.sh --check`. The three
   deploy artifacts — Splunk `savedsearches.generated.conf`, Sentinel
   `rules.generated.kql`, Elastic `rules.generated.lucene` — are *generated* from the
   Sigma tree; this proves the committed files still match what the generator emits, so
   no deploy form can drift by hand (the same idea as htpx's `gen-views.sh --check`).
4. **ATT&CK Navigator drift** — `detections/navigator/gen-navigator.sh --check`. The
   `coverage-layer.json` heatmap is *generated* from the rules' `attack.*` tags; this
   proves the committed layer still matches, so the coverage view can't drift from the
   rules.
5. **ATT&CK coverage report drift** — `detections/navigator/gen-coverage.sh --check`. The
   human-readable `COVERAGE.md` roll-up (by tactic / technique / logsource) is *generated*
   from the same tags; this proves the committed report still matches, so it can't drift.
6. **Methodology claims** — `detections/check-methodology.sh`. `DEFENSE-METHODOLOGY.md`
   is the one hand-written map of the detection layer, so it can't be drift-gated by
   regenerating and diffing the way the artifacts above are — two of its table's columns
   are editorial judgement no generator can emit. This checks the subset that *is*
   machine-checkable: every repo path it references exists, and every ATT&CK technique it
   names is either covered by a rule in `sigma/` or declared absent in the document's own
   `methodology-check: known-absent` marker. The inverse direction is the useful one — a
   technique the doc calls a gap quietly becoming covered makes the prose around it wrong,
   and this fails the build at that moment.
7. **Validation coverage** — `docker/validation/check-rule-coverage.sh`. The gates above
   prove a rule *parses* and *compiles*; firing is proved by `run-sigma-validation.sh`,
   which iterates the **manifests**, not the corpus — so a rule nobody listed is silently
   never run against a fixture: it compiles, it ships, and nothing ever demonstrated it
   fires. This closes that loop and the matching one for exclusions: a true positive shows
   a rule *can* fire and says nothing about whether a `filter_*` still excludes, so every
   rule carrying one must also ship a true negative. Genuine exceptions go in
   `no-fixture-allowlist.tsv`, with a reason.
8. **Fixture provenance** — `docker/validation/check-fixture-provenance.sh`. The coverage
   gate proves every rule *has* a fixture; it cannot prove the fixture reflects the
   provider's schema. Where a fixture was hand-written from the same belief that produced
   the rule, the test is circular — the rule passes its true positive *and* its true
   negative while being inert in production (#149). No gate can tell a plausible invented
   field from a real one, so this enforces only that the distinction is never lost: every
   fixture a manifest references declares whether its field names are `captured`,
   `vendor-documented`, or `unverified`.
9. **README gate-list correspondence** — `detections/check-readme-gates.sh`. This list
   and the block below are a second copy of the workflow's steps, and a copy that nothing
   compares is a copy that drifts — which is how the two gates above went undocumented
   while this section claimed six. Asserts every hard gate appears in the local block,
   that the block contains no command CI doesn't run, and that these counts match. The
   prose describing each gate is deliberately left alone; that's editorial, the same way
   `check-methodology.sh` leaves the methodology table's judgement columns alone.
10. **Splunk precedence** — `detections/siem/check-splunk-precedence.sh`. pySigma's
   Splunk backend does not parenthesise a top-level `OR` against a top-level `NOT`, so
   `(a) OR (b) NOT (filter)` is correct *only* under the search command's documented
   evaluation order (parentheses, NOT, OR, AND). Read with AND binding first — which is
   what `eval` and `where` do — branch `(a)` escapes the filter entirely. Nothing else
   catches it: zircolite evaluates the Sigma condition, where the parentheses are
   explicit, and the drift gate compares the generated file byte-for-byte rather than
   semantically. This flags every such search and fails unless it carries a reviewed row
   in `splunk-precedence-allowlist.tsv`. Both instances today are correct and signed off;
   the point is that the third one is a review conversation rather than a silent
   behaviour change (#166).
11. **ATT&CK id validity** — `detections/check-attack-tags.sh`. Checks every ATT&CK id
   in the repo against a **pinned** release, in **both** places they are written: the
   `attack.*` tags, and every id cited outside them — prose, and the technique pages
   `references:` entries link to. The second half exists because gating one representation
   moves the risk to the other: #171 retagged for v19 and #179 then found 27 revoked ids
   still sitting in prose and references, untouched, because this gate read `tags:` and
   nothing else. Those links are the sharp end — `attack.mitre.org` serves a revoked
   technique with a banner rather than a 404, so a stale reference shows a responder the
   wrong technique without ever announcing itself. A deliberate historical mention is
   escaped with `attack-id-historical` on the line. This was advisory until #172, and
   why it stopped being one is the useful part: pySigma ≥ 1.5.0 resolves tags against a
   STIX bundle it downloads at check time from the HEAD of `attack-stix-data`, dropping
   revoked objects — so the same commit reported 0 issues one run and 52 the next with
   nothing in the repo changed, and `continue-on-error` hid the flip. It was the only
   step here whose answer moved on its own, and the only one whose failures were
   invisible by design. `detections/attack-data.pin` now names an immutable per-version
   bundle and its SHA-256, verified every run and injected through pySigma's own
   `set_url()`. Reproducible, therefore a gate: an ATT&CK release fails the build when
   someone bumps the pin, in a PR that gets read, rather than silently on an unrelated
   Tuesday.
12. **htpx claim validity** — `detections/check-htpx-pairing.sh`. The promise at the top
   of this file is that each rule names the exact Offense fold and **htpx pair** that
   reproduces it, so the purple loop is closed in the file itself. Rules keep it two ways:
   ~80 `references:` URLs pointing at `entries/blue/<id>.md`, and an `htpx pair <id>` in
   the validation note. Nothing verified either — htpx is a separate repo on its own
   release cycle, so an entry renamed there left a rule here pointing at a 404, and the
   only way to find out was for someone to click the link. This resolves every named
   entry against the corpus at the commit in `detections/htpx.pin`, and checks the blue
   entries it names still pair back to a red entry that points at them. Adopting it found
   four dead names: `bloodhound-sharphound` was renamed `bloodhound-collect` upstream, and
   `archive-staging-rar` / `local-data-collection` named entries htpx has never had. It
   gates **claims, not coverage** — a name that resolves to nothing is simply wrong, where
   a *gap* is a scope judgement and belongs in the report below.
13. **htpx coverage report drift** — `detections/gen-htpx-coverage.sh --check`.
   `HTPX-COVERAGE.md` is *generated* from the rules plus the pinned corpus: which htpx blue
   entries this repo claims, which it does not, which techniques here the corpus has no
   attack for, and which entries htpx declares unpaired (read from its `pair_note:`, so the
   reason lives upstream rather than in an allowlist here). It never fails on a gap — htpx
   spans SaaS and CI/CD platforms this repo has no rules for by design, and a gate that
   failed on those would be red forever and silenced within a week. It fails when the
   committed report stops matching, so a change in the shape of the boundary arrives as a
   diff someone reads. #196.

Two of those gates read the **pinned** htpx corpus, which is what makes their verdict
reproducible — and also means they cannot see upstream moving. `.github/workflows/htpx-drift.yml`
covers that gap on a weekly schedule: it asks whether htpx's `entries/` has changed and files
one issue when it has, leading with any entry this repo *names* that upstream no longer
carries. That case is the reason it exists rather than a nicety — the gate reads the pinned
sha while the `references:` URLs point at `/blob/main/`, so a removal upstream is a live 404
for a reader while CI is still green. It stays quiet for upstream commits that do not touch
`entries/`, since nothing here reads anything else. Not in the list above because it is
scheduled, not part of the per-change gate.

Run it locally (any pySigma backend):

```sh
# pinned, matching CI (splunk + elasticsearch + kusto backends)
pip install "pysigma==1.5.0" "sigma-cli==3.0.2" "pysigma-backend-splunk==2.1.0" \
            "pysigma-backend-elasticsearch==2.1.0" "pysigma-backend-kusto==1.0.1"
sigma check --fail-on-issues -c detections/sigma-validation-config.yml detections/sigma/   # lint
detections/sigma/convert.sh splunk                                                         # compile → SPL
detections/siem/gen-siem.sh --check                                                        # deploy-form drift (Splunk/Sentinel/Elastic)
detections/navigator/gen-navigator.sh --check                                              # ATT&CK Navigator layer drift
detections/navigator/gen-coverage.sh --check                                               # ATT&CK coverage report (COVERAGE.md) drift
detections/check-methodology.sh                                                             # DEFENSE-METHODOLOGY.md claims still true
docker/validation/check-rule-coverage.sh                                                   # every rule fixtured; every filter_* has a true negative
docker/validation/check-fixture-provenance.sh                                              # every fixture declares where its schema came from
detections/check-readme-gates.sh                                                            # this gate list still matches sigma.yml
detections/siem/check-splunk-precedence.sh                                                  # no Splunk search leans on OR/NOT precedence
detections/check-attack-tags.sh                                                             # every ATT&CK tag valid against the pinned release
detections/check-htpx-pairing.sh                                                            # every htpx entry this repo names still exists upstream
detections/gen-htpx-coverage.sh --check                                                     # htpx pairing report (HTPX-COVERAGE.md) drift
```

`convert.sh` is the reproducible "Sigma → backend" *compile check*: it compiles each
rule with `--without-pipeline` (raw logical fields). `gen-siem.sh` is the reproducible
"Sigma → **deploy form**" step across **three SIEMs**: the Splunk `savedsearches`
form (Windows dirs through the `splunk_windows` TA pipeline, non-Windows dirs raw),
plus one-query-per-rule **Sentinel KQL** (`kusto` backend) and **Elastic Lucene**
(`lucene` backend) forms — all generated from the tree and drift-gated together. The
KQL/Lucene forms compile raw (add a `sentinel_asim`/`ecs_windows` pipeline for a real
Windows deploy); rules a backend can't express (Sigma correlations) are noted in-file,
not dropped. The hand-wrapped `siem/` forms below stay for the enriched, absence/join,
and packaged-analytics deploys a bare compile can't emit.

## What ships today (the starter pack)

The first content drop mirrors the **htpx red↔blue corpus**: each rule below
detects a technique that `dotfiles-Offense` can execute on demand, so every one is
purple-validatable out of the box.

### `sigma/` — 109 rules / 127 documents, organized by ATT&CK tactic

**`credential_access/`**

| Rule                             | Event / source                        | ATT&CK    | Validate with (Offense fold · htpx pair)     |
| -------------------------------- | ------------------------------------- | --------- | -------------------------------------------- |
| `kerberoasting_rc4_tgs`          | 4769 RC4 (0x17)                       | T1558.003 | Kerberos · kerberoast-getuserspns            |
| `asrep_roast_probing_4771`       | 4771 0x18 (correlation)               | T1558.004 | Kerberos · asreproast-getnpusers             |
| `password_spray_4625`            | 4625 (value_count correlation)        | T1110.003 | Kerberos/Poisoning · password-spray-kerbrute |
| `dcsync_replication_4662`        | 4662 replication right                | T1003.006 | DCSync/NTDS · dcsync-secretsdump             |
| `gpp_cpassword_sysvol_5145`      | 5145 SYSVOL prefs XML                 | T1552.006 | SMB · gpp-cpassword                          |
| `coercion_named_pipes_5145`      | 5145 IPC$ pipe (spoolss/efsrpc/…)     | T1187     | Poisoning & relay · coerce-petitpotam        |
| `coercion_efsrpc_pipe_sysmon_18` | Sysmon 18 PipeEvent (`\efsrpc` bound) | T1187     | Poisoning & relay · coerce-petitpotam        |
| `dpapi_backupkey_5145`           | 5145 IPC$ `protected_storage`         | T1555     | Credential access · dpapi-backupkey          |
| `ntds_dump_ntdsutil_vss_4688`    | proc create (ntdsutil/VSS)            | T1003.003 | DCSync/NTDS · ntds-ntdsutil                  |
| `lsass_handle_access`            | Sysmon 10 (LSASS)                     | T1003.001 | Lateral movement · lsass-dump-lsassy         |

**`privilege_escalation/`**

| Rule                                                          | Event / source                                                                                    | ATT&CK    | Validate with                                |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | --------- | -------------------------------------------- |
| `adcs_esc1_san_mismatch_4886`                                 | 4886/4887 cert request                                                                            | T1649     | AD CS abuse · adcs-esc1-certipy              |
| `potato_seimpersonate_4688` / `potato_seimpersonate_sysmon_1` | proc create (service→shell); per-channel pair (4688 `SubjectUserName` / Sysmon-1 `ParentUser`)    | T1134.001 | Win privesc · potato-seimpersonate           |
| `spoolss_pipe_impersonation_sysmon_17`                        | Sysmon 17 PipeEvent (`\spoolss` created by anything but `spoolsv.exe`)                            | T1134.001 | Win privesc · potato-seimpersonate           |
| `token_theft_process_target_subject_4688`                     | 4688 Target Subject (process created with a SYSTEM token by a non-SYSTEM creator)                 | T1134.001 | Win privesc · potato-seimpersonate           |
| `shadow_credentials_keycredentiallink_5136`                   | 5136 msDS-KeyCredentialLink                                                                       | T1556     | AD attack paths · shadow-credentials-certipy |
| `rbcd_allowedtoact_5136`                                      | 5136 msDS-AllowedToActOnBehalf…                                                                   | T1098     | AD attack paths · rbcd-impacket              |

**`lateral_movement/`**

| Rule                                 | Event / source                                                             | ATT&CK                            | Validate with                                            |
| ------------------------------------ | -------------------------------------------------------------------------- | --------------------------------- | -------------------------------------------------------- |
| `wmiexec_wmiprvse_child_4688`        | proc create (WmiPrvSE child)                                               | T1047                             | Lateral movement · wmiexec-impacket                      |
| `rdp_hijack_tscon_4688`              | proc create (tscon /dest:)                                                 | T1563.002                         | Lateral movement · rdp-hijack-tscon                      |
| `service_creation_psexec_7045`       | 7045 service install                                                       | T1569.002                         | Lateral movement · pth-lateral-nxc                       |
| `svcctl_atsvc_remote_pipe_sysmon_18` | Sysmon 18 PipeEvent (`\svcctl`/`\atsvc` bound from `System`, i.e. off-box) | T1021.002 / T1569.002 / T1053.005 | Lateral movement · pth-lateral-nxc                       |
| `passthehash_4624_fanout`            | 4624 type-3 (value_count correlation)                                      | T1550.002 / T1021                 | Lateral movement · pth-lateral-nxc                       |
| `unconstrained_delegation_4624`      | 4624 type-3 Kerberos, DC machine account → non-DC                          | T1187 / T1550.003                 | Poisoning & relay · PURPLE-TEAM unconstrained-deleg-4624 |

**`discovery/`**

| Rule                               | Event / source                                                                                      | ATT&CK                                                                    | Validate with                                                                     |
| ---------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `sharphound_ldap_sweep_4662`       | 4662 dir-access (value_count correlation)                                                           | T1087.002 / T1069.002                                                     | AD enumeration · bloodhound-collect                                               |
| `ldap_recon_explicit_creds_4648`   | 4648 explicit-cred fan-out (value_count correlation)                                                | T1087.002 / T1046                                                         | recon · PURPLE-TEAM 4648 row                                                      |
| `host_recon_command_burst`         | proc create, distinct discovery commands per host (value_count correlation)                         | T1033 / T1082 / T1018 / T1016 / T1049 / T1057 / T1007 / T1087.001 / T1135 | Situational awareness · `whoami`/`net`/`nltest` sweep                             |
| `local_group_enum_sweep_4798_4799` | 4798/4799 local group membership enumerated, distinct hosts per principal (value_count correlation) | T1069.001 / T1087.001                                                     | AD enumeration · SharpHound LocalGroup / `net localgroup \\host`                  |
| `host_enum_srvsvc_wkssvc_5145`     | 5145 IPC$ to the srvsvc/wkssvc pipes, distinct hosts per principal (value_count correlation)        | T1135 / T1049 / T1033                                                     | SMB enumeration · smb-enum-nxc                                                    |
| `host_recon_powershell_4104`       | 4104 script blocks, distinct discovery cmdlets per host (value_count correlation)                   | T1033 / T1082 / T1018 / T1016 / T1049 / T1057 / T1007 / T1087.001 / T1135 | Situational awareness · the same sweep from an **interactive** PowerShell session |

`host_recon_powershell_4104` is the independent-feed twin of `host_recon_command_burst`,
not a keyword variant of it. Every selection in that rule needs a **process** with a known
`Image` basename, so recon done inside one PowerShell session emits nothing there — no
process, no 4688, no Sysmon 1. 4104 sees it, and is immune to a renamed binary because a
cmdlet name is not a file on disk. It carries **no `Path` exclusion on purpose**: 4104
emits an empty `Path` for an interactive console, and a `not filter` on an empty field
nulls the whole match — so the obvious tuning move would suppress exactly the
hands-on-keyboard case and keep the inventory scripts. Tune it with the threshold, triage
on `Path` at alert time.

**`persistence/`**

| Rule                                  | Event / source                       | ATT&CK                | Validate with                   |
| ------------------------------------- | ------------------------------------ | --------------------- | ------------------------------- |
| `scheduled_task_suspicious_4698`      | 4698 task created                    | T1053.005             | Persistence · schtask-persist   |
| `wmi_event_subscription_consumer`     | Sysmon 20                            | T1546.003             | Persistence · wmi-subscription  |
| `rogue_account_creation_4720`         | 4720 account created                 | T1136.002 / T1136.001 | Persistence · `net user /add`   |
| `machine_account_creation_burst_4741` | 4741 burst (value_count correlation) | T1136.002             | AD attack paths · rbcd-impacket |

**`defense_impairment/`**

| Rule                             | Event / source                    | ATT&CK    | Validate with                           |
| -------------------------------- | --------------------------------- | --------- | --------------------------------------- |
| `dcshadow_rogue_dc_4742`         | 4742 `GC/` SPN write (+5137/4662) | T1207     | AD attack paths · dcshadow              |
| `windows_event_log_cleared_1102` | 1102 Security log cleared         | T1685.005 | `wevtutil cl Security` on a lab host    |
| `windows_event_log_cleared_104`  | 104 non-Security log cleared      | T1685.005 | `wevtutil cl Application` on a lab host |

**`impact/`** (the ransomware chain — process creation 4688 / Sysmon 1, plus 4663 and Sysmon 11 for the encryption sweep)

| Rule                              | Event / source                                                                       | ATT&CK | Validate with                                             |
| --------------------------------- | ------------------------------------------------------------------------------------ | ------ | --------------------------------------------------------- |
| `recovery_inhibition_process`     | proc create (vssadmin/wbadmin/bcdedit)                                               | T1490  | ransomware-precursor · inhibit-recovery-vssadmin          |
| `service_stop_burst`              | proc create, distinct service stops per host (value_count correlation)               | T1489  | ransomware-precursor · inhibit-recovery-vssadmin          |
| `data_destruction_wipe`           | proc create (cipher `/w`, sdelete, fsutil setZeroData, diskpart clean)               | T1485  | ransomware-precursor · destruction commands               |
| `bitlocker_abuse_encryption`      | proc create (manage-bde `-on`/`-protectors -add`, `Enable-BitLocker`)                | T1486  | ransomware-precursor · ShrinkLocker-style BitLocker abuse |
| `service_stop_protected_services` | proc create, ONE stop of a named backup/AV/DB service                                | T1489  | ransomware-precursor · service-stop-preransom             |
| `mass_file_encryption_4663`       | 4663 write/delete handles, distinct files per host+process (value_count correlation) | T1486  | ransomware-precursor · ransomware-encrypt-files           |
| `mass_file_encryption_sysmon_11`  | Sysmon 11 FileCreate, distinct files per host+image (value_count correlation)        | T1486  | ransomware-precursor · ransomware-encrypt-files           |
| `account_access_removal_4725`     | 4724/4725/4726, distinct target accounts per actor (value_count correlation)         | T1531  | account-lockout-defenders · account-removal-4725          |

They are one chain, not seven alerts: T1489 clears the locks, T1490 destroys the
rollback, T1485/T1486 are the objective. Two of them on one host inside a window is
the chain in progress — alert-chain them if your backend can.

`account_access_removal_4725` is the chain's other half: not destroying the estate but
locking the people who would respond out of it. It deliberately keys on 4724/4725/4726
only — on 4729/4733 (group-member removal) `TargetUserName` holds the *group* and the
removed principal is in `MemberName`, so folding them in would make the
distinct-target count mix users with groups. That is a separate rule on its own fields,
not a wider selection here.

Two techniques carry a deliberate set of rules, covering different halves:

- **T1489** — `service_stop_burst` counts volume and variety (five distinct stop commands
  on one host in five minutes) and knows nothing about service names;
  `service_stop_protected_services` knows the names that matter and fires on a single one.
  The burst misses the surgical stop, the named rule misses the no-name walk.
- **T1486** — three rules, one per data source, because each sees a different slice.
  `bitlocker_abuse_encryption` covers what process creation can see (BitLocker driven from
  a command line). The other two find the same invariant — one process rewriting many
  distinct files in minutes — from different telemetry: `mass_file_encryption_4663` reads
  Security 4663, which needs no Sysmon change but only fires **where a SACL exists**, so
  its reach is exactly your SACL's scope; `mass_file_encryption_sysmon_11` reads Sysmon
  FileCreate, which is **ACL-independent** and therefore covers the shares nobody put a
  SACL on, at the cost of enabling event 11. They are a per-source pair in the same sense
  as the `potato_seimpersonate` 4688/Sysmon-1 pair — genuinely different field names
  (`ObjectName`/`ProcessName` vs `TargetFilename`/`Image`), so one rule naming both would
  null under either pipeline. Note what that precedent cost to establish: the potato pair
  named the wrong Sysmon field for two months (`User`, the child, rather than `ParentUser`,
  the creator) and looked like a twin the whole time, because the two agree on every event
  except the attack. A per-channel pair is only a pair once someone has checked that the two
  fields mean the same thing — see
  `docker/validation/labruns/2026-08-potato-sysmon1-user-semantics.md`.
  Deploy whichever you collect; deploy both if you collect both.

**`collection/`** (host-side collection — proc create 4688 / Sysmon 1, plus 4663 for the read sweep)

| Rule                      | Event / source                                                                                                              | ATT&CK                | Validate with                            |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------- | --------------------- | ---------------------------------------- |
| `mass_file_read_4663`     | 4663 read handles (`AccessList` `%%4416`, or `AccessMask` `0x1`), distinct files per host+process (value_count correlation) | T1005                 | collection/exfil · a copy sweep          |
| `archive_staging_utility` | proc create (rar/7z/tar/makecab under a password or into a staging path)                                                    | T1560.001 / T1074.001 | collection/exfil · rar/7z staging        |

The two are the halves of one step, and they chain: `mass_file_read_4663` catches the
**sweep** that fills a staging directory, `archive_staging_utility` catches the
**archive** it gets packed into. Both on one host inside a window is collection in
progress; if egress follows (the `network/` C2 and exfil detections), exfiltration
already is.

`mass_file_read_4663` is the read-side twin of `impact/mass_file_encryption_4663` —
same event, same SACL, different access rights. The rights are what separate *someone is
copying the file share* from *someone is encrypting it*, so if you turned on Object
Access auditing for the impact rule, this one's data is already flowing. Both rules match
those rights on **two** fields: `AccessList`, which names one right per `%%NNNN` token and
is therefore unaffected by whatever else the same operation touched, and `AccessMask`,
which is the hexadecimal OR of all of them and so only equals the isolated bit when that
right was the only one used. `AccessList` is the anchor; the mask is the fallback for
pipelines that drop it. Keying on the mask alone is how both correlations came to be
[silently inert](https://github.com/dotgibson/dotfiles-Defense/issues/159) — they matched
nothing, fired never, and passed every CI gate doing it. It is also
**the noisiest rule in the corpus**, which is said in the rule itself rather than left
to be discovered: reads are orders of magnitude more common than writes, so its
threshold is higher (200 vs 100) *and* its base event ships a `filter_indexers`
suppression list. Treat that list as mandatory — unfilled, the nightly backup trips it,
the rule gets muted, and a muted rule is a blind spot.

**`linux/`** (Linux host telemetry — `product: linux`; `category: process_creation` for the
argv rules and `service: auditd` for the file/syscall watches)

The auditd rules select on the **watch key**, not on a path list, so the audit rules are
the single place that decides what is watched and the detection cannot drift away from
them. Each rule's description carries the `auditd` rules that set its key; load them with
`augenrules --load` or the rule is inert. What Sigma adds on top is the allowlist auditd
cannot express — package managers, configuration management, and the auth stack are the
entire volume on these keys, which is why most of them ship a `DEPLOY-REQUIRED`
filter. `history_clearing` is the exception and says so in-file: its selection is a
syscall class ordinary shell use never reaches, so there is no routine volume for an
allowlist to remove.

| Rule                        | Event / source                                               | ATT&CK    | Validate with                                  |
| --------------------------- | ------------------------------------------------------------ | --------- | ---------------------------------------------- |
| `ccache_theft_staging`      | ccache path in argv of a copy/transfer/interpreter process   | T1558.005 | Kerberos · cp/base64 an `*.ccache`             |
| `cron_persistence`          | auditd `cron_persist` — write to a cron drop dir / crontab   | T1053.003 | Linux persistence · cron callback              |
| `systemd_unit_persistence`  | auditd `systemd_persist` — write into a unit directory       | T1543.002 | Linux persistence · unit or timer              |
| `ssh_authorized_keys_write` | auditd `ssh_authkeys` — write to an `authorized_keys` file   | T1098.004 | Linux persistence · append attacker key        |
| `ssh_private_key_read`      | auditd `ssh_key_read` — private key read off the SSH stack   | T1552.004 | Linux cred access · harvest private keys       |
| `sudo_root_shell`           | auditd `sudo_abuse` — root shell under a real login uid      | T1548.003 | Linux privesc · GTFOBins sudo escape           |
| `suid_bit_set`              | auditd `suid_change` — chmod that sets the setuid/setgid bit | T1548.001 | Linux privesc · plant a SUID shell             |
| `shadow_file_read`          | auditd `shadow_read` — `/etc/shadow` read off the auth stack | T1003.008 | Linux cred access · dump for cracking          |
| `history_clearing`          | auditd `hist_tamper` — unlink/truncate of a `*_history` file | T1070.003 | Linux anti-forensics · `shred ~/.bash_history` |

**`cloud/`** (multi-cloud — Entra `product: azure`, AWS `product: aws`, GCP `product: gcp`)

| Rule                              | Event / source                                                                          | ATT&CK    | Validate with                            |
| --------------------------------- | --------------------------------------------------------------------------------------- | --------- | ---------------------------------------- |
| `entra_illicit_consent_grant`     | Entra AuditLogs "Consent to application"                                                | T1528     | M365/Entra · consent-grant               |
| `entra_sp_credential_backdoor`    | Entra AuditLogs "Add SP credentials"                                                    | T1098.001 | M365/Entra · sp-cred-backdoor            |
| `entra_directory_role_grant`      | Entra AuditLogs "Add member to role"                                                    | T1098.003 | M365/Entra · entra-directory-role        |
| `aws_iam_access_key_created`      | CloudTrail `CreateAccessKey`                                                            | T1098.001 | AWS IAM · aws-iam-backdoor-key           |
| `aws_login_profile_created`       | CloudTrail Create/UpdateLoginProfile                                                    | T1098     | AWS IAM · aws-console-login-profile      |
| `aws_iam_privesc_policy`          | CloudTrail policy attach/put/version + group add                                        | T1098.003 | AWS IAM · aws-iam-privesc-policy         |
| `aws_s3_bulk_exfil`               | CloudTrail S3 `GetObject`, distinct object keys per principal (value_count correlation) | T1530     | AWS S3 · aws-s3-mass-exfil               |
| `aws_data_destruction`            | CloudTrail snapshot/bucket/object/table deletes per principal (event_count correlation) | T1485     | AWS destruction · cloud-snapshot-destroy |
| `gcp_service_account_key_created` | GCP audit `CreateServiceAccountKey`                                                     | T1098.001 | GCP IAM · gcp-sa-key                     |

**`kubernetes/`** (kube-apiserver audit — `product: kubernetes`)

| Rule                         | Event / source                                | ATT&CK      | Validate with                         |
| ---------------------------- | --------------------------------------------- | ----------- | ------------------------------------- |
| `k8s_privileged_pod_created` | audit: privileged/hostPID/hostPath pod create | T1610/T1611 | Kubernetes · k8s-privileged-pod       |
| `k8s_pod_exec_attach`        | audit: `pods/exec`+`pods/attach` create       | T1609       | Kubernetes · k8s-exec                 |
| `k8s_clusteradmin_binding`   | audit: roleRef `cluster-admin` binding        | T1098       | Kubernetes · k8s-clusteradmin-binding |

**`okta/`** (Okta System Log — `product: okta`)

| Rule                     | Event / source                         | ATT&CK          | Validate with            |
| ------------------------ | -------------------------------------- | --------------- | ------------------------ |
| `okta_mfa_factor_reset`  | `user.mfa.factor.reset_all`/deactivate | T1556.006       | Okta · okta-mfa-reset    |
| `okta_api_token_created` | `system.api_token.create`              | T1098           | Okta · okta-api-token    |
| `okta_idp_created`       | `system.idp.lifecycle.create`/activate | T1556/T1484.002 | Okta · okta-idp-backdoor |

**`github/`** (GitHub Enterprise audit log — `product: github`, `service: audit`; field `action`)

| Rule                                   | Event / source                                                    | ATT&CK | Validate with                     |
| -------------------------------------- | ----------------------------------------------------------------- | ------ | --------------------------------- |
| `github_self_hosted_runner_registered` | `self_hosted_runner.created`                                      | T1543  | GitHub · gh-self-hosted-runner    |
| `github_branch_protection_tamper`      | `protected_branch.destroy` / `protected_branch.policy_override`   | T1685  | GitHub · gh-branch-protection-off |
| `github_credential_backdoor`           | `repo.create_deploy_key` / `personal_access_token.access_granted` | T1098  | GitHub · gh-deploy-key-backdoor   |

**`registry/`** (Harbor container-registry audit log — `product: harbor`, `service: audit`; field `operation`)

| Rule                              | Event / source                            | ATT&CK | Validate with                   |
| --------------------------------- | ----------------------------------------- | ------ | ------------------------------- |
| `harbor_image_pushed_trusted_tag` | `operation=push` `resource_type=artifact` | T1525  | Harbor · harbor-image-backdoor  |
| `harbor_robot_account_created`    | `operation=create` `resource_type=robot`  | T1098  | Harbor · harbor-robot-backdoor  |
| `harbor_artifact_deleted`         | `operation=delete` artifact/repository    | T1070  | Harbor · harbor-artifact-delete |

**`gitlab/`** (GitLab audit events — `product: gitlab`, `service: audit`; field `event_type`)

| Rule                             | Event / source                                                                            | ATT&CK | Validate with                    |
| -------------------------------- | ----------------------------------------------------------------------------------------- | ------ | -------------------------------- |
| `gitlab_rogue_runner_associated` | `set_runner_associated_projects`                                                          | T1543  | GitLab · gl-runner-hijack        |
| `gitlab_protected_branch_tamper` | `protected_branch_removed` / `protected_branch_created`                                   | T1685  | GitLab · gl-protected-branch-off |
| `gitlab_token_backdoor`          | `project_access_token_created` / `personal_access_token_created` / `deploy_token_created` | T1098  | GitLab · gl-token-backdoor       |

**`vault/`** (HashiCorp Vault audit device — `product: vault`, `service: audit`; fields `request.operation`/`request.path`)

| Rule                          | Event / source                                       | ATT&CK | Validate with                  |
| ----------------------------- | ---------------------------------------------------- | ------ | ------------------------------ |
| `vault_bulk_secret_read`      | `read` on `secret/` path (value_count correlation)   | T1555  | Vault · vault-secret-exfil     |
| `vault_approle_backdoor`      | create/update on `auth/approle/role/` or `sys/auth/` | T1098  | Vault · vault-approle-backdoor |
| `vault_audit_device_disabled` | `delete` on `sys/audit/` path                        | T1685  | Vault · vault-audit-disable    |

**`terraform/`** (Terraform Cloud audit trail — `product: terraform`, `service: audit`; fields `resource.type`/`resource.action`)

| Rule                     | Event / source                  | ATT&CK | Validate with                  |
| ------------------------ | ------------------------------- | ------ | ------------------------------ |
| `tfc_rogue_agent_pool`   | `agent_pool` `create`           | T1543  | Terraform · tfc-agent-hijack   |
| `tfc_token_backdoor`     | `authentication_token` `create` | T1098  | Terraform · tfc-token-backdoor |
| `tfc_variable_injection` | `variable` `create`/`update`    | T1072  | Terraform · tfc-var-injection  |

**`jenkins/`** (Jenkins Audit Trail plugin — `product: jenkins`, `service: audit`; keyword/URI matches)

| Rule                        | Event / source                                     | ATT&CK | Validate with                    |
| --------------------------- | -------------------------------------------------- | ------ | -------------------------------- |
| `jenkins_script_console`    | `/script` / `/scriptText` request                  | T1059  | Jenkins · jenkins-script-console |
| `jenkins_api_token_created` | `ApiTokenProperty/generateNewToken` request        | T1098  | Jenkins · jenkins-api-token      |
| `jenkins_job_backdoor`      | `/createItem` / `/job/<name>/configSubmit` request | T1072  | Jenkins · jenkins-job-backdoor   |

**`snowflake/`** (Snowflake `ACCOUNT_USAGE.QUERY_HISTORY` — `product: snowflake`, `service: audit`; fields `query_type`/`query_text`)

| Rule                              | Event / source                           | ATT&CK    | Validate with                        |
| --------------------------------- | ---------------------------------------- | --------- | ------------------------------------ |
| `snowflake_data_unload`           | `QUERY_TYPE=UNLOAD` (COPY INTO location) | T1567.002 | Snowflake · snowflake-exfil-stage    |
| `snowflake_user_created`          | `CREATE_USER` / priv `GRANT`             | T1136.003 | Snowflake · snowflake-rogue-user     |
| `snowflake_network_policy_change` | `NETWORK POLICY` in query text           | T1686.001 | Snowflake · snowflake-network-policy |

**`google_workspace/`** (Google Workspace admin/token/user audit — `product: google_workspace`; field `eventName`)

| Rule                           | Event / source                                     | ATT&CK    | Validate with                |
| ------------------------------ | -------------------------------------------------- | --------- | ---------------------------- |
| `gws_illicit_oauth_grant`      | token `authorize`                                  | T1528     | Workspace · gws-oauth-grant  |
| `gws_admin_role_grant`         | `GRANT_DELEGATED_ADMIN_PRIVILEGES` / `ASSIGN_ROLE` | T1098.003 | Workspace · gws-super-admin  |
| `gws_external_mail_forwarding` | `email_forwarding_out_of_domain`                   | T1114.003 | Workspace · gws-mail-forward |

**`cloudflare/`** (Cloudflare account audit log — `product: cloudflare`, `service: audit`; fields `resource.type`/`action.type`)

| Rule                           | Event / source                                            | ATT&CK    | Validate with                 |
| ------------------------------ | --------------------------------------------------------- | --------- | ----------------------------- |
| `cloudflare_api_token_created` | `resource.type=api_token` `create`                        | T1098     | Cloudflare · cf-api-token     |
| `cloudflare_waf_rule_disabled` | `firewall_rule`/`ruleset` `delete`/`update`               | T1686.001 | Cloudflare · cf-waf-disable   |
| `cloudflare_worker_deployed`   | `resource.type=worker`/`workers_script` `create`/`update` | T1648     | Cloudflare · cf-worker-deploy |

**`npm/`** (npm account/org audit log — `product: npm`, `service: audit`; field `action`)

| Rule                            | Event / source                        | ATT&CK    | Validate with               |
| ------------------------------- | ------------------------------------- | --------- | --------------------------- |
| `npm_malicious_package_publish` | `package.publish` by non-CI actor     | T1195.002 | npm · npm-malicious-publish |
| `npm_maintainer_added`          | `package.owner_add` / `team.user_add` | T1098     | npm · npm-owner-add         |
| `npm_publish_2fa_disabled`      | `package.edit` `mfa=none`             | T1685     | npm · npm-2fa-disable       |

**`pypi/`** (PyPI project journal — `product: pypi`, `service: audit`; field `action`)

| Rule                           | Event / source                          | ATT&CK    | Validate with                 |
| ------------------------------ | --------------------------------------- | --------- | ----------------------------- |
| `pypi_token_release_upload`    | `new release` not via trusted publisher | T1195.002 | PyPI · pypi-malicious-publish |
| `pypi_collaborator_added`      | `add Owner` / `add Maintainer`          | T1098     | PyPI · pypi-role-add          |
| `pypi_trusted_publisher_added` | add `trusted publisher` entry           | T1098     | PyPI · pypi-trusted-publisher |

**`slack/`** (Slack Enterprise Grid audit logs — `product: slack`, `service: audit`; field `action`)

| Rule                             | Event / source                                                                                 | ATT&CK | Validate with                |
| -------------------------------- | ---------------------------------------------------------------------------------------------- | ------ | ---------------------------- |
| `slack_app_installed`            | `app_installed` (broad read scopes)                                                            | T1098  | Slack · slack-malicious-app  |
| `slack_external_shared_channel`  | `shared_channel_invite_sent` / `_accepted`                                                     | T1567  | Slack · slack-external-share |
| `slack_2fa_enforcement_disabled` | `pref.two_factor_auth_changed` (fires on the change; the direction lives in Slack's `details`) | T1685  | Slack · slack-2fa-disable    |

`password_spray`, `asrep_roast_probing`, `sharphound_ldap_sweep`,
`ldap_recon_explicit_creds_4648`, `host_recon_command_burst`,
`passthehash_4624_fanout`, `machine_account_creation_burst_4741`,
`service_stop_burst`, `mass_file_encryption_4663`, `mass_file_read_4663`,
`mass_file_encryption_sysmon_11`, `vault_bulk_secret_read`, `aws_s3_bulk_exfil`,
`account_access_removal_4725`, `aws_data_destruction`,
`local_group_enum_sweep_4798_4799`, and `host_enum_srvsvc_wkssvc_5145` are Sigma
**correlation** rules (a base event + a count over a window); the rest are
single-event selections. All but one count *distinct values* of a field
(`value_count`) — breadth is almost always the sharper invariant than raw rate.
`aws_data_destruction` is the exception and uses `event_count`, because on the control
plane the volume of deletes *is* the signal: a wiper that only calls `DeleteObject`
would never trip a distinct-verb count, and unlike a file read there is no benign
process that issues ten destructive API calls a minute. The two process-creation correlations
(`host_recon_command_burst`, `service_stop_burst`) group by `Computer` rather than by
account on purpose — the actor field differs per channel (Security-4688
`SubjectUserName` vs Sysmon-1 `User`) and naming either would null the rule under the
other channel's pipeline, the same trap the `potato_seimpersonate` 4688/Sysmon-1 pair
documents. Grouping by `Computer` also sidesteps a second problem the pair had to be
corrected for: those two fields are not the same actor. Security-4688 `SubjectUserName` is
the creator and Sysmon-1 `User` is the new process — so a burst grouped by one is not the
same burst grouped by the other, and the host is the only key that means one thing on both
channels.
Both bursts are a property of the host anyway.

The `linux/`, `cloud/`, `kubernetes/`, `okta/`, `github/`, `registry/`,
`gitlab/`, `vault/`, `terraform/`, `jenkins/`, `snowflake/`, `google_workspace/`,
`cloudflare/`, `npm/`, `pypi/`, and `slack/`
rules are the non-Windows logsources here
(`product: linux|azure|aws|gcp|kubernetes|okta|github|harbor|gitlab|vault|terraform|jenkins|snowflake|google_workspace|cloudflare|npm|pypi|slack`)
and mirror the htpx corpus's companion-only cloud, K8s, Okta, GitHub Actions, Harbor
registry, GitLab CI/CD, HashiCorp Vault, Terraform Cloud, Jenkins, Snowflake,
Google Workspace, Cloudflare, npm + PyPI registry, and Slack pairs, and the
Linux auditd persistence / privilege-escalation / credential-access pairs.
The `jenkins/` rules match the Audit Trail plugin's request-URI log line via a `uri`
field (`uri|contains`), scoped to the specific endpoints (e.g. job `configSubmit` is
bound to the `/job/` path so global config submits don't trip it).

#### Deploy-time substitutions (`DEPLOY-REQUIRED`)

A few rules can't be meaningful until you substitute an environment-specific value —
the anomaly is defined *relative to your baseline*, which the repo can't know. Those
spots carry a `DEPLOY-REQUIRED:` marker in a YAML comment; run
[`sigma/deploy-required.sh`](sigma/deploy-required.sh) to list them before deploying and
fill each one. (Advisory, exits 0 — the repo ships the placeholders on purpose; a
comment isn't enforcement, so this is the discoverable checklist instead.)

| Rule                                              | Substitute                                                                                            | Until you do                                                                                                                                                                                                              |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `privilege_escalation/rbcd_allowedtoact_5136`     | `filter_delegation_admins` → your delegation-admin accounts                                           | can't tell admin from user; pair with `machine_account_creation_burst_4741` for fidelity that doesn't need it                                                                                                             |
| `defense_impairment/dcshadow_rogue_dc_4742`       | `filter_real_dcs` → your real DC computer accounts                                                    | a `GC/` SPN write onto another real DC would alert (low risk — rare regardless)                                                                                                                                           |
| `lateral_movement/unconstrained_delegation_4624`  | `TargetUserName` → your DC computer accounts, **and** `filter_dc_destinations` → those DCs' hostnames | **inert** — the rule matches only the `DC1$`/`DC2$` examples, so a coerced logon from any other DC is missed entirely. This is the one placeholder that makes its rule a no-op rather than merely noisy; fill it first.   |
| `cloud/entra_illicit_consent_grant`               | `filter_known_apps` → sanctioned app (client) IDs                                                     | verified LOB apps holding mail/file scopes alert (the high-risk-scope match still scopes it)                                                                                                                              |
| `snowflake/snowflake_data_unload`                 | `filter_known_stages` → sanctioned named stages                                                       | a named *internal* stage (not `@%`/`@~`) alerts alongside external ones                                                                                                                                                   |
| `collection/mass_file_read_4663`                  | `filter_indexers` → your backup / AV / indexing / sync agents                                         | **the loudest unfilled placeholder in the repo.** Reads are constant, so an unfilled list means the nightly backup trips it, someone mutes the rule, and the mute is the blind spot. Fill before deploying, not after.    |
| `collection/archive_staging_utility`              | `filter_backup_tooling` → your backup / packaging / build tooling                                     | the staging-path half alerts on CI and installer builds that archive into `%TEMP%`; the password-protected half is unaffected and stays high-confidence                                                                   |
| `credential_access/lsass_handle_access`           | `filter_av` → your endpoint-protection agent binaries                                                 | in a non-Defender shop the EDR reads LSASS continuously and this `high` rule fires steadily                                                                                                                               |
| `persistence/rogue_account_creation_4720`         | `filter_provisioning` → your IAM/JML and helpdesk provisioning principals                             | every routine onboarding alerts                                                                                                                                                                                           |
| `cloudflare/cloudflare_worker_deployed`           | `filter_ci` → the deploy pipeline's Cloudflare identity                                               | every CI Worker deploy is a `high` alert                                                                                                                                                                                  |
| `cloud/aws_iam_privesc_policy`                    | `filter_iac` → your IaC / access-management automation principal(s)                                   | Terraform's routine policy attachments alert alongside operator-driven ones                                                                                                                                               |
| `cloud/aws_s3_bulk_exfil`                         | `filter_bulk_readers` → your backup / replication / analytics / ETL role ARNs                         | the S3 twin of `filter_indexers`: object reads are constant, so an unfilled list means the nightly backup or an Athena scan trips the correlation and the rule gets muted                                                 |
| `cloud/aws_data_destruction`                      | `filter_iac` → your IaC / automation principal(s)                                                     | a `terraform destroy` of an ephemeral environment and a scheduled snapshot-retention job both look exactly like the attack from CloudTrail alone                                                                          |
| `impact/account_access_removal_4725`              | `filter_identity_admins` → your help-desk / JML / IAM provisioning principals                         | bulk offboarding alerts. This list is what makes the rule *sharp*, not merely quiet — the signal is an actor who does **not** normally administer identity                                                                |
| `cloudflare/cloudflare_waf_rule_disabled`         | `filter_ci` → the IaC pipeline's Cloudflare identity                                                  | every pipeline-driven edge change is a `high` alert — including the ones that *tighten* the WAF, since `ruleset/update` is the event for any ruleset change                                                               |
| `terraform/tfc_variable_injection`                | `filter_ci` → the pipeline actor in `auth.description`                                                | fires on every pipeline variable write, among the highest-volume events TFC emits — the rule's own description calls most of them benign CI                                                                               |
| `registry/harbor_artifact_deleted`                | `filter_gc` → your retention / garbage-collection account                                             | routine retention pruning alerts alongside the anti-forensics delete the rule is for                                                                                                                                      |
| `persistence/machine_account_creation_burst_4741` | `filter_provisioning` → your domain-join / imaging / MDM principals                                   | an imaging run clears the correlation's 3-in-30m threshold on its own, so the burst rule pages on routine provisioning                                                                                                    |
| `linux/cron_persistence`                          | `filter_provisioning` → your package manager + CM binaries                                            | every package install and CM converge that touches a cron path alerts                                                                                                                                                     |
| `linux/systemd_unit_persistence`                  | `filter_provisioning` → your package manager + CM binaries                                            | unit files are written on nearly every package install, so the rule reports your patch window                                                                                                                             |
| `linux/ssh_authorized_keys_write`                 | `filter_provisioning` → your key-distribution / cloud-init / CM path                                  | where keys are managed centrally that tooling writes these files on every converge and is the whole volume                                                                                                                |
| `linux/ssh_private_key_read`                      | `filter_ssh_stack` → extend with your backup / endpoint agents                                        | the SSH stack itself is already allowlisted, so this is deployable — a backup agent sweeping home directories is the noise you add to it                                                                                  |
| `linux/sudo_root_shell`                           | `filter_admins` → the login **uids** of your real administrators                                      | **not a volume stub — a meaning one.** Every `sudo -i` by a legitimate admin matches, so unfilled the rule restates your change calendar; filled, what remains is a root shell traced to a login that should not have one |
| `linux/suid_bit_set`                              | `filter_provisioning` → your package manager + build tooling                                          | a patch window that ships any setuid binary produces a burst                                                                                                                                                              |
| `linux/shadow_file_read`                          | `filter_auth_stack` → extend with your compliance scanner / backup agents                             | the standard auth stack is already allowlisted, so this is deployable as-is; until extended a nightly compliance scan alerts                                                                                              |

#### What `status:` means here

`status` is a triage signal, not decoration, so it is not uniform across the corpus:

- **`test`** — an invariant on a rare event, with **no** unpopulated `DEPLOY-REQUIRED`
  placeholder and a committed validation fixture proving it fires
  (`dcsync_replication_4662`, `recovery_inhibition_process`, `vault_audit_device_disabled`,
  `okta_idp_created`, and the rest of that shape). Deploy these first; they are the
  near-zero-FP tripwires.
- **`experimental`** — everything else, and deliberately so: rules whose filter stub is
  still a placeholder, the threshold-tuned `value_count` correlations (the threshold is a
  property of *your* environment, not of the rule), and the broad token-mint / creation
  rules whose own `falsepositives` say routine activity produces them. These are worth
  deploying, but tune before you page on them.

Nothing is `stable` yet — that would claim production-tuning history this repo doesn't have.

### `sysmon/` — `sysmonconfig-detection-lab.xml`

A deliberately minimal Sysmon baseline that turns on **exactly** the telemetry
the rules above need (ProcessCreate 1, ProcessAccess 10 on LSASS, FileCreate 11
for the encryption sweep, Registry 12/13 for autorun/WDigest, PipeEvent 17/18 for
the coercion pipes and the spoolss impersonation rule, WmiEvent 19/20/21). It is a
lab baseline, not production — graduate to `sysmon-modular` and tune.

**FileCreate 11 is the one block that costs real volume**, and it is enabled on
purpose: it is what makes `mass_file_encryption_sysmon_11` ACL-independent, where the
4663 twin sees only what a SACL covers. It is `onmatch="exclude"` rather than an
allowlist so an encryptor writing somewhere unexpected is still logged, and the
exclusions are by *target path* wherever possible — dropping a whole `Image` (svchost,
explorer) would hand an operator a place to write from, so only two purpose-built,
high-churn processes are named. If the lab drowns, this is the first block to tighten:
scope it to your document shares with an `include` group and accept the narrower reach.
The Sigma rule filters the same shape of path again in its base event, so it still
behaves on a host whose Sysmon config is broader than this one.

### `network/` — wire-side mirrors

- `zeek/kerberoast-rc4.zeek` — notices on an RC4 service ticket for a user SPN
  (the on-wire twin of `kerberoasting_rc4_tgs`).
- `suricata/coercion.rules` — DCERPC interface binds for PetitPotam / PrinterBug /
  DFSCoerce / ShadowCoerce (the wire twin of the 5145 coercion detection).

**Command-and-Control (TA0011)** — the "Exfil / C2" methodology row, on Zeek + Suricata
(behavioral invariants in Zeek, per-packet/fingerprint tells in Suricata; htpx pairs
`dns-tunnel-c2`, `dga-c2-domains`, `reverse-tunnel-chisel`, `icmp-tunnel-c2`, `mtls-c2-sliver`,
`https-beacon-sliver`):

- `zeek/dns-c2.zeek` — DNS tunneling (T1071.004, long distinct-subdomain fan-out per
  zone) and DGA beaconing (T1568.002, long vowel-poor NXDOMAIN bursts), via SumStats.
- `zeek/http-c2.zeek` — HTTPS/HTTP beaconing (T1071.001) by **callback regularity**:
  jitter randomizes each interval but not the distribution, so a low coefficient of
  variation (stdev ÷ mean) of the inter-arrival times per src→dst survives the jitter, a
  rotated domain, and TLS. Clocks `connection_established`, never `ssl_established` —
  which is both why it needs no analyzer and why it can be fixture-gated where
  `tls-c2.zeek` cannot (see "Known gaps" in `docker/validation/README.md`). State is
  O(1) per pair (streaming moments, not a timestamp vector).
- `zeek/reverse-tunnel.zeek` — long-lived high-volume bidirectional external sessions
  (T1572); the same shape surfaces bulk egress (T1041/T1048).
- `zeek/icmp-tunnel.zeek` — sustained large-payload ICMP echo to one external host
  (T1095).
- `zeek/tls-c2.zeek` — encrypted C2 (T1573.002): a self-signed-cert-to-external
  behavioral hunt (always-on) for the unknown-implant case, plus a pointer to the opt-in
  JA3 fast path below.
- `zeek/tls-c2-ja3.zeek` — **opt-in** JA3 known-implant match (T1573.002). Needs the ja3
  add-on package; its blocklist is data in `zeek/ja3-c2-feed.zeek` (generated).
- `suricata/c2.rules` — the fast-path signatures: encoded/oversized DNS labels
  (T1071.004), oversized ICMP echo (T1095), and a feed-driven JA3 `dataset` rule
  (T1573.002, ships commented — `ja3.hash` needs ja3 enabled in suricata.yaml).

**JA3 feed** — the known-implant fingerprints rotate, so they aren't hard-coded.
[`update-ja3-feed.sh`](network/update-ja3-feed.sh) pulls a maintained feed (abuse.ch
SSLBL JA3 by default; `--url` / `--from-file` to override) and regenerates both engines'
data: `zeek/ja3-c2-feed.zeek` (a `redef` fragment `@load`'d by `tls-c2-ja3.zeek`) and
`suricata/ja3-c2.lst` (base64 `dataset` entries). Deterministic output (dedup + sort),
bash 3.2-safe; run it on a schedule and commit the diff. An empty feed matches nothing,
so nothing goes stale or false-positives — the same discipline as the `DEPLOY-REQUIRED`
placeholders.

**Cryptomining / resource hijacking (T1496.001)** — the Impact tactic's one wire-side
technique, and the reason `DEFENSE-METHODOLOGY.md`'s Impact row reads `sigma, network`:

- `zeek/cryptomine-pool.zeek` — the behavioural half. A Stratum-port session that is
  long-lived and **thin** — the exact inverse of `reverse-tunnel.zeek`'s long-and-fat
  profile, because a miner's work happens on the CPU, not on the wire: a job down, a
  share up, repeat. It never inspects payload, which is the point — the documented
  attack runs xmrig with `--tls`, so a payload signature would miss it. Second notice
  (`Known_Pool_Destination`) matches known pool addresses on **any** port, which is what
  covers pool-over-443 where the port test can't help.
- `suricata/cryptomine.rules` — the plaintext Stratum handshake (`mining.subscribe` /
  `.authorize` / `.submit`), shipped with the caveat written into the file: against the
  documented `--tls` command it matches nothing. It catches the lazy case, which is still
  common, and the rule says so rather than implying parity with the Zeek half.

**Pool feed** — pool infrastructure rotates, so it isn't hard-coded either.
[`update-pool-feed.sh`](network/update-pool-feed.sh) is the same design as the JA3 script
above (deterministic dedup + sort, empty feed matches nothing, bash 3.2-safe) and
regenerates `zeek/cryptomine-pool-feed.zeek` (a `redef CryptoMine::pool_hosts` fragment)
and `suricata/cryptomine-pool.lst`. Ships empty, so it is inert until you populate it.
Unlike JA3 there is no single canonical pool blocklist — treat the default as a starting
point and prefer your own threat intel via `--url`.

### `siem/` — deployable backend forms

- **`splunk/savedsearches.generated.conf`** — GENERATED. Every rule in `sigma/`
  compiled to its Splunk `savedsearches` deploy stanza by `gen-siem.sh`
  (Windows dirs through the `splunk_windows` TA pipeline, non-Windows dirs raw), and
  drift-gated in CI via `gen-siem.sh --check`. This is the "real pipeline" the note
  above promised: edit a rule → `gen-siem.sh` → commit both. Do not hand-edit it.
- **`sentinel/rules.generated.kql`** — GENERATED. Every rule as a Microsoft Sentinel
  KQL query (`kusto` backend), one per rule, by the same `gen-siem.sh` (drift-gated).
- **`elastic/rules.generated.lucene`** — GENERATED. Every rule as an Elasticsearch
  Lucene query (`lucene` backend), one per rule, by the same `gen-siem.sh` (drift-gated).
- **`splunk/savedsearches.conf`** — HAND. Five single-event rules with hand-tuned
  enrichment (stats correlation, per-search schedules/severities/`action.notable`)
  the bare `savedsearches` format doesn't emit — kept as the worked, richer example.
- **`splunk/correlation_searches.conf`** — the three *absence/join-based* detections
  Sigma can't express — **Golden Ticket** (4769-without-4768, T1558.001), **Silver
  Ticket** (4624-without-4769, T1558.002), and **NTLM relay** (4624 workstation/source
  mismatch, T1557.001) — as deployable Splunk saved searches, with matching Sentinel
  KQL forms in `sentinel/` (see below). **These are covered detections that the
  `navigator/COVERAGE.md` roll-up does not count** — that report is generated from the
  Sigma tree only, so T1558.001/.002 and T1557.001 read as "0" there despite being
  instrumented here. Read the coverage report as *Sigma* coverage, not total.
  (T1557.001 was renamed by MITRE to "Name Resolution Poisoning and SMB Relay";
  T1558's `.005` Ccache Files sub-technique is now instrumented on Linux — see
  `sigma/linux/ccache_theft_staging.yml`.)
- **`sentinel/*.yaml`** — Microsoft Sentinel scheduled-analytics-rule deploy forms.
  Two families: the Entra cloud detections (illicit consent grant, SP credential
  backdoor, device-code sign-in), and the KQL twins of the three absence/join-based
  Kerberos/relay searches above — **Golden Ticket** (`golden_ticket_4769.yaml`,
  T1558.001), **Silver Ticket** (`silver_ticket_4624.yaml`, T1558.002), and **NTLM
  relay** (`ntlm_relay_4624.yaml`, T1557.001) — so the absence coverage the Splunk
  `correlation_searches.conf` provides has parity on Sentinel (KQL expresses `countif`
  absence and the watchlist join natively). Like the Splunk forms these are hand-
  authored (not emitted by `gen-siem.sh`) and not counted by `navigator/COVERAGE.md`.
  The AWS/GCP cloud rules deploy in their native consoles (CloudTrail/Athena, GCP
  Logging) or via Sentinel's AWS/GCP connectors.

### `navigator/` — ATT&CK coverage heatmap + report

- **`coverage-layer.json`** — GENERATED. A MITRE ATT&CK Navigator layer rolled up from
  every rule's `attack.*` tags by `gen-navigator.sh`, drift-gated in CI via
  `gen-navigator.sh --check`. Load it into the
  [ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator/) (Open Existing
  Layer → Upload) to see the corpus's coverage on the matrix: each covered technique is
  scored by how many rules detect it (gradient white→blue) and commented with the rule
  names. Edit a rule's tags → `gen-navigator.sh` → commit both.
- **`COVERAGE.md`** — GENERATED. The human-readable companion: a Markdown roll-up of the
  same tags **by ATT&CK tactic, by technique, and by logsource** (with the headline
  rule/technique/tactic/logsource counts), emitted by `gen-coverage.sh` and drift-gated
  via `gen-coverage.sh --check`. Read it in the repo to see coverage at a glance without
  loading the Navigator. Edit a rule's tags → `gen-coverage.sh` → commit both.

## Coverage gaps (honest notes)

- **Golden Ticket** (4769-without-4768), **Silver Ticket** (Kerberos logon
  without a matching 4769), and **NTLM relay** (4624 workstation mismatch) are all
  *absence*/join-based — they detect the lack of an expected event or a field-to-
  field comparison, which Sigma can't express cleanly. They ship as **deployable
  Splunk correlation searches** in `siem/splunk/correlation_searches.conf` and as
  **Microsoft Sentinel KQL** in `siem/sentinel/{golden_ticket_4769,silver_ticket_4624,
  ntlm_relay_4624}.yaml` (and as SPL in Offense's `PURPLE-TEAM.md` via their htpx pairs).
  For Silver Ticket the durable control remains PAC validation.
- **The Entra sign-in joins are the same shape on a different plane.** **T1078.004**
  (failure burst then success for one principal) and **T1566.002** (AiTM session-token
  replay — interactive auth from one ASN, non-interactive token use from another inside
  the token's life) are field-to-field comparisons across two sign-in tables, so they
  ship as `siem/sentinel/{entra_valid_accounts_signin,entra_aitm_token_replay}.yaml`
  rather than as Sigma, and read zero in `COVERAGE.md` for the same reason. Both htpx
  pairs are companion-only — `PURPLE-TEAM.md` is scoped to on-prem Splunk — so this is
  their first deployable form. They need the `SigninLogs` connector
  `entra_device_code_signin.yaml` already assumes, plus
  `AADNonInteractiveUserSignInLogs` for the AiTM half.
- **T1486 Data Encrypted for Impact — closed, on both data sources.** The honest invariant
  is mass file modification. This shipped first as `impact/mass_file_encryption_4663`
  (Security 4663 + a SACL, no Sysmon change required), which left the ingestion ticket
  *downgraded, not closed*: 4663 is only emitted where a SACL exists, so that rule's reach
  is exactly your SACL's scope, and a share nobody put a SACL on stayed invisible.
  `sysmon/sysmonconfig-detection-lab.xml` now enables **FileCreate (event 11)** and
  `impact/mass_file_encryption_sysmon_11` reads it, which is ACL-independent and closes
  that gap. Both are validated in `docker/validation` — and the Sysmon-11 rule's path
  exclusions were verified negatively as well as positively: 500 writes to excluded cache
  and servicing paths produce no detection, while the same 500 events on an ordinary path
  fire. `impact/bitlocker_abuse_encryption` still covers the slice process creation can
  see. What remains is a deployment trade, not a coverage hole: event 11 is the loudest
  block in the Sysmon config, and narrowing it narrows this rule's reach with it.
- **T1496.001 Compute Hijacking — the network half shipped; the other half never will.**
  The pair is documented in **`dotfiles-Offense`**, under that repo's
  `offensive/companion/entries/` — red `resource-hijack-xmrig`, blue
  `cryptomine-pool-detect`. The blue companion asks for **two** converging tells: a
  Stratum connection to a mining pool, and a process pegged near 100% CPU for a sustained
  period. The first is now covered by `network/zeek/cryptomine-pool.zeek` (#109), closing
  the purple loop. The second is not reachable at all: Sysmon has **no**
  resource/utilisation event at any config level — this is not a "turn on event N" gap
  like the T1486 one above, which was closed by doing exactly that — and the lab stack
  ships no metrics collector. Closing it would mean owning a new class of data source for
  a single corroborating signal, and no other blue companion entry asks for
  process-resource telemetry, so it was declined deliberately in **#110** (closed
  recorded-not-planned) rather than left to look like an oversight.
  **So the shipped detection is deliberately weaker than the companion specifies**: one
  tell, not two. The companion's own position is that either signal alone is worth a
  look, which is why one is worth shipping — but a Stratum session on an odd port from a
  build server is a *lead*, not a verdict, and it should be triaged as one.
  Note also that `navigator/COVERAGE.md` shows T1496.001 as uncovered and always will —
  the roll-up reads the Sigma tree only. Same caveat as C2 and the `siem/` detections;
  don't "fix" the report to compensate.
- **Collection (TA0009) now has a host-side half, and it was the marginal one.** The
  tactic used to be one cloud rule (`gws_external_mail_forwarding`, T1114.003), which the
  coverage-gap report called "thin" while explicitly saying *note, don't necessarily
  fill* — it is under-emphasized in `DEFENSE-METHODOLOGY.md` and ranked last of four.
  It was filled anyway, on request, so the trade is worth recording rather than
  implying this was free: `mass_file_read_4663` (T1005) and `archive_staging_utility`
  (T1560.001/T1074.001) are **lower-fidelity than anything else in the corpus**. Reading
  files and compressing them are what normal computers do all day, so unlike the AD
  rules — where the invariant is an operation nothing benign performs — these rest on
  volume and destination, which every environment baselines differently. Both ship a
  `DEPLOY-REQUIRED` suppression list for exactly that reason, and both are worth
  substantially less unfilled than the rules above are. The methodology now carries a
  Collection row so the map matches the corpus.
- **Discovery's single point of failure, narrowed — not solved.** Nine of the tactic's
  techniques used to hang on `discovery/host_recon_command_burst.yml` alone, all on one
  data source: if process-creation auditing is tuned out, or a host is EDR-blind, most of
  Discovery went dark at once and `COVERAGE.md` would still have read 12 techniques.
  `local_group_enum_sweep_4798_4799` (SAM-R local-group enumeration) and
  `host_enum_srvsvc_wkssvc_5145` (the srvsvc/wkssvc enumeration pipes) now detect the same
  operator behaviour on two independent feeds — the SAM-R path matters most, because
  SharpHound enumerates local admins in-process and writes **no** process-creation event
  at all, so the command-line rule never saw it. Score: techniques resting *exclusively*
  on that one file went **9 → 5** (T1007, T1016, T1018, T1057, T1082 remain), and
  techniques surviving the loss of that rule went **3 → 8**. The remaining five are the
  ones whose only tell really is a command line, so closing them means a different
  ingestion decision, not another rule.
  **No tags were moved off the burst rule.** It genuinely matches commands for all nine,
  so deleting tags would make the roll-up understate the rule while changing nothing about
  resilience. Diversification is new files on new events, not re-labelling the old one.
- **WMI is a dead end for discovery here, checked so it is not re-proposed.** The shipped
  `sysmonconfig-detection-lab.xml` enables `WmiEvent` (events 19/20/21), which is
  *subscription registration* telemetry — already consumed by
  `persistence/wmi_event_subscription_consumer`. It records no WMI **query or method
  invocation**, so it offers T1047/T1082 discovery nothing. WMI query logging means
  adopting `Microsoft-Windows-WMI-Activity/Operational`, a separate ingestion ask.
- **Declined this cycle (coverage-gap #124)**, with the reasons and reopen-conditions
  recorded in `DEFENSE-METHODOLOGY.md`'s "Declined coverage" section and enforced by its
  `known-absent` marker: **T1090.004** (domain fronting needs TLS decryption to compare SNI
  against the inner Host — a Zeek script would be inert on the path it appears to cover,
  the same reasoning that kept `CopyObject` out of `aws_s3_bulk_exfil`), **T1102.002**
  (a Sysmon Event 3 *host* detection, not wire work as the report framed it; Event 3 is not
  enabled here and is the loudest event Sysmon emits — and `http-c2.zeek` already catches a
  beacon *to* a trusted web service on cadence alone), and **T1526 / T1580 / T1069.003**
  (declined on the red side's own assessment — the Offense entry ships unpaired because the
  activity is read-only, low-signal, and lands in GCP Data Access logs that are off by
  default). The marker makes this ledger self-policing: ship a Sigma rule tagged with any
  of them and CI fails until the prose is updated.
- **External Reconnaissance (TA0043) and Resource Development (TA0042)** have no
  detection here and are not meant to: the first is pre-compromise and only nominally in
  `DEFENSE-METHODOLOGY.md`'s "Recon / Discovery" row (which is really *internal*
  Discovery — covered), and the second is attacker-side infrastructure building, invisible
  to defender telemetry. Neither is a methodology row. A Zeek portscan detector under
  `network/` is the one defensible addition to TA0043 if the scope ever widens.
- **Initial Access (TA0001) was in that list until #209**, and only because the two
  supply-chain rules that cover it were mistagged. `npm_malicious_package_publish` and
  `pypi_token_release_upload` carry T1195.002 — an Initial-Access-only technique — but
  tagged `attack.execution`, so the whole tactic column read zero while Execution
  quietly over-counted. The capability was always there; the label was wrong. The tactic
  now has a row in `DEFENSE-METHODOLOGY.md` and in `COVERAGE.md`, and
  `check-attack-tags.sh` gained a tactic↔technique pairing assertion so a tag can no
  longer claim a tactic ATT&CK does not place the technique in.
- **`COVERAGE.md` counts Sigma only**, so it understates the corpus by a whole tactic:
  `network/` (Zeek + Suricata) covers Command and Control (TA0011) end to end and
  `siem/` covers the absence/join Kerberos and relay detections, and neither is in the
  roll-up. Read it as *Sigma* coverage, not total — the same caveat the Golden/Silver
  Ticket note above makes for `siem/`.
- The **AWS/GCP** Sigma rules are broad event surfaces by design — the backdoor
  invariant (actor ≠ target) is a field-to-field comparison left to backend triage,
  same as the ADCS ESC1 and Entra-consent rules.
- Field names assume the Splunk Windows TA / Sysmon schema; normalize to your CIM
  before relying on them.
