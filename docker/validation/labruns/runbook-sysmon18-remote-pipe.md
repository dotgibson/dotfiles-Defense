# Runbook — first-party confirmation of the Sysmon-18 remote-pipe premise

What is left of [#235] after `2026-08-sysmon18-remote-pipe.md` settled the mechanism from a
third-party capture, plus the volume question [#248] could not close when it wrote the
`\pipe\srvsvc` / `\pipe\epmapper` rule. Four things still need a real host, and only one of
them needs a domain.

Assumes **no existing lab**. Nothing in `docker/` builds a Windows host — `detection-lab.compose.yml`
is OpenSearch + Dashboards, a log store with no ingestion path — so the Windows side is yours to
stand up.

## What is still open, and why each needs a host

1. **First-party schema confirmation.** The capture that settled the mechanism is from Sysmon
   builds of 2019–2020 on someone else's hosts. Our shipped
   `detections/sysmon/sysmonconfig-detection-lab.xml` is `schemaversion="4.90"` (Sysmon 15.x).
   Confirming the field set on *our* config is what moves four provenance rows from
   `vendor-documented` to `captured`.
2. **`\svcctl` and `\efsrpc` directly.** `\atsvc` was observed; the other two are inference from
   the shared NPFS path. Cheap to close once a host exists.
3. **The `\lsarpc` volume count.** #233 declined an lsarpc rule on the argument that coercion and
   routine domain binds are byte-identical on this plane, and scoped the atsvc/svcctl rule as a
   triage surface with no filterable field. Both arguments are sound on the schema and
   unquantified on volume. This is the only item needing a *domain-joined* host and a working
   day of observation.
4. **The nested-pipe create volume, for `\pipe\srvsvc` and `\pipe\epmapper`.** Carried here
   from [#248], which shipped `srvsvc_epmapper_pipe_impersonation_sysmon_17` on a corpus
   measurement and could not close this half.
   `2026-08-srvsvc-epmapper-pipe-creation.md` found no legitimate **create** of either name
   anywhere in the pinned corpus — bare or nested — which is consistent with once-per-boot
   creation by the Server service and `rpcss`, but none of those captures spans a boot, so it is
   absence of evidence. The rule's whole quietness argument is that legitimate creates carry the
   **bare** name and so fall outside a selection keyed on the interior `\pipe\`. That is
   inference until a host is watched across a boot. Needs one reboot and a working day; does
   **not** need a domain.

### What this run predicts, for item 4

Written before the host exists, so the record cannot be composed to fit the log — the same
discipline `2026-08-sysmon18-remote-pipe.md` reports against.

- **Zero** Sysmon 17s matching `\pipe\srvsvc` or `\pipe\epmapper` across the whole
  observation window, reboot included.
- **Non-zero** creates of the **bare** `\srvsvc` and `\epmapper` at boot, attributed to the
  Server service and `rpcss`. This is the prediction that matters: it confirms the rule is quiet
  because the narrowing works, not because the pipes are never created. A window with no bare
  create either means the window missed the boot, and settles nothing.
- The bare creates carry a **service** `Image`, not `System` — `System` is the remote-bind
  attribution seen on connects, and a local create should name its creator.

## Standing it up

One Windows target, plus an attacker box with `dotfiles-Offense`. A domain controller only for
item 3.

```powershell
# On the target, from an elevated prompt. The include list matters: it scopes the PipeEvent
# feed to seven pipe names before Sigma ever sees anything.
sysmon.exe -accepteula -i sysmonconfig-detection-lab.xml
sysmon.exe -c            # confirm the config took, and record the reported schema version
```

Record the Sysmon version and schema version now — the run record needs both, and the whole
point of item 1 is that they differ from the third-party capture.

## Firing it

From `dotfiles-Offense`. Each row is one attack and the pipe it should light up.

| Tool | Fold / htpx pair | Expected pipe |
| --- | --- | --- |
| `impacket-smbexec`, `impacket-psexec` | Lateral movement & remote execution · `pth-lateral-nxc` | `\svcctl` |
| `impacket-atexec` | same fold | `\atsvc` |
| PetitPotam with the EFSR pipe selected | Poisoning & relay · `coerce-petitpotam` | `\efsrpc` |
| PetitPotam default, or DFSCoerce | same | `\lsarpc` |
| EfsPotato | Windows privilege escalation · `potato-seimpersonate` | `\<guid>\pipe\srvsvc` (17) |
| RoguePotato | same fold | `\RoguePotato\pipe\epmapper` (17) |

The last two rows are item 4's *positive* control and are cheap to run on the same host — they
prove the rule fires on our config, which the corpus cannot. They need `SeImpersonate`, so run
them from a service identity; `runbook-potato-seimpersonate.md` stands that up. RoguePotato also
needs a listener on 135 to resolve the OXID. Item 4's real content is the *quiet* window either
side of them.

Run each one at a time and note the wall-clock, so the events can be attributed with confidence
rather than guessed at from a mixed log.

## Capturing

```powershell
wevtutil epl Microsoft-Windows-Sysmon/Operational C:\sysmon-run.evtx
```

Pull it to the analysis box, then normalise it with the tool that already exists:

```bash
docker/validation/evtx-to-fixture.sh --event-id 17 --event-id 18 sysmon-run.evtx > run.jsonl
```

For each attack record: **does an 18 arrive**, and the exact `Image`, `ProcessId`, `PipeName`
spelling, the full `EventData` key set, and whether `EventType` is present.

Then run the shipped rules against the capture — the same engine the gate uses:

```bash
PYTHON=... ZIRCOLITE=.../zircolite.py \
  python "$ZIRCOLITE" -j -e run.jsonl \
  -r detections/sigma/lateral_movement/svcctl_atsvc_remote_pipe_sysmon_18.yml \
  --pipeline sysmon -c "$ZDIR/config/config.yaml" -o fired.json
```

## The volume count (needs a domain-joined host)

Leave the config running for a working day on a domain-joined machine that sees ordinary
business, then:

```bash
docker/validation/evtx-to-fixture.sh --event-id 18 workday.evtx \
  | python3 -c 'import sys,json,collections
c=collections.Counter(json.loads(l)["Event"]["EventData"].get("PipeName") for l in sys.stdin)
[print(f"{v:8d}  {k}") for k,v in c.most_common()]'
```

What the numbers decide:

- **`\lsarpc` low** → #233's decline is reopenable; an lsarpc rule on this plane might be
  affordable after all.
- **`\lsarpc` high** → the decline is confirmed with a number behind it, and the sysmon config
  comment's "hunt and pivot material, not a rule" stands on evidence rather than reasoning.
- **`\svcctl`/`\atsvc` high** → the atsvc/svcctl rule's "triage surface, scope it by asset"
  framing needs to become a deployment warning with a figure attached.
- **Any nested `\pipe\srvsvc` or `\pipe\epmapper` create that is not one of the two potato
  rows** → `srvsvc_epmapper_pipe_impersonation_sysmon_17`'s no-`filter_*` decision is wrong and
  needs an `Image` allowlist. That is a filter conversation, not a mute: record the creator and
  its publisher before changing anything.
- **Bare creates observed, nested creates zero** → the rule's central claim is measured rather
  than inferred, and its second `falsepositives` entry can be rewritten to say so.

## Filing the result

Add a run record to this directory following `README.md`. Then:

- **If the field set matches at schema 4.90** — move the four Sysmon-18 rows (and the two
  spoolss-17 rows) in `docker/validation/fixture-provenance.tsv` from `vendor-documented` to
  `captured`, citing the run. These would be the repo's first `captured` rows. The two
  `srvsvc_epmapper_pipe_17_*` rows move only if the EfsPotato/RoguePotato rows were actually
  fired here — their TP is a transcribed third-party record, so a schema match alone does not
  promote it, and promoting the TP without re-deriving the TN would strand the pair at mixed
  tiers, the trap `runbook-potato-seimpersonate.md` records for row C.
- **If it differs** — correct the fixtures to what was measured and say in the note which claim
  the capture overturned.
- **If no 18 arrives for the remote path on our config** — that contradicts the third-party
  capture rather than merely being unproven, so re-measure before acting. If it holds, #235's
  outcome 3 applies: retire both rules, restore the "collected and unread" note in the Sysmon
  config comment, and reopen #229 with the measurement attached.

[#235]: https://github.com/dotgibson/dotfiles-Defense/issues/235
[#248]: https://github.com/dotgibson/dotfiles-Defense/issues/248
