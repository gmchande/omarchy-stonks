# Stonks

Stonks is a stock watchlist for the Omarchy shell: a pill in the bar, a popup
and a window, in QML. `CONTRIBUTING.md` says how to run, test and send a
change. This file says what a change is judged by, and why.

## Simplicity

- Simple means untangled, not short: each piece does one job and can change
  on its own. Leave the code simpler than you found it, and delete what
  nothing uses.
- Handle only what real data and real readers can produce. A guard for the
  impossible is code someone has to read forever.
- Before designing around a limit you blame on the shell, find it in the
  shell's code (`/usr/share/omarchy/shell/`).

## What Stonks promises

- **Only what's true.** People act on these prices. Show what Yahoo or
  Robinhood sent, in the listing's own currency and its exchange's own time,
  naming the zone when it isn't the reader's. Never convert, adjust or guess:
  leave out a figure that isn't known. A rate from Yahoo may sit inside a
  ratio, such as a P/E reported in another currency. A "!" means a refresh
  failed or is late, nothing else.
- **Sources.** Yahoo's unofficial endpoints and Robinhood's public price
  history, with no account or key. The README says so, and Stonks never shows
  Robinhood's logo.
- **Color.** Up is the theme's green and down its red, never the accent,
  which in Omarchy means "selected". Where a theme has no usable pair, Stonks
  uses its own for that ground. It never changes the theme's colors.
- **Calm.** Nothing jumps: when the look, range, list or stock changes,
  everything keeps its place and size.
- **Character.** The bull and the bear, their sleep while the market rests,
  the live dot and the day's named moments are part of the product. Each says
  something true and none cheers a number, so a cleanup keeps them.
- **Light on the shell.** Stonks shares the shell's one thread with the whole
  desktop. It fetches a listing only as often as its market moves, nothing
  for a surface no screen shows, nothing while every screen is off, and it
  backs off from a site that refuses it.
- **Lists stay safe.** Stonks never writes over a data file it can't read,
  keeps the keys it doesn't know, and every release reads every older file.
- **Mouse and keys.** Every flow works by mouse alone and by keys alone, and
  what looks clickable acts. A button says what it does, and keys are listed
  on the `?` sheet, never on screen. Tooltips go only where a control can't
  say what it does.
- **Text.** Every character drawn must be one JetBrainsMono Nerd Font has, or
  it shows as a box.

## Words

Every word on screen, in the README, the manifest and the release notes is
for someone who has never seen Stonks and gives it thirty seconds.

- Say what Stonks does for them, in their words, not the code's: "the stock
  you last looked at", not "the featured symbol". One name for each thing:
  the pill, the popup, the window, a row, a list, All, smooth, retro.
- Plain and specific: present tense, active verbs, a number over an
  adjective, each thing said once. American spelling, since most readers are
  in the US.
- Trouble says what's on screen, then why, then what to do.
- Change the words with the code, and promise nothing it doesn't do.

## Tests

- A test fails only when something a user relies on breaks. It never
  restates the code.
- Test a rule in its `.js` file with `bun`. Walk the popup or the window only
  for what passes between pieces, such as a key and its action, or a save and
  the next read.
- A fix's test fails on the code before the fix, as a case in a test that
  already exists.
- Wait for what a step needs, never for a set time. How Stonks looks and
  moves is `test/review.sh`'s to show, not `test/all.sh`'s.

## Code

- QML components take values in and derive the rest with `readonly
  property`. Every side effect is a `Process`. Animations use the shell's own
  timing.
- Rule files (`*.js`) start with `.pragma library`, so QML loads each once,
  and hold pure functions imported one way.
- Secondary text is mixed toward its ground (`Tones.dim`). `Qt.darker` gets
  louder on a light theme.
- Read Omarchy's colors as `Commons.Color`, after `import qs.Commons as
  Commons`: a bare `Color` is Qt's own type.

Also read `AGENTS.local.md` when it exists: it holds this machine's rules.
