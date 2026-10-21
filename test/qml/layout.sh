#!/usr/bin/env bash
# Nothing jumps: positions across looks, symbols, and ranges, offscreen.
# No surface is added to the running shell.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree layout.qml
export QT_QPA_PLATFORM=offscreen
export STONKS_CALENDARS="$plugin/calendars.json"
frame_tools
run_qs 180
finish "LAYOUT DONE"
