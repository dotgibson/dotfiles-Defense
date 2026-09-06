#!/usr/bin/env bash
# check-closing-refs.sh — does this PR close an issue its own body says it must not?
#
# WHY THIS EXISTS, AND WHY IT IS NOT A LINTER FOR PROSE.
#
# dotgibson/dotfiles-Defense#246 has been auto-closed twice by merging PRs that opened with a
# disclaimer saying they closed nothing:
#
#   #253 — `Closes nothing. **#246 stays open**`
#   #269 — `**Closes nothing.** #246 is blocked on a Windows host`
#
# Both were squash-merged and both closed #246. The first reopen blamed the branch name;
# #269 was then deliberately branched with no issue number in it and closed #246 anyway, which
# is what settled the cause: GitHub's linked-issue parser reads the closing keyword and the
# issue number and files a reference. THE DISCLAIMER IS WHAT PERFORMS THE CLOSE. Writing it
# more emphatically each time makes it worse.
#
# So this gate does NOT try to reimplement that parser or grade the wording. It asks GitHub
# what the PR will actually close — `closingIssuesReferences`, the same field the reopen
# comment used to prove the link — and fails only when that answer CONTRADICTS the body. A
# contradiction is unambiguous and cannot be argued with: the PR says it closes nothing, and
# GitHub says it closes #246. One of the two is wrong before the merge, not after.
#
# NOTE ON PHRASING, because the advice recorded in #246 is not safe as written. That comment
# suggests "does not close #246". #269 is the measurement against it: GitHub matched `Closes`
# to `#246` ACROSS the intervening words "nothing." and a bold marker. A parser that spans
# that gap will certainly match "close #246" when the two are adjacent, so the negation buys
# nothing. Lead with the number instead — `#246 stays open` — so no closing keyword precedes
# the reference at all. This gate accepts either, because it judges the outcome rather than
# the sentence; the recommendation is here so the next author does not have to rediscover it.
#
# Hermetic and offline by design: the caller does the one API query and passes the answer in,
# so the whole decision is testable from tests/test-defense.sh with no network and no PR.
#
# Usage:
#   check-closing-refs.sh <body-file> [issue-number...]
#
#   <body-file>      the PR body, verbatim, as a file. Passed as a FILE and never as an
#                    argument or an interpolated string: a PR body is attacker-controlled
#                    text, and `run: echo ${{ github.event.pull_request.body }}` is a shell
#                    injection in a repo that would have opinions about shipping one.
#   issue-number...  what `closingIssuesReferences` reported, one per argument. None means
#                    the PR closes nothing and the gate is vacuously green.
#
# Exit codes: 0 pass · 1 contradiction · 2 usage.

set -uo pipefail

die() {
  printf 'check-closing-refs: %s\n' "$1" >&2
  exit 2
}

[ $# -ge 1 ] || die "usage: check-closing-refs.sh <body-file> [issue-number...]"

body_file="$1"
shift
[ -f "$body_file" ] || die "no such body file: $body_file"

# No closing references means there is nothing to contradict. Say so out loud rather than
# exiting silently — a gate whose green is indistinguishable from a gate that did not run is
# the failure mode htpx-drift.yml's header is about.
if [ $# -eq 0 ]; then
  echo "closing references: none — this PR closes no issue. Nothing to check."
  exit 0
fi

echo "closing references reported by GitHub: $*"
echo

# Normalise before matching, so emphasis and link syntax cannot hide a disclaimer:
#   • lowercase                          — `Closes Nothing` is the same claim
#   • issue URLs collapse to #N          — a full link is the same reference
#   • strip * _ and `                    — `**Closes nothing.**` must read as `closes nothing.`
#                                          A markdown-escaped `\#246` needs no handling: the
#                                          reference still matches inside it, and an escaped
#                                          one files no closing reference to contradict.
#   • collapse all whitespace to spaces  — the two halves are often on different lines, which
#                                          is exactly how #269's disclaimer was written
normalised="$(
  tr '[:upper:]' '[:lower:]' <"$body_file" |
    sed -E 's%https?://github\.com/[^/[:space:]]+/[^/[:space:]]+/issues/([0-9]+)%#\1%g' |
    tr -d '*_`' |
    tr -s '[:space:]' ' '
)"

# A blanket disclaimer: the body claims it closes nothing at all, so EVERY reported
# reference contradicts it. This is the shape that bit twice.
blanket_re='(close|closes|closed|closing|fix|fixes|fixed|resolve|resolves|resolved) (nothing|no issue|no issues)'
blanket=0
if printf '%s' "$normalised" | grep -Eq -- "$blanket_re"; then
  blanket=1
fi

violations=""
for n in "$@"; do
  case "$n" in
  '' | *[!0-9]*) die "not an issue number: $n" ;;
  esac

  if [ "$blanket" -eq 1 ]; then
    violations="$violations $n"
    continue
  fi

  # A targeted disclaimer naming this issue. Two shapes, matching how people actually write
  # it: the negation before the number, and the number leading its own clause.
  #  \#N([^0-9]|$) keeps #246 from matching #2467.
  targeted_re="(does not|doesn't|do not|don't|will not|won't|must not|should not|shall not|cannot|can't|never) (close|closes|closing|fix|fixes|resolve|resolves) #${n}([^0-9]|$)"
  #  [^#]{0,60} rather than .{0,60}: the window must not cross another issue reference, or
  #  "closes #300. #246 stays open." reads the #246 clause as a disclaimer about #300.
  targeted_re="${targeted_re}|#${n}([^0-9]|\$)[^#]{0,60}(stays open|remains open|stays blocked|remains blocked|is not closed|is still open|must stay open|must remain open)"
  if printf '%s' "$normalised" | grep -Eq -- "$targeted_re"; then
    violations="$violations $n"
  fi
done

if [ -z "$violations" ]; then
  echo "PASS — the body does not disclaim any of the issues this PR will close."
  exit 0
fi

cat >&2 <<MSG
FAIL — this PR would close an issue its own body says it must not close.

  contradicted:$violations

GitHub reports these in closingIssuesReferences, so merging this PR CLOSES them, whatever the
body says about it. This has happened twice to #246 (via #253 and #269), and both times the
disclaimer itself was what performed the close: the linked-issue parser reads the closing
keyword and the issue number and does no negation analysis.

To fix it, remove the closing keyword from ahead of the reference — do not reword the
disclaimer, which is what failed the last two times:

  NO   Closes nothing. #246 is blocked on a Windows host
  NO   This does not close #246                  <- keyword still adjacent to the number
  YES  #246 stays open — it is blocked on a Windows host
  YES  Leaves #246 open; see the runbook for what unblocks it

Then confirm the link is gone BEFORE merging, rather than reopening afterwards:

  gh api graphql -f query='{repository(owner:"dotgibson",name:"dotfiles-Defense")
    {pullRequest(number:NNN){closingIssuesReferences(first:10){nodes{number}}}}}'

If the PR is genuinely meant to close one of these, delete the disclaimer instead.
MSG
exit 1
