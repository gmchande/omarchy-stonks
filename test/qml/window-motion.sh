#!/usr/bin/env bash
# The real App and Service: actions runs the replay keys, pointer, chart
# selection and market sleep state for all.sh. With no chapter, charts and
# rows run their rendered-motion and position judgments for review.sh.
# HOME and curl are scratch.
chapter=${1:-${STONKS_MOTION_FLOW:-}}
case "$chapter" in
  "")
    for chapter in charts rows; do bash "$0" "$chapter" || exit "$?"; done
    exit 0 ;;
  actions|charts|rows) export STONKS_MOTION_FLOW="$chapter" ;;
  *) echo "FAIL unknown window-motion chapter: $chapter"; exit 1 ;;
esac
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
patch_copy plugin/ChartMotion.qml '/^  property real reveal: 1$/a\  property alias testDrawIn: drawInAnim\n  property alias testSlow: slowTimer\n  property alias testDim: dimAnim\n  property alias testReplay: replayAnim'
frame_tools
export QT_QPA_PLATFORM=offscreen
run_qs 110
finish "WINDOW MOTION DONE"
