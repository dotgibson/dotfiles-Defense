#!/usr/bin/env python3
"""gen_cryptomine.py — synthesize a Stratum mining session for the T1496.001 detections.

Feeds BOTH engines from one PCAP, the way gen_icmp_tunnel.py does:

  zeek/cryptomine-pool.zeek   Stratum_Pool_Session fires on an EXTERNAL destination on a
                              Stratum port with duration >= min_duration (10m), total
                              bytes >= min_total_bytes (2000), and a sustained rate <=
                              max_bytes_per_min (20000 B/min).
  suricata/cryptomine.rules   the plaintext handshake rules match `mining.subscribe` /
                              `mining.authorize` / `mining.submit` to_server.

The shape is the point, and it is the INVERSE of gen_reverse_tunnel.py's: that one moves
~1 MB each way to look like a tunnel, this one trickles a few KB over a quarter of an hour
to look like a miner. Sizing is deliberate — comfortably past the duration floor and the
byte floor, comfortably under the rate ceiling:

  duration 900s (15m)   vs min_duration 10m
  total    ~6.9 KB      vs min_total_bytes 2000
  rate     ~463 B/min   vs max_bytes_per_min 20000

That headroom matters: a fixture sized just barely over a threshold turns the gate red on
a harmless tuning change instead of on a real regression.

Zeek counts payload bytes from the sequence-number span, so seq/ack must advance
correctly — both sides are tracked. Deterministic. Usage: gen_cryptomine.py <out.pcap>
"""
import sys
from scapy.all import wrpcap, Ether, IP, TCP, Raw  # type: ignore

CLIENT, SERVER = "10.1.1.77", "203.0.113.44"  # internal -> external (TEST-NET-3)
SPORT, DPORT = 49330, 3333  # 3333/tcp is in CryptoMine::stratum_ports
SPAN = 900.0  # 15 minutes end to end (> the 10-minute floor)
JOBS = 40  # job/share round trips spread across the span

SUBSCRIBE = b'{"id":1,"method":"mining.subscribe","params":["xmrig/6.21.0"]}\n'
AUTHORIZE = b'{"id":2,"method":"mining.authorize","params":["4AdUnd...wallet","x"]}\n'
JOB = b'{"jsonrpc":"2.0","method":"job","params":{"blob":"0e0e","job_id":"%d","target":"b88d0600"}}\n'
SUBMIT = b'{"id":%d,"method":"mining.submit","params":{"job_id":"%d","nonce":"a1b2c3d4"}}\n'


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: gen_cryptomine.py <out.pcap>", file=sys.stderr)
        return 2

    pkts = []
    t0 = 1_000_000_000.0
    cseq, sseq = 2000, 9000
    c_bytes = s_bytes = 0

    def c2s(flags, payload=b"", t=t0):
        base = Ether() / IP(src=CLIENT, dst=SERVER) / TCP(
            sport=SPORT, dport=DPORT, flags=flags, seq=cseq, ack=sseq)
        p = base / Raw(payload) if payload else base
        p.time = t
        return p

    def s2c(flags, payload=b"", t=t0):
        base = Ether() / IP(src=SERVER, dst=CLIENT) / TCP(
            sport=DPORT, dport=SPORT, flags=flags, seq=sseq, ack=cseq)
        p = base / Raw(payload) if payload else base
        p.time = t
        return p

    # Handshake.
    pkts.append(c2s("S", t=t0)); cseq += 1
    pkts.append(s2c("SA", t=t0 + 0.01)); sseq += 1
    pkts.append(c2s("A", t=t0 + 0.02))

    # Stratum login — what the plaintext Suricata rules match.
    pkts.append(c2s("PA", SUBSCRIBE, t0 + 0.10)); cseq += len(SUBSCRIBE); c_bytes += len(SUBSCRIBE)
    pkts.append(c2s("PA", AUTHORIZE, t0 + 0.20)); cseq += len(AUTHORIZE); c_bytes += len(AUTHORIZE)

    # Steady state: a job down, a share up, trickling across the whole span. This is the
    # low-and-slow profile the Zeek script keys on.
    for i in range(JOBS):
        t = t0 + 1.0 + (SPAN - 2.0) * (i / (JOBS - 1))
        job = JOB % i
        pkts.append(s2c("PA", job, t)); sseq += len(job); s_bytes += len(job)
        sub = SUBMIT % (i + 3, i)
        pkts.append(c2s("PA", sub, t + 0.05)); cseq += len(sub); c_bytes += len(sub)

    # Teardown at the end of the span, so conn duration spans the full window.
    pkts.append(c2s("FA", t=t0 + SPAN)); cseq += 1
    pkts.append(s2c("FA", t=t0 + SPAN + 0.01)); sseq += 1
    pkts.append(c2s("A", t=t0 + SPAN + 0.02))

    wrpcap(sys.argv[1], pkts)
    total = c_bytes + s_bytes
    print(f"gen_cryptomine: wrote {len(pkts)} pkts, {total} payload bytes over {int(SPAN)}s "
          f"(~{total / (SPAN / 60.0):.0f} B/min), {CLIENT} -> {SERVER}:{DPORT} to {sys.argv[1]}",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
