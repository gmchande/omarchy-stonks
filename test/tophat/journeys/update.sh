#!/usr/bin/env bash
# The update (update.md): a user of an older release (OLD, the last tag by
# default) learns of REF's release from the footer, clicks, updates in the
# terminal Omarchy opens, restarts the shell from the footer, and finds the
# release running with their data file as it was. Usage: update.sh
# [--update-from OLD] REF; the rest as lib.sh's header.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
args=("$@")
[[ " ${args[*]} " == *" --update-from "* ]] || args=(--update-from "$(git -C "$checkout" describe --tags --abbrev=0 --match 'v*' "${!#}")" "${args[@]}")
journey_begin update "${args[@]}"

plugin=$run/home/.config/omarchy/plugins/grvc.stonks
release=$(cat "$run/release.version")
say "installed: $(jq -r .version "$plugin/manifest.json"); GitHub's main: Stonks $release"

# card_box BEFORE AFTER: the popup's card, "W H X Y", from what changed
# below the bar between two shots.
card_box() {
  magick "$1" "$2" -compose difference -composite -crop "${WIDTH}x$((HEIGHT - 30))+0+30" +repage \
    -colorspace gray -threshold 0 -trim -format '%w %h %X %Y' info: 2> /dev/null | awk '{ print $1, $2, $3, $4 + 30 }'
}
# footer_at SHOT BOX: the middle of the card's last line of words, "X Y":
# the lowest band of rows, over the card's middle 300 pixels, with letters'
# edges in it. The card's ground can let the wallpaper through, so edges,
# not a colour, tell words from ground. An older release has no locator,
# so its footer is found by sight.
footer_at() {
  local w h x y top
  read -r w h x y <<< "$2"
  top=$((y + h - 90))
  magick "$1" -crop "300x80+$((x + w / 2 - 150))+$top" +repage -colorspace gray \
    -morphology EdgeIn Diamond:1 -threshold 12% -scale '1x80!' -depth 8 txt:- 2> /dev/null \
    | awk -F'[,:() ]+' -v top="$top" -v cx="$((x + w / 2))" '
      NR > 1 && $2 != "" { lit[$2] = ($3 > 16) }
      END {
        for (r = 79; r >= 0 && !lit[r]; r--) ;
        if (r < 0) exit 1
        last = r
        for (; r >= 0 && lit[r]; r--) ;
        print cx, top + int((r + 1 + last) / 2)
      }'
}
# open_and_find NAME: the popup opened from the pill, shot as NAME, and its
# footer found (footer). An older release has no locator, so the pill is
# clicked where it is centred on the bar.
open_and_find() {
  local before=$shots/before.png after box sum
  # The pointer on the pill in both shots, so only the card differs.
  move_to "$((WIDTH / 2))" 12
  sleep 0.3
  "$tophat" shot "$before" > /dev/null || { fail "shot before opening"; return 1; }
  sum=$(columns_sum)
  "$tophat" click "$((WIDTH / 2))" 12 > /dev/null || { fail "click the pill"; return 1; }
  soon "the pill's click opened the popup" 5 columns_changed "$sum" || return 1
  sleep 0.6
  after=$(printf '%s/%02d-%s.png' "$out" "$step_no" "$1")
  "$tophat" shot "$after" > /dev/null || { fail "shot $1"; return 1; }
  box=$(card_box "$before" "$after")
  footer=$(footer_at "$after" "$box") || { fail "found the footer's words in the popup ($box)"; return 1; }
  say "  card: $box; footer at $footer; shot $(basename "$after")"
}

# The update's terminal: foot, and what its shell runs in a session of the
# terminal's own; each found by the run's mark.
ours_named() {
  local pid
  for pid in $(pgrep -x "$1"); do
    grep -qzx "TOPHAT_RUN=$RUN_ID" "/proc/$pid/environ" 2> /dev/null && return 0
  done
  return 1
}
in_terminal() { ours_named "$1"; }
pager_or_prompt() { in_terminal less || in_terminal gum; }
terminal_gone() { ! ours_named foot; }
at_main() { [ "$(git -C "$plugin" rev-parse HEAD)" = "$(git -C "$run/github" rev-parse main)" ]; }
names_release() { [ "$(jq -r .version "$plugin/manifest.json")" = "$release" ]; }
shell_pid() { pgrep -g "$LEADER" -x quickshell | head -n 1; }
restarted() { local now; now=$(shell_pid); [ -n "$now" ] && [ "$now" != "$old_shell" ] && "$tophat" shell grvc.stonks.tophat where heroChart > /dev/null 2>&1; }
# Every value the installed data file held, the restarted release holds,
# empty lists and objects included: each of its keys holds what it did.
kept_all() {
  jq -e -n --slurpfile was "$run/data.before.json" --slurpfile now "$data" \
    '$was[0] as $a | $now[0] as $b | $a | to_entries | all(.value == $b[.key])' > /dev/null
}
# What the installed data file says, by jq PATH.
was() { jq -r "$1" "$run/data.before.json"; }
# says NAME TEXT: the shown item NAME's words hold TEXT, in any case.
says() { words "$1" | grep -qiF -- "$2"; }
# The look the file saved: retro draws the price in blocks (blockPrice).
look_kept() { if [ "$(was .style)" = retro ]; then shown blockPrice; else ! shown blockPrice; fi; }
# Every list the file saved is in the list menu, All first.
lists_kept() {
  local name
  says listChoice All || return 1
  while IFS= read -r name; do says listChoice "$name" || return 1; done < <(was '.lists[].name')
}

step "The older release asks GitHub, and main names Stonks $release"
need "the release's manifest was asked for and answered" within 60 test -s "$run/release/asked"
sleep 1

step "Open the popup: the footer says a newer Stonks is out"
need "the popup opened and its footer was found" open_and_find note
# The pointer on it holds the note past its few seconds.
read -r fx fy <<< "$footer"
move_to "$fx" "$fy"
shot note-held

step "Click the note: the update opens in a terminal"
"$tophat" click "$fx" "$fy" > /dev/null || fail "click the note at $footer"
need "the click opened the update's terminal in the session" within 10 test -s "$run/joined"
need "the terminal shows the update's diff or its question" within 30 pager_or_prompt
shot terminal
# Focus to the terminal, which fills the output; the popup closes.
"$tophat" click 60 "$((HEIGHT / 2))" > /dev/null
sleep 0.5
if in_terminal less; then key q; fi
need "Omarchy asks before it updates" within 30 in_terminal gum
shot question
key y
need "the plugin's clone moved to GitHub's main" within 60 at_main
check "the installed manifest names Stonks $release" names_release
sleep 1
shot updated
key Return
soon "the terminal closed with a key" 10 terminal_gone

step "Open the popup again: the footer offers the shell's restart"
park
need "the popup opened and its footer was found" open_and_find restart
old_shell=$(shell_pid)
read -r fx fy <<< "$footer"
"$tophat" click "$fx" "$fy" > /dev/null || fail "click the restart notice at $footer"
need "a new shell came up, running a build with the locator" within 90 restarted
locator=1

step "The release runs what the data file saved, and keeps the file"
open_popup
loaded
shot restarted
readout heroSymbol listLabel changeCaption
check "the chart shows the stock the file saved, $(was .featured)" says heroSymbol "$(was .featured)"
check "the list on show is the one the file saved, $(was .list)" says listLabel "$(was .list)"
check "the range is the one the file saved, $(was .range)" says changeCaption "$(was .range)"
check "the look is the one the file saved, $(was .style)" look_kept
key l
sleep 0.4
readout listChoice
check "the list menu holds every list the file saved" lists_kept
key Escape
key question
sleep 0.4
readout helpCredit
check "the key sheet names Stonks $release" shown helpCredit --has "Stonks $release"
key Escape
check "every value the installed data file held is kept, empty lists included" kept_all
keep_data after
check "nothing on the restarted footer offers an update" eval '! shown footerUndo'
