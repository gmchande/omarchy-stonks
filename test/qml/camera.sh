#!/usr/bin/env bash
# The screenshot, through the real popup by keys and the real window by the
# pointer, with stand-ins for wl-copy and omarchy-notification-send
# (bin/) that record what they were given and reach no clipboard and no
# notification: each shot saves one picture, named for its symbol and the
# moment, in the folder Omarchy's screenshots use, puts that picture on the
# clipboard as a PNG, and sends Omarchy's notification with that file; the
# picture is of the chart on show, never the list. The shell's layer-shell
# card window does not load offscreen, so the copy of Panel.qml puts the
# card in CardWindow.qml, as sounds.sh does. HOME and curl are scratch; the
# scratch HOME names its Pictures folder in user-dirs.dirs, as a reader's
# may.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree camera.qml
cp "$here/CardWindow.qml" "$root/plugin/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testBody: root.body'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
scratch_home v1-data.json grvc.stonks.json
# The reader's own settings never reach the run.
unset OMARCHY_SCREENSHOT_DIR OMARCHY_SCREENSHOT_EDITOR
printf 'XDG_DESKTOP_DIR="$HOME/Desktop"\nXDG_PICTURES_DIR="$HOME/Shots"\n' > "$HOME/.config/user-dirs.dirs"
export QT_QPA_PLATFORM=offscreen
run_qs 90
finish "CAMERA DONE"
