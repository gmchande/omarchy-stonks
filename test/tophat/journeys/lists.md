# Adding, removing, and putting back

Search adds a stock to the list you're looking at. A row goes with its ×,
`x`, or its menu, and comes back with the footer's Undo, `u`, or PUT BACK,
in its lists and at its old place. Each makes a short sound, and the data
file keeps the result.

## Sub-features

- `add-key`: `a` or `+` opens search; typing a name or symbol finds it; Enter adds the top result.
- `add-footer`: "+ Add a symbol" opens search; a click on a result adds it.
- `add-joins`: the new row joins once its first price arrives, with the add sound.
- `remove-x`: `x` removes the selected row; in All, a symbol another list holds too asks first ("Remove from all 2 lists"), and Enter answers.
- `remove-cross`: the × beside a hovered row's symbol removes it; the row that slides under the still pointer shows its × only once the pointer moves.
- `remove-menu`: a right-click on a row offers where to remove it from.
- `put-back-footer`: for 5 seconds after a removal, "Undo NAME" beside "+ Add a symbol" puts it back; the add beside it stays clickable.
- `put-back-u`: `u` undoes the last removal, until a list next changes.
- `put-back-search`: "+ Add a symbol" offers the removed symbol first, with PUT BACK.
- `sounds`: add, remove, and undo each ask for their sound.

## How to get to it (user POV)

- Open the popup from the pill. Press `a`, or click "+ Add a symbol" at its foot.
- Point at a row and click the × after its symbol; or select it (`j` `k`, `1` to `9`) and press `x`; or right-click it.
- Click "Undo NAME" in the footer, press `u`, or click "+ Add a symbol" and choose PUT BACK.

## Driving it with test/tophat

Journey: `test/tophat/journeys/lists.sh REF`.

Preconditions: the demo watchlist (All: AAPL, JNJ, SPY, ^GSPC, BTC-USD,
SHEL.L, 7203.T; US: the first four), Yahoo's search reachable.

- **Add by key.** `a`, type "MSFT", wait for a `searchResult` starting MSFT, Enter. The data file's All holds MSFT; its row (`rowSymbol` "MSFT") joins; `add.wav` asked for. Shots `02-search-MSFT`, `02-added-MSFT`.
- **Add by footer.** Click `footerText` "+ Add a symbol", type "nvidia", click the NVDA result. NVDA saved, its row joins, `add.wav`. Shots `03-search-nvidia`, `03-added-NVDA`.
- **x asks first.** `1` shows AAPL; `x` shows the question (`rowMenuLine`), AAPL still saved; Enter removes it from All and US; `remove.wav`. Shots `04-asked`, `04-removed-AAPL`.
- **u.** AAPL is back in All and US at its old place; `undo.wav`. Shot `05-undone-AAPL`.
- **×.** Hover BTC-USD's row, click its `rowRemove`. Gone at once (no other list holds it); `remove.wav`. No `rowRemove` shows under the still pointer, and `footerUndoText` says "Undo BTC-USD". Shot `06-removed-BTC`.
- **PUT BACK.** Click "+ Add a symbol": the first result is BTC-USD, its `searchAdd` says PUT BACK; a click puts it back at its old place; `undo.wav`. Shots `07-put-back-offer`, `07-put-back`.
- **Row menu.** Right-click SPY's symbol: the menu (`rowMenuLine`) says where it goes from; a click on it removes SPY; `u` brings it back. Shots `08-row-menu`, `08-menu-undone`.
- **Footer's Undo.** Hover BTC-USD again, click its `rowRemove`; `footerUndoText` says "Undo BTC-USD"; a click on it puts BTC-USD back at its place, `undo.wav`, and the offer goes. Shots `09-undo-offer`, `09-undo-clicked`.

## Gotchas

- An added row is hidden until its first price arrives, and its sound plays then, not on Enter.
- Adding shows the new symbol in the chart, so the selection follows it: select a row (`1`) before `x`.
- The × shows only on a row the pointer moved onto (two moves): a pointer that was resting there when the popup opened doesn't count.
- The removal on offer is in memory only, and ends at the next change to the lists.
