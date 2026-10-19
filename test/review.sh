#!/usr/bin/env bash
# The maintainer's review kit: how Stonks looks and moves, and the rules read
# against the real saved answers. Run it by hand before merging a visible
# change, a contributor's included, on their branch, and before a release.
# It is neither test/all.sh nor CI: pictures and frame timings vary by
# machine, and the saved answers are private. Without them (test/
# fixtures-dir.sh) almost all of it skips.
#
# - The offscreen renders (out/render/): every state on every kind of
#   listing in both looks, for your eyes; nothing compares them.
# - The README's pictures, into a scratch folder, so test/qml/readme.sh
#   still works when a release renders them for real.
# - Nothing jumps: positions across looks, symbols, and ranges.
# - Window and popup motion, judged on rendered frames (test/qml/frames.js),
#   never on the property behind it; and the frame checker's own self-check.
# - The long list: a power user's day on a slow network, on wall-clock
#   budgets.
# - The tophat's guards, without a screen. Try a visible change in a nested
#   session first (test/tophat.sh, its usage at the top).
# - The rules read against Yahoo's and Robinhood's saved answers
#   (test/saved.test.js).
#
# The queue, the lock, and the verdict are test/queue.sh's: one run of
# either runner at a time.
source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"

# saved_tests: the rules read against the saved answers, when there are any.
saved_tests() {
  local why
  why=$(test/fixtures-dir.sh 2>&1 > /dev/null) || { echo "SKIP saved.test.js: $why"; return 77; }
  bun test ./test/saved.test.js
}

# Longest first, as measured: the kit takes as long as the renders.
start "offscreen renders" bash test/qml/render.sh
start "nothing-jumps layout harness" bash test/qml/layout.sh
start "long list harness" bash test/qml/long-list.sh
start "window motion harness" bash test/qml/window-motion.sh
start "README pictures, into a scratch folder" env STONKS_README_OUT="$logs/readme" bash test/qml/readme.sh
start "popup motion harness" bash test/qml/popup-motion.sh
start "tophat guards (no screen)" bash test/tophat.sh self-check
fill

run "bun test (saved answers)" saved_tests
run "frame checker self-check" bun test/qml/frames.js self-check
verdict
