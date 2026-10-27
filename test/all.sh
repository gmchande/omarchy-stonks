#!/usr/bin/env bash
# Every check a pull request needs: what Stonks does, fetches, saves and
# says, and what a key or a click changes. Every unit-test file
# (test/unit.sh), source boundaries, QML lint, manifest and launcher
# validation, the Quickshell flow harnesses, and the frame checker's
# self-check on made-up frames. Pictures, positions and motion belong to
# test/review.sh; input readiness and a target's reachability to the action
# they protect; the queue, the lock and the verdict to test/queue.sh. Needs
# Omarchy installed and the Wayland session for the harnesses.
source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"

# validate_clone: omarchy plugin validate on what a clone of this checkout
# holds: the tracked files as they are here, an uncommitted edit included,
# never an ignored one (out/, docs/, AGENTS.local.md, test/fixtures/). Links
# stay links, so a tracked one still fails.
validate_clone() {
  local tree code file
  tree=$(mktemp -d "$logs/clone.XXXXXX")
  git ls-files -z | while IFS= read -r -d '' file; do
    [[ -e $file || -L $file ]] && printf '%s\0' "$file"
  done | tar -c --null -T - | tar -x -C "$tree"
  (cd "$tree" && omarchy plugin validate .)
  code=$?
  rm -rf "$tree"
  return "$code"
}

# Longest first, as measured.
start "window search harness" bash test/qml/window-search.sh
start "sounds harness" bash test/qml/sounds.sh
start "fetch policy harness" bash test/qml/fetch.sh
start "window adds harness" bash test/qml/window-adds.sh
start "pointer harness" bash test/qml/pointer.sh
start "window rows harness" bash test/qml/window-rows.sh
start "charts fetched ahead harness" bash test/qml/ahead.sh
start "shared range harness" bash test/qml/range.sh
start "overnight harness" bash test/qml/overnight.sh
start "named watchlists harness" bash test/qml/lists.sh
start "quote queue harness" bash test/qml/quote-queue.sh
start "service harness" bash test/qml/service.sh
start "save, clock and pending work harness" bash test/qml/resilience.sh
start "Quickshell crash handling (stand-in)" bash test/qml/crash-check.sh
start "camera harness" env QT_SCALE_FACTOR=1 bash test/qml/camera.sh
start "update check harness" bash test/qml/updates.sh
start "history harness" bash test/qml/history.sh
# On a scale-2 screen too: the picture is drawn and saved at 2400 x 1350
# there, not at twice that or half of it. Only the two sized shots.
start "camera harness at scale 2" env QT_SCALE_FACTOR=2 STONKS_CAMERA_SIZES=1 bash test/qml/camera.sh
start "keys harness" bash test/qml/keys.sh
start "popup harness" bash test/qml/popup.sh
fill

run "unit tests (every *.test.js)" bash test/unit.sh
run "frame checker self-check" bun test/qml/frames.js self-check
run "required font glyphs" bun test/font.js
run "source boundaries" bash test/boundaries.sh
run "qmllint (only the baseline in test/lint.sh)" bash test/lint.sh
run "qmllint gate self-check" bash test/lint.sh self-check
run "omarchy plugin validate (what a clone holds)" validate_clone
run "launcher entry validates" desktop-file-validate share/stonks.desktop
verdict
