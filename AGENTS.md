# Stonks

Stonks is a stock watchlist for the Omarchy shell, in QML.
`CONTRIBUTING.md` says how to run and test it.

## What Stonks is for

Stonks aims to be the watchlist that gets the hard part right: true data,
light fetching, a quick shell, and charts and controls made with craft and
simple enough that a newcomer reads each at a glance. It leaves out
holdings, news and alerts, since many plugins list features and few get
these right. Judge any idea by whether it makes what Stonks already does
truer, lighter, quicker, simpler or better made.

## Simple code

- Simple code is untangled, not short: each piece does one job and can
  change on its own, so someone who writes Omarchy's plugins enjoys
  changing it. Leave the code you change simpler, and delete what nothing
  uses.
- Handle only what real data and real readers can produce, since a guard
  for the impossible is code someone reads forever.
- Read Omarchy's colors as `Commons.Color`: a bare `Color` is Qt's type.
- Find a shell limit in `/usr/share/omarchy/shell/` before designing around
  it.

## What Stonks promises

- **Only what's true.** People act on these prices. Stonks shows what Yahoo
  or Robinhood sent, in the listing's currency and its exchange's time,
  naming the zone when it isn't the reader's. It never converts, adjusts or
  guesses, and leaves out what isn't known. The README names the two
  exceptions: a Yahoo rate may sit inside a ratio, such as the P/E, and the
  market cap moves with the price from Yahoo's last figure, since shares
  change only when the company reports. A "!" means only that a refresh
  failed or is late.
- **Sources.** Market data comes only from Yahoo's unofficial endpoints and
  Robinhood's public price history, with no account or key, as the README
  says. Robinhood's logo never shows.
- **Color.** Up is the theme's green and down its red, never its accent,
  which means "selected". Where a theme has no usable pair, Stonks uses its
  own for that ground, and it never changes the theme's colors.
- **Calm.** Nothing jumps: when the look, range, list or stock changes,
  everything keeps its place and size.
- **1D at night.** A stock's day starts at its open, and until the next
  open the chart keeps the day that closed, with tonight and the pre-market
  joined at its end. Tonight's trades belong to the day ahead: from the
  night's first trade the panel's % counts from the close just gone, its one
  dashed line is that close, and the closed day's session draws fainter, in
  green above that line and red below, so every colour on the chart reads
  against the one line drawn. The line breaks only for hours that take room
  on the chart, such as Tokyo's lunch. Until 04:00 in its exchange's time,
  the rows and the pill report how the day ended, its close and its move,
  with tonight drawn fainter on their line in green and red by the same
  rule, or grey where the day they report is already faint, and tonight's
  move in the pill's hover.
- **Character.** The bull and the bear, their sleep while the market rests,
  the live dot and the day's named moments survive any cleanup: each says
  something true, and none cheers a number.
- **Light on the shell.** Stonks shares the shell's one thread with the
  desktop. It fetches a listing only as often as its market moves, never
  for a surface no screen shows or while every screen is off, and backs off
  from a site that refuses it.
- **Lists stay safe.** Stonks never writes over a data file it can't read,
  keeps the keys it doesn't know, and every release reads every older file.
- **Mouse and keys.** Every flow works by mouse alone, and what looks
  clickable acts. The only keys are the `?` sheet's and Omarchy's panel
  keys. A tooltip goes only on a control that can't say what it does.

## Words

Every word on screen, in the README, the manifest and the release notes is
for someone new to Stonks who gives it thirty seconds.

- Use their words, not the code's: "the stock you last looked at", not "the
  featured symbol". Give each thing one name, the one the README uses.
- Prefer a number to an adjective, and say each thing once.
- Trouble says what's on screen, then why, then what to do.
- Change the words with the code, and promise nothing it doesn't do.

## Tests

- A test fails only when something a user relies on breaks, and never
  restates the code.
- A fix's test is a new case in the test that already covers it, and fails
  before the fix.

Also read @AGENTS.local.md when it exists: it holds this machine's rules.
