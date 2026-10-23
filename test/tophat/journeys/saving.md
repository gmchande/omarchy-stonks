# Saving

Every change to the lists, the range, the unit, or the look is written to
`~/.config/omarchy/grvc.stonks.json` at once. When a save can't land, the
footer says "Your changes aren't saved · click to try again" (or "Not
saved" where that won't fit), and a click or the next change tries again.

## Sub-features

- `save-at-once`: a change is in the data file right away.
- `save-first-open`: the first open shows how Stonks is moved and changed, once, and saves that it did (`hinted`).
- `save-failed`: a save that can't land leaves the file at its last good save, and the footer says so.
- `save-retry-click`: a click on that footer saves everything again.
- `save-retry-change`: the next change saves everything again.
- `save-shown`: closed and opened again, the popup shows what was saved.

## How to get to it (user POV)

- Change anything in the popup or the window; nothing to press to save.
- When the footer says the changes aren't saved, click it.

## Driving it with test/tophat

Journey: `test/tophat/journeys/saving.sh REF`.

Preconditions: the demo watchlist, never opened (no `hinted`). The failure
is made by turning off write access to the data file's folder in the
session's own home; the journey turns it back on however it ends.

- **First open.** Click the pill. The data file gets `hinted: true`; `footerHint` shows. Shot `01-first-open`.
- **At once.** `c`: `changeMode` is `abs` in the file.
- **Fails.** Folder read-only, `c`: the file still says `abs`; `footerText` says the changes aren't saved. Shot `03-unsaved`.
- **Click retries.** Folder writable, click the footer: the file says `open`, the footer is "+ Add a symbol" again. Shot `04-retried`.
- **Change retries.** Fail once more, make the folder writable, press `c`: the file moves on, the footer is back. Shot `05-next-change`.
- **Shown again.** Esc, open from the pill: the unit is the saved one. Shot `06-reopened`.

## Gotchas

- A read-only file in a writable folder doesn't fail the save: the write replaces the file. Make the folder read-only.
- A click that still fails says "Still not saved · your disk may be full" for a moment.
- An unreadable file ("Couldn't load your lists") isn't driven.
