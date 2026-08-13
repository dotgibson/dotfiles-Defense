# Defense Methodology — the detection map behind the tool layer

The "why" for `defense/defense.zsh`, `detections/`, and `docker/`: how the blue
tooling lines up against MITRE ATT&CK from the defender's seat. Mirror of Kali's
`OFFENSIVE-METHODOLOGY.md` — same ATT&CK through-line, opposite chair.

> The validation half lives across the fence: Kali's `PURPLE-TEAM.md` pairs each
> attack with the detection it trips. Detection engineering here + attack-paired
> detections there = the full purple loop.

## The philosophy

- **Detect the invariant, not the IOC.** Climb the Pyramid of Pain — spend
  detection budget on behaviors the technique cannot avoid (Kerberoast RC4
  downgrade, DCSync replication right, relay host-mismatch), not brittle IOCs.
- **A detection isn't real until it's fired on purpose.** Write the rule, make
  the attack happen (Atomic Red Team, Caldera, or your Kali box), watch it
  trigger. Untested detections are hypotheses.
- **No data source, no detection.** Coverage is an ingestion problem first. Map
  what you collect to what you want to catch; the gaps are the roadmap.
- **Tune for signal.** A noisy rule gets muted, and a muted rule is a blind spot.
- **Evidence is handled, not hoarded.** Case data lives outside the repo, with a
  timeline and provenance.

## ATT&CK tactic → data source → detection

| ATT&CK tactic            | Primary data sources    | Where detections live | Validate with (Kali)        |
| ------------------------ | ----------------------- | --------------------- | --------------------------- |
| Recon / Discovery        | Zeek, 4688/4769, 4798/4799, 5145 | network, sigma | recon / Kerberoast folds  |
| Credential Access        | Sysmon 10, 4625/4771    | sysmon, sigma         | Responder / cracking folds  |
| Lateral Movement         | 4624 type 3, Zeek SMB   | sigma, network        | lateral-movement fold       |
| Priv Esc / Persistence   | Sysmon 1/13, 4720/7045  | sysmon, sigma         | LOLBAS / persistence folds  |
| Coercion / Relay / AD CS | 5145 pipes, 4886 SAN    | siem                  | coercion → relay → DC fold  |
| Collection               | 4663 file reads, 4688 archive cmds | sigma      | collection / exfil fold     |
| Exfil / C2               | Suricata, Zeek conn/dns/ssl | network           | reverse-shell / pivot folds |
| Impact                   | 4688 destructive + service-stop cmds, 4663 file writes, Zeek conn | sigma, network | ransomware chain (teardown → recovery → payload); cryptomining pair |

The right-hand column is the point: every row has a Kali fold that proves the
detection works.

**Collection** is the newest row and the weakest one, which is worth knowing before you
lean on it. Its detections — the T1005 read sweep and the T1560.001 archive step under
`detections/sigma/collection/` — key on *volume and destination* rather than on an
operation nothing benign performs, because reading and compressing files is ordinary
work. That makes them tuning-dependent in a way the AD rows are not: both ship a
`DEPLOY-REQUIRED` suppression list, and both are worth much less until it is filled. The
row earns its place because collection is the step between access and exfiltration and
leaving it blank hid a real sequence, not because these rules are as sharp as the
Kerberos ones.

**Impact is the one row that spans both layers**, and it is worth understanding why
rather than reading `sigma, network` as a formatting quirk. Most of the tactic is host
work — the T1489 teardown, T1490 recovery inhibition, and T1485/T1486 payload rules under
`detections/sigma/impact/`. But T1496.001 Compute Hijacking has no host invariant this
repo can reach: the giveaway is a conversation with a mining pool, and the corroborating
tell the Kali companion asks for — a process pegged near 100% CPU — needs resource
telemetry no Sysmon config emits at any level. So it lives on the wire, in
`detections/network/zeek/cryptomine-pool.zeek`, and the `network` in that column is that
one detection.

A consequence to hold on to: **T1496.001 is covered but will never appear in
`detections/navigator/COVERAGE.md`.** That roll-up is generated from the Sigma tree alone, so a
network-only detection reads as "0" there — the same documented caveat that already
applies to the whole Command-and-Control tactic and to the `detections/siem/` absence detections.
Do not "fix" the coverage report to compensate; the report is Sigma coverage, not total
coverage, and that is stated where it is generated.

That is also why T1496.001 stays in the marker below even though the detection now
exists. The marker means *"the Sigma corpus does not cover this"*, which is still true
and will stay true — `check-methodology.sh` computes coverage from `detections/sigma/`
only. Removing the id would fail the build, not celebrate the win.

**T1071.001 Web Protocols is the second entry of that kind**, added with
`detections/network/zeek/http-c2.zeek`. The rest of the C2 corner was already on the
wire — DNS (T1071.004), ICMP (T1095), tunnels (T1572), the TLS fingerprint (T1573.002) —
but a plain HTTPS implant riding 443 to a redirector tripped none of them. The invariant
is statistical rather than structural: jitter randomizes each callback interval but not
the distribution, so a low coefficient of variation over enough samples survives the
jitter, a rotated domain, and TLS. Same caveat as T1496.001 — it will read "0" in
`COVERAGE.md` forever, and that is the report being honest about what it counts.

**Discovery no longer rests on one data source.** Nine of its techniques used to hang on
`detections/sigma/discovery/host_recon_command_burst.yml` alone, so a tuned-out
process-creation policy or one EDR-blind host took most of the tactic with it. Two rules
on independent feeds now sit beside it — `local_group_enum_sweep_4798_4799.yml` (SAM-R
local-group enumeration, the path SharpHound takes in-process without writing a 4688 at
all) and `host_enum_srvsvc_wkssvc_5145.yml` (the srvsvc/wkssvc enumeration pipes, on a
5145 feed the coercion rules already require). Five techniques still depend on that one
file; that is better, not solved.

### Declined coverage (recorded, not planned)

Techniques with a documented attack in the red mirror and a deliberate decision **not**
to author a detection here. Recorded so the weekly `/coverage-gap` routine stops
re-deriving them, each with the condition that would reopen it:

- **T1090.004 Domain Fronting** — the invariant is TLS SNI ≠ the inner HTTP `Host`, which
  is only visible with a TLS-inspecting proxy. Without decryption Zeek cannot see the
  inner Host at all, so a script would be inert on the exact path it appears to cover —
  the same reason the S3 rule refuses a `CopyObject` branch. *Reopen when* a
  TLS-inspecting proxy is part of the lab stack.
- **T1102.002 Web Service C2** — a **host** detection, not wire work: the blue companion
  keys on Sysmon Event ID 3 (NetworkConnect), which
  `detections/sysmon/sysmonconfig-detection-lab.xml` does not enable. Event 3 is the
  loudest event Sysmon emits, and turning it on estate-wide to serve one technique — whose
  detection then reduces to an allowlist of trusted SaaS domains, an IOC-shaped rule this
  methodology argues against — is a poor trade. The corner is not unwatched: `http-c2.zeek`
  catches a beacon *to* a legitimate web service on cadence alone, with no new host
  telemetry. *Reopen when* the Sysmon baseline graduates to a production config that
  carries Event 3 anyway.
- **T1526, T1580, T1069.003 cloud discovery** — declined on the red side's own assessment:
  the Kali entry ships unpaired because the activity is read-only, low-signal, and lands in
  GCP Data Access telemetry that is off by default. *Reopen when* Data Access logging is
  enabled in the lab project.

<!-- methodology-check: known-absent = T1069.003, T1071.001, T1071.004, T1090.004, T1095, T1102.002, T1496.001, T1526, T1572, T1573.002, T1580 -->
<!-- Techniques this document names but the SIGMA corpus does not cover — which is not
     the same as "no detection exists". Two classes live here:
       (a) COVERED, but not by Sigma — the whole network/ plane. T1496.001
           (zeek/cryptomine-pool.zeek), T1071.001 (zeek/http-c2.zeek), T1071.004
           (zeek/dns-c2.zeek), T1095 (zeek/icmp-tunnel.zeek), T1572
           (zeek/reverse-tunnel.zeek), T1573.002 (zeek/tls-c2.zeek). This gate reads
           detections/sigma/ only, so dropping any of them would fail the build.
       (b) DECLINED, reasons and reopen-conditions in "Declined coverage" above —
           T1090.004, T1102.002, T1526, T1580, T1069.003.
     Every other technique id in this file must be tagged by a rule in detections/sigma/.
     Adding an id here is a deliberate act. Remove one only when a SIGMA rule starts
     covering it — and note the gate enforces that in both directions, so the decline
     ledger cannot rot: ship a rule tagged with one of these and CI fails until the prose
     above is updated too. -->

Every other ATT&CK id in this document is checked against the corpus on each change.

## The detection-engineering lifecycle

1. **Hypothesis** — "an attacker doing X leaves Y" (from ATT&CK or a Kali fold).
2. **Data check** — do we collect Y? If not, that's an ingestion ticket.
3. **Author** — write it as code in `detections/` (Sigma is the source of truth).
4. **Validate (purple)** — run the technique from Kali, confirm the rule fires.
5. **Tune** — allowlist known-good, threshold the noise.
6. **Deploy + document** — record data source, ATT&CK ID, and the validation.

## OPSEC / evidence hygiene

- **Case-first.** `mkcase` writes `case.md` (scope + authorization) first.
- **Everything in `~/cases`, never in the repo.**
- **Timeline + provenance** for every artifact (`note` drops timestamped lines).
- **Containers for the heavy stuff** — the lab is ephemeral and reproducible.
