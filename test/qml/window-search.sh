#!/usr/bin/env bash
# Search in the window through the real App and Service with real Qt keys
# and pointer: results that belong to their query, a search out at a close,
# looking a result up on the hero before adding it, one preview across two
# surfaces, and a preview before the hero's first quote that leaves the hero
# its cap and P/E. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree window-search.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
# An add's step tops up Yahoo's budget, which the flows before it spent.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testHistoryFeed: historyFeed\n  readonly property alias testYahooGate: yahooGate'
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 110
finish "WINDOW SEARCH DONE"
