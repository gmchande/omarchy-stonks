#!/usr/bin/env bash
# Real saves and deadline wakes, malformed overnight recovery, and work
# queued before/while the screens are off. Everything owned by this run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree resilience.qml
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testGate: yahooGate\n  readonly property alias testFeed: feed\n  readonly property alias testHistory: historyFeed\n  readonly property alias testFundamentals: fundamentalsFeed\n  readonly property alias testDataFile: dataFile'
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/property int clockOffset: 0\n  function wallSecond() { return Math.floor(Date.now() \/ 1000) + root.clockOffset }/'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeys: keyCatcher'
printf '%s\n' '{"version":1,"symbols":["BTC-USD"],"featured":"BTC-USD","order":"manual","style":"smooth","range":"1D"}' > "$HOME/.config/omarchy/grvc.stonks.json"
# Even a failed test must restore the one scratch directory before cleanup.
trap 'chmod u+w "$HOME/.config/omarchy"; quickshell_exit; rm -rf "$work"' EXIT
export QT_QPA_PLATFORM=offscreen
run_qs 90
if rg -q 'PASS failed atomic save keeps' "$work/log"; then
  sed -i '\|WARN scene: QML FileView at @plugin/Service.qml.*Write of .*grvc.stonks.json failed: Unknown error when opening file\.|d' "$work/log"
fi
finish "RESILIENCE DONE"
