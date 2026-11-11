#!/usr/bin/env bash
# Every key the README's table lists, pressed with real Qt keys in the real
# panel (Panel.qml) and the real window (App.qml), changes what it should;
# the Esc order, Omarchy's panel keys there, a key after Tab in the
# window, and the sheet's credit to the manifest's version. The shell's
# layer-shell card window does not load offscreen, so the copy of Panel.qml
# puts the card in CardWindow.qml. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree keys.qml
cp "$plugin/README.md" "$root/"
card_window
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 90
finish "KEYS DONE"
