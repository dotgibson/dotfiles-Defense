# Is Sysmon 1 `User` the creator or the created process — and does the potato pair fire on a real potato?

- **Date:** 2026-08-30
- **Issue:** [dotgibson/dotfiles-Defense#239](https://github.com/dotgibson/dotfiles-Defense/issues/239)
- **Outcome:** **Both** pre-committed questions answered, and the answer is the one the issue
  feared. `User` is the **created process**. The shipped
  `potato_seimpersonate_sysmon_1.yml` is **silent on all six real potato captures in the
  corpus** — measured through the engine, not argued. Plus two findings the issue did not
  anticipate: the spawned process's parent really is the potato tool on every one of the six
  (no seclogon reparenting), and `token_theft_process_target_subject_4688.yml` fires on a real
  captured token swap for the first time.

## The question

`detections/sigma/privilege_escalation/potato_seimpersonate_sysmon_1.yml` and
`potato_seimpersonate_4688.yml` describe themselves as one shape on two channels. They differ
in one field, and #239 doubted that the field means the same thing:

| Rule | Field | Claimed |
| --- | --- | --- |
| `potato_seimpersonate_4688` | `SubjectUserName` | the creator |
| `potato_seimpersonate_sysmon_1` | `User` | the creator — *if the pair is a twin* |

If `User` is instead the **created** process's account, then on a successful potato the field
reads `NT AUTHORITY\SYSTEM` and `User|contains: 'APPPOOL'` is false exactly when the attack
succeeds. Silence that reads as coverage.

## Telemetry source

Not a first-party lab run. This is a **third-party capture**: real Sysmon and Security EVTX
from real hosts, published in `sbousseaden/EVTX-ATTACK-SAMPLES`, pinned at commit
`4ceed2f4706daf601c212a8f91c113dd85349a2c` — the same corpus and commit
`2026-08-sysmon18-remote-pipe.md` used.

All 278 EVTX in the corpus were parsed with `chainsaw 2.16.4` (`chainsaw dump --json`) and
normalised with `docker/validation/evtx-to-fixture.sh`. That yielded **1491 Sysmon EventID 1**
and **42 Security EventID 4688** records across 14 hosts.

| Sample | Host | Date | Relevance |
| --- | --- | --- | --- |
| `Credential Access/tutto_malseclogon.evtx` | `MSEDGEWIN10` | 2021-12-07 | the only sample carrying **both** Sysmon 1 and Security 4688 for the same process — the cross-channel join |
| `Privilege Escalation/privesc_rotten_potato_from_webshell_metasploit_sysmon_1_8_3.evtx` | `IEWIN7` | 2019-05-26 | RottenPotato from an IIS webshell — the exact `IIS APPPOOL\DefaultAppPool` shape the rule is written for |
| `Privilege Escalation/RogueWinRM.evtx` | `MSEDGEWIN10` | 2020-05-24 | LOCAL SERVICE → SYSTEM, payload `cmd.exe` |
| `Privilege Escalation/PrivEsc_Imperson_NetSvc_to_Sys_Decoder_Sysmon_1_17_18.evtx` | `MSEDGEWIN10` | 2020-05-10 | NETWORK SERVICE → SYSTEM, payload `cmd.exe` |
| `Privilege Escalation/privesc_roguepotato_sysmon_17_18.evtx` | `MSEDGEWIN10` | 2020-05-11 | RoguePotato, payload `nc64.exe` |
| `Privilege Escalation/EfsPotato_sysmon_17_18_privesc_seimpersonate_to_system.evtx` | `LAPTOP-JU4M3I0E` | 2021-08-22 | EfsPotato, payload `whoami` |
| `Privilege Escalation/privesc_seimpersonate_tosys_spoolsv_sysmon_17_18.evtx` | `MSEDGEWIN10` | 2020-05-02 | PrintSpoofer `-i -c powershell.exe` |

## Finding 1 — `User` is the created process, settled on a cross-channel join

`tutto_malseclogon.evtx` is the one sample in the corpus that carries a Sysmon 1 and a Security
4688 for the same process creation. Joining Sysmon `ProcessId` (decimal) to 4688
`NewProcessId` (hex) gives three joined pairs. Two are controls where creator and child share a
logon; the third is the discriminating one.

The 4688, verbatim — the creator is **SYSTEM**, the new process runs as **IEUser**:

```json
{
  "Event": {
    "System": {
      "Provider_attributes": { "Name": "Microsoft-Windows-Security-Auditing" },
      "EventID": 4688,
      "TimeCreated_attributes": { "SystemTime": "2021-12-07T17:33:01.619364Z" },
      "Channel": "Security",
      "Computer": "MSEDGEWIN10"
    },
    "EventData": {
      "SubjectUserSid": "S-1-5-18",
      "SubjectUserName": "MSEDGEWIN10$",
      "SubjectDomainName": "WORKGROUP",
      "SubjectLogonId": "0x3e7",
      "NewProcessId": "0x17b8",
      "NewProcessName": "\\Device\\Mup\\VBoxSvr\\Users\\bouss\\Downloads\\MalSeclogon-master\\x64\\Debug\\MalSeclogon.exe",
      "TokenElevationType": "%%1936",
      "ProcessId": "0x27c",
      "CommandLine": "",
      "TargetUserSid": "S-1-0-0",
      "TargetUserName": "IEUser",
      "TargetDomainName": "MSEDGEWIN10",
      "TargetLogonId": "0x16e3db3",
      "ParentProcessName": "C:\\Windows\\System32\\lsass.exe",
      "MandatoryLabel": "S-1-16-12288"
    }
  }
}
```

The Sysmon 1 for the same process (`ProcessId` 6072 = `0x17b8`), verbatim:

```json
{
  "Event": {
    "System": {
      "Provider_attributes": { "Name": "Microsoft-Windows-Sysmon" },
      "EventID": 1,
      "TimeCreated_attributes": { "SystemTime": "2021-12-07T17:33:01.636384Z" },
      "Channel": "Microsoft-Windows-Sysmon/Operational",
      "Computer": "MSEDGEWIN10"
    },
    "EventData": {
      "RuleName": "-",
      "UtcTime": "2021-12-07 17:33:01.619",
      "ProcessGuid": "747F3D96-9ACD-61AF-D501-000000000102",
      "ProcessId": 6072,
      "Image": "\\\\VBoxSvr\\Users\\bouss\\Downloads\\MalSeclogon-master\\x64\\Debug\\MalSeclogon.exe",
      "CommandLine": "MalSeclogon.exe  -p 636 -d 2 -l 1",
      "CurrentDirectory": "C:\\Windows\\system32\\",
      "User": "MSEDGEWIN10\\IEUser",
      "LogonGuid": "747F3D96-9ACD-61AF-B33D-6E0100000000",
      "LogonId": "0x16e3db3",
      "TerminalSessionId": 0,
      "IntegrityLevel": "High",
      "ParentProcessGuid": "00000000-0000-0000-0000-000000000000",
      "ParentProcessId": 636,
      "ParentImage": "-",
      "ParentCommandLine": "-",
      "ParentUser": "-"
    }
  }
}
```

(`Hashes`, `FileVersion`, `Description`, `Product`, `Company` and `OriginalFileName` elided for
length; every other key is verbatim.)

| | creator, per 4688 | new process, per 4688 | Sysmon 1 `User` |
| --- | --- | --- | --- |
| account | `WORKGROUP\MSEDGEWIN10$` (`S-1-5-18`) | `MSEDGEWIN10\IEUser` | `MSEDGEWIN10\IEUser` |
| logon | `SubjectLogonId 0x3e7` | `TargetLogonId 0x16e3db3` | `LogonId 0x16e3db3` |

Sysmon's `User` matches 4688's **Target**, not its **Subject**. And the logon ids join the same
way — Sysmon `LogonId` is `TargetLogonId`, not `SubjectLogonId` — which is the corroborator
that cannot be explained away as a rendering difference, because it is a numeric identifier
carried independently on both channels. **`User` is the created process's account. #239 is
confirmed.**

The two control pairs in the same file behave exactly as Microsoft documents: where creator and
child share a logon the Target block is null (`TargetUserSid S-1-0-0`, `TargetLogonId 0x0`) and
Sysmon `LogonId` equals `SubjectLogonId`.

Corroborated at volume, on other hosts: **47 Sysmon 1 records** across `MSEDGEWIN10` and
`PC01.example.corp` have `ParentImage` `\services.exe` — a process that is unambiguously SYSTEM
— and a `User` that is not SYSTEM (`NT AUTHORITY\LOCAL SERVICE` ×32, `NT AUTHORITY\NETWORK
SERVICE` ×9, named users ×6). If `User` were the creator, every one of those would read SYSTEM.

## Finding 2 — the shipped rule is silent on all six real potato captures

Run through the same engine the gate uses — zircolite v3.7.6, `--pipeline sysmon`, against the
normalised captures — the shipped rule as committed:

```text
potato_seimpersonate_sysmon_1 (03e878f6)  vs  EfsPotato_sysmon_17_18_…                SILENT
potato_seimpersonate_sysmon_1 (03e878f6)  vs  PrivEsc_Imperson_NetSvc_to_Sys_Decoder  SILENT
potato_seimpersonate_sysmon_1 (03e878f6)  vs  RogueWinRM                              SILENT
potato_seimpersonate_sysmon_1 (03e878f6)  vs  privesc_roguepotato_sysmon_17_18        SILENT
potato_seimpersonate_sysmon_1 (03e878f6)  vs  privesc_rotten_potato_from_webshell…    SILENT
potato_seimpersonate_sysmon_1 (03e878f6)  vs  privesc_seimpersonate_tosys_spoolsv…    SILENT
```

Six for six. The RottenPotato capture is the sharpest illustration, because it is the literal
shape the rule was written for — an IIS app pool. Both halves of the escalation are in the log:

```text
pid 3388  notepad.exe   User=IIS APPPOOL\DefaultAppPool   ParentImage=…\inetsrv\w3wp.exe
pid 1240  notepad.exe   User=NT AUTHORITY\SYSTEM          ParentImage=…\notepad.exe (3388)
```

`User|contains: 'APPPOOL'` matches the **pre-escalation** process and not the escalated one.
That is the defect #239 described, observed rather than argued.

## Finding 3 — the parent is the potato tool, on every capture

This is the load-bearing question for any `ParentUser`-based rule, and the answer was not
obvious: `CreateProcessWithTokenW` is serviced by the Secondary Logon service in `svchost.exe`,
and whether seclogon reparents the created process back to the RPC caller is contested.
Measured across all six, `ParentImage` on the escalated process is the tool itself:

| Capture | escalated process | its `ParentImage` | parent's own `User` |
| --- | --- | --- | --- |
| RottenPotato (webshell) | `notepad.exe` SYSTEM | `notepad.exe` (3388) | `IIS APPPOOL\DefaultAppPool` |
| RogueWinRM | `cmd.exe` SYSTEM | `RogueWinRM.exe` | `NT AUTHORITY\LOCAL SERVICE` |
| NetworkServiceExploit | `cmd.exe` SYSTEM | `NetworkServiceExploit.exe` | `NT AUTHORITY\NETWORK SERVICE` |
| RoguePotato | `nc64.exe` SYSTEM | `RoguePotato.exe` | `NT AUTHORITY\LOCAL SERVICE` |
| EfsPotato | `whoami.exe` SYSTEM | `EfsPotato.exe` | `NT AUTHORITY\NETWORK SERVICE` |
| PrintSpoofer `-i -c powershell.exe` | `powershell.exe` SYSTEM | `PrintSpoofer.exe` | `MSEDGEWIN10\IEUser` |

**No seclogon reparenting in any of the six.** The parent-identity reading the repointed rule
rests on is therefore sound for this family as captured.

## Finding 4 — what the repointed rule catches, and what it still misses

`ParentUser` resolves cleanly under the sysmon pipeline (`sigma convert -t splunk -p sysmon` →
`EventID=1 Image IN (…) ParentUser IN (…)`). Under `windows-audit` it converts without
complaint to `EventID=4688 NewProcessName IN (…) ParentUser IN (…)` — it does **not** null the
rule the way `SubjectUserName` nulls under sysmon; it passes through unmapped and then matches
nothing forever, which is the `token_theft_process_target_subject_4688.yml` behaviour rather
than the original `potato_seimpersonate` one.

None of the six captures carries `ParentUser` — all six predate Sysmon 13. Re-running them with
`ParentUser` set to the parent process's own captured `User` (a reconstruction, not a capture —
see below) gives:

```text
candidate (ParentUser)  vs  PrivEsc_Imperson_NetSvc_to_Sys_Decoder  FIRED
candidate (ParentUser)  vs  RogueWinRM                              FIRED
candidate (ParentUser)  vs  EfsPotato_sysmon_17_18_…                SILENT   payload `whoami`, not a shell
candidate (ParentUser)  vs  privesc_roguepotato_sysmon_17_18        SILENT   payload `nc64.exe`, not a shell
candidate (ParentUser)  vs  privesc_rotten_potato_from_webshell…    SILENT   payload `notepad.exe`, not a shell
candidate (ParentUser)  vs  privesc_seimpersonate_tosys_spoolsv…    SILENT   PrintSpoofer run by an interactive
                                                                             admin, so ParentUser is a named user
```

Two of six, against zero of six today. The four remaining silences are the `Image|endswith`
shell list doing what it is written to do, and they are the exact class
`token_theft_process_target_subject_4688.yml` claims — *"this rule carries no Image constraint
at all, so it survives `-c nc.exe`, `-c whoami`, and any payload that is not a named shell"*.
That claim is now measured: three of the six real payloads were `whoami`, `nc64.exe` and
`notepad.exe`.

## Finding 5 — `token_theft_process_target_subject_4688.yml` fires on real telemetry

Not anticipated by #239, but the same capture answers it. Run against the six real 4688s from
`tutto_malseclogon.evtx` (zircolite v3.7.6, `--pipeline windows-audit`):

```text
token_theft_process_target_subject_4688  rc=0  FIRED id=1faa7a59-9fd5-4d14-9bf1-d94f82466acb matches=1
  -> NewProcessName C:\Windows\System32\lsass.exe
     Subject IEUser  S-1-5-21-3461203602-4096304019-2269080069-1000
     Target  MSEDGEWIN10$  S-1-5-18
```

A non-SYSTEM creator producing a process carrying a SYSTEM token, on a genuine token-
manipulation sample. That is the first time that rule has fired on anything but its own
hand-written fixture.

Two things this also confirms about that rule's fixtures. The hand-written
`token_theft_4688_tp.jsonl` / `_tn.jsonl` assert an event-version-2 key set taken from
Microsoft's published Event XML; those six captured 4688s carry the **identical key set, in the
identical order**. That is the first evidence the fixtures' schema is the provider's rather than
the author's. And the rule's own falsepositives note — *"a host older than Windows 10 / Server
2016 emits event version 0 or 1, which has no Target Subject block at all … verify against a
real 4688 before trusting silence"* — is now measured rather than feared: the eight 4688s in
`Privilege Escalation/security_4624_4673_token_manip.evtx` (`IEWIN7`, a Windows 7 host) carry
exactly nine keys, with no `Target*` block, no `ParentProcessName` and no `MandatoryLabel`, and
the rule is correctly silent on all of them.

One observation against it, recorded because the rule keys on `TargetUserSid` alone: in this
same capture, one 4688 populates `TargetUserName`, `TargetDomainName` and `TargetLogonId` while
`TargetUserSid` reads the null SID `S-1-0-0` (the discriminating record in Finding 1). The
records whose target was SYSTEM carried the correct `S-1-5-18`, so the rule is not defeated
here — but "Target Subject is populated" and "`TargetUserSid` is meaningful" are not the same
condition, and only the second one that rule can see.

## What this run does NOT settle

- **`ParentUser` has never been observed on a real potato.** All six potato captures predate
  Sysmon 13. Finding 4's fire/silent table uses `ParentUser` reconstructed from the parent
  process's own captured `User` in the same log. That reconstruction is well grounded — Sysmon
  derives `ParentUser` from the parent process, and Finding 3 shows the parent is the tool —
  but it is a derivation, and the fixture built from it says so.
- **`ParentUser` was not confirmed equal to the parent process's own `User` by a join.** The corpus
  holds only four Sysmon 13+ ProcessCreate records with a populated `ParentUser`, and in none of
  them is the parent's own Sysmon 1 present in the same log. Both observed values are consistent
  with the parent's identity; neither is joined to it.
- **`potato_seimpersonate_4688.yml` is still unconfirmed on a real potato.** No capture in the
  corpus carries a Security 4688 for a potato at all, let alone one with an `IIS APPPOOL`
  `SubjectUserName`. That question — and the `SubjectUserSid` half of #230's open assumption —
  is untouched by this run.
- **This is not first-party.** Someone else's hosts, Sysmon builds of 2019–2021, and their
  config rather than `detections/sysmon/sysmonconfig-detection-lab.xml` (`schemaversion="4.90"`,
  Sysmon 15.x). Under `labruns/README.md` that earns `vendor-documented`, not `captured`.

`runbook-potato-seimpersonate.md` is what is left.

## Reproducing this

```bash
git clone https://github.com/sbousseaden/EVTX-ATTACK-SAMPLES.git
git -C EVTX-ATTACK-SAMPLES checkout 4ceed2f4706daf601c212a8f91c113dd85349a2c
docker/validation/evtx-to-fixture.sh --event-id 1 --channel Sysmon \
  "EVTX-ATTACK-SAMPLES/Privilege Escalation/RogueWinRM.evtx" > rogue.jsonl
git clone --branch v3.7.6 https://github.com/wagga40/Zircolite.git && pip install -r Zircolite/requirements.txt
python3 Zircolite/zircolite.py -j -e rogue.jsonl --pipeline sysmon \
  -c Zircolite/config/config.yaml \
  -r detections/sigma/privilege_escalation/potato_seimpersonate_sysmon_1.yml -o det.json
```
