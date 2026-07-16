#!/usr/bin/env python3
"""gen_coercion.py — synthesize an authentication-coercion PCAP for suricata/coercion.rules.

The coercion rules match a DCERPC bind to a specific MS-RPC interface UUID over an
established TCP session to 135/445 (`dce_iface:<uuid>; flow:to_server,established`). So we
build a 3-way handshake to the endpoint mapper (TCP/135) followed by a client->server
DCERPC bind whose abstract syntax is MS-EFSRPC (PetitPotam) — sid 9000001. The interface
is the invariant; a real coercion tool sends exactly this bind before the coerce call.

The bind carries an NDR transfer syntax so it's well-formed for Suricata's DCERPC parser.
Deterministic. Usage: gen_coercion.py <out.pcap>
"""
import sys
import uuid
from scapy.all import wrpcap, Ether, IP, TCP, Raw  # type: ignore
from scapy.layers.dcerpc import (  # type: ignore
    DceRpc5, DceRpc5Bind, DceRpc5Context, DceRpc5AbstractSyntax, DceRpc5TransferSyntax,
)

CLIENT, SERVER = "10.1.1.50", "10.1.1.20"  # attacker -> target DC (both "internal": $HOME_NET)
SPORT, DPORT = 49700, 135
EFSRPC = "c681d488-d850-11d0-8c52-00c04fd90f7e"          # MS-EFSRPC (PetitPotam)
NDR = "8a885d04-1ceb-11c9-9fe8-08002b104860"             # NDR transfer syntax v2


def bind_bytes() -> bytes:
    ctx = DceRpc5Context(
        cont_id=0,
        abstract_syntax=DceRpc5AbstractSyntax(if_uuid=uuid.UUID(EFSRPC), if_version=1),
        transfer_syntaxes=[DceRpc5TransferSyntax(if_uuid=uuid.UUID(NDR), if_version=2)],
    )
    return bytes(DceRpc5() / DceRpc5Bind(context_elem=[ctx]))


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: gen_coercion.py <out.pcap>", file=sys.stderr)
        return 2
    t0 = 1_000_000_000.0
    cseq, sseq = 2000, 8000
    pkts = []

    def mk(src, dst, sp, dp, flags, seq, ack, payload, t):
        p = Ether() / IP(src=src, dst=dst) / TCP(sport=sp, dport=dp, flags=flags, seq=seq, ack=ack)
        if payload:
            p = p / Raw(payload)
        p.time = t
        return p

    # 3-way handshake so the flow is established / to_server.
    pkts.append(mk(CLIENT, SERVER, SPORT, DPORT, "S", cseq, 0, b"", t0)); cseq += 1
    pkts.append(mk(SERVER, CLIENT, DPORT, SPORT, "SA", sseq, cseq, b"", t0 + 0.01)); sseq += 1
    pkts.append(mk(CLIENT, SERVER, SPORT, DPORT, "A", cseq, sseq, b"", t0 + 0.02))

    # The DCERPC bind (client -> server) carrying the MS-EFSRPC interface.
    payload = bind_bytes()
    pkts.append(mk(CLIENT, SERVER, SPORT, DPORT, "PA", cseq, sseq, payload, t0 + 0.03))
    cseq += len(payload)
    pkts.append(mk(SERVER, CLIENT, DPORT, SPORT, "A", sseq, cseq, b"", t0 + 0.04))

    wrpcap(sys.argv[1], pkts)
    print(f"gen_coercion: wrote {len(pkts)} pkts (DCERPC bind to MS-EFSRPC {EFSRPC} on "
          f"TCP/{DPORT}) to {sys.argv[1]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
