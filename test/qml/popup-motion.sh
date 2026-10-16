#!/usr/bin/env bash
# The popup's card edge in motion through the real Panel and Service with
# real Qt keys, judged on rendered frames: a list switch either way, the key
# sheet closing, a removal and its undo, an add that lands, a membership
# change from elsewhere, the list menu, and search opening and closing each
# ease the edge in 160 ms, the footer riding it whole where it shows; an
# open from closed holds its fitted height.
# The shell's layer-shell card window does not load offscreen, so the copy
# of Panel.qml puts the card in CardWindow.qml, a plain window. HOME and
# curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree popup-motion.qml
cp "$here/CardWindow.qml" "$root/plugin/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testCard: panel'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
scratch_home v1-data.json grvc.stonks.json
frame_tools
export QT_QPA_PLATFORM=offscreen
run_qs 60
finish "POPUP MOTION DONE"
