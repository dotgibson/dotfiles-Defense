##! reverse-tunnel.zeek — long-lived, high-volume outbound sessions (tunnels & egress).
##!
##! Closes the tunneling/egress corner of the "Exfil / C2" methodology row.
##! Network mirror of the htpx pair reverse-tunnel-chisel <-> reverse-tunnel-detect
##! (T1572, Protocol Tunneling). A tunnel (chisel/ligolo/ssh -R) collapses many
##! logical sessions into ONE transport connection, so on conn.log it stands out as a
##! single external connection that lives far longer and moves far more bytes — in
##! BOTH directions — than a normal client flow, often to a raw IP or an odd port.
##! Duration + bidirectional volume is the invariant; the framework and port vary.
##!
##! The same shape is the tail end of a data-egress: a workstation or server holding a
##! fat, long outbound session to the internet is either a tunnel or bulk exfil
##! (T1041 over the C2 channel, T1048 over an alternative protocol) — both worth the
##! look, so this fires on the shape and lets triage split them.
##!
##! Evaluated per-connection at teardown (connection_state_remove) — no windowing, so
##! it's cheap and self-contained. Baseline out sanctioned long-haul sessions (backups,
##! replication, VPN concentrators, software mirrors) by dst or (src,dst,port).
##!
##! Validate (purple): run chisel/ligolo reverse tunnel from dotfiles-Kali
##! (hacktheplanet "Exfil / C2" / pivot folds; htpx pair reverse-tunnel-chisel).
##! Enrich with a JA3 tunneling fingerprint + destination reputation to raise fidelity.
##!
##! Load:  add `@load ./reverse-tunnel.zeek` to local.zeek (or drop in site/).

@load base/frameworks/notice
@load base/protocols/conn

module RevTunnel;

export {
    redef enum Notice::Type += {
        ## A long-lived, high-volume, bidirectional external session — tunnel/egress.
        Long_Lived_Egress
    };

    ## Only external (non-RFC1918/loopback/link-local) destinations qualify.
    const internal_nets: set[subnet] = {
        10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
        127.0.0.0/8, 169.254.0.0/16, 224.0.0.0/4,
        [fc00::]/7, [fe80::]/10, [::1]/128,
    } &redef;

    ## Minimum session lifetime to consider (tunnels persist; browsing doesn't).
    const min_duration = 30min &redef;
    ## Minimum payload bytes in EACH direction (a real tunnel moves data both ways).
    const min_bytes_each_way = 1000000 &redef;
}

event connection_state_remove(c: connection)
    {
    if ( ! c?$id || ! c?$duration )
        return;
    if ( c$id$resp_h in internal_nets )
        return;
    if ( c$duration < min_duration )
        return;
    if ( ! c?$orig || ! c?$resp )
        return;
    if ( c$orig$size < min_bytes_each_way || c$resp$size < min_bytes_each_way )
        return;

    NOTICE([$note=Long_Lived_Egress,
            $conn=c,
            $msg=fmt("Long-lived external session: %s -> %s:%s for %s, %d bytes out / %d bytes in (tunnel or bulk egress)",
                     c$id$orig_h, c$id$resp_h, c$id$resp_p, c$duration,
                     c$orig$size, c$resp$size),
            $identifier=cat(c$id$orig_h, c$id$resp_h, c$id$resp_p)]);
    }
