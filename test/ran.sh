#!/usr/bin/env bash
# The full runs recorded against REF's tree (HEAD by default), oldest first:
# commit, runner, date, time, and last line. test/queue.sh records a run of
# test/all.sh or test/review.sh that began and ended on a clean tree, so a
# record vouches for exactly that tree: a merge commit holding the same tree
# is covered, and a rebase that changed anything is not. Exits 1 when no run
# is recorded for it.
#
# With --passed RUNNER, it prints nothing and says only whether RUNNER ended
# ALL PASS on REF's tree since the last package change, the rule
# test/queue.sh runs by, which a deploy can go by too.
#
#   test/ran.sh                         this checkout's HEAD
#   test/ran.sh origin/BRANCH           a pushed branch's head
#   test/ran.sh --passed RUNNER [REF]   test/all.sh or test/review.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
runner=""
if [ "${1:-}" = --passed ]; then runner=${2:?usage: test/ran.sh --passed RUNNER [REF]}; shift 2; fi
ref=${1:-HEAD}
tree=$(git rev-parse "$ref^{tree}")
runs="$(git rev-parse --path-format=absolute --git-common-dir)/stonks-runs"
if [ -n "$runner" ]; then
  at=$(grep "^$tree [^ ]* $runner .* ALL PASS$" "$runs" 2> /dev/null | tail -n 1 | cut -d' ' -f4 || true)
  updated=$(stat -c %Y /var/lib/pacman/local 2> /dev/null || echo 0)
  [ -n "$at" ] && [ "$(date -d "$at" +%s)" -gt "$updated" ] && exit 0
  echo "no $runner pass recorded for $ref's tree ($tree) since the last package change" >&2
  exit 1
fi
grep "^$tree " "$runs" 2> /dev/null | cut -d' ' -f2- && exit 0
echo "no run recorded for $ref's tree ($tree)" >&2
exit 1
