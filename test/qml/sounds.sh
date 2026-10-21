#!/usr/bin/env bash
# What Stonks plays, through the real popup by keys and the real window by
# the pointer, with a stand-in pw-play (bin/pw-play) that plays nothing and
# records what it was asked to play: on by default, each sound in each
# look's voice, a replay's sound that is its chart's line and stops with it,
# one sound at a time, nothing while off, and nothing for what happens on
# its own or for looking around. The shell's layer-shell card window does
# not load offscreen, so the copy of Panel.qml puts the card in
# CardWindow.qml, as keys.sh does. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree sounds.qml
cp "$here/CardWindow.qml" "$root/plugin/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testBody: root.body'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
scratch_home v1-data.json grvc.stonks.json
: > "$STONKS_FAKE_STATE/pw-play.log"
: > "$STONKS_FAKE_STATE/pw-cat.log"
: > "$STONKS_FAKE_STATE/pw-dump.log"
export QT_QPA_PLATFORM=offscreen
run_qs 120
finish "SOUNDS DONE"
