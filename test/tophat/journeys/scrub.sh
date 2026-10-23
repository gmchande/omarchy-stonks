#!/usr/bin/env bash
# Scrubbing the day and its chimes (scrub.md): by key and by pointer, what
# follows the scrub, the chimes Stonks asks for, and each way a scrub ends.
# Usage: lib.sh's header.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
journey_begin scrub "$@"

chimes() { step_sound_lines | grep -c 'chime-'; }
follows() { readout statusText smoothPrice changeText baselineLegend; }
scrubbed() { shown statusText --has "AT "; }
unscrubbed() { ! scrubbed; }
# holding: the stream of silence that keeps the output awake for the chimes
# (the stand-in pw-cat's silence.log) is running now.
holding() { [[ "$(tail -n 1 "$("$tophat" folder)/silence.log" 2> /dev/null | cut -d ' ' -f 1)" =~ ^(start|streaming)$ ]]; }
resting() { ! holding; }
# press KEY…: each key alone, as a hand presses them, since chimes struck
# closer than 45 ms apart keep only the latest (Sounds.qml). moved counts the
# keys that moved the scrub: a chart with few prints runs out of steps.
press() {
  local k was
  moved=0
  for k; do
    was=$(words statusText)
    key "$k"
    [ "$(words statusText)" != "$was" ] && moved=$((moved + 1))
  done
}
# chimed N: each of the N steps that moved asked for a chime; without the
# locator, which tells a step that moved, at least one did.
chimed() {
  if (( locator )); then
    check "the keys moved the scrub ($1 of $2 did)" [ "$1" -ge 1 ]
    check "each step that moved asked for a chime ($(chimes) for $1)" [ "$(chimes)" -ge "$1" ]
  else
    check "the steps asked for chimes" [ "$(chimes)" -ge 1 ]
  fi
}

step "Open the popup from the pill, on 1D"
open_popup
loaded
shot now
follows
sleep 0.5
check "the open popup, nothing scrubbed, holds no stream of silence" resting

step "h scrubs back one step at a time, a chime each"
press h h h h
sleep 0.3
shot h4
follows
sounds_here
chimed "$moved" 4
(( locator )) && check "the header says the moment scrubbed to (AT …)" scrubbed
soon "the key scrub holds a stream of silence for its chimes" 3 holding

step "l and the arrow keys step it too"
press l Left Right
sleep 0.3
shot keys
follows
sounds_here
chimed "$moved" 3

step "Esc ends the scrub and leaves the popup open"
key Escape
sleep 0.4
shot esc
follows
if (( locator )); then
  check "the header is back on now" unscrubbed
  check "the popup is still open" shown heroChart
fi
soon "the silence ends soon after Esc" 3 resting

step "The pointer sweeps the chart: the moment follows it, a chime as the line's height changes"
if reachable "hovering the chart"; then
  read -r cx cy cw < <(matches heroChart | jq -r '"\(.x) \(.y + .height / 2 | floor) \(.width)"')
  # The whole width in small steps: at night the 1D chart's line fills only
  # its left edge, and the rest scrubs to its last print.
  moments=()
  for f in $(seq 1 3 99); do
    move_to "$((cx + cw * f / 100))" "$cy"
    moments+=("$(words statusText)")
    [ "${#moments[@]}" = 4 ] && shot pointer-early
  done
  shot pointer-end
  follows
  distinct=$(printf '%s\n' "${moments[@]}" | grep '^AT ' | sort -u | grep -c .)
  say "  the header showed $distinct moments: $(printf '%s\n' "${moments[@]}" | grep '^AT ' | uniq | paste -sd '|')"
  sounds_here
  check "the header followed the pointer through more than one moment" [ "$distinct" -ge 2 ]
  check "the pointer's scrub asked for chimes" [ "$(chimes)" -ge 1 ]
  soon "the pointer's scrub holds a stream of silence" 3 holding
fi

step "The pointer leaving the chart ends the scrub"
if reachable "leaving the chart"; then
  read -r hx hy < <(at heroSymbol)
  move_to "$hx" "$hy"
  sleep 0.4
  shot left
  follows
  check "the header is back on now" unscrubbed
  check "the popup is still open" shown heroChart
  soon "the silence ends soon after the pointer leaves" 3 resting
fi

step "A click on the chart snaps back to now"
if reachable "clicking the chart"; then
  move_to "$((cx + cw * 40 / 100 - 2))" "$cy"
  move_to "$((cx + cw * 40 / 100))" "$cy"
  sleep 0.3
  check "the hover scrubbed first" scrubbed
  "$tophat" click "$((cx + cw * 40 / 100))" "$cy" > /dev/null || fail "click the chart"
  sleep 0.4
  shot clicked
  follows
  check "the click put the header back on now" unscrubbed
  check "the popup is still open" shown heroChart
fi
