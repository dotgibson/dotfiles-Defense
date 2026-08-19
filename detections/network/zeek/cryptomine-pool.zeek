##! cryptomine-pool.zeek — cryptomining pool sessions (resource hijacking).
##!
##! Closes the Impact tactic's one wire-side technique: T1496.001 Compute Hijacking.
##! Network mirror of the dotfiles-Offense companion pair resource-hijack-xmrig <->
##! cryptomine-pool-detect. Every other Impact detection in this repo is a Sigma rule on
##! host telemetry; this one cannot be, because the invariant is a conversation with a
##! mining pool, not anything the endpoint does to itself.
##!
##! The invariant is the SHAPE OF THE CONVERSATION, and it is the exact inverse of
##! reverse-tunnel.zeek's. A tunnel is long-lived and FAT. A miner is long-lived and
##! THIN: it holds one connection open for hours and exchanges a trickle of small JSON
##! messages — a job in, a share out, repeat — because the work happens on the CPU, not
##! on the wire. Long duration plus a LOW sustained byte rate on a Stratum port is a
##! profile normal traffic doesn't produce: bulk transfers on the same port are fat, and
##! chatty control channels are short.
##!
##! Why not a payload signature: the documented attack runs xmrig with `--tls`, so
##! matching `mining.subscribe`/`mining.authorize` on the wire would miss the very thing
##! this pair exists to validate. This script never inspects payload, so TLS costs it
##! nothing. suricata/cryptomine.rules ships the plaintext signature separately and says
##! plainly that it catches the lazy case, not the documented one.
##!
##! Two notices, deliberately separate:
##!  * Stratum_Pool_Session — the behavioural half. Port + duration + rate profile. Finds
##!    an unknown pool, survives TLS, and needs no feed.
##!  * Known_Pool_Destination — the indicator half. A connection to a known pool address
##!    on ANY port, which is what catches pool-over-443 where the port test can't help.
##!    Data comes from cryptomine-pool-feed.zeek (generated; empty by default, and an
##!    empty set matches nothing, so it is inert until you populate it).
##!
##! Known limits, worth stating rather than discovering:
##!  * Pool-over-443 defeats the port test; the feed is the fallback, and a CDN-proxied
##!    pool defeats both.
##!  * A miner throttled to burst rather than trickle can slip the rate ceiling — raise
##!    max_bytes_per_min if you would rather trade noise for that.
##!  * The companion asks for a SECOND tell this repo cannot supply: a process pegged
##!    near 100% CPU. No Sysmon config emits resource utilisation at any level and the
##!    lab ships no metrics collector, so this detection is the network half ALONE and is
##!    correspondingly weaker than the companion's "two converging tells" design. That is
##!    an ingestion gap, recorded in detections/README.md, not something to fake here.
##!  * Expect false positives from blockchain nodes, dev workstations, and CI runners
##!    doing legitimate crypto work — allowlist by host, the same tuning story as the
##!    rest of the network layer.
##!
##! Evaluated per-connection at teardown (connection_state_remove) — no windowing, so
##! it's cheap and self-contained, matching reverse-tunnel.zeek.
##!
##! Validate (purple): run xmrig against a pool from dotfiles-Offense (companion pair
##! resource-hijack-xmrig). Synthetic coverage ships too — see
##! docker/validation/fixtures/gen_cryptomine.py.
##!
##! Load:  add `@load ./cryptomine-pool.zeek` to local.zeek (or drop in site/).

@load base/frameworks/notice
@load base/protocols/conn

module CryptoMine;

export {
    redef enum Notice::Type += {
        ## A long-lived, low-rate session to a Stratum port — the mining profile.
        Stratum_Pool_Session,
        ## A connection to a known mining-pool address, on any port.
        Known_Pool_Destination
    };

    ## Only external (non-RFC1918/loopback/link-local) destinations qualify.
    const internal_nets: set[subnet] = {
        10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
        127.0.0.0/8, 169.254.0.0/16, 224.0.0.0/4,
        [fc00::]/7, [fe80::]/10, [::1]/128,
    } &redef;

    ## Stratum's conventional ports. Pools also run 443/80 to evade exactly this test —
    ## that case is the feed's job, not this one's.
    const stratum_ports: set[port] = {
        3333/tcp, 4444/tcp, 5555/tcp, 7777/tcp, 8888/tcp, 14444/tcp,
    } &redef;

    ## Minimum session lifetime. Miners hold the connection for the duration of the
    ## work; a port scan or a failed connect does not.
    const min_duration = 10min &redef;

    ## Rate ceiling, bytes per minute across BOTH directions. This is the discriminator:
    ## a miner trickles (jobs in, shares out), while a bulk transfer on the same port
    ## moves orders of magnitude more. Raise it to catch throttled/batched miners at the
    ## cost of catching slow file transfers too.
    const max_bytes_per_min = 20000.0 &redef;

    ## Floor so a long-lived but SILENT connection (an idle socket, a half-open scan
    ## artefact) cannot satisfy "low rate" by moving nothing at all.
    const min_total_bytes = 2000 &redef;

    ## Known mining-pool addresses. Populated by cryptomine-pool-feed.zeek (generated by
    ## detections/network/update-pool-feed.sh). Empty by default — matches nothing.
    const pool_hosts: set[addr] = {} &redef;
}

event connection_state_remove(c: connection)
    {
    if ( ! c?$id || ! c?$duration || ! c?$orig || ! c?$resp )
        return;
    if ( c$id$resp_h in internal_nets )
        return;

    local total = c$orig$size + c$resp$size;

    # Indicator half: a known pool address on ANY port, and no duration/rate test —
    # a short connection to a pool is still a connection to a pool.
    if ( c$id$resp_h in pool_hosts )
        {
        NOTICE([$note=Known_Pool_Destination,
                $conn=c,
                $msg=fmt("Connection to a known mining pool: %s -> %s:%s (%d bytes, %s)",
                         c$id$orig_h, c$id$resp_h, c$id$resp_p, total, c$duration),
                $identifier=cat(c$id$orig_h, c$id$resp_h)]);
        return;
        }

    # Behavioural half: Stratum port + long-lived + low sustained rate.
    if ( c$id$resp_p !in stratum_ports )
        return;
    if ( c$duration < min_duration )
        return;
    if ( total < min_total_bytes )
        return;

    local mins = interval_to_double(c$duration) / 60.0;
    if ( mins <= 0.0 )
        return;
    local rate = (0.0 + total) / mins;
    if ( rate > max_bytes_per_min )
        return;

    NOTICE([$note=Stratum_Pool_Session,
            $conn=c,
            $msg=fmt("Long-lived low-rate Stratum session: %s -> %s:%s for %s, %d bytes total (%.0f bytes/min) — cryptomining profile",
                     c$id$orig_h, c$id$resp_h, c$id$resp_p, c$duration, total, rate),
            $identifier=cat(c$id$orig_h, c$id$resp_h, c$id$resp_p)]);
    }
