#!/usr/bin/env bash
# Merge pull request N into dev and exit 0 only once it has: waited for
# GitHub's answer on whether the pull request can merge, merged it, seen it
# merged, and fast-forwarded the main checkout's dev. A lead chains its next
# steps (closing the builder's tab and branch, marking the work merged) on
# this exit, since a merge that was skipped once looked like a merge that
# happened (23 October, #70: GitHub still answered "unknown", the guard
# skipped the merge, and the next steps ran anyway).
#
# - GitHub answers "unknown" for a while after a push or a merge into the
#   base. It waits up to 2 minutes, asking again, and refuses after that.
#   It refuses at once when the pull request can't merge (conflicts), isn't
#   open, or isn't against dev.
# - It merges with `gh pr merge --merge --match-head-commit SHA
#   --author-email code@gauravchande.com`: SHA is the head the lead last read,
#   given as the second argument; without one, the head GitHub reports when
#   the script starts. GitHub refuses when the head has moved since. It checks
#   the merge commit's author is code@ too: without the email, GitHub signs
#   with the account's other address.
# - It checks the pull request now reads as merged, fetches origin, and
#   fast-forwards dev in the checkout that has it checked out. It refuses
#   before merging when that checkout has uncommitted edits or dev isn't
#   behind origin/dev alone, so the fast-forward can't fail after the merge.
# - It prints the merge commit and whether its tree is the head's. When it
#   isn't, dev holds something the head didn't, and test/batch.sh runs the
#   suites on it; when it is, the passes recorded for the head's tree cover
#   dev (test/ran.sh).
# - It takes test/batch.sh's lock before it checks or merges anything, and
#   holds it until the fast-forward is done. A batch runs the suites in the
#   main checkout, and a fast-forward under a running suite makes it end on
#   a tree that changed under it, which no record covers (23 October). So a
#   merge started during a batch says so and waits, up to 30 minutes
#   (MERGE_BATCH_WAIT, in seconds; a batch takes about 6, more when it
#   bisects), then refuses with nothing merged. The head it merges is the
#   one GitHub reports when the script starts, not after the wait. The
#   checks below run after the wait, since a batch may have moved dev.
#
# It never merges into main, never forces a push, and never deletes a
# branch. Any failure exits non-zero and does nothing more; a failure after
# the merge says the pull request is merged. Each step prints what it did.
#
#   test/merge.sh N [HEAD-SHA]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
email=code@gauravchande.com
patience=${MERGE_WAIT:-120}
poll=${MERGE_POLL:-3}
batch_patience=${MERGE_BATCH_WAIT:-1800}
say() { echo "merge: $*"; }
refuse() { echo "merge: refusing: $*" >&2; exit 1; }

pr=${1:-}
want=${2:-}
[[ $pr =~ ^[0-9]+$ ]] || refuse "usage: test/merge.sh N [HEAD-SHA]"
[[ -z $want || $want =~ ^[0-9a-f]{40}$ ]] || refuse "HEAD-SHA must be the full 40-character commit"

# gh asks origin's repository, never another remote's (history).
if [ -z "${GH_REPO:-}" ]; then
  GH_REPO=$(git remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##') || exit 1
  export GH_REPO
fi

# read_pr: sets state, mergeable, base, head, merged from GitHub's answer.
read_pr() {
  local line
  line=$(gh pr view "$pr" --json state,mergeable,baseRefName,headRefOid,mergeCommit \
    --jq '[.state, .mergeable, .baseRefName, .headRefOid, (.mergeCommit.oid // "")] | join("|")') || return 1
  IFS='|' read -r state mergeable base head merged <<< "$line"
}
if [ -z "$want" ]; then
  read_pr || refuse "can't read pull request #$pr from GitHub"
  want=$head
fi

# Fd 8 holds the batch's lock (test/batch.sh) until this script ends. Fd 7
# holds a share of the merge lock beside it, which tells a batch that finds
# the batch lock taken that a merge holds it (merges never block each other
# on it; the batch lock serializes them). It is taken first, so a merge that
# holds the batch lock always holds its share. The commands below that can
# start a background process (git's gc) run without either (8>&- 7>&-), so
# nothing outlives the merge holding them.
lockdir=$(git rev-parse --path-format=absolute --git-common-dir)
exec 7>> "$lockdir/stonks-merge.lock" 8>> "$lockdir/stonks-batch.lock" || exit 1
flock -s 7 || exit 1
if ! flock -n 8; then
  say "waiting up to ${batch_patience}s for the batch running in this repository to end: a merge would change the checkout its suites run in"
  flock -w "$batch_patience" 8 || refuse "a batch still holds the lock after ${batch_patience}s: nothing merged"
  say "the batch has ended"
fi

# The checkout that has dev checked out, which gets the fast-forward.
main=$(git worktree list --porcelain | awk '/^worktree / { dir = substr($0, 10) } $0 == "branch refs/heads/dev" { print dir; exit }')
[ -n "$main" ] || refuse "no checkout has dev checked out"
[ -z "$(git -C "$main" status --porcelain)" ] || refuse "$main has uncommitted edits or untracked files"
git fetch --quiet origin 7>&- 8>&- || refuse "can't fetch origin"
git merge-base --is-ancestor dev origin/dev || refuse "dev has commits origin/dev doesn't: dev and origin/dev have diverged"

end=$((SECONDS + patience))
while :; do
  read_pr || refuse "can't read pull request #$pr from GitHub"
  want=${want:-$head}
  [ "$state" = OPEN ] || refuse "pull request #$pr is $state, not open"
  [ "$base" = dev ] || refuse "pull request #$pr is against $base: this merges into dev only"
  [ -z "$want" ] || [ "$want" = "$head" ] || refuse "pull request #$pr's head is ${head:0:7}, not ${want:0:7} that you last read"
  case $mergeable in
    MERGEABLE) break ;;
    CONFLICTING) refuse "pull request #$pr conflicts with dev: it can't merge" ;;
    UNKNOWN) ;;
    *) refuse "GitHub says pull request #$pr is $mergeable" ;;
  esac
  [ "$SECONDS" -lt "$end" ] || refuse "GitHub still couldn't say after ${patience}s whether #$pr can merge: nothing merged"
  say "GitHub hasn't yet said whether #$pr can merge; asking again"
  sleep "$poll"
done

gh pr merge "$pr" --merge --match-head-commit "$want" --author-email "$email" 7>&- 8>&- > /dev/null \
  || refuse "gh couldn't merge #$pr at ${want:0:7}: nothing merged"

# From here on the pull request is merged: a failure says so.
broke() { echo "merge: pull request #$pr was merged at ${want:0:7}, but $*" >&2; exit 1; }
end=$((SECONDS + patience))
until read_pr && [ "$state" = MERGED ] && [ -n "$merged" ]; do
  [ "$SECONDS" -lt "$end" ] || broke "GitHub doesn't read it as merged after ${patience}s: look at it before going on"
  sleep "$poll"
done
git fetch --quiet origin 7>&- 8>&- || broke "can't fetch origin: dev is not updated"
git merge-base --is-ancestor "$merged" origin/dev || broke "merge commit ${merged:0:7} isn't on origin/dev"
[ "$(git rev-parse --quiet --verify "$merged^2")" = "$want" ] || broke "merge commit ${merged:0:7} doesn't have ${want:0:7} as its second parent"
[ "$(git log -1 --format=%ae "$merged")" = "$email" ] || broke "merge commit ${merged:0:7} has the author $(git log -1 --format=%ae "$merged"), not $email"
[ "$(git -C "$main" symbolic-ref --quiet --short HEAD)" = dev ] || broke "$main is no longer on dev: nothing fast-forwarded"
git -C "$main" merge --ff-only --quiet origin/dev 7>&- 8>&- || broke "dev in $main didn't fast-forward to origin/dev"
say "merged #$pr: $(git log -1 --format='%h %s' "$merged"); dev in $main is at $(git -C "$main" rev-parse --short HEAD)"
if [ "$(git rev-parse "$merged^{tree}")" = "$(git rev-parse "$want^{tree}")" ]; then
  say "its tree is the head's (${want:0:7}): the suites' passes for it cover dev (test/ran.sh)"
else
  say "its tree is NOT the head's (${want:0:7}): dev holds changes the head lacked; test/batch.sh must run the suites"
fi
