##! tls-c2.zeek — encrypted C2: self-signed-to-external cert + JA3 fingerprint hook.
##!
##! Closes the encrypted-channel corner of the "Exfil / C2" methodology row.
##! Network mirror of the htpx pair mtls-c2-sliver <-> mtls-c2-ja3 (T1573.002,
##! Asymmetric Cryptography). Encryption hides the payload, not the handshake.
##!
##! Two layers, matching the blue entry — split by dependency so the useful half is
##! always on:
##!
##!   ALWAYS ON — behavioral, no add-on. A self-signed / untrusted certificate
##!   presented to an EXTERNAL destination. Legitimate public TLS chains to a trusted
##!   CA; a self-signed cert to the internet is the tell for the unknown-implant case
##!   no fingerprint list can be complete against (Sliver/Cobalt Strike default certs,
##!   ad-hoc HTTPS listeners). Uses `validation_status` from the stock
##!   protocols/ssl/validate-certs policy, loaded below.
##!
##!   TUNE THE CA TRUST FIRST — validation_status is only as good as the roots Zeek
##!   trusts. Two traps flood this notice with benign traffic if you skip this:
##!     * TLS-intercepting proxy / NGFW re-signs external TLS with an internal root —
##!       every session then reads as "unable to get local issuer" unless you add that
##!       root to Zeek's trust store (`redef SSL::root_certs += { ... }`, or point
##!       `SSL::root_certs` at your enterprise CA bundle).
##!     * A stale/missing Mozilla CA list in the Zeek build makes even public CAs fail.
##!   Confirm a baseline capture is mostly "ok" before enabling; if intercept can't be
##!   trusted out, narrow `untrusted_cert_status` to `/self signed/` only (drops the
##!   broken-chain half, keeps the high-signal self-signed-implant half).
##!
##!   OPT-IN — JA3 fast path. Each implant's ClientHello hashes to a stable JA3 that
##!   frameworks reuse across builds, so a known-implant JA3 is a high-fidelity match
##!   regardless of destination or sleep. JA3 is an add-on field (github.com/zeek/ja3
##!   or salesforce/ja3), so it lives in its own opt-in module: `tls-c2-ja3.zeek`, whose
##!   blocklist is fed from a maintained source by `../update-ja3-feed.sh` (so the hashes
##!   rotate with the feed, not by hand). Load that after the ja3 package. An empty feed
##!   matches nothing — the same can't-go-stale choice suricata/c2.rules makes.
##!
##! Validate (purple): stand up a Sliver mTLS / self-signed HTTPS listener from
##! dotfiles-Kali and beacon to it (hacktheplanet "Exfil / C2" folds; htpx pair
##! mtls-c2-sliver).
##!
##! Load:  add `@load ./tls-c2.zeek` to local.zeek (or drop in site/).

@load base/frameworks/notice
@load base/protocols/ssl
@load protocols/ssl/validate-certs

module TLSC2;

export {
    redef enum Notice::Type += {
        ## Self-signed / untrusted certificate to an external host (unknown-implant hunt).
        C2_SelfSigned_External
    };

    ## External destinations only (same net set as the other network/ scripts).
    const internal_nets: set[subnet] = {
        10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
        127.0.0.0/8, 169.254.0.0/16, 224.0.0.0/4,
        [fc00::]/7, [fe80::]/10, [::1]/128,
    } &redef;

    ## Validation statuses that read as self-signed / untrusted-chain.
    const untrusted_cert_status =
        /self signed/ | /unable to get local issuer/ &redef;
}

event ssl_established(c: connection)
    {
    if ( ! c?$ssl )
        return;
    if ( c$id$resp_h in internal_nets )
        return;
    if ( ! c$ssl?$validation_status )
        return;
    if ( untrusted_cert_status !in c$ssl$validation_status )
        return;

    NOTICE([$note=C2_SelfSigned_External,
            $conn=c,
            $msg=fmt("Self-signed/untrusted TLS to external %s (SNI '%s', status '%s') - unknown-implant C2 hunt",
                     c$id$resp_h,
                     c$ssl?$server_name ? c$ssl$server_name : "<none>",
                     c$ssl$validation_status),
            $identifier=cat(c$id$orig_h, c$id$resp_h)]);
    }

# ── OPT-IN: JA3 known-implant fast path ───────────────────────────────────────
# The JA3 layer lives in its own module because it needs the ja3 add-on field:
#   tls-c2-ja3.zeek         the set + ssl_established handler (opt-in, load after the
#                           ja3 package)
#   ja3-c2-feed.zeek        the blocklist data, GENERATED from a maintained feed by
#                           ../update-ja3-feed.sh (abuse.ch SSLBL JA3 by default)
# Enable it by installing the ja3 package and adding `@load ./tls-c2-ja3.zeek` after it,
# then run update-ja3-feed.sh to populate the blocklist.
