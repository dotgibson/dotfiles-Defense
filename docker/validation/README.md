# docker/validation — does each detection actually fire?

The Sigma CI (`sigma.yml`) proves the rules *parse and compile*. This proves the
network detections **work**: attack-shaped traffic in → the real shipped detection runs
→ the expected signal comes out. It's the executable form of every `Validate (purple):`
line, minus the manual Kali box.

## How it works

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
`.github/workflows/network-validation.yml`), inside the `zeek/zeek` image. Locally:

```sh
pip install scapy
# needs `zeek` on PATH — install Zeek, or drop a shim that wraps the image:
#   printf '#!/usr/bin/env bash\nexec docker run --rm -i -v "$PWD":/w -w /w zeek/zeek:lts zeek "$@"\n' > ~/bin/zeek && chmod +x ~/bin/zeek
docker/validation/run-validation.sh
```

`ZEEK_CMD` / `PYTHON` override the binaries.

## Adding a detection

1. Write `fixtures/gen_<name>.py` that takes an output path and synthesizes the
   attack-shaped traffic just past the detection's threshold (keep it seeded/deterministic).
2. Add a row to `manifest.tsv` pointing at the generator, the detection script, and the
   `Module::Notice_Type` you expect.

Suricata rows (engine `suricata`, expected = a `sid`/`msg`) are the next addition — the
manifest and runner already leave room for them.

## Scope

This is the **network plane** (PCAP replay — offline, deterministic, hermetic). The host
plane (Sigma vs EVTX via chainsaw/zircolite) and generating fixtures from the real Kali
attacks are later phases — see [`../LAB-VALIDATION-PLAN.md`](../LAB-VALIDATION-PLAN.md).
Detections that can't be synthesized cleanly (TLS handshakes / JA3, Kerberos ASN.1,
multi-megabyte long-haul tunnels) wait for captured fixtures from that phase rather than
shipping a fragile synthetic.
