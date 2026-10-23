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

step "Open the popup from the pill, on 1D"
open_popup
loaded
shot now
follows

step "h scrubs back one step at a time, a chime each"
# One key at a time, as a hand presses them: chimes struck closer than 45 ms
# apart keep only the latest (Sounds.qml).
for _ in 1 2 3 4; do key h; done
sleep 0.3
shot h4
follows
sounds_here
check "four h steps asked for four chimes" [ "$(chimes)" -ge 4 ]
(( locator )) && check "the header says the moment scrubbed to (AT …)" scrubbed

step "l and the arrow keys step it too"
key l; key Left; key Right
sleep 0.3
shot keys
follows
sounds_here
check "three more steps asked for three chimes" [ "$(chimes)" -ge 3 ]

step "Esc ends the scrub and leaves the popup open"
key Escape
sleep 0.4
shot esc
follows
if (( locator )); then
  check "the header is back on now" unscrubbed
  check "the popup is still open" shown heroChart
fi

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
fi

step "The pointer leaving the chart ends the scrub"
if reachable "leaving the chart"; then
  read -r hx hy < <(at heroSymbol)
  move_to "$hx" "$hy"
  sleep 0.4
  shot left
  follows
  check "the header is back on now" unscrubbed
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
fi
