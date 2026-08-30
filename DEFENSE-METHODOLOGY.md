# Defense Methodology — the detection map behind the tool layer

The "why" for `defense/defense.zsh`, `detections/`, and `docker/`: how the blue
tooling lines up against MITRE ATT&CK from the defender's seat. Mirror of Offense's
`OFFENSIVE-METHODOLOGY.md` — same ATT&CK through-line, opposite chair.

> The validation half lives across the fence: Offense's `PURPLE-TEAM.md` pairs each
> attack with the detection it trips. Detection engineering here + attack-paired
> detections there = the full purple loop.

## The philosophy

- **Detect the invariant, not the IOC.** Climb the Pyramid of Pain — spend
  detection budget on behaviors the technique cannot avoid (Kerberoast RC4
  downgrade, DCSync replication right, relay host-mismatch), not brittle IOCs.
- **A detection isn't real until it's fired on purpose.** Write the rule, make
  the attack happen (Atomic Red Team, Caldera, or your Kali box), watch it
  trigger. Untested detections are hypotheses.
- **No data source, no detection.** Coverage is an ingestion problem first. Map
  what you collect to what you want to catch; the gaps are the roadmap.
- **Tune for signal.** A noisy rule gets muted, and a muted rule is a blind spot.
- **Evidence is handled, not hoarded.** Case data lives outside the repo, with a
  timeline and provenance.

## ATT&CK tactic → data source → detection

| ATT&CK tactic            | Primary data sources                                              | Where detections live | Validate with (Offense)                                              |
| ------------------------ | ----------------------------------------------------------------- | --------------------- | -------------------------------------------------------------------- |
| Initial Access           | npm / PyPI publish audit logs                                     | sigma                 | htpx pairs `npm-malicious-publish` / `pypi-malicious-publish`        |
| Recon / Discovery        | Zeek, 4688/4769, 4798/4799, 5145                                  | network, sigma        | recon / Kerberoast folds                                             |
| Credential Access        | Sysmon 10, 4625/4771                                              | sysmon, sigma         | Responder / cracking folds                                           |
| Lateral Movement         | 4624 type 3, Zeek SMB                                             | sigma, network        | lateral-movement fold                                                |
| Priv Esc / Persistence   | Sysmon 1/13/17, 4720/7045                                         | sysmon, sigma         | LOLBAS / persistence folds                                           |
| Coercion / Relay / AD CS | 5145 pipes, 4886 SAN                                              | siem                  | coercion → relay → DC fold                                           |
| Collection               | 4663 file reads, 4688 archive cmds                                | sigma                 | collection / exfil fold                                              |
| Exfil / C2               | Suricata, Zeek conn/dns/ssl                                       | network               | reverse-shell / pivot folds                                          |
| Impact                   | 4688 destructive + service-stop cmds, 4663 file writes, Zeek conn | sigma, network        | ransomware chain (teardown → recovery → payload); cryptomining pair  |
| Anti-forensics           | 1102 + 104 log clears, auditd history syscalls, 4742 rogue DC     | sigma                 | DCShadow fold; `wevtutil cl` / `shred ~/.bash_history` on a lab host |

The right-hand column is the point: every row has a Offense fold that proves the
detection works.

**Initial Access is the newest row, and it exists because the tag was wrong, not because
the detection was missing.** Its two rules — `detections/sigma/npm/npm_malicious_package_publish.yml`
and `detections/sigma/pypi/pypi_token_release_upload.yml` — have covered T1195.002
(Compromise Software Supply Chain) since they were written, but tagged `attack.execution`.
T1195.002 is Initial-Access-only in ATT&CK, so the tactic column read zero in
`detections/navigator/COVERAGE.md` while Execution over-counted it, and this table had no row at
all. The weekly `/coverage-gap` routine caught it in #209.

**The Anti-forensics row spans two ATT&CK tactics, and reading it needs one fact about
v19 that is easy to get wrong.** ATT&CK v19 split Defense Evasion into **Stealth
(TA0005)** and **Defense Impairment (TA0112)**, and the split did not fall where the
names suggest. Log *clearing* went to **Defense Impairment**, not Stealth: the old
*Clear Windows Event Logs* sub-technique was revoked and re-issued as **T1685.005**
under TA0112, and *Clear Linux or Mac System Logs* went the same way. (Their pre-v19
ids are deliberately not written here — a revoked id in this file reads as a coverage
claim to `detections/check-methodology.sh`, and `detections/check-attack-tags.sh` is
the gate that pins the current numbering.) So
`detections/sigma/defense_impairment/windows_event_log_cleared_1102.yml` and its
per-channel sibling
`detections/sigma/defense_impairment/windows_event_log_cleared_104.yml` (both
**T1685.005**) count toward Defense Impairment, and only
`detections/sigma/linux/history_clearing.yml` (**T1070.003** Clear Command History,
which v19 left where it was) counts toward Stealth.

Two rules for one technique is not double-counting: 1102 is written only for the
Security channel and 104 only for everything else, they therefore sit on different
logsources (`service: security` vs `service: system`), and Sigma allows one logsource
per rule. Deploy both — clearing Sysmon's operational channel and leaving Security alone
is a real evasion, and it is 104 that catches it. The same forced split is why
`detections/sigma/privilege_escalation/` carries a `potato_seimpersonate_*` pair.

This is written down because #215 was filed on the opposite assumption — that authoring
the Windows log-clearing rule would fill the thin `Stealth` row in
`detections/navigator/COVERAGE.md`. It does not, and tagging it `attack.stealth` to make
it would fail the pairing assertion in `detections/check-attack-tags.sh`. Nor could the
gap be ledgered instead: T1070 is already covered by
`detections/sigma/registry/harbor_artifact_deleted.yml`, so listing it in the
`known-absent` marker fails `detections/check-methodology.sh` in the other direction.
Both rules were written; they land in different rows, and that is correct rather than a
mistag.

Stealth is three techniques and three rules, and that is an honest reading of the corpus
rather than an artifact of tagging. Two of them — T1070 and T1070.003 — are the command-
history and artifact-removal work described above. The third is T1134.001, and it arrived
by the route this section reserved for it rather than by a tag: see below. The rest of
TA0005 is masquerading, obfuscation, process injection and LOLBAS proxy execution — a
body of work this repo has not started, not one it has misfiled. The row being one wider
is not the gap closing.

**The pair still declines the row, and #223 is still the reason.** Because T1134.001 is
dual-tactic, `detections/sigma/privilege_escalation/potato_seimpersonate_4688.yml` and its
Sysmon-1 twin could legally claim the TA0005 half — the pairing assertion in
`detections/check-attack-tags.sh` asserts a tactic tag is *earned* by some technique
tagged beside it, not that every tactic is claimed, so the tag would pass and
`detections/navigator/COVERAGE.md` would read `Stealth TA0005 | 3 | 5` instead of
`3 | 3`. The pair does **not** claim it. What those rules select is a service identity
spawning a shell — the shape *before* the token is stolen, keyed on the un-masked
account field — and their own descriptions concede they cannot show the run-as-SYSTEM
result. The evasion is the part they cannot see. Taking the row would buy two rules'
worth of apparent TA0005 coverage backed by no detection of evasion, and `/coverage-gap`
is told to trust `COVERAGE.md` rather than recompute it, so the cost lands on the next
person ranking holes. The precedent runs the same way —
`detections/sigma/lateral_movement/unconstrained_delegation_4624.yml` claims a deliberate
subset of its three techniques' tactics and says so above the block.

**Reopened and answered by #225.** This section used to end on a condition: *a rule that
actually detects the impersonation — Sysmon 17/18 on the spoolss/DCOM named pipe, or a
token-context anomaly on 4624/4672 — earns the TA0005 half on its own evidence, and
should take it.* The spoolss half of that condition is now met by
`detections/sigma/privilege_escalation/spoolss_pipe_impersonation_sysmon_17.yml`, which
takes both tactic tags. PrintSpoofer-class tools do not abuse the spooler's own pipe;
they stand up their own and coerce the spooler into connecting to it, so a non-spooler
process *creating* a pipe named `spoolss` is the impersonation becoming visible. That is
evidence of the evasion, not of the shape around it, which is what the tag was being
reserved for. Note the rule pins itself to pipe **creation**: `category: pipe_created`
resolves to Sysmon 17 and 18, and on a connect event the only thing the attack produces
is the spooler binding back — which the rule's own `spoolsv.exe` filter removes — so
everything that would survive the filter there is ordinary print traffic.

**The token-context half is closed by #230, and not where #230 expected.** That half asked
for a rule reading 4624/4672 for an anomalous token context. There is no such rule, because
those two events are not written by this attack. 4624 generates when a logon SESSION is
created and 4672 when privileges are assigned to a new one, and no potato variant creates a
session: the pipe-impersonation majority never authenticates at all — `ImpersonateNamedPipeClient`
is a kernel token attachment, not a protocol — and the local-relay minority (Rotten, Juicy,
LocalPotato) rides NTLM's local-call short circuit, which hands the caller's existing token
to the server context in place of calling `LsaLogonUser`. `DuplicateTokenEx` then preserves
`AuthenticationId`, so the SYSTEM process the operator ends up with sits in logon session
0x3e7 rather than a fresh one. The only variants that ever produced the shape #230 imagined
are HotPotato and GhostPotato, dead since MS16-075 and CVE-2019-1384 respectively. A rule
built on it would have passed its own true positive AND its own true negative and then sat
inert in production, which is #149 with a Windows event id on it. Recorded here rather than
left as a silence, because the next person to read the reopen condition would otherwise
re-derive it.

**What answers it instead is 4688, and the tag moves there.**
`detections/sigma/privilege_escalation/token_theft_process_target_subject_4688.yml` takes the
TA0005 half on the plane where the telemetry exists. Event version 2 of 4688 (Windows 10 and
Server 2016 onward) added a Target Subject block, populated — in Microsoft's own words — only
when the creator and target "do not share the same logon". A process whose Target Subject is
SYSTEM was therefore created with a token that is not its creator's, which is the theft
stated as a field rather than inferred from the shape around it. It is also the property #230
actually wanted: every variant ends in `CreateProcessWithTokenW` or `CreateProcessAsUserW`, so
this sits downstream of all of them, including the ones that coerce over an endpoint other
than `spoolss` and so leave the pipe rule silent. One caveat travels with it and is written
into the rule: whether the audit reads Creator Subject from the calling process's token or
from its impersonating thread token is inference from Microsoft's documentation, not a
capture, and a lab run settles it — the same run that would establish whether the potato pair
has ever fired on a real potato.

Two shapes were considered on the way and rejected, so they are not re-proposed. A flat 4672
selection is noise by construction — every SYSTEM logon on the host emits one, at service
start rather than at escalation. And a 4624-to-4672 session join cannot be built here even if
the events existed: 4624 carries the session in `TargetLogonId` and 4672 in `SubjectLogonId`,
Sigma's only mechanism for reconciling that is `aliases`, and the SQLite backend zircolite
runs templates aliases into the WHERE clause, so the rule would compile to Splunk and never
fire under the validation gate. Grouping on `Computer` instead degrades to "some 4624 and some
4672 happened on this host", which is worse than the flat rule already rejected. The narrow
reopen condition that remains is a variant obtaining its token through `LsaLogonUser` rather
than duplication — JuicyPotatoNG is the live candidate, and its tell would be a 4624 LogonType
9, not a 4672.

**The rest of the PipeEvent block, and the one name that stays unread (#229).** #225 left
four of the five collected pipe names consumed by nothing, which is the same
telemetry-ahead-of-detection hole it had just closed, one size smaller. Two rules close
three of them: `detections/sigma/lateral_movement/svcctl_atsvc_remote_pipe_sysmon_18.yml`
on `atsvc`/`svcctl`, and
`detections/sigma/credential_access/coercion_efsrpc_pipe_sysmon_18.yml` on `efsrpc`.
Neither widens coverage, and the ledger should not be read as though they do: T1569.002 is
already held by `service_creation_psexec_7045`, T1053.005 by
`scheduled_task_suspicious_4698`, and T1187 by `coercion_named_pipes_5145` together with
`detections/network/suricata/coercion.rules`. What the pair buys is a second, independent
plane — the bind is visible on the host, so it survives an estate that forwards neither
7045 nor 4698 nor 5145, and it is the *request* rather than the result, so it is earlier in
the chain. The one genuinely new technique row is T1021.002, and it is new only because
nothing here previously named the admin-share access itself.

The invariant had to be re-derived rather than copied across, and that is the part worth
recording. #225's shape was ownership on pipe **creation** — the spooler is the only
legitimate creator of a `spoolss` pipe, so any other creator is anomalous on its own. It
transfers to none of the other four. `svcctl` is created once at boot by `services.exe`,
`atsvc` by the Task Scheduler, `efsrpc` and `lsarpc` by `lsass.exe`, and every tool in scope
**connects** to a pipe that is already there — impacket-psexec creates pipes of its own, but
they are `RemCom_*` names the baseline does not collect. The creation half therefore detects
nothing on these names, and the new rules take the connect half: the opposite trade to #225,
for the opposite reason. What replaces ownership is *origin*. A remote SMB client's pipe open
is serviced by the kernel SMB server, so `Image` reads `System` rather than the local
`sc.exe` or `schtasks.exe` that would otherwise be binding, and "this came from off-box" is
what separates impacket from ordinary remote administration. The efsrpc rule does not need
even that much and is deliberately not keyed on `Image`: over SMB that pipe is bound by
almost nothing but MS-EFSR and the tools that abuse it.

**`lsarpc` ships no rule, and that is a decision rather than an omission.** It stays
collected as hunt and pivot material. Sysmon PipeEvent carries no authenticating principal —
`User` is the local process's identity, not the account on the far end of the SMB session —
so `coercion_named_pipes_5145`'s `filter_machine`, the one block that keeps that pipe
survivable there, has no counterpart on this plane. A DFSCoerce bind and a domain member's
routine `lsarpc` bind arrive as byte-identical events, and a rule over them would be
unfilterable volume: a noisy rule gets muted, and a muted rule is a blind spot with extra
steps. The cost of declining is stated rather than buried — PetitPotam's *default* endpoint
is `lsarpc`, so the new `efsrpc` rule does not see the default invocation, and 5145 remains
the primary for coercion. This is the same "prefer the efsrpc/spoolss subset" trade
`coercion_named_pipes_5145` already recommends in its own description, applied to a plane
where it is forced rather than optional, and it is recorded in a form that runs: the efsrpc
rule's true-negative fixture *is* an `lsarpc` bind. *Reopen when* the host plane gains the
source of a bind — a Sysmon schema that carries it, or an ingestion path that joins 17/18 to
the 5145 for the same session — at which point a principal-shaped filter becomes expressible
and the rule becomes writable.

That caveat has now been partly discharged (#235). The premise — that Sysmon emits an 18 for
a remote SMB pipe open at all, attributed to `System` — was derived from where the kernel
services that open, and is now **observed**. Across 33 captured PipeEvent records from three
hosts, every remote-origin bind arrives as `Image=System`, `ProcessId=4` — 16 distinct pipe
names, including `\atsvc`, one of the two the atsvc/svcctl rule selects — while local binds in
the same captures carry their own image (`mmc.exe`, `PsExec.exe`), which is the true-negative
shape the fixtures assert. The shipped rule fires on that captured
record under the same engine the gate uses. The measurement is written up in
`docker/validation/labruns/2026-08-sysmon18-remote-pipe.md`, and the second-plane claim above
stands.

Three things that record keeps honest rather than letting the green tick imply. It is a
**third-party** capture — 2019–2020 Sysmon builds on other people's hosts, not our shipped
`sysmonconfig-detection-lab.xml` at schemaversion 4.90 — so the fixtures moved to
`vendor-documented`, not `captured`, and #235 stays open for the first-party run. `\svcctl`
and `\efsrpc` were **not** directly observed; their behaviour is inferred from the shared
NPFS path that produced sixteen differently-named remote binds identically attributed. And the
capture corrected something no one had questioned: PipeEvent carries **no `User` field at
all**, which every fixture here had asserted. That strengthened rather than weakened the
argument for declining an lsarpc rule — there is no principal on this plane to filter on, not
merely an unhelpful one — but it is exactly the class of defect the ledger exists to catch,
found the only way it can be found.

The rules still fail **independently**: the efsrpc one is not keyed on `Image`, so a Sysmon
that attributes the kernel SMB path differently costs a one-value change to the atsvc/svcctl
rule and nothing else. And no gate here could have settled it — `check_near_miss` requires a
true negative to carry the *identical* `EventData` key set as its true positive, so by
construction no fixture in this manifest can exercise a missing-or-renamed-field case. That is
the right call for the gate, and it is why the answer was a capture rather than more CI.

The row is narrow on purpose: it is the *registry* plane, not the endpoint. Both rules
fire on a publish event in an npm or PyPI audit log — a package shipped by an actor that
is not the sanctioned CI identity, or a release uploaded with a long-lived token rather
than OIDC trusted publishing. The downstream execution their descriptions mention (the
trojanized version that every `npm install` then runs) is the *consequence*, which is why
it is prose and not a second tactic tag.

**Collection** is the newest row and the weakest one, which is worth knowing before you
lean on it. Its detections — the T1005 read sweep and the T1560.001 archive step under
`detections/sigma/collection/` — key on *volume and destination* rather than on an
operation nothing benign performs, because reading and compressing files is ordinary
work. That makes them tuning-dependent in a way the AD rows are not: both ship a
`DEPLOY-REQUIRED` suppression list, and both are worth much less until it is filled. The
row earns its place because collection is the step between access and exfiltration and
leaving it blank hid a real sequence, not because these rules are as sharp as the
Kerberos ones.

**Impact is the one row that spans both layers**, and it is worth understanding why
rather than reading `sigma, network` as a formatting quirk. Most of the tactic is host
work — the T1489 teardown, T1490 recovery inhibition, and T1485/T1486 payload rules under
`detections/sigma/impact/`. But T1496.001 Compute Hijacking has no host invariant this
repo can reach: the giveaway is a conversation with a mining pool, and the corroborating
tell the Offense companion asks for — a process pegged near 100% CPU — needs resource
telemetry no Sysmon config emits at any level. So it lives on the wire, in
`detections/network/zeek/cryptomine-pool.zeek`, and the `network` in that column is that
one detection.

A consequence to hold on to: **T1496.001 is covered but will never appear in
`detections/navigator/COVERAGE.md`.** That roll-up is generated from the Sigma tree alone, so a
network-only detection reads as "0" there — the same documented caveat that already
applies to the whole Command-and-Control tactic and to the `detections/siem/` absence detections.
Do not "fix" the coverage report to compensate; the report is Sigma coverage, not total
coverage, and that is stated where it is generated.

That is also why T1496.001 stays in the marker below even though the detection now
exists. The marker means *"the Sigma corpus does not cover this"*, which is still true
and will stay true — `check-methodology.sh` computes coverage from `detections/sigma/`
only. Removing the id would fail the build, not celebrate the win.

**T1071.001 Web Protocols is the second entry of that kind**, added with
`detections/network/zeek/http-c2.zeek`. The rest of the C2 corner was already on the
wire — DNS (T1071.004), ICMP (T1095), tunnels (T1572), the TLS fingerprint (T1573.002) —
but a plain HTTPS implant riding 443 to a redirector tripped none of them. The invariant
is statistical rather than structural: jitter randomizes each callback interval but not
the distribution, so a low coefficient of variation over enough samples survives the
jitter, a rotated domain, and TLS. Same caveat as T1496.001 — it will read "0" in
`COVERAGE.md` forever, and that is the report being honest about what it counts.

**The `detections/siem/` absence detections are the third kind, and the ledger below was
missing them.** Four techniques are covered by this repo and will never appear in
`COVERAGE.md` for the same reason the network plane does not — the roll-up reads
`detections/sigma/` only:

- **T1558.001 Golden Ticket** (4769 with no preceding 4768) and **T1558.002 Silver Ticket**
  (4624 with no preceding 4769) — `detections/siem/sentinel/golden_ticket_4769.yaml`,
  `detections/siem/sentinel/silver_ticket_4624.yaml`, and the matching stanzas in
  `detections/siem/splunk/correlation_searches.conf`.
- **T1557.001 Name Resolution Poisoning and SMB Relay** (4624 workstation/source mismatch) —
  `detections/siem/sentinel/ntlm_relay_4624.yaml` and the same correlation file.
- **T1568.002 DGA** (vowel-poor NXDOMAIN bursts) — `detections/network/zeek/dns-c2.zeek`.

The first three are there because **Sigma cannot express an absence**: "this event without
that other event inside a window" is a backend-correlation shape, not a detection block. So
they live where the correlation engine does, and the coverage report reads zero for them
forever. That is the report being honest about what it counts, exactly as it is for the C2
corner — but until now the ledger recorded only the `detections/network/` half of that story, which is
why the weekly `/coverage-gap` routine could keep re-deriving these four as holes. Recording
them here is the whole purpose of the ledger.

**The Entra sign-in plane is the fourth kind, and it is a join rather than an absence.**
Two more techniques are covered here and will read zero in `COVERAGE.md` for the same
reason:

- **T1078.004 Cloud Accounts** (a burst of failed interactive sign-ins for one principal
  followed by a success in the same window) —
  `detections/siem/sentinel/entra_valid_accounts_signin.yaml`.
- **T1566.002 Spearphishing Link** (AiTM session-token replay: an interactive
  authentication from one ASN, then non-interactive sign-ins for that principal from a
  different one inside the token's life) —
  `detections/siem/sentinel/entra_aitm_token_replay.yaml`.

Both are field-to-field comparisons across two sign-in tables, so they are the same shape
as the Kerberos and relay detections above rather than a new kind of problem — Sigma has
no way to say "these two events disagree about where the user is". They sit on a logsource
the repo already ingests: `entra_device_code_signin.yaml` established `SigninLogs` here,
and the AiTM rule adds `AADNonInteractiveUserSignInLogs` alongside it.

What each one deliberately does **not** do is worth recording, because both invariants are
weak if stated carelessly. The valid-accounts rule reports the ASN of the winning sign-in
but does not gate on it — gating would drop the stuffing hit that lands from a residential
proxy in the user's own country. And the AiTM rule alerts on the auth-vs-token *split*,
never on a single anomalous-location sign-in, because travel and VPNs produce those all
day; a real user's token is used from where they authenticated, and that is the whole
signal.

**Discovery no longer rests on one data source.** Nine of its techniques used to hang on
`detections/sigma/discovery/host_recon_command_burst.yml` alone, so a tuned-out
process-creation policy or one EDR-blind host took most of the tactic with it. Two rules
on independent feeds now sit beside it — `local_group_enum_sweep_4798_4799.yml` (SAM-R
local-group enumeration, the path SharpHound takes in-process without writing a 4688 at
all) and `host_enum_srvsvc_wkssvc_5145.yml` (the srvsvc/wkssvc enumeration pipes, on a
5145 feed the coercion rules already require), and `host_recon_powershell_4104.yml` closes
the last of it: the five techniques that still hung on that one file (T1007, T1016, T1018,
T1057, T1082) now have a second feed in PowerShell script-block logging.

That last one is worth a sentence, because it is not a duplicate of the 4688 rule with
different keywords. Every selection in `host_recon_command_burst` requires a PROCESS to be
created with a known `Image` basename, so an operator running their situational awareness
inside one PowerShell session — `Get-Process`, `Get-ComputerInfo`, `Get-NetIPConfiguration`
— creates no process and emits nothing there at all. 4104 sees it, survives a renamed
binary (a cmdlet name is not a file on disk), and survives the process-creation feed being
off. It needs Script Block Logging turned on, the same shape of ingestion precondition the
4663 rules carry for their SACL.

Its own limit, recorded so it is not rediscovered: 4104 logs a script BLOCK, so a
monolithic `.ps1` doing all the recon at once is one event and will not trip a
distinct-block count. The interactive operator is what it adds; a scripted one is caught by
the 4688 twin only if the script shells out.

### Declined coverage (recorded, not planned)

Techniques with a documented attack in the red mirror and a deliberate decision **not**
to author a detection here. Recorded so the weekly `/coverage-gap` routine stops
re-deriving them, each with the condition that would reopen it:

- **T1090.004 Domain Fronting** — the invariant is TLS SNI ≠ the inner HTTP `Host`, which
  is only visible with a TLS-inspecting proxy. Without decryption Zeek cannot see the
  inner Host at all, so a script would be inert on the exact path it appears to cover —
  the same reason the S3 rule refuses a `CopyObject` branch. *Reopen when* a
  TLS-inspecting proxy is part of the lab stack.
- **T1102.002 Web Service C2** — a **host** detection, not wire work: the blue companion
  keys on Sysmon Event ID 3 (NetworkConnect), which
  `detections/sysmon/sysmonconfig-detection-lab.xml` does not enable. Event 3 is the
  loudest event Sysmon emits, and turning it on estate-wide to serve one technique — whose
  detection then reduces to an allowlist of trusted SaaS domains, an IOC-shaped rule this
  methodology argues against — is a poor trade. The corner is not unwatched: `http-c2.zeek`
  catches a beacon *to* a legitimate web service on cadence alone, with no new host
  telemetry. *Reopen when* the Sysmon baseline graduates to a production config that
  carries Event 3 anyway.
- **T1041 Exfiltration Over C2 Channel, T1048 Exfiltration Over Alternative Protocol** —
  declined because the only invariant this repo can reach does not separate them from what
  it already claims. `detections/network/zeek/reverse-tunnel.zeek` fires on duration plus
  bidirectional volume: a single external session that lives far longer and moves far more
  bytes than a normal client flow. That shape is a tunnel (T1572, which the script does
  claim), or exfil over the C2 channel (T1041), or exfil over a different protocol (T1048),
  and the wire evidence is identical in all three. Tagging the script with T1041/T1048
  would assert a discrimination the detection does not make — coverage reading as more
  specific than it is, which is the failure the `known-absent` ledger exists to prevent,
  pointed the other way. The script says as much itself: it "fires on the shape and lets
  triage split them". Triage splits them; the detection does not.
  A dedicated rule is not the answer either, for the same reason T1102.002 is declined:
  there is no host-side invariant in the ingestion set. Separating exfil from tunneling
  needs either content inspection or per-process network byte counts, and the Sysmon
  baseline carries no Event 3 at all. *Reopen when* the stack gains content inspection (a
  DLP or TLS-inspecting proxy — the same trigger as T1090.004) or per-process network
  volume telemetry, either of which makes the split expressible rather than assumed. Note
  the egress corner is watched meanwhile: the shape fires, it is just filed under T1572.
- **T1526, T1580, T1069.003 cloud discovery** — declined on the red side's own assessment:
  the Offense entry ships unpaired because the activity is read-only, low-signal, and lands in
  GCP Data Access telemetry that is off by default. *Reopen when* Data Access logging is
  enabled in the lab project.

<!-- methodology-check: known-absent = T1041, T1048, T1069.003, T1071.001, T1071.004, T1078.004, T1090.004, T1095, T1102.002, T1496.001, T1526, T1557.001, T1558.001, T1558.002, T1566.002, T1568.002, T1572, T1573.002, T1580 -->
<!-- Techniques this document names but the SIGMA corpus does not cover — which is not
     the same as "no detection exists". Two classes live here:
       (a) COVERED, but not by Sigma — two planes, both invisible to this gate and to
           COVERAGE.md, which read detections/sigma/ only. Dropping any id here would
           fail the build.
             network/  — T1496.001 (zeek/cryptomine-pool.zeek), T1071.001
                         (zeek/http-c2.zeek), T1071.004 and T1568.002 (zeek/dns-c2.zeek),
                         T1095 (zeek/icmp-tunnel.zeek), T1572 (zeek/reverse-tunnel.zeek),
                         T1573.002 (zeek/tls-c2.zeek).
             siem/     — the ABSENCE detections, which Sigma cannot express at all:
                         T1558.001 (sentinel/golden_ticket_4769.yaml), T1558.002
                         (sentinel/silver_ticket_4624.yaml), T1557.001
                         (sentinel/ntlm_relay_4624.yaml), each with a matching stanza in
                         splunk/correlation_searches.conf. And the Entra sign-in JOINS,
                         same reason: T1078.004
                         (sentinel/entra_valid_accounts_signin.yaml) and T1566.002
                         (sentinel/entra_aitm_token_replay.yaml).
       (b) DECLINED, reasons and reopen-conditions in "Declined coverage" above —
           T1090.004, T1102.002, T1526, T1580, T1069.003, and T1041/T1048 (detected in
           effect by zeek/reverse-tunnel.zeek, but not claimed: its shape cannot separate
           exfil from the tunneling it already reports as T1572).
     Every other technique id in this file must be tagged by a rule in detections/sigma/.
     Adding an id here is a deliberate act. Remove one only when a SIGMA rule starts
     covering it — and note the gate enforces that in both directions, so the decline
     ledger cannot rot: ship a rule tagged with one of these and CI fails until the prose
     above is updated too. -->

Every other ATT&CK id in this document is checked against the corpus on each change.

## The detection-engineering lifecycle

1. **Hypothesis** — "an attacker doing X leaves Y" (from ATT&CK or a Offense fold).
2. **Data check** — do we collect Y? If not, that's an ingestion ticket.
3. **Author** — write it as code in `detections/` (Sigma is the source of truth).
4. **Validate (purple)** — run the technique from Offense, confirm the rule fires.
5. **Tune** — allowlist known-good, threshold the noise.
6. **Deploy + document** — record data source, ATT&CK ID, and the validation.

## OPSEC / evidence hygiene

- **Case-first.** `mkcase` writes `case.md` (scope + authorization) first.
- **Everything in `~/cases`, never in the repo.**
- **Timeline + provenance** for every artifact (`note` drops timestamped lines).
- **Containers for the heavy stuff** — the lab is ephemeral and reproducible.
