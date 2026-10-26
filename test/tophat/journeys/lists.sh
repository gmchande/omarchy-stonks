#!/usr/bin/env bash
# Adding, removing, and putting back (lists.md): search by key and by the
# footer, the ×, Delete and its question in All, the row's menu, Ctrl+Z, and
# PUT BACK, each with its sound and what the data file kept. Usage: lib.sh's
# header.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
journey_begin lists "$@"

# in_all SYMBOL: All holds it; place SYMBOL: its place in All, from 0.
in_all() { saved "(.symbols | index(\"$1\")) != null"; }
in_us() { saved "(.lists[] | select(.name == \"US\") | .symbols | index(\"$1\")) != null"; }
not_in_all() { ! in_all "$1"; }
not_in_us() { ! in_us "$1"; }
place() { jq -r --arg s "$1" '.symbols | index($s)' "$data"; }
rows() { readout rowSymbol; }
# hidden NAME [FILTERS]: no such item is on screen.
hidden() { ! shown "$@"; }

step "Open the popup from the pill"
open_popup
loaded
shot open
keep_data before

step "a opens search; a symbol typed; Enter adds the top result"
key a
typed MSFT
if (( locator )); then
  soon "search found MSFT" 15 shown searchResult --word MSFT
else
  # Nothing tells the answer's arrival without the locator: give it the
  # search's debounce, the session's delay, and a few seconds more.
  sleep $((4 + ${SLOW:-0}))
fi
settle
shot search-MSFT
readout searchResult searchAdd
key Return
soon "Enter added MSFT to All" 20 in_all MSFT
(( locator )) && { soon "MSFT's row joined the list" 20 shown rowSymbol --text MSFT; }
soon "the add sound played" 5 heard add.wav
sounds_here
shot added-MSFT
keep_data added-MSFT

step "The footer's \"+ Add a symbol\", a name typed, a click on its result"
if reachable "the footer and a result"; then
  click_on footerText --has "Add a symbol"
  typed nvidia
  soon "search found NVDA for 'nvidia'" 15 shown searchResult --word NVDA
  shot search-nvidia
  readout searchResult
  click_on searchResult --word NVDA
  soon "the click added NVDA to All" 20 in_all NVDA
  soon "NVDA's row joined the list" 20 shown rowSymbol --text NVDA
  soon "the add sound played" 5 heard add.wav
  sounds_here
  shot added-NVDA
  keep_data added-NVDA
fi

step "↑ to AAPL and Enter shows it; Delete on it, in All and US, asks first; Enter removes it from both"
for _ in 1 2 3 4 5 6 7 8 9; do key Up; done
key Return
was=$(place AAPL)
key Delete
sleep 0.3
shot asked
readout rowMenuLine
check "AAPL is still kept before the answer" in_all AAPL
key Return
soon "Enter removed AAPL from All" 5 not_in_all AAPL
check "AAPL left US too" not_in_us AAPL
soon "the remove sound played" 5 heard remove.wav
sounds_here
shot removed-AAPL
rows
keep_data removed-AAPL

step "Ctrl+Z puts AAPL back in both lists, at its place"
key ctrl+z
soon "Ctrl+Z put AAPL back in All" 5 in_all AAPL
check "Ctrl+Z put AAPL back in US" in_us AAPL
check "AAPL is back at its place ($was)" [ "$(place AAPL)" = "$was" ]
soon "the undo sound played" 5 heard undo.wav
sounds_here
shot undone-AAPL
rows
keep_data undone-AAPL

step "The × on a hovered BTC-USD, in All alone, removes it at once; the row sliding under the still pointer shows no ×, and the footer offers Undo"
if reachable "the row's ×"; then
  btc=$(place BTC-USD)
  hover_on rowSymbol --text BTC-USD
  shot hover-BTC
  click_on rowRemove --symbol BTC-USD
  soon "the × removed BTC-USD" 5 not_in_all BTC-USD
  soon "the remove sound played" 5 heard remove.wav
  sounds_here
  check "no × under the still pointer" hidden rowRemove
  check "the footer offers Undo BTC-USD" shown footerUndoText --text "Undo BTC-USD"
  readout footerText footerUndoText
  shot removed-BTC
  rows
fi

step "\"+ Add a symbol\" offers it back first, as PUT BACK; a click puts it back"
if reachable "PUT BACK"; then
  click_on footerText --has "Add a symbol"
  soon "search offers BTC-USD" 5 shown searchResult --word BTC-USD
  shot put-back-offer
  readout searchResult searchAdd
  check "the offer says PUT BACK" shown searchAdd --has "PUT BACK"
  click_on searchResult --word BTC-USD
  soon "PUT BACK put BTC-USD back" 5 in_all BTC-USD
  check "BTC-USD is back at its place ($btc)" [ "$(place BTC-USD)" = "$btc" ]
  soon "the undo sound played" 5 heard undo.wav
  sounds_here
  shot put-back
  keep_data put-back
fi

step "A right-click on SPY's row offers where to remove it from; a click removes it"
if reachable "the row's menu"; then
  click_on rowSymbol --text SPY -- right
  sleep 0.3
  shot row-menu
  readout rowMenuLine
  click_on rowMenuLine --has "Remove from"
  soon "the menu removed SPY" 5 not_in_all SPY
  soon "the remove sound played" 5 heard remove.wav
  sounds_here
  key ctrl+z
  soon "Ctrl+Z put SPY back" 5 in_all SPY
  shot menu-undone
  keep_data menu-undone
fi

step "The × removes BTC-USD again; the footer's Undo takes it back"
if reachable "the footer's Undo"; then
  btc=$(place BTC-USD)
  hover_on rowSymbol --text BTC-USD
  click_on rowRemove --symbol BTC-USD
  soon "the × removed BTC-USD" 5 not_in_all BTC-USD
  soon "the footer offers Undo BTC-USD" 3 shown footerUndoText --text "Undo BTC-USD"
  shot undo-offer
  click_on footerUndoText
  soon "Undo put BTC-USD back" 5 in_all BTC-USD
  check "BTC-USD is back at its place ($btc)" [ "$(place BTC-USD)" = "$btc" ]
  soon "the undo sound played" 5 heard undo.wav
  check "the offer went with the undo" hidden footerUndoText
  sounds_here
  shot undo-clicked
  keep_data undo-clicked
fi
