#!/usr/bin/env bash
# The maintainer's review kit: how Stonks looks and moves, and the rules read
# against the real saved answers. Run it by hand before merging a visible
# change, a contributor's included, on their branch, and before a release.
# It is neither test/all.sh nor CI: pictures and frame timings vary by
# machine, and the saved answers are private. Without them (test/
# fixtures-dir.sh) almost all of it skips.
#
# - The offscreen renders (out/render/): every state on every kind of
#   listing in both looks, for your eyes. The base's too, from its own
#   files and renderer, so the render diff (test/render-diff.sh) lists every
#   picture the change moved, side by side in out/render-diff/. The base is
#   the merge-base with origin/dev, or with STONKS_RENDER_BASE (a release's
#   tag, before the next release).
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

# render_diff: the pictures the change moved, once both sets are rendered.
render_diff() {
  local why
  why=$(test/fixtures-dir.sh 2>&1 > /dev/null) || { echo "SKIP render diff: $why"; return 77; }
  [ -n "$base" ] || { echo "FAILED no base: HEAD and $base_ref share no commit"; return 1; }
  test/render-diff.sh "$logs/base-render" out/render out/render-diff
}

# The base's tree, outside git, with this checkout's saved answers beside it.
base_ref=${STONKS_RENDER_BASE:-origin/dev}
base=$(git merge-base HEAD "$base_ref" 2> /dev/null)
if [ -n "$base" ]; then
  mkdir -p "$logs/base"
  git archive "$base" | tar -x -C "$logs/base"
  fixtures=$(test/fixtures-dir.sh 2> /dev/null) && ln -s "$fixtures" "$logs/base/test/fixtures"
fi
# out/render holds this run's pictures only, so the diff reads no other's.
rm -rf out/render

# Longest first, as measured. The renders, the head's and the base's, run in
# two parts each.
start "nothing-jumps layout harness" bash test/qml/layout.sh
start "offscreen renders, 1 of 2" bash test/qml/render.sh --part 1/2
start "offscreen renders, 2 of 2" bash test/qml/render.sh --part 2/2
if [ -n "$base" ]; then
  # A base from before the parts renders whole.
  if grep -q -- '--part I/N' "$logs/base/test/qml/render.sh"; then
    start "base renders, 1 of 2" env STONKS_VISUAL_DIR="$logs/base-render" bash "$logs/base/test/qml/render.sh" --part 1/2
    start "base renders, 2 of 2" env STONKS_VISUAL_DIR="$logs/base-render" bash "$logs/base/test/qml/render.sh" --part 2/2
  else
    start "base renders" env STONKS_VISUAL_DIR="$logs/base-render" bash "$logs/base/test/qml/render.sh"
  fi
fi
start "long list harness" bash test/qml/long-list.sh
start "window motion harness" bash test/qml/window-motion.sh
start "README pictures, into a scratch folder" env STONKS_README_OUT="$logs/readme" bash test/qml/readme.sh
start "popup motion harness" bash test/qml/popup-motion.sh
start "tophat guards (no screen)" bash test/tophat.sh self-check
fill

run "bun test (saved answers)" saved_tests
run "frame checker self-check" bun test/qml/frames.js self-check
drain
run "render diff, against ${base:0:7} (out/render-diff/)" render_diff
verdict
