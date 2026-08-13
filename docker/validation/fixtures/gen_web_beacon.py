#!/usr/bin/env python3
"""gen_web_beacon.py — synthesize a periodic HTTPS-beacon PCAP for zeek/http-c2.zeek.

The Web_Beacon notice fires when one src -> dst:web_port pair accumulates
min_intervals (20) inter-arrival gaps, each between min_period (30s) and max_period
(2h), whose coefficient of variation (stdev / mean) is below max_cv (0.35). So we
build 22 short, complete TCP connections from an internal client to an external
:443 — 21 gaps, one more than the floor — spaced with a long sleep and heavy jitter.

Raw bytes on 443 with no real TLS handshake is deliberate and sufficient: http-c2.zeek
clocks connection_established (the TCP handshake), never ssl_established, precisely so
that it can be fixture-gated. See the script's header and the "Known gaps" note in
../README.md for why tls-c2.zeek cannot be tested this way.

Jitter is +/-1200s around a 3600s sleep (33%), mirroring the documented Sliver posture
(--seconds 3600 --jitter 1800) but landing CV well under the ceiling rather than just
past it: a fixture sized *just* past a threshold turns the gate red on a harmless tuning
change instead of on a real regression. Seeded, so the PCAP is byte-identical every run.

The generator computes the mean/stdev/CV it actually produced and REFUSES to write if
they would not trip the detection — a drifted fixture becomes a loud error here rather
than a silently non-firing PCAP in CI.

Usage: gen_web_beacon.py <out.pcap>
"""
import random
import statistics
import sys

from scapy.all import wrpcap, Ether, IP, TCP, Raw  # type: ignore

CLIENT, SERVER = "10.1.1.50", "203.0.113.42"  # internal -> external (TEST-NET-3)
DPORT = 443
CONNS = 22  # 22 connections => 21 gaps, one past the 20-interval floor
SLEEP = 3600.0  # mean callback period, seconds
JITTER = 1200.0  # +/- this much, uniform
SEED = 20260813

# The thresholds in detections/network/zeek/http-c2.zeek this fixture must satisfy.
MIN_INTERVALS = 20
MIN_PERIOD = 30.0
MAX_PERIOD = 7200.0
MAX_CV = 0.35
# Refuse to write unless we land with real headroom under the ceiling.
CV_CEILING = 0.30


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: gen_web_beacon.py <out.pcap>", file=sys.stderr)
        return 2

    rng = random.Random(SEED)
    gaps = [SLEEP + rng.uniform(-JITTER, JITTER) for _ in range(CONNS - 1)]

    mean = statistics.fmean(gaps)
    stdev = statistics.stdev(gaps)
    cv = stdev / mean

    # Self-check: everything the detection asserts, asserted here first.
    if len(gaps) < MIN_INTERVALS:
        print(f"gen_web_beacon: only {len(gaps)} gaps, need {MIN_INTERVALS}", file=sys.stderr)
        return 1
    if min(gaps) <= MIN_PERIOD or max(gaps) >= MAX_PERIOD:
        print(f"gen_web_beacon: gap out of range [{min(gaps):.0f}, {max(gaps):.0f}]s — "
              f"must sit strictly inside ({MIN_PERIOD:.0f}, {MAX_PERIOD:.0f})s", file=sys.stderr)
        return 1
    if cv >= CV_CEILING:
        print(f"gen_web_beacon: cv {cv:.3f} has no headroom under the {MAX_CV} ceiling",
              file=sys.stderr)
        return 1

    pkts = []
    t = 1_000_000_000.0
    req = b"x" * 600   # beacon check-in: small request up...
    resp = b"y" * 200  # ...smaller tasking reply down

    for i in range(CONNS):
        sport = 52000 + i
        cseq, sseq = 1000 + i * 10, 5000 + i * 10

        def c2s(flags, payload=b"", at=0.0, seq=0, ack=0):
            pkt = Ether() / IP(src=CLIENT, dst=SERVER) / TCP(
                sport=sport, dport=DPORT, flags=flags, seq=seq, ack=ack)
            if payload:
                pkt = pkt / Raw(payload)
            pkt.time = at
            return pkt

        def s2c(flags, payload=b"", at=0.0, seq=0, ack=0):
            pkt = Ether() / IP(src=SERVER, dst=CLIENT) / TCP(
                sport=DPORT, dport=sport, flags=flags, seq=seq, ack=ack)
            if payload:
                pkt = pkt / Raw(payload)
            pkt.time = at
            return pkt

        # Handshake — this is what raises connection_established, i.e. the beacon clock.
        pkts.append(c2s("S", at=t, seq=cseq, ack=0))
        pkts.append(s2c("SA", at=t + 0.01, seq=sseq, ack=cseq + 1))
        pkts.append(c2s("A", at=t + 0.02, seq=cseq + 1, ack=sseq + 1))
        # Check-in and tasking reply.
        pkts.append(c2s("PA", req, at=t + 0.03, seq=cseq + 1, ack=sseq + 1))
        pkts.append(s2c("PA", resp, at=t + 0.06, seq=sseq + 1, ack=cseq + 1 + len(req)))
        # Teardown, so the connection closes cleanly before the next callback.
        pkts.append(c2s("FA", at=t + 0.09, seq=cseq + 1 + len(req), ack=sseq + 1 + len(resp)))
        pkts.append(s2c("FA", at=t + 0.10, seq=sseq + 1 + len(resp), ack=cseq + 2 + len(req)))
        pkts.append(c2s("A", at=t + 0.11, seq=cseq + 2 + len(req), ack=sseq + 2 + len(resp)))

        if i < CONNS - 1:
            t += gaps[i]

    wrpcap(sys.argv[1], pkts)
    print(f"gen_web_beacon: wrote {len(pkts)} pkts, {CONNS} connections "
          f"({len(gaps)} gaps) {CLIENT} -> {SERVER}:{DPORT}, "
          f"mean {mean:.0f}s stdev {stdev:.0f}s cv {cv:.3f} (ceiling {MAX_CV}) "
          f"to {sys.argv[1]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
