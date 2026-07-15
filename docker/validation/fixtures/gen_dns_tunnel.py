#!/usr/bin/env python3
"""gen_dns_tunnel.py — synthesize a DNS-tunneling PCAP for zeek/dns-c2.zeek.

The DNS_Tunnel notice fires when one source drives >= tunnel_min_unique (100) distinct
long (>= 25-char) leftmost labels under a single parent zone in the epoch. So we emit
120 unique labels — each a 64-char SHA-256 hex digest, well over the 25-char floor — from
one internal host to the resolver, under one zone, a second apart: comfortably over the
threshold and inside the 10-minute window.

Deterministic (seeded) so the fixture — and therefore the assertion — is reproducible.
Usage: gen_dns_tunnel.py <out.pcap>
"""
import hashlib
import sys
from scapy.all import wrpcap, Ether, IP, UDP, DNS, DNSQR  # type: ignore

SRC, RESOLVER, ZONE = "10.1.1.50", "10.1.1.1", "tunnel.evil.example"
N = 120


def label(i: int) -> str:
    # A 64-char hex digest of i — deterministic, guaranteed-unique per i, and well over
    # the 25-char "long label" floor. (Uniqueness is the property the count relies on;
    # a colliding PRNG silently under-counts and the fixture stops crossing the threshold.)
    return hashlib.sha256(str(i).encode()).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: gen_dns_tunnel.py <out.pcap>", file=sys.stderr)
        return 2
    pkts = []
    t0 = 1_000_000_000.0  # fixed base time — deterministic, all within one 10m epoch
    for i in range(N):
        qname = f"{label(i)}.{ZONE}"
        p = (Ether() / IP(src=SRC, dst=RESOLVER) /
             UDP(sport=40000 + (i % 20000), dport=53) /
             DNS(id=i & 0xFFFF, rd=1, qd=DNSQR(qname=qname)))
        p.time = t0 + i  # one second apart
        pkts.append(p)
    wrpcap(sys.argv[1], pkts)
    print(f"gen_dns_tunnel: wrote {len(pkts)} DNS queries "
          f"({N} distinct long labels under {ZONE}) to {sys.argv[1]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
