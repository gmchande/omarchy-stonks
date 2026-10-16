#!/usr/bin/env bash
# The window's rows by hand through the real App and Service with real Qt
# keys and pointer: removal, the sorted view's guards, help, moves by keys,
# drag, and the wheel, the cursor, rows held by a close, and the footer's
# notices. HOME, curl, and omarchy are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree window-rows.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testHistoryFeed: historyFeed'
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 110
finish "WINDOW ROWS DONE"
