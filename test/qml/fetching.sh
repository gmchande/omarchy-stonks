#!/usr/bin/env bash
# Fetching's promises, through the real Plugin, Service, App and two pills
# on a clock the walk sets: with nothing open only the pill's stock is
# asked, and with the window open each listing as often as its market
# moves; r twice asks once; a Yahoo that refuses is left alone until its
# time and one that doesn't answer is tried again within two minutes, r at
# once; a window no screen shows asks what a closed one asks, and a night's
# trades come every five minutes, and a pointer on the pill reads tonight's
# price as it changes; with every screen off nothing is asked, and the key
# that wakes one asks at once; a panel open on a screen that's off asks what
# a closed one asks, and the key that wakes that screen asks its rows at
# once. HOME and curl are scratch; the fake curl answers from
# test/fixtures/moments/fetch-2026-10-07.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree fetching.qml
# The pills' panels have their cards in CardWindow.qml, as in keys.sh.
card_window
export QT_QPA_PLATFORM=offscreen
scratch_home fetch-watchlist.json grvc.stonks.json
echo fetch-2026-10-07 listings-2026-10-07-1455 > "$STONKS_FAKE_STATE/overnight.set"
run_qs 300
finish "FETCHING DONE"
