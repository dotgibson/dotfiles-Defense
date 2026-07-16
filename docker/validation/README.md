# docker/validation — does each detection actually fire?

The Sigma CI (`sigma.yml`) proves the rules *parse and compile*. This proves the
detections **work**: attack telemetry in → the real shipped detection runs → the expected
signal comes out. It's the executable form of every `Validate (purple):` line, minus the
manual Kali box. Two planes:

- **Network** (this doc, below) — PCAP replay through Zeek/Suricata (`run-validation.sh`).
- **Host / Sigma** — a JSON-lines event log through the real Sigma rule with
  [zircolite](https://github.com/wagga40/Zircolite) (`run-sigma-validation.sh`), asserting
  the rule id lands in the detections. Manifest: [`sigma-manifest.tsv`](sigma-manifest.tsv)
  (`name / pipeline / fixture / rule / expected-id`); fixtures are committed JSONL under
  `sigma-fixtures/`. Covers single-selection, filtered, and `value_count`-correlation rules
  across the `windows-audit` and `sysmon` pipelines. Run it:
  `ZIRCOLITE=/path/to/zircolite.py docker/validation/run-sigma-validation.sh` (CI clones a
  pinned zircolite — see `.github/workflows/sigma-validation.yml`). Gated the same way the
  network plane is: a rule that stops firing turns it red.

## How it works (network plane)

`run-validation.sh` reads [`manifest.tsv`](manifest.tsv) — one row per detection:

```
name<TAB>engine<TAB>generator<TAB>detection-script<TAB>expected-signal
```

For each row it:

1. runs the **generator** (`fixtures/gen_*.py`, scapy) to synthesize an attack-shaped
   PCAP — deterministic and seeded, sized just past the detection's threshold;
2. replays it through the **engine** with the **real** detection script
   (`zeek -r fixture.pcap detections/network/zeek/<script>`);
3. asserts the **expected signal** (a Zeek `Notice::Type`) appears in the output.

PASS/FAIL per row; non-zero exit if any fails. Because the generators are seeded, a green
run means the detection fires on exactly the shape it claims — and a regression that
breaks the detection turns the gate red.

## Run it

CI runs this on every `detections/network/**` or `docker/validation/**` change (see
`.github/workflows/network-validation.yml`) — one job per engine, each in that engine's
image (`zeek/zeek`, `jasonish/suricata`). Locally, run one plane at a time:

```sh
pip install scapy
docker/validation/run-validation.sh zeek        # needs `zeek` on PATH
docker/validation/run-validation.sh suricata    # needs `suricata` on PATH
docker/validation/run-validation.sh             # both
# no engine installed? wrap the image in a shim on PATH, e.g.:
#   printf '#!/usr/bin/env bash\nexec docker run --rm -i -v "$PWD":/w -w /w zeek/zeek:lts zeek "$@"\n' > ~/bin/zeek && chmod +x ~/bin/zeek
```

`ZEEK_CMD` / `SURICATA_CMD` / `PYTHON` override the binaries. The preflight only requires
the engine(s) the selected rows actually use.

## Adding a detection

1. Write `fixtures/gen_<name>.py` that takes an output path and synthesizes the
   attack-shaped traffic just past the detection's threshold (keep it seeded/deterministic).
   One fixture can feed both engines — e.g. `gen_icmp_tunnel.py`'s 900-byte echo clears
   Zeek's mean-payload floor *and* Suricata's `dsize:>800`.
2. Add a row to `manifest.tsv`: the generator, the detection script, and the expected
   signal — a Zeek `Module::Notice_Type`, or a Suricata rule `msg` (matched literally).

## Scope — what's covered, what isn't

This is the **network plane** (PCAP replay — offline, deterministic, hermetic). Covered:
Zeek DNS tunnel + DGA, ICMP tunnel, reverse-tunnel/egress; Suricata DNS-tunnel and ICMP
oversized-echo.

**Known gaps — deferred to Phase-3 captured fixtures**, not silently uncovered. These
depend on protocol state a faithful synthetic can't cheaply fake, so a captured PCAP from
the real Kali attack is the honest fixture:

- `zeek/tls-c2.zeek` (self-signed cert) and `zeek/tls-c2-ja3.zeek` (JA3) — need a real TLS
  handshake + X.509 chain for Zeek's SSL analyzer and the ja3 add-on.
- `zeek/kerberoast-rc4.zeek` — needs a real Kerberos TGS-REP (ASN.1, RC4 etype).
- `suricata/coercion.rules` — a byte-correct scapy DCERPC bind (v5 `05 00 0b`, MS-EFSRPC +
  NDR UUIDs) was built and tried, but Suricata 7's app-layer didn't parse the interface
  out of a hand-crafted raw-TCP/135 flow (it read the packets, emitted no alert). The DCERPC
  app-layer wants a real bind/bind-ack exchange over SMB or the epmapper — captured from
  the real coercer, not synthesized. Trivially extendable once one interface validates:
  the other three (MS-RPRN/DFSNM/FSRVP — swap the UUID).

Partial, trivially extendable (same shape as a covered row): the c2.rules
oversized-query-name / echo-reply variants.

The host plane (Sigma vs EVTX via chainsaw/zircolite) is a later phase — see
[`../LAB-VALIDATION-PLAN.md`](../LAB-VALIDATION-PLAN.md).
