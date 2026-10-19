#!/usr/bin/env bash
# The charts in sight fetched ahead through the real Service and App with
# real Qt pointer: on a range the hero's chart first, then each row in
# sight, on every kind of listing; a click on one shows at once; the hero's
# never waits on one; a new range drops the last one's; r, the day, half of
# Yahoo's budget, a paused Yahoo, every screen off, and a closed window
# fetch none; and a window taller than the history cache keeps the hero's
# chart on show. HOME and curl are scratch; the fake curl answers each
# listing's saved day of 7 October and its saved year.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree ahead.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testWindow: window'
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testHistoryFeed: historyFeed\n  readonly property alias testYahooGate: yahooGate\n  readonly property alias testFeed: feed'
scratch_home fetch-watchlist.json grvc.stonks.json
echo fetch-2026-10-07 listings-2026-10-07-1455 > "$STONKS_FAKE_STATE/overnight.set"
export QT_QPA_PLATFORM=offscreen
run_qs 150
finish "AHEAD DONE"
