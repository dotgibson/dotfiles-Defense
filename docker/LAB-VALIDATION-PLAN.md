# Detection lab — end-to-end validation plan

The lab today is the log store (`detection-lab.compose.yml`: OpenSearch + Dashboards).
This is the plan to make every detection's `Validate (purple):` line **executable** —
attack → telemetry → the shipped detection fires — instead of a manual note.

## The model: three telemetry planes, replay not live

Detections split by where their telemetry comes from; each plane has a cheapest path to a
reproducible "does it fire?" check that does **not** need a live attack range:

| Plane | Detections | Telemetry | Check |
| ----- | ---------- | --------- | ----- |
| **Network** | `dns-c2`, `reverse-tunnel`, `icmp-tunnel`, `tls-c2` (+JA3), `coercion`, `kerberoast` | PCAP | `zeek -r x.pcap <script>` / `suricata -r x.pcap` → assert notice/sid. Offline, deterministic, hermetic. |
| **Host / Sigma** | the 4624/4662/5136/5145/4688/4741… corpus | Windows EVTX / JSON | `chainsaw hunt x.evtx -s detections/sigma/` (or zircolite) → assert the rule matched. No Windows VM. |
| **Cloud / SaaS** | azure/aws/gcp/okta/snowflake/… | audit-log JSON | compile rule → run over a sample-event fixture → assert a hit. |

The unlock is **replay against committed/synthesized fixtures**: deterministic and
CI-gateable, without standing up Windows hosts or a live range. Executing the real
attacks becomes a *fixture-generation* step (Phase 3), not a CI dependency.

## Phases

**Phase 0 — harness + golden path.** ✅ *(this PR)*
`docker/validation/` with `run-validation.sh` + `manifest.tsv`, driving seeded scapy
generators through the real Zeek scripts and asserting the Notice. Two golden paths wired
(`dns-c2` DNS-tunnel, `icmp-tunnel`), gated by `network-validation.yml`.

**Phase 1 — network plane coverage.** *(in progress)*
A generator + manifest row per network detection, and a Suricata `-r` runner alongside
Zeek (engine=`suricata`, expected=`sid`). This is where the engine-side code authored
to-spec but never run — the C2 Zeek scripts, the JA3 `dataset`/feed — finally gets
validated. Cleanly synthesizable now: DNS tunnel/DGA, ICMP tunnel, coercion (DCERPC
binds). Deferred to Phase 3 fixtures: TLS/JA3 (needs a real handshake), Kerberoast (ASN.1),
reverse-tunnel (multi-MB, 30-min flow) — synthesizing these faithfully is more fragile
than capturing them once.

**Phase 2 — host / Sigma plane.**
Add `chainsaw` (or `zircolite`) in a container and run `detections/sigma/` against curated
EVTX/JSON fixtures, same manifest shape. `value_count` correlations need multi-event
fixtures. Gated by `sigma-validation.yml`.

**Phase 3 — fixtures from the real attacks.** *(not CI)*
A documented `regen-fixtures.sh` that runs the paired Kali attacks (the htpx pairs)
against lab targets and captures the PCAP/EVTX, so fixtures are reproducible from source.
Needs a real lab network + targets (and Windows for the host plane), so it stays a
manually-run step, never a gate.

## What is and isn't achievable

- **CI-gateable & deterministic:** Phases 0–2 (replay against committed/synthesized
  fixtures). This is the prize — the corpus becomes continuously self-verifying.
- **Not CI-friendly:** live attack execution (targets, Windows licensing, a range) → the
  Phase 3 manual regen.
- **Cloud plane:** fixture unit tests only (no live SaaS to fire against).

## Decisions taken

- **Synthetic, not committed blobs** — generators (scapy) live in git, PCAPs are built at
  run time. Reviewable diffs, no binary weight. Captured fixtures (Phase 3) are the
  exception, for shapes too fragile to synthesize.
- **CI-gated from Phase 0** — a detection that stops firing turns the gate red, same as a
  Sigma parse error does.
- **Replay over live** — the whole design avoids a standing attack range on the critical
  path; live execution is confined to the opt-in Phase 3 regen.
