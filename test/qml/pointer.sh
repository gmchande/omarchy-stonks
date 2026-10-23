#!/usr/bin/env bash
# Pointer-held sorting, the featured day's direction, native wheel scrolling,
# one actionable cursor, and safe click targets in one offscreen window.
# No surface is added to the running shell.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree pointer.qml
export QT_QPA_PLATFORM=offscreen
export STONKS_WATCHLIST_FIXTURE="$STONKS_FIXTURES/list-22.json"
run_qs 110
finish "POINTER DONE"
