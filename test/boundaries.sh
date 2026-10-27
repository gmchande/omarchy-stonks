#!/usr/bin/env bash
# Boundaries in the production source that no flow can see: who may run a
# command, read or write a file, start a feed, or name an endpoint; that the
# model stays pure; that colours come from the theme; that the bar entry
# holds only the pill's forms; and that no file takes QtQuick's Sprite name.
# And one in the tests: a harness ends Quickshell only through
# HarnessExit.qml.
# Prints a FAILED line per breach and exits non-zero on any.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
failed=0
fail() { echo "FAILED $*"; failed=1; }

# only PATTERN FILE...: PATTERN (PCRE, across lines) appears in production
# QML only in FILEs.
only() {
  local pattern=$1 files file
  shift
  files=$(rg -lUP -e "$pattern" -- *.qml)
  [ $? -le 1 ] || fail "rg could not check '$pattern'"
  for file in $files; do
    [[ " $* " == *" $file "* ]] || fail "$file: '$pattern' belongs only in $*"
  done
}
# none PATTERN FILE...: PATTERN (PCRE) appears in none of FILEs. An rg error,
# a missing file or a bad pattern, fails too: a check that did not run passes
# nothing.
none() {
  local pattern=$1 hits code hit
  shift
  hits=$(rg -nP -e "$pattern" -- "$@")
  code=$?
  [ "$code" -le 1 ] || fail "rg could not check '$pattern' in $*"
  [ "$code" -eq 0 ] || return 0
  while read -r hit; do fail "$hit: '$pattern' is not allowed here"; done <<< "$hits"
}

# External commands run only in the feeds, search, the version watch's
# shell restart and update, the sounds' pw-play, its chimes' sh, the
# bell's pw-dump, and the silence's pw-cat, the camera's screenshot
# hand-off, and the sh and chmod that keep Stonks' files its owner's and
# the sh that makes the data file so (OwnerOnly); files are read and
# written only by the service, the version watch reads the manifest, the
# trend colours read the theme's colours, the sounds read their own
# bundled sounds,
# the cache's files, the saved quotes and the sounds' replay, chimes, and
# lead-ins, are written only through OwnerOnly, and the camera writes its
# screenshot and reads Omasnap's settings; one service owns the feeds; the
# quote URL is the quote feed's, the fundamentals URLs the fundamentals
# feed's, the overnight URL the overnight feed's, the all-day URL the
# all-day feed's, and the manifest's URL the release feed's. The plugin has
# one IPC target; only the window's host acts on Hyprland.
only '\bProcess\s*\{' QuoteFeed.qml HistoryFeed.qml FundamentalsFeed.qml OvernightFeed.qml AllDayFeed.qml ReleaseFeed.qml SymbolSearch.qml Updates.qml Sounds.qml Camera.qml OwnerOnly.qml
only '\bFileView\s*\{' Service.qml Updates.qml TrendColors.qml OwnerOnly.qml Sounds.qml
only '\bSettings\s*\{|^import QtCore' Camera.qml
only '^import Quickshell\.Io' QuoteFeed.qml HistoryFeed.qml FundamentalsFeed.qml OvernightFeed.qml AllDayFeed.qml ReleaseFeed.qml SymbolSearch.qml Service.qml IpcTarget.qml Updates.qml TrendColors.qml Sounds.qml Camera.qml OwnerOnly.qml
# Only the camera grabs and saves a picture, puts it on the clipboard, and
# sends a notification.
only 'grabToImage|saveToFile|wl-copy|wl-paste|omarchy-notification-send|notify-send' Camera.qml
# A command started by exec is a sound's, and only there; it is pw-play
# under its time limit, and nothing else. A chime's pw-play has its own 2 s,
# so a stalled PipeWire piles none up. Only the sounds ask PipeWire
# anything, or hold its output awake.
only '\.exec\(|pw-play|pw-dump|pw-cat' Sounds.qml
none '\.exec\((?!\["timeout", "-k", "1", "4", "pw-play",)' Sounds.qml
none '(?<!timeout -k 1 2 )pw-play --' Sounds.qml
# Every command the camera and the file keeper run is under `timeout`.
none 'command:\s*\[(?!"timeout",)' Camera.qml OwnerOnly.qml
only '\bIpcHandler\s*\{' IpcTarget.qml
only '^import Quickshell\.Hyprland' WindowHost.qml
only '\b(QuoteFeed|HistoryFeed|FundamentalsFeed|OvernightFeed|AllDayFeed|ReleaseFeed)\s*\{' Service.qml
only 'Quote\.chartUrl\(' QuoteFeed.qml
only 'Fundamentals\.(fundamentalsUrl|capCloseUrl|rateUrl)\(' FundamentalsFeed.qml
only 'Overnight\.overnightUrl\(' OvernightFeed.qml
only 'Overnight\.allDayUrl\(' AllDayFeed.qml
only 'Release\.MANIFEST_URL\b' ReleaseFeed.qml
none 'execDetached|XMLHttpRequest|https?://' *.qml
# GitHub's address is the release rule's alone: no other file names it.
others=()
for file in *.js; do [ "$file" = Release.js ] || others+=("$file"); done
none 'github(usercontent)?\.com' *.qml "${others[@]}"
# Every request goes through Fetch.curlCommand, which compresses and caps
# it, and through a host's gate, which only the service holds.
while read -r hit; do
  [ -n "$hit" ] && fail "$hit: a command that is not Fetch.curlCommand's"
done <<< "$(rg -n '\.command\s*=' -- *.qml | rg -v 'Fetch\.curlCommand\(')"
for flag in --compressed --max-filesize; do
  rg -q -F -- "\"$flag\"" Fetch.js || fail "Fetch.js: curlCommand no longer sends $flag"
done
only '\bGate\s*\{' Service.qml
# The rule files (every *.js here) are data rules: no host, no I/O, no wall
# clock of their own, and no colour of their own: even Stonks' up and down
# for a theme without a pair are made from the theme's (`Tones.ownPair`).
none '\bQt\.|\bQuickshell\b|XMLHttpRequest|Date\.now\(|\bDate\s*\(\s*\)' *.js
none "([\"'])#[0-9a-fA-F]{3,8}\\1" *.js
# Colours come from the shell's Color singleton, so a component used without
# its colours still themes: no hex literal in either quote, no numeric
# Qt.rgba, and no literal but "transparent" as a colour's whole value.
none "([\"'])#[0-9a-fA-F]{3,8}\\1|Qt\\.(rgba|hsla|hsva)\\(\\s*[0-9.]|(?i)(\\b\\w*color|fillstyle|strokestyle|property\\s+color\\s+\\w+)\\s*[:=]\\s*([\"'])(?!transparent\\4)[^\"'\\n]+\\4\\s*;?\\s*$" *.qml
# The bar entry holds only the pill's forms: barStyle, and, absent until a
# middle-click there, barStyleRight for the right section and
# barStyleVertical for a side bar; the service's file holds the rest.
jq -e '.barWidget.defaults | keys == ["barStyle"]' manifest.json > /dev/null \
  || fail "manifest.json: the bar entry's defaults hold more than barStyle"
jq -e '[.barWidget.schema[].key] == ["barStyle", "barStyleRight", "barStyleVertical"]' manifest.json > /dev/null \
  || fail "manifest.json: the bar entry's schema holds more than barStyle, barStyleRight, and barStyleVertical"
# QtQuick owns Sprite: a Sprite.qml here would resolve as QtQuick's type.
[ -e Sprite.qml ] && fail "Sprite.qml: QtQuick owns the Sprite type"
# Qt.exit tears Quickshell's engine down at the next deferred delete, which
# QtTest's wait() runs under the test's handler: Qt aborts, and the abort
# dumps core. HarnessExit.qml exits only once no test is running, so no other
# QML or JS under test/ may quit, from a timer, Qt.callLater, or anywhere.
hits=$(rg -n -g '*.{qml,js}' -g '!HarnessExit.qml' -e '\bQt\.(exit|quit)\b' -- test)
code=$?
[ "$code" -le 1 ] || fail "rg could not check test/ for Qt.exit"
[ "$code" -ne 0 ] || while read -r hit; do
  fail "$hit: a harness quits only by setting exitCode on its HarnessExit and starting it"
done <<< "$hits"

exit "$failed"
