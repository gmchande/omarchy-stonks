#!/usr/bin/env bash
# The checks your change can break, for while you build: the steps of
# test/all.sh and test/review.sh, and the journeys, that the diff from BASE
# (dev by default) reaches, uncommitted edits and untracked files included.
# It says what it runs and what it leaves out, and why (test/touched.js
# holds the rules: a check is left out only when nothing it runs names a
# changed file). The full runs stay the gate: this run is never recorded
# (test/ran.sh), and its last line is never ALL PASS.
#
# The suites' steps run through their own runners, so through the one lock
# and queue (test/queue.sh), with STONKS_ONLY naming the checks picked. The
# journeys test/review.sh doesn't run go after, one at a time, on HEAD: a
# journey runs a commit, so with uncommitted edits none runs, and the run
# fails saying so. The saved answers are a repository of their own: a
# change there isn't in the diff.
#
#   test/touched.sh [BASE]
#   test/touched.sh self-check   the rules on a made-up checkout
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source "$PWD/test/scratch.sh"
if [ "${1:-}" = self-check ]; then exec bun test/touched.js self-check; fi
base=${1:-dev}
picks=$(bun test/touched.js "$base") || exit 1

only=() runs=() journeys=() unrun=()
dirty=$(git status --porcelain)
{
  read -r _ since changed
  echo "test/touched.sh: $changed files differ from where this branch left $base (${since:0:7})"
  while IFS=$'\t' read -r verdict file runner why; do
    if [ "$verdict" = leave ]; then
      echo "  leaves out $file: $why"
    elif [[ $file == test/tophat/journeys/* && -n $dirty ]]; then
      unrun+=("$file")
    else
      echo "  runs $file: $why"
      only+=("$file")
      [[ " ${runs[*]} " == *" $runner "* ]] || runs+=("$runner")
      [ "$runner" != journey ] || journeys+=("$file")
    fi
  done
} <<< "$picks"
for file in "${unrun[@]}"; do
  echo "  can't run $file: a journey runs a commit, and this checkout has edits no commit holds"
done

failed=()
export STONKS_ONLY="${only[*]}"
for runner in all review; do
  [[ " ${runs[*]} " == *" $runner "* ]] || continue
  echo
  test/$runner.sh || failed+=("test/$runner.sh")
done
for journey in "${journeys[@]}"; do
  echo
  echo "== $journey HEAD"
  bash "$journey" HEAD || failed+=("$journey")
done

echo
[ "${#failed[@]}" -eq 0 ] || printf 'failed: %s\n' "${failed[@]}"
if [ "${#failed[@]}" -gt 0 ]; then echo "touched checks: SOME FAILED"; exit 1; fi
if [ "${#unrun[@]}" -gt 0 ]; then echo "touched checks: NOT ALL RUN (commit your edits for the journeys)"; exit 1; fi
echo "touched checks: PASS"
