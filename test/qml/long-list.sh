#!/usr/bin/env bash
# A power user's list through the real Plugin, Service, App, and a pill, on
# a clock the harness sets: 154 symbols, Wednesday 7 October from 15:00 New
# York, the window open. The list answers in one run of a few requests,
# refreshes whole every minute, has its strays judged on the chart while a
# refresh never waits behind more than one run of judging, and warns of
# nothing while every wait is Stonks' own pacing; Yahoo refusing still warns.
# HOME and curl are scratch; the fake curl answers from test/fixtures.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree long-list.qml
frame_tools
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testWindow: window'
# The harness owns the clock, from Wednesday 7 October at 15:00 New York.
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.now }/'
patch_copy plugin/Service.qml 's/property int now: Math.floor(Date.now() \/ 1000)/property int now: 1791399600/'
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testYahooGate: yahooGate'
# The pill's panel stays unloaded, and the window host asks a stand-in, not
# the owner's Hyprland (as fetch.sh).
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
patch_copy plugin/WindowHost.qml '/readonly property bool opened:/a\  property var hyprlandStandIn: null'
patch_copy plugin/WindowHost.qml 's/Hyprland\.\(toplevels\|focusedWorkspace\|dispatch\)/root.hyprlandStandIn.\1/g'
export QT_QPA_PLATFORM=offscreen
jq -n '{ version: 1, symbols: (["TALL001", "STRAY", "SHOP.TO", "BTC-USD"] + [range(5; 155) | "LONG" + ("00" + tostring)[-3:]]),
  featured: "TALL001", order: "manual", changeMode: "pct", style: "smooth", refreshIntervalSec: 60 }' > "$HOME/.config/omarchy/grvc.stonks.json"
run_qs 600
# One step spends the budget on purpose, and the harness checks that
# nothing before it was held back: the log's line is that step's.
export STONKS_BUDGET_EXPECTED=1
finish "LONG LIST DONE"
