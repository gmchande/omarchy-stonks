#!/usr/bin/env bash
# Adding symbols in the window through the real App and Service with real
# Qt keys and pointer: an add held until its price is in, its row joining
# at its place, adds out at a close or a list switch, two adds in a row,
# adds from search, a joining row's day line drawn in, whole once drawn, and
# a stock put back, by u and by PUT BACK, asking for its quote at once.
# HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree window-adds.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testHistoryFeed: historyFeed'
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 110
finish "WINDOW ADDS DONE"
