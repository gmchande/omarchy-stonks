#!/usr/bin/env bash
# Two copies of Stonks side by side, as the real Plugin, under the ids their
# manifests give: grvc.stonks, a user's install whose folder is a clone, and
# grvc.stonks-dev, named "Stonks dev", whose folder is a worktree. Each
# reads and writes its own lists file and cache, answers on its own IPC
# target, finds its own window by its title, and reaches its own service and
# panel; only the clone asks GitHub for a newer Stonks and offers it. HOME and
# curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree twin.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property alias testWindow: window'
# The cache step waits for each copy's quote runs to land.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
# The pills' panels stay unloaded: the offscreen platform has no
# PopupWindow to put one in.
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'
# The window hosts ask the harness's stand-in, not the owner's Hyprland.
patch_copy plugin/WindowHost.qml '/readonly property bool opened:/a\  property var hyprlandStandIn: null'
patch_copy plugin/WindowHost.qml 's/Hyprland\.\(toplevels\|focusedWorkspace\|dispatch\)/root.hyprlandStandIn.\1/g'
patch_copy plugin/WindowHost.qml 's/target: Hyprland$/target: root.hyprlandStandIn/'
scratch_home v1-data.json grvc.stonks.json
printf '{ "version": 1, "symbols": ["NVDA"], "featured": "NVDA", "order": "manual", "refreshIntervalSec": 60 }\n' \
  > "$HOME/.config/omarchy/grvc.stonks-dev.json"
plugins=$HOME/.config/omarchy/plugins
mkdir -p "$plugins/grvc.stonks/.git" "$plugins/grvc.stonks-dev"
echo "ref: refs/heads/main" > "$plugins/grvc.stonks/.git/HEAD"
echo "gitdir: /elsewhere/.git/worktrees/grvc.stonks-dev" > "$plugins/grvc.stonks-dev/.git"
# Main is a release ahead of this build.
echo 99.0.0 > "$STONKS_FAKE_STATE/MANIFEST.version"
export QT_QPA_PLATFORM=offscreen
run_qs 60
finish "TWIN DONE"
