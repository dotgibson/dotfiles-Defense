# Runbook — first-party confirmation of the potato / SeImpersonate pair

What is left of [#239] and the open half of [#230] after
`2026-08-potato-sysmon1-user-semantics.md` settled the field semantics from a third-party
capture. #239 is closed on the correction; this runbook's items are tracked as [#246]. Three
things still need a real host, and none of them needs a domain.

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
   `potato_sysmon1_tp.jsonl` and its TN from `vendor-documented` to `captured`.
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

## What this run predicts

Written down before the host exists, so the record cannot be composed to fit whatever the log
turned out to say. `2026-08-sysmon18-remote-pipe.md` reports its result as "1 of 3 pre-committed
claims confirmed" for the same reason: a prediction made after the measurement is not a
prediction.

1. On the escalated process's Sysmon 1, **`ParentUser` reads the service identity**, and equals
   the parent process's own `User` on its own Sysmon 1 in the same log. (Both halves matter. The
   corpus never confirmed the second, because in none of the four records carrying `ParentUser`
   is the parent's own Sysmon 1 present.)
2. On that same process's 4688, **`SubjectUserName` reads the service identity** — the app pool
   or `NETWORK SERVICE`/`LOCAL SERVICE` — and `potato_seimpersonate_4688.yml` fires.
3. **`SubjectUserSid` is the creating process's token SID, not `S-1-5-18`.** Equivalently: the
   audit reads Creator Subject from the process token, and `filter_same_context` in
   `token_theft_process_target_subject_4688.yml` does not eat its own true positive.

A fourth, weaker expectation, worth recording because the corpus already contradicted it once:
**`TargetUserSid` reads `S-1-5-18`** rather than the null SID `S-1-0-0`. One captured
event-version-2 4688 in the corpus populates `TargetUserName`/`TargetDomainName`/`TargetLogonId`
while `TargetUserSid` is `S-1-0-0`, so this is the least safe of the four.

## Standing it up

The target OS is not one choice, because items 2–3 and the JuicyPotato row below want different
builds.

- **Primary target — Windows 10 1809+ or Server 2019+.** Event version 2 is where the Target
  Subject block exists, and this is the build class anything deployed today actually runs. It
  covers items 1, 2 and 3.
- **Optional second target — Windows 10 1803 or earlier / Server 2016.** Only for the
  JuicyPotato row. JuicyPotato's BITS/DCOM CLSID route was fixed in 1809 and Server 2019 —
  RoguePotato exists precisely because it stopped working — so on the primary target that row
  will not run at all. If you skip this box, say so in the run record and leave the API-path
  question open rather than letting it read as measured.

Plus an attacker box with `dotfiles-Offense`, and IIS with a default app pool if you want item 2
in its canonical `IIS APPPOOL\DefaultAppPool` form.

```powershell
# On the target, from an elevated prompt.
sysmon.exe -accepteula -i sysmonconfig-detection-lab.xml
sysmon.exe -c            # confirm the config took, and record the reported schema version
```

Item 1 is only meaningful on Sysmon **13 or later**, and the whole point is that it differs from
the third-party capture (2019–2021 builds vs our shipped `schemaversion="4.90"`, Sysmon 15.x).

Both items 2 and 3 need the Security channel to carry 4688 with a command line:

```powershell
auditpol /set /subcategory:"Process Creation" /success:enable /failure:disable
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f
auditpol /get /subcategory:"Process Creation"    # confirm it took, and record the output
```

### Record these before firing anything

None of it is recoverable once the host is gone, and `labruns/README.md` requires a first-party
capture to name the host, the Sysmon build and the attack that produced it.

- Sysmon version and the schema version `sysmon.exe -c` reported.
- Windows build (`winver` / `[System.Environment]::OSVersion` plus the release ID).
- The exact tool builds — version string and, where the tool is built from source, the commit.
- The `auditpol /get` output above.
- Wall-clock for each tool as you run it, so events are attributed rather than guessed at from a
  mixed log.
- Hostname, since it lands in every fixture's `Computer` field.

## Firing it

From `dotfiles-Offense`, hacktheplanet "Windows privilege escalation" fold, htpx pair
`potato-seimpersonate`. **Run each one at a time**, noting the wall-clock.

Five rows, not three. The first three settle the open items; rows D and E exist so the run can
produce first-party *true negatives* as well as true positives, which is the difference between
promoting one fixture and promoting a pair.

| # | Tool | Run it as | Payload | What it produces |
| --- | --- | --- | --- | --- |
| A | GodPotato `-cmd "cmd /c whoami"` | an IIS app-pool identity | `cmd.exe` | items 1, 2, 3 together, and the potato pair's TP in its canonical `IIS APPPOOL` form |
| B | PrintSpoofer `-i -c cmd.exe` | NETWORK SERVICE or LOCAL SERVICE | `cmd.exe` | the same three items from a second identity — belt and braces if IIS is not stood up |
| C | PrintSpoofer `-i -c powershell.exe` | **an interactive admin shell** | `powershell.exe` | the potato pair's **true negative** — a genuine potato whose creator is a user, not a service identity |
| D | GodPotato `-cmd "whoami"` | an IIS app-pool identity | `whoami.exe`, not a shell | `token_theft_parent_child_mismatch_sysmon_1.yml`'s TP — the class the potato pair's `Image` list cannot catch |
| E | plain `whoami.exe` from the webshell, no escalation | the same app-pool identity | `whoami.exe` | that rule's **true negative** — a service process spawning under its own token |
| F | JuicyPotato `-t u` then `-t t` | any service identity | a named shell | *second target only.* Whether the `CreateProcessAsUser` and `CreateProcessWithTokenW` paths differ in `ParentImage`/`ParentUser` |

Row C is the one most easily skipped and the one that costs most later. `potato_sysmon1_tn.jsonl`
today is a real potato launched by an already-interactive admin, so `ParentUser` reads
`MSEDGEWIN10\IEUser` and the rule correctly declines it. Without row C the TP is promoted to
`captured` and the TN is stranded at `vendor-documented`, which is a mixed-tier pair asserting a
discrimination only half of it can support.

Row F matters because JuicyPotato is the one tool that lets the operator select the API, so it is
the only cheap way to test both paths on one host. Every capture the run record examined ended up
parented to the tool — but every capture was also produced by a tool that chose for itself.

## Capturing

```powershell
wevtutil epl Microsoft-Windows-Sysmon/Operational C:\sysmon-run.evtx
wevtutil epl Security C:\security-run.evtx
```

Pull both to the analysis box and normalise with the tool that already exists. It writes JSONL to
**stdout** — redirect it; do not pass an output path:

```bash
docker/validation/evtx-to-fixture.sh --event-id 1    --channel Sysmon   sysmon-run.evtx   > sysmon-run.jsonl
docker/validation/evtx-to-fixture.sh --event-id 4688 --channel Security security-run.evtx > security-run.jsonl
```

### The constraint that must be satisfied before the host is torn down

`check_near_miss` in `run-sigma-validation.sh` requires every TN fixture to carry the **identical
EventID set and the identical `EventData` key set** as its TP. So the TP and TN of a pair must
come off the **same host and the same Sysmon build**, and the payloads must be alike enough that
Sysmon emits the same keys for both — a binary carrying no version resource drops
`FileVersion`/`Description`/`Product`/`Company`/`OriginalFileName`, and the pair then fails the
gate. Rows A/C and D/E above are chosen to satisfy this.

Diff the key sets before you release the host:

```bash
for f in sysmon-run.jsonl security-run.jsonl; do
  python3 -c 'import sys,json
for l in open(sys.argv[1]):
    e=json.loads(l)["Event"]
    print(e["System"]["EventID"], "|", ",".join(e["EventData"].keys()))' "$f" | sort -u
done
```

Every Sysmon-1 line should print the same key list. If it does not, re-capture rather than
hand-editing a fixture into agreement — hand-editing is how `token_theft_sysmon1_tn.jsonl` ended
up `unverified`.

Then run the shipped rules against the capture with the same engine and pins the gate uses
(zircolite v3.7.6, pySigma 1.5.0):

```bash
PYTHON=... ZIRCOLITE=.../zircolite.py ZDIR=.../. \
  python "$ZIRCOLITE" -j -e sysmon-run.jsonl \
  -r detections/sigma/privilege_escalation/potato_seimpersonate_sysmon_1.yml \
  --pipeline sysmon -c "$ZDIR/config/config.yaml" -o fired.json

python "$ZIRCOLITE" -j -e security-run.jsonl \
  -r detections/sigma/privilege_escalation/potato_seimpersonate_4688.yml \
  --pipeline windows-audit -c "$ZDIR/config/config.yaml" -o fired-4688.json
```

Repeat for `token_theft_parent_child_mismatch_sysmon_1.yml` (`--pipeline sysmon`) and
`token_theft_process_target_subject_4688.yml` (`--pipeline windows-audit`).

## Reading it

In this order, and write a run record for whatever the answers are:

1. On the escalated process's Sysmon 1 — is `ParentUser` the service identity, and does it equal
   the parent process's own `User` on the parent's own Sysmon 1 in the same log?
2. On the same process's 4688 — is `SubjectUserName` the service identity, or is
   `SubjectUserSid` `S-1-5-18`?
3. Is the Target Subject block populated, and does `TargetUserSid` read `S-1-5-18` rather than
   the null SID `S-1-0-0` the run record observed on one captured event?

Answer 2 decides whether `potato_seimpersonate_4688.yml` and
`token_theft_process_target_subject_4688.yml` survive contact with a real potato. Answer it
before touching either rule.

**A third outcome on question 1.** `ParentUser` can arrive as the `-` placeholder, which is
Sysmon saying it could not resolve the parent rather than saying anything about identity. 401 of
the 1491 Sysmon-1 records swept in the #239 sweep resolve no parent that way, and that placeholder
is exactly why the negated-filter rule shape was rejected in `2026-08-token-mismatch-sysmon-1.md`.
If a first-party potato produces `-`, item 1 is answered — "the field is present but
unresolvable on this path, and the rule is silently unsatisfiable there" — and that is a finding
to record, not a failed run to retry. It would also mean the fixture cannot be promoted, because
the captured event does not fire the rule.

## Filing the result

Add a run record to this directory following `README.md`, named `YYYY-MM-<subject>.md`. Then:

### What a result can and cannot promote

`captured` is first-party capture — our config, our host, our attack — so a row moves only when
the fixture is **replaced with the captured event**. Citing the run record over a fixture that is
still hand-authored or still third-party does not earn the tier, and #246's phrasing that closing
this "does the same for `token_theft_sysmon1_*`" is wrong on exactly that point: that TP is a
synthetic host (`Computer: WEB01`) modelled on the corpus, not a capture.

| Fixture | Provenance row | Reaches `captured` when replaced with |
| --- | --- | --- |
| `potato_sysmon1_tp.jsonl` | 166 | row A (or B) — the escalated process's Sysmon 1 |
| `potato_sysmon1_tn.jsonl` | 167 | row C — the interactive-admin capture, same key set |
| `potato_security_4688.jsonl` | 165 | row A's 4688. Today its identity block is *constructed*, and its Target Subject block is deliberately null pending exactly this measurement |
| `token_theft_sysmon1_tp.jsonl` | 168 | row D — the non-shell payload. Synthetic today |
| `token_theft_sysmon1_tn.jsonl` | 169 | row E. `unverified` today, hand-authored from its TP |
| `token_theft_4688_{tp,tn}.jsonl` | 190, 189 | row A's 4688 and any same-context 4688 from the same log |

When a row moves, drop the trailing `first-party run still open as dotgibson/dotfiles-Defense#246`
clause from its note and cite the new run record instead. These would be the repo's first
`captured` rows — `check-fixture-provenance.sh` reports 0 today.

### Branches

- **All three predictions hold.** Replace the fixtures per the table, move rows 165–169 and
  189–190 in `docker/validation/fixture-provenance.tsv` from `vendor-documented` to `captured`,
  and close #246. Nothing about the rules changes; this is the branch where the derivation
  behind them turns out to have been right.
- **Item 3 fails — `SubjectUserSid` reads `S-1-5-18`.** The expensive branch, and the reason
  question 2 is answered first. On the thread-token reading, `filter_same_context` in
  `token_theft_process_target_subject_4688.yml` deletes that rule's own true positive, and
  `potato_seimpersonate_4688.yml` goes silent for the same reason — its `SubjectUserName` would
  read `SYSTEM`, never an app pool. That is a two-rule rework, not a fixture edit. Reopen [#238]
  and [#230] with the measurement attached, and note that
  `token_theft_parent_child_mismatch_sysmon_1.yml` is the rule that survives it: `ParentUser` is
  resolved from the parent *process*'s token and is untouched by the question. Its description
  already makes that claim and would finally have evidence for it.
- **Item 2 fails but item 3 holds.** The 4688 arrives with a subject that is neither the app pool
  nor `S-1-5-18`. Correct `potato_seimpersonate_4688.yml`'s selection to what was measured and
  say in the record which claim the capture overturned — the #239 shape, where the fix is a
  field, not a threshold.
- **`ParentUser` reads `-`.** As above: record it, do not promote the Sysmon rows, and treat the
  rule's silence on that path as measured rather than as a bug in the capture.
- **No 4688 at all despite `auditpol`.** This contradicts documented behaviour rather than merely
  being unproven, so re-measure before acting — check the `auditpol /get` output was captured and
  that Row A actually produced a process creation.

### Manifest consequences

`docker/validation/sigma-manifest.tsv` row 40 (`potato-seimpersonate-4688`) carries `-` in the TN
column, and the rule has no `filter_*` block, so `check-rule-coverage.sh` does not require a true
negative. It is still worth adding one: the same capture session yields a benign 4688 for free,
and the pair costs nothing to carry. Rows 38, 39 and 115 already name both fixtures and need no
structural change — only the fixtures behind them are replaced.

[#230]: https://github.com/dotgibson/dotfiles-Defense/issues/230
[#238]: https://github.com/dotgibson/dotfiles-Defense/issues/238
[#239]: https://github.com/dotgibson/dotfiles-Defense/issues/239
[#246]: https://github.com/dotgibson/dotfiles-Defense/issues/246
