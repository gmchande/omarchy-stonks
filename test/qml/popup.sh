#!/usr/bin/env bash
# The real Panel against the installed third-party bar API, without mapping
# an overlay or fetching quotes, and a real pill whose loader loads that same
# Panel. Needs the running Wayland session.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree popup.qml
# Only the disposable copy suppresses the popup; lifecycle state remains real.
# If Panel.qml's line is reworded the patch misses and the popup would map on
# the desktop, so patch_copy stops before Quickshell starts.
patch_copy plugin/Panel.qml 's/open: root.opened/open: false/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testWatchlist: root.body ? root.body.watchlist : null\n  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher'
patch_copy plugin/BarWidget.qml '/readonly property var panel: panelLoader.item/a\  readonly property alias testButton: button'
export STONKS_WATCHLIST_FIXTURE="$STONKS_FIXTURES/list-22.json"
run_qs 45
finish "POPUP DONE"
