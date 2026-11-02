#!/usr/bin/env bash
# The set-time wait gate: counts each harness file's wait(N) with a number
# written in, outside comments, and passes only when each count is its
# baseline below. A count may only go down: a step waits for what it needs,
# with within(ms, fn) (Steps.qml), never for a set time. Many of today's
# step a stand-in clock on purpose.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Each file's count today. Remove a set-time wait and lower its count here.
declare -A baseline=(
  [Steps.qml]=1
  [ahead.qml]=7
  [camera.qml]=2
  [fetch.qml]=19
  [keys.qml]=1
  [layout.qml]=155
  [lists.qml]=5
  [long-list.qml]=4
  [overnight.qml]=11
  [pointer.qml]=16
  [popup-motion.qml]=2
  [popup.qml]=1
  [range.qml]=24
  [render.qml]=2
  [resilience.qml]=1
  [sounds.qml]=22
  [updates.qml]=2
  [window-adds.qml]=3
  [window-motion.qml]=4
  [window-rows.qml]=5
  [window-search.qml]=45
)

counts=$(rg --count-matches -P '//.*(*SKIP)(*F)|\bwait\(\s*[0-9]' -g '*.qml' -- test/qml)
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
