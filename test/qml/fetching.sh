#!/usr/bin/env bash
# Fetching's promises, through the real Plugin, Service, App and two pills
# on a clock the walk sets: with nothing open only the pill's stock is
# asked, and with the window open each listing as often as its market
# moves; r twice asks once; a Yahoo that refuses is left alone until its
# time and one that doesn't answer is tried again within two minutes, r at
# once; a window no screen shows asks what a closed one asks, and a night's
# trades come every five minutes; with every screen off nothing is asked,
# and the key that wakes one asks at once. HOME and curl are scratch; the
# fake curl answers from test/fixtures/moments/fetch-2026-10-07.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree fetching.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testWindow: window'
# The harness owns the clock, from Wednesday 7 October at 05:59 New York.
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.now }/'
patch_copy plugin/Service.qml 's/property int now: Math.floor(Date.now() \/ 1000)/property int now: 1791367140/'
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testPreviewFeed: previewFeed\n  readonly property alias testYahooGate: yahooGate\n  readonly property alias testOvernightFeed: overnightFeed'
patch_copy plugin/QuoteFeed.qml 's/interval: 2500/interval: 200/'
# The pills' panels stay unloaded, and the window host asks a stand-in, not
# the owner's Hyprland (as range.sh), and hears its events from the stand-in
# too: the owner's own, a window title or a keyboard layout changing, would
# ask the screens again while they are off, at a moment the harness doesn't
# choose.
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
patch_copy plugin/WindowHost.qml '/readonly property bool opened:/a\  property var hyprlandStandIn: null'
patch_copy plugin/WindowHost.qml 's/Hyprland\.\(toplevels\|focusedWorkspace\|dispatch\)/root.hyprlandStandIn.\1/g'
patch_copy plugin/WindowHost.qml 's/target: Hyprland$/target: root.hyprlandStandIn/'
patch_copy plugin/Screens.qml '/property bool watching:/a\  property var hyprlandStandIn: null'
patch_copy plugin/Screens.qml 's/target: Hyprland$/target: root.hyprlandStandIn/'
# Whether every screen is off is asked of the screens the harness hands the
# host, stand-ins that answer as they are set.
patch_copy plugin/Screens.qml 's/Hyprland\.refreshMonitors()/root.monitors.forEach(function(m) { m.refresh() })/g'
# The input that wakes the screens comes from the harness too, never the
# owner's own keys and pointer.
patch_copy plugin/Screens.qml 's/^  IdleMonitor {$/  QtObject {\n    property bool enabled\n    property int timeout\n    property bool respectInhibitors\n    property bool isIdle: false/'
patch_copy plugin/Screens.qml '/property bool watching:/a\  readonly property alias testInput: input'
export QT_QPA_PLATFORM=offscreen
scratch_home fetch-watchlist.json grvc.stonks.json
echo fetch-2026-10-07 listings-2026-10-07-1455 > "$STONKS_FAKE_STATE/overnight.set"
run_qs 300
finish "FETCHING DONE"
