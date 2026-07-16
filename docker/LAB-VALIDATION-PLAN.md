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

**Phase 1 — network plane coverage.** *(mostly done)*
A generator + manifest row per network detection, across both engines, with
`run-validation.sh <engine>` running one plane per CI job/image. Validated: Zeek
DNS-tunnel, DGA, ICMP-tunnel, reverse-tunnel/egress; Suricata DNS-tunnel and ICMP-oversized.
This closed the "authored to-spec, never run" gap for the C2 network detections — and
immediately caught a real bug (dns-c2's DGA path keyed on the wrong Zeek event, so it never
fired on NXDOMAIN). reverse-tunnel turned out synthesizable after all (compact 8 KB segments
over a 31-min span). Remaining, deferred to Phase-3 captured fixtures: TLS self-signed / JA3
(real handshake + X.509), Kerberoast (ASN.1 TGS-REP), and coercion — a byte-correct DCERPC
bind was built, but Suricata's app-layer wouldn't parse the interface out of a hand-crafted
raw-TCP flow (it wants a real bind/bind-ack over SMB/epmapper). All three need too much
protocol state to fake faithfully; capture them from the real Kali attack instead.

**Phase 2 — host / Sigma plane.** *(started)*
`run-sigma-validation.sh` runs the real Sigma rule against a committed JSON-lines event
fixture with **zircolite** (native Sigma via the pysigma `windows-audit` / `sysmon`
pipelines), asserting the rule id lands in the detections — gated by `sigma-validation.yml`
(pinned zircolite). The Windows-security + Sysmon corpus is now covered — 23 rules across every shape
(single-selection, filtered, `value_count` correlation) on the `windows-audit` and `sysmon`
pipelines. That sweep already earned its keep: it surfaced that
`potato_seimpersonate_4688` doesn't fire through pysigma at all — its dual-channel
`User`/`SubjectUserName` selection nulls under either single pipeline (see the finding in
[`validation/README.md`](validation/README.md)). Cloud/SaaS splits in two by whether
zircolite can see the field names. 21 flat-field rules (AWS, Entra, GitHub, Google Workspace,
Jenkins, Okta, npm, PyPI-collaborator, Slack app/share) run on zircolite via `pipeline=none`.
The other 26 (GCP, Cloudflare, GitLab, Kubernetes, Harbor, Snowflake, Terraform, Vault, and a
few others) match on field names zircolite's EVTX flattener can't preserve — dotted paths
*and* underscored keys (verified with `--keepflat`: `gcp.audit.method_name` → `methodname`,
`resource_type` → `resourcetype`) — so they run on a dedicated **nested-field cloud plane**
(`run-cloud-validation.sh`): `sigma_eval.py` matches the real rule against natural cloud-event
JSON by walking pysigma's own parsed condition tree, and each rule is checked both ways — its
true-positive fires, a benign true-negative near-miss stays silent. Host-plane total: 70 rules
(23 Windows/Sysmon + 21 zircolite cloud + 26 evaluator cloud). Both Sigma engines run in the
authoring environment, so every rule+fixture is verified locally before CI.

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
