#!/usr/bin/env bash
# The screenshot, through the real popup by keys and the real window by the
# pointer, with stand-ins for wl-copy and omarchy-notification-send (bin/)
# that record what they were given and reach no clipboard and no
# notification: each shot saves one picture of the chart on show, never the
# list, named for its symbol and the moment, in the folder Omarchy's
# screenshots use, puts it on the clipboard as a PNG, and sends Omarchy's
# notification with that file. Then the folder and the editor on Omarchy 4.0
# and 4.5, with Omasnap absent and present, under each version's settings.
# The shell's layer-shell card window does not load offscreen, so the copy
# of Panel.qml puts the card in CardWindow.qml, as sounds.sh does. HOME and
# curl are scratch; the scratch HOME names its Pictures folder in
# user-dirs.dirs, as a reader's may.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree camera.qml
cp "$here/CardWindow.qml" "$root/plugin/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testBody: root.body\n  readonly property alias testKeys: bodyKeys'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
scratch_home v1-data.json grvc.stonks.json
# Omasnap, Omarchy 4.5's screenshot tool, is off the run's PATH: a folder on
# it that holds a real one is linked in again, tool by tool, without it. A
# step on 4.5 puts omasnap/, a stand-in the camera only looks for, first on
# the camera's PATH. The copy of Camera.qml takes each step's environment,
# its settings and that PATH, from the harness.
patch_copy plugin/Camera.qml '/^  id: root$/a\  property var testEnvironment: ({})'
patch_copy plugin/Camera.qml '/^    id: naming$/a\    environment: root.testEnvironment'
mkdir "$work/omasnap"
printf '#!/bin/sh\nexit 1\n' > "$work/omasnap/omasnap"
chmod +x "$work/omasnap/omasnap"
export STONKS_OMASNAP="$work/omasnap"
path=""
n=0
IFS=: read -ra dirs <<< "$PATH"
for dir in "${dirs[@]}"; do
  if [ -x "$dir/omasnap" ]; then
    n=$((n + 1))
    mkdir "$work/path$n"
    for tool in "$dir"/*; do [ "${tool##*/}" = omasnap ] || ln -s "$tool" "$work/path$n/"; done
    dir="$work/path$n"
  fi
  path="${path:+$path:}$dir"
done
export PATH="$path"
printf 'XDG_DESKTOP_DIR="$HOME/Desktop"\nXDG_PICTURES_DIR="$HOME/Shots"\n' > "$HOME/.config/user-dirs.dirs"
# Omasnap reads its settings and the pictures folder from XDG_CONFIG_HOME,
# and Omarchy 4.0 from ~/.config: here they differ, so each step shows
# which it read. The steps set OMASNAP_SCREENSHOT_DIR themselves.
unset OMASNAP_SCREENSHOT_DIR
export XDG_CONFIG_HOME="$HOME/.xdg-config"
mkdir -p "$XDG_CONFIG_HOME" "$HOME/.config/omasnap"
printf 'XDG_PICTURES_DIR="$HOME/Photos"\n' > "$XDG_CONFIG_HOME/user-dirs.dirs"
printf '[output]\ndirectory = ~/Wrong\n' > "$HOME/.config/omasnap/omasnap.conf"
export QT_QPA_PLATFORM=offscreen
run_qs 90
finish "CAMERA DONE"
