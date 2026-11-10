#!/usr/bin/env bash
# The maintainer's review kit: how Stonks looks and moves. Run it by hand
# before merging a visible change, a contributor's included, on their branch,
# and before a release. It is neither test/all.sh nor CI: pictures and frame
# timings vary by machine, and the saved answers are private. Without them
# (test/fixtures-dir.sh) almost all of it skips.
#
# - The offscreen renders (out/render/): every state on every kind of
#   listing, in each look where the look draws it differently, for your
#   eyes, and the panel's place under its pill (popup-anchor.qml). The
#   base's too, from its own files and renderer, so the render diff
#   (test/render-diff.sh) lists every picture the change moved, side by
#   side in out/render-diff/. The base is the merge-base with origin/dev,
#   or with STONKS_RENDER_BASE (a release's tag, before the next release).
#   The base draws every state but the panel-anchor ones, whose check
#   judges the base's own harness on today's Omarchy, not the change.
# - Nothing jumps: positions across looks, symbols, and ranges.
# - Window and panel motion, judged on rendered frames (test/qml/frames.js)
#   and the rows' places.
# - The long list: a power user's 154 symbols, on wall-clock budgets.
# - Omarchy 4.0.6, the oldest shell Stonks works on (test/old-shell.sh): the
#   bar's renders on its shell, in out/render-omarchy-4.0/ with their own
#   diff in out/render-diff-omarchy-4.0/; the window and panel motion, on
#   its curve; the screenshot; and the panel, its keys and the window rows,
#   failing as on the installed one on a TypeError or the plugin's Qt
#   warnings, and on a panel that shows nothing (popup.qml).
#
# Each set of renders, the head's and the base's on each shell, is drawn
# once: a run keeps each set it draws whole under the name
# test/render-key.sh makes from everything that draws it, and a later run
# with that name uses the kept set instead. The log says which sets were
# kept and which run drew them.
# The newest 20 sets stay, about 22 MB each, in the git folder every
# worktree shares. --fresh reuses none and replaces what it draws: a
# release's run, which has to catch a change from outside the repo
# (CONTRIBUTING.md, Releases).
#
# The queue, the lock, and the verdict are test/queue.sh's: one run of
# either runner at a time. It takes --fresh, and passes any other option on
# to queue.sh, which refuses it.
fresh=""
for arg; do
  shift
  if [ "$arg" = --fresh ]; then fresh=1; else set -- "$@" "$arg"; fi
done
source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"
# What a kept set says drew it: HEAD, and whether the checkout had edits.
commit=$(git rev-parse -q --verify HEAD)
edited=$(git status --porcelain)

store="$(git rev-parse --path-format=absolute --git-common-dir)/stonks-renders"
keep=20

# kept NAME: the kept set NAME's folder, marked as just used, when this run
# may use it. A set is whole while its note of who drew it is there: the
# note is written last, and goes first when the set goes.
kept() {
  [ -z "$fresh" ] && [ -n "$1" ] && [ -f "$store/$1/drawn" ] && touch "$store/$1" && echo "$store/$1"
}

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
  local what=${commit:0:7} status=0 old i
  [ -z "$edited" ] || what="$what with uncommitted edits"
  for i in "${!draw_keys[@]}"; do
    # shellcheck disable=SC2086 # the parts' numbers, one word each
    passed ${draw_parts[i]} || continue
    STONKS_SHELL=${draw_shells[i]} STONKS_RENDER_STATES=${draw_patterns[i]} keep_set "${draw_keys[i]}" "${draw_trees[i]}" "${draw_folders[i]}" \
      "$([ "${draw_trees[i]}" = . ] && echo "$what" || echo "${base:0:7}, the base")${draw_names[i]}" || status=1
  done
  [ -d "$store" ] || { echo "no sets kept"; return "$status"; }
  while IFS= read -r old; do drop "$old" || status=1; done < <(ls -dt "$store"/*/ | tail -n +$((keep + 1)))
  echo "$(ls -d "$store"/*/ | wc -l) sets kept, $(du -sh "$store" | cut -f1), in $store"
  return "$status"
}

# render_diff BASE HEAD OUT: the pictures the change moved, once both sets
# are rendered.
render_diff() {
  local why
  why=$(test/fixtures-dir.sh 2>&1 > /dev/null) || { echo "SKIP render diff: $why"; return 77; }
  test/render-diff.sh "$@"
}

# With no base nothing is compared, so the run fails: it never ends ALL PASS
# on a base's name mistyped or not fetched.
no_base() {
  echo "FAILED no base: HEAD and $base_ref share no commit. Fetch it, or name the base in STONKS_RENDER_BASE."
  return 1
}

# The base's tree, outside git, with this checkout's saved answers beside it.
base_ref=${STONKS_RENDER_BASE:-origin/dev}
base=$(git merge-base HEAD "$base_ref" 2> /dev/null)
if [ -n "$base" ]; then
  mkdir -p "$logs/base"
  git archive "$base" | tar -x -C "$logs/base"
  fixtures=$(test/fixtures-dir.sh 2> /dev/null) && ln -s "$fixtures" "$logs/base/test/fixtures"
fi

# The pictures are drawn on two shells: every one on the installed shell,
# into out/render, and the bar's, the pill sheets, on Omarchy 4.0.6's
# (test/old-shell.sh), into out/render-omarchy-4.0, each with its own render
# diff. The panel and the window draw the same on both, so 4.0 adds only
# what its own bar draws. A shell that can't be had names no folder, and
# its renders fail. A base from before Stonks' harnesses could take another
# shell (STONKS_SHELL, test/qml/lib.sh) draws on the installed one alone, so
# on 4.0 the head's pictures have no diff.
old_shell=$(test/old-shell.sh) || old_shell=/no-omarchy-4.0.6-shell
shells=("" "$old_shell")
names=("" " on Omarchy 4.0.6")
suffixes=("" "-omarchy-4.0")
patterns=("" '*pill-sheet*')
base_takes_shell=""
[ -z "$base" ] || ! grep -q STONKS_SHELL "$logs/base/test/qml/lib.sh" || base_takes_shell=1

# Each set this run draws: its key, tree, folder, shell, name, and the
# queue numbers of its parts (keep_sets). The head's and the base's on each
# shell are kept, the head's on that shell when the same files draw both,
# or drawn here. out/render* holds this run's pictures only, so a diff reads
# no other's.
draw_keys=() draw_trees=() draw_folders=() draw_shells=() draw_names=() draw_parts=() draw_states=() draw_patterns=()
diffs=()
for i in "${!shells[@]}"; do
  shell=${shells[i]} name=${names[i]} pattern=${patterns[i]} head_render=out/render${suffixes[i]}
  rm -rf "$head_render"
  # Each set's name; none without the saved answers, where the renders skip.
  head_key=$(STONKS_SHELL=$shell STONKS_RENDER_STATES=$pattern test/render-key.sh 2> /dev/null) || head_key=""
  if head_set=$(kept "$head_key"); then
    mkdir -p "$head_render" && cp "$head_set"/*.png "$head_render/"
    echo "== the head's renders$name: kept as $head_key, $(cat "$head_set/drawn")"
  else
    draw_keys+=("$head_key") draw_trees+=(.) draw_folders+=("$head_render") draw_shells+=("$shell") draw_names+=("$name") draw_states+=(head) draw_patterns+=("$pattern")
  fi
  [ -n "$base" ] || continue
  if [ -n "$shell" ] && [ -z "$base_takes_shell" ]; then
    echo "== the base's renders$name: none, since ${base:0:7}'s harnesses draw on the installed shell alone"
    continue
  fi
  base_key=$(STONKS_SHELL=$shell STONKS_RENDER_STATES=$pattern test/render-key.sh "$logs/base" 2> /dev/null) || base_key=""
  if base_set=$(kept "$base_key"); then
    base_render=$base_set
    echo "== the base's renders$name: kept as $base_key, $(cat "$base_set/drawn")"
  elif [ -n "$base_key" ] && [ "$base_key" = "$head_key" ]; then
    base_render=$head_render
    echo "== the base's renders$name: the head's, which the same files draw"
  else
    base_render=$logs/base-render${suffixes[i]}
    draw_keys+=("$base_key") draw_trees+=("$logs/base") draw_folders+=("$base_render") draw_shells+=("$shell") draw_names+=("$name") draw_states+=(base) draw_patterns+=("$pattern")
  fi
  diffs+=("$base_render" "$head_render" "out/render-diff${suffixes[i]}" "$name")
done

# Longest first, as measured. A whole set this run draws runs in two parts,
# the head's in four when it is the only one; the bar's alone, in one. The
# head's whole set takes --part; the base's, by name, smooth and the rest,
# about half each, since --part would run its anchor check, which judges the
# base's own harness on today's Omarchy, not the change.
whole=0
for pattern in "${draw_patterns[@]}"; do [ -n "$pattern" ] || whole=$((whole + 1)); done
parts=2
[ "$whole" -gt 1 ] || parts=4
for i in "${!draw_keys[@]}"; do
  draw_parts+=("")
  tree=${draw_trees[i]} label="offscreen renders"
  [ "${draw_states[i]}" = head ] || label="base renders"
  if [ -n "${draw_patterns[i]}" ]; then
    draw_parts[i]+=" ${#labels[@]}"
    start "$label${draw_names[i]}, the bar's" env STONKS_SHELL="${draw_shells[i]}" STONKS_VISUAL_DIR="${draw_folders[i]}" bash "$tree/test/qml/render.sh" "${draw_patterns[i]}"
  elif [ "${draw_states[i]}" = head ]; then
    for part in $(seq "$parts"); do
      draw_parts[i]+=" ${#labels[@]}"
      start "$label${draw_names[i]}, $part of $parts" env STONKS_SHELL="${draw_shells[i]}" STONKS_VISUAL_DIR="${draw_folders[i]}" bash test/qml/render.sh --part "$part/$parts"
    done
  else
    part=0
    for states in '!(popup-anchor-*|!(*smooth*))' '!(popup-anchor-*|*smooth*)'; do
      part=$((part + 1))
      draw_parts[i]+=" ${#labels[@]}"
      start "$label${draw_names[i]}, $part of 2" env STONKS_SHELL="${draw_shells[i]}" STONKS_VISUAL_DIR="${draw_folders[i]}" bash "$tree/test/qml/render.sh" "$states"
    done
  fi
done
start "nothing-jumps layout harness, surfaces" bash test/qml/layout.sh surfaces
start "window motion harness" bash test/qml/window-motion.sh
start "window motion harness on Omarchy 4.0.6" env STONKS_SHELL="$old_shell" bash test/qml/window-motion.sh
start "nothing-jumps layout harness, live" bash test/qml/layout.sh live
start "long list harness" bash test/qml/long-list.sh
start "nothing-jumps layout harness, sizes" bash test/qml/layout.sh sizes
start "panel motion harness" bash test/qml/popup-motion.sh
start "panel motion harness on Omarchy 4.0.6" env STONKS_SHELL="$old_shell" bash test/qml/popup-motion.sh
start "camera harness on Omarchy 4.0.6" env STONKS_SHELL="$old_shell" QT_SCALE_FACTOR=1 bash test/qml/camera.sh
for walk in keys mouse saving fetching; do
  start "$walk walk on Omarchy 4.0.6" env STONKS_SHELL="$old_shell" bash "test/qml/$walk.sh"
done
fill

run "installed theme diagnostic" bun test/themes.js
drain
for ((i = 0; i < ${#diffs[@]}; i += 4)); do
  run "render diff${diffs[i + 3]}, against ${base:0:7} (${diffs[i + 2]}/)" render_diff "${diffs[@]:i:3}"
done
[ -n "$base" ] || run "render diff, against a base" no_base
run "keep the renders this run drew" keep_sets
verdict
