# Ranges and the lines under the chart

Under the chart, a row of ranges from 1D to All. Picking one shows every
stock on that range, even after a restart. Two lines under the ranges place
the price between its lows and highs, and a range marks its high and low on
the chart, with their dates.

## Sub-features

- `range-keys`: `]` steps to the next longer range and `[` to the shorter one, stopping at 1D and All.
- `range-click`: a click on a range in the row picks it.
- `range-wheel`: a wheel notch over the row steps one range, up to the shorter.
- `range-kept`: the range is saved at once and the popup opens on it again.
- `range-lines`: the first line is the range's (on 1D the day's: low, high, OPEN, VOL; on a longer range its low, high, START, VOL); the second is the past 52 weeks' (low, high, MKT CAP, P/E).
- `range-marks`: on a longer range, the high and the low with their dates, marked on the chart; while the scrub's line runs through a mark, the whole mark steps aside, clear of it, and comes back as the line moves off.
- `range-caption`: the caption under the change names the range, or says "SINCE …" for a younger stock.

## How to get to it (user POV)

- Open the popup from the pill, then click a range under the chart, or use the wheel over that row.
- With the popup open, press `]` or `[`.

## Driving it with test/tophat

Journey: `test/tophat/journeys/ranges.sh REF`.

Preconditions: the demo watchlist, AAPL featured, the data file naming no
range (1D).

- **Open.** Click the pill. On 1D, `periodLine` is the day's line. Shot `01-1D`.
- **Every range by key.** Press `]` until the range stops changing. After each, the data file's `range` is the new one; the shot and the words of `changeCaption`, `periodLine`, `yearLine`, `highMark`, and `lowMark` are kept for it (`02-1W` … `11-All`). `]` on the last changes nothing.
- **Back.** `[` steps one range shorter. Shot `13-10Y`.
- **Click.** Click `rangeOption` "1D", then "1Y". The data file follows each. Shots `14-click-1D`, `14-click-1Y`.
- **Marks under the scrub.** On 1Y, the pointer over the middle of each mark's `markPrice`, then its `markDate`, the upper ones the high's: `highMark` or `lowMark` stays shown, and all of it now stands clear of the pointer's x. Shots `15-scrub-highMark-markPrice` … `15-scrub-lowMark-markDate`.
- **Wheel.** One notch up over "1Y" picks a shorter range. Shot `16-wheel-…`.
- **Kept.** Esc closes the popup; the pill opens it again on the same range, and the caption names it. Shot `17-reopened-…`.

## Gotchas

- The range's chart is fetched: wait for `loadingLabel` to go, then for the popup to settle, before the shot.
- A restart of the shell isn't driven: the nested session has no restart that doesn't go through the owner's services.
- On a commit before the locator, the lines are only in the shots (no words), and the click and wheel steps are SKIP. The ranges by key still run, so the shots compare.
- The demo watchlist holds no stock younger than a range, so `range-caption`'s "SINCE …" isn't reached: add one through search to see it.
