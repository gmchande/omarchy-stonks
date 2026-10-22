# Shared setup for the Quickshell harnesses. A harness script sources this,
# builds a tree, runs Quickshell on it, and finishes on the harness's own
# finish line. Quickshell loads QML only from inside its config folder, so
# each tree is assembled in a scratch folder that is removed on exit.
# Harnesses run side by side (test/queue.sh), so each keeps its own HOME, QML
# cache, and fake curl state. Every harness reads the saved answers
# (STONKS_FIXTURES, test/fixtures-dir.sh), the fake curl's too; without them
# it says so and exits 77, which the runners report as skipped. One that
# reads none sets saved_answers=none before sourcing this: it runs on any
# clone, and the fake curl fails its every ask.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
plugin="$(cd "$here/../.." && pwd)"
if [ "${saved_answers:-}" = none ]; then
  unset STONKS_FIXTURES
elif ! STONKS_FIXTURES=$("$plugin/test/fixtures-dir.sh" 2>&1); then
  echo "SKIP ${BASH_SOURCE[1]##*/}: $STONKS_FIXTURES"
  exit 77
fi
export STONKS_FIXTURES
source "$here/quickshell.sh"
work="$(mktemp -d)"
# However the run ends, its Quickshell's group and marked processes go first.
trap 'quickshell_exit; rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export HOME="$work/home"
# The reader is in New York: an exchange's time names its
# zone only where it differs from the reader's clock.
export TZ=America/New_York
export XDG_CACHE_HOME="$HOME/.cache"
export STONKS_FAKE_STATE="$work/state"
mkdir -p "$HOME/.config/omarchy" "$STONKS_FAKE_STATE"
root=""
code=0

# feed_tree HARNESS FILE...: copies of just the named plugin files, so a
# feed loads without the shell's Ui and Commons. Copies, so a script can
# patch them. Every tree holds HarnessExit.qml, a harness's one way out.
feed_tree() {
  root="$work/config"
  mkdir -p "$root"
  cp "$here/$1" "$root/shell.qml"
  cp "$here/HarnessExit.qml" "$root/"
  shift
  for file in "$@"; do cp "$plugin/$file" "$root/"; done
}

# plugin_tree HARNESS: copies of the whole plugin beside the shell's Ui and
# Commons, its manifest too, which the version watch reads. Copies, so a
# script can sed test aliases into them, or move the manifest's version.
# The window host lists no screens, so a harness never asks the owner's
# Hyprland whether theirs are off, and its quote runs never wait on them;
# a harness that steps through screens off hands the host its own.
plugin_tree() {
  root="$work"
  mkdir -p "$root/plugin"
  cp "$plugin"/*.qml "$plugin"/*.js "$plugin/calendars.json" "$plugin/manifest.json" "$root/plugin/"
  cp -r "$plugin/sounds" "$root/plugin/"
  ln -s /usr/share/omarchy/shell/Ui /usr/share/omarchy/shell/Commons "$root/"
  cp "$here/$1" "$root/shell.qml"
  cp "$here/HarnessExit.qml" "$root/"
  patch_copy plugin/WindowHost.qml 's/readonly property var monitors: Hyprland.monitors.values/property var monitors: []/'
}

# frame_tools: FrameGrab.qml beside the harness, a folder for its frames,
# and frames.js to judge them.
frame_tools() {
  cp "$here/FrameGrab.qml" "$root/"
  export STONKS_FRAMES="$work/frames" STONKS_FRAME_CHECK="$here/frames.js"
  mkdir -p "$STONKS_FRAMES"
}

# patch_copy FILE SED: run one sed command on the tree's copy of FILE (a
# path under the tree), and stop before Quickshell starts if it changed
# nothing: a reworded line would otherwise leave the harness running on
# what the patch meant to replace.
patch_copy() {
  local before
  before=$(md5sum < "$root/$1")
  sed -i "$2" "$root/$1"
  if [ "$(md5sum < "$root/$1")" = "$before" ]; then
    echo "FAIL the patch missed $1 ($2); not starting Quickshell"
    exit 1
  fi
}

# scratch_home FIXTURE NAME...: puts each saved file from STONKS_FIXTURES in
# the scratch HOME's ~/.config/omarchy under the name after it.
scratch_home() {
  while [ "$#" -gt 1 ]; do
    cp "$STONKS_FIXTURES/$1" "$HOME/.config/omarchy/$2"
    shift 2
  done
}

# run_qs SECONDS: run Quickshell on the tree, with the fake curl first on
# PATH, into $work/log (quickshell.sh).
run_qs() {
  PATH="$here/bin:$PATH" quickshell_run "$1" "$work/log" -p "$root" --no-color
  code=$qs_code
}

# fetched NAME: how many times the fake curl answered NAME.
fetched() {
  cat "$STONKS_FAKE_STATE/$1.calls" 2>/dev/null || echo 0
}

# stonks_warnings LOG: the Qt warnings (and errors) in LOG that name one of
# the plugin's own files, on the line itself or on a stack line under it,
# each printed with its stack: a binding loop names where the object was
# made (the harness's shell.qml) and the binding's own file only on the line
# under it. The shell's files (@Ui/, @Commons/) and the harness's shell.qml
# never match.
stonks_warnings() {
  local names
  names=$(cd "$plugin" && ls -- *.qml | sed 's/\.qml$//' | paste -sd '|')
  awk -v files="(@|/qs/)(plugin/)?($names)\\\\.qml" '
    /^ *(DEBUG|INFO|WARN|ERROR|FATAL)[: ]/ {
      warned = $1 ~ /^(WARN|ERROR|FATAL)/
      entry = $0
      shown = 0
      if (warned && $0 ~ files) { print; shown = 1 }
      next
    }
    warned && (shown || $0 ~ files) {
      if (!shown) print entry
      print
      shown = 1
    }' "$1"
}

# finish MARKER: print the harness's lines, then exit. Fails on a non-zero
# exit, any FAIL line, a TypeError, ReferenceError, or Error: in the log (a
# binding that throws is logged, not raised), a Qt warning from the plugin's
# own files (stonks_warnings), a host's budget holding a request back
# (Gate.qml; normal use never reaches it, so only a harness that sets
# STONKS_BUDGET_EXPECTED may), and a run that never printed MARKER, the
# harness's finish line: a step that throws ends a Quickshell harness
# without a FAIL line.
finish() {
  rg -N 'PASS |FAIL[ !]|ALL PASS|[0-9]+ FAILED|ERROR|TypeError|ReferenceError|\bError:' "$work/log" \
    | sed -E 's/^ *[A-Z]+ qml: //' || true
  if rg -q '(^\s*|qml: )FAIL[ !]' "$work/log"; then code=1; fi
  if rg -q 'TypeError|ReferenceError|\bError:' "$work/log"; then
    echo "FAIL the log has a runtime error"
    code=1
  fi
  if [ -z "${STONKS_BUDGET_EXPECTED:-}" ] && rg -q "budget held back" "$work/log"; then
    echo "FAIL a host's budget held requests back: $(rg -o "stonks: .*budget held back.*" "$work/log" | head -1)"
    code=1
  fi
  local warnings
  warnings=$(stonks_warnings "$work/log")
  if [ -n "$warnings" ]; then
    echo "FAIL the log has Qt warnings from the plugin's files:"
    sort <<< "$warnings" | uniq -c | sort -rn
    code=1
  fi
  if ! rg -q -F "$1" "$work/log"; then
    echo "FAIL the run never reached $1"
    code=1
  fi
  if [ "$code" -ne 0 ]; then
    echo "exit $code"
    cat "$work/log"
  fi
  exit "$code"
}
