# Runbook — first-party confirmation of the potato / SeImpersonate pair

What is left of [#239] and the open half of [#230] after
`2026-08-potato-sysmon1-user-semantics.md` settled the field semantics from a third-party
capture. Three things still need a real host, and none of them needs a domain.

Assumes **no existing lab**. Nothing in `docker/` builds a Windows host —
`detection-lab.compose.yml` is OpenSearch + Dashboards, a log store with no ingestion path — so
the Windows side is yours to stand up.

## What is still open, and why each needs a host

1. **`ParentUser` on a real potato.** This is the field
   `potato_seimpersonate_sysmon_1.yml` now selects, and it has never been observed on one. All
   six potato captures in `sbousseaden/EVTX-ATTACK-SAMPLES` predate Sysmon 13, so the run
   record's fire/silent table set `ParentUser` to the parent process's own captured `User`.
   That derivation is well grounded — the parent is the tool on all six, with no Secondary
   Logon reparenting — but it is a derivation. One Sysmon 15 host closes it, and moves
   `potato_sysmon1.jsonl` and its TN from `vendor-documented` to `captured`.
2. **Whether `potato_seimpersonate_4688.yml` fires on a real potato — it never has.** No
   capture in the corpus carries a Security 4688 for a potato at all, let alone one whose
   `SubjectUserName` is an app pool. Its fixture proves only that the rule fires on the event
   shape we believe in. This is the oldest unconfirmed claim in the pair and the cheapest to
   close: it is one `auditpol` setting away on the same host as item 1.
3. **`SubjectUserSid` on that 4688 — the `ONE ASSUMPTION, STATED` in
   `token_theft_process_target_subject_4688.yml`.** Whether the audit takes Creator Subject
   from the calling process's token or from its impersonating thread token is still inference.
   If it is the thread token, `SubjectUserSid` arrives `S-1-5-18` and `filter_same_context`
   removes that rule's own true positive. The run record narrowed this — the *process* parent
   is the tool on all six captures, so the seclogon-reparenting route to the same failure is
   ruled out for this family — but the thread-token route is untouched, because it is a
   property of the audit subsystem rather than of the process tree.

## Standing it up

One Windows target — Windows 10 or Server 2016+, because event version 2 is where the Target
Subject block exists — plus an attacker box with `dotfiles-Offense`. IIS with a default app
pool if you want item 2 in its canonical form.

```powershell
# On the target, from an elevated prompt.
sysmon.exe -accepteula -i sysmonconfig-detection-lab.xml
sysmon.exe -c            # confirm the config took, and record the reported schema version
```

Record the Sysmon version and schema version now. Item 1 is only meaningful on **13 or later**,
and the whole point is that it differs from the third-party capture (2019–2021 builds vs our
shipped `schemaversion="4.90"`, Sysmon 15.x).

Both items 2 and 3 need the Security channel to carry 4688 with a command line:

```powershell
auditpol /set /subcategory:"Process Creation" /success:enable /failure:disable
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f
```

## Firing it

From `dotfiles-Offense`, hacktheplanet "Windows privilege escalation" fold, htpx pair
`potato-seimpersonate`. Run each one at a time and note the wall-clock, so events can be
attributed with confidence rather than guessed at from a mixed log.

| Tool | Run it as | Payload | What it should settle |
| --- | --- | --- | --- |
| PrintSpoofer `-i -c cmd.exe` | NETWORK SERVICE or LOCAL SERVICE | a named shell | items 1, 2, 3 together |
| GodPotato `-cmd "cmd /c whoami"` | an IIS app-pool identity | not a shell | item 2 in its canonical `IIS APPPOOL` form |
| JuicyPotato `-t u` then `-t t` | any service identity | a named shell | whether the `CreateProcessAsUser` and `CreateProcessWithTokenW` paths differ in `ParentImage` / `ParentUser` — the one place seclogon reparenting could still bite |

The `-t u` / `-t t` pair matters. Every capture the run record examined ended up parented to the
tool, but JuicyPotato is the one tool that lets the operator select the API, so it is the only
cheap way to test both paths on one host.

## Capturing

```powershell
wevtutil epl Microsoft-Windows-Sysmon/Operational C:\sysmon-run.evtx
wevtutil epl Security C:\security-run.evtx
```

Pull both to the analysis box and normalise with the tool that already exists:

```bash
docker/validation/evtx-to-fixture.sh --event-id 1    --channel Sysmon   sysmon-run.evtx
docker/validation/evtx-to-fixture.sh --event-id 4688 --channel Security security-run.evtx
```

Then read, in this order, and write a run record for whatever the answers are:

1. On the escalated process's Sysmon 1 — is `ParentUser` the service identity?
2. On the same process's 4688 — is `SubjectUserName` the service identity, or is
   `SubjectUserSid` `S-1-5-18`?
3. Is the Target Subject block populated, and does `TargetUserSid` read `S-1-5-18` rather than
   the null SID `S-1-0-0` the run record observed on one captured event?

Answer 2 decides whether `potato_seimpersonate_4688.yml` and
`token_theft_process_target_subject_4688.yml` survive contact with a real potato. Answer it
before touching either rule.

[#239]: https://github.com/dotgibson/dotfiles-Defense/issues/239
[#230]: https://github.com/dotgibson/dotfiles-Defense/issues/230
