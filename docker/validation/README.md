# docker/validation — does each detection actually fire?

The Sigma CI (`sigma.yml`) proves the rules *parse and compile*. This proves the
detections **work**: attack telemetry in → the real shipped detection runs → the expected
signal comes out. It's the executable form of every `Validate (purple):` line, minus the
manual Kali box. Two planes:

- **Network** (this doc, below) — PCAP replay through Zeek/Suricata (`run-validation.sh`).
- **Host / Sigma** — a JSON-lines event log through the real Sigma rule with
  [zircolite](https://github.com/wagga40/Zircolite) (`run-sigma-validation.sh`), asserting
  the rule id lands in the detections. Manifest: [`sigma-manifest.tsv`](sigma-manifest.tsv)
  (`name / pipeline / tp-fixture / rule / expected-id / tn-fixture`); fixtures are committed
  JSONL under `sigma-fixtures/`. Covers single-selection, filtered, and
  `value_count`-correlation rules across the `windows-audit` and `sysmon` pipelines, and —
  where a row names a true-negative — asserts the rule stays **silent** on a benign
  near-miss too (`-` for none). Run it:
  `ZIRCOLITE=/path/to/zircolite.py docker/validation/run-sigma-validation.sh` (CI clones a
  pinned zircolite — see `.github/workflows/sigma-validation.yml`). Gated the same way the
  network plane is: a rule that stops firing turns it red, and so does a filter that stops
  filtering.
- **Cloud / SaaS (nested-field)** — the cloud rules zircolite's EVTX flattener can't reach
  (dotted paths + underscored keys, see the finding below), driven through
  [`sigma_eval.py`](sigma_eval.py) (`run-cloud-validation.sh`). Manifest:
  [`sigma-cloud-manifest.tsv`](sigma-cloud-manifest.tsv)
  (`name / rule / tp-fixture / tn-fixture / expected-id`). Each rule is checked both ways —
  the true-positive fires the expected id, the true-negative (a benign near-miss) does not.
  Pure Python: `pip install pysigma && docker/validation/run-cloud-validation.sh`.

## How it works (network plane)

`run-validation.sh` reads [`manifest.tsv`](manifest.tsv) — one row per detection:

```text
name<TAB>engine<TAB>generator<TAB>detection-script<TAB>expected-signal
```

For each row it:

1. runs the **generator** (`fixtures/gen_*.py`, scapy) to synthesize an attack-shaped
   PCAP — deterministic and seeded, sized just past the detection's threshold;
2. replays it through the **engine** with the **real** detection script
   (`zeek -r fixture.pcap detections/network/zeek/<script>`);
3. asserts the **expected signal** (a Zeek `Notice::Type`) appears in the output.

PASS/FAIL per row; non-zero exit if any fails. Because the generators are seeded, a green
run means the detection fires on exactly the shape it claims — and a regression that
breaks the detection turns the gate red.

## Run it

CI runs this on every `detections/network/**` or `docker/validation/**` change (see
`.github/workflows/network-validation.yml`) — one job per engine, each in that engine's
image (`zeek/zeek`, `jasonish/suricata`). Locally, run one plane at a time:

```sh
pip install scapy
docker/validation/run-validation.sh zeek        # needs `zeek` on PATH
docker/validation/run-validation.sh suricata    # needs `suricata` on PATH
docker/validation/run-validation.sh             # both
# no engine installed? wrap the image in a shim on PATH, e.g.:
#   printf '#!/usr/bin/env bash\nexec docker run --rm -i -v "$PWD":/w -w /w zeek/zeek:lts zeek "$@"\n' > ~/bin/zeek && chmod +x ~/bin/zeek
```

`ZEEK_CMD` / `SURICATA_CMD` / `PYTHON` override the binaries. The preflight only requires
the engine(s) the selected rows actually use.

## Adding a detection

1. Write `fixtures/gen_<name>.py` that takes an output path and synthesizes the
   attack-shaped traffic just past the detection's threshold (keep it seeded/deterministic).
   One fixture can feed both engines — e.g. `gen_icmp_tunnel.py`'s 900-byte echo clears
   Zeek's mean-payload floor *and* Suricata's `dsize:>800`.
2. Add a row to `manifest.tsv`: the generator, the detection script, and the expected
   signal — a Zeek `Module::Notice_Type`, or a Suricata rule `msg` (matched literally).

## Scope — what's covered, what isn't

This is the **network plane** (PCAP replay — offline, deterministic, hermetic). Covered:
Zeek DNS tunnel + DGA, ICMP tunnel, reverse-tunnel/egress, cryptomining pool session,
web-protocol beacon (`http-c2.zeek`);
Suricata DNS-tunnel, ICMP oversized-echo, plaintext Stratum, and all four DCERPC coercion
vectors (MS-EFSRPC/RPRN/DFSNM/FSRVP).

`gen_cryptomine.py` feeds both engines from one PCAP, the way `gen_icmp_tunnel.py` does,
and its sizing is the interesting part: 6.9 KB over 900 seconds (~463 B/min) is
comfortably past `cryptomine-pool.zeek`'s duration and byte floors and comfortably under
its rate ceiling. That headroom is deliberate — a fixture sized *just* past a threshold
turns the gate red on a harmless tuning change instead of on a real regression. Note the
Suricata row proves only the plaintext path; the documented attack it pairs with runs
with `--tls`, where the Zeek row is the one that matters.

**Coercion — synthesized after all (`suricata/coercion.rules`, all 4 interfaces).** An
earlier bind-only attempt was deferred because Suricata parsed the interface but emitted no
alert. The missing piece wasn't the bind bytes: `dce_iface` matches when a **request** is
issued on a *bound* interface, not on the bind alone. `gen_coercion.py` now builds the full
DCERPC/TCP exchange per vector — TCP handshake → bind → bind_ack → a request PDU on the
bound context — one flow each for MS-EFSRPC (PetitPotam), MS-RPRN (PrinterBug), MS-DFSNM
(DFSCoerce) and MS-FSRVP (ShadowCoerce), all in one PCAP. Four manifest rows, all firing.

**Known gaps — deferred to Phase-3 captured fixtures**, not silently uncovered. These
depend on protocol state a faithful synthetic can't cheaply fake, so a captured PCAP from
the real Offense attack is the honest fixture:

- `zeek/tls-c2.zeek` (self-signed cert) and `zeek/tls-c2-ja3.zeek` (JA3) — need a real TLS
  handshake + X.509 chain for Zeek's SSL analyzer and the ja3 add-on.
- `zeek/kerberoast-rc4.zeek` — needs a real Kerberos TGS-REP (ASN.1, RC4 etype).

Worth contrasting with the covered case directly above them: `zeek/http-c2.zeek` watches the
same encrypted traffic those two do, and *is* gated, because it clocks
`connection_established` rather than `ssl_established`. That was a design choice made partly
for this reason — a detection keyed on the TCP handshake needs no certificate to be provable,
so `gen_web_beacon.py` can synthesize 22 beacon callbacks on port 443 with no TLS at all. The
generator also computes the mean/stdev/CV it produced and refuses to write a PCAP that would
not trip the thresholds, so a drifted fixture fails loudly here instead of going quietly
non-firing in CI.

Partial, trivially extendable (same shape as a covered row): the c2.rules
oversized-query-name / echo-reply variants.

## Host / Sigma plane — coverage & findings

Covered (81 rows, `sigma-manifest.tsv`): the Windows-security and Sysmon corpus across
every shape — Kerberoast, AS-REP, DCSync, GPP cpassword, coercion, DPAPI, LSASS access,
NTDS dump, rogue-account / machine-account / scheduled-task / WMI-subscription persistence,
DCShadow, RBCD, shadow-credentials, ADCS ESC1, RDP-hijack, PsExec, WMIexec, the potato
SeImpersonate pair and the spoolss-pipe rule that detects the impersonation those two
can only infer, the atsvc/svcctl and efsrpc pipe-bind rules that corroborate 7045/4698/5145
on the host plane, the full ransomware chain (recovery-inhibition, service-stop burst,
protected-service stop, data destruction, BitLocker abuse, mass encryption),
unconstrained-delegation abuse, host-side collection (the 4663 read sweep and the archive
staging step), and the correlation rules (password-spray, pass-the-hash, LDAP-recon,
SharpHound, host-recon burst, local-SAM enumeration sweep, share/session enumeration
sweep, mass-encryption on both 4663 and Sysmon 11, mass-read). The two 4663 rules each
carry a second row whose events use combined access masks — the shape a real SACL emits —
so the `AccessList` branch that makes them fire there is a standing regression test rather
than an assertion.
Each was verified firing against the real engine locally.

### True negatives — how a filter is proven

This plane used to be true-positive only, which meant a row could prove a rule *fires* but
never that it *doesn't*: an exclusion that silently stopped matching would keep the gate
green while the rule quietly went noisy. `sigma-manifest.tsv` now carries a sixth column,
the TN fixture (`-` for none), and **every rule with a `filter_*` block has one**. The
runner reports the count (`81/81 passed (38 with a true-negative)`), and rules that grow a
filter but no TN are named in an advisory at the end of the run — the same
discoverable-checklist idea as [`deploy-required.sh`](../../detections/sigma/deploy-required.sh).

A TN is only worth anything if it would really have fired. Three things enforce that, and
each exists because the obvious version of this gate fails silently:

1. **Engine errors are not silence.** zircolite producing no detections because it *failed*
   looks identical to a filter doing its job. A TN passes only on a three-way contract: the
   engine exited 0, it **wrote** its output file, and the id is absent. Same reasoning
   `run-cloud-validation.sh` documents for its evaluator's 0/1/2 exit codes.
2. **The fixture must be a structural near-miss of its TP** — same EventID set, same
   `EventData` key set, one *value* changed so exactly one `filter_*` block catches it.
   This is checked before the engine runs. It was added after a garbage TN fixture (a file
   of non-JSON) *passed*: zircolite ingested 0 events, exited 0, and wrote an empty
   result — a vacuous pass. The key-set half catches the subtler version, a typo'd field
   name that makes the base selection miss, so the rule goes silent for a reason that has
   nothing to do with the filter under test.
3. **Correlation TNs are sized past the threshold** — 101 objects against SharpHound's
   `gte: 100`, 205 files against the Sysmon-11 `gte: 200`, 12 failures against the spray
   rule's `gte: 10`. A TN that merely falls short of the threshold would pass no matter what
   the filter did.

The gate itself was checked by breaking things on purpose: neutering a rule's `filter_*`
block turns its row red (`TN: rule fired on the benign near-miss`), and a missing,
unparseable, or wrong-shaped TN fixture fails with the reason named rather than passing.
Re-run that exercise if you change the TN machinery — a green suite is not evidence that
the negative half works.

**A filter that gates only *part* of a rule needs a row per branch.** One TN proves a
filter suppresses what it should; it says nothing about what the filter must leave alone.
`collection/archive_staging_utility` is the worked example: its `filter_backup_tooling`
is scoped to the staging-path branch and deliberately does **not** touch the
password-protected branch, so it carries two rows —
`archive-staging` (staging-path near-miss under the suppressed parent → silent) and
`archive-staging-password-survives-filter` (an *encrypted* archive under that same
suppressed parent → still fires). The second is the one that matters: the rule originally
applied the filter to the whole condition, which silently suppressed its own
high-confidence half, and a single TN row was perfectly happy with that. Reuse one TN
fixture across both rows; only the TP changes.

The `unconstrained-deleg-4624` row is the one whose fixture is bound to a
`DEPLOY-REQUIRED` placeholder: the rule ships matching only the `DC1$`/`DC2$` examples,
so the fixture names `DC1$` as the coerced DC. It proves the *shape* fires, not that the
rule is deployable — substituting the real DC inventory is still on the operator (see the
`DEPLOY-REQUIRED` table in `detections/README.md`). The `dcshadow-4742` row has the same
property.

**Resolved — the potato SeImpersonate rule now fires (split into a per-channel pair).**
The original `potato_seimpersonate_4688.yml` was dual-channel by design: one
`selection_svc_identity` matched the service account in EITHER `User` (Sysmon-1) OR
`SubjectUserName` (Security-4688). Both fields in one rule broke it under a single pysigma
pipeline — the **sysmon** pipeline can't resolve `SubjectUserName` and the **windows-audit**
pipeline can't resolve `User`, so in each case the unresolved branch nulled the whole rule
(reproduced: adding the second-channel branch → 0 matches on an event the single-channel form
caught). The fix was a detection-content decision, so it was flagged rather than changed under
the cloud-plane PR. It's now split into a per-channel pair — `potato_seimpersonate_sysmon_1.yml`
(field `User`, validated on the **sysmon** pipeline) and `potato_seimpersonate_4688.yml`
(field `SubjectUserName`, EventID 4688, validated on **windows-audit**) — with the original id
preserved on the 4688 half so the htpx cross-link holds. Both are wired into the manifest and
verified firing locally; deploy both and whichever channel a host forwards will match.

**Cloud / SaaS** (`pipeline=none`): 22 rules covered — AWS (IAM key, login profile), Entra
(consent, SP credential, directory-role grant), GitHub (branch-protection, credential, runner), Google Workspace
(admin role, mail-forward, OAuth), Jenkins (×3), Okta (×3), npm (×2), PyPI collaborator,
Slack (app-installed, external-share). These have no EventID and match on raw field names,
so they run without a pysigma pipeline.

**Nested-field cloud plane — the 30 zircolite can't reach, now covered.** zircolite is
EVTX-oriented: its flattener collapses a nested/dotted event path to the **last key with
underscores stripped** (verified with `--keepflat`: `gcp.audit.method_name` → `methodname`,
`resource.type` → `type`, with collisions; and it strips `_` from flat keys too, so
`resource_type` → `resourcetype`, `event_type` → `eventtype`). So cloud rules that match on
dotted paths *or* underscored keys can't be exercised through zircolite — the column never
carries the name the rule expects. This hit every rule for **GCP, Cloudflare, GitLab,
Kubernetes, Harbor, Snowflake, Terraform, Vault**, plus a few others (npm-malicious-publish,
PyPI token/trusted-publisher, Slack-2FA, AWS IAM privesc-policy — which filters on the
dotted `userIdentity.arn`): 30 rules.

These are now validated by a small dedicated matcher, [`sigma_eval.py`](sigma_eval.py),
rather than zircolite. It matches a rule against natural cloud-event JSON by walking
**pysigma's own parsed, fully-resolved condition tree** — so the field modifiers
(`contains`/`startswith`/`endswith`/`all`) and the `and`/`or`/`not` logic come from the
authoritative parser, not a re-implementation — and does a dotted-path lookup into nested
JSON (fanning out lists, e.g. a pod's `containers[].securityContext.privileged`), which is
exactly the step zircolite drops. It supports only what this corpus uses (field-equals over
string/number/bool/null, with wildcards); anything outside that surface raises rather than
guessing, so an unsupported rule fails loudly. Two guards keep this from being "my matcher
agrees with my fixture": every rule must fire its true-positive **and** stay silent on a
benign true-negative near-miss, and the tree it walks is pysigma's, not ours. The stateful
correlation rule (`vault_bulk_secret_read`, `value_count gte 20`) is validated at its base
per-event detection; the count/timespan aggregation is out of scope for a single-event
matcher (noted, not silently claimed).

The 22 flat-field cloud rules (AWS, Entra, GitHub, Google Workspace, Jenkins, Okta, npm,
PyPI-collaborator, Slack app/share) stay on zircolite — keeping an independent third-party
engine in the loop wherever one can actually run the rule; the evaluator is introduced only
where no available engine preserves the field names.

The network plane (above) is PCAP replay; both Sigma planes are JSONL-event replay. Tracked
in [`../LAB-VALIDATION-PLAN.md`](../LAB-VALIDATION-PLAN.md).
