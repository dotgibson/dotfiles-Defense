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
2. On that same process's 4688, **`SubjectUserName` reads the service identity** — and record the
   exact field split, because 4688 does not qualify the account the way Sysmon does. Sysmon puts
   `IIS APPPOOL\DefaultAppPool` in one field; 4688 splits it, the way the captured 4688 in
   `2026-08-potato-sysmon1-user-semantics.md` splits `MSEDGEWIN10$` / `WORKGROUP`. So expect
   `SubjectUserName: DefaultAppPool` with `SubjectDomainName: IIS APPPOOL`.
   `potato_seimpersonate_4688.yml` selects `SubjectUserName|contains: 'APPPOOL'`, so on the default
   pool it survives only on the case-insensitive `AppPool` substring of the pool *name*, and on a
   pool named anything else there is no such substring in that field at all — the identity is in
   `SubjectDomainName`, which the rule does not read. Record both fields verbatim, for the escalated
   process and for the foothold.
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
from an app-pool identity rather than only from `NETWORK SERVICE`/`LOCAL SERVICE`.

You also need a way to execute **as** each identity, which is the part it is easy to discover you
lack once the tools are already staged:

- **App-pool identity (rows A, D, E).** A webshell in the default site, or
  `psexec -i -u 'IIS APPPOOL\DefaultAppPool'`. Row E runs from the same shell as row A, so stand
  this up once.
- **`NETWORK SERVICE` / `LOCAL SERVICE` (row B).** `psexec -u 'NT AUTHORITY\Network Service'`, or a
  service created for the purpose. Both hold `SeImpersonate`, which is what PrintSpoofer needs.
- **The analysis box** needs `chainsaw` and `python3` on `PATH`. `evtx-to-fixture.sh` hard-fails
  without either, by design — a normalizer that skipped silently would emit an empty fixture.

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

Six rows, not three. Rows A and B settle the three open items, from two service identities. C, D
and E exist so the run yields first-party *pairs* rather than lone true positives — C is the potato
pair's true negative, and D and E are the true positive and true negative of
`token_theft_parent_child_mismatch_sysmon_1.yml` — which is the difference between promoting one
fixture and promoting a pair. F runs only on the optional second target and is the one row that
settles nothing if you skipped that box.

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

Then run the shipped rules against the capture with the same engine the gate uses: zircolite
v3.7.6 and its own pinned requirements (`git clone --branch v3.7.6`, then
`pip install -r requirements.txt`), which is what `sigma-validation.yml` does. That workflow pins
zircolite but not pySigma — `pysigma==1.5.0` is the *compile* gate's pin in `sigma.yml`, and the
cloud evaluator pins 1.4.0 — so record the pySigma version the install resolved to.

Assign the paths, do not prefix them onto the command. In `VAR=x cmd "$VAR"` the shell expands
`"$VAR"` *before* applying the assignment, so the prefix form silently runs `python` with no script
at all, and the assignment does not survive to the next command either:

```bash
# From the repo root, with the two .jsonl captures alongside it.
PYTHON=python3
ZIRCOLITE=/path/to/Zircolite/zircolite.py
ZDIR="$(dirname "$ZIRCOLITE")"

# zircolite drops a db and a log in its cwd, so give each run its own directory.
mkdir -p replay/sysmon replay/security

(cd replay/sysmon && "$PYTHON" "$ZIRCOLITE" -j -e ../../sysmon-run.jsonl \
  -r ../../detections/sigma/privilege_escalation/potato_seimpersonate_sysmon_1.yml \
  --pipeline sysmon -c "$ZDIR/config/config.yaml" -o fired.json)

(cd replay/security && "$PYTHON" "$ZIRCOLITE" -j -e ../../security-run.jsonl \
  -r ../../detections/sigma/privilege_escalation/potato_seimpersonate_4688.yml \
  --pipeline windows-audit -c "$ZDIR/config/config.yaml" -o fired-4688.json)
```

Repeat for `token_theft_parent_child_mismatch_sysmon_1.yml` (`--pipeline sysmon`) and
`token_theft_process_target_subject_4688.yml` (`--pipeline windows-audit`).

### Run the real gate before you release the host

The replays above answer "fired / silent" and nothing else. They do not run `check_near_miss`, which
is the whole reason the constraint above exists — a TN that goes silent for the wrong reason passes
every hand-run in this section. Replace the fixtures, then:

```bash
ZIRCOLITE="$ZIRCOLITE" bash docker/validation/run-sigma-validation.sh
docker/validation/check-rule-coverage.sh
docker/validation/check-fixture-provenance.sh
```

The manifest rows this run touches are `potato-seimpersonate-sysmon-1`,
`token-theft-parent-child-sysmon-1`, `potato-seimpersonate-4688` and
`token-theft-target-subject-4688`. Name them, never number them: an earlier draft of this runbook
cited line numbers, and by the time you are reading it they pointed at other detections' rows.
A failure here while the host is still up is a re-capture. The same failure after teardown is a
re-build.

## Reading it

**The rule firing is not the measurement.** Run row A from an app pool and the pair fires twice,
and only one of the two matches is the escalation. The foothold — `w3wp.exe` spawning `cmd.exe`
under the app-pool identity — satisfies `potato_seimpersonate_sysmon_1.yml` by itself, with no token
theft in the event at all, and its 4688 satisfies `potato_seimpersonate_4688.yml` for the same
reason whatever the answers to items 2 and 3 turn out to be. That is not hypothetical: it is what
the shipped rule was silently delivering before #239, recorded in
`2026-08-potato-sysmon1-user-semantics.md` as `FIRED matches=1` on `LM_typical_IIS_webshell`,
`w3wp.exe -> cmd.exe`. So identify the escalated process first — from the wall-clock notes and the
tool's own `ProcessGuid` / `NewProcessId` — and answer every question below against **that** record.
`matches=2` is not an answer to any of them, and `fired.json` has to be read record by record.

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
Sysmon saying it could not resolve the parent rather than saying anything about identity. It is not
rare among the records that carry the field at all: of the 1491 Sysmon-1 records swept in the #239
sweep, exactly four carry `ParentUser`, and two of those four are `-`. (The 401 figure in
`2026-08-token-mismatch-sysmon-1.md` is a different measurement — records whose parent's own Sysmon
1 is absent from the corpus, so that run's GUID-linked derivation could not resolve one. It is the
population a Sysmon 13+ host would most likely render as `-`, not a count of Sysmon emitting it.)
That placeholder is exactly why the negated-filter rule shape was rejected in
`2026-08-token-mismatch-sysmon-1.md`, where `-` does not contain `SYSTEM` and so passes a negated
filter.
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

Find each ledger row by grepping its fixture path. The path is the row's only stable key; rows are
inserted above these regularly, so any line number written down here is wrong by the time it is read.

```bash
grep -n 'sigma-fixtures/<name>.jsonl' docker/validation/fixture-provenance.tsv
```

| Fixture | Tier today | Reaches `captured` when replaced with |
| --- | --- | --- |
| `potato_sysmon1_tp.jsonl` | `vendor-documented` | row A (or B) — the escalated process's Sysmon 1 |
| `potato_sysmon1_tn.jsonl` | `vendor-documented` | row C — the interactive-admin capture, same key set |
| `potato_security_4688.jsonl` | `vendor-documented` | row A's 4688. Today its identity block is *constructed*, and its Target Subject block is deliberately null pending exactly this measurement |
| `token_theft_sysmon1_tp.jsonl` | `vendor-documented` | row D — the non-shell payload. Synthetic today |
| `token_theft_sysmon1_tn.jsonl` | `unverified` | row E. Hand-authored from its TP |
| `token_theft_4688_{tp,tn}.jsonl` | `vendor-documented` | TP: row A's 4688, and only if the fourth expectation held. TN: see below — probably nothing this run can produce |

**The 4688 true negative probably cannot be captured, and that is a result rather than a gap.**
`token_theft_4688_tn.jsonl` is silent today because `filter_same_context` catches it: it carries
`TargetUserSid` **and** `SubjectUserSid` `S-1-5-18`. A captured SYSTEM-creates-SYSTEM 4688 will not
have that shape. Windows populates Target Subject only when creator and target do not share a logon,
so a genuine same-context creation carries `TargetUserSid: S-1-0-0` and `TargetLogonId: 0x0` — and
that event is silent because the **selection** missed, not because the filter caught it.
`check_near_miss` cannot tell the two silences apart: it compares EventID sets and `EventData` key
sets, never values, and both shapes carry the identical event-version-2 key set. Promoting one would
turn a filter-exercising TN into a vacuous one with the gate still green.

So sweep the captured Security log for the only shape that qualifies — both SIDs `S-1-5-18`, which
means `SubjectLogonId` must differ from `TargetLogonId` or the block would not have populated:

```bash
python3 -c 'import sys, json
for l in open(sys.argv[1]):
    d = json.loads(l)["Event"]["EventData"]
    if d.get("TargetUserSid") == "S-1-5-18" and d.get("SubjectUserSid") == "S-1-5-18":
        print(d.get("SubjectLogonId"), d.get("TargetLogonId"), d.get("NewProcessName"))' security-run.jsonl
```

If a record comes back, it is the promotable TN. If none does — the likely outcome — leave
`token_theft_4688_tn.jsonl`'s ledger row where it is and say in the record that the shape was
looked for and not found. The mixed tier is
acceptable here and not on the Sysmon pair, for a reason worth stating: row C's true negative is a
real event this run can reproduce, and this one is a counterfactual the OS is not supposed to emit.

When a row moves, drop the trailing `first-party run still open as dotgibson/dotfiles-Defense#246`
clause from its note and cite the new run record instead. These would be the repo's first
`captured` rows — `check-fixture-provenance.sh` reports 0 today.

### Branches

- **All four predictions hold, and every row you needed actually ran.** Replace the fixtures per
  the table above and move each **replaced** row in `docker/validation/fixture-provenance.tsv` to
  `captured` — those rows and only those. Promotion is per fixture, not per prediction:
  `token_theft_4688_tp.jsonl` moves only if the fourth expectation also held,
  `token_theft_sysmon1_{tp,tn}` only if rows D and E ran, and `token_theft_sysmon1_tn.jsonl` starts
  from `unverified` rather than `vendor-documented`. Close #246 when every row in the table has
  moved; if some moved and some did not, say which in the record and leave #246 open for the rest.
  Nothing about the rules changes on this branch — this is where the derivation behind them turns
  out to have been right.
- **Item 3 fails — `SubjectUserSid` reads `S-1-5-18`.** The expensive branch, and the reason
  question 2 is answered first. On the thread-token reading, `filter_same_context` in
  `token_theft_process_target_subject_4688.yml` deletes that rule's own true positive, and
  `potato_seimpersonate_4688.yml` goes silent for the same reason — its `SubjectUserName` would
  carry whatever the host renders `S-1-5-18` as, never an app pool. Do not expect the literal string
  `SYSTEM` there: the one captured 4688 in the corpus with `SubjectUserSid` `S-1-5-18` renders it
  `MSEDGEWIN10$` / `WORKGROUP`, the machine account. Record the rendering, since it is what any
  replacement selection would have to match. That is a two-rule rework, not a fixture edit. Reopen [#238]
  and [#230] with the measurement attached, and note that
  `token_theft_parent_child_mismatch_sysmon_1.yml` is the rule that survives it: `ParentUser` is
  resolved from the parent *process*'s token and is untouched by the question. Its description
  already makes that claim and would finally have evidence for it.
- **Item 2 fails but item 3 holds.** The 4688 arrives with a subject that is neither the app pool
  nor `S-1-5-18`. Correct `potato_seimpersonate_4688.yml`'s selection to what was measured and
  say in the record which claim the capture overturned — the #239 shape, where the fix is a
  field, not a threshold.
- **`SubjectUserName` reads the bare pool name.** The expected result on the field split above.
  This is *not* item 2 failing — the creator is the service identity, exactly as predicted — it is
  the rule reading the wrong half of it, so it is a rule finding rather than a fixture one: `potato_seimpersonate_4688.yml` matches `DefaultAppPool`
  only by the case-insensitive `AppPool` substring and cannot match a custom-named pool at all.
  Replace the fixture with what was captured — `potato_security_4688.jsonl` today carries the
  Sysmon-style qualified string in `SubjectUserName` while also setting `SubjectDomainName`, a shape
  no captured 4688 has — and open a rule change adding `SubjectDomainName|contains: 'APPPOOL'`, or
  moving the term there, with the measurement attached. Do not hand-edit the fixture back to the
  qualified form to keep the rule green: that is the #149 shape.
- **The fourth expectation fails — `TargetUserSid` reads `S-1-0-0` on a populated Target Subject
  block.** The corpus already produced one 4688 shaped that way, so this is the least surprising
  failure of the four, and it is the whole selection of
  `token_theft_process_target_subject_4688.yml`: on that reading the rule is silent on exactly the
  event it was written for. `potato_security_4688.jsonl` still moves, because its rule never reads
  that field. `token_theft_4688_tp.jsonl` does **not**, and must not be hand-edited into firing —
  it would fail the gate as its own TP, after the host is gone. Record which of the four Target
  fields did populate, because that decides whether the rule can be re-keyed on `TargetUserName` at
  the cost of the localisation-immunity the SID buys it, which its description names as its
  advantage over the Sysmon twin. Reopen [#230] with the measurement attached.
- **`ParentUser` reads `NT AUTHORITY\SYSTEM` on any row.** The seclogon-reparenting outcome the
  corpus ruled out for six tools and row F exists to test on the `CreateProcessWithTokenW` path
  specifically. Both Sysmon rules are inert on that path — including
  `token_theft_parent_child_mismatch_sysmon_1.yml`, which the item-3 branch above nominates as the
  rule that survives everything, so this is the one result that removes the fallback. Record the
  tool and the API, do not promote the Sysmon rows from that row, and reopen [#239].
- **`ParentUser` is a service identity but does not equal the parent's own `User`.** Prediction 1's
  second half, which the corpus could never test. The fixtures still promote, because the rules read
  `ParentUser` alone — but say so plainly in the record, because both Sysmon rules' descriptions and
  the `potato_sysmon1_*` and `token_theft_sysmon1_*` provenance notes all derive `ParentUser` from
  the parent's own captured `User`, and that derivation would then be measured wrong.
- **`ParentUser` reads `-`.** As above: record it, do not promote the Sysmon rows, and treat the
  rule's silence on that path as measured rather than as a bug in the capture.
- **No 4688 at all despite `auditpol`.** This contradicts documented behaviour rather than merely
  being unproven, so re-measure before acting — check the `auditpol /get` output was captured and
  that Row A actually produced a process creation.

### Manifest consequences

The `potato-seimpersonate-4688` row of `docker/validation/sigma-manifest.tsv` carries `-` in the TN
column, and the rule has no `filter_*` block, so `check-rule-coverage.sh` does not require a true
negative. It is still worth adding one, and **row E's 4688** is the one to use: same app-pool
`Subject*` block, `NewProcessName` of `whoami.exe`, so it changes exactly one value against row A's
4688 and `check_near_miss` will accept it. Adding it is three edits rather than one — the fixture,
that manifest row's sixth column, and a new row in `fixture-provenance.tsv` — because the provenance
gate fails on a manifest-referenced fixture with no ledger row, and `check_near_miss` starts applying
to this pair the moment the `-` goes away. `potato-seimpersonate-sysmon-1`,
`token-theft-parent-child-sysmon-1` and `token-theft-target-subject-4688` already name both fixtures
and need no structural change — only the fixtures behind them are replaced.

[#230]: https://github.com/dotgibson/dotfiles-Defense/issues/230
[#238]: https://github.com/dotgibson/dotfiles-Defense/issues/238
[#239]: https://github.com/dotgibson/dotfiles-Defense/issues/239
[#246]: https://github.com/dotgibson/dotfiles-Defense/issues/246
