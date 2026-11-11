#!/usr/bin/env bash
# What looks clickable acts: a real pointer on the real window (App.qml)
# shows a row's chart, drags a row to a new place, scrolls, opens a row's
# menu and the list menu and takes their lines, steps the order, the unit
# and the range, switches the look and the sounds, takes a screenshot,
# opens the key sheet, adds a stock found and removes it, and scrubs the
# chart. Each is judged by what the lists file and the surface then hold,
# never by where a thing is drawn. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree mouse.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 90
finish "MOUSE DONE"
