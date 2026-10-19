#!/usr/bin/env bash
# The fetch policy through the real Plugin, Service, App, and two pills, on a
# clock the harness sets: requests per listing at each moment against each
# market's cadence, with nothing open and with the window open, for a busy
# stock, a thin one, an ETF, an index, a cryptocurrency, London, Tokyo at
# lunch, and Toronto; an offline start on saved quotes and the network's
# return; an open that finds the rows fresh; r twice; Yahoo refusing and
# recovering; a network back within seconds; a list of 50 every minute; the
# pill's wheel; an add, a removal and its undo; a search's preview; and, in a
# second run, a US holiday while London and Toronto trade. HOME and curl are
# scratch; the fake curl answers from test/fixtures/moments/fetch-2026-10-07
# and listings-2026-10-07-1455.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree fetch.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testWindow: window'
# The harness owns the clock, from Wednesday 7 October at 05:59 New York.
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.now }/'
patch_copy plugin/Service.qml 's/property int now: Math.floor(Date.now() \/ 1000)/property int now: 1791367140/'
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testPreviewFeed: previewFeed\n  readonly property alias testYahooGate: yahooGate\n  readonly property alias testDataFile: dataFile'
patch_copy plugin/QuoteFeed.qml 's/interval: 2500/interval: 200/'
# The pills' popups stay unloaded, and the window host asks a stand-in, not
# the owner's Hyprland (as range.sh).
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
patch_copy plugin/WindowHost.qml '/readonly property bool opened:/a\  property var hyprlandStandIn: null'
patch_copy plugin/WindowHost.qml 's/Hyprland\.\(toplevels\|focusedWorkspace\|dispatch\)/root.hyprlandStandIn.\1/g'
# Whether every screen is off is asked of the screens the harness hands the
# host, stand-ins that answer as they are set.
patch_copy plugin/WindowHost.qml 's/Hyprland\.refreshMonitors()/root.monitors.forEach(function(m) { m.refresh() })/g'
export QT_QPA_PLATFORM=offscreen

# The main run starts offline, with last session's quotes saved: NEST at
# Tuesday's close and London's Thursday.
scratch_home fetch-watchlist.json grvc.stonks.json
echo fetch-2026-10-07 listings-2026-10-07-1455 > "$STONKS_FAKE_STATE/overnight.set"
touch "$STONKS_FAKE_STATE/YAHOO.offline"
mkdir -p "$XDG_CACHE_HOME/grvc.stonks"
bun -e '
  const { load } = await import(process.argv[1] + "/test/load.js")
  const Quote = load("Quote.js")
  const read = name => JSON.parse(require("fs").readFileSync(process.env.STONKS_FIXTURES + "/" + name, "utf8"))
  const saved = q => ({ quote: Quote.parseChart(q), receivedAt: Quote.parseChart(q).marketTime })
  console.log(JSON.stringify({ version: 1, quotes: {
    NEST: saved(read("moments/2026-10-06-1800/nest.json")),
    "SHEL.L": saved(read("shel-l-day.json"))
  } }))
' "$plugin" > "$XDG_CACHE_HOME/grvc.stonks/quotes.json"
run_qs 400
mv "$work/log" "$work/main.log"

# The holiday run: New York closed on 7 October, London and Toronto open.
rm -rf "$STONKS_FAKE_STATE" "$XDG_CACHE_HOME/grvc.stonks"
mkdir -p "$STONKS_FAKE_STATE"
echo fetch-2026-10-07 listings-2026-10-07-1455 > "$STONKS_FAKE_STATE/overnight.set"
scratch_home fetch-watchlist.json grvc.stonks.json
patch_copy plugin/calendars.json 's/"2026-11-26": *"Thanksgiving Day"/"2026-10-07": "Fetch holiday", &/'
main_code=$code
STONKS_FETCH_RUN=holiday run_qs 120
[ "$main_code" -ne 0 ] && code=$main_code
cat "$work/main.log" "$work/log" > "$work/both.log"
mv "$work/both.log" "$work/log"

if ! rg -q -F "FETCH DONE" "$work/log"; then
  echo "FAIL the main run never reached FETCH DONE"
  code=1
fi
finish "FETCH HOLIDAY DONE"
