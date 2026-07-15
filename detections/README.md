# detections/ — version-controlled detection content

Detection as code. **Sigma is the portable source of truth** — author once,
compile down to whatever SIEM the lab runs. Each rule carries its ATT&CK
technique, its data source, and a validation note that names the **exact
`dotfiles-Kali` hacktheplanet fold and `htpx` pair** that reproduces it — so the
purple loop is closed in the file itself: run the attack there, confirm the rule
fires here.

| Dir        | Holds                                                 | Start from (upstream)                          |
| ---------- | ----------------------------------------------------- | ---------------------------------------------- |
| `sigma/`   | portable rules (the source of truth)                  | SigmaHQ                                        |
| `sysmon/`  | Sysmon config baseline(s)                             | Olaf Hartong `sysmon-modular`; SwiftOnSecurity |
| `network/` | Zeek scripts + Suricata rules                         | Zeek pkgs; ET Open ruleset                     |
| `siem/`    | compiled saved-searches, props/transforms, dashboards | compile from `sigma/`                          |
| `navigator/` | ATT&CK Navigator layer (heatmap) + `COVERAGE.md` report | generate from `sigma/`                       |

Workflow: write Sigma → convert to your backend → stand up the lab (`siemup`) →
run the matching attack from Kali → confirm it fires → tune → commit rule +
validation note. Real IOC values from cases stay in `~/cases/*/iocs`, never here.

## CI gate — the rules are validated as code

The Sigma rules are gated on every change by `.github/workflows/sigma.yml` (the
repo's `lint.yml` only covers shell). Five hard checks, one advisory:

1. **Structural lint** (hermetic) —
   `sigma check --fail-on-issues -c detections/sigma-validation-config.yml`.
   Catches bad YAML, broken conditions, dangling field refs, duplicate ids/titles,
   bad status/level. `--fail-on-issues` is required — `sigma check` otherwise exits 0
   on validator *issues* (only parse/semantic errors fail it by default). The config
   drops only the two validators that need live MITRE downloads, so the gate never
   flakes on a network hiccup.
2. **Compile** — every rule must compile to a real backend (Splunk) via
   `detections/sigma/convert.sh`. A rule that won't convert isn't deployable.
3. **SIEM deploy-form drift** — `detections/siem/gen-siem.sh --check`. The three
   deploy artifacts — Splunk `savedsearches.generated.conf`, Sentinel
   `rules.generated.kql`, Elastic `rules.generated.lucene` — are *generated* from the
   Sigma tree; this proves the committed files still match what the generator emits, so
   no deploy form can drift by hand (the same idea as htpx's `gen-views.sh --check`).
4. **ATT&CK Navigator drift** — `detections/navigator/gen-navigator.sh --check`. The
   `coverage-layer.json` heatmap is *generated* from the rules' `attack.*` tags; this
   proves the committed layer still matches, so the coverage view can't drift from the
   rules.
5. **ATT&CK coverage report drift** — `detections/navigator/gen-coverage.sh --check`. The
   human-readable `COVERAGE.md` roll-up (by tactic / technique / logsource) is *generated*
   from the same tags; this proves the committed report still matches, so it can't drift.
6. **ATT&CK-tag validity** — advisory (`continue-on-error`); checks each
   `attack.tXXXX` is a real published technique, but never breaks the build on a
   transient MITRE download failure.

Run it locally (any pySigma backend):

```sh
# pinned, matching CI (splunk + elasticsearch + kusto backends)
pip install "sigma-cli==3.0.2" "pysigma-backend-splunk==2.1.0" \
            "pysigma-backend-elasticsearch==2.1.0" "pysigma-backend-kusto==1.0.1"
sigma check --fail-on-issues -c detections/sigma-validation-config.yml detections/sigma/   # lint
detections/sigma/convert.sh splunk                                                         # compile → SPL
detections/siem/gen-siem.sh --check                                                        # deploy-form drift (Splunk/Sentinel/Elastic)
detections/navigator/gen-navigator.sh --check                                              # ATT&CK Navigator layer drift
detections/navigator/gen-coverage.sh --check                                               # ATT&CK coverage report (COVERAGE.md) drift
```

`convert.sh` is the reproducible "Sigma → backend" *compile check*: it compiles each
rule with `--without-pipeline` (raw logical fields). `gen-siem.sh` is the reproducible
"Sigma → **deploy form**" step across **three SIEMs**: the Splunk `savedsearches`
form (Windows dirs through the `splunk_windows` TA pipeline, non-Windows dirs raw),
plus one-query-per-rule **Sentinel KQL** (`kusto` backend) and **Elastic Lucene**
(`lucene` backend) forms — all generated from the tree and drift-gated together. The
KQL/Lucene forms compile raw (add a `sentinel_asim`/`ecs_windows` pipeline for a real
Windows deploy); rules a backend can't express (Sigma correlations) are noted in-file,
not dropped. The hand-wrapped `siem/` forms below stay for the enriched, absence/join,
and packaged-analytics deploys a bare compile can't emit.

## What ships today (the starter pack)

The first content drop mirrors the **htpx red↔blue corpus**: each rule below
detects a technique that `dotfiles-Kali` can execute on demand, so every one is
purple-validatable out of the box.

### `sigma/` — 71 rules / 78 documents, organized by ATT&CK tactic

**`credential_access/`**

| Rule | Event / source | ATT&CK | Validate with (Kali fold · htpx pair) |
| ---- | -------------- | ------ | ------------------------------------- |
| `kerberoasting_rc4_tgs` | 4769 RC4 (0x17) | T1558.003 | Kerberos · kerberoast-getuserspns |
| `asrep_roast_probing_4771` | 4771 0x18 (correlation) | T1558.004 | Kerberos · asreproast-getnpusers |
| `password_spray_4625` | 4625 (value_count correlation) | T1110.003 | Kerberos/Poisoning · password-spray-kerbrute |
| `dcsync_replication_4662` | 4662 replication right | T1003.006 | DCSync/NTDS · dcsync-secretsdump |
| `gpp_cpassword_sysvol_5145` | 5145 SYSVOL prefs XML | T1552.006 | SMB · gpp-cpassword |
| `coercion_named_pipes_5145` | 5145 IPC$ pipe (spoolss/efsrpc/…) | T1187 | Poisoning & relay · coerce-petitpotam |
| `dpapi_backupkey_5145` | 5145 IPC$ `protected_storage` | T1555 | Credential access · dpapi-backupkey |
| `ntds_dump_ntdsutil_vss_4688` | proc create (ntdsutil/VSS) | T1003.003 | DCSync/NTDS · ntds-ntdsutil |
| `lsass_handle_access` | Sysmon 10 (LSASS) | T1003.001 | Lateral movement · lsass-dump-lsassy |

**`privilege_escalation/`**

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `adcs_esc1_san_mismatch_4886` | 4886/4887 cert request | T1649 | AD CS abuse · adcs-esc1-certipy |
| `potato_seimpersonate_4688` | proc create (service→shell) | T1134.001 | Win privesc · potato-seimpersonate |
| `shadow_credentials_keycredentiallink_5136` | 5136 msDS-KeyCredentialLink | T1556 | AD attack paths · shadow-credentials-certipy |
| `rbcd_allowedtoact_5136` | 5136 msDS-AllowedToActOnBehalf… | T1098 | AD attack paths · rbcd-impacket |

**`lateral_movement/`**

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `wmiexec_wmiprvse_child_4688` | proc create (WmiPrvSE child) | T1047 | Lateral movement · wmiexec-impacket |
| `rdp_hijack_tscon_4688` | proc create (tscon /dest:) | T1563.002 | Lateral movement · rdp-hijack-tscon |
| `service_creation_psexec_7045` | 7045 service install | T1569.002 | Lateral movement · pth-lateral-nxc |
| `passthehash_4624_fanout` | 4624 type-3 (value_count correlation) | T1550.002 / T1021 | Lateral movement · pth-lateral-nxc |

**`discovery/`**

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `sharphound_ldap_sweep_4662` | 4662 dir-access (value_count correlation) | T1087.002 / T1069.002 | AD enumeration · bloodhound-sharphound |
| `ldap_recon_explicit_creds_4648` | 4648 explicit-cred fan-out (value_count correlation) | T1087.002 / T1046 | recon · PURPLE-TEAM 4648 row |

**`persistence/`**

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `scheduled_task_suspicious_4698` | 4698 task created | T1053.005 | Persistence · schtask-persist |
| `wmi_event_subscription_consumer` | Sysmon 19/20/21 | T1546.003 | Persistence · wmi-subscription |
| `rogue_account_creation_4720` | 4720 account created | T1136.002 / T1136.001 | Persistence · rogue-account |
| `machine_account_creation_burst_4741` | 4741 burst (value_count correlation) | T1136.002 | AD attack paths · rbcd-impacket |

**`defense_evasion/`**

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `dcshadow_rogue_dc_4742` | 4742 `GC/` SPN write (+5137/4662) | T1207 | AD attack paths · dcshadow |

**`cloud/`** (multi-cloud — Entra `product: azure`, AWS `product: aws`, GCP `product: gcp`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `entra_illicit_consent_grant` | Entra AuditLogs "Consent to application" | T1528 | M365/Entra · consent-grant |
| `entra_sp_credential_backdoor` | Entra AuditLogs "Add SP credentials" | T1098.001 | M365/Entra · sp-cred-backdoor |
| `aws_iam_access_key_created` | CloudTrail `CreateAccessKey` | T1098.001 | AWS IAM · aws-iam-backdoor-key |
| `aws_login_profile_created` | CloudTrail Create/UpdateLoginProfile | T1098 | AWS IAM · aws-console-login-profile |
| `gcp_service_account_key_created` | GCP audit `CreateServiceAccountKey` | T1098.001 | GCP IAM · gcp-sa-key |

**`kubernetes/`** (kube-apiserver audit — `product: kubernetes`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `k8s_privileged_pod_created` | audit: privileged/hostPID/hostPath pod create | T1610/T1611 | Kubernetes · k8s-privileged-pod |
| `k8s_pod_exec_attach` | audit: `pods/exec`+`pods/attach` create | T1609 | Kubernetes · k8s-exec |
| `k8s_clusteradmin_binding` | audit: roleRef `cluster-admin` binding | T1098 | Kubernetes · k8s-clusteradmin-binding |

**`okta/`** (Okta System Log — `product: okta`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `okta_mfa_factor_reset` | `user.mfa.factor.reset_all`/deactivate | T1556.006 | Okta · okta-mfa-reset |
| `okta_api_token_created` | `system.api_token.create` | T1098 | Okta · okta-api-token |
| `okta_idp_created` | `system.idp.lifecycle.create`/activate | T1556/T1484.002 | Okta · okta-idp-backdoor |

**`github/`** (GitHub Enterprise audit log — `product: github`, `service: audit`; field `action`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `github_self_hosted_runner_registered` | `self_hosted_runner.created` | T1543 | GitHub · gh-self-hosted-runner |
| `github_branch_protection_tamper` | `protected_branch.destroy` / `protected_branch.policy_override` | T1562.001 | GitHub · gh-branch-protection-off |
| `github_credential_backdoor` | `repo.create_deploy_key` / `personal_access_token.access_granted` | T1098 | GitHub · gh-deploy-key-backdoor |

**`registry/`** (Harbor container-registry audit log — `product: harbor`, `service: audit`; field `operation`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `harbor_image_pushed_trusted_tag` | `operation=push` `resource_type=artifact` | T1525 | Harbor · harbor-image-backdoor |
| `harbor_robot_account_created` | `operation=create` `resource_type=robot` | T1098 | Harbor · harbor-robot-backdoor |
| `harbor_artifact_deleted` | `operation=delete` artifact/repository | T1070 | Harbor · harbor-artifact-delete |

**`gitlab/`** (GitLab audit events — `product: gitlab`, `service: audit`; field `event_type`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `gitlab_rogue_runner_associated` | `set_runner_associated_projects` | T1543 | GitLab · gl-runner-hijack |
| `gitlab_protected_branch_tamper` | `protected_branch_removed` / `protected_branch_created` | T1562.001 | GitLab · gl-protected-branch-off |
| `gitlab_token_backdoor` | `project_access_token_created` / `personal_access_token_created` / `deploy_token_created` | T1098 | GitLab · gl-token-backdoor |

**`vault/`** (HashiCorp Vault audit device — `product: vault`, `service: audit`; fields `request.operation`/`request.path`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `vault_bulk_secret_read` | `read` on `secret/` path (value_count correlation) | T1555 | Vault · vault-secret-exfil |
| `vault_approle_backdoor` | create/update on `auth/approle/role/` or `sys/auth/` | T1098 | Vault · vault-approle-backdoor |
| `vault_audit_device_disabled` | `delete` on `sys/audit/` path | T1562.001 | Vault · vault-audit-disable |

**`terraform/`** (Terraform Cloud audit trail — `product: terraform`, `service: audit`; fields `resource.type`/`resource.action`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `tfc_rogue_agent_pool` | `agent_pool` `create` | T1543 | Terraform · tfc-agent-hijack |
| `tfc_token_backdoor` | `authentication_token` `create` | T1098 | Terraform · tfc-token-backdoor |
| `tfc_variable_injection` | `variable` `create`/`update` | T1072 | Terraform · tfc-var-injection |

**`jenkins/`** (Jenkins Audit Trail plugin — `product: jenkins`, `service: audit`; keyword/URI matches)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `jenkins_script_console` | `/script` / `/scriptText` request | T1059 | Jenkins · jenkins-script-console |
| `jenkins_api_token_created` | `ApiTokenProperty/generateNewToken` request | T1098 | Jenkins · jenkins-api-token |
| `jenkins_job_backdoor` | `/createItem` / `/job/<name>/configSubmit` request | T1072 | Jenkins · jenkins-job-backdoor |

**`snowflake/`** (Snowflake `ACCOUNT_USAGE.QUERY_HISTORY` — `product: snowflake`, `service: audit`; fields `query_type`/`query_text`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `snowflake_data_unload` | `QUERY_TYPE=UNLOAD` (COPY INTO location) | T1567.002 | Snowflake · snowflake-exfil-stage |
| `snowflake_user_created` | `CREATE_USER` / priv `GRANT` | T1136.003 | Snowflake · snowflake-rogue-user |
| `snowflake_network_policy_change` | `NETWORK POLICY` in query text | T1562.007 | Snowflake · snowflake-network-policy |

**`google_workspace/`** (Google Workspace admin/token/user audit — `product: google_workspace`; field `eventName`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `gws_illicit_oauth_grant` | token `authorize` | T1528 | Workspace · gws-oauth-grant |
| `gws_admin_role_grant` | `GRANT_DELEGATED_ADMIN_PRIVILEGES` / `ASSIGN_ROLE` | T1098.003 | Workspace · gws-super-admin |
| `gws_external_mail_forwarding` | `email_forwarding_out_of_domain` | T1114.003 | Workspace · gws-mail-forward |

**`cloudflare/`** (Cloudflare account audit log — `product: cloudflare`, `service: audit`; fields `resource.type`/`action.type`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `cloudflare_api_token_created` | `resource.type=api_token` `create` | T1098 | Cloudflare · cf-api-token |
| `cloudflare_waf_rule_disabled` | `firewall_rule`/`ruleset` `delete`/`update` | T1562.001 | Cloudflare · cf-waf-disable |
| `cloudflare_worker_deployed` | `resource.type=worker`/`workers_script` `create`/`update` | T1648 | Cloudflare · cf-worker-deploy |

**`npm/`** (npm account/org audit log — `product: npm`, `service: audit`; field `action`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `npm_malicious_package_publish` | `package.publish` by non-CI actor | T1195.002 | npm · npm-malicious-publish |
| `npm_maintainer_added` | `package.owner_add` / `team.user_add` | T1098 | npm · npm-owner-add |
| `npm_publish_2fa_disabled` | `package.edit` `mfa=none` | T1562.001 | npm · npm-2fa-disable |

**`pypi/`** (PyPI project journal — `product: pypi`, `service: audit`; field `action`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `pypi_token_release_upload` | `new release` not via trusted publisher | T1195.002 | PyPI · pypi-malicious-publish |
| `pypi_collaborator_added` | `add Owner` / `add Maintainer` | T1098 | PyPI · pypi-role-add |
| `pypi_trusted_publisher_added` | add `trusted publisher` entry | T1098 | PyPI · pypi-trusted-publisher |

**`slack/`** (Slack Enterprise Grid audit logs — `product: slack`, `service: audit`; field `action`)

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `slack_app_installed` | `app_installed` (broad read scopes) | T1098 | Slack · slack-malicious-app |
| `slack_external_shared_channel` | `shared_channel_invite_sent` / `_accepted` | T1567 | Slack · slack-external-share |
| `slack_2fa_enforcement_disabled` | `pref.two_factor_auth_changed` `two_factor_required=false` | T1562.001 | Slack · slack-2fa-disable |

`password_spray`, `asrep_roast_probing`, `sharphound_ldap_sweep`,
`ldap_recon_explicit_creds_4648`, `passthehash_4624_fanout`,
`machine_account_creation_burst_4741`, and `vault_bulk_secret_read` are Sigma
**correlation** rules (a base event + a `value_count` over a window); the rest are
single-event selections. The `cloud/`, `kubernetes/`, `okta/`, `github/`, `registry/`,
`gitlab/`, `vault/`, `terraform/`, `jenkins/`, `snowflake/`, `google_workspace/`,
`cloudflare/`, `npm/`, `pypi/`, and `slack/`
rules are the non-Windows logsources here
(`product: azure|aws|gcp|kubernetes|okta|github|harbor|gitlab|vault|terraform|jenkins|snowflake|google_workspace|cloudflare|npm|pypi|slack`)
and mirror the htpx corpus's companion-only cloud, K8s, Okta, GitHub Actions, Harbor
registry, GitLab CI/CD, HashiCorp Vault, Terraform Cloud, Jenkins, Snowflake,
Google Workspace, Cloudflare, npm + PyPI registry, and Slack pairs.
The `jenkins/` rules match the Audit Trail plugin's request-URI log line via a `uri`
field (`uri|contains`), scoped to the specific endpoints (e.g. job `configSubmit` is
bound to the `/job/` path so global config submits don't trip it).

#### Deploy-time substitutions (`DEPLOY-REQUIRED`)

A few rules can't be meaningful until you substitute an environment-specific value —
the anomaly is defined *relative to your baseline*, which the repo can't know. Those
spots carry a `DEPLOY-REQUIRED:` marker in a YAML comment; run
[`sigma/deploy-required.sh`](sigma/deploy-required.sh) to list them before deploying and
fill each one. (Advisory, exits 0 — the repo ships the placeholders on purpose; a
comment isn't enforcement, so this is the discoverable checklist instead.)

| Rule | Substitute | Until you do |
| ---- | ---------- | ------------ |
| `privilege_escalation/rbcd_allowedtoact_5136` | `filter_delegation_admins` → your delegation-admin accounts | can't tell admin from user; pair with `machine_account_creation_burst_4741` for fidelity that doesn't need it |
| `defense_evasion/dcshadow_rogue_dc_4742` | `filter_real_dcs` → your real DC computer accounts | a `GC/` SPN write onto another real DC would alert (low risk — rare regardless) |
| `cloud/entra_illicit_consent_grant` | `filter_known_apps` → sanctioned app (client) IDs | verified LOB apps holding mail/file scopes alert (the high-risk-scope match still scopes it) |
| `snowflake/snowflake_data_unload` | `filter_known_stages` → sanctioned named stages | a named *internal* stage (not `@%`/`@~`) alerts alongside external ones |

### `sysmon/` — `sysmonconfig-detection-lab.xml`

A deliberately minimal Sysmon baseline that turns on **exactly** the telemetry
the rules above need (ProcessCreate 1, ProcessAccess 10 on LSASS, Registry 12/13
for autorun/WDigest, PipeEvent 17/18 for coercion pipes, WmiEvent 19/20/21). It
is a lab baseline, not production — graduate to `sysmon-modular` and tune.

### `network/` — wire-side mirrors

- `zeek/kerberoast-rc4.zeek` — notices on an RC4 service ticket for a user SPN
  (the on-wire twin of `kerberoasting_rc4_tgs`).
- `suricata/coercion.rules` — DCERPC interface binds for PetitPotam / PrinterBug /
  DFSCoerce / ShadowCoerce (the wire twin of the 5145 coercion detection).

**Command-and-Control (TA0011)** — the "Exfil / C2" methodology row, on Zeek + Suricata
(behavioral invariants in Zeek, per-packet/fingerprint tells in Suricata; htpx pairs
`dns-tunnel-c2`, `dga-c2-domains`, `reverse-tunnel-chisel`, `icmp-tunnel-c2`, `mtls-c2-sliver`):

- `zeek/dns-c2.zeek` — DNS tunneling (T1071.004, long distinct-subdomain fan-out per
  zone) and DGA beaconing (T1568.002, long vowel-poor NXDOMAIN bursts), via SumStats.
- `zeek/reverse-tunnel.zeek` — long-lived high-volume bidirectional external sessions
  (T1572); the same shape surfaces bulk egress (T1041/T1048).
- `zeek/icmp-tunnel.zeek` — sustained large-payload ICMP echo to one external host
  (T1095).
- `zeek/tls-c2.zeek` — encrypted C2 (T1573.002): a self-signed-cert-to-external
  behavioral hunt (always-on) for the unknown-implant case, plus a pointer to the opt-in
  JA3 fast path below.
- `zeek/tls-c2-ja3.zeek` — **opt-in** JA3 known-implant match (T1573.002). Needs the ja3
  add-on package; its blocklist is data in `zeek/ja3-c2-feed.zeek` (generated).
- `suricata/c2.rules` — the fast-path signatures: encoded/oversized DNS labels
  (T1071.004), oversized ICMP echo (T1095), and a feed-driven JA3 `dataset` rule
  (T1573.002, ships commented — `ja3.hash` needs ja3 enabled in suricata.yaml).

**JA3 feed** — the known-implant fingerprints rotate, so they aren't hard-coded.
[`update-ja3-feed.sh`](network/update-ja3-feed.sh) pulls a maintained feed (abuse.ch
SSLBL JA3 by default; `--url` / `--from-file` to override) and regenerates both engines'
data: `zeek/ja3-c2-feed.zeek` (a `redef` fragment `@load`'d by `tls-c2-ja3.zeek`) and
`suricata/ja3-c2.lst` (base64 `dataset` entries). Deterministic output (dedup + sort),
bash 3.2-safe; run it on a schedule and commit the diff. An empty feed matches nothing,
so nothing goes stale or false-positives — the same discipline as the `DEPLOY-REQUIRED`
placeholders.

### `siem/` — deployable backend forms

- **`splunk/savedsearches.generated.conf`** — GENERATED. Every rule in `sigma/`
  compiled to its Splunk `savedsearches` deploy stanza by `gen-siem.sh`
  (Windows dirs through the `splunk_windows` TA pipeline, non-Windows dirs raw), and
  drift-gated in CI via `gen-siem.sh --check`. This is the "real pipeline" the note
  above promised: edit a rule → `gen-siem.sh` → commit both. Do not hand-edit it.
- **`sentinel/rules.generated.kql`** — GENERATED. Every rule as a Microsoft Sentinel
  KQL query (`kusto` backend), one per rule, by the same `gen-siem.sh` (drift-gated).
- **`elastic/rules.generated.lucene`** — GENERATED. Every rule as an Elasticsearch
  Lucene query (`lucene` backend), one per rule, by the same `gen-siem.sh` (drift-gated).
- **`splunk/savedsearches.conf`** — HAND. Five single-event rules with hand-tuned
  enrichment (stats correlation, per-search schedules/severities/`action.notable`)
  the bare `savedsearches` format doesn't emit — kept as the worked, richer example.
- **`splunk/correlation_searches.conf`** — the three *absence/join-based* detections
  Sigma can't express — **Golden Ticket** (4769-without-4768, T1558.001), **Silver
  Ticket** (4624-without-4769, T1558.002), and **NTLM relay** (4624 workstation/source
  mismatch, T1557.001) — as deployable Splunk saved searches. **These are covered
  detections that the `navigator/COVERAGE.md` roll-up does not count** — that report is
  generated from the Sigma tree only, so T1558.001/.002 and T1557.001 read as "0" there
  despite being instrumented here. Read the coverage report as *Sigma* coverage, not
  total. (T1557.001 was renamed by MITRE to "Name Resolution Poisoning and SMB Relay";
  T1558 has since gained a `.005` Ccache Files sub-technique, not yet instrumented.)
- **`sentinel/*.yaml`** — Microsoft Sentinel scheduled-analytics-rule deploy forms
  of the Entra cloud detections (illicit consent grant, SP credential backdoor,
  device-code sign-in). The AWS/GCP cloud rules deploy in their native consoles
  (CloudTrail/Athena, GCP Logging) or via Sentinel's AWS/GCP connectors.

### `navigator/` — ATT&CK coverage heatmap + report

- **`coverage-layer.json`** — GENERATED. A MITRE ATT&CK Navigator layer rolled up from
  every rule's `attack.*` tags by `gen-navigator.sh`, drift-gated in CI via
  `gen-navigator.sh --check`. Load it into the
  [ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator/) (Open Existing
  Layer → Upload) to see the corpus's coverage on the matrix: each covered technique is
  scored by how many rules detect it (gradient white→blue) and commented with the rule
  names. Edit a rule's tags → `gen-navigator.sh` → commit both.
- **`COVERAGE.md`** — GENERATED. The human-readable companion: a Markdown roll-up of the
  same tags **by ATT&CK tactic, by technique, and by logsource** (with the headline
  rule/technique/tactic/logsource counts), emitted by `gen-coverage.sh` and drift-gated
  via `gen-coverage.sh --check`. Read it in the repo to see coverage at a glance without
  loading the Navigator. Edit a rule's tags → `gen-coverage.sh` → commit both.

## Coverage gaps (honest notes)

- **Golden Ticket** (4769-without-4768), **Silver Ticket** (Kerberos logon
  without a matching 4769), and **NTLM relay** (4624 workstation mismatch) are all
  *absence*/join-based — they detect the lack of an expected event or a field-to-
  field comparison, which Sigma can't express cleanly. They now ship as **deployable
  Splunk correlation searches** in `siem/splunk/correlation_searches.conf` (and as
  SPL in Kali's `PURPLE-TEAM.md` via their htpx pairs). For Silver Ticket the
  durable control remains PAC validation.
- The **AWS/GCP** Sigma rules are broad event surfaces by design — the backdoor
  invariant (actor ≠ target) is a field-to-field comparison left to backend triage,
  same as the ADCS ESC1 and Entra-consent rules.
- Field names assume the Splunk Windows TA / Sysmon schema; normalize to your CIM
  before relying on them.
