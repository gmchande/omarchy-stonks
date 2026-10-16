#!/usr/bin/env bash
# Pointer-held sorting, featured sprite direction, native wheel scrolling,
# and the one cursor, its fill and the list menu's edge judged on rendered
# frames, in one offscreen window. No surface is added to the running shell.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree pointer.qml
frame_tools
export QT_QPA_PLATFORM=offscreen
export STONKS_WATCHLIST_FIXTURE="$STONKS_FIXTURES/list-22.json"
run_qs 110
finish "POINTER DONE"
