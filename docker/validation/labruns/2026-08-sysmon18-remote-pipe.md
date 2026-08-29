# Does Sysmon emit an 18 for a remote SMB pipe open, and does `Image` read `System`?

- **Date:** 2026-08-29
- **Issue:** [dotgibson/dotfiles-Defense#235](https://github.com/dotgibson/dotfiles-Defense/issues/235)
- **Outcome:** **1** of the three the issue pre-committed to — an 18 arrives, and `Image` is
  `System`. Plus one correction the issue did not anticipate: the field set is wrong in our
  fixtures.

## The question

`detections/sigma/lateral_movement/svcctl_atsvc_remote_pipe_sysmon_18.yml` and
`detections/sigma/credential_access/coercion_efsrpc_pipe_sysmon_18.yml` both rest on two claims
that had never been observed:

1. Sysmon emits an EventID 18 at all when the NPFS create is issued by `srv2.sys` in kernel on
   behalf of a remote SMB client, rather than by a user-mode process.
2. `Image` reads `System` on that event — the entire invariant of the atsvc/svcctl rule, and the
   thing separating impacket from a local `sc.exe` or `schtasks.exe`.

## Telemetry source

Not a first-party lab run. This is a **third-party capture**: real Sysmon EVTX from real hosts,
published in `sbousseaden/EVTX-ATTACK-SAMPLES`, pinned at commit
`4ceed2f4706daf601c212a8f91c113dd85349a2c`.

| Sample | Host | Date | Relevance |
| --- | --- | --- | --- |
| `Discovery/Discovery_Remote_System_NamedPipes_Sysmon_18.evtx` | `MSEDGEWIN10` | 2020-09-27 | remote pipe enumeration — 20 binds, includes `\atsvc` |
| `Discovery/discovery_sysmon_18_Invoke_UserHunter_NetSessionEnum_DC-srvsvc.evtx` | `DC1.insecurebank.local` | 2019-05-14 | remote `srvsvc` bind (NetSessionEnum) |
| `Lateral Movement/lm_sysmon_18_remshell_over_namedpipe.evtx` | `IEWIN7` | 2019-04-29 | remote shell over a named pipe |
| `Defense Evasion/DE_renamed_psexec_service_sysmon_17_18.evtx` | `MSEDGEWIN10` | 2020-09-27 | psexec 17/18 pairs, plus local binds |

Parsed with `chainsaw 2.16.4` (`chainsaw dump --json`). 33 PipeEvent records across the four
samples: 29 EventID 18 and 4 EventID 17.

## Finding 1 — an 18 does arrive, with `Image` `System` and `ProcessId` 4

Every remote-origin bind observed, across three hosts and two Sysmon eras, is attributed to the
System process. The direct hit is `\atsvc` — one of the two pipe names the rule selects —
verbatim from the capture:

```json
{
  "Event": {
    "System": {
      "Provider_attributes": { "Name": "Microsoft-Windows-Sysmon" },
      "EventID": 18,
      "TimeCreated_attributes": { "SystemTime": "2020-09-27T13:19:54.272246Z" },
      "Channel": "Microsoft-Windows-Sysmon/Operational",
      "Computer": "MSEDGEWIN10"
    },
    "EventData": {
      "RuleName": "",
      "EventType": "ConnectPipe",
      "UtcTime": "2020-09-27 13:19:54.263",
      "ProcessGuid": "747F3D96-0C7A-5F71-0000-0010EB030000",
      "ProcessId": 4,
      "PipeName": "\\atsvc",
      "Image": "System"
    }
  }
}
```

In that one capture, 18 remote binds covering **14 distinct pipe names** arrive this way —
`\atsvc`, `\srvsvc`, `\wkssvc`, `\lsass`, `\ntsvcs`, `\scerpc`, `\epmapper`, `\browser`,
`\eventlog`, `\InitShutdown`, `\LSM_API_service`, `\ROUTER`, `\tapsrv`, `\trkwks` — all
`Image=System`, all `ProcessId=4`, inside 160 ms (13:19:54.231 → .390). Across all four
samples, 16 distinct pipe names arrive as remote `System`/pid-4 binds. Claims 1 and 2 are
both confirmed.

The true-negative premise is confirmed in the same captures: local binds carry their own image
(`C:\Windows\system32\mmc.exe` on `\wkssvc` and `\browser`, `C:\Windows\system32\PsExec.exe` on
its own stdin/stdout/stderr pipes). That is exactly the shape
`svcctl_atsvc_pipe_18_tn.jsonl` asserts.

## Finding 2 — the shipped rule fires on the real event

Not on our fixture. The captured records above, normalised and run through the real rule with the
same engine the gate uses (zircolite v3.7.6, `--pipeline sysmon`):

```text
svcctl_atsvc_remote_pipe_sysmon_18   rc=0  FIRED id=e9d70412-5340-436c-9917-b3664f5d77a7 matches=1
coercion_efsrpc_pipe_sysmon_18       rc=0  SILENT (no detections)
```

The match:

```text
Computer    = 'MSEDGEWIN10'
EventType   = 'ConnectPipe'
PipeName    = '\atsvc'
Image       = 'System'
ProcessId   = 4
UtcTime     = '2020-09-27 13:19:54.263'
```

The efsrpc rule staying silent is correct — no `\efsrpc` bind occurs in these samples. It is a
true negative against real telemetry, not a failure.

This is lifecycle Step 4 for the atsvc/svcctl rule, on a real event from a real host.

## Finding 3 — the fixtures had the wrong field set (not anticipated by #235)

The captured `EventData` key set is:

```text
RuleName, EventType, UtcTime, ProcessGuid, ProcessId, PipeName, Image
```

All six Sysmon-pipe fixtures in this repo carried a **`User` field that Sysmon does not emit on
PipeEvent**, and omitted **`RuleName`, which it does**. No `User` appears on any of the 33
captured records, on any host, in either Sysmon era. Two independent published sources agree:
the TrustedSec Sysmon Community Guide's PipeEvent field list, and Splunk's own EID 18 sample
event, which renders `RuleName` as `-` and carries no `User`.

Neither rule selects on `User`, so this never made them unsatisfiable. But both rule descriptions
argued *"`User` is the LOCAL process's identity (SYSTEM), not the account on the far end of the
SMB session"* as the reason no principal filter is available. That reasoning was wrong in detail
while its conclusion was right and is now stronger: PipeEvent carries **no user field at all**.
Both descriptions have been corrected.

Two further fidelity corrections from the same capture: `ProcessId` is a JSON number, not a
string, and `ProcessGuid` is rendered without braces.

`PipeName` spelling is confirmed as our fixtures already had it — a single leading backslash,
no `\Device\NamedPipe\` prefix.

## Finding 4 — the `EventType` pin is real, and older builds really do omit it

Both rules pin `EventType: 'ConnectPipe'`, and each carries a false-positive note warning that a
Sysmon that omits `EventType` would make the selection *silently unsatisfiable rather than
noisy*. That is not hypothetical. The two 2019-era samples (`IEWIN7`, `DC1.insecurebank.local`)
carry **no `EventType` field at all** — the field is present on the 2020-era `MSEDGEWIN10`
samples and absent on the older pair.

So the pin is safe on any modern Sysmon and is a genuine coverage cliff on old ones. The shipped
`detections/sysmon/sysmonconfig-detection-lab.xml` is `schemaversion="4.90"` (Sysmon 15.x), well
past that boundary. The warning stays in both rules, now stated as observed rather than feared.

## What this run does NOT settle

Honest limits, all of which keep [#235] open:

- **It is not first-party.** These are someone else's hosts on Sysmon builds from 2019–2020, not
  our `sysmonconfig-detection-lab.xml` at schema 4.90. The provenance rows therefore move to
  `vendor-documented`, not `captured`. See `README.md` in this directory for why that line is
  drawn where it is.
- **`\svcctl` and `\efsrpc` were not directly observed.** `\atsvc` was — a direct hit on half the
  atsvc/svcctl selection. The generalisation to the other two names is an argument, not a
  measurement: the PipeEvent include list filters on `PipeName` only, and the kernel path
  servicing a remote SMB pipe open is the same NPFS create regardless of which name is opened,
  as evidenced by 16 different names arriving identically attributed. Strong, but state it as
  inference.
- **The `\lsarpc` volume question is untouched.** #233 declined an lsarpc rule on the argument
  that coercion and routine domain binds are byte-identical on this plane, and scoped the
  atsvc/svcctl rule as a triage surface. Both arguments remain sound on the schema and
  unquantified on volume. Counting `\lsarpc` versus `\svcctl`/`\atsvc` 18s over a working day on
  a domain-joined host still needs a real estate. `runbook-sysmon18-remote-pipe.md` in this
  directory is how to collect it.

## Reproducing this

```bash
docker/validation/evtx-to-fixture.sh --event-id 18 path/to/sample.evtx > /tmp/real.jsonl
```

then run that JSONL through the rule exactly as `run-sigma-validation.sh` does.

[#235]: https://github.com/dotgibson/dotfiles-Defense/issues/235
