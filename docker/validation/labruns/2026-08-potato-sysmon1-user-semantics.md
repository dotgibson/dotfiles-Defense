# Is Sysmon 1 `User` the creator or the child, and does the potato pair fire on a real potato?

- **Date:** 2026-08-29, extended 2026-08-30
- **Issue:** [dotgibson/dotfiles-Defense#239](https://github.com/dotgibson/dotfiles-Defense/issues/239)
- **Outcome:** the doubt is **confirmed**, and worse than filed. `User` is the child. The
  shipped `potato_seimpersonate_sysmon_1.yml` is **silent on all six real potato captures in
  the corpus** — not merely at risk of being silent. The corrected rule fires on them.
  Extended on 2026-08-30 by a second sweep of the same pinned corpus, which widened the scan
  from 170 samples to all 278, added two more potato captures and 42 Security 4688 records, and
  closed two of the limits the first pass recorded: the field semantics are now settled on a
  **cross-channel join** rather than on same-channel inference, and the parenting question a
  `ParentUser` rule rests on is measured rather than assumed. Findings 5–7 are that pass.

## The question

`potato_seimpersonate_sysmon_1.yml` and `potato_seimpersonate_4688.yml` describe themselves as
one shape expressed on two channels, and `detections/README.md` records the same pairing. The
two rules are byte-identical except for one field:

| Rule | Field | Documented as |
| --- | --- | --- |
| `potato_seimpersonate_4688` | `SubjectUserName` | the account that **requested** the create — the creator |
| `potato_seimpersonate_sysmon_1` | `User` | *asserted* by the rule to be the creator |

Both then apply `<field>|contains: ['APPPOOL','NETWORK SERVICE','LOCAL SERVICE']`. On an
ordinary service-spawns-shell event the creator and the child are the same account and the two
agree. On a successful potato they diverge — that divergence *is* the technique — so if Sysmon's
`User` is the **child's** identity, the Sysmon rule goes silent exactly when its twin fires.

Issue #239 rated its own reading high-but-not-certain: the TrustedSec community guide's wording
("Name of the account who created the process (child)") reads either way, and no captured
Sysmon 1 from a real token swap had been consulted. This is that consultation.

## Telemetry source

Not a first-party lab run. This is a **third-party capture**: real Sysmon EVTX from real hosts,
published in `sbousseaden/EVTX-ATTACK-SAMPLES`, pinned at commit
`4ceed2f4706daf601c212a8f91c113dd85349a2c` — the same corpus and commit
`2026-08-sysmon18-remote-pipe.md` used.

170 samples matching `sysmon|proc` were swept in the first pass; **147 Sysmon EventID 1
records** across them. The second pass swept **all 278 EVTX in the corpus**, yielding **1491
Sysmon EventID 1** and **42 Security EventID 4688** records across 14 hosts. The samples the
two passes turn on:

| Sample | Host | Date | Relevance |
| --- | --- | --- | --- |
| `Privilege Escalation/RogueWinRM.evtx` | MSEDGEWIN10 | 2020-05-24 | RogueWinRM, LOCAL SERVICE → SYSTEM, payload is `cmd.exe` |
| `Privilege Escalation/PrivEsc_Imperson_NetSvc_to_Sys_Decoder_Sysmon_1_17_18.evtx` | MSEDGEWIN10 | 2020-05-10 | NETWORK SERVICE → SYSTEM, payload is `cmd.exe` |
| `Privilege Escalation/privesc_rotten_potato_from_webshell_metasploit_sysmon_1_8_3.evtx` | IEWIN7 | 2019-05-26 | RottenPotato from an IIS webshell, `IIS APPPOOL\DefaultAppPool` → SYSTEM |
| `Privilege Escalation/EfsPotato_sysmon_17_18_privesc_seimpersonate_to_system.evtx` | LAPTOP-JU4M3I0E | 2021-08-22 | EfsPotato, NETWORK SERVICE → SYSTEM |
| `Privilege Escalation/privesc_unquoted_svc_sysmon_1_11.evtx` | MSEDGEWIN10 | 2020-04-25 | 79 Sysmon-1 records of ordinary boot/logon activity — the control |
| `Lateral Movement/LM_typical_IIS_webshell_sysmon_1_10_traces.evtx` | IEWIN7 | — | IIS webshell foothold, `w3wp.exe` → `cmd.exe` as the app-pool identity |
| `Privilege Escalation/privesc_spoolfool_mahdihtm_sysmon_1_11_7_13.evtx` | DESKTOP-TTEQ6PR | 2022-02-19 | one of only four records carrying `ParentUser` at all |
| `Privilege Escalation/privesc_roguepotato_sysmon_17_18.evtx` | MSEDGEWIN10 | 2020-05-11 | RoguePotato, LOCAL SERVICE → SYSTEM, payload `nc64.exe` (2nd pass) |
| `Privilege Escalation/privesc_seimpersonate_tosys_spoolsv_sysmon_17_18.evtx` | MSEDGEWIN10 | 2020-05-02 | PrintSpoofer `-i -c powershell.exe` (2nd pass) |
| `Credential Access/tutto_malseclogon.evtx` | MSEDGEWIN10 | 2021-12-07 | the only sample carrying **both** a Sysmon 1 and a Security 4688 for the same process (2nd pass) |

Parsed with `chainsaw 2.16.4` (`chainsaw dump --json`), normalised with
`docker/validation/evtx-to-fixture.sh --event-id 1`.

## Finding 1 — `User` is the child

The discriminating case is a process whose creator is *provably* SYSTEM and whose `User` is not.
Nine such records were found across three hosts. The cleanest is a Windows invariant that needs
no argument — `winlogon.exe` always runs as SYSTEM, and `userinit.exe` always runs as the
account logging on:

```json
{"Event": {"System": {"EventID": 1, "Channel": "Microsoft-Windows-Sysmon/Operational", "Computer": "MSEDGEWIN10"},
 "EventData": {
   "UtcTime": "2020-04-25 22:19:21.838",
   "Image": "C:\\Windows\\System32\\userinit.exe",
   "CommandLine": "C:\\Windows\\system32\\userinit.exe",
   "User": "MSEDGEWIN10\\IEUser",
   "LogonGuid": "747F3D96-B767-5EA4-0000-00209BD30100",
   "LogonId": "0x1d39b",
   "TerminalSessionId": 1,
   "IntegrityLevel": "Medium",
   "ParentProcessId": 568,
   "ParentImage": "C:\\Windows\\System32\\winlogon.exe",
   "ParentCommandLine": "winlogon.exe"}}}
```

The creator is SYSTEM; `User` reads `MSEDGEWIN10\IEUser`. **`User` is the account of the new
process.** The other eight are the same shape — `services.exe` → `svchost.exe` as `IEUser`
(per-user service host), `svchost.exe` → `sihost.exe` / `rundll32.exe` / `FileCoAuth.exe` as the
interactive user, `winlogon.exe` → `dwm.exe` as `Window Manager\DWM-1`.

It is corroborated structurally by the field order the capture preserves: `User` sits inside one
contiguous block — `CurrentDirectory`, **`User`, `LogonGuid`, `LogonId`, `TerminalSessionId`,
`IntegrityLevel`**, `Hashes` — every other member of which is indisputably the new process's.
`LogonId` `0x1d39b` above is the interactive session's, not session 0's.

The #239 reading was correct.

## Finding 2 — the shipped rule is silent on every real potato in the corpus

Six captures, four hosts, six different tools — four found in the first pass, plus RoguePotato
and PrintSpoofer in the second. Run through the same engine the gate uses (zircolite v3.7.6,
`--pipeline sysmon`) the shipped rule was **silent six times out of six**. In each, the swap
record is GUID-linked to its parent's own Sysmon-1 record, so the parent's identity is read from the capture rather than
inferred from the image name. RogueWinRM, verbatim — note `ParentProcessGuid` on the second
record is `ProcessGuid` on the first:

```json
{"Event": {"System": {"EventID": 1, "Channel": "Microsoft-Windows-Sysmon/Operational", "Computer": "MSEDGEWIN10"},
 "EventData": {
   "UtcTime": "2020-05-24 01:13:47.752",
   "ProcessGuid": "747F3D96-CA4B-5EC9-0000-0010B8CB3700",
   "Image": "C:\\Users\\IEUser\\Tools\\PrivEsc\\RogueWinRM.exe",
   "CommandLine": "RogueWinRM.exe  -p c:\\Windows\\System32\\cmd.exe",
   "User": "NT AUTHORITY\\LOCAL SERVICE",
   "LogonId": "0x3e5",
   "ParentImage": "C:\\Windows\\System32\\cmd.exe"}}}

{"Event": {"System": {"EventID": 1, "Channel": "Microsoft-Windows-Sysmon/Operational", "Computer": "MSEDGEWIN10"},
 "EventData": {
   "UtcTime": "2020-05-24 01:13:50.301",
   "ProcessGuid": "747F3D96-CA4E-5EC9-0000-00109FE23700",
   "Image": "C:\\Windows\\System32\\cmd.exe",
   "CommandLine": "c:\\Windows\\System32\\cmd.exe",
   "User": "NT AUTHORITY\\SYSTEM",
   "LogonId": "0x3e7",
   "IntegrityLevel": "System",
   "ParentProcessGuid": "747F3D96-CA4B-5EC9-0000-0010B8CB3700",
   "ParentProcessId": 3960,
   "ParentImage": "C:\\Users\\IEUser\\Tools\\PrivEsc\\RogueWinRM.exe",
   "ParentCommandLine": "RogueWinRM.exe  -p c:\\Windows\\System32\\cmd.exe"}}}
```

The creator is `NT AUTHORITY\LOCAL SERVICE`. The child is `NT AUTHORITY\SYSTEM`. All four
captures agree, GUID-linked in every case:

| Capture | Creator (`User` of the parent record) | Child (`User` of the swap record) | Payload |
| --- | --- | --- | --- |
| RogueWinRM | `NT AUTHORITY\LOCAL SERVICE` | `NT AUTHORITY\SYSTEM` | `cmd.exe` |
| NetworkServiceExploit | `NT AUTHORITY\NETWORK SERVICE` | `NT AUTHORITY\SYSTEM` | `cmd.exe` |
| RottenPotato (webshell) | `IIS APPPOOL\DefaultAppPool` | `NT AUTHORITY\SYSTEM` | `notepad.exe` |
| EfsPotato | `NT AUTHORITY\NETWORK SERVICE` | `NT AUTHORITY\SYSTEM` | `whoami.exe` |

`User|contains: ['APPPOOL','NETWORK SERVICE','LOCAL SERVICE']` is false on every one of them.
Run through the real rule with the same engine the gate uses (zircolite v3.7.6, pySigma 1.5.0,
`--pipeline sysmon`), over all 13 Sysmon-1 records from the four captures:

```text
potato_seimpersonate_sysmon_1 (shipped, User)         rc=0  SILENT (no detections)
```

**The rule has never fired on a potato because it cannot.** #239 asked whether the pair had ever
been confirmed to fire on a real one; for the Sysmon half the answer is that it provably does
not.

What it *does* fire on is the foothold before the swap — the webshell, not the escalation:

```text
potato_seimpersonate_sysmon_1 on LM_typical_IIS_webshell   rc=0  FIRED matches=1
    C:\Windows\System32\inetsrv\w3wp.exe -> C:\Windows\System32\cmd.exe   User=IIS APPPOOL\DefaultAppPool
```

That is a real and useful detection, and it is the one the rule was silently delivering. It is
not the one the rule, `detections/README.md` or `COVERAGE.md` claimed.

## Finding 3 — the corrected rule fires on the same telemetry

Sysmon 1's semantic equal of 4688's `SubjectUserName` is **`ParentUser`**, not `User`. Moving
the selection there and changing nothing else:

```yaml
  selection_svc_identity:
    ParentUser|contains: ['APPPOOL', 'NETWORK SERVICE', 'LOCAL SERVICE']
```

```text
potato_seimpersonate_sysmon_1 (corrected, ParentUser)  rc=0  FIRED id=03e878f6-bbdc-41e1-afa6-68b2979938fe matches=2

  2020-05-24 01:13:50.301  MSEDGEWIN10
      C:\Users\IEUser\Tools\PrivEsc\RogueWinRM.exe -> C:\Windows\System32\cmd.exe
      User=NT AUTHORITY\SYSTEM   ParentUser=NT AUTHORITY\LOCAL SERVICE
  2020-05-10 00:09:36.703  MSEDGEWIN10
      C:\Users\IEUser\Tools\PrivEsc\NetworkServiceExploit.exe -> C:\Windows\System32\cmd.exe
      User=NT AUTHORITY\SYSTEM   ParentUser=NT AUTHORITY\NETWORK SERVICE
```

Two of the four, and the two are the right two: RottenPotato's payload is `notepad.exe` and
EfsPotato's is `whoami.exe`, both excluded by the rule's pre-existing `Image|endswith` shell
list. That limitation is already conceded in
`token_theft_process_target_subject_4688.yml` ("survives `-c nc.exe`, `-c whoami`, and any
payload that is not a named shell — the whole class those two miss") and is not what #239 is
about. Against the shell-payload cases the corrected rule goes from 0/2 to 2/2.

**Read the qualification in "What this run does NOT settle" before reading this as a capture of
`ParentUser`.** It is not one.

## Finding 4 — `ParentUser` exists, and the captures show why the constraint is real

`ParentUser` arrived in Sysmon 13.00. Of the 147 Sysmon-1 records swept, exactly **one** carries
the field — the 2022 SpoolFool capture:

```json
{"Event": {"System": {"EventID": 1, "Channel": "Microsoft-Windows-Sysmon/Operational", "Computer": "DESKTOP-TTEQ6PR"},
 "EventData": {
   "UtcTime": "2022-02-19 17:35:16.196",
   "Image": "C:\\Users\\win10\\Desktop\\SpoolFool-main\\SpoolFool.exe",
   "User": "DESKTOP-TTEQ6PR\\win10",
   "IntegrityLevel": "Medium",
   "ParentImage": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
   "ParentCommandLine": "\"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -noexit -command Set-Location -literalPath 'C:\\Users\\win10\\Desktop\\SpoolFool-main'",
   "ParentUser": "DESKTOP-TTEQ6PR\\win10"}}}
```

Every other record — all from 2019–2021 hosts — omits it entirely. That is the ingestion
constraint stated as a measurement rather than as a footnote from the release notes: on a
pre-13 build the corrected rule's selection is **silently unsatisfiable**, not noisy. The
shipped `detections/sysmon/sysmonconfig-detection-lab.xml` is `schemaversion="4.90"`
(Sysmon 15.x) and captures all `ProcessCreate`, so it emits the field; an estate running older
agents does not, and this rule's silence there means nothing.

## Finding 5 — the cross-channel join, which settles `User` without relying on Sysmon alone

Findings 1–4 argue from within one channel. The second pass found the one sample in the corpus
that carries **both** a Sysmon 1 and a Security 4688 for the same process creation
(`Credential Access/tutto_malseclogon.evtx`, MSEDGEWIN10, 2021-12-07), joined on Sysmon
`ProcessId` (decimal) → 4688 `NewProcessId` (hex). Three pairs join; two are controls where
creator and child share a logon, and the third discriminates. The 4688, verbatim:

```json
{"Event": {"System": {"EventID": 4688, "Channel": "Security", "Computer": "MSEDGEWIN10"},
 "EventData": {
   "SubjectUserSid": "S-1-5-18",
   "SubjectUserName": "MSEDGEWIN10$",
   "SubjectDomainName": "WORKGROUP",
   "SubjectLogonId": "0x3e7",
   "NewProcessId": "0x17b8",
   "NewProcessName": "\\Device\\Mup\\VBoxSvr\\Users\\bouss\\Downloads\\MalSeclogon-master\\x64\\Debug\\MalSeclogon.exe",
   "TargetUserSid": "S-1-0-0",
   "TargetUserName": "IEUser",
   "TargetDomainName": "MSEDGEWIN10",
   "TargetLogonId": "0x16e3db3",
   "ParentProcessName": "C:\\Windows\\System32\\lsass.exe",
   "MandatoryLabel": "S-1-16-12288"}}}
```

The Sysmon 1 for the same process (`ProcessId` 6072 = `0x17b8`) reads
`"User": "MSEDGEWIN10\\IEUser"` and `"LogonId": "0x16e3db3"`.

| | creator, per 4688 | new process, per 4688 | Sysmon 1 |
| --- | --- | --- | --- |
| account | `WORKGROUP\MSEDGEWIN10$` (`S-1-5-18`) | `MSEDGEWIN10\IEUser` | `User` = `MSEDGEWIN10\IEUser` |
| logon | `SubjectLogonId 0x3e7` | `TargetLogonId 0x16e3db3` | `LogonId` = `0x16e3db3` |

On 4688, Subject is the creator and Target is the new process — Microsoft's documented
semantics, and the anchor `token_theft_process_target_subject_4688.yml` already leans on.
Sysmon's `User` matches the **Target**. The `LogonId` join says the same thing with a numeric
identifier carried independently on both channels, so it cannot be read as a rendering
difference between two providers' spellings of one account. The two control pairs behave as
documented: where creator and child share a logon, the Target block is null (`S-1-0-0`, `0x0`)
and Sysmon `LogonId` equals `SubjectLogonId`.

This closes the second limit the first pass recorded — that the reading rested on Microsoft's
documentation and on `ParentUser` being useless otherwise, rather than on an observation.

## Finding 6 — the parent is the potato tool, so `ParentUser` is the right field to key on

This was not obvious, and it is load-bearing for the corrected rule. `CreateProcessWithTokenW`
needs only `SeImpersonate` — which is why this whole family exists — and it is serviced by the
Secondary Logon service in `svchost.exe`. Had seclogon created the payload rather than the tool,
`ParentUser` would read `NT AUTHORITY\SYSTEM` and the corrected rule would be inert for a
reason having nothing to do with field semantics. Measured across all six captures:

| Capture | escalated process | its `ParentImage` | parent's own `User` |
| --- | --- | --- | --- |
| RottenPotato (webshell) | `notepad.exe` SYSTEM | `notepad.exe` (3388) | `IIS APPPOOL\DefaultAppPool` |
| RogueWinRM | `cmd.exe` SYSTEM | `RogueWinRM.exe` | `NT AUTHORITY\LOCAL SERVICE` |
| NetworkServiceExploit | `cmd.exe` SYSTEM | `NetworkServiceExploit.exe` | `NT AUTHORITY\NETWORK SERVICE` |
| RoguePotato | `nc64.exe` SYSTEM | `RoguePotato.exe` | `NT AUTHORITY\LOCAL SERVICE` |
| EfsPotato | `whoami.exe` SYSTEM | `EfsPotato.exe` | `NT AUTHORITY\NETWORK SERVICE` |
| PrintSpoofer `-i -c powershell.exe` | `powershell.exe` SYSTEM | `PrintSpoofer.exe` | `MSEDGEWIN10\IEUser` |

**No seclogon reparenting in any of the six.** The same result narrows the open assumption in
`token_theft_process_target_subject_4688.yml`: the seclogon route to Creator Subject arriving
`S-1-5-18` is ruled out for this family, while the thread-token route is untouched, because it
is a property of the audit subsystem rather than of the process tree.

Note the PrintSpoofer row. Its `ParentUser` is a named user, not a service identity, because
that capture's operator was an already-interactive admin rather than a coerced service context.
The corrected rule declines it, correctly — which is what makes it a usable true negative, and
it is now the pair's TN fixture.

## Finding 7 — what the second pass showed about the Security channel

The first pass recorded that it said nothing about 4688. The second pass does, though not about
the potato question:

- `token_theft_process_target_subject_4688.yml` **fires on real telemetry**, for the first time
  outside its own fixture (zircolite v3.7.6, `--pipeline windows-audit`):
  `FIRED id=1faa7a59-… matches=1 -> NewProcessName lsass.exe, Subject IEUser
  S-1-5-21-3461203602-…, Target MSEDGEWIN10$ S-1-5-18` — a non-SYSTEM creator producing a
  process carrying a SYSTEM token, on a genuine token-manipulation sample.
- Its fixtures' **event-version-2 key set and field order are identical** to the six captured
  4688s. That is the first evidence their schema is the provider's rather than the author's.
- Its falsepositives note about pre-Windows-10 hosts is **measured**: the eight 4688s in
  `Privilege Escalation/security_4624_4673_token_manip.evtx` (`IEWIN7`, a Windows 7 host) carry
  nine keys with no `Target*` block, no `ParentProcessName` and no `MandatoryLabel`, and the
  rule is correctly silent on all of them.
- One observation against it: the discriminating record in Finding 5 populates `TargetUserName`,
  `TargetDomainName` and `TargetLogonId` while `TargetUserSid` reads the null SID `S-1-0-0`.
  "Target Subject is populated" and "`TargetUserSid` is meaningful" are not the same condition,
  and `TargetUserSid` is the only one of the four that rule can see.
- `potato_security_4688.jsonl` was a three-key skeleton missing twelve fields every real 4688
  carries. It is rebuilt on the captured key set and order, with the Target block left null so
  it does not pre-judge the open question.

## What this run does NOT settle

Honest limits, after both passes. The first is load-bearing and [#239] should stay open for it;
`docker/validation/labruns/runbook-potato-seimpersonate.md` is what closing them needs:

- **`ParentUser` was never directly observed on a potato.** All six potato captures predate
  Sysmon 13, so none carries the field. The firing run in Finding 3 was performed against those
  records with `ParentUser` **injected**, taking each value from the parent process's own
  Sysmon-1 record in the same capture, matched on `ParentProcessGuid` → `ProcessGuid`. That is a
  rigorous derivation of what a Sysmon 13+ host would have emitted for the same process tree —
  the parent's identity is read from the capture, not guessed — but it is a derivation, and the
  corrected rule has therefore been proven to select the right *field semantics*, not to have
  fired on an untouched captured event. A first-party run on a modern build closes this.
- **No record was found where `ParentUser` is present and differs from `User`.** Of the four
  records in the corpus carrying the field, two are a user launching their own tool (the two
  legitimately agree) and two carry the `-` placeholder for a parent Sysmon could not resolve.
  Finding 5 removes the need for that divergence to settle what `User` means — the cross-channel
  join does it independently — but the narrower claim that `ParentUser` equals the parent
  process's own `User` was still not confirmed by a join: in none of the four is the parent's own
  Sysmon 1 present in the same log. Both observed values are consistent with the parent's
  identity; neither is joined to it.
- **It is not first-party.** Someone else's hosts, someone else's Sysmon builds, someone else's
  attacks. Per `docker/validation/labruns/README.md` the provenance row therefore reaches
  `vendor-documented` and never `captured`.
- **`potato_seimpersonate_4688.yml` is still untouched.** No 4688 from a potato was found in
  the corpus, so #239's third question stays exactly as open as it was. Finding 7 says real
  things about the Security channel, but none of them is about a potato: do not read it as
  covering that rule.
- **The `SubjectUserSid` assumption behind `token_theft_process_target_subject_4688.yml`
  (dotgibson/dotfiles-Defense#238) is narrowed, not closed.** Finding 6 rules out the seclogon
  route. The thread-token route — the one that rule actually states — needs a 4688 captured from
  a real potato, which is item 2 of `runbook-potato-seimpersonate.md`.
- **Four of the six potato captures remain undetected** by the corrected rule, for the
  independent and already-documented reason that their payload is not a named shell: the six
  payloads include `whoami`, `nc64.exe` and `notepad.exe`. That is the class
  `token_theft_parent_child_mismatch_sysmon_1.yml` and
  `token_theft_process_target_subject_4688.yml` exist to catch, and their "survives `-c nc.exe`,
  `-c whoami`" claim is measured by the same six.

## Reproducing this

```bash
docker/validation/evtx-to-fixture.sh --event-id 1 path/to/RogueWinRM.evtx > /tmp/real.jsonl
```

then run that JSONL through the rule exactly as `run-sigma-validation.sh` does (zircolite
v3.7.6, `--pipeline sysmon`). For Finding 1, any capture containing an ordinary logon works —
look for `ParentImage` `winlogon.exe` and read `User`. For Finding 3, link each record to its
parent with `ParentProcessGuid` → `ProcessGuid` and copy the parent's `User` into `ParentUser`
before the run; the injection is what makes it a derivation rather than a capture, and it must
be stated wherever the result is cited.

[#239]: https://github.com/dotgibson/dotfiles-Defense/issues/239
