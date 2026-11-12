#!/usr/bin/env bash
# What a long list costs, counted, through the real Plugin, Service, App
# and a pill on a clock the walk sets: 154 symbols answer in one run of
# nine requests, refresh whole every minute in a few requests, build only
# the rows near sight, and work out and redraw a row's day only in sight.
# HOME and curl are scratch; the fake curl answers from test/fixtures.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree cost.qml
# The pill's panel has its card in CardWindow.qml, as in keys.sh.
card_window
export QT_QPA_PLATFORM=offscreen
jq -n '{ version: 1, symbols: (["TALL001", "STRAY", "SHOP.TO", "BTC-USD"] + [range(5; 155) | "LONG" + ("00" + tostring)[-3:]]),
  lists: [{ name: "Ten", symbols: [range(5; 15) | "LONG" + ("00" + tostring)[-3:]], order: "manual" }],
  featured: "TALL001", order: "manual", changeMode: "pct", style: "smooth", refreshIntervalSec: 60 }' > "$HOME/.config/omarchy/grvc.stonks.json"
run_qs 300
finish "COST DONE"
