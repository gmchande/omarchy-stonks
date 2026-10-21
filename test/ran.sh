#!/usr/bin/env bash
# The full runs recorded against REF's tree (HEAD by default), oldest first:
# commit, runner, date, time, and last line. test/queue.sh records a run of
# test/all.sh or test/review.sh that began and ended on a clean tree, so a
# record vouches for exactly that tree: a merge commit holding the same tree
# is covered, and a rebase that changed anything is not. Exits 1 when no run
# is recorded for it.
#
#   test/ran.sh                 this checkout's HEAD
#   test/ran.sh origin/BRANCH   a pushed branch's head
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ref=${1:-HEAD}
tree=$(git rev-parse "$ref^{tree}")
runs="$(git rev-parse --path-format=absolute --git-common-dir)/stonks-runs"
grep "^$tree " "$runs" 2> /dev/null | cut -d' ' -f2- && exit 0
echo "no run recorded for $ref's tree ($tree)" >&2
exit 1
