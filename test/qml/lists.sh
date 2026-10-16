#!/usr/bin/env bash
# Named watchlists through the real Service, App, StonksBody, ListMenu, and
# Watchlist with real Qt keys: a version-1 file read as it is, making a list,
# adding to it, switching, removing by the list's rules, and a second
# Service reading back what the first wrote. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree lists.qml
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeyCatcher: keyCatcher\n  readonly property alias testWindow: window'
# The flows wait for the quote feed to go quiet: nothing in flight or queued.
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
# The flow hashes the pictures it grabs, so it grabs into this run's own
# folder, where no other run can replace them, and they are copied out after.
export STONKS_LISTS_OUT="$work/pictures"
out="${STONKS_VISUAL_DIR:-$plugin/out/render}"
mkdir -p "$STONKS_LISTS_OUT" "$out"
run_qs 60
find "$STONKS_LISTS_OUT" -name '*.png' -exec cp -t "$out" {} + \
  || { echo "FAIL the list flow's pictures did not reach $out"; code=1; }
finish "LISTS DONE"
