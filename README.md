# Stonks

Stonks puts a stock watchlist in your Omarchy 4 bar. A small pill shows how
a stock is doing today. Click it for that stock's chart and your lists, and
move the pointer across the chart to see the price at any moment on it.

<img src="preview.png" alt="Stonks in the Omarchy bar: its pill shows SPY's sparkline and change. Below the bar, the pixel bull, the STONKS wordmark, 'Stocks in your Omarchy bar.' and 'Free · No account · No API key', beside the retro popup: SPY at 769.94, up 0.88%, with the bull, over the day's chart in pixel columns">

- Charts from one day to all time.
- Pre-market, after-hours, and overnight prices, and when the market opens
  or closes.
- Stocks, ETFs, indexes, and crypto, from New York to London and Tokyo, each
  in its own currency.
- Lists of your own, such as a portfolio or a sector.
- Two looks, smooth and retro, in your theme's colours, light or dark.
- No account and no API key.

It doesn't track holdings, send price alerts, or convert prices into another currency.

Website: [getstonks.app](https://getstonks.app)

[![Omarchy marketplace](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fgmchande%2Fstonks-site%2Fmarketplace-status%2Fmarketplace.json)](https://plugins.omarchy.org/plugin.html?id=grvc.stonks)
[![Last verified on the Omarchy marketplace](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fgmchande%2Fstonks-site%2Fmarketplace-status%2Fverified.json)](https://plugins.omarchy.org/plugin.html?id=grvc.stonks)

## Install

Needs Omarchy 4.

```sh
omarchy plugin add https://github.com/gmchande/omarchy-stonks.git --enable
```

Omarchy warns that plugins run unsandboxed and asks you to confirm. Then it
asks where in the bar to put `grvc.stonks`, which is Stonks' id. The centre
is the default.

To read the code first, leave out `--enable`, say no when Omarchy offers to
enable it, and run `omarchy plugin enable grvc.stonks` when you're ready.

Stonks starts with five symbols so the pill has something to show: NVDA,
AAPL, MSFT, SPY, and TSLA. Add your own and remove any you don't follow.

## The pill

<img src="media/pill.png" width="200" alt="The pill's four forms: a sparkline, an arrow, the price as text, and the day's bear">

The pill shows today's move for the stock you last looked at, in one of four
forms: a sparkline, an arrow, the price as text, or the day's animal, the
bull on an up day and the bear on a down one. Middle-click it to change its
form. On a bar at the side of the screen it shows the animal, and a
middle-click there switches to the symbol over its change.

Scroll over it to step through your list, left-click for the popup,
right-click for the window, and drag it to move it along the bar.

## Reading the day

<img src="media/scrub.png" width="480" alt="The popup scrubbed back an hour and a half, to 10:15 in the morning: the price, the change, and the rows follow the pointer">

Hover the chart to scrub back through the day: the price, the change, and
the rows follow the pointer. Click the bull, or on a down day the bear, to
replay the chart.

Pick a range under the chart, from 1D to All. Every stock then shows that
range, even after a restart. The rows stay on the day's move. To see it as
a percent, an amount, or since the open, click the sign at the end of the
list's header, or on 1D the change beside the price. A range marks its
high and low on the chart, with their dates, and a stock younger than the
range says when it began: "SINCE 31 JUL 2025".

Under the ranges, two lines place the price between its low and high. The
first is the range's: on 1D the day's, beside its open and volume, and on a
longer range that range's, beside START, the price its change is measured
from, and the volume traded over it. The second is the past 52 weeks', beside
the market cap and P/E. The market cap is an estimate: Yahoo's last reported
figure, moved with the price since. The P/E is the price over the last
year's earnings per share. Where a company reports earnings in another
currency, as Shopify does in US dollars, Stonks converts them at Yahoo's
rate of the day, inside the P/E alone.

The top line says where the market is, in its own time: counting down to
the open or the close, after hours, or closed. With less room, as at a
larger text size, it says less and keeps the time: "CLOSED AT 16:00". A
smaller line under the price shows the pre-market, after-hours, or
overnight price. The overnight price is for the US stocks and ETFs
Robinhood trades overnight. Until the
next session opens, the 1D chart shows the last session, the one the price
and its move are about, then the night after it and the pre-market.
Pointing anywhere on it measures that price from the dashed line, the
close the chart is drawn against; the smaller line measures the overnight
price from the last close. A stock that trades only now and then shows the
night's trades as dots.

An old price says "As of" and its time, on its row and above the price.
Old means more than two minutes behind while its market trades, or saved
from the last session. A price nothing kept fresh while the popup and the
window were closed, such as a coin's, says it only if its new price takes
more than 2 seconds to come. At the open, the last close says it only if
the session's first price takes more than a minute to come; Stonks asks for
it every 15 seconds until then. If Yahoo sends no regular price, Stonks keeps
the last regular chart trade, labelled "Last trade" with its time.
If Yahoo sends a price without its time, it says "Time not sent", and
"Saved" too if kept from the last session.
A refresh that fails, or gets no answer in 90
seconds, says so in the same places and puts a "!" on the pill.

## Your lists

<img src="media/lists.png" width="480" alt="The list menu open over the rows: All with seven symbols, US with four, New list, and Manage lists">

Click the list's name to switch lists, start one, or manage them. All holds
every symbol you follow, and your own lists hold some of them. Ctrl-click a
row to choose the lists it's in. Removing a symbol from All removes it
everywhere.

Click "+ Add a symbol" and type a name or a symbol. The top result shows in
the chart, and Enter or a click adds it. Search finds stocks, ETFs,
indexes, and crypto.

To remove a row, point at it and click the × beside its symbol, or press
Delete: it goes from the list you're looking at. The row that slides into
its place shows its × only once you move the pointer, so a second click
can't remove it by mistake. Right-click a row to choose where it goes from,
such as "Remove from Growth" or "Remove from all 3 lists". In All, where
removing takes a symbol out of every list, the × and Delete ask first when
one of your own lists holds it too.

For 5 seconds after a removal, "Undo NVDA" shows beside "+ Add a symbol":
click it to bring the row back. Until a list next changes, `Ctrl+Z` does the
same, and so does "+ Add a symbol", where the symbol is the first result,
with PUT BACK. Each puts it back in its lists at its old place, with the
price it had, and Stonks asks for a new one at once.

The line beside the list's name shows how many rows are up, in green, and
down, in red. Click the order word to sort by symbol, name, or change, and
click its arrow to reverse the sort.

The sign at the end of the line says what the rows' figures are: % for a
percent, ± for an amount, and a bell for since the open. Click it to step
every row to the next. Sorted by change, the rows rank by the percent they
show, from the open when they show since the open. Amounts can't be ranked
across currencies, so while the rows show amounts they stay in percent
order.

## The window

<img src="media/window.png" width="720" alt="Stonks' window: the popup's chart and rows at the window's width">

Stonks also opens in a tiled window: the popup's chart and rows at the
window's width. To open it, right-click the pill or run
`omarchy-shell grvc.stonks openWindow '{}'`. It shares the popup's lists,
range, and quotes. To float it, match class `org.quickshell` and title
`Stonks` in a window rule.

The window also works with no pill. Run
`omarchy plugin disable grvc.stonks`, then add `{ "id": "grvc.stonks" }` to
`plugins` in `~/.config/omarchy/shell.json` to keep the plugin loaded. To
bring the pill back, remove that entry first, then run
`omarchy plugin enable grvc.stonks center`.

For keys that open and close the popup and the window, add these lines to
`~/.config/hypr/bindings.lua`. Omarchy doesn't use either key by default:

```lua
o.bind("SUPER + ALT + T", "Stonks popup", "omarchy-shell shell toggle grvc.stonks")
o.bind("SUPER + SHIFT + T", "Stonks window", "omarchy-shell grvc.stonks toggleWindow")
```

For Stonks in the app launcher, which `omarchy plugin add` doesn't set up:

```sh
cp ~/.config/omarchy/plugins/grvc.stonks/share/stonks.desktop ~/.local/share/applications/
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
cp ~/.config/omarchy/plugins/grvc.stonks/share/grvc.stonks.svg ~/.local/share/icons/hicolor/scalable/apps/
```

## Smooth or retro

<img src="media/retro.png" width="480" alt="The popup in retro: block digits and a chart of pixel columns">

Stonks opens in retro: the price in block digits and the charts in pixel
columns, the way Omarchy draws its logo. Click the small chart icon at the
top right to switch between smooth and retro.

<img src="media/light.png" width="480" alt="The popup in Catppuccin Latte, a light theme: Stonks' own green and red, for a light ground, on the theme's pale background">

Both looks draw in your theme's colours, light themes too: up in its green
and down in its red, or in Stonks' own pair where the theme's are missing,
too alike, or too faint.

## Sounds

Stonks makes a short sound when you add a symbol, remove a row, or undo the
removal, which plays the removal backwards, and a shutter when you take a
screenshot. Run the pointer along the chart
and it plays like a row of chimes, higher where the line is higher: the bars
you cross ring, up to 22 a second, ending on the one under the pointer, and
each step of `←` `→` rings too. A replay sweeps the same bars along the
line; in retro it also ticks where the line crosses the chart's baseline:
the previous close on 1D, the range's first price on the others. Each look
has its own voice. A soft bell rings as the market of the stock you last
looked at opens and as it closes, on time or not at all, and never while
every screen is off or an app records from your microphone. Nothing else
sounds by itself: no refresh or price. Click the speaker at the top right,
or press `m`, to turn sounds off; Stonks remembers. Your system volume
sets how loud they are.

## Screenshots

Click the camera at the top right, or press `Ctrl+C`, for a picture of the
chart you're looking at, laid out to share: the price large with its
currency beside it, its move, the day's bull or bear, the exchange, the time
of the price with its zone, the price the move is measured from, a range's
high and low on its chart, and at the foot the day's date or the range's
length. Scrubbed, it shows the moment you scrubbed to. Your list is never in
it. It lands where Omarchy's own screenshots do, on Omarchy 4.0 and on 4.5:
a file in your screenshots folder, the picture on the clipboard, and
Omarchy's notification, which opens it in your screenshot editor when you
click it: Omasnap on 4.5, Tensaku on 4.0.

## Keys

`?` opens a sheet of every key, the same as this table:

| Key | Does |
| --- | --- |
| `↑` `↓` | Move the selection |
| `⏎` | Show the selected row's chart |
| `←` `→` | Scrub the chart one step |
| `[` `]` | Change the range |
| `p` | Replay the chart |
| `Ctrl+C` | Take a screenshot |
| `a` | Add a symbol |
| Delete or Backspace | Remove the selected row |
| `Ctrl+Z` | Undo a removal |
| `Shift+↑` `Shift+↓` | Move the row in your own order |
| `o` | Change the order |
| `Shift+O` | Reverse the order |
| `l` | Open the list menu |
| `c` | Show the change as %, amount or since the open |
| `s` | Smooth or retro |
| `m` | Sound on or off |
| `r` | Refresh |
| Tab or `Shift+Tab` | Next or previous panel on the bar (popup) |
| `?` | All keys |
| `Esc` | Close |

## If something's wrong

A "!" on the pill means its stock's quote is late or its last refresh
failed: point at the pill to read which. The row and the line above the
price say the same.

- **The header says "No prices from Yahoo".** Every symbol you follow is
  waiting on Yahoo, or Yahoo turned every one away, so Stonks says it once
  rather than on every row. Rows with a price keep it, with the time it's
  from, and the rest show their symbol alone. What to do is as for "No
  data" below. If Yahoo has changed what it sends, only a newer Stonks can
  fix that.
- **A row says "No data" or "Update overdue".** Stonks has waited 90
  seconds on Yahoo: no answer came, or Yahoo turned it away. A row with a
  price keeps it, with the time it's from. Check your connection. If other
  sites load, Yahoo is down or refusing Stonks, and there's nothing to do
  but wait. Stonks keeps trying by itself, less often the longer Yahoo stays
  away, and `r` won't hurry it.
- **A row says "No data for this symbol" or "Refresh failed".** Yahoo said
  it has nothing for the symbol, or sent a broken answer three times
  running. A row with a price keeps it, with the time it's from, and `r`
  tries again. A symbol Yahoo has dropped, after a merger, a rename, or a
  delisting, stays this way: search for the company to find what Yahoo
  calls it now.
- **A stock or index says "As of" while its market is open.** Yahoo sends
  many exchanges' prices late, and some indexes'. When we measured,
  London's, São Paulo's, and the Cboe's VIX came 15 minutes late and
  Mexico's 20. Nasdaq's, NYSE's, Toronto's, and crypto came within a
  minute. For any other exchange, Tokyo's among them, see [Yahoo's table of delays](https://help.yahoo.com/kb/SLN2310.html).
  A thin stock can say it too, when its last trade was more than two
  minutes ago. The overnight price shows its own time, usually 10 to 15
  minutes back, since Robinhood reports those trades late, and dims once
  it's 20 minutes old.
- **A price looks wrong.** Each price is in its listing's currency, never
  converted, and shows no code where Yahoo names none, as for some
  indexes. A price marked PENCE is in pence, as Yahoo quotes many London
  listings: 3,580.00 is £35.80. The large price is the regular session's.
  Pre-market, after-hours, and overnight trades show on the smaller line
  under it, which some apps show as the main price. The change is from the
  previous close, unless you've clicked it to show since the open. On a
  longer range, it's from the range's start. Stonks shows Yahoo's prices as
  sent, except for the odd stray price Yahoo drops into a chart, which it
  leaves out.
- **The day's chart says "No trades charted" or "Traded only at" a time.**
  The listing traded too little that day to draw a line.
- **The header says "1W unavailable", with RETRY beside it.** Yahoo didn't
  send that range's chart. Click RETRY, or press `r`. While Yahoo is
  turning Stonks away, a range fails at once.
- **Search says "Search didn't answer", with RETRY beside it.** Yahoo's
  search didn't answer. Click RETRY, or press Enter. While Yahoo is turning
  Stonks away, a search fails at once: try again in a moment.
- **The header says "schedule unavailable".** Stonks knows each exchange's
  holidays up to a set date. This exchange's have run out, so it can't say
  when the market next opens. Stonks doesn't update itself:
  [update it](#update) for a renewed calendar.
- **The footer says "Couldn't load your lists".** The file holding your
  lists, `~/.config/omarchy/grvc.stonks.json`, can't be opened or isn't
  valid JSON, often after a hand edit. Stonks keeps the lists it has and
  writes nothing over the file until it can read it again. A change you
  make meanwhile shows, and the footer says "Your changes aren't saved ·
  couldn't load your lists": the file read again, or a restart, loses it.
  Fix the file and Stonks reads it as you save, or remove it to start over
  with the five starter symbols.
- **The footer says "Your changes aren't saved".** Stonks couldn't write
  the file holding your lists: the disk is full, or the file or its
  folder, `~/.config/omarchy`, is read-only. Your lists stay as they look
  until the shell restarts, and a restart loses every change since the
  last save. Free some space or fix the permissions, then click the
  footer. Any change you make tries again too.

To report a price or chart that looks wrong, or anything this doesn't
answer, use the [bug form](https://github.com/gmchande/omarchy-stonks/issues/new?template=bug.yml).
For a price, give the symbol, the range, and the time (scrub the chart to
it), what Stonks showed, and what your broker or the exchange showed then.
The shell's log the form asks for can name the prices Stonks left out.

## What it runs

- **Needs:** nothing beyond Omarchy 4. It runs `curl`, PipeWire's
  `pw-play`, `pw-cat`, and `pw-dump`, and `sh`, `bash`, `timeout`,
  `head`, `mkdir`, `chmod`, `mktemp`, `ln`, and `rm`, which Omarchy ships,
  and, for a screenshot, `wl-copy` and `omarchy-notification-send`.
- **Commands:** `curl` for every request; as Stonks starts, one `sh` that
  makes its cache folder, `mkdir` and `chmod`, yours alone, and `chmod` as
  it writes each of its files, to make it yours alone too; only when it
  saves `~/.config/omarchy/grvc.stonks.json` and finds none there, one
  `sh` that makes it, yours alone before it holds anything: `mktemp` makes
  a file beside it that only you can read, the `sh` writes your settings
  into it from its environment, never its arguments, `ln` puts it under
  its name, never over a file there, and `rm` takes the extra name away;
  each of these under `timeout`, which stops it after 5 seconds; a save
  that can't be made this way says your changes aren't saved; while
  sounds are on, `pw-play` to play a sound, only
  when you add, remove, or undo a row, take a screenshot, turn sounds on,
  replay a chart, or move along it, or the bell is due, with 4 seconds
  under `timeout`, and one `sh` that
  starts a `pw-play` for each chime, with 2 seconds each under `timeout`,
  and plays nothing else; while sounds are on and you scrub the chart, with
  the pointer on it or by `←` `→`, and for a second after, `pw-cat` playing
  silence, so each chime plays at once; `pw-dump` once as each bell is due, in
  `bash` under `timeout` for 3 seconds and through `head` for 4 MB, to see
  whether an app is recording from a microphone, reading only which streams
  run; an answer that runs out of time, fails, or goes over 4 MB counts as
  recording, so the bell stays quiet; only when you take a screenshot, one
  `sh` that looks for `omasnap`, Omarchy 4.5's screenshot tool, and names
  the picture's file in your screenshots folder, making the folder if it
  isn't there, its answer through `head` for 8 KB; another that hands
  `wl-copy` the picture on its input, to
  put it on the clipboard; and `omarchy-notification-send` with Omarchy's
  own words, as Omarchy 4.0's own screenshots do; each under `timeout`,
  which stops it after 5 seconds; only when you click that notification,
  Omarchy runs your screenshot editor on the file: `omasnap` where it's
  installed, else `OMARCHY_SCREENSHOT_EDITOR`, else Tensaku; `omarchy restart
  shell` only when you click the notice that an update is on disk; and, only
  when you click the note that a newer Stonks is out, `omarchy plugin update
  grvc.stonks` in a terminal.
- **Silence's cost:** while `pw-cat` plays silence, your speakers'
  amplifier stays powered and your headphones stay connected to this
  computer, as when any sound plays, and it takes about a tenth of a
  percent of one processor core. It runs only while you scrub the chart,
  or a replay waits for a sleeping output to wake, never just because the
  popup or the window is open. A sound after 4 seconds of quiet from
  Stonks starts with up to 150 ms of silence of its own, so a sleeping
  output wakes before the sound and none of it is cut; a replay waits for
  the output instead, so its sound keeps in step with its sweep.
- **Sites:** `query1.finance.yahoo.com` for quotes, charts, and the market
  cap and P/E, with the day's currency rate a P/E needs;
  `query2.finance.yahoo.com` for search; `api.robinhood.com`
  for overnight prices and which stocks trade overnight; and
  `raw.githubusercontent.com` for the newest version number, as the shell
  starts and then once a day; when no answer comes, again once Yahoo
  answers again, or a day later; never with `"updateCheck": false` in
  `~/.config/omarchy/grvc.stonks.json`. Nothing else.
- **Data:** Yahoo's endpoints are unofficial, and its terms restrict
  automated access; Robinhood's data is for personal use. Either may change
  or stop without notice. Some prices come late: [Yahoo's table](https://help.yahoo.com/kb/SLN2310.html)
  lists delays of up to 30 minutes for many exchanges and some indexes,
  London's and Tokyo's among them. Stonks isn't investment advice, and isn't
  affiliated with Yahoo or Robinhood.
- **Files it writes:** your lists and settings in
  `~/.config/omarchy/grvc.stonks.json`, the last quotes in
  `~/.cache/grvc.stonks/quotes.json`, and, while sounds are on, a replay's
  sound in `~/.cache/grvc.stonks/replay.wav`, written over at each replay of
  another chart, and beside it the chimes' notes, `chime-*.wav`, each also
  with its silence first, and the other sounds with theirs, `lead-*.wav`,
  written each run; and
  for each screenshot you take, one picture,
  `stonks-<symbol>-<date>_<time>.png`, in the folder Omarchy's own
  screenshots use: where Omasnap is installed, `OMASNAP_SCREENSHOT_DIR`,
  else `OMARCHY_SCREENSHOT_DIR`, else the `directory` in Omasnap's
  `[output]` settings, else `Screenshots` in your Pictures folder; without
  it, `OMARCHY_SCREENSHOT_DIR`, else your Pictures folder;
  saved straight there, with no copy anywhere else. Everything in
  `~/.cache/grvc.stonks` is readable by you alone (0600, the folder 0700),
  and so is the data file, from the moment Stonks makes it, and again
  after an older Stonks or an editor left it readable to others.
  The shell keeps the pill's form on its bar entry in
  `~/.config/omarchy/shell.json`.
- **Limits:** every request has a time limit and a size cap. Quotes come
  up to 20 listings to a request, so a long list refreshes in a few
  requests a minute, and overnight prices up to 25 for a whole day and 75
  for the last hour. Before a US session opens, from 04:00 New York, and
  for a listing's first price, Stonks asks for two days of prices in place
  of one, so the chart has the last session. Stonks fetches each
  listing only as often as its market can move, and leaves a site that
  refuses it alone for a while, as long as it asks up to half an hour. A
  window no screen shows, on another workspace or a screen switched off,
  fetches only what a closed one does.
- **Robinhood:** Stonks asks whether your US stocks and ETFs trade
  overnight, and for their overnight prices, both at once: for the stock on
  the pill once each time the shell starts, as its first price comes in; for
  the rest when the popup or window first opens, and for each one you add;
  and, while one is open, every 5 minutes through a night that trades;
  and when you press `r`, for the stock on the chart. It asks for the last
  hour of prices when it has prices from the last half hour, and for a
  whole day otherwise.
- **Updates:** never by itself. When a newer version is out, the footer
  says so for 5 seconds.

Every request runs through the one curl command in [`Fetch.js`](Fetch.js),
which sets its limits. [`test/boundaries.sh`](test/boundaries.sh) fails if a
command, a file read or write, or a request turns up outside the few files
allowed them. It runs on every push:

[![Checks](https://github.com/gmchande/omarchy-stonks/actions/workflows/fresh-clone.yml/badge.svg)](https://github.com/gmchande/omarchy-stonks/actions/workflows/fresh-clone.yml)

## Update

```sh
omarchy plugin update grvc.stonks
omarchy restart shell
```

Once a day, Stonks asks GitHub for the newest version. When it's newer than
yours, the footer says "Stonks … is out · click to update" for 5 seconds
as the popup or the window opens, once for each day's answer. A
click while it shows opens a terminal that runs `omarchy plugin update
grvc.stonks`, which shows what changes and asks before it updates. Until
the shell restarts, the old version keeps running, and the footer says
"Updated to … · click to restart the shell".

To stop the daily look, add `"updateCheck": false` to
`~/.config/omarchy/grvc.stonks.json`; Stonks then asks GitHub nothing, and
you update by the commands above. Take it out to look again.

## Remove

```sh
omarchy plugin remove grvc.stonks
```

That removes the plugin and its pill. Your lists, the saved quotes, and the
launcher files, if you added them, stay. Delete what you no longer want:

```sh
rm ~/.config/omarchy/grvc.stonks.json   # your lists; keep it to reinstall later
rm -r ~/.cache/grvc.stonks
rm -f ~/.local/share/applications/stonks.desktop ~/.local/share/icons/hicolor/scalable/apps/grvc.stonks.svg
```

If you added them, also delete the `{ "id": "grvc.stonks" }` entry in
`plugins` in `~/.config/omarchy/shell.json`, and the `o.bind` lines in
`~/.config/hypr/bindings.lua`.

## Contributing

How Stonks is built, how to run your checkout, the checks, and how to send a
change are in [CONTRIBUTING.md](CONTRIBUTING.md).

License: MIT, see [LICENSE](LICENSE). The sounds in `sounds/` and the ones
Stonks makes as it runs were made for Stonks, from code, and are MIT too.
