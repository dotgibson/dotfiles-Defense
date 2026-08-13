##! http-c2.zeek — web-protocol C2: HTTPS/HTTP beacons found by callback regularity.
##!
##! Closes the web-protocol half of the "Exfil / C2" methodology row (T1071.001,
##! Application Layer Protocol: Web Protocols) — the corner the rest of network/ leaves
##! open: dns-c2.zeek covers DNS (T1071.004), icmp-tunnel.zeek ICMP (T1095),
##! reverse-tunnel.zeek tunnels (T1572), tls-c2*.zeek the handshake fingerprint
##! (T1573.002). None of them sees a plain HTTPS implant riding 443 to a redirector.
##! Network mirror of the htpx pair https-beacon-sliver <-> https-beacon-jitter.
##!
##! THE INVARIANT: jitter randomizes each interval but not the DISTRIBUTION. A beacon's
##! callbacks stay clustered around a mean period with bounded spread; human browsing
##! does not. So key on the coefficient of variation (stdev / mean) of the inter-arrival
##! times per src -> dst: low CV over enough samples is the tell that survives jitter,
##! a rotated domain, a malleable profile, and TLS. Uniform jitter of +/-J around sleep S
##! gives CV = J / (S * sqrt(3)) — the documented Sliver posture (S=3600s, J=1800s) lands
##! at CV ~= 0.29, inside the 0.35 ceiling with margin. To push CV past the ceiling an
##! operator has to jitter more than ~60% of the sleep, which costs them tasking
##! responsiveness. That trade is the detection.
##!
##! WHY IT CLOCKS connection_established AND NOT ssl_established. Three reasons, and the
##! third is why this script can be gated at all:
##!   1. A beacon sleeping for minutes-to-hours cannot hold a socket open between
##!      callbacks — each callback is a fresh TCP connection. Establishment IS the clock.
##!   2. It never touches payload, so TLS costs it nothing and it needs no analyzer.
##!   3. docker/validation/README.md records why tls-c2.zeek ships no fixture: a synthetic
##!      TLS handshake plus X.509 chain is not cheaply fakeable. Keying on ssl_established
##!      would land this script in that same un-gated bucket. Clocking the TCP handshake
##!      keeps it provable — see the web-beacon row in docker/validation/manifest.tsv.
##! ssl_established is still hooked, but ONLY to record SNI for the alert text; the timing
##! series never depends on it.
##!
##! WHY NOT SumStats (dns-c2.zeek uses it): the epoch model does not fit hour-scale sleeps
##! — a 10-minute epoch never accumulates 20 samples, and the threshold mechanism takes a
##! single monotone value, so a two-part test (enough samples AND low CV) has to be
##! smuggled into $threshold_val. State here is O(1) per pair (streaming moments, not a
##! vector of timestamps), so inline evaluation is both cheaper and clearer.
##!
##! Known limits, stated rather than implied:
##!   - A beacon that multiplexes its callbacks inside ONE long-lived connection is
##!     invisible here. That is reverse-tunnel.zeek's shape; the two are complementary.
##!   - State is node-local. On a Zeek cluster the callbacks of one pair hash to a worker
##!     by 5-tuple, but a beacon rotating source ports still lands consistently by
##!     originator; on a multi-worker deployment expect per-worker series. Standalone
##!     sensor recommended, same class of caveat as tls-c2.zeek's CA-trust note.
##!   - CDN / SaaS destinations shared with a beacon mix series together — allowlist by
##!     destination rather than raising the threshold.
##!
##! Validate (purple): run a Sliver/Havoc HTTPS beacon with a long sleep and jitter from
##! dotfiles-Kali (htpx pair https-beacon-sliver).
##!
##! Load:  add `@load ./http-c2.zeek` to local.zeek (or drop in site/).

@load base/frameworks/notice
@load base/protocols/conn
@load base/protocols/ssl

module HTTPC2;

export {
    redef enum Notice::Type += {
        ## One source calling one web destination on a near-metronomic cadence.
        Web_Beacon
    };

    ## Only external (non-RFC1918/loopback/link-local) destinations qualify.
    const internal_nets: set[subnet] = {
        10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
        127.0.0.0/8, 169.254.0.0/16, 224.0.0.0/4,
        [fc00::]/7, [fe80::]/10, [::1]/128,
    } &redef;

    ## Web-protocol destination ports. T1071.001 is *Web Protocols*, so both halves.
    const web_ports: set[port] = { 80/tcp, 443/tcp, 8080/tcp, 8443/tcp } &redef;

    ## Intervals (not connections) needed before a verdict. The SPL companion's
    ## `count > 20` counts connections; 20 intervals means 21 connections, so this is
    ## marginally stricter and never looser.
    const min_intervals: count = 20 &redef;

    ## Ignore gaps shorter than this — browser bursts and parallel connection fan-out.
    ## (They also inflate CV, so they are suppressed twice.) Matches the SPL's period>30.
    const min_period = 30sec &redef;

    ## Gaps longer than this END the series rather than widening it: a 9-hour outlier
    ## folded into the variance would mask the cadence either side of it. Also bounds
    ## state lifetime, and drops daily/weekly updater check-ins that are periodic but
    ## uninteresting. The documented 3600s beacon sleep sits well inside it.
    const max_period = 2hr &redef;

    ## Fire below this coefficient of variation. Identical to the SPL companion's 0.35.
    const max_cv = 0.35 &redef;

    ## Idle lifetime of a pair's state. 3x max_period, so a slow beacon is never reaped
    ## between callbacks.
    const state_expire = 6hr &redef;
}

## Streaming moments, so memory is O(1) per pair no matter how long a beacon runs —
## sum and sumsq are all the mean and sample stdev need.
type Beacon: record {
    ## Start time of the previous connection for this pair.
    last: time;
    ## Number of accepted intervals in the current series.
    n: count &default=0;
    ## Sum of interval lengths, seconds.
    sum: double &default=0.0;
    ## Sum of squared interval lengths, seconds^2.
    sumsq: double &default=0.0;
    ## SNI, when a TLS handshake happened to reveal it. Enrichment only.
    sni: string &default="";
    ## Fire once per series, not once per callback thereafter.
    alerted: bool &default=F;
};

## &write_expire (NOT &create_expire): a 3600s beacon needs ~21 hours to reach 20
## intervals, and &create_expire would reap the series mid-flight — killing the detector
## on exactly the long-sleep case it exists for. Note this means every mutation below
## must ASSIGN the record back into the table: mutating a copy in place does not reset
## the write timer.
global beacons: table[addr, addr, port] of Beacon &write_expire = state_expire;

event connection_established(c: connection)
    {
    local id = c$id;

    if ( id$resp_h in internal_nets )
        return;
    if ( id$resp_p !in web_ports )
        return;

    local key_o = id$orig_h;
    local key_r = id$resp_h;
    local key_p = id$resp_p;

    # First sighting of this pair: record the clock and wait for a second callback.
    if ( [key_o, key_r, key_p] !in beacons )
        {
        beacons[key_o, key_r, key_p] = [$last=c$start_time];
        return;
        }

    local s = beacons[key_o, key_r, key_p];
    local gap = c$start_time - s$last;
    s$last = c$start_time;

    # Too fast or too slow: this is not a continuation of the current series. Reset the
    # accumulator rather than folding the outlier in.
    if ( gap < min_period || gap > max_period )
        {
        s$n = 0;
        s$sum = 0.0;
        s$sumsq = 0.0;
        s$alerted = F;
        beacons[key_o, key_r, key_p] = s;
        return;
        }

    local delta = interval_to_double(gap);
    ++s$n;
    s$sum += delta;
    s$sumsq += delta * delta;
    beacons[key_o, key_r, key_p] = s;

    if ( s$alerted || s$n < min_intervals )
        return;

    local nd = s$n + 0.0;
    local mean = s$sum / nd;
    if ( mean <= 0.0 )
        return;

    # Sample variance from the streaming moments; floored because float error can push a
    # perfectly regular series a hair below zero.
    local variance = (s$sumsq - nd * mean * mean) / (nd - 1.0);
    if ( variance < 0.0 )
        variance = 0.0;

    local cv = sqrt(variance) / mean;
    if ( cv >= max_cv )
        return;

    s$alerted = T;
    beacons[key_o, key_r, key_p] = s;

    local dest = s$sni == "" ? fmt("%s", key_r) : fmt("%s (%s)", key_r, s$sni);
    NOTICE([$note=Web_Beacon,
            $conn=c,
            $msg=fmt("Web-protocol beacon: %s -> %s:%s, %d callbacks averaging %.0fs apart (cv %.2f) — periodic C2",
                     key_o, dest, key_p, s$n + 1, mean, cv),
            $identifier=cat(key_o, key_r, key_p)]);
    }

# Enrichment only: name the destination in the alert when TLS revealed an SNI. The
# timing series above never depends on this firing.
event ssl_established(c: connection)
    {
    local id = c$id;

    if ( [id$orig_h, id$resp_h, id$resp_p] !in beacons )
        return;
    if ( ! c?$ssl || ! c$ssl?$server_name )
        return;

    local s = beacons[id$orig_h, id$resp_h, id$resp_p];
    s$sni = c$ssl$server_name;
    beacons[id$orig_h, id$resp_h, id$resp_p] = s;
    }
