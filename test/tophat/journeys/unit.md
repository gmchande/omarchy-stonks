# The unit sign

The sign at the end of the list's header says what the rows' figures are: %
for a percent, ± for an amount, and a bell for since the open. A click on it,
or `c`, steps every row to the next, and the choice is saved.

## Sub-features

- `unit-key`: `c` steps percent → amount → since the open → percent.
- `unit-sign`: a click on the sign steps the same way.
- `unit-change`: on 1D, a click on the change beside the price steps it too; on a longer range that change stays the range's percent and its click does nothing.
- `unit-shown`: the rows' figures (`rowContent`), the change beside the price on 1D, and "SINCE OPEN" under it follow the unit.
- `unit-saved`: the unit is written to the data file at once.

## How to get to it (user POV)

- Open the popup from the pill; click the sign at the right end of the line above the rows, or the change beside the price on 1D.
- With the popup open, press `c`.

## Driving it with test/tophat

Journey: `test/tophat/journeys/unit.sh REF`.

Preconditions: the demo watchlist, in percent, on 1D.

- **Open.** Click the pill. The data file's `changeMode` is `pct`. Shot `01-pct`.
- **c.** `changeMode` becomes `abs`; `changeText` shows a signed amount. Shot `02-abs`.
- **The sign.** Click `unitTarget`: `open`, and `changeCaption` says SINCE OPEN. Shot `03-open`.
- **The change.** Click `changeText`: back to `pct`. Shot `04-back-to-pct`.
- **On 1W.** `]`; a click on `changeText` leaves `changeMode` alone; a click on the sign still steps it. Shot `05-range`.

## Gotchas

- The sign is drawn, not written: its state is in the shot and the data file, not in its words.
- Since the open shows "—" once a listing's next day has begun, until its session's first bar: a stock from the pre-market its answer turns at, an index from the first answer that comes after its next day's pre-market begins (or its open, where its market has none). Before that, both show the last session's. A scrub of the last session still reads from that session's open.
