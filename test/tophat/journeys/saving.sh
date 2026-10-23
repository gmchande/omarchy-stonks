#!/usr/bin/env bash
# Saving (saving.md): every change written at once, a save that can't land
# said in the footer and kept trying, by its click or the next change, and
# what was saved shown again after a close. The failure is the data file's
# folder made read-only in the session's own home. Usage: lib.sh's header.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
journey_begin saving "$@"

folder=$(dirname "$data")
journey_cleanup() { chmod u+w "$folder"; }
mode() { jq -r '.changeMode // "pct"' "$data"; }
is_mode() { [ "$(mode)" = "$1" ]; }
not_mode() { ! is_mode "$1"; }
footer() { readout footerText footerAction; }
unsaved() { shown footerText --has "saved"; }
saved_ok() { shown footerText --has "Add a symbol"; }

step "The first open writes that its hint was shown"
open_popup
loaded
soon "the first open saved hinted" 5 saved '.hinted == true'
shot first-open
readout footerHint
footer
keep_data first-open

step "c is written at once"
key c
soon "c was written at once" 3 is_mode abs
footer
keep_data abs

step "A save that can't land: the footer says so, and the file keeps the last good save"
chmod u-w "$folder"
key c
sleep 1
shot unsaved
footer
check "the file still holds the last good save (abs)" is_mode abs
(( locator )) && check "the footer says the changes aren't saved" unsaved
keep_data unsaved

step "The footer's click tries again once the folder can be written"
journey_cleanup
if reachable "the footer's try again"; then
  click_on footerText --has "saved"
  soon "the click saved since the open" 3 is_mode open
  sleep 0.5
  shot retried
  footer
  check "the footer is back to + Add a symbol" saved_ok
  keep_data retried
else
  key c
  soon "the next change saved" 3 not_mode abs
fi

step "Fails again; the next change, once it can land, saves everything"
chmod u-w "$folder"
key c
sleep 1
want_before=$(mode)
(( locator )) && check "the footer says the changes aren't saved" unsaved
journey_cleanup
key c
sleep 1
shot next-change
footer
check "the next change was written (the file moved on from $want_before)" not_mode "$want_before"
(( locator )) && check "the footer is back to + Add a symbol" saved_ok
keep_data next-change

step "Closed and opened again, the popup shows what was saved"
kept=$(mode)
key Escape
sleep 0.5
open_popup
loaded
shot reopened
readout changeText changeCaption
# On 1D the change beside the price shows the saved unit: a percent, an
# amount, or a percent with SINCE OPEN under it.
shows() {
  case $1 in
    pct) shown changeText --has % && ! shown changeCaption --has "SINCE OPEN" ;;
    abs) shown changeText && ! shown changeText --has % ;;
    open) shown changeCaption --has "SINCE OPEN" ;;
  esac
}
if (( locator )); then check "the reopened popup shows the saved unit ($kept)" shows "$kept"; fi
