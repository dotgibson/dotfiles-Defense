# Fleet auth: retiring the cross-repo PATs with a GitHub App (G2)

This is the runbook for replacing the two broad, silently-expiring Personal Access
Tokens the fleet's automation depends on with a **GitHub App** that mints
**short-lived, per-repo-scoped installation tokens** at run time. It is written so the
repo owner can execute it end to end — the App registration and the private-key
handling are owner actions that cannot be automated from CI.

**Status: shipped.** Every consumer mints App tokens (verified live), both PATs are deleted,
and the `token-health` probe that guarded their expiry has been retired — a minted token
lives ~1 hour and cannot silently expire, so there was nothing left for it to watch. This
document is retained as the reference for how the auth works and how to extend it.

## What we are replacing, and why

Two secrets are long-lived PATs with broad scope and no automatic rotation:

| Secret | Used by | What it authorises today |
| --- | --- | --- |
| `FLEET_SYNC_TOKEN` | `dotfiles-core` `sync-fanout.yml`, `htpx` `sync-fanout.yml` | Clone another repo, push a `sync/…` branch, and open a PR (contents + pull-requests **write** on the OS repos and `dotfiles-Kali`). |
| `WEBHOOK_SECRET` | every source repo's `notify-web.yml` (via `notify-web-call.yml`) | A `Bearer` token POSTing a `repository_dispatch` to `dotfiles-web` to trigger a docs rebuild (contents **write** on `dotfiles-web`). |

Both are the same anti-pattern: a **single broad token**, held as a secret in many
repos, that expires on a date nobody is watching (the failure G2 closes). A GitHub App
fixes all three problems at once — tokens are **minted per run**, **scoped to just the
target repo(s) and permissions** each job needs, and **expire in ~1 hour**, so a leak or
a missed rotation is bounded.

## Step 1 — register the App (owner action, one time)

In **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**:

- **Name:** `dotgibson-fleet-sync` (any unique name).
- **Homepage URL:** the org URL (unused, but required).
- **Webhook:** **uncheck** "Active" — this App is used only to mint tokens, it receives
  no events.
- **Repository permissions** (least privilege — grant only these):
  - **Contents: Read and write** — the `git push` of the sync branch, and the
    `repository_dispatch` POST both require it.
  - **Pull requests: Read and write** — `gh pr create` for the fan-out PRs.
  - Everything else: **No access**.
- **Where can this App be installed?** **Only on this account.**

Create it, then note the **App ID** (shown on the App's page). Under **Private keys**,
**Generate a private key** and download the `.pem` — you will paste its contents into a
secret in Step 3. Store the `.pem` in your password manager and delete the download.

## Step 2 — install the App on the target repos

On the App's page → **Install App** → install on **`dotgibson`**, and select **only the
repos that RECEIVE cross-repo writes**:

- The Core-vendoring OS repos + `dotfiles-Kali` (targets of `dotfiles-core`'s fan-out).
- `dotfiles-Kali` (target of `htpx`'s companion fan-out — already in the list above).
- `dotfiles-web` (target of the `notify-web` dispatch).
- **`dotfiles-core`** — for its own **self-PRs**: `freshness.yml` opens a pin-bump PR *in
  Core*, and a PR opened by `GITHUB_TOKEN` has its CI held at `action_required` (GitHub's
  recursion guard). Installing the App here lets freshness open that PR as the App bot, so
  its CI runs without a manual "Approve and run". Without this install the mint step is
  skipped/fails and freshness falls back to `GITHUB_TOKEN` — the PR still opens, it just
  needs the one-click approval. (Core is the one repo that is both a *source* and a *target*.)

Aside from that one self-PR case, the App does **not** need to be installed on the *source*
repos (`htpx`, and `dotfiles-core` for its *fan-out* minting) — those only mint tokens whose
reach is decided by the installation on the *other* repos.

## Step 3 — store the credentials on the source repos

The **minting** happens in `dotfiles-core` and `htpx` (and, for `notify-web`, in every
source repo that dispatches). On each repo that runs a workflow which mints a token, set:

- **Variable** (not secret — the App ID is not sensitive): `FLEET_APP_ID` = the App ID
  from Step 1. Repo → Settings → Secrets and variables → Actions → **Variables**.
- **Secret**: `FLEET_APP_PRIVATE_KEY` = the **full contents** of the `.pem` (including the
  `-----BEGIN/END-----` lines). Repo → Settings → Secrets and variables → Actions →
  **Secrets**.

Using a *variable* for the App ID is deliberate: variables are readable in a job `if:`,
which is what makes the migration backward-compatible (Step 4).

## Step 4 — the workflow pattern (backward-compatible)

Replace each `secrets.FLEET_SYNC_TOKEN` / `secrets.WEBHOOK_SECRET` use with a minted
token, **falling back to the legacy PAT** so the change is inert until the App is
configured. Mint with the first-party **`actions/create-github-app-token`** action —
which, like every external action, must be **pinned to a 40-hex commit SHA** (the
modernization floor; `actions/` is not the fleet's exempt owner). Resolve the SHA for the
latest release yourself — the CI environment cannot reach the Actions API to look it up:

```sh
gh api repos/actions/create-github-app-token/git/refs/tags/v2 --jq .object.sha
# (dereference to the commit if it returns an annotated-tag object)
```

Then, in the job:

```yaml
    steps:
      # Mint a short-lived token scoped to JUST the target repo — only when the App is
      # configured (vars are readable in `if:`; secrets are not). No App yet → skipped,
      # and the job falls back to the legacy PAT below, so merging this changes nothing
      # until you complete Steps 1-3.
      - name: Mint a scoped installation token
        id: app
        if: ${{ vars.FLEET_APP_ID != '' }}
        uses: actions/create-github-app-token@<PIN-40-HEX-SHA> # vX.Y.Z
        with:
          app-id: ${{ vars.FLEET_APP_ID }}
          private-key: ${{ secrets.FLEET_APP_PRIVATE_KEY }}
          owner: ${{ github.repository_owner }}
          repositories: dotfiles-Kali # scope to the one target this job writes to

      # ... then wherever the job used the PAT, prefer the minted token:
      #   env:
      #     GH_TOKEN: ${{ steps.app.outputs.token || secrets.FLEET_SYNC_TOKEN }}
      # and for the git credential rewrite (GIT_CONFIG_VALUE_0 etc.), use the same
      # `${{ steps.app.outputs.token || secrets.FLEET_SYNC_TOKEN }}` expression.
```

Prefer the `||` expression **inline in `env:`** rather than writing the token to
`$GITHUB_OUTPUT` — a token in an output can surface in logs; a secret in `env` is masked.

## Step 5 — migrate the consumers, verify, then retire the PATs

Roll it out one consumer at a time, canary first, verifying a real run each time:

1. **`dotfiles-core/.github/workflows/sync-fanout.yml`** — the reference case (lives here;
   `make audit` / `check-modern.sh` validate the pinned action). Scope `repositories:` to
   the OS repo(s) a given run targets.
2. **`htpx/.github/workflows/sync-fanout.yml`** — same pattern, `repositories: dotfiles-Kali`.
3. **`notify-web-call.yml`** (reusable) — mint a `dotfiles-web`-scoped token and use it as
   the `Bearer` for the `dispatches` POST; drop the `WEBHOOK_SECRET` secret input. Fan the
   caller change out to every source repo's `notify-web.yml`.

**Verify** after each: trigger the workflow (a real fan-out / a `refresh` dispatch) and
confirm the cross-repo write still lands. Because the token is minted per run and scoped to
the target, the repo/org **audit log** shows exactly what it did (the App has no webhook —
Step 1 — so there are no "recent deliveries" to consult, and minting a token via the REST
API generates none regardless).

**Retire** once every consumer is migrated and green: delete the `FLEET_SYNC_TOKEN` and
`WEBHOOK_SECRET` secrets from all repos, remove the `|| secrets.…` fallbacks (and the
`WEBHOOK_SECRET` inputs) in a follow-up, and drop the `token-health.yml` probe — a minted
token cannot silently expire, so the probe it guarded against is no longer needed.

**Rollback** at any point: unset `FLEET_APP_ID`. Every job falls straight back to the
legacy PAT (still present until the retire step), with zero code changes.
