# Scrubbing the day

Hovering the chart, or stepping with keys, scrubs back through the day: the
header says the moment, and the price, the change, and the rows follow it. A
chime sounds as the scrub moves, higher where the line is higher.

## Sub-features

- `scrub-keys`: `←` `→` step the scrub one chart step, each step a chime.
- `scrub-pointer`: hovering the chart scrubs to the pointer, a chime each time the line's height under it changes.
- `scrub-follows`: the header says "AT hh:mm · PHASE"; the price, the change, and the "┄ PREV CLOSE" legend show the moment; on 1D the rows follow too.
- `scrub-end`: Esc, the pointer leaving the chart, and a click on the chart each end the scrub and put everything back on now.
- `scrub-silence`: while a scrub shows, by the pointer or the keys, a stream of silence keeps the output awake so each chime plays at once; it ends a second after the scrub does, and an open popup with nothing scrubbed holds none. After a quiet spell the first chimes open with up to 150 ms of silence of their own (`chime-lead*.wav`), shrinking as the output wakes so they keep their order.

## How to get to it (user POV)

- Open the popup from the pill, then move the pointer over the chart.
- With the popup open, press `←` to step back, `→` to step forward.
- Esc ends the scrub (a second Esc closes the popup).

## Driving it with test/tophat

Journey: `test/tophat/journeys/scrub.sh REF`.

Preconditions: the demo watchlist, AAPL featured, on 1D, sounds on (the
demo file doesn't turn them off).

- **Open.** Click the pill (`pillSymbol`). The popup shows (`heroChart`); the header (`statusText`) shows the market's phase; no stream of silence runs (`silence.log`). Shot `01-now`.
- **Keys back.** Press `Left` four times, one at a time. The header says "AT …"; four `chime-*.wav` asks in `sounds.log`; a stream of silence runs. Shot `02-back4`.
- **Keys forward and back.** `Right`, `Left`, `Right`: three more chimes. Shot `03-keys`.
- **Esc.** The header is back on now; the popup stays open; the silence ends within 3 s. Shot `04-esc`.
- **Pointer sweep.** Move across `heroChart` in 3 % steps. The header shows more than one moment; at least one chime; a stream of silence runs. Shots `05-pointer-early`, `05-pointer-end`.
- **Leave.** Move onto the symbol above the chart (`heroSymbol`). The header is back on now; the silence ends within 3 s. Shot `06-left`.
- **Click.** Hover the chart, then click it. The scrub snaps to now. Shot `07-clicked`.

## Gotchas

- Keys sent back to back strike chimes closer than 45 ms apart, and only the latest plays: send them one at a time.
- At night the 1D chart is the overnight session, drawn only at the chart's left edge; the rest of the width scrubs to its last print. Sweep the whole width.
- A pointer chime sounds only when the line's height under it changes, so a small move can be silent; a key step always chimes, unless it lands where no price was printed.
- The first point the pointer reports isn't a move of its own: move twice before reading a hover.
- Retro's chimes and scrub (`s`) aren't driven yet.
