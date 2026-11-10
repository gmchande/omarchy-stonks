#!/usr/bin/env bash
# The set-time wait gate: counts each harness file's wait(...) outside
# strings and comments, a computed one such as wait(interval - 150) too,
# and passes only when each count is its baseline below. A count may only
# go down: a step waits for what it needs, with within(ms, fn) (Steps.qml),
# never for a set time. Many of today's step a stand-in clock on purpose.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Each file's count today. Remove a set-time wait and lower its count here.
declare -A baseline=(
  [Steps.qml]=1
  [camera.qml]=2
  [fetching.qml]=3
  [keys.qml]=1
  [render.qml]=2
  [saving.qml]=1
)

# Strings and comments, either kind, are skipped (\x22 and \x27 are the two
# quotes).
code_only='\x22(?:\\.|[^\x22\\\n])*\x22(*SKIP)(*F)|\x27(?:\\.|[^\x27\\\n])*\x27(*SKIP)(*F)|/\*[\s\S]*?\*/(*SKIP)(*F)|//.*(*SKIP)(*F)'
counts=$(rg -U --count-matches -P "$code_only|\\bwait\\s*\\(" -g '*.qml' -- test/qml)
code=$?
[ "$code" -le 1 ] || { echo "FAILED rg could not count the waits in test/qml"; exit 1; }
failed=0
total=0
declare -A seen=()
while IFS=: read -r path count; do
  [ -n "$path" ] || continue
  file=${path##*/}
  seen[$file]=$count
  total=$((total + count))
  allowed=${baseline[$file]:-0}
  if [ "$count" -gt "$allowed" ]; then
    echo "FAILED $path: $count set-time waits, baseline $allowed. Wait for what the step needs, with within(ms, fn)."
    failed=1
  fi
done <<< "$counts"
for file in "${!baseline[@]}"; do
  count=${seen[$file]:-0}
  if [ "$count" -lt "${baseline[$file]}" ]; then
    echo "FAILED test/qml/$file: $count set-time waits, baseline ${baseline[$file]}: lower its baseline in test/waits.sh"
    failed=1
  fi
done
[ "$failed" -eq 0 ] && echo "$total set-time waits in ${#seen[@]} harness files, none over its baseline"
exit "$failed"
