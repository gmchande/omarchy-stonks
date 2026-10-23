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
# It checks out and restarts holding the tophat lock alone (test/tophat.sh),
# so no tophat session runs through a restart, whose stop would find the
# owner's session changed. It waits up to 20 minutes for the sessions
# running to end, holding the gate meanwhile so no new one starts, and
# refuses after that, changing nothing. It lets go once the restarted
# shell's services are back, even when the restart failed: each fact
# test/host-facts.sh prints names as many things as before the restart.
# When they aren't back within a minute, it says which aren't and exits 1,
# the commit checked out.
#
#   test/live.sh BRANCH-OR-COMMIT
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
live="$HOME/.config/omarchy/plugins/grvc.stonks"
ref="${1:?usage: test/live.sh <branch-or-commit>}"
refuse() { echo "refusing: $*" >&2; exit 1; }
lock=${TOPHAT_LOCK:-${XDG_RUNTIME_DIR:-/run/user/$UID}/tophat.lock}
gate=${lock%.lock}.gate
patience=${LIVE_WAIT:-1200}
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

# Fd 7 holds the gate and fd 8 the tophat lock; nothing started here keeps them.
exec 7>> "$gate" 8>> "$lock"
if ! { flock -n 7 && flock -n 8; }; then
  echo "live: waiting up to $((patience / 60)) minutes for the tophat sessions running to end; no new one starts meanwhile"
  end=$((SECONDS + patience))
  left() { echo $((end > SECONDS ? end - SECONDS : 0)); }
  flock -w "$(left)" 7 && flock -w "$(left)" 8 \
    || refuse "tophat sessions kept the shell from restarting for $((patience / 60)) minutes, so ${commit:0:7} isn't live; nothing changed"
fi
before=$("$here/host-facts.sh" 7>&- 8>&-)
git -C "$live" checkout --quiet --detach "$commit" 7>&- 8>&-
# A restart that fails may have started the new shell all the same, so its
# services are waited for either way, and its failure is the exit.
restarted=0
omarchy restart shell 7>&- 8>&- || restarted=$?
# counts: how many words each fact has, its name's included.
counts() { awk '{ print NF }'; }
end=$((SECONDS + 60))
until [ "$("$here/host-facts.sh" 7>&- 8>&- | counts)" = "$(counts <<< "$before")" ]; do
  if (( SECONDS >= end )); then
    echo "live: the restarted shell's services aren't all back a minute on; before the restart, and now:" >&2
    diff <(echo "$before") <("$here/host-facts.sh" 7>&- 8>&-) | grep '^[<>]' >&2 || true
    echo "live: $(git -C "$live" log -1 --oneline)"
    exit 1
  fi
  sleep 0.5
done
echo "live: $(git -C "$live" log -1 --oneline)"
exit "$restarted"
