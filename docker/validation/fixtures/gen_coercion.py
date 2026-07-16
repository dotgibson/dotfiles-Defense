#!/usr/bin/env python3
"""gen_coercion.py — synthesize a DCERPC authentication-coercion PCAP for
suricata/coercion.rules (PetitPotam & friends).

coercion.rules keys on the RPC interface UUID via Suricata's `dce_iface` keyword, over
DCERPC/TCP (port 135). `dce_iface` matches when a REQUEST is issued on a bound interface —
NOT on the bind alone — so a faithful fixture needs the full exchange per interface:
TCP 3-way handshake → DCERPC bind → bind_ack → a request PDU on the bound context. (An
earlier bind-only attempt is why this was once deferred to captured fixtures; the missing
piece was the bind_ack + request, not the bind bytes.)

One flow per coercion vector, all four in one PCAP so a single fixture validates every SID:
  MS-EFSRPC (PetitPotam) · MS-RPRN (PrinterBug) · MS-DFSNM (DFSCoerce) · MS-FSRVP (ShadowCoerce)

Attacker (10.9.9.9) → DC (10.1.1.10:135, inside Suricata's default HOME_NET). Deterministic
and seeded — reproducible. Usage: gen_coercion.py <out.pcap>
"""
import struct
import sys

from scapy.all import IP, TCP, Ether, Raw, wrpcap  # type: ignore

NDR = "8a885d04-1ceb-11c9-9fe8-08002b104860"  # NDR transfer syntax, v2

# (msg-tag, interface UUID, iface major.minor, coercion opnum) — one DCERPC vector each.
VECTORS = [
    ("MS-EFSRPC", "c681d488-d850-11d0-8c52-00c04fd90f7e", (1, 0), 0),   # EfsRpcOpenFileRaw
    ("MS-RPRN", "12345678-1234-abcd-ef00-0123456789ab", (1, 0), 65),    # RpcRemoteFindFirstPrinterChangeNotificationEx
    ("MS-DFSNM", "4fc742e0-4a10-11cf-8273-00aa004ae673", (3, 0), 12),   # NetrDfsRemoveStdRoot
    ("MS-FSRVP", "a8e0653c-2744-4389-a61d-7373df8b2292", (1, 0), 8),    # IsPathSupported
]

SRC, DST = "10.9.9.9", "10.1.1.10"  # attacker -> DC (in Suricata's default HOME_NET 10/8)
DPORT = 135  # DCERPC / epmapper over TCP


def _uuid_le(u):
    """UUID string -> DCE/RPC wire encoding (first three fields little-endian)."""
    a, b, c, d, e = u.split("-")
    return (struct.pack("<I", int(a, 16)) + struct.pack("<H", int(b, 16)) +
            struct.pack("<H", int(c, 16)) + bytes.fromhex(d) + bytes.fromhex(e))


def _pdu(ptype, body, call_id):
    """Wrap a DCERPC v5 PDU header (little-endian data rep, first+last frag) around body."""
    hdr = struct.pack("<BBBB", 5, 0, ptype, 0x03) + b"\x10\x00\x00\x00"
    hdr += struct.pack("<HH", 16 + len(body), 0) + struct.pack("<I", call_id)
    return hdr + body


def _bind(iface, ver, call_id=1):
    ctx = struct.pack("<HBB", 0, 1, 0)  # p_cont_id=0, n_transfer_syn=1, reserved
    ctx += _uuid_le(iface) + struct.pack("<HH", ver[0], ver[1])
    ctx += _uuid_le(NDR) + struct.pack("<I", 2)
    body = struct.pack("<HHI", 5840, 5840, 0) + struct.pack("<BBH", 1, 0, 0) + ctx
    return _pdu(11, body, call_id)


def _bind_ack(call_id=1):
    sec = b"135\x00"
    sec_field = struct.pack("<H", len(sec)) + sec
    sec_field += b"\x00" * ((-len(sec_field)) % 4)  # pad to 4-byte boundary
    result = struct.pack("<HH", 0, 0) + _uuid_le(NDR) + struct.pack("<I", 2)  # accept
    body = struct.pack("<HHI", 5840, 5840, 0x11223344) + sec_field + struct.pack("<BBH", 1, 0, 0) + result
    return _pdu(12, body, call_id)


def _request(opnum, call_id=2, ctx=0, stub=b"\x00" * 32):
    body = struct.pack("<IHH", len(stub), ctx, opnum) + stub  # alloc_hint, p_cont_id, opnum
    return _pdu(0, body, call_id)


def _flow(sport, iface, ver, opnum, t0):
    """Full handshake + bind + bind_ack + request for one interface, as a timestamped list."""
    cs, ss = 1000, 5000
    pk = []

    def add(frm_client, flags, payload, seq, ack):
        s, d, sp, dp = (SRC, DST, sport, DPORT) if frm_client else (DST, SRC, DPORT, sport)
        p = Ether() / IP(src=s, dst=d) / TCP(sport=sp, dport=dp, flags=flags, seq=seq, ack=ack)
        if payload:
            p = p / Raw(load=payload)
        p.time = t0 + len(pk) * 0.01
        pk.append(p)

    add(True, "S", b"", cs, 0)
    add(False, "SA", b"", ss, cs + 1)
    add(True, "A", b"", cs + 1, ss + 1)
    b = _bind(iface, ver)
    add(True, "PA", b, cs + 1, ss + 1)
    c2 = cs + 1 + len(b)
    add(False, "A", b"", ss + 1, c2)
    ba = _bind_ack()
    add(False, "PA", ba, ss + 1, c2)
    s2 = ss + 1 + len(ba)
    add(True, "A", b"", c2, s2)
    req = _request(opnum)
    add(True, "PA", req, c2, s2)
    add(False, "A", b"", s2, c2 + len(req))
    return pk


def main():
    if len(sys.argv) != 2:
        print("usage: gen_coercion.py <out.pcap>", file=sys.stderr)
        return 2
    pkts = []
    t0 = 1_000_000_000.0
    for i, (_tag, iface, ver, opnum) in enumerate(VECTORS):
        pkts += _flow(40000 + i, iface, ver, opnum, t0 + i * 10.0)
    wrpcap(sys.argv[1], pkts)
    print(f"gen_coercion: wrote {len(pkts)} packets — {len(VECTORS)} DCERPC coercion flows "
          f"({', '.join(v[0] for v in VECTORS)}) {SRC} -> {DST}:{DPORT} to {sys.argv[1]}",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
