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
# test/queue.sh runs by: test/live.sh and test/batch.sh go by it.
#
# A failed run's record names each step that failed after its last line:
# `SOME FAILED | LABEL | LABEL`. --self-check proves it on a made-up
# checkout with steps that fail, its own lock and record: a run names its
# failed steps, a harness no runner starts fails as "harness wiring", and a
# run test/touched.sh narrowed leaves no record.
#
#   test/ran.sh                         this checkout's HEAD
#   test/ran.sh origin/BRANCH           a pushed branch's head
#   test/ran.sh --passed RUNNER [REF]   test/all.sh or test/review.sh
#   test/ran.sh --self-check
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

self_check() {
  local code=0 last recorded before
  source "$PWD/test/scratch.sh"
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/repo/test/qml" "$work/runtime"
  cp test/queue.sh test/scratch.sh "$work/repo/test/"
  echo 'finish() { echo "$1"; [ "$1" = PASS ]; exit; }' > "$work/repo/test/qml/lib.sh"
  printf 'source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\nfinish "%s"\n' FAIL > "$work/repo/test/qml/broken.sh"
  printf 'source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\nfinish "%s"\n' PASS > "$work/repo/test/qml/fine.sh"
  cat > "$work/repo/test/all.sh" << 'EOF'
source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"
start "a made-up harness, that fails" bash test/qml/broken.sh
start "a made-up harness that passes" bash test/qml/fine.sh
fill
run "a made-up quick check, that fails" false
verdict
EOF
  : > "$work/repo/test/review.sh"
  # commit MESSAGE: the made-up checkout's edits, so a run on it is clean.
  commit() { git -C "$work/repo" add -A && git -C "$work/repo" -c user.name=check -c user.email=check@example.com commit -qm "$1"; }
  # runs [ONLY]: a run of its test/all.sh on its own lock, narrowed to ONLY
  # when given, as test/touched.sh narrows one; its record's last line, and
  # how many runs it records.
  runs() {
    (
      cd "$work/repo" && unset STONKS_ONLY
      [ -z "${1:-}" ] || export STONKS_ONLY=$1
      XDG_RUNTIME_DIR="$work/runtime" bash test/all.sh > "$work/out" 2>&1
    ) || true
    last=$(tail -n 1 "$work/repo/.git/stonks-runs" 2> /dev/null || true)
    recorded=$(cat "$work/repo/.git/stonks-runs" 2> /dev/null | wc -l)
  }
  check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; code=1; fi; }
  git -C "$work/repo" init -q && commit "made up"
  runs
  check "a failed run's record names each step that failed, as its output does" "${last#* SOME FAILED}" " | a made-up quick check, that fails | a made-up harness, that fails"
  before=$recorded
  runs test/qml/fine.sh
  check "a run test/touched.sh narrowed leaves no record" "$recorded" "$before"
  check "the narrowed run says what it left out" "$(grep -c '^left out, as test/touched.sh asked: a made-up harness, that fails$' "$work/out" || true)" 1
  cp "$work/repo/test/qml/fine.sh" "$work/repo/test/qml/unstarted.sh" && commit "a harness no runner starts"
  runs
  check "a harness no runner starts fails the run as harness wiring" "${last#* SOME FAILED}" " | harness wiring"
  return "$code"
}
if [ "${1:-}" = --self-check ]; then self_check; exit; fi
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
