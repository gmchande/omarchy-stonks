#!/usr/bin/env bash
# What Stonks plays, through the real popup by keys and the real window by
# the pointer, with a stand-in pw-play (bin/pw-play) that plays nothing and
# logs what it was asked to play. The shutter's shots land in the scratch
# HOME through bin/'s stand-ins for wl-copy and omarchy-notification-send,
# as camera.sh's do. The shell's layer-shell card window does not load
# offscreen, so the copy of Panel.qml puts the card in CardWindow.qml, as
# keys.sh does. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree sounds.qml
cp "$here/CardWindow.qml" "$root/plugin/"
patch_copy plugin/Panel.qml 's/^  KeyboardPanel {$/  CardWindow {/'
patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property var testBody: root.body'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
# A quote's retry pauses 200 ms, not 2.5 s, as fetch.sh's does.
patch_copy plugin/QuoteFeed.qml 's/interval: 2500/interval: 200/'
# The copy counts the output asleep 1.5 s after its last sound or its
# silence's end, not 4 s, so each quiet spell is shorter, and writes a look's
# files ahead 5 ms apart, not 100, so a start writes all 71 in a moment.
patch_copy plugin/Sounds.qml 's/asleepAfter = Math.max(asleepAfter, now + 4000)/asleepAfter = Math.max(asleepAfter, now + 1500)/'
patch_copy plugin/Sounds.qml '/root.asleepAfter = Date.now()/s/ : 4000)/ : 1500)/'
patch_copy plugin/Sounds.qml '/id: ahead$/{n;s/interval: 100$/interval: 5/}'
scratch_home v1-data.json grvc.stonks.json
: > "$STONKS_FAKE_STATE/pw-play.log"
: > "$STONKS_FAKE_STATE/pw-cat.log"
: > "$STONKS_FAKE_STATE/pw-dump.log"
export QT_QPA_PLATFORM=offscreen
run_qs 120
finish "SOUNDS DONE"
