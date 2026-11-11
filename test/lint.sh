#!/usr/bin/env bash
# The QML lint gate: lints every production QML file against the installed
# shell, or only the files named, and passes only when qmllint ran cleanly
# on every file and each of its diagnostics is in the baseline below.
#
#   test/lint.sh [FILE...]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source "$PWD/test/scratch.sh"
export LC_ALL=C.UTF-8
# Qt 6.12's qmllint warns of every `var` declared in a block, a style the
# code keeps throughout.
qmllint=${QMLLINT:-/usr/lib/qt6/bin/qmllint}
lint_flags=(--block-scope-var-declaration disable)
# Every scratch folder is made in this one, removed by exact path however the
# run ends, an interrupt included.
work=$(mktemp -d) || exit 1
trap 'rm -rf -- "$work"' EXIT

# Warnings outside the house baseline, each file, category, and token with
# its exact count. Fix one and lower its count here.
declare -A listed=(
  # Watchlist.qml: pauseRows and settleRows call functions the row delegate
  # declares, which qmllint cannot see through Repeater.itemAt.
  ["Watchlist.qml missing-property pause"]=1
  ["Watchlist.qml missing-property settle"]=1
  # BarWidget.qml: injectPanel sets each property the loaded panel has,
  # checked with `in`; Qt 6.12 types Loader.item as a bare QObject.
  ["BarWidget.qml missing-property target"]=5
  # An alias that exposes an inner object by its own id, which Qt 6.12
  # counts as shadowing: the alias and the id's line each.
  ["StonksBody.qml id-shadows-member motion"]=2
  ["StonksBody.qml id-shadows-member watchlist"]=2
  ["StonksBody.qml id-shadows-member search"]=2
  ["WindowHost.qml id-shadows-member app"]=2
  ["Service.qml id-shadows-member yahooGate"]=2
)

# The house baseline, what qmllint cannot see in the installed shell: these
# members of its QtObject-typed Style.font, Style.bar, Commons.Color.popups,
# and Commons.Color.bar, and of the `bar` that Panel and BarWidget inherit.
shell_members=" Style.font.family Style.font.title Style.font.body Style.font.bodySmall
  Style.font.caption Style.font.display Style.font.displayLarge Style.font.icon
  Style.bar.iconSlot Style.bar.iconCanvas Commons.Color.popups.background Commons.Color.popups.border Commons.Color.popups.text
  Commons.Color.bar.background BarWidget.qml:bar.shell BarWidget.qml:bar.layoutConfig
  BarWidget.qml:bar.transparent BarWidget.qml:bar.barForeground BarWidget.qml:bar.foreground
  Panel.qml:bar.shell Panel.qml:bar.foreground Panel.qml:bar.fontFamily
  Panel.qml:bar.switchPanelFrom Panel.qml:bar.setCenterHoverRevealSuppressed "
shell_members=${shell_members//$'\n'/ }
house() { # file id message member
  [ "$2" = missing-property ] && [[ $3 == *'not found on type "QObject"' ]] &&
    [[ $shell_members == *" $4 "* || $shell_members == *" $1:${4#root.} "* ]]
}

lint() { # file...
  local tmp out code failed=0 shown=0 houses=0
  tmp=$(mktemp -d "$work/XXXXXX")
  ln -s /usr/share/omarchy/shell "$tmp/qs"
  out=$("$qmllint" "${lint_flags[@]}" -I "$tmp" --json "$tmp/lint.json" "$@" 2>&1)
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

if [ "$#" -gt 0 ]; then lint "$@"; else lint *.qml; fi
