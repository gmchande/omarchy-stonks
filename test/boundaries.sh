#!/usr/bin/env bash
# Boundaries in the production source that no flow can see: who may run a
# command, read or write a file, or make a request, as the README's "What it
# runs" says; that the rule files stay pure; that colours come from the
# theme; that the bar entry holds only the pill's forms; and that no file
# takes QtQuick's Sprite name.
# And three in the tests: a harness ends Quickshell only through
# HarnessExit.qml, one that builds the whole plugin hands it a stand-in
# for Hyprland, and GitHub's checks name only files a clone holds.
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

# External commands run only in the feeds' one runner, the version watch's
# shell restart and update, the sounds' pw-play, its chimes' sh, the bell's
# omarchy-shell and pw-dump, the silence's pw-cat, the camera's screenshot
# hand-off, the text field's paste, the file reader's dd, and the sh and
# chmod that keep Stonks' files its owner's (OwnerOnly). Files are read and
# written only by the service and its lists file, the version watch (the
# manifest), the trend colours (the theme's colours), the sounds (their
# own), OwnerOnly (the cache), and the camera, which writes its screenshot
# and reads Omasnap's settings.
only '\bProcess\s*\{' FetchRun.qml Updates.qml Sounds.qml Camera.qml OwnerOnly.qml Field.qml FileRead.qml
only '\bFileView\s*\{' Service.qml ListsFile.qml Updates.qml TrendColors.qml OwnerOnly.qml Sounds.qml
only '\bSettings\s*\{|^import QtCore' Camera.qml
# Only the camera grabs and saves a picture, puts it on the clipboard, and
# sends a notification; only the text field reads the clipboard, by its
# bounded paste, and puts a selection in the primary selection; only the
# file reader reads a file by a command.
only 'grabToImage|saveToFile|wl-copy|omarchy-notification-send|notify-send' Camera.qml
only 'wl-paste|Commands\.(pastedText|primaryCopy)' Field.qml
# A command started by exec is a sound's, and only there; it is pw-play
# under its time limit, and nothing else. A chime's pw-play has its own 2 s,
# so a stalled PipeWire piles none up. Only the sounds ask PipeWire
# anything, or hold its output awake, by the commands written there or
# Commands.js's bell check and chime player.
only '\.exec\s*\(|pw-play|pw-dump|pw-cat|Commands\.(bellCheck|chimePlayer)\b' Sounds.qml
none '\.exec\s*\((?!\["timeout", "-k", "1", "4", "pw-play",)' Sounds.qml
none '(?<!timeout -k 1 2 )pw-play --' Sounds.qml Commands.js
# Every finite command runs under `timeout` with a kill after it: those the
# camera, the file keeper and the sounds write out, and those Commands.js
# and Fetch.js make. The chimes' one shell runs while sounds are on, each
# chime under its own; the update's are a terminal and a restart, started
# apart from the shell.
none 'command:\s*\[(?!"timeout", "-k", "1",)' Camera.qml OwnerOnly.qml Sounds.qml
for made in screenshotName createPrivately soundSurvey bellCheck pastedText primaryCopy readSaved; do
  rg -qUP "function $made\\([^)]*\\) \\{\\n  return \\[\"timeout\", \"-k\", \"1\", " Commands.js || fail "Commands.js: $made does not start with timeout -k 1"
done
rg -qUP 'function curlCommand\([^)]*\) \{\n  return \["timeout", "-k", "1", ' Fetch.js || fail "Fetch.js: curlCommand does not start with timeout -k 1"
# Hyprland's dispatcher can start a program too: only the plugin's entry
# reaches Hyprland, to hand it on, and the one dispatch is the window
# host's, which focuses the window.
only '^import Quickshell\.Hyprland' Plugin.qml
only '\.dispatch\s*\(' WindowHost.qml
none '\.dispatch\s*\((?!"hl\.dsp\.focus\()' WindowHost.qml
# A request leaves only from the feeds' runner, which only the feeds use,
# and no QML names an address or asks any other way.
only '\bFetchRun\s*\{' QuoteFeed.qml HistoryFeed.qml FundamentalsFeed.qml OvernightFeed.qml AllDayFeed.qml ReleaseFeed.qml SearchFeed.qml
none 'execDetached|XMLHttpRequest|https?://' *.qml
# GitHub's address is the release rule's alone: no other file names it.
others=()
for file in *.js; do [ "$file" = Release.js ] || others+=("$file"); done
none 'github(usercontent)?\.com' *.qml "${others[@]}"
# Stonks asks no site but those the README's "What it runs" names.
sites=$(awk '/^\*\*Sites\*\*/,/^\*\*Files/' README.md | rg -o '^- `([^`]+)`' -r '$1')
while read -r host; do
  [ -z "$host" ] || grep -qxF -- "$host" <<< "$sites" || fail "$host: a site the README's \"What it runs\" doesn't name"
done <<< "$(rg -o --no-filename 'https?://([^/"]+)' -r '$1' -- *.js | sort -u)"
# The programs Stonks runs, and the README's "Commands" names them all and
# no others. A program the code starts must be here: at a command's head,
# after its `timeout`, or at a command's place in a shell script it hands
# `sh -c`, `bash -c` or Omarchy's terminal. Each here must be in the code
# and the README, and each the README names must be here.
programs="curl timeout sh bash mkdir chmod mktemp ln rm dd head md5sum sed tail date pw-play pw-cat pw-dump
  omarchy-shell wl-copy wl-paste omarchy-notification-send omasnap tensaku-edit omarchy git"
programs=$(tr -s ' \n' '\n' <<< "$programs" | sed '/^$/d' | sort -u)
named=$(awk '/^\*\*Commands\*\*/,/^\*\*Sites\*\*/' README.md | rg -o '`[a-z][a-z0-9-]*' | tr -d '`' | sort -u)
# A script's words at a command's place: its string pieces joined, each
# script on its own line, then split where a command can start. The shell's
# own words are no programs.
scripted() {
  rg -U -o --no-filename -P '(?m)(?:"-c"|"presentation"),[\s\S]*?(?:,\s*"(?:ba)?sh"\s*,|"\s*\]\s*$)' -- *.qml *.js \
    | sed -E 's/^("-c"|"presentation"),/"\\n",/' \
    | rg -o -P '"(?:\\.|[^"\\])*"' | sed -E 's/^"//; s/"$//' | tr '\n' ' ' \
    | sed -E 's/\$\{[^}]*\}//g; s/\$\(\(([^)]*)\)\)//g; s/\\n/\n/g; s/\\"/"/g; s/\$\(/\n/g; s/(&&|\|\||[;|{(!`])/\n/g; s/\b(then|do|else|exec)\b/\n/g' \
    | sed -E 's/^[[:space:]]+//; s/^timeout( +-[a-z-]+( +[0-9]+)?)* +[0-9.]+ +//' \
    | rg -o -P '^[a-z][a-z0-9-]*(?![=a-z0-9-])' \
    | rg -vx 'case|cd|command|continue|done|echo|esac|exit|false|fi|for|if|printf|read|return|set|test|true|umask|while'
}
started=$( { rg -o --no-filename -P '(?:command:\s*|return\s+|\.exec\s*\()\["([a-z][a-z0-9-]*)"' -r '$1' -- *.qml *.js
  rg -o --no-filename -P '"timeout", (?:"-[a-z-]+", (?:"\d+", )?)?"[0-9.]+"\s*\)?,\s*"([a-z][a-z0-9-]*)"' -r '$1' -- *.qml *.js
  rg -o --no-filename -P '"timeout", "-k", "1", String\([^)]*\)\)?, "([a-z][a-z0-9-]*)"' -r '$1' -- *.qml *.js
  scripted; } | sort -u)
while read -r program; do
  [ -z "$program" ] || grep -qxF -- "$program" <<< "$programs" || fail "$program: a program the code starts that boundaries.sh's list doesn't name"
done <<< "$started"
while read -r program; do
  grep -qxF -- "$program" <<< "$named" || fail "$program: a program Stonks runs that the README's \"Commands\" doesn't name"
  rg -qw -- "$program" *.qml *.js || fail "$program: a program the README names that no code runs"
done <<< "$programs"
while read -r program; do
  [ -z "$program" ] || grep -qxF -- "$program" <<< "$programs" || fail "$program: a program the README's \"Commands\" names that Stonks doesn't run"
done <<< "$named"
# Every request goes through Fetch.curlCommand, which compresses and caps
# it.
while read -r hit; do
  [ -n "$hit" ] && fail "$hit: a command that is not Fetch.curlCommand's"
done <<< "$(rg -n '\.command\s*=' -- *.qml | rg -v 'Fetch\.curlCommand\(')"
for flag in --compressed --max-filesize; do
  rg -q -F -- "\"$flag\"" Fetch.js || fail "Fetch.js: curlCommand no longer sends $flag"
done
# The rule files (every *.js here) are data rules: no host, no I/O, no wall
# clock of their own, and no colour of their own: even Stonks' up and down
# for a theme without a pair are made from the theme's (`Tones.ownPair`).
none '\bQt\.|\bQuickshell\b|XMLHttpRequest|Date\.now\(|\bDate\s*\(\s*\)' *.js
none "([\"'])#[0-9a-fA-F]{3,8}\\1" *.js
# Colours come from the shell's Color singleton, so a component used without
# its colours still themes: no hex literal in either quote, no numeric
# Qt.rgba, and no literal but "transparent" as a colour's whole value.
none "([\"'])#[0-9a-fA-F]{3,8}\\1|Qt\\.(rgba|hsla|hsva)\\(\\s*[0-9.]|(?i)(\\b\\w*color|fillstyle|strokestyle|property\\s+color\\s+\\w+)\\s*[:=]\\s*([\"'])(?!transparent\\4)[^\"'\\n]+\\4\\s*;?\\s*$" *.qml
# Secondary text is mixed toward its ground (Tones.dim): Qt.darker gets
# louder on a light theme. A comment may name it. The shell's TextField
# draws its hint with Qt.darker, so a text box is a Field, which draws it in
# Tones.dim. Strings and comments, either kind, are skipped (\x22 and \x27
# are the two quotes).
code_only='\x22(?:\\.|[^\x22\\\n])*\x22(*SKIP)(*F)|\x27(?:\\.|[^\x27\\\n])*\x27(*SKIP)(*F)|/\*[\s\S]*?\*/(*SKIP)(*F)|//.*(*SKIP)(*F)'
hits=$(rg -U -n -o -P "$code_only|\\bQt\\.darker\\b|\\bTextField(?=\\s*\\{)" -- *.qml)
code=$?
[ "$code" -le 1 ] || fail "rg could not check for Qt.darker"
[ "$code" -ne 0 ] || while IFS=: read -r file line match; do
  case $match in
    Qt.darker) fail "$file:$line: Qt.darker gets louder on a light theme. Mix secondary text toward its ground with Tones.dim." ;;
    *) [ "$file" = Field.qml ] || fail "$file:$line: the shell's TextField draws its hint with Qt.darker, which gets louder on a light theme. Use Field, which mixes it toward its ground with Tones.dim." ;;
  esac
done <<< "$hits"
# The bar entry holds only the pill's forms: barStyle, and, absent until a
# middle-click there, barStyleRight for the right section and
# barStyleVertical for a side bar; the service's file holds the rest.
jq -e '.barWidget.defaults | keys == ["barStyle"]' manifest.json > /dev/null \
  || fail "manifest.json: the bar entry's defaults hold more than barStyle"
jq -e '[.barWidget.schema[].key] == ["barStyle", "barStyleRight", "barStyleVertical"]' manifest.json > /dev/null \
  || fail "manifest.json: the bar entry's schema holds more than barStyle, barStyleRight, and barStyleVertical"
# QtQuick owns Sprite: a Sprite.qml here would resolve as QtQuick's type.
[ -e Sprite.qml ] && fail "Sprite.qml: QtQuick owns the Sprite type"
# A harness that builds the whole plugin hands it a stand-in for Hyprland, so
# no walk asks the owner's desktop whether its screens are off.
hits=$(rg -n 'Stonks\.Plugin \{' -- test/qml | rg -v 'hyprland: ')
[ -z "$hits" ] || while read -r hit; do
  fail "$hit: a harness hands the plugin a stand-in for Hyprland (hyprland: ...)"
done <<< "$hits"
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
# GitHub's checks (.github/workflows/) name only files a clone holds, so a
# script deleted here fails this check before the push, not every run there.
# A file is named by its path, ending in a script's or a data file's
# extension.
hits=$(rg -noP '(?<![\w$/.*-])[\w.-]+(?:/[\w.-]+)*\.(?:sh|js|mjs|json|desktop|qml|py)\b' -- .github/workflows)
code=$?
[ "$code" -le 1 ] || fail "rg could not check .github/workflows for the files it names"
[ "$code" -ne 0 ] || while IFS=: read -r workflow line path; do
  git ls-files --error-unmatch -- ":(literal)$path" > /dev/null 2>&1 && [ -e "$path" ] \
    || fail "$workflow:$line: names $path, which a clone doesn't hold"
done <<< "$hits"

exit "$failed"
