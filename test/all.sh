#!/usr/bin/env bash
# Every check a pull request needs, one after another: the rule tests
# (test/unit.sh), the source boundaries, QML lint, the font's glyphs, the
# manifest and the launcher entry, and the walks through the real plugin:
# keys, mouse, saving, fetching, what a long list costs, and the
# screenshot. The walks draw offscreen, but need Quickshell, Omarchy's
# shell, and a display for Qt's GTK theme.
# How Stonks looks is for the pictures (test/qml/render.sh), and how it
# moves and feels for a hand on the running plugin.
#
# A check that exits 77 had no saved answers to run on
# (test/fixtures-dir.sh): it says so, and the last line counts the skips.
# Only a whole run with none skipped ends ALL PASS.
#
#   test/all.sh [NAME...]   only the named checks: a walk by its
#                           test/qml/NAME.sh, the rest by the names below
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source test/scratch.sh

# validate_clone: omarchy plugin validate on what a clone of this checkout
# holds: the tracked files as they are here, an uncommitted edit included,
# never an ignored one (out/, docs/, AGENTS.local.md, test/fixtures/). Links
# stay links, so a tracked one still fails.
validate_clone() {
  local tree code file
  tree=$(mktemp -d) || return 1
  git ls-files -z | while IFS= read -r -d '' file; do
    [[ -e $file || -L $file ]] && printf '%s\0' "$file"
  done | tar -c --null -T - | tar -x -C "$tree"
  (cd "$tree" && omarchy plugin validate .)
  code=$?
  rm -rf "$tree"
  return "$code"
}

# Every check: check NAME LABEL COMMAND...
checks() {
  check unit "unit tests (every *.test.js)" bash test/unit.sh
  check font "required font glyphs" bun test/font.js
  check boundaries "source boundaries" bash test/boundaries.sh
  check lint "qmllint (only the baseline in test/lint.sh)" bash test/lint.sh
  check validate "omarchy plugin validate (what a clone holds)" validate_clone
  check launcher "launcher entry validates" desktop-file-validate share/stonks.desktop
  check keys "keys walk" bash test/qml/keys.sh
  check mouse "mouse walk" bash test/qml/mouse.sh
  check saving "saving walk" bash test/qml/saving.sh
  check fetching "fetching walk" bash test/qml/fetching.sh
  check cost "cost walk" bash test/qml/cost.sh
  check camera "camera harness" env QT_SCALE_FACTOR=1 bash test/qml/camera.sh
  # On a scale-2 screen too, and on 1.75, where 2400 pixels are no whole
  # number of units: the picture is drawn and saved at 2400 x 1350 there,
  # not at twice that or half of it or a pixel off, and the same on each.
  # Only the two sized shots.
  check camera "camera harness at scale 2" env QT_SCALE_FACTOR=2 STONKS_CAMERA_SIZES=1 bash test/qml/camera.sh
  check camera "camera harness at scale 1.75" env QT_SCALE_FACTOR=1.75 STONKS_CAMERA_SIZES=1 bash test/qml/camera.sh
}

# A name that isn't a check's stops the run before anything starts.
names=""
check() { [[ " $names " == *" $1 "* ]] || names+=" $1"; }
checks
for name; do
  [[ " $names " == *" $name "* ]] || { echo "test/all.sh: no check is named $name; the names are:$names"; exit 2; }
done

picked=" $* "
failed=0
skipped=0
check() {
  local name=$1 label=$2 code
  shift 2
  [ "$picked" = "  " ] || [[ $picked == *" $name "* ]] || return 0
  echo "== $label"
  "$@"
  code=$?
  if [ "$code" -eq 0 ]; then echo "   ok"
  elif [ "$code" -eq 77 ]; then echo "   skipped"; skipped=$((skipped + 1))
  else echo "   FAILED"; failed=1; fi
}
checks

echo "test/all.sh took $((SECONDS / 60)) min $((SECONDS % 60)) s"
if [ "$failed" -ne 0 ]; then last="SOME FAILED"
elif [ "$picked" != "  " ]; then
  last="PASSED ONLY $*"
  [ "$skipped" -eq 0 ] || last+=", $skipped SKIPPED (no saved answers)"
elif [ "$skipped" -gt 0 ]; then last="PASSED, $skipped SKIPPED (no saved answers)"
else last="ALL PASS"; fi
echo "$last"
exit "$failed"
