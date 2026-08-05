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
| Recon / Discovery        | Zeek, 4688/4769         | network, sigma        | recon / Kerberoast folds    |
| Credential Access        | Sysmon 10, 4625/4771    | sysmon, sigma         | Responder / cracking folds  |
| Lateral Movement         | 4624 type 3, Zeek SMB   | sigma, network        | lateral-movement fold       |
| Priv Esc / Persistence   | Sysmon 1/13, 4720/7045  | sysmon, sigma         | LOLBAS / persistence folds  |
| Coercion / Relay / AD CS | 5145 pipes, 4886 SAN    | siem                  | coercion → relay → DC fold  |
| Exfil / C2               | Suricata, Zeek conn/dns | network               | reverse-shell / pivot folds |
| Impact                   | 4688 destructive + service-stop cmds, 4663 file writes | sigma | ransomware chain (teardown → recovery → payload) |

The right-hand column is the point: every row has a Kali fold that proves the
detection works.

One row is knowingly incomplete. **Impact** reads `sigma` because that is where its
detections live *today* — the T1489 teardown, T1490 recovery inhibition, and
T1485/T1486 payload rules under `detections/sigma/impact/`. The tactic's other
documented technique, T1496.001 Compute Hijacking, belongs on the **wire** rather than
the host (a Stratum connection to a mining pool), so it is the one Impact detection the
`sigma` column will never cover. It is not written yet — tracked as a coverage gap in
`detections/README.md` and in the issue tracker. Add `network` to this row when it
lands, not before: the column says where detections *are*, not where they are planned.

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
