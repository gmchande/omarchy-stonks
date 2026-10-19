#!/usr/bin/env bash
# Overnight prices through the real Service, feeds, and App window, on a
# clock the harness sets: which listings Robinhood is asked for, when, and
# for which span; the 1D chart as one New York calendar day, midnight to
# midnight, on a weekday, a weekend, and Sunday night; search's preview of a
# symbol in All and of one not yet added; the overnight line under the price
# and its dimming; a scrub of the night leaving the rows on now; none for a
# symbol that has not traded tonight, an index, or a cryptocurrency, none at
# the weekend; a scrub to the day's end after the close reading the close,
# an index's and a stock's, and Tokyo's row on its close while it follows a
# Nasdaq scrub; a failed answer asked again; the first live night's lone
# print, drawn and scrubbed in both looks, and its line on 1M at rest and
# scrubbed; a night held open across midnight, the chart staying on
# Tuesday until Wednesday's first print, then measured from Tuesday's close
# at rest and scrubbed; and two names Robinhood does not trade all day,
# KILN and BOLT, with no overnight line from a stray night trade, Yahoo's
# own day laid out a print a step from the left edge, keys stepping print to
# print, and SPY on Yahoo's day while Robinhood's instruments are down;
# exchange times named by zone for a reader in New York; an index with
# no pre-market, no tail after its close, and its next open; and the
# header's animal asleep on Saturday and for a stock whose night doesn't
# trade, awake for one whose night does and for a cryptocurrency, woken by
# a scrub, in both looks. HOME
# and curl are scratch; the fake curl answers from test/fixtures/moments.
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
scratch_home moments/data.json grvc.stonks.json
echo weekend > "$STONKS_FAKE_STATE/overnight.set"
export QT_QPA_PLATFORM=offscreen
run_qs 60
finish "OVERNIGHT DONE"
