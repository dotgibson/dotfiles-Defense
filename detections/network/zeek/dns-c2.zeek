##! dns-c2.zeek — DNS-based C2: tunneling and DGA beaconing on the wire.
##!
##! Closes the Command-and-Control DNS half of the "Exfil / C2" methodology row.
##! Network mirror of two htpx pairs (dotfiles-Kali PURPLE-TEAM.md):
##!   dns-tunnel-c2  <-> dns-tunnel-sysmon-22   (T1071.004, DNS as an app-layer C2)
##!   dga-c2-domains <-> dga-nxdomain-entropy   (T1568.002, DGA rendezvous)
##! The Sysmon-22 twins attribute the queries to a process; this is the resolver /
##! Zeek dns.log view — the invariant is the *shape of the query stream*, not any
##! one domain, so it survives a domain rotation the way an IOC blocklist can't.
##!
##! Two SumStats streams over a rolling epoch:
##!   Tunnel — one source driving many DISTINCT, long, leftmost labels under a single
##!            parent zone (the encoded payload). Resolution *succeeds*; the tell is
##!            the fan-out of long subdomains to one zone.
##!   DGA    — one source producing a burst of long, vowel-poor labels that FAIL to
##!            resolve (NXDOMAIN / rejected). A DGA mints far more names than register,
##!            so the failures pile up before the one live rendezvous.
##!
##! Tune the thresholds to your DNS volume and baseline out telemetry/AV clients and
##! CDNs that legitimately fan out many subdomains (allowlist by src or parent zone).
##!
##! Validate (purple): run iodine/dnscat2 (tunnel) or a DGA generator from
##! dotfiles-Kali (hacktheplanet "Exfil / C2" folds; htpx pairs dns-tunnel-c2,
##! dga-c2-domains). Needs Zeek's DNS analyzer (base/protocols/dns) — no add-on.
##!
##! Load:  add `@load ./dns-c2.zeek` to local.zeek (or drop in site/).

@load base/frameworks/sumstats
@load base/frameworks/notice
@load base/protocols/dns

module DNSC2;

export {
    redef enum Notice::Type += {
        ## One source fanning out many long, distinct subdomains to one zone.
        DNS_Tunnel,
        ## One source producing a burst of long, vowel-poor NXDOMAIN failures.
        DNS_DGA_Beacon
    };

    ## Rolling window the counts accumulate over.
    const epoch = 10min &redef;

    ## Tunnel: a leftmost label at/above this length is "long" (encoded payload).
    const tunnel_min_label_len = 25 &redef;
    ## Tunnel: fire when a src touches this many distinct long subdomains in one zone.
    const tunnel_min_unique = 100.0 &redef;

    ## DGA: only consider failed labels at/above this length.
    const dga_min_label_len = 12 &redef;
    ## DGA: only consider labels whose vowel ratio is below this (randomness proxy).
    const dga_max_vowel_ratio = 0.30 &redef;
    ## DGA: fire when a src racks up this many distinct failed odd labels.
    const dga_min_nxdomain = 50.0 &redef;
}

# Vowel ratio of a lowercased label — a cheap, self-contained entropy proxy.
function vowel_ratio(label: string): double
    {
    local n = |label|;
    if ( n == 0 )
        return 1.0;
    local stripped = gsub(to_lower(label), /[aeiou]/, "");
    local vowels = n - |stripped|;
    return (vowels + 0.0) / n;
    }

# Leftmost label of a name, or "" if it has none.
function leftmost_label(name: string): string
    {
    local parts = split_string(name, /\./);
    if ( |parts| == 0 )
        return "";
    return parts[0];
    }

# Registrable-ish parent (last two labels) — good enough to group a tunnel's zone.
function parent_zone(name: string): string
    {
    local parts = split_string(name, /\./);
    if ( |parts| < 2 )
        return name;
    return parts[|parts|-2] + "." + parts[|parts|-1];
    }

event zeek_init()
    {
    local tunnel_r = SumStats::Reducer($stream="dnsc2.tunnel",
                                       $apply=set(SumStats::UNIQUE));
    SumStats::create([$name="dnsc2-tunnel",
                      $epoch=epoch,
                      $reducers=set(tunnel_r),
                      $threshold=tunnel_min_unique,
                      $threshold_val(key: SumStats::Key, result: SumStats::Result) =
                          {
                          return result["dnsc2.tunnel"]$unique + 0.0;
                          },
                      $threshold_crossed(key: SumStats::Key, result: SumStats::Result) =
                          {
                          NOTICE([$note=DNS_Tunnel,
                                  $src=key$host,
                                  $msg=fmt("DNS tunneling: %s queried %d distinct long subdomains under zone '%s' in %s",
                                           key$host, result["dnsc2.tunnel"]$unique,
                                           key$str, epoch),
                                  $identifier=cat(key$host, key$str)]);
                          }]);

    local dga_r = SumStats::Reducer($stream="dnsc2.dga",
                                    $apply=set(SumStats::UNIQUE));
    SumStats::create([$name="dnsc2-dga",
                      $epoch=epoch,
                      $reducers=set(dga_r),
                      $threshold=dga_min_nxdomain,
                      $threshold_val(key: SumStats::Key, result: SumStats::Result) =
                          {
                          return result["dnsc2.dga"]$unique + 0.0;
                          },
                      $threshold_crossed(key: SumStats::Key, result: SumStats::Result) =
                          {
                          NOTICE([$note=DNS_DGA_Beacon,
                                  $src=key$host,
                                  $msg=fmt("DGA beacon: %s produced %d distinct long vowel-poor NXDOMAIN labels in %s",
                                           key$host, result["dnsc2.dga"]$unique, epoch),
                                  $identifier=cat(key$host)]);
                          }]);
    }

# Tunnel: every query with a long leftmost label counts toward its (src, zone).
event dns_request(c: connection, msg: dns_msg, query: string, qtype: count, qclass: count)
    {
    if ( query == "" )
        return;
    if ( |leftmost_label(query)| < tunnel_min_label_len )
        return;
    SumStats::observe("dnsc2.tunnel",
                      [$host=c$id$orig_h, $str=parent_zone(query)],
                      [$str=query]);
    }

# DGA: NXDOMAIN replies with long, vowel-poor labels. Keyed on dns_query_reply
# (fires on the *reply*, echoes the Question, and exposes msg$rcode) gated to
# rcode 3 = NXDOMAIN — the precise DGA tell. This avoids depending on the exact
# RCODE range dns_rejected covers; broaden to `msg$rcode != 0` for SERVFAIL/etc.
event dns_query_reply(c: connection, msg: dns_msg, query: string, qtype: count, qclass: count)
    {
    if ( msg$rcode != 3 )   # DNS_CODE_NAME_ERR (NXDOMAIN)
        return;
    if ( query == "" )
        return;
    local label = leftmost_label(query);
    if ( |label| < dga_min_label_len )
        return;
    if ( vowel_ratio(label) >= dga_max_vowel_ratio )
        return;
    SumStats::observe("dnsc2.dga",
                      [$host=c$id$orig_h],
                      [$str=query]);
    }
