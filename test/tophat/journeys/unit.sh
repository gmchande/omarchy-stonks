#!/usr/bin/env bash
# The unit sign (unit.md): %, ±, and since the open, by c, by the sign at the
# end of the list's header, and by the change beside the price on 1D, which a
# longer range leaves alone. Usage: lib.sh's header.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
journey_begin unit "$@"

mode() { jq -r '.changeMode // "pct"' "$data"; }
is_mode() { [ "$(mode)" = "$1" ]; }
figures() { readout changeText changeCaption rowContent; }
not_mode() { ! is_mode "$1"; }

step "Open the popup from the pill, on 1D, in percent"
open_popup
loaded
shot pct
figures
check "the rows start in percent" is_mode pct

step "c steps to amounts (±)"
key c
soon "c chose amounts, and it was saved" 3 is_mode abs
shot abs
figures
keep_data abs

step "A click on the sign steps to since the open"
if reachable "the unit sign"; then
  click_on unitTarget
  soon "the sign chose since the open, and it was saved" 3 is_mode open
  shot open
  figures
  check "the caption says SINCE OPEN" shown changeCaption --has "SINCE OPEN"
fi

step "A click on the change beside the price steps on, on 1D"
if reachable "the change beside the price"; then
  click_on changeText
  soon "the change's click chose percent, and it was saved" 3 is_mode pct
  shot back-to-pct
  figures
fi

step "On 1W the change beside the price stays a percent and its click does nothing"
key bracketright
loaded
before=$(mode)
if reachable "the change beside the price on 1W"; then
  click_on changeText
  sleep 0.3
  check "the click left the rows' unit alone ($before)" is_mode "$before"
  click_on unitTarget
  soon "the sign still steps on 1W" 3 not_mode "$before"
fi
shot range
figures
keep_data range
