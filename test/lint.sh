#!/usr/bin/env bash
# The QML lint gate: lints every production QML file against the installed
# shell and passes only when qmllint ran cleanly on every file and each of
# its diagnostics is in the baseline below. `test/lint.sh self-check` shows
# the gate failing on a missing linter, a scratch unqualified access, and a
# scratch outer id read from a nested component in a file without
# `pragma ComponentBehavior: Bound`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export LC_ALL=C.UTF-8
qmllint=${QMLLINT:-/usr/lib/qt6/bin/qmllint}

# Warnings outside the house baseline, each file, category, and token with
# its exact count. Fix one and lower its count here.
declare -A listed=(
  # Watchlist.qml: pauseRows and settleRows call functions the row delegate
  # declares, which qmllint cannot see through Repeater.itemAt.
  ["Watchlist.qml missing-property pause"]=1
  ["Watchlist.qml missing-property settle"]=1
)

# The house baseline, what qmllint cannot see in the installed shell: these
# members of its QtObject-typed Style.font, Style.spacing, Style.bar,
# Color.popups, and Color.bar, and of the `bar` that Panel and BarWidget
# inherit.
shell_members=" Style.font.family Style.font.title Style.font.body Style.font.bodySmall
  Style.font.caption Style.font.display Style.font.displayLarge Style.font.icon Style.spacing.md
  Style.bar.iconSlot Style.bar.iconCanvas Color.popups.background Color.bar.background BarWidget.qml:bar.shell BarWidget.qml:bar.layoutConfig
  Panel.qml:bar.shell Panel.qml:bar.foreground Panel.qml:bar.fontFamily
  Panel.qml:bar.switchPanelFrom Panel.qml:bar.setCenterHoverRevealSuppressed "
shell_members=${shell_members//$'\n'/ }
house() { # file id message member
  [ "$2" = missing-property ] && [[ $3 == *'not found on type "QObject"' ]] &&
    [[ $shell_members == *" $4 "* || $shell_members == *" $1:${4#root.} "* ]]
}

lint() { # file...
  local tmp out code failed=0 shown=0 houses=0
  tmp=$(mktemp -d)
  ln -s /usr/share/omarchy/shell "$tmp/qs"
  out=$("$qmllint" -I "$tmp" --json "$tmp/lint.json" "$@" 2>&1)
  code=$?
  if [ "$code" -ne 0 ] || [ -n "$out" ]; then
    echo "qmllint exited $code${out:+ and printed:}"
    [ -n "$out" ] && printf '%s\n' "$out"
    failed=1
  fi
  if ! jq -e --argjson n "$#" '.files | length == $n and all(.warnings | type == "array")' "$tmp/lint.json" >/dev/null 2>&1; then
    echo "qmllint wrote no report for all $# files"
    rm -rf "$tmp"
    return 1
  fi
  declare -A linted=() seen=() report=()
  local path file line col len id type message text token member key src=()
  for path in "$@"; do linted[${path##*/}]=1; done
  while IFS=$'\t' read -r path line col len id type message; do
    file=${path##*/}
    shown=$((shown + 1))
    mapfile -t src < "$path"
    text=${src[line - 1]:-}
    token=${text:col-1:len}
    member=$token
    [[ ${text:0:col-1} =~ ([A-Za-z_][A-Za-z0-9_.]*\.)$ ]] && member=${BASH_REMATCH[1]}$token
    if [ "$type" = warning ] && house "$file" "$id" "$message" "$member"; then
      houses=$((houses + 1))
      continue
    fi
    key="$file $id $token"
    seen[$key]=$((${seen[$key]:-0} + 1))
    report[$key]+="  $file:$line:$col: $type [$id] $message: ${text#"${text%%[![:space:]]*}"}"$'\n'
  done < <(jq -r '.files[] | .filename as $f | .warnings[] | [$f, .line, .column, .length, .id, .type, .message]
      | @tsv' "$tmp/lint.json")
  rm -rf "$tmp"
  for key in "${!seen[@]}"; do
    [ "${listed[$key]:-0}" -eq "${seen[$key]}" ] && continue
    echo "${seen[$key]} of \"$key\", baseline allows ${listed[$key]:-0}:"
    printf '%s' "${report[$key]}"
    failed=1
  done
  for key in "${!listed[@]}"; do
    [ -n "${seen[$key]:-}" ] || [ -z "${linted[${key%% *}]:-}" ] && continue
    echo "0 of \"$key\", baseline allows ${listed[$key]}: lower it"
    failed=1
  done
  echo "$# files, $shown diagnostics: $houses house baseline, $((shown - houses)) listed or new"
  return "$failed"
}

self_check() {
  local tmp out failed=0
  if out=$(QMLLINT=/nonexistent/qmllint bash test/lint.sh 2>&1); then
    echo "passed with no linter:"; printf '%s\n' "$out"; failed=1
  elif [[ $out != *"qmllint exited 127"* ]]; then
    echo "failed with no linter, but not for that:"; printf '%s\n' "$out"; failed=1
  else
    echo "a missing linter fails the gate"
  fi
  tmp=$(mktemp -d)
  printf '%s\n' 'import QtQuick' '' 'Item {' '  id: root' '  width: undefinedWidth' \
    '  Repeater {' '    model: 1' '    Item { width: root.width }' '  }' '}' > "$tmp/Scratch.qml"
  if out=$(lint "$tmp/Scratch.qml" 2>&1); then
    echo "passed an unqualified access:"; printf '%s\n' "$out"; failed=1
  elif [[ $out != *"Scratch.qml:5:10: warning [unqualified]"* || $out != *"Scratch.qml:8:19: warning [unqualified]"* ]]; then
    echo "failed on the scratch file, but not for both unqualified accesses:"; printf '%s\n' "$out"; failed=1
  else
    echo "an unqualified access, and an outer id read in a file without the pragma, fail the gate"
  fi
  rm -rf "$tmp"
  return "$failed"
}

if [ "${1:-}" = self-check ]; then self_check; else lint *.qml; fi
