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
| `navigator/` | ATT&CK Navigator coverage layer (heatmap)           | generate from `sigma/`                          |

Workflow: write Sigma → convert to your backend → stand up the lab (`siemup`) →
run the matching attack from Kali → confirm it fires → tune → commit rule +
validation note. Real IOC values from cases stay in `~/cases/*/iocs`, never here.

## CI gate — the rules are validated as code

The Sigma rules are gated on every change by `.github/workflows/sigma.yml` (the
repo's `lint.yml` only covers shell). Four hard checks, one advisory:

1. **Structural lint** (hermetic) —
   `sigma check --fail-on-issues -c detections/sigma-validation-config.yml`.
   Catches bad YAML, broken conditions, dangling field refs, duplicate ids/titles,
   bad status/level. `--fail-on-issues` is required — `sigma check` otherwise exits 0
   on validator *issues* (only parse/semantic errors fail it by default). The config
   drops only the two validators that need live MITRE downloads, so the gate never
   flakes on a network hiccup.
2. **Compile** — every rule must compile to a real backend (Splunk) via
   `detections/sigma/convert.sh`. A rule that won't convert isn't deployable.
3. **SIEM deploy-form drift** — `detections/siem/gen-siem.sh --check`. The Splunk
   `savedsearches.generated.conf` deploy artifact is *generated* from the Sigma tree;
   this proves the committed file still matches what the generator emits, so the
   deploy form can't drift by hand (the same idea as htpx's `gen-views.sh --check`).
4. **ATT&CK Navigator drift** — `detections/navigator/gen-navigator.sh --check`. The
   `coverage-layer.json` heatmap is *generated* from the rules' `attack.*` tags; this
   proves the committed layer still matches, so the coverage view can't drift from the
   rules.
5. **ATT&CK-tag validity** — advisory (`continue-on-error`); checks each
   `attack.tXXXX` is a real published technique, but never breaks the build on a
   transient MITRE download failure.

Run it locally (any pySigma backend):

```sh
pip install "sigma-cli==3.0.2" "pysigma-backend-splunk==2.1.0"   # pinned, matching CI
sigma check --fail-on-issues -c detections/sigma-validation-config.yml detections/sigma/   # lint
detections/sigma/convert.sh splunk                                                         # compile → SPL
detections/siem/gen-siem.sh --check                                                        # deploy-form drift
detections/navigator/gen-navigator.sh --check                                              # ATT&CK coverage drift
```

`convert.sh` is the reproducible "Sigma → backend" *compile check*: it compiles each
rule with `--without-pipeline` (raw logical fields). `gen-siem.sh` is the reproducible
"Sigma → **deploy form**" step: it runs the backend's `savedsearches` output format
(Windows dirs through the `splunk_windows` TA pipeline, non-Windows dirs raw) over the
whole tree and writes `siem/splunk/savedsearches.generated.conf` — the deployable
artifact a bare per-rule `convert.sh` doesn't assemble. The other `siem/` forms below
stay hand-wrapped for what the generator can't emit (enriched examples, absence/join
correlations, Sentinel).

## What ships today (the starter pack)

The first content drop mirrors the **htpx red↔blue corpus**: each rule below
detects a technique that `dotfiles-Kali` can execute on demand, so every one is
purple-validatable out of the box.

### `sigma/` — 49 rules / 51 documents, organized by ATT&CK tactic

**`credential_access/`**

| Rule | Event / source | ATT&CK | Validate with (Kali fold · htpx pair) |
| ---- | -------------- | ------ | ------------------------------------- |
| `kerberoasting_rc4_tgs` | 4769 RC4 (0x17) | T1558.003 | Kerberos · kerberoast-getuserspns |
| `asrep_roast_probing_4771` | 4771 0x18 (correlation) | T1558.004 | Kerberos · asreproast-getnpusers |
| `password_spray_4625` | 4625 (value_count correlation) | T1110.003 | Kerberos/Poisoning · password-spray-kerbrute |
| `dcsync_replication_4662` | 4662 replication right | T1003.006 | DCSync/NTDS · dcsync-secretsdump |
| `gpp_cpassword_sysvol_5145` | 5145 SYSVOL prefs XML | T1552.006 | SMB · gpp-cpassword |
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

**`persistence/`**

| Rule | Event / source | ATT&CK | Validate with |
| ---- | -------------- | ------ | ------------- |
| `scheduled_task_suspicious_4698` | 4698 task created | T1053.005 | Persistence · schtask-persist |
| `wmi_event_subscription_consumer` | Sysmon 19/20/21 | T1546.003 | Persistence · wmi-subscription |

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
| `vault_bulk_secret_read` | `read` on `secret/` path (breadth = triage) | T1555 | Vault · vault-secret-exfil |
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

`password_spray` and `asrep_roast_probing` are Sigma **correlation** rules
(a base event + a `value_count` over a window); the rest are single-event
selections. The `cloud/`, `kubernetes/`, `okta/`, `github/`, `registry/`,
`gitlab/`, `vault/`, `terraform/`, `jenkins/`, and `snowflake/` rules are the
non-Windows logsources here
(`product: azure|aws|gcp|kubernetes|okta|github|harbor|gitlab|vault|terraform|jenkins|snowflake`)
and mirror the htpx corpus's companion-only cloud, K8s, Okta, GitHub Actions, Harbor
registry, GitLab CI/CD, HashiCorp Vault, Terraform Cloud, Jenkins, and Snowflake pairs.
The `jenkins/` rules match the Audit Trail plugin's request-URI log line via a `uri`
field (`uri|contains`), scoped to the specific endpoints (e.g. job `configSubmit` is
bound to the `/job/` path so global config submits don't trip it).

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

### `siem/` — deployable backend forms

- **`splunk/savedsearches.generated.conf`** — GENERATED. Every rule in `sigma/`
  compiled to its Splunk `savedsearches` deploy stanza by `gen-siem.sh`
  (Windows dirs through the `splunk_windows` TA pipeline, non-Windows dirs raw), and
  drift-gated in CI via `gen-siem.sh --check`. This is the "real pipeline" the note
  above promised: edit a rule → `gen-siem.sh` → commit both. Do not hand-edit it.
- **`splunk/savedsearches.conf`** — HAND. Five single-event rules with hand-tuned
  enrichment (stats correlation, per-search schedules/severities/`action.notable`)
  the bare `savedsearches` format doesn't emit — kept as the worked, richer example.
- **`splunk/correlation_searches.conf`** — the three *absence/join-based* detections
  Sigma can't express — **Golden Ticket** (4769-without-4768), **Silver Ticket**
  (4624-without-4769), and **NTLM relay** (4624 workstation/source mismatch) — as
  deployable Splunk saved searches. This is the promised next step for the
  coverage-gap items below.
- **`sentinel/*.yaml`** — Microsoft Sentinel scheduled-analytics-rule deploy forms
  of the Entra cloud detections (illicit consent grant, SP credential backdoor,
  device-code sign-in). The AWS/GCP cloud rules deploy in their native consoles
  (CloudTrail/Athena, GCP Logging) or via Sentinel's AWS/GCP connectors.

### `navigator/` — ATT&CK coverage heatmap

- **`coverage-layer.json`** — GENERATED. A MITRE ATT&CK Navigator layer rolled up from
  every rule's `attack.*` tags by `gen-navigator.sh`, drift-gated in CI via
  `gen-navigator.sh --check`. Load it into the
  [ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator/) (Open Existing
  Layer → Upload) to see the corpus's coverage on the matrix: each covered technique is
  scored by how many rules detect it (gradient white→blue) and commented with the rule
  names. Edit a rule's tags → `gen-navigator.sh` → commit both.

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
