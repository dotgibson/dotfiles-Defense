#!/usr/bin/env bash
# scripts/fleet-protection.sh
# ──────────────────────────────────────────────────────────────────────────────
# FLEET BRANCH-PROTECTION CHECK — does a RULESET actually bind `main` everywhere?
#
# GitHub has two protection systems and they do not behave the same way:
#   • CLASSIC branch protection honours `enforce_admins`. Every repo in this fleet
#     had it set to FALSE, so classic protection never bound an admin — the required
#     checks were advisory for the only person pushing.
#   • RULESETS bind everyone unless a `bypass_actors` entry says otherwise.
#
# That difference was invisible until it bit: a Core fan-out was pushed straight to
# `main` on dotfiles-Debian (no ruleset at all — classic only) and dotfiles-Gentoo
# (ruleset present, but carrying a `RepositoryRole:5` bypass at `always`), landing
# unreviewed with no CI, while the other seven repos correctly demanded a PR.
#
# Worse, the two systems had DIVERGED. Nine of ten rulesets were strict subsets of
# their classic config — `lint / secret scan (gitleaks)` was classic-only in seven —
# so "retire classic, keep rulesets" would silently have dropped the secret-scanning
# gate fleet-wide. This script is the check that would have caught all of it.
#
# It is a REPORTER by default and never writes. `--migrate` copies any classic-only
# required check INTO the ruleset (idempotent); `--retire` additionally deletes the
# classic config, but ONLY after re-reading the ruleset from the server and proving
# coverage. A repo whose ruleset is still short keeps its classic config and is
# reported red — the script will not trade a real gate for a tidy one.
#
# Ruleset selection is by TARGET + CONDITION, never by name: the fleet calls the same
# thing `First`, `Second` and `main-protection`, and matching on name silently skips
# whichever repo disagrees with your guess (it skipped dotfiles-MacBook when written
# that way). Requires an authenticated `gh` with repo admin; needs no local checkout.
#
# NOTE: this file deliberately avoids the variable names UID/EUID/GID/EGID. Those are
# special parameters in zsh, and assigning to `GID` calls setgid(2) — which fails as
# "zsh: failed to change group ID: operation not permitted" and looks like a broken
# machine rather than a broken variable name.
#
#   ./scripts/fleet-protection.sh             report only (default; writes nothing)
#   ./scripts/fleet-protection.sh --migrate   copy classic-only checks into rulesets
#   ./scripts/fleet-protection.sh --retire    migrate, verify, then delete classic
#   ./scripts/fleet-protection.sh --rulesets-only
#                                             check rulesets only, skipping the classic
#                                             probe — for CI, whose GITHUB_TOKEN has no
#                                             admin. Rulesets ARE publicly readable, so
#                                             this needs no privileged token at all.
#
set -uo pipefail

REPOS=(dotfiles-MacBook dotfiles-Alpine dotfiles-Arch dotfiles-Debian dotfiles-Defense
       dotfiles-Fedora dotfiles-Gentoo dotfiles-Offense dotfiles-openSUSE dotfiles-core)
ORG=dotgibson
ACTIONS_APP_ID=15368   # GitHub Actions — the app that reports every check in this fleet

MODE=report
SKIP_CLASSIC=0
for arg in "$@"; do
  case "$arg" in
    --migrate)       MODE=migrate ;;
    --retire)        MODE=retire  ;;
    --rulesets-only) SKIP_CLASSIC=1 ;;
    -h|--help)       sed -n '2,46p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done
if (( SKIP_CLASSIC )) && [[ "$MODE" != report ]]; then
  echo "--rulesets-only is report-only: migrating needs to READ classic protection" >&2; exit 2
fi

command -v gh >/dev/null || { echo "gh not installed" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }

# The id of the ruleset governing the default branch, by target+condition (never by
# name — the fleet calls the same thing First/Second/main-protection).
#
# Prints the id on stdout. Exit 0 = answered (id, or empty for "none governs main");
# exit 3 = COULD NOT READ. Those must stay separable: collapsing them makes an
# unreadable repo indistinguishable from an unprotected one, which is the same
# can't-see-vs-not-there confusion this script exists to catch, merely inverted.
main_ruleset() {
  local body ids id
  body="$(gh api "repos/$ORG/$1/rulesets" 2>/dev/null)" || return 3
  ids="$(jq -r '.[].id' <<<"$body" 2>/dev/null)" || return 3
  for id in $ids; do
    gh api "repos/$ORG/$1/rulesets/$id" --jq '
      select(.target == "branch"
             and ((.conditions.ref_name.include // [])
                  | any(. == "~DEFAULT_BRANCH" or . == "refs/heads/main")))
      | .id' 2>/dev/null
  done | head -1
}

rc=0
for repo in "${REPOS[@]}"; do
  if ! rs_id="$(main_ruleset "$repo")"; then
    echo "✗ $repo: CANNOT READ rulesets — this is 'could not check', not 'checked and clean'."
    echo "      Is gh authenticated? (\`gh auth status\`). In CI set GH_TOKEN."
    rc=1; continue
  fi
  if [[ -z "$rs_id" ]]; then
    echo "✗ $repo: NO ruleset governs main — classic protection alone does not bind admins"
    rc=1; continue
  fi

  if ! rs="$(gh api "repos/$ORG/$repo/rulesets/$rs_id" 2>/dev/null)"; then
    echo "✗ $repo: cannot read ruleset $rs_id — not treating that as a pass"; rc=1; continue
  fi
  bypass="$(jq '.bypass_actors | length' <<<"$rs")"
  have="$(jq '[.rules[] | select(.type=="required_status_checks")
               | .parameters.required_status_checks[].context]' <<<"$rs")"
  # Probe for classic protection FIRST, and DISTINGUISH ITS FAILURES. On a repo where it
  # is absent `gh api` prints a 404 body to STDOUT, so a `|| echo '[]'` fallback yields
  # two concatenated JSON docs and every later --argjson dies.
  #
  # The sharper trap: reading classic protection needs ADMIN, and without it the API
  # answers 401/403 — which a bare `if gh api …; then` reads as "no classic protection
  # here", reporting a cheerful ✓ for a repo it cannot actually see. That is
  # green-because-absent, the failure this whole script exists to catch, so a probe that
  # cannot see is a HARD ERROR and never a pass. `gh` puts the code in .status on the
  # error body, which is what makes 404 (genuinely absent) separable from 401/403 (blind).
  if (( SKIP_CLASSIC )); then
    has_classic=0; classic='[]'
  elif classic_body="$(gh api "repos/$ORG/$repo/branches/main/protection" 2>/dev/null)"; then
    has_classic=1
    classic="$(jq '[.required_status_checks.contexts[]?]' <<<"$classic_body")"
  else
    case "$(jq -r '.status // empty' <<<"${classic_body:-{\}}" 2>/dev/null)" in
      404) has_classic=0; classic='[]' ;;
      *)   echo "✗ $repo: cannot read classic branch protection ($(jq -r '.message // "unknown error"' <<<"${classic_body:-{\}}" 2>/dev/null))."
           echo "      Needs a token with repo ADMIN. Re-run with --rulesets-only to check rulesets alone."
           rc=1; continue ;;
    esac
  fi
  missing="$(jq -n --argjson c "$classic" --argjson u "$have" '$c - $u')"
  n_missing="$(jq length <<<"$missing")"

  if (( bypass > 0 )); then
    echo "✗ $repo: ruleset $rs_id has $bypass bypass actor(s) — admins can push straight to main"
    jq -r '.bypass_actors[] | "      \(.actor_type):\(.actor_id) (\(.bypass_mode))"' <<<"$rs"
    rc=1
  fi

  if [[ "$MODE" == report ]]; then
    printf '%s %-20s ruleset=%-9s checks=%-3s classic=%-8s classic_only=%s\n' \
      "$( (( n_missing == 0 && bypass == 0 )) && echo '✓' || echo '✗' )" \
      "$repo" "$rs_id" "$(jq length <<<"$have")" \
      "$( (( has_classic )) && echo present || echo retired )" "$n_missing"
    (( n_missing > 0 )) && { jq -r '.[] | "      only in classic: " + .' <<<"$missing"; rc=1; }
    continue
  fi

  if (( n_missing > 0 )); then
    echo "→ $repo: adding $n_missing classic-only check(s) to ruleset $rs_id"
    jq -r '.[] | "      + " + .' <<<"$missing"
    if jq --argjson m "$missing" --argjson app "$ACTIONS_APP_ID" '
          {name, target, enforcement, conditions, bypass_actors,
           rules: [.rules[]
                   | if .type == "required_status_checks"
                     then .parameters.required_status_checks
                            += [$m[] | {context: ., integration_id: $app}]
                     else . end]}' <<<"$rs" \
       | gh api -X PUT "repos/$ORG/$repo/rulesets/$rs_id" --input - >/dev/null; then
      echo "    ✓ ruleset updated"
    else
      echo "    ✗ UPDATE FAILED — classic left in place"; rc=1; continue
    fi
  else
    echo "✓ $repo: ruleset already covers every classic check"
  fi

  # Prove coverage from the SERVER before anything is deleted.
  after="$(gh api "repos/$ORG/$repo/rulesets/$rs_id" \
             --jq '[.rules[] | select(.type=="required_status_checks")
                    | .parameters.required_status_checks[].context]')"
  still="$(jq -n --argjson c "$classic" --argjson u "$after" '$c - $u')"
  if [[ "$(jq length <<<"$still")" != 0 ]]; then
    echo "    ✗ still missing $(jq -c . <<<"$still") — NOT retiring classic"; rc=1; continue
  fi

  if [[ "$MODE" == retire ]] && (( has_classic )); then
    if gh api -X DELETE "repos/$ORG/$repo/branches/main/protection" >/dev/null 2>&1; then
      echo "    ✓ classic protection retired"
    else
      echo "    ✗ could not delete classic protection"; rc=1
    fi
  fi
done

exit "$rc"
