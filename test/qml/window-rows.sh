#!/usr/bin/env bash
# The window's rows by hand through the real App and Service with real Qt
# keys and pointer: removal, the sorted view's guards, help, moves by keys,
# drag, and the wheel, the cursor, rows held by a close, the chart's own
# clicks and keys, and the footer's notices. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree window-rows.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testHistoryFeed: historyFeed'
# The animal's sleep step holds the clock where it sets it.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  property bool testClockHeld: false'
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.testClockHeld ? root.now : Math.floor(Date.now() \/ 1000) }/'
# A replay held at its moment.
patch_copy plugin/ChartMotion.qml '/^  property real reveal: 1$/a\  property alias testReplay: replayAnim'
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 110
finish "WINDOW ROWS DONE"