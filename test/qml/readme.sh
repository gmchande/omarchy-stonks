#!/usr/bin/env bash
# The README's pictures, rendered again in one command: the real popup,
# window, and pill (readme.qml) on the demo watchlist (test/tophat/demo.json),
# its quotes the saved capture named below (test/capture-demo.sh), the clock
# a minute after that capture, in Tokyo Night at twice the scale. Writes
# preview.png at the root and media/*.png, or all of them into
# STONKS_README_OUT (test/review.sh renders into a scratch folder, so the
# script can't quietly break). The popup's card window is CardWindow.qml, as
# in keys.sh. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
out="${STONKS_README_OUT:-$plugin/media}"
top="${STONKS_README_OUT:-$plugin}"
# The capture the committed pictures show. Named, not the newest, so a new
# capture changes nothing until the commit that renders from it names it.
moment=demo-2026-10-19-1146
[ -d "$STONKS_FIXTURES/moments/$moment" ] || { echo "FAIL no saved capture $moment (test/capture-demo.sh)"; exit 1; }
stamp=${moment#demo-}
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
jq '. + { hinted: true }' "$plugin/test/tophat/demo.json" > "$HOME/.config/omarchy/grvc.stonks.json"
echo "$moment" > "$STONKS_FAKE_STATE/overnight.set"
mkdir -p "$HOME/.local/state/omarchy/current"
ln -sfn /usr/share/omarchy/themes/tokyo-night "$HOME/.local/state/omarchy/current/theme"
export STONKS_README_RAW="$work/raw"
mkdir -p "$STONKS_README_RAW" "$out"
export QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR=2
run_qs 90

# Each picture as a palette PNG, so a clone stays small, the pill's forms
# with the black between their strips clear. Only this run's grabs make
# them: a step that failed leaves its grab missing, and finish names the
# failure.
raw=$STONKS_README_RAW
files=("$top/preview.png")
for name in pill scrub lists retro window; do files+=("$out/$name.png"); done
rm -f -- "${files[@]}"
grabbed() { local grab; for grab in popup strip forms scrub lists retro window; do [ -s "$raw/$grab.png" ] || return 1; done; }
fade=$(rg -m 1 -o -r '$1' 'PREVIEW_FADE ([0-9.]+ [0-9.]+)' "$work/log")
if [ "$code" -eq 0 ] && grabbed && [ -n "$fade" ]; then
  small() { local dest=$1; shift; magick "$@" -strip -dither None -colors 128 "PNG8:$dest"; }
  # preview.png, the README's first picture and the marketplace card's, at
  # 2:1: the bar across the width with the pill at its centre, and under it
  # the popup down to its list's header, fading out below its figures
  # (PREVIEW_FADE, from readme.qml). The ground is the theme's darkest
  # background, standing in for a wallpaper, so the bar and the card show
  # against it. The card crops the picture to a short box from the middle,
  # which keeps the pill and the chart.
  pw=$(magick identify -format '%w' "$raw/popup.png") ph=$(magick identify -format '%h' "$raw/popup.png")
  sh=$(magick identify -format '%h' "$raw/strip.png")
  bar=$(magick "$raw/strip.png" -format '%[pixel:p{0,0}]' info:)
  ground=$(sed -n 's/^darker_background = "\(#[0-9a-fA-F]*\)"/\1/p' "$HOME/.local/state/omarchy/current/theme/colors.toml")
  px() { awk -v share="$1" -v ph="$ph" 'BEGIN { printf "%d", share * ph + 0.5 }'; }
  solid=$(px "${fade% *}") keep=$(px "${fade#* }") gap=16
  h=$(( sh + gap + keep )) w=$(( (sh + gap + keep) * 2 ))
  small "$top/preview.png" -size "${w}x$h" "xc:$ground" \
    \( "$raw/strip.png" -background "$bar" -gravity center -extent "${w}x$sh" \) -gravity north -composite \
    \( "$raw/popup.png" -alpha set -gravity north -crop "${pw}x$keep+0+0" +repage \
      \( -size "${pw}x$solid" xc:white -size "${pw}x$(( keep - solid ))" gradient:white-black -append -alpha copy \) \
      -compose DstIn -composite \) \
    -compose Over -gravity north -geometry "+0+$(( sh + gap ))" -composite
  small "$out/pill.png" "$raw/forms.png" -transparent black
  for name in scrub lists retro window; do small "$out/$name.png" "$raw/$name.png"; done
fi
for file in "${files[@]}"; do
  if [ -s "$file" ]; then
    echo "PASS ${file##*/} $(magick identify -format '%wx%h' "$file"), $(( $(stat -c %s "$file") / 1024 )) KB"
  else
    echo "FAIL ${file##*/} was not written" >> "$work/log"
  fi
done
finish "README DONE"
