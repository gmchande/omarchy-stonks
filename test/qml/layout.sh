#!/usr/bin/env bash
# Nothing jumps: positions across looks, symbols, and ranges, offscreen.
# No surface is added to the running shell.
# Each chapter has a fresh surface and its own 180-second hang limit, so
# the live marks and text-size sweep don't spend the surfaces' time left.
# With no chapter named it runs all three in turn; a queue may run
# `layout.sh surfaces`, `layout.sh live` and `layout.sh sizes` side by side.
chapter=${1:-${STONKS_LAYOUT_FLOW:-}}
case "$chapter" in
  "")
    for chapter in surfaces live sizes; do
      echo "== layout $chapter (180 s limit)"
      layout_began=$SECONDS
      bash "$0" "$chapter" || exit "$?"
      echo "layout $chapter passed in $((SECONDS - layout_began)) s"
    done
    exit 0 ;;
  surfaces|live|sizes) export STONKS_LAYOUT_FLOW="$chapter" ;;
  *) echo "FAIL unknown layout chapter: $chapter"; exit 1 ;;
esac
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree layout.qml
# The side bar's pill loads no popup: the offscreen platform has no popup
# window to put one in.
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
export QT_QPA_PLATFORM=offscreen
export STONKS_CALENDARS="$plugin/calendars.json"
frame_tools
run_qs 180
finish "LAYOUT DONE"
