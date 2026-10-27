#!/usr/bin/env bash
# Named watchlists through the real Service, App, StonksBody, ListMenu, and
# Watchlist with real Qt keys and pointer: making a list, adding to it,
# switching, removing by the list's rules, and the views that own the keys.
# And a stock removed in the real popup (Panel.qml) closing its lists in the
# window: the shell's layer-shell card window does not load offscreen, so
# the copy of Panel.qml puts the card in CardWindow.qml, as keys.sh does.
# HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree lists.qml
cp "$here/CardWindow.qml" "$root/plugin/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testBody: root.body'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 60
finish "LISTS DONE"
