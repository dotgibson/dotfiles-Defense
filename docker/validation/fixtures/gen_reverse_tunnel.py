#!/usr/bin/env python3
"""gen_reverse_tunnel.py — synthesize a long-lived-egress PCAP for zeek/reverse-tunnel.zeek.

The Long_Lived_Egress notice fires on a connection to an EXTERNAL host with duration >=
min_duration (30m) AND >= min_bytes_each_way (1_000_000) payload bytes in BOTH directions.
So we build one TCP flow, internal -> external:443, that moves ~1.06 MB each way (130 x
8192-byte segments per side) and spans 31 minutes end to end.

Zeek counts payload bytes from the sequence-number span, so seq/ack must advance correctly
— we track both sides. Deterministic. Usage: gen_reverse_tunnel.py <out.pcap>
"""
import sys
from scapy.all import wrpcap, Ether, IP, TCP, Raw  # type: ignore

CLIENT, SERVER = "10.1.1.50", "203.0.113.9"  # internal -> external (TEST-NET-3)
SPORT, DPORT = 51000, 443
SEG = 8192
ROUNDS = 130  # 130 * 8192 = 1_064_960 bytes each way (> the 1_000_000 floor)
SPAN = 1860.0  # 31 minutes end to end (> the 30-minute floor)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: gen_reverse_tunnel.py <out.pcap>", file=sys.stderr)
        return 2
    pkts = []
    t0 = 1_000_000_000.0
    cseq, sseq = 1000, 5000

    def c2s(flags, payload=b"", t=t0):
        p = (Ether() / IP(src=CLIENT, dst=SERVER) /
             TCP(sport=SPORT, dport=DPORT, flags=flags, seq=cseq, ack=sseq) / Raw(payload)
             if payload else
             Ether() / IP(src=CLIENT, dst=SERVER) /
             TCP(sport=SPORT, dport=DPORT, flags=flags, seq=cseq, ack=sseq))
        p.time = t
        return p

    def s2c(flags, payload=b"", t=t0):
        p = (Ether() / IP(src=SERVER, dst=CLIENT) /
             TCP(sport=DPORT, dport=SPORT, flags=flags, seq=sseq, ack=cseq) / Raw(payload)
             if payload else
             Ether() / IP(src=SERVER, dst=CLIENT) /
             TCP(sport=DPORT, dport=SPORT, flags=flags, seq=sseq, ack=cseq))
        p.time = t
        return p

    # Handshake.
    pkts.append(c2s("S", t=t0)); cseq += 1
    pkts.append(s2c("SA", t=t0 + 0.01)); sseq += 1
    pkts.append(c2s("A", t=t0 + 0.02))

    # Bidirectional data, timestamps spread across the full span.
    blob = b"x" * SEG
    for i in range(ROUNDS):
        t = t0 + 1.0 + (SPAN - 2.0) * (i / (ROUNDS - 1))
        pkts.append(c2s("PA", blob, t)); cseq += SEG
        pkts.append(s2c("PA", blob, t + 0.001)); sseq += SEG

    # Teardown at the end of the span.
    pkts.append(c2s("FA", t=t0 + SPAN)); cseq += 1
    pkts.append(s2c("FA", t=t0 + SPAN + 0.01)); sseq += 1
    pkts.append(c2s("A", t=t0 + SPAN + 0.02))

    wrpcap(sys.argv[1], pkts)
    print(f"gen_reverse_tunnel: wrote {len(pkts)} pkts, ~{ROUNDS * SEG} bytes each way over "
          f"{int(SPAN)}s, {CLIENT} -> {SERVER}:{DPORT} to {sys.argv[1]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
