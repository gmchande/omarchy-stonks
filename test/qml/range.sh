#!/usr/bin/env bash
# The one shared chart range through the real Service, App, and BarWidget: a
# range picked in the window, the pill showing the day on every range in
# every style, the window's hold while a range's history is out or failed,
# expired history arriving while it refetches, r (its "Refreshing" while out,
# and its day-old cap and P/E),
# the window opened and closed by the pill's right-click and by IPC, against
# the popup and another workspace, real IPC refreshing once for two pills
# and reaching the plugin with no pill at all, a range left behind never
# retrying, no history fetched with no surface open, the pill's first-fetch
# states, the pill's animal turning with its day and switching on a wheel
# step, and later Services reading back the saved range, with a window
# summoned before each was ready, and the hero holding what it showed while
# a range or symbol loads. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree range.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher'
# The flows wait for the feeds to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed\n  readonly property alias testHistoryFeed: historyFeed\n  readonly property alias testFundamentalsFeed: fundamentalsFeed'
# The history copy says when it is in its retry pause.
patch_copy plugin/HistoryFeed.qml '/readonly property bool busy:/a\  readonly property alias testRetrying: retryTimer.running'
# The pills' popups stay unloaded: the offscreen platform has no popup
# window to put one in, and no flow here opens one.
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
# The harness never asks the owner's Hyprland: the window host's lookup,
# workspace check, and focus call run against the harness's stand-in.
patch_copy plugin/WindowHost.qml '/readonly property bool opened:/a\  property var hyprlandStandIn: null'
patch_copy plugin/WindowHost.qml 's/Hyprland\.\(toplevels\|focusedWorkspace\|dispatch\)/root.hyprlandStandIn.\1/g'
scratch_home v1-data.json grvc.stonks.json
# The theme where the shell reads it, Tokyo Night's, a copy the flow
# replaces to switch themes the way omarchy-theme-set does.
mkdir -p "$HOME/.local/state/omarchy/current/theme"
cp /usr/share/omarchy/themes/tokyo-night/colors.toml "$HOME/.local/state/omarchy/current/theme/"
export QT_QPA_PLATFORM=offscreen
run_qs 165
finish "RANGE DONE"
