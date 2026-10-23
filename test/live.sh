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
#   test/live.sh BRANCH-OR-COMMIT
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
live="$HOME/.config/omarchy/plugins/grvc.stonks"
ref="${1:?usage: test/live.sh <branch-or-commit>}"
refuse() { echo "refusing: $*" >&2; exit 1; }
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
git -C "$live" checkout --quiet --detach "$commit"
omarchy restart shell
echo "live: $(git -C "$live" log -1 --oneline)"
