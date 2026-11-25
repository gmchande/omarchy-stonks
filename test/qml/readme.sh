#!/usr/bin/env bash
# Renders the README's pictures again in one command at a release
# (CONTRIBUTING.md, Releases): the real panel, window, and pill (readme.qml)
# on the demo watchlist (test/demo.json), quoted from the capture named below
# (test/capture-demo.sh) a minute after it, in Tokyo Night at twice the
# scale; one panel at night, from the night's capture named below; and one
# panel in Catppuccin Latte. The night and the light panel each take a run
# of their own. Writes media/*.png, or into STONKS_README_OUT to look at
# first.
#
# `readme.sh --marketplace SCALE DIR` writes no README picture: it grabs
# the maintainer's marketplace picture's two, drawn at SCALE, into DIR:
# popup.png, Nebius's (NBIS) smooth panel, and strip.png, its pill on the
# bar, from the capture named below with NBIS alone on the list.
# The panel's card window is CardWindow.qml, as in keys.sh. HOME and curl
# are scratch.
scale=2 keep=""
if [ "${1:-}" = --marketplace ]; then
  [ $# -eq 3 ] || { echo "usage: readme.sh [--marketplace SCALE DIR]" >&2; exit 2; }
  scale=$2 keep=$(realpath -m "$3")
fi
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
out="${STONKS_README_OUT:-$plugin/media}"
# The captures the committed pictures show. Named, not the newest, so a new
# capture changes nothing until the commit that renders from it names it.
# The night's is the demo watchlist on a Tuesday at 23:49, with Robinhood's
# quotes, and its picture shows SPY. The marketplace's is Monday evening
# after hours, with NBIS up on the day, and its list holds NBIS alone.
demo=$(jq -c '.symbols' "$plugin/test/demo.json")
night_moment=night-2026-11-24-2349 night_symbol=SPY
if [ -n "$keep" ]; then
  export STONKS_README_MARKETPLACE=NBIS
fi

# at_moment MOMENT LISTED [LISTS]: the next run's watchlist is LISTED, with
# the lists LISTS (the demo's own by default), quoted from MOMENT, its clock
# standing still a minute after it. Stonks' saved quotes from a run before
# are cleared, so none of them leaks in from another moment.
at_moment() {
  [ -d "$STONKS_FIXTURES/moments/$1" ] || { echo "FAIL no saved capture $1"; exit 1; }
  local stamp=${1#*-}
  export STONKS_README_AT=$(( $(date -d "${stamp:0:10} ${stamp:11:2}:${stamp:13:2}" +%s) + 60 ))
  jq --argjson listed "$2" --argjson lists "${3:-null}" \
    '. + { hinted: true, symbols: $listed } | if $lists then .lists = $lists else . end' \
    "$plugin/test/demo.json" > "$HOME/.config/omarchy/grvc.stonks.json"
  echo "$1" > "$STONKS_FAKE_STATE/overnight.set"
  rm -rf -- "$XDG_CACHE_HOME/grvc.stonks"
  echo "the watchlist $2 at $1"
}

plugin_tree readme.qml
card_window
# Offscreen, a grab's empty pixels are black, not the window's colour, so
# the window's grab takes a ground of that colour under the body.
patch_copy plugin/App.qml '/^      Loader {$/i\      Rectangle { anchors.fill: parent; color: window.color }'
# The pills on their strips open no panel of their own.
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
if [ -n "$keep" ]; then
  at_moment jump-2026-11-23-1756 '["NBIS"]' '[]'
else
  at_moment demo-2026-10-19-1146 "$demo"
fi
mkdir -p "$HOME/.local/state/omarchy/current"
tokyo=/usr/share/omarchy/themes/tokyo-night
ln -sfn "$tokyo" "$HOME/.local/state/omarchy/current/theme"
export STONKS_README_RAW="${keep:-$work/raw}"
mkdir -p "$STONKS_README_RAW"
export QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR=$scale
run_qs 90
if [ -z "$keep" ]; then
  # next_run: keeps the run's log, and its failure if it failed, for finish.
  failed=0
  : > "$work/log.all"
  next_run() {
    cat "$work/log" >> "$work/log.all"
    [ "$code" -eq 0 ] || failed=$code
  }
  next_run
  # The night, in a run of its own from its capture.
  at_moment "$night_moment" "$demo"
  export STONKS_README_NIGHT=$night_symbol
  run_qs 90
  next_run
  unset STONKS_README_NIGHT
  # The light picture in a run of its own, in Catppuccin Latte from the
  # start, under Adwaita's light GTK theme, as Omarchy sets for a light
  # theme (omarchy-theme-set-gnome): Qt reads it, which draws the rows'
  # scrollbar, only as it starts.
  at_moment demo-2026-10-19-1146 "$demo"
  ln -sfn /usr/share/omarchy/themes/catppuccin-latte "$HOME/.local/state/omarchy/current/theme"
  export STONKS_README_LIGHT=1 GTK_THEME=Adwaita
  run_qs 90
  next_run
  mv "$work/log.all" "$work/log"
  code=$failed
fi
raw=$STONKS_README_RAW
if [ -n "$keep" ]; then
  for grab in popup strip; do
    [ -s "$raw/$grab.png" ] || echo "FAIL $grab was not grabbed" >> "$work/log"
  done
  finish "README DONE"
fi
grabs=(forms scrub lists retro window night light)

# Each picture as a palette PNG, so a clone stays small, the pill's forms
# with the black between their strips clear. Only this run's grabs make
# them: a failed step leaves its grab missing, and finish names it.
mkdir -p "$out"
files=()
for name in pill scrub lists retro window night light; do files+=("$out/$name.png"); done
rm -f -- "${files[@]}"
grabbed() { local grab; for grab in "${grabs[@]}"; do [ -s "$raw/$grab.png" ] || return 1; done; }
if [ "$code" -eq 0 ] && grabbed; then
  small() { local dest=$1; shift; magick "$@" -strip -dither None -colors 128 "PNG8:$dest"; }
  small "$out/pill.png" "$raw/forms.png" -transparent black
  for name in scrub lists retro window night light; do small "$out/$name.png" "$raw/$name.png"; done
fi
missing=0
for file in "${files[@]}"; do
  [ -s "$file" ] || { echo "FAIL ${file##*/} was not written" >> "$work/log"; missing=1; }
done
[ "$missing" = 1 ] || echo "PASS the README's ${#files[@]} pictures render"
finish "README DONE"
