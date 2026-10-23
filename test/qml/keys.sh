#!/usr/bin/env bash
# Every key the key sheet draws and the README's table lists, pressed with
# real Qt keys in the real popup (Panel.qml) and the real window (App.qml):
# each changes what the surface shows. And the sheet itself: the same on both
# surfaces and in both looks, and its foot crediting the
# manifest's version, Yahoo, and Robinhood. The shell's layer-shell card
# window does not load offscreen, so the copy of Panel.qml puts the card in
# CardWindow.qml, as popup-motion.sh does. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree keys.qml
cp "$here/CardWindow.qml" "$root/plugin/"
cp "$plugin/README.md" "$root/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher'
# r reaches the service's refresh, counted: a refresh of quotes this fresh
# asks for nothing.
patch_copy plugin/Service.qml 's/^  function refresh() {$/  property int testRefreshes: 0\n&\n    testRefreshes++/'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 90
finish "KEYS DONE"
