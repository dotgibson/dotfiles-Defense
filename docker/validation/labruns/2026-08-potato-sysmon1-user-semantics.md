# Is Sysmon 1 `User` the creator or the child, and does the potato pair fire on a real potato?

- **Date:** 2026-08-29
- **Issue:** [dotgibson/dotfiles-Defense#239](https://github.com/dotgibson/dotfiles-Defense/issues/239)
- **Outcome:** the doubt is **confirmed**, and worse than filed. `User` is the child. The
  shipped `potato_seimpersonate_sysmon_1.yml` is **silent on all four real potato captures in
  the corpus** — not merely at risk of being silent. The corrected rule fires on them.

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

170 samples matching `sysmon|proc` were swept; **147 Sysmon EventID 1 records** across them.
The ones this run turns on:

| Sample | Host | Date | Relevance |
| --- | --- | --- | --- |
| `Privilege Escalation/RogueWinRM.evtx` | MSEDGEWIN10 | 2020-05-24 | RogueWinRM, LOCAL SERVICE → SYSTEM, payload is `cmd.exe` |
| `Privilege Escalation/PrivEsc_Imperson_NetSvc_to_Sys_Decoder_Sysmon_1_17_18.evtx` | MSEDGEWIN10 | 2020-05-10 | NETWORK SERVICE → SYSTEM, payload is `cmd.exe` |
| `Privilege Escalation/privesc_rotten_potato_from_webshell_metasploit_sysmon_1_8_3.evtx` | IEWIN7 | 2019-05-26 | RottenPotato from an IIS webshell, `IIS APPPOOL\DefaultAppPool` → SYSTEM |
| `Privilege Escalation/EfsPotato_sysmon_17_18_privesc_seimpersonate_to_system.evtx` | LAPTOP-JU4M3I0E | 2021-08-22 | EfsPotato, NETWORK SERVICE → SYSTEM |
| `Privilege Escalation/privesc_unquoted_svc_sysmon_1_11.evtx` | MSEDGEWIN10 | 2020-04-25 | 79 Sysmon-1 records of ordinary boot/logon activity — the control |
| `Lateral Movement/LM_typical_IIS_webshell_sysmon_1_10_traces.evtx` | IEWIN7 | — | IIS webshell foothold, `w3wp.exe` → `cmd.exe` as the app-pool identity |
| `Privilege Escalation/privesc_spoolfool_mahdihtm_sysmon_1_11_7_13.evtx` | DESKTOP-TTEQ6PR | 2022-02-19 | the only swept record carrying `ParentUser` at all |

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

Four captures, three hosts, four different tools. In each, the swap record is GUID-linked to its
parent's own Sysmon-1 record, so the parent's identity is read from the capture rather than
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

## What this run does NOT settle

Honest limits. The first is load-bearing and [#239] should stay open for it:

- **`ParentUser` was never directly observed on a potato.** All four potato captures predate
  Sysmon 13, so none carries the field. The firing run in Finding 3 was performed against those
  records with `ParentUser` **injected**, taking each value from the parent process's own
  Sysmon-1 record in the same capture, matched on `ParentProcessGuid` → `ProcessGuid`. That is a
  rigorous derivation of what a Sysmon 13+ host would have emitted for the same process tree —
  the parent's identity is read from the capture, not guessed — but it is a derivation, and the
  corrected rule has therefore been proven to select the right *field semantics*, not to have
  fired on an untouched captured event. A first-party run on a modern build closes this.
- **No record was found where `ParentUser` is present and differs from `User`.** The one record
  carrying the field is a user launching their own tool, where the two legitimately agree. The
  claim that `ParentUser` is the parent's identity rests on Microsoft's documentation and on the
  field being useless otherwise, not on an observed divergence.
- **It is not first-party.** Someone else's hosts, someone else's Sysmon builds, someone else's
  attacks. Per `docker/validation/labruns/README.md` the provenance row therefore reaches
  `vendor-documented` and never `captured`.
- **It says nothing about Security 4688.** `potato_seimpersonate_4688.yml` is untouched by this
  run — no 4688 from a potato was found in the corpus — so #239's third question, and the
  `SubjectUserSid` assumption behind
  `token_theft_process_target_subject_4688.yml` (dotgibson/dotfiles-Defense#238), both remain
  exactly as open as they were. Do not read this record as covering them.
- **Two of the four potato captures remain undetected** by the corrected rule, for the
  independent and already-documented reason that their payload is not a named shell.

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
