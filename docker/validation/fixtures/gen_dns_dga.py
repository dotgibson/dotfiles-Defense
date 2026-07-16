#!/usr/bin/env python3
"""gen_dns_dga.py — synthesize a DGA-beacon PCAP for zeek/dns-c2.zeek.

The DNS_DGA_Beacon notice fires when one source racks up >= dga_min_nxdomain (50) distinct
long (>= 12-char), vowel-poor (vowel ratio < 0.30) labels that FAIL to resolve (NXDOMAIN,
rcode 3). The Zeek rule keys on dns_query_reply gated to rcode 3, so each query needs its
NXDOMAIN *response*. So we emit 60 query+response pairs: a 64-char SHA-256 hex label (hex
is vowel-poor — only a,e among 0-9a-f, ratio ~0.12) under one zone, each response rcode 3.

60 distinct labels crosses the DGA floor (50) but stays under the tunnel floor (100), so
this fixture fires DGA and not the tunnel notice. Deterministic (seeded) so the assertion
is reproducible. Usage: gen_dns_dga.py <out.pcap>
"""
import hashlib
import sys
from scapy.all import wrpcap, Ether, IP, UDP, DNS, DNSQR  # type: ignore

CLIENT, RESOLVER, ZONE = "10.1.1.50", "10.1.1.1", "dga.example"
N = 60


def label(i: int) -> str:
    # 64-char hex digest: unique per i, >= the 12-char floor, vowel ratio ~0.12 (< 0.30).
    return hashlib.sha256(f"dga{i}".encode()).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: gen_dns_dga.py <out.pcap>", file=sys.stderr)
        return 2
    pkts = []
    t0 = 1_000_000_000.0
    for i in range(N):
        qname = f"{label(i)}.{ZONE}"
        sport = 40000 + (i % 20000)
        q = (Ether() / IP(src=CLIENT, dst=RESOLVER) /
             UDP(sport=sport, dport=53) /
             DNS(id=i & 0xFFFF, rd=1, qd=DNSQR(qname=qname)))
        # NXDOMAIN response (rcode=3), question echoed back — what dns_query_reply sees.
        r = (Ether() / IP(src=RESOLVER, dst=CLIENT) /
             UDP(sport=53, dport=sport) /
             DNS(id=i & 0xFFFF, qr=1, rcode=3, qd=DNSQR(qname=qname)))
        q.time = t0 + i
        r.time = t0 + i + 0.01
        pkts.extend([q, r])
    wrpcap(sys.argv[1], pkts)
    print(f"gen_dns_dga: wrote {len(pkts)} pkts "
          f"({N} distinct NXDOMAIN labels under {ZONE}) to {sys.argv[1]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
