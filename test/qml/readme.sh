#!/usr/bin/env bash
# Renders the README's pictures again in one command at a release
# (CONTRIBUTING.md, Releases): the real popup, window, and pill (readme.qml)
# on the demo watchlist (test/demo.json), quoted from the capture named below
# (test/capture-demo.sh) a minute after it, in Tokyo Night at twice the
# scale, plus one popup in Catppuccin Latte. Writes media/*.png, or into
# STONKS_README_OUT to look at first.
#
# `readme.sh --marketplace SCALE DIR` writes no README picture: it grabs
# the maintainer's marketplace picture's two, drawn at SCALE, into DIR:
# popup.png, NVDA's retro popup, and strip.png, its pill on the bar, from
# the capture named below with NVDA on the demo watchlist.
# The popup's card window is CardWindow.qml, as in keys.sh. HOME and curl
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
# The marketplace's is a weekday noon in New York that holds NVDA.
moment=demo-2026-10-19-1146
listed=$(jq -c '.symbols' "$plugin/test/demo.json")
if [ -n "$keep" ]; then
  moment=watch-2026-10-26-1200
  listed=$(jq -c '.symbols + ["NVDA"]' "$plugin/test/demo.json")
  export STONKS_README_MARKETPLACE=NVDA
fi
[ -d "$STONKS_FIXTURES/moments/$moment" ] || { echo "FAIL no saved capture $moment"; exit 1; }
stamp=${moment#*-}
at=$(( $(date -d "${stamp:0:10} ${stamp:11:2}:${stamp:13:2}" +%s) + 60 ))
echo "the demo watchlist at $moment"

plugin_tree readme.qml
cp "$here/CardWindow.qml" "$root/plugin/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testBody: root.body\n  readonly property alias testCard: panel'
# Offscreen, a grab's empty pixels are black, not the window's colour, so
# the window's grab takes a ground of that colour under the body.
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher'
patch_copy plugin/App.qml '/^      Loader {$/i\      Rectangle { anchors.fill: parent; color: window.color }'
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testAllDay: allDayFeed\n  readonly property alias testOvernight: overnightFeed'
# The clock stands still a minute after the capture.
patch_copy plugin/Service.qml "s/property int now: Math.floor(Date.now() \/ 1000)/property int now: $at/"
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.now }/'
# The pills on their strips open no popup of their own.
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
jq --argjson listed "$listed" '. + { hinted: true, symbols: $listed }' "$plugin/test/demo.json" > "$HOME/.config/omarchy/grvc.stonks.json"
echo "$moment" > "$STONKS_FAKE_STATE/overnight.set"
mkdir -p "$HOME/.local/state/omarchy/current"
tokyo=/usr/share/omarchy/themes/tokyo-night
ln -sfn "$tokyo" "$HOME/.local/state/omarchy/current/theme"
export STONKS_README_RAW="${keep:-$work/raw}"
mkdir -p "$STONKS_README_RAW"
export QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR=$scale
run_qs 90
raw=$STONKS_README_RAW
if [ -n "$keep" ]; then
  for grab in popup strip; do
    [ -s "$raw/$grab.png" ] || echo "FAIL $grab was not grabbed" >> "$work/log"
  done
  finish "README DONE"
fi
grabs=(forms scrub lists retro window light)

# Each picture as a palette PNG, so a clone stays small, the pill's forms
# with the black between their strips clear. Only this run's grabs make
# them: a failed step leaves its grab missing, and finish names it.
mkdir -p "$out"
files=()
for name in pill scrub lists retro window light; do files+=("$out/$name.png"); done
rm -f -- "${files[@]}"
grabbed() { local grab; for grab in "${grabs[@]}"; do [ -s "$raw/$grab.png" ] || return 1; done; }
if [ "$code" -eq 0 ] && grabbed; then
  small() { local dest=$1; shift; magick "$@" -strip -dither None -colors 128 "PNG8:$dest"; }
  small "$out/pill.png" "$raw/forms.png" -transparent black
  for name in scrub lists retro window light; do small "$out/$name.png" "$raw/$name.png"; done
fi
missing=0
for file in "${files[@]}"; do
  [ -s "$file" ] || { echo "FAIL ${file##*/} was not written" >> "$work/log"; missing=1; }
done
[ "$missing" = 1 ] || echo "PASS the README's ${#files[@]} pictures render"
finish "README DONE"
