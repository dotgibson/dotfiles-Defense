##! tls-c2-ja3.zeek — OPT-IN JA3 known-implant fast path for encrypted C2 (T1573.002).
##!
##! The fingerprint half of tls-c2.zeek, in its own file because it depends on the JA3
##! package (github.com/zeek/ja3 or salesforce/ja3), which adds the `ja3` field to
##! SSL::Info. A script that reads `c$ssl$ja3` won't even compile without that field, so
##! keeping it separate lets tls-c2.zeek's self-signed detection stay always-on while
##! this stays opt-in. Load order:
##!
##!   @load <the ja3 package>       # provides c$ssl$ja3
##!   @load ./tls-c2-ja3.zeek       # this file (pulls the feed below)
##!
##! Each implant's ClientHello hashes to a stable JA3 that frameworks reuse across
##! builds, so a known-implant JA3 is a high-fidelity match regardless of destination or
##! sleep time. The hashes ROTATE, so they are NOT hard-coded here: the blocklist is data
##! in ja3-c2-feed.zeek, regenerated from a maintained feed by ../update-ja3-feed.sh
##! (abuse.ch SSLBL JA3 by default). An empty feed = empty set = matches nothing, so this
##! is safe to load before the first refresh and can't false-positive on stale hashes.
##!
##! Validate (purple): beacon a Sliver / Cobalt Strike mTLS implant from dotfiles-Kali,
##! capture its JA3 into the feed, and confirm this notice fires (htpx pair mtls-c2-sliver).
##!
##! Load:  add `@load ./tls-c2-ja3.zeek` to local.zeek AFTER the ja3 package.

@load base/frameworks/notice
@load base/protocols/ssl

module TLSC2JA3;

export {
    redef enum Notice::Type += {
        ## TLS handshake matched a known C2-framework JA3 fingerprint.
        C2_JA3_Match
    };

    ## Known-implant JA3 hashes. Populated by the generated ja3-c2-feed.zeek (loaded at
    ## the bottom of this file); redef inline too if you keep a private set.
    const c2_ja3_blocklist: set[string] = {} &redef;
}

event ssl_established(c: connection)
    {
    if ( ! c?$ssl || ! c$ssl?$ja3 )
        return;
    if ( c$ssl$ja3 !in c2_ja3_blocklist )
        return;

    NOTICE([$note=C2_JA3_Match,
            $conn=c,
            $msg=fmt("Known C2 JA3 %s: %s -> %s (SNI '%s')",
                     c$ssl$ja3, c$id$orig_h, c$id$resp_h,
                     c$ssl?$server_name ? c$ssl$server_name : "<none>"),
            $identifier=cat(c$id$orig_h, c$id$resp_h, c$ssl$ja3)]);
    }

# The generated fingerprint feed (a redef of c2_ja3_blocklist). Loaded last so the const
# is declared before it's extended. Regenerate with ../update-ja3-feed.sh.
@load ./ja3-c2-feed.zeek
