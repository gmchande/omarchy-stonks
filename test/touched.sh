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
# journeys test/review.sh doesn't run go beside them, one at a time, on
# HEAD. A journey runs a commit, so with edits no commit holds, no journey
# runs, and the run fails saying so. The saved answers are a repository of
# their own: a change there isn't in the diff.
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
# The journeys go beside the suites, as tophat sessions do, one after
# another, each in its own nested session; their output prints at the end.
journeys_log=$(mktemp)
trap 'rm -f "$journeys_log" "$journeys_log.failed"' EXIT
if [ "${#journeys[@]}" -gt 0 ]; then
  set -m
  (
    for journey in "${journeys[@]}"; do
      echo
      echo "== $journey HEAD"
      bash "$journey" HEAD || echo "$journey" >> "$journeys_log.failed"
    done > "$journeys_log" 2>&1
  ) &
  set +m
  journeys_pid=$!
  trap 'kill -- "-$journeys_pid" 2> /dev/null; exit 130' INT TERM
fi
export STONKS_ONLY="${only[*]}"
for runner in all review; do
  [[ " ${runs[*]} " == *" $runner "* ]] || continue
  echo
  test/$runner.sh || failed+=("test/$runner.sh")
done
if [ -n "${journeys_pid:-}" ]; then
  # The worker ends 0 once every journey ran, failed or not; anything else
  # means it was stopped before all of them did.
  wait "$journeys_pid" || failed+=("the journeys, whose run stopped early (status $?)")
  cat "$journeys_log"
  [ ! -f "$journeys_log.failed" ] || mapfile -t -O "${#failed[@]}" failed < "$journeys_log.failed"
fi

echo
[ "${#failed[@]}" -eq 0 ] || printf 'failed: %s\n' "${failed[@]}"
if [ "${#failed[@]}" -gt 0 ]; then echo "touched checks: SOME FAILED"; exit 1; fi
if [ "${#unrun[@]}" -gt 0 ]; then echo "touched checks: NOT ALL RUN (commit your edits for the journeys)"; exit 1; fi
echo "touched checks: PASS"
