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
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testWatchlist: root.body ? root.body.watchlist : null\n  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property real testContentHeight: panel.contentHeight\n  readonly property real testInset: panel.verticalContentInset\n  readonly property alias testCard: panel\n  readonly property alias testHeldAnchor: heldAnchor'
patch_copy plugin/BarWidget.qml '/readonly property var panel: panelLoader.item/a\  readonly property alias testButton: button'
# The card is placed from its pill's bar window, which an unmapped pill has
# none of: a copy of the shell's Ui takes the bar window and the pill's spot
# on it from the flow, and keeps the rest of the shell's placement; so does
# the held anchor take the pill's bar window. pointer.sh finds that window
# through a pill in a window that maps offscreen.
rm "$root/Ui"
cp -r /usr/share/omarchy/shell/Ui "$root/Ui"
patch_copy Ui/KeyboardPanel.qml 's/readonly property var anchorWindow: /property var anchorWindow: /; s/readonly property point anchorScreenPos: {/property point anchorScreenPos: {/'
patch_copy plugin/HeldAnchor.qml 's/readonly property var barWindow: /property var barWindow: /'
export STONKS_WATCHLIST_FIXTURE="$STONKS_FIXTURES/list-22.json"
run_qs 45
finish "POPUP DONE"
