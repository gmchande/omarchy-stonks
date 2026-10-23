#!/usr/bin/env bash
# Deploy a committed ref to the live plugin worktree, restart the shell, and
# print the commit now live. It refuses:
#
# - a branch behind its upstream, fetched first: a stale branch put live
#   restarts the shell for nothing (22 October);
# - a commit whose tree has no ALL PASS since the last package change
#   (test/ran.sh --passed): test/all.sh always, and test/review.sh too when
#   Stonks' own files, everything outside test/ and .github/
#   (test/render-key.sh), differ from the live commit's.
#
# Tophat sessions run through the restart (test/tophat.sh). It holds the
# tophat lock alone from the facts it reads before the restart to those it
# reads once the restarted shell's services are back, even when the restart
# failed: each fact test/host-facts.sh prints names as many things as
# before. A session reads its facts under a share of the lock, so never
# mid-restart, and its stop finds the change explained in the record this
# leaves of each restart, a folder in tophat.restarts beside the lock named
# for the time the restart began (date +%s%N):
#
#   commit  the commit put live
#   before  the facts before the restart
#   after   the facts once the services were back
#   back    the time they were back (date +%s%N), written last
#
# When the services aren't back within a minute, it says which aren't and
# exits 1, the commit checked out, and the record has no after or back.
# Another restart holding the lock is waited for up to 5 minutes. Records
# over a day old are removed.
#
#   test/live.sh BRANCH-OR-COMMIT
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
live="$HOME/.config/omarchy/plugins/grvc.stonks"
ref="${1:?usage: test/live.sh <branch-or-commit>}"
refuse() { echo "refusing: $*" >&2; exit 1; }
lock=${TOPHAT_LOCK:-${XDG_RUNTIME_DIR:-/run/user/$UID}/tophat.lock}
restarts=${lock%.lock}.restarts
[ -z "$(git -C "$live" status --porcelain)" ] || refuse "$live has local changes"
commit=$(git -C "$live" rev-parse --verify --quiet "$ref^{commit}") || refuse "no such ref: $ref"
if upstream=$(git -C "$live" rev-parse --abbrev-ref --symbolic-full-name "$ref@{upstream}" 2> /dev/null); then
  git -C "$live" fetch --quiet "$(git -C "$live" config "branch.$ref.remote")"
  behind=$(git -C "$live" rev-list --count "$ref..$ref@{upstream}")
  [ "$behind" -eq 0 ] || refuse "$ref is $behind commit(s) behind $upstream: bring it up to date first"
fi
runners=(test/all.sh)
git -C "$live" diff --quiet HEAD "$commit" -- . ':(exclude)test' ':(exclude).github' || runners+=(test/review.sh)
for runner in "${runners[@]}"; do
  "$here/ran.sh" --passed "$runner" "$commit" 2> /dev/null \
    || refuse "${commit:0:7}'s tree has no $runner pass since the last package change (test/ran.sh $commit)"
done

# Fd 8 holds the tophat lock; nothing started here keeps it.
exec 8>> "$lock"
if ! flock -n 8; then
  echo "live: the tophat lock ($lock) is held, by another restart or by a session an older test/tophat.sh started; waiting up to 5 minutes"
  flock -w 300 8 || refuse "the tophat lock was held for 5 minutes, so ${commit:0:7} isn't live; nothing changed"
fi
git -C "$live" checkout --quiet --detach "$commit" 8>&-
began=$(date +%s%N)
record=$restarts/$began
mkdir -p "$record"
for old in "$restarts"/*/; do
  old=$(basename "$old")
  [[ $old =~ ^[0-9]+$ ]] && (( old < began - 86400000000000 )) && rm -rf -- "${restarts:?}/$old"
done
echo "$commit" > "$record/commit"
"$here/host-facts.sh" 8>&- > "$record/before"
# A restart that fails may have started the new shell all the same, so its
# services are waited for either way, and its failure is the exit.
restarted=0
omarchy restart shell 8>&- || restarted=$?
# counts: how many words each fact has, its name's included.
counts() { awk '{ print NF }' "$@"; }
end=$((SECONDS + 60))
until now=$("$here/host-facts.sh" 8>&-); [ "$(counts <<< "$now")" = "$(counts "$record/before")" ]; do
  if (( SECONDS >= end )); then
    echo "live: the restarted shell's services aren't all back a minute on; before the restart, and now:" >&2
    diff "$record/before" - <<< "$now" | grep '^[<>]' >&2 || true
    echo "live: $(git -C "$live" log -1 --oneline)"
    exit 1
  fi
  sleep 0.5
done
echo "$now" > "$record/after"
date +%s%N > "$record/back"
echo "live: $(git -C "$live" log -1 --oneline)"
exit "$restarted"
