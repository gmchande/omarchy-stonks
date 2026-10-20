#!/usr/bin/env bash
# The look for a newer Stonks through the real Plugin, Service, Updates, App,
# and a pill, on a clock the harness sets. HOME and curl are scratch: the
# fake curl answers Yahoo from the saved days, and main's manifest on GitHub
# with the version in MANIFEST.version. This build is 1.0.9.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree updates.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body'
# The harness owns the clock.
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.now }/'
# A step waits for the look's answer to land.
patch_copy plugin/Service.qml '/readonly property alias mainVersion:/a\  readonly property alias testReleaseFeed: releaseFeed'
patch_copy plugin/ReleaseFeed.qml '/property int askedAt: 0/a\  readonly property alias testAsking: fetchProc.running'
# The pill's popup stays unloaded, and the window host asks stand-ins, not
# the owner's Hyprland, for the window and the screens (as fetch.sh).
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
patch_copy plugin/WindowHost.qml '/readonly property bool opened:/a\  property var hyprlandStandIn: null'
patch_copy plugin/WindowHost.qml 's/Hyprland\.\(toplevels\|focusedWorkspace\|dispatch\)/root.hyprlandStandIn.\1/g'
patch_copy plugin/WindowHost.qml 's/target: Hyprland$/target: root.hyprlandStandIn/'
patch_copy plugin/WindowHost.qml 's/Hyprland\.refreshMonitors()/root.monitors.forEach(function(m) { m.refresh() })/g'
jq '.version = "1.0.9"' "$root/plugin/manifest.json" > "$work/manifest.json"
mv "$work/manifest.json" "$root/plugin/manifest.json"
# Main names this build's version as the service starts.
echo 1.0.9 > "$STONKS_FAKE_STATE/MANIFEST.version"
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 60
finish "UPDATES DONE"
