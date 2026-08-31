# Does a parent/child identity mismatch on Sysmon 1 detect the potato, and what does it cost?

- **Date:** 2026-08-29, re-measured over the full corpus 2026-08-30
- **Issue:** follow-on from
  [dotgibson/dotfiles-Defense#239](https://github.com/dotgibson/dotfiles-Defense/issues/239),
  which measured the field semantics this rule depends on
- **Outcome:** the shape works — **5 of 6** real potato captures, **0** other matches across
  **1491** records — and the measurement also killed the variant that looked more elegant

## The question

Issue #239 corrected `potato_seimpersonate_sysmon_1.yml` to key on `ParentUser`, the creator,
restoring it as the true per-channel twin of `potato_seimpersonate_4688.yml`. It deliberately
did not add the *other* shape the same measurement made available: `User` (the child) being
SYSTEM while `ParentUser` (the creator) is a service identity — the swap having succeeded,
rather than the shape before it.

That is a different and stronger claim, so it needed its own rule and its own evidence. Three
things had to be settled before writing it:

1. does it earn the TA0005 (Stealth) half of T1134.001, which the potato pair correctly
   declines;
2. should it carry the pair's `Image` shell list;
3. what is its false-positive surface.

## Telemetry source

The same third-party capture set as
[`2026-08-potato-sysmon1-user-semantics.md`](2026-08-potato-sysmon1-user-semantics.md), which
carries the full provenance discussion: `sbousseaden/EVTX-ATTACK-SAMPLES` pinned at
`4ceed2f4706daf601c212a8f91c113dd85349a2c`, parsed with `chainsaw 2.16.4`, normalised with
`docker/validation/evtx-to-fixture.sh --event-id 1`. **All 278 EVTX swept, 1491 Sysmon-1
records in total**, of which six are potato swap events (RogueWinRM, NetworkServiceExploit,
RottenPotato from an IIS webshell, EfsPotato, RoguePotato, PrintSpoofer — four hosts,
2019–2021).

All six captures predate Sysmon 13, so none carries `ParentUser`. As in the #239 run it was
derived by linking each record to its parent's own Sysmon-1 record on `ParentProcessGuid` →
`ProcessGuid`; 1090 of the 1491 records resolve a parent that way. That derivation is the
load-bearing limit on everything below and is restated at the end.

## Finding 1 — the shape finds every potato launched from a service context, and nothing else

Engine: zircolite v3.7.6, pySigma 1.5.0, `--pipeline sysmon` — the same engine and pins the
gate uses.

```text
selection:        User|contains: 'SYSTEM'
selection_parent: ParentUser|contains: ['APPPOOL','NETWORK SERVICE','LOCAL SERVICE']

  against the six potato captures       rc=0  FIRED matches=5
  against all 1491 Sysmon-1 records     rc=0  FIRED matches=5   (the same five)

      LAPTOP-JU4M3I0E  EfsPotato.exe             -> whoami.exe     ParentUser=NT AUTHORITY\NETWORK SERVICE
      MSEDGEWIN10      NetworkServiceExploit.exe -> cmd.exe        ParentUser=NT AUTHORITY\NETWORK SERVICE
      MSEDGEWIN10      RogueWinRM.exe            -> cmd.exe        ParentUser=NT AUTHORITY\LOCAL SERVICE
      MSEDGEWIN10      RoguePotato.exe           -> nc64.exe       ParentUser=NT AUTHORITY\LOCAL SERVICE
      IEWIN7           notepad.exe               -> notepad.exe    ParentUser=IIS APPPOOL\DefaultAppPool

The sixth, PrintSpoofer, is missed and should be: its operator was an already-interactive admin,
so `ParentUser` reads `MSEDGEWIN10\IEUser` rather than a service identity. This rule's invariant
is a SYSTEM child created by a SERVICE identity, and that capture is not one. It is the same
record `potato_seimpersonate_sysmon_1.yml` uses as its true negative.

Three payloads in that list — `whoami.exe`, `nc64.exe`, `notepad.exe` — are not named shells,
which is the class this rule exists to catch and the potato pair's `Image` list cannot.
```

```text
  2020-05-24 01:13:50.301  MSEDGEWIN10
      C:\Users\IEUser\Tools\PrivEsc\RogueWinRM.exe        -> C:\Windows\System32\cmd.exe
      User=NT AUTHORITY\SYSTEM   ParentUser=NT AUTHORITY\LOCAL SERVICE
  2020-05-10 00:09:36.703  MSEDGEWIN10
      C:\Users\IEUser\Tools\PrivEsc\NetworkServiceExploit.exe -> C:\Windows\System32\cmd.exe
      User=NT AUTHORITY\SYSTEM   ParentUser=NT AUTHORITY\NETWORK SERVICE
  2019-05-26 15:48:00.742  IEWIN7
      C:\Windows\System32\notepad.exe                     -> C:\Windows\System32\notepad.exe
      User=NT AUTHORITY\SYSTEM   ParentUser=IIS APPPOOL\DefaultAppPool
  2021-08-22 19:33:38.890  LAPTOP-JU4M3I0E
      C:\temp\EfsPotato.exe                               -> C:\Windows\System32\whoami.exe
      User=NT AUTHORITY\SYSTEM   ParentUser=NT AUTHORITY\NETWORK SERVICE
```

Every match is a potato. No benign record in the corpus — including 79 Sysmon-1 records of
ordinary boot and logon activity from `privesc_unquoted_svc_sysmon_1_11.evtx` — produces one.

## Finding 2 — the `Image` shell list would cost half the detections and buy nothing

Three variants over the same 1491 records:

| Selection | potato hits | other matches |
| --- | --- | --- |
| `User`=SYSTEM + `ParentUser`=service, **no `Image`** | **5 / 6** | 0 |
| the same, plus the pair's `Image` shell list | 2 / 6 | 0 |
| the shipped `potato_seimpersonate_sysmon_1` (`ParentUser` + `Image`) | 2 / 6 | 0 |

The three the shell list drops are RottenPotato (`notepad.exe`), EfsPotato (`whoami.exe`) and
RoguePotato (`nc64.exe`). It removes no noise, because across 1491 records there is none to
remove. (The sixth capture, PrintSpoofer, is outside every row's reach for the separate reason
in Finding 1: its creator is a named user, not a service identity.) **So the rule ships without an `Image`
constraint**, which is the same argument `token_theft_process_target_subject_4688.yml` already
makes for itself on the 4688 plane — it survives `-c nc.exe`, `-c whoami`, and any payload that
is not a named shell.

## Finding 3 — the more elegant variant is a backend-dependent trap

The obvious alternative mirrors the 4688 rule's structure — select `User`=SYSTEM, filter out
the case where the creator is SYSTEM too — and so catches *any* non-SYSTEM creator rather than
three named identities:

```yaml
  selection:
    User|contains: 'SYSTEM'
  filter_same_context:
    ParentUser|contains: 'SYSTEM'
  condition: selection and not filter_same_context
```

Over 147 records it looked indistinguishable. Over all 1491 it is not: it matches **8**, and
the three beyond the shipped shape's five are instructive rather than reassuring.

```text
  MSEDGEWIN10  PPLdump.exe    -> services.exe    User=NT AUTHORITY\SYSTEM  ParentUser=MSEDGEWIN10\IEUser
  MSEDGEWIN10  PrintSpoofer.exe -> powershell.exe User=NT AUTHORITY\SYSTEM  ParentUser=MSEDGEWIN10\IEUser
  MSEDGEWIN10  -              -> svchost.exe     User=NT AUTHORITY\SYSTEM  ParentUser=-
```

The first two are arguably wanted — PPLdump is a real privilege-escalation tool, and
PrintSpoofer is the potato the narrower shape misses — so on hits alone the filter form looks
*better*. The third is the tell: `ParentUser` is `-`, Sysmon's placeholder for a parent it could
not resolve, and `-` does not contain `SYSTEM`, so a negated filter passes it through. A rule
whose selection is "anything not matching" inherits every unresolvable value as a match. 401 of
the 1491 records resolve no parent at all, so that is not a corner case. It is still the wrong
choice for the reason below as well, which only shows up in conversion:

```text
positive form   splunk  EventID=1 User="*SYSTEM*" ParentUser IN ("*APPPOOL*", "*NETWORK SERVICE*", "*LOCAL SERVICE*")
negated form    splunk  EventID=1 User="*SYSTEM*" NOT ParentUser="*SYSTEM*"
```

In Splunk, `NOT field="value"` **matches events where the field does not exist**. A
pre-Sysmon-13 host emits no `ParentUser` at all, so the negated form fires on every SYSTEM
process creation on that host — 50 such records in this corpus. Replayed through zircolite,
whose SQLite backend gives NULL rather than TRUE for the same negation, it matches none of
them:

```text
  corpus with ParentUser stripped (the pre-13 reality, 50 records with User=SYSTEM)
    positive form   matches=0
    negated form    matches=0     <- under zircolite/SQLite only
```

A rule that is silent in CI and floods one production backend on exactly the hosts that cannot
satisfy it is the #149 shape wearing a new face, and the gate cannot see it because the gate
runs the backend that stays quiet. The positive form requires the field to be present and
cannot behave that way. **Shipped as the positive form, and the rejected variant is written
into the rule so it is not re-proposed.**

## Finding 4 — what the rule gives up against its 4688 sibling

Both readings are worth having, and they fail differently, which is the argument for deploying
both rather than treating one as the other's fallback.

`token_theft_process_target_subject_4688.yml` is the stronger claim on stronger evidence:
Windows populates 4688's Target Subject block only when creator and target "do not share the
same logon", so the OS asserts the mismatch instead of leaving a rule to infer it, and it keys
on the SID `S-1-5-18`, which localisation does not move. Sysmon 1 carries **no SID field** —
verified against every one of the 1491 records, whose 23 distinct `EventData` keys include no
`*Sid` at all — so this rule must match the string `SYSTEM`,
and a locale that translates the account name defeats it.

The compensation is real. The open question on the 4688 rule (#238) is whether the audit reads
Creator Subject from the calling process's token or from its impersonating *thread* token; on
the thread-token reading `SubjectUserSid` arrives `S-1-5-18` and that rule's
`filter_same_context` deletes its own true positive. `ParentUser` is resolved from the parent
**process's** token and is untouched by that question. Where the 4688 rule might fall, this one
stands.

## What this run does NOT settle

- **`ParentUser` was never observed on a potato.** All six potato captures predate Sysmon 13.
  The values above were derived by GUID-linking each record to its parent's own Sysmon-1
  record; 1090 of the 1491 records resolve a parent that way, and the 401 that do not are the
  same population that makes the negated-filter variant in Finding 3 unsafe. This proves the rule selects the right *field semantics* on real process trees; it
  does not prove it fires on an untouched captured event. The first-party run tracked by
  dotgibson/dotfiles-Defense#246 closes that, and it closes it for this rule at the same time.
- **The zero-false-positive result is "not yet met", not "does not occur".** It is now measured
  over 1491 records rather than 147, which is a stronger negative set but not a representative
  one: the corpus is an attack-sample collection. It contains no EDR, RMM or patch agent, which is precisely the
  benign population that legitimately spawns SYSTEM helpers from a service identity. That
  false-positive class is stated in the rule and is not measured here.
- **The locale exposure is reasoned, not measured.** Every host in the corpus is
  English-language. No translated `SYSTEM` account name was observed either matching or
  failing to match.
- **Nothing here touches 4688.** No 4688 from a potato exists in the corpus, so #238's Creator
  Subject question and #239's question about `potato_seimpersonate_4688.yml` are exactly as
  open as they were.

## Reproducing this

```bash
docker/validation/evtx-to-fixture.sh --event-id 1 path/to/RogueWinRM.evtx > /tmp/real.jsonl
```

Link each record to its parent on `ParentProcessGuid` → `ProcessGuid` and copy the parent's
`User` into `ParentUser` before the run — the injection is what makes this a derivation rather
than a capture and must be stated wherever the result is cited. Then run that JSONL through the
rule exactly as `run-sigma-validation.sh` does. For Finding 3, convert both forms with
`sigma convert -t splunk -p sysmon` and read the `NOT` clause.
