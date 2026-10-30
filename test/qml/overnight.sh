#!/usr/bin/env bash
# Overnight prices through the real Service, feeds, and App window, on a
# clock the harness sets: what Robinhood is asked, when, and how much (the
# pill's two questions side by side with nothing open, the rest's at the
# first open, r for the chart on show, the five-minute night refresh, a
# failed answer and a refusal, a symbol gone, 110 instruments and 80 prints);
# and how its answers reach the line under the price, the header, the
# animal, a scrub, a replay, search's preview, and the rows. The rules on
# each saved moment are saved.test.js's. HOME and curl are scratch; the fake
# curl answers from test/fixtures/moments.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree overnight.qml
# The later saved moments hold NEST's day alone: the other symbols' quotes
# fail there, and a 200 ms retry pause keeps their retries from holding up
# a refresh.
patch_copy plugin/QuoteFeed.qml 's/interval: 2500/interval: 200/'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher'
# The harness owns the clock.
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.now }/'
# The failure step reads the feed's answers; the midnight walk takes a
# quote's regular price away.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testOvernightFeed: overnightFeed\n  readonly property alias testAllDayFeed: allDayFeed\n  readonly property alias testFeed: feed\n  readonly property alias testYahooGate: yahooGate\n  readonly property alias testRobinhoodGate: robinhoodGate'
# A step hands Robinhood's prints run its output by hand (`FetchRun`).
patch_copy plugin/OvernightFeed.qml '/property var landing: null/a\  readonly property alias testRun: fetchRun'
scratch_home moments/data.json grvc.stonks.json
echo weekend > "$STONKS_FAKE_STATE/overnight.set"
# Robinhood's answers wait from the start, so the first step sees what the
# pill's first live answer asks for while it is out.
touch "$STONKS_FAKE_STATE/ROBINHOOD.hold"
export QT_QPA_PLATFORM=offscreen
run_qs 60
finish "OVERNIGHT DONE"
