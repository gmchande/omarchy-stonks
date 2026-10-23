#!/usr/bin/env bash
# Ranges and the lines under the chart (ranges.md): every range by key, the
# lines and marks on each, a click and a wheel notch on the range row, and
# the range kept across a close. Usage: lib.sh's header.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
journey_begin ranges "$@"

saved_range() { jq -r '.range // "1D"' "$data"; }
# lines: what the range shows under and on the chart, as evidence.
lines() { readout changeCaption periodLine yearLine highMark lowMark; }

step "Open the popup from the pill, on 1D"
open_popup
loaded
shot 1D
lines
check "the range starts on 1D" [ "$(saved_range)" = 1D ]

# Each ] steps to the next range, until ] changes nothing. That must be on
# All, the last range on every commit, having visited every range the row
# offers.
offered=$(words rangeOption | grep -c .)
visited=1
last=$(saved_range)
for _ in $(seq 1 20); do
  key bracketright
  now=$(saved_range)
  if [ "$now" = "$last" ]; then
    step "] on the last range, $last"
    check "] stops only on All" [ "$last" = All ]
    if (( locator )); then
      check "] visited every range the row offers ($visited of $offered)" [ "$visited" = "$offered" ]
    fi
    break
  fi
  visited=$((visited + 1))
  step "] to $now"
  pass "] moved the range from $last to $now, and it was saved"
  loaded
  shot "$now"
  lines
  last=$now
done

step "[ steps back one range"
key bracketleft
back=$(saved_range)
check "[ moved the range back from $last, and it was saved" [ "$back" != "$last" ]
loaded
shot "$back"
lines

step "Click 1D, then 1Y, on the range row"
if reachable "clicking a range"; then
  click_on rangeOption --text 1D
  check "a click on 1D chose 1D" [ "$(saved_range)" = 1D ]
  park
  loaded
  shot click-1D
  lines
  click_on rangeOption --text 1Y
  check "a click on 1Y chose 1Y" [ "$(saved_range)" = 1Y ]
  park
  loaded
  shot click-1Y
  lines
fi

step "On 1Y, the scrub's line through each mark, at its price and at its date, keeps all of the mark clear of it"
if reachable "a scrub over a mark"; then
  read -r _ cy <<< "$(at heroChart)"
  for mark in highMark lowMark; do
    rest=$(matches "$mark" | head -n 1)
    [ -n "$rest" ] || { fail "the $mark is on the 1Y chart"; continue; }
    for word in markPrice markDate; do
      # The word's middle where the mark rests, the high's the upper.
      nth=$([ "$mark" = highMark ] && echo 0 || echo 1)
      x=$(matches "$word" | jq -s -r "sort_by(.y)[$nth] | (.x + .width / 2) | floor")
      move_to "$((x - 3))" "$cy"
      move_to "$x" "$cy"
      sleep 0.3
      shot "scrub-$mark-$word"
      readout "$mark"
      check "the $mark stays while the scrub's line crosses its ${word#mark}" shown "$mark"
      check "all of the $mark stands clear of the line at x $x" jq -e --argjson x "$x" '.x > $x + 2 or .x + .width < $x - 2' <<< "$(matches "$mark" | head -n 1)"
      park
      sleep 0.3
    done
  done
fi

step "A wheel notch up over the range row is the shorter range"
if reachable "the wheel on the range row"; then
  before=$(saved_range)
  scroll_on rangeOption --text 1Y -- -1
  after=$(saved_range)
  check "a notch up moved $before to a shorter range ($after)" [ "$after" != "$before" ]
  park
  loaded
  shot "wheel-$after"
fi

step "The range stays after the popup closes and opens again"
kept=$(saved_range)
key Escape
sleep 0.5
open_popup
loaded
shot "reopened-$kept"
lines
check "the range was still saved as $kept" [ "$(saved_range)" = "$kept" ]
if (( locator )) && [ "$kept" != 1D ]; then
  check "the reopened chart's caption names $kept" shown changeCaption --has "${kept^^}"
fi
keep_data reopened
