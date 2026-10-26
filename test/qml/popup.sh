#!/usr/bin/env bash
# The real Panel against the installed third-party bar API, without fetching
# quotes, and a real pill whose loader loads that same Panel, pressed with
# real Qt keys. The shell's layer-shell card window does not load offscreen,
# so the copy of Panel.qml puts the card in CardWindow.qml, a plain window,
# as keys.sh does: nothing maps on the desktop.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree popup.qml
cp "$here/CardWindow.qml" "$root/plugin/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testWatchlist: root.body ? root.body.watchlist : null\n  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testBodyKeys: bodyKeys'
patch_copy plugin/BarWidget.qml '/readonly property var panel: panelLoader.item/a\  readonly property alias testButton: button'
export STONKS_WATCHLIST_FIXTURE="$STONKS_FIXTURES/list-22.json"
export QT_QPA_PLATFORM=offscreen
run_qs 45
finish "POPUP DONE"
