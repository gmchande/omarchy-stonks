# Stonks

How to run, verify and send a change is in `CONTRIBUTING.md`; this file
holds the rules a change is judged by.

## Simplicity

- Simple means untangled, not short: each piece does one job and can change on its own. Refuse state braided with time, one component knowing two concerns, a flag that couples two paths, a result that depends on hidden order.
- Leave the code simpler than you found it.
- No handling for cases this data and its users can't produce.
- Delete what nothing uses.
- Confirm a limit you blame on the shell in its code
  (`/usr/share/omarchy/shell/`) before designing around it.

## Product rules

- **Data.** Quotes come from Yahoo's unofficial chart, spark, and search
  endpoints, and overnight prices from Robinhood's public price history, with
  no account or key. The README says so plainly, and nothing shows
  Robinhood's logo.
- **Only what's true.** Show what the source sent, never an adjustment,
  precision, or coverage it didn't. Leave out a figure that isn't known; never
  guess it. The headline price is Yahoo's regular-market quote. If that price
  is missing, keep the last regular chart trade, labelled "Last trade"
  with its time. Only a failed or overdue refresh shows a "!".
- **Money.** Each listing in its own currency, with its code beside the
  exchange, as Apple's Stocks does: nothing shown is converted. A rate may
  serve inside a ratio, such as a P/E whose earnings are reported in
  another currency, from Yahoo's own quotes, never a new source.
- **Time.** An exchange's times are its own, with its zone named when it
  differs from the reader's. Never assume New York.
- **Colour.** Up is the theme's green and down its red (the shell's urgent),
  everywhere; never the accent, which in Omarchy means selected. Where a
  theme's green and red are no real pair (two greys, two greens, two blues)
  or the fainter is under 3:1 on a surface's ground, up and down there are
  Stonks' own pair for that ground, dark or light. Never adjust a theme's
  colours.
- **Calm.** Nothing moves when the look, range, list, order, or charted
  stock changes, except the footer for a list of another length: it rides
  the popup's easing edge, and sits one gap under a short list in the
  window.
- **Character.** Stonks has a few signs of life: the bull and the bear,
  their sleep while the market rests, the live dot's ripples, and the day's
  named moments, such as "Power hour". Each says something true and none
  cheers a number. They are part of the product, so a cleanup keeps them.
- **Fetching.** Stonks fetches each listing only as often as its market can
  move, and treats a window no screen shows as closed. It asks Robinhood its
  two questions about a stock, whether it trades all day and its overnight
  prices, at the same time, never one after the other. It fetches nothing
  while every screen is off, and leaves a site that refuses it alone for a
  while.
- **Lists.** All holds every symbol, and named lists hold some of them. The
  data file at `~/.config/omarchy/grvc.stonks.json` keeps its version-1 keys,
  so an older build still reads All, and one that can't be read is never
  written over. When Stonks writes the file, it keeps every key it doesn't
  know, so a newer build's settings survive an older one.
- **Mouse and keys.** Every flow works by mouse alone and by keys alone, and
  anything that looks clickable acts when clicked. A button says only what it
  does, and no word on screen names a key: the keys are on the `?` sheet.
- **Tooltips.** Few: a control has one only where it can't say what it does
  by itself. A tip shows as the shell's own do, above its control where
  there's room and below where there isn't, and may cover what's beside the
  control while the pointer rests on it.
- **Text.** Every character drawn is one JetBrainsMono Nerd Font has.

## Words

The README, the release notes, the manifest, the forms, and every word on
screen are written for one reader who has never seen Stonks and has thirty
seconds to give it.

- Open with what Stonks does for the reader, in a sentence with a verb. The
  second sentence says something the first didn't.
- Change the words with the code, and promise nothing it doesn't do.
- Use the reader's words, not the code's: "the stock you last looked at",
  not "the featured symbol"; "show the selected row's chart", not "feature
  the cursor row".
- One name for each thing, the same on screen and in the docs: the pill,
  the popup, the window, a row, a list, All, smooth and retro.
- Present tense and active verbs, with Stonks or "you" doing something:
  "Stonks keeps the lists it has", not "the lists are kept". British
  spelling: colour, centre.
- Specific over general: a number, a time, the words the reader will see.
  "150 symbols refresh every minute", not "long lists stay fast".
- Say it once. Cut "very", "just", "simply", "quite", and any sentence that
  repeats the one before.
- Trouble starts from the words on screen, then says why, then what to do.
- Release notes open with a sentence on what the release changes for you,
  then the update commands, then a line per change saying what you'll
  notice. Add a section headed by who must act only when someone must.

## Style

- QML: value-in components, `readonly property` for derived state, a
  `Process` for every side effect, animations at the shell's 160 ms
  OutCubic.
- Secondary text is the foreground mixed toward its ground (`Tones.dim`),
  never `Qt.darker`, which gets louder on a light theme.
- Read Omarchy's colours as `Commons.Color`, after
  `import qs.Commons as Commons`. A plain `Color` names Qt 6.12's own
  `Color` type, not Omarchy's.
- Rule files: `.pragma library` first, so QML loads each once rather than
  once per row; top-level functions only, read through `.import`, imports
  one way with no cycles.

Also read `AGENTS.local.md` when it exists: it holds this machine's rules.
