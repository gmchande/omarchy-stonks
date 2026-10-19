#!/usr/bin/env bash
# The window's chart in motion through the real App and Service with real
# Qt keys and pointer: repaints, replays, the day and the hero, the draw-in
# judged on rendered frames, a wrong draw-in failing that same judgement, a
# joining row's day line drawing in and a list switch's rows drawn at once,
# the header's animal closing and opening its eyes at the bell and changing
# at once on every other change, and a closing surface holding still. HOME
# and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree window-motion.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testHistoryFeed: historyFeed'
# The animal's sleep steps hold the clock where they set it.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  property bool testClockHeld: false'
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.testClockHeld ? root.now : Math.floor(Date.now() \/ 1000) }/'
scratch_home v1-data.json grvc.stonks.json
# The draw-in check runs on wrong draw-ins too: the real animation made
# 160 ms, 400 ms, and none; and the dim's on wrong dims, its wait and ease.
patch_copy plugin/ChartMotion.qml '/^  property real reveal: 1$/a\  property alias testDrawIn: drawInAnim\n  property alias testSlow: slowTimer\n  property alias testDim: dimAnim'
frame_tools
export QT_QPA_PLATFORM=offscreen
run_qs 110
finish "WINDOW MOTION DONE"
