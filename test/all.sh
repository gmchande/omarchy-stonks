#!/usr/bin/env bash
# Every check a pull request needs: what Stonks does, what it fetches, saves,
# and says, and what a key or a click changes. Every unit-test file
# (test/unit.sh), source boundaries, QML lint, manifest and launcher
# validation, the Quickshell flow harnesses, and the frame checker's
# self-check. A picture, a position, or a timing is the maintainer's review
# kit's (test/review.sh); some steps inside these harnesses still judge one
# (frames, pixels, an x, an ease), until they move there: window motion's
# most of all, which runs here for the keys and clicks only it checks, and
# whose frame-judged steps, as pointer's, rely on the frame checker. The
# queue, the lock, and the verdict are test/queue.sh's. Needs Omarchy
# installed and the Wayland session for the harnesses.
source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"

# validate_clone: omarchy plugin validate on what a clone of this checkout
# holds: the tracked files as they are here, an uncommitted edit included,
# never an ignored one (out/, docs/, AGENTS.md, test/fixtures/). Links stay
# links, so a tracked one still fails.
validate_clone() {
  local tree code file
  tree=$(mktemp -d)
  git ls-files -z | while IFS= read -r -d '' file; do
    [[ -e $file || -L $file ]] && printf '%s\0' "$file"
  done | tar -c --null -T - | tar -x -C "$tree"
  (cd "$tree" && omarchy plugin validate .)
  code=$?
  rm -rf "$tree"
  return "$code"
}

# Longest first, as measured.
start "pointer harness" bash test/qml/pointer.sh
start "shared range harness" bash test/qml/range.sh
start "window search harness" bash test/qml/window-search.sh
start "window motion harness" bash test/qml/window-motion.sh
start "window adds harness" bash test/qml/window-adds.sh
start "named watchlists harness" bash test/qml/lists.sh
start "fetch policy harness" bash test/qml/fetch.sh
start "overnight harness" bash test/qml/overnight.sh
start "popup harness" bash test/qml/popup.sh
start "charts fetched ahead harness" bash test/qml/ahead.sh
start "window rows harness" bash test/qml/window-rows.sh
start "keys harness" bash test/qml/keys.sh
start "quote queue harness" bash test/qml/run.sh
start "service harness" bash test/qml/service.sh
start "update check harness" bash test/qml/updates.sh
start "Quickshell crash handling (stand-in)" bash test/qml/crash-check.sh
start "history harness" bash test/qml/history.sh
start "1.0.0 data file harness" bash test/qml/data-files.sh
fill

run "unit tests (every *.test.js)" bash test/unit.sh
run "frame checker self-check" bun test/qml/frames.js self-check
run "source boundaries" bash test/boundaries.sh
run "qmllint (only the baseline in test/lint.sh)" bash test/lint.sh
run "qmllint gate self-check" bash test/lint.sh self-check
run "omarchy plugin validate (what a clone holds)" validate_clone
run "launcher entry validates" desktop-file-validate share/stonks.desktop
verdict
