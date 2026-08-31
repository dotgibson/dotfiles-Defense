# Run record — the nested `\pipe\srvsvc` / `\pipe\epmapper` create, measured

## The question

[#248] asks for a Sigma rule on the two PipeEvent names `detections/sysmon/sysmonconfig-detection-lab.xml`
collects and nothing reads, and asks for three things to be **re-derived rather than inherited**:
whether the rule takes the create or the connect half, whether one rule or two, and whether the
generic `\<x>\pipe\<y>` structural shape should replace a name-based rule.

Those questions had figures attached — 61 PipeEvent records, 7 matching `srvsvc`, 3 matching
`epmapper` — but **no run record**. The measurement existed only as prose in
`detections/sysmon/sysmonconfig-detection-lab.xml`, `DEFENSE-METHODOLOGY.md` and `CHANGELOG.md`,
written while gathering evidence for [#240]. `labruns/README.md` says a lab run is what breaks the
circle between a rule and the belief that produced it; a rule resting on a number recorded only in
an XML comment is that circle with an extra step. This record is the sweep re-run from scratch so
the rule's arguments cite a measurement rather than a paragraph.

It also **corrects two claims** the repo currently makes. See "What this changes in the prose".

## The source of the telemetry

Not a first-party lab run. Third-party capture: real Sysmon EVTX from real hosts, published in
`sbousseaden/EVTX-ATTACK-SAMPLES`, pinned at commit
`4ceed2f4706daf601c212a8f91c113dd85349a2c` — the same commit every other pipe record in this repo
cites, and today also the repository's `HEAD`.

```bash
git clone --depth 1 https://github.com/sbousseaden/EVTX-ATTACK-SAMPLES
git -C EVTX-ATTACK-SAMPLES rev-parse HEAD   # 4ceed2f4706daf601c212a8f91c113dd85349a2c
```

All **278 EVTX** were swept. Normalised with `docker/validation/evtx-to-fixture.sh`
(`chainsaw 2.16.4` + `python3`), one file at a time — the tool hard-fails a file that yields no
matching event, by design, so a corpus-wide sweep runs per file and skips the misses:

```bash
while IFS= read -r f; do
  out=$(docker/validation/evtx-to-fixture.sh --event-id 17 --event-id 18 "$f" 2>/dev/null) || continue
  [ -n "$out" ] && printf '%s\n' "$out" >> pipeevents.jsonl
done < <(find EVTX-ATTACK-SAMPLES -name '*.evtx' | sort)
```

**61 PipeEvent records** across 16 files — 48 EventID 18 and 13 EventID 17. The 61 reproduces the
figure [#240] recorded, exactly.

## Finding 1 — every nested pipe is a create/connect PAIR, and only the create names the attacker

This is the finding that settles the create-vs-connect question, and it was inherited rather than
measured until now. Every record in the corpus whose `PipeName` carries an **interior** `\pipe\`
segment:

```text
17  CreatePipe   \dd4c18dc-bff6-42ce-b707-62c114b84291\pipe\srvsvc     c:\temp\EfsPotato.exe                          LAPTOP-JU4M3I0E  2021-08-22 19:33:38.843
18  ConnectPipe  \dd4c18dc-bff6-42ce-b707-62c114b84291\pipe\srvsvc     System                                         LAPTOP-JU4M3I0E  2021-08-22 19:33:38.884
17  CreatePipe   \RoguePotato\pipe\epmapper                            c:\Users\IEUser\tools\PrivEsc\RoguePotato.exe  MSEDGEWIN10      2020-05-11 23:21:56.507
18  ConnectPipe  \RoguePotato\pipe\epmapper                            System                                         MSEDGEWIN10      2020-05-11 23:21:56.554
17  CreatePipe   \9023de59-e026-4da5-97dd-913597cd038f\pipe\spoolss    c:\Users\IEUser\Tools\PrivEsc\PrintSpoofer.exe  MSEDGEWIN10      2020-05-02 18:01:54.857
18  ConnectPipe  \9023de59-e026-4da5-97dd-913597cd038f\pipe\spoolss    System                                         MSEDGEWIN10      2020-05-02 18:01:54.863
```

Three pipes, **six records**, three tools, zero legitimate. Each pipe produces exactly one 17 and
one 18, 41 ms / 47 ms / 6 ms apart. The 17 carries the tool's own `Image`. The 18 is the coerced
service binding back and arrives `Image=System`, `ProcessId=4` — it names the victim, not the
attacker.

So the create half is not merely the conventional choice inherited from [#225]: it is the only half
of this attack that carries attribution, and taking both halves would double every alert while
adding no detection. The arithmetic, run over the 61:

| Selection | Matches | What the extra matches are |
| --- | ---: | --- |
| `EventType=CreatePipe` + `\pipe\srvsvc`/`\pipe\epmapper` | **2** | the two attacks, under their own `Image` |
| same names, **no** `EventType` pin | 4 | the same two attacks plus their connect halves, `Image=System` |

The pin buys deduplication and attribution. It buys no coverage, and it costs no coverage.

## Finding 2 — the generic `\<x>\pipe\<y>` shape adds nothing over the shipped corpus

[#248]'s question 3 cites the structural shape as 3/3 with zero false positives against 1/1 for a
name-based rule. Measured, the structural shape is **6 of 61 records over 3 distinct pipes** (the
issue's "3 of 61 records" counts pipes, not records), and on the create half it is 3 of 61. But the
third of those three is PrintSpoofer's `\9023de59-…\pipe\spoolss`, and
`detections/sigma/privilege_escalation/spoolss_pipe_impersonation_sysmon_17.yml` **already fires on
it** — its `PipeName|contains: 'spoolss'` matches the nested form, and `PrintSpoofer.exe` is not
`spoolsv.exe`, so `filter_legit` does not remove it. Verified by replaying its condition over the
sweep: exactly one match, that record.

| Selection | Matches on the 61 | New coverage vs. the shipped corpus |
| --- | ---: | --- |
| `EventType=CreatePipe` + `PipeName\|contains: '\pipe\'` | 3 | **0** |
| `EventType=CreatePipe` + the two names | 2 | 2 |

So over this corpus the generic form's marginal coverage is **zero**: every record it would add is
already held by an existing rule. That is a stronger objection than the ingestion argument [#248]
leads with, and it is measured rather than argued. The ingestion argument still stands on its own —
the generic form needs unfiltered PipeEvent collection, which the shipped `onmatch="include"` list
is not, so on a host running our baseline it would select nothing the two-name form does not — and
so does the base-rate objection: 3/3 is drawn from a corpus that is overwhelmingly attack telemetry,
and says nothing about how often a working desktop creates a nested pipe.

It also still misses GodPotato, which hooks `combase`'s RPC dispatch table and can name its pipe
anything.

## Finding 3 — no legitimate CREATE of either name exists in the corpus, bare or nested

All seven records matching bare `srvsvc` and all three matching bare `epmapper`:

```text
18  <NO EventType>  \srvsvc    C:\Windows\system32\wbem\wmiprvse.exe  MSEDGEWIN10   Credential Access/sysmon17_18_kekeo_tsssp_default_np.evtx
18  ConnectPipe     \srvsvc    System                                 MSEDGEWIN10   Discovery/Discovery_Remote_System_NamedPipes_Sysmon_18.evtx
18  <NO EventType>  \srvsvc    System                                 DC1.insecurebank.local  Discovery/discovery_enum_shares_target_sysmon_3_18.evtx
18  <NO EventType>  \srvsvc    System                                 DC1.insecurebank.local  Discovery/discovery_enum_shares_target_sysmon_3_18.evtx
18  <NO EventType>  \srvsvc    System                                 DC1.insecurebank.local  Discovery/discovery_sysmon_18_Invoke_UserHunter_NetSessionEnum_DC-srvsvc.evtx
17  CreatePipe      \dd4c18dc-…\pipe\srvsvc   c:\temp\EfsPotato.exe   LAPTOP-JU4M3I0E
18  ConnectPipe     \dd4c18dc-…\pipe\srvsvc   System                  LAPTOP-JU4M3I0E

18  ConnectPipe     \epmapper  System                                 MSEDGEWIN10   Discovery/Discovery_Remote_System_NamedPipes_Sysmon_18.evtx
17  CreatePipe      \RoguePotato\pipe\epmapper  c:\Users\IEUser\tools\PrivEsc\RoguePotato.exe  MSEDGEWIN10
18  ConnectPipe     \RoguePotato\pipe\epmapper  System                                         MSEDGEWIN10
```

Two things follow, and one of them is a limit rather than a result.

**The narrowing works, and it is what does the job an `Image` filter was expected to do.** The five
bare `\srvsvc` and the one bare `\epmapper` records are all EventID 18 binds; none contains the
substring `\pipe\srvsvc` or `\pipe\epmapper`, so none is in selection. And the legitimate `\epmapper`
record is `Image=System`, **not** `svchost.exe` — confirming that the `filter_legit:
Image|endswith: '\svchost.exe'` [#240] proposed would have excluded nothing while reading as
though it did.

**No legitimate create was observed at all** — every one of the six benign records is a connect.
That is consistent with the Server service and `rpcss` creating their endpoints once per boot, but
it is absence of evidence: none of these captures spans a boot. The claim that a legitimate create
would carry the *bare* name and therefore fall outside this selection is **inference, not
measurement**, and it is the item [#235] carries.

## Finding 4 — the `EventType` cliff, quantified

Two `EventData` key sets appear across the 61:

```text
53  RuleName, EventType, UtcTime, ProcessGuid, ProcessId, PipeName, Image
 8  RuleName,            UtcTime, ProcessGuid, ProcessId, PipeName, Image
```

Eight records — on `MSEDGEWIN10` (a 2019-era kekeo capture), `DC1.insecurebank.local` and `IEWIN7` —
carry **no `EventType` field at all**, which is the coverage cliff
`2026-08-sysmon18-remote-pipe.md` first reported and which every `EventType`-pinned rule in this
repo inherits. Three of those eight are bare `\srvsvc` binds.

All six nested records **do** carry `EventType`, so the cliff does not touch the attack telemetry
here — but it is a real property of old agents, not a hypothetical, and the rule states it.

There is no `User` field on PipeEvent, `ProcessId` is a JSON number, and `ProcessGuid` carries no
braces — unchanged from `2026-08-sysmon18-remote-pipe.md`.

Note one thing the key set does not show: `RuleName` is **not** always empty. The RoguePotato and
PrintSpoofer records carry `Rogue Epmapper np detected - possible RoguePotato privesc` and
`Possible PrivEsc attempt - Rogue Spoolss Named Pipe` — the *capturing host's* own Sysmon rule
names, from a config that already watched for these pipes in 2020. That is provenance, not
contamination, and the fixtures keep it verbatim.

## What fired

Two different things, and the distinction matters.

**The arithmetic above** was computed by replaying each selection over the normalised sweep as its
literal Sigma semantics (`EventType` equality, `PipeName` substring). That settles the counts; it is
not the engine.

**The shipped rule** was then run under the engine, on the fixtures cut from this sweep:

```text
zircolite v3.7.6 (wagga40/Zircolite, the version .github/workflows/sigma-validation.yml pins)
pipeline: sysmon

PASS srvsvc-epmapper-pipe-impersonation-17
  TP fired 563f2958-0d44-4138-884f-14d338d37cd9, TN silent
  (sysmon · srvsvc_epmapper_pipe_impersonation_sysmon_17.yml)

full suite: 84/84 passed (42 with a true-negative)
```

So the rule fires on the **real captured** EfsPotato and RoguePotato create records — not on a
hand-authored approximation of them — and stays silent when the only thing changed is the pipe name
losing its interior `\pipe\` segment. That is the narrowing proven to discriminate, which is the
one claim a true positive alone could never support.

## What this changes in the prose

Two claims this repo currently makes are wrong, and are corrected alongside this record:

1. **"five of those are ordinary share enumeration (NetShareEnum, NetSessionEnum) arriving as bare
   `\srvsvc` from `Image=System`"** — of the five bare `\srvsvc` records, **four** are `Image=System`
   and the fifth is `wmiprvse.exe`, and they arise from three different captures (share enumeration,
   session enumeration, remote named-pipe discovery) plus a kekeo capture, not from share
   enumeration alone. The load-bearing half of the claim — that none of them takes the nested form —
   holds exactly.
2. **"3 of 61 PipeEvent records"** for the nested structural shape counts *pipes*; it is **6 of 61
   records over 3 pipes**, or 3 records on the create half.

## What this run does NOT settle

- **Volume on a live host**, in either direction, for either name. This corpus is attack telemetry
  with incidental benign records; 61 PipeEvent records are not a baseline. No legitimate create of
  either name was observed and no capture spans a boot, so the rule's quietness rests on inference.
  This is the open item, and it is carried by [#235] —
  `docker/validation/labruns/runbook-sysmon18-remote-pipe.md` is how to collect it.
- **That the rule fires on OUR telemetry.** It fires on these captures under the engine, which is
  a real result and a stronger one than most rules here can show — but a rule firing on a 2021
  third-party record is not the same claim as a rule firing on a potato run against our config.
- **Anything about our shipped config.** These are 2019–2021 Sysmon builds on third-party hosts,
  not `detections/sysmon/sysmonconfig-detection-lab.xml` at `schemaversion="4.90"`. The fixtures
  this record supports are therefore `vendor-documented`, not `captured`;
  `labruns/README.md` reserves `captured` for first-party capture.
- **GodPotato.** It appears nowhere in this corpus, and by construction it would not appear in this
  measurement even if it did.

[#225]: https://github.com/dotgibson/dotfiles-Defense/issues/225
[#235]: https://github.com/dotgibson/dotfiles-Defense/issues/235
[#240]: https://github.com/dotgibson/dotfiles-Defense/issues/240
[#248]: https://github.com/dotgibson/dotfiles-Defense/issues/248
