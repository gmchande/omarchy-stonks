#!/usr/bin/env bash
# What looks clickable acts: a real pointer on the real window (App.qml)
# shows a row's chart, drags a row to a new place, scrolls, opens a row's
# menu and the list menu and takes their lines, steps the order, the unit
# and the range, switches the look and the sounds, takes a screenshot,
# opens the key sheet, replays the chart, runs an update on offer, adds a
# stock found and removes it, and scrubs the chart; and on the real pill
# (BarWidget.qml), a right-click changes its look. Each is judged by what
# the lists file, the surface and the stand-in commands then hold, never by
# where a thing is drawn. The shell's layer-shell card window, which the
# pill's panel uses, does not load offscreen, so the copy of Panel.qml puts
# the card in CardWindow.qml. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree mouse.qml
card_window
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 90
finish "MOUSE DONE"
