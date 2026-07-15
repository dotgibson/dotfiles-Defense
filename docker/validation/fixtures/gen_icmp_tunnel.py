#!/usr/bin/env python3
"""gen_icmp_tunnel.py — synthesize an ICMP-tunneling PCAP for zeek/icmp-tunnel.zeek.

The ICMP_Tunnel notice fires on a flow to an EXTERNAL host with >= min_packets (500)
echo requests AND a mean payload >= min_avg_payload (64) bytes. So we emit 520 echo
requests (one ICMP id, incrementing seq, so Zeek groups them into one connection) with
a 100-byte payload, from an internal source to a TEST-NET-3 (external) destination.

Deterministic so the fixture is reproducible. Usage: gen_icmp_tunnel.py <out.pcap>
"""
import sys
from scapy.all import wrpcap, Ether, IP, ICMP, Raw  # type: ignore

SRC, DST = "10.1.1.50", "203.0.113.5"  # internal -> external (TEST-NET-3)
N = 520
PAYLOAD = b"T" * 100  # 100 bytes > the 64-byte mean-payload floor
ICMP_ID = 0x4242


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: gen_icmp_tunnel.py <out.pcap>", file=sys.stderr)
        return 2
    pkts = []
    t0 = 1_000_000_000.0
    for i in range(N):
        p = (Ether() / IP(src=SRC, dst=DST) /
             ICMP(type=8, id=ICMP_ID, seq=i & 0xFFFF) / Raw(load=PAYLOAD))
        p.time = t0 + i * 0.1  # 0.1s apart — one sustained flow
        pkts.append(p)
    wrpcap(sys.argv[1], pkts)
    print(f"gen_icmp_tunnel: wrote {len(pkts)} ICMP echo requests "
          f"({len(PAYLOAD)}-byte payload) {SRC} -> {DST} to {sys.argv[1]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
