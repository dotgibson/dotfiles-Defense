##! icmp-tunnel.zeek — ICMP tunneling by echo volume + payload size.
##!
##! Closes the non-application-layer C2 corner of the "Exfil / C2" methodology row.
##! Network mirror of the htpx pair icmp-tunnel-c2 <-> icmp-c2-volume (T1095,
##! Non-Application Layer Protocol). Legitimate ICMP echo is sparse and small —
##! fixed-size OS pings, a few per host. A tunnel (icmpsh / ptunnel / Loki) is the
##! opposite: sustained echo request/reply to a single external host, high packet
##! counts, and large or variable payloads carrying the encoded session. Volume +
##! payload size is the invariant.
##!
##! Zeek aggregates an ICMP echo flow into one connection record, so this evaluates
##! per-flow at teardown: high packet count AND large mean payload to an external
##! peer. Baseline out monitoring pollers (Nagios/Zabbix/SmartPing) that legitimately
##! ping a lot — allowlist those source addresses.
##!
##! Validate (purple): run icmpsh / ptunnel from dotfiles-Offense (hacktheplanet
##! "Exfil / C2" folds; htpx pair icmp-tunnel-c2). Uses only conn.log fields — no
##! add-on analyzer.
##!
##! Load:  add `@load ./icmp-tunnel.zeek` to local.zeek (or drop in site/).

@load base/frameworks/notice
@load base/protocols/conn

module ICMPTunnel;

export {
    redef enum Notice::Type += {
        ## Sustained, large-payload ICMP echo to one external host — tunnel-shaped.
        ICMP_Tunnel
    };

    ## External destinations only (see reverse-tunnel.zeek for the same net set).
    const internal_nets: set[subnet] = {
        10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
        127.0.0.0/8, 169.254.0.0/16, 224.0.0.0/4,
        [fc00::]/7, [fe80::]/10, [::1]/128,
    } &redef;

    ## Minimum echo packets in the flow (normal pings are a handful).
    const min_packets = 500 &redef;
    ## Minimum mean payload bytes per packet (OS echo payloads are tiny/fixed).
    const min_avg_payload = 64.0 &redef;
}

event connection_state_remove(c: connection)
    {
    if ( ! c?$id )
        return;
    if ( get_port_transport_proto(c$id$resp_p) != icmp )
        return;
    if ( c$id$resp_h in internal_nets )
        return;
    if ( ! c?$orig )
        return;

    local pkts = c$orig$num_pkts;
    if ( pkts < min_packets )
        return;

    local avg_payload = (c$orig$size + 0.0) / pkts;
    if ( avg_payload < min_avg_payload )
        return;

    NOTICE([$note=ICMP_Tunnel,
            $conn=c,
            $msg=fmt("ICMP tunneling: %s -> %s, %d echo packets, mean payload %.0f bytes",
                     c$id$orig_h, c$id$resp_h, pkts, avg_payload),
            $identifier=cat(c$id$orig_h, c$id$resp_h)]);
    }
