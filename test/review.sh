#!/usr/bin/env bash
# The maintainer's review kit: how Stonks looks and moves. Run it by hand
# before merging a visible change, a contributor's included, on their branch,
# and before a release. It is neither test/all.sh nor CI: pictures and frame
# timings vary by machine, and the saved answers are private. Without them
# (test/fixtures-dir.sh) almost all of it skips.
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
# - Popup motion, judged on rendered frames (test/qml/frames.js), never on
#   the property behind it.
# - The long list: a power user's day on a slow network, on wall-clock
#   budgets.
# - The tophat's guards, without a screen. Try a visible change in a nested
#   session first (test/tophat.sh, its usage at the top).
#
# Each set of renders, the head's and the base's, is drawn once: a run keeps
# each set it draws whole under the name test/render-key.sh makes from
# everything that draws it, and a later run with that name uses the kept
# set instead. The log says which sets were kept and which run drew them.
# The newest 20 sets stay, about 22 MB each, in the git folder every
# worktree shares. --fresh reuses none and replaces what it draws: a
# release's run, which has to catch a change from outside the repo
# (CONTRIBUTING.md, Releases).
#
# The queue, the lock, and the verdict are test/queue.sh's: one run of
# either runner at a time. It takes every option but --fresh. --fresh runs
# a tree that already passed too, since that run may have reused a set.
fresh=""
for arg; do
  shift
  if [ "$arg" = --fresh ]; then fresh=1; set -- "$@" --again; else set -- "$@" "$arg"; fi
done
source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"

store="$(git rev-parse --path-format=absolute --git-common-dir)/stonks-renders"
keep=20

# kept NAME: the kept set NAME's folder, marked as just used, when this run
# may use it. A set is whole while its note of who drew it is there: the
# note is written last, and goes first when the set goes.
kept() {
  [ -z "$fresh" ] && [ -n "$1" ] && [ -f "$store/$1/drawn" ] && touch "$store/$1" && echo "$store/$1"
}

# drop FOLDER: removes a kept set, its note first.
drop() { rm -f "$1/drawn" && rm -rf "$1"; }

# keep_set NAME TREE FOLDER WHAT: keeps FOLDER's pictures, drawn from TREE,
# of WHAT, as set NAME, unless what draws them changed during the run.
keep_set() {
  [ -n "$1" ] || return 0
  if [ "$(test/render-key.sh "$2" 2> /dev/null)" != "$1" ]; then
    echo "not keeping $4's renders: what draws them changed during the run"
    return 0
  fi
  drop "${store:?}/$1" && mkdir -p "$store/$1" && cp "$3"/*.png "$store/$1/" \
    && echo "$4, drawn by the run at $(date '+%H:%M on %-d %B') on ${commit:0:7}" > "$store/$1/drawn" \
    && echo "kept $4's renders as $1"
}

# keep_sets: keeps each set this run drew once every part of it passed;
# then only the newest $keep.
keep_sets() {
  local what=${commit:0:7} status=0 old
  [ -n "$tree" ] || what="$what with uncommitted edits"
  if [ "${#head_parts[@]}" -gt 0 ] && passed "${head_parts[@]}"; then
    keep_set "$head_key" . out/render "$what" || status=1
  fi
  if [ "${#base_parts[@]}" -gt 0 ] && passed "${base_parts[@]}"; then
    keep_set "$base_key" "$logs/base" "$base_render" "${base:0:7}, the base" || status=1
  fi
  [ -d "$store" ] || { echo "no sets kept"; return "$status"; }
  while IFS= read -r old; do drop "$old" || status=1; done < <(ls -dt "$store"/*/ | tail -n +$((keep + 1)))
  echo "$(ls -d "$store"/*/ | wc -l) sets kept, $(du -sh "$store" | cut -f1), in $store"
  return "$status"
}

# render_diff: the pictures the change moved, once both sets are rendered.
render_diff() {
  local why
  why=$(test/fixtures-dir.sh 2>&1 > /dev/null) || { echo "SKIP render diff: $why"; return 77; }
  [ -n "$base" ] || { echo "FAILED no base: HEAD and $base_ref share no commit"; return 1; }
  test/render-diff.sh "$base_render" out/render out/render-diff
}

# The base's tree, outside git, with this checkout's saved answers beside it.
base_ref=${STONKS_RENDER_BASE:-origin/dev}
base=$(git merge-base HEAD "$base_ref" 2> /dev/null)
if [ -n "$base" ]; then
  mkdir -p "$logs/base"
  git archive "$base" | tar -x -C "$logs/base"
  fixtures=$(test/fixtures-dir.sh 2> /dev/null) && ln -s "$fixtures" "$logs/base/test/fixtures"
fi
# Each set's name; none without the saved answers, where the renders skip.
head_key=$(test/render-key.sh 2> /dev/null) || head_key=""
base_key=""
[ -z "$base" ] || base_key=$(test/render-key.sh "$logs/base" 2> /dev/null) || base_key=""

# out/render holds this run's pictures only, so the diff reads no other's.
rm -rf out/render
head_set=$(kept "$head_key") || head_set=""
if [ -n "$head_set" ]; then
  mkdir -p out/render && cp "$head_set"/*.png out/render/
  echo "== the head's renders: kept as $head_key, $(cat "$head_set/drawn")"
fi
# The base's renders: kept, the head's when the same files draw both, or
# drawn here.
base_render=""
draw_base=""
if [ -n "$base" ]; then
  if base_set=$(kept "$base_key"); then
    base_render=$base_set
    echo "== the base's renders: kept as $base_key, $(cat "$base_set/drawn")"
  elif [ -n "$base_key" ] && [ "$base_key" = "$head_key" ]; then
    base_render=out/render
    echo "== the base's renders: the head's, which the same files draw"
  else
    base_render=$logs/base-render
    draw_base=1
  fi
fi

# Longest first, as measured. The renders each set this run draws run in
# parts, two each when it draws both, else four. Each part's number in the
# queue goes in head_parts or base_parts, so its set is kept only once every
# part passed.
head_parts=()
base_parts=()
start "nothing-jumps layout harness" bash test/qml/layout.sh
if [ -z "$head_set" ]; then
  parts=4
  [ -z "$draw_base" ] || parts=2
  for part in $(seq "$parts"); do
    head_parts+=("${#labels[@]}")
    start "offscreen renders, $part of $parts" bash test/qml/render.sh --part "$part/$parts"
  done
fi
if [ -n "$draw_base" ]; then
  # A base from before the parts renders whole.
  if grep -q -- '--part I/N' "$logs/base/test/qml/render.sh"; then
    for part in 1 2; do
      base_parts+=("${#labels[@]}")
      start "base renders, $part of 2" env STONKS_VISUAL_DIR="$base_render" bash "$logs/base/test/qml/render.sh" --part "$part/2"
    done
  else
    base_parts+=("${#labels[@]}")
    start "base renders" env STONKS_VISUAL_DIR="$base_render" bash "$logs/base/test/qml/render.sh"
  fi
fi
start "long list harness" bash test/qml/long-list.sh
start "README pictures, into a scratch folder" env STONKS_README_OUT="$logs/readme" bash test/qml/readme.sh
start "popup motion harness" bash test/qml/popup-motion.sh
start "tophat guards (no screen)" bash test/tophat.sh self-check
fill

drain
run "render diff, against ${base:0:7} (out/render-diff/)" render_diff
run "keep the renders this run drew" keep_sets
verdict
