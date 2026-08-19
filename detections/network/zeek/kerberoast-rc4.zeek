##! kerberoast-rc4.zeek — raise a notice on the Kerberoasting invariant on the wire.
##!
##! The network mirror of the 4769 RC4-TGS Sigma rule (../../sigma/credential_access/
##! kerberoasting_rc4_tgs.yml). Zeek's krb analyzer records the ticket cipher in
##! krb.log; an RC4 (rc4-hmac) service ticket for a non-machine, non-krbtgt SPN is the
##! roast tell — the encryption downgrade the technique cannot avoid. This reads only
##! the documented Kerberos::Info fields off the connection, so it does not depend on
##! low-level message layouts.
##!
##! Validate (purple): run impacket-GetUserSPNs / "nxc --kerberoasting" from
##! dotfiles-Offense and confirm this notice fires in the lab (htpx pair
##! kerberoast-getuserspns <-> kerberoasting-4769).
##!
##! Load:  add `@load ./kerberoast-rc4.zeek` to local.zeek (or drop in site/).

@load base/protocols/krb
@load base/frameworks/notice

module Kerberoast;

export {
    redef enum Notice::Type += { RC4_Service_Ticket };
}

event connection_state_remove(c: connection)
    {
    if ( ! c?$krb )
        return;

    local k = c$krb;

    # Only TGS (service-ticket) requests, only when we captured the cipher.
    if ( ! k?$request_type || k$request_type != "TGS" )
        return;
    if ( ! k?$cipher )
        return;

    # The invariant: an RC4 service ticket.
    if ( /rc4/ !in to_lower(k$cipher) )
        return;

    # Drop machine-account service tickets (…$) and krbtgt — not roastable users.
    if ( k?$service && ( /\$/ in k$service || /krbtgt/ in to_lower(k$service) ) )
        return;

    NOTICE([$note=RC4_Service_Ticket,
            $conn=c,
            $msg=fmt("Kerberoast-shaped RC4 TGS for service '%s' requested by '%s'",
                     k?$service ? k$service : "<unknown>",
                     k?$client ? k$client : "<unknown>"),
            $identifier=cat(c$id$orig_h, k?$service ? k$service : "")]);
    }
