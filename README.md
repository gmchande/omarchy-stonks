# Stonks

A stock watchlist plugin for the Omarchy 4 shell: today's move in your bar,
and a chart you can scrub a click away.

<img src="preview.png" alt="Stonks in the Omarchy bar: the pill shows Apple's symbol, sparkline, and change, and under it two popups side by side, each showing Apple's price, the day's chart, the range buttons, the day's and 52-week figures, and the first rows of the list. On the left, smooth, scrubbed back to 10:15 when the day was up, with the bull; on the right, retro, on the latest price of a down day, with the bear">

- Today's move in your bar; scroll over it to step through your stocks.
- Click for the day's chart and scrub it with the pointer, or pick a range
  from a week to all time.
- Pre-market, after-hours, and overnight prices, and when the market opens
  or closes.
- Stocks, ETFs, indexes, and crypto, from New York to London and Tokyo, each
  in its own currency.
- Lists of your own, such as a portfolio or a sector.
- Drawn in your theme's colours, with Stonks' own green and red where the
  theme's are missing, too alike, or too faint.
- No account and no API key.

It doesn't track holdings, send price alerts, or convert currencies.

## Install

Needs Omarchy 4.

```sh
omarchy plugin add https://github.com/gmchande/omarchy-stonks.git --enable
```

Omarchy warns that plugins run unsandboxed and asks you to confirm the
clone, then asks which bar section gets `grvc.stonks` (Stonks' id); the
centre is the default. To read the code first, leave out `--enable`, say no
when asked to enable it, and run `omarchy plugin enable grvc.stonks` when
you're ready.

## The pill

<img src="media/pill.png" width="200" alt="The pill's four forms: a sparkline, an arrow, the price as text, and Stonks' mark">

The pill shows today's move for the stock you last looked at, in one of four
forms: a sparkline, an arrow, the price as text, or Stonks' mark, a little
chart that climbs on an up day and falls on a down one. Middle-click it to
change its form. On a bar at the side of the screen it shows the mark, and
a middle-click there switches to the symbol over its change.

Scroll over it to step through your list, left-click for the popup,
right-click for the window, and drag it to move it along the bar.

## Reading the day

<img src="media/scrub.png" width="480" alt="The popup scrubbed back an hour and a half, to 10:15 in the morning: the price, the change, and the rows follow the pointer">

Hover the chart to scrub back through the day: the price, the change, and
the rows follow the pointer. Click the bull, or on a down day the bear, to
replay the chart.

Pick a range under the chart, from 1D to All: every stock keeps it, even
after a restart, while the rows stay on today. On 1D, click the change
beside the price to see it as a percent, an amount, or since the open.

Under the ranges, two lines place the price between its low and high: for
the day or the range, and for the past 52 weeks. Beside them are the open
and volume, or a range's low and high dates, then the market cap and P/E.
The market cap is an estimate: Yahoo's last reported figure, moved with the
price since.

The top line says where the market is, in its own time: counting down to
the open or the close, after hours, or closed. A smaller line under the
price shows the pre-market, after-hours, or overnight price. The overnight
price is for the US stocks and ETFs Robinhood trades overnight.

An old price says "As of" and its time, on its row and above the price.
Old means more than two minutes behind while its market trades, or saved
from the last session. A refresh that fails, or gets no answer in 90
seconds, says so there and puts a "!" on the pill.

## Your lists

<img src="media/lists.png" width="480" alt="The list menu open over the rows: All with seven symbols, US with four, New list, and Manage lists">

Click the list's name to switch lists, start one, or manage them. All holds
every symbol you follow, and your own lists hold some of them: Ctrl-click a
row to tick the lists it's in. Removing a symbol from All removes it
everywhere.

Click "+ Add a symbol" and type a name or a symbol: the top result shows in
the chart, and Enter or a click adds it. Search lists stocks, ETFs,
indexes, and crypto.

To remove a row, right-click it, or point at it and click the × beside its
symbol. A click on the note that then shows in the footer puts it back.

The line beside the list's name shows how many rows are up, in green, and
down, in red. Click the order word to sort by symbol, name, or change;
click its arrow to reverse the sort.

## The window

<img src="media/window.png" width="720" alt="Stonks' window: the popup's chart and rows at the window's width">

Stonks also opens in a tiled window: the popup's chart and rows at the
window's width. Right-click the pill, or run
`omarchy-shell grvc.stonks openWindow '{}'`, to open it. It shares the
popup's lists, range, and quotes. To float it, match
class `org.quickshell` and title `Stonks` in a window rule.

The window also works with no pill. Run
`omarchy plugin disable grvc.stonks`, then add `{ "id": "grvc.stonks" }` to
`plugins` in `~/.config/omarchy/shell.json` to keep the plugin loaded. To
bring the pill back, remove that entry first, then run
`omarchy plugin enable grvc.stonks center`.

For a key that opens and closes the window, add this line to
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + T", "Stonks", "omarchy-shell grvc.stonks toggleWindow")
```

For Stonks in the app launcher, which `omarchy plugin add` doesn't set up:

```sh
cp ~/.config/omarchy/plugins/grvc.stonks/share/stonks.desktop ~/.local/share/applications/
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
cp ~/.config/omarchy/plugins/grvc.stonks/share/grvc.stonks.svg ~/.local/share/icons/hicolor/scalable/apps/
```

## Smooth or retro

<img src="media/retro.png" width="480" alt="The popup in retro: block digits and a chart of pixel columns">

Retro draws the price in block digits and the charts in pixel columns, the
way Omarchy draws its logo. Click the small chart icon at the top right to
switch between smooth and retro.

<img src="media/light.png" width="480" alt="The popup in Catppuccin Latte, a light theme: Stonks' own green and red, for a light ground, on the theme's pale background">

Both looks draw in your theme's colours, light themes too: up in its green
and down in its red, or in Stonks' own pair where the theme's are missing,
too alike, or too faint.

## Keys

`?` opens a sheet of the everyday keys. Every key is in this table:

| Key | Does |
| --- | --- |
| `↑` `↓` | Move the selection |
| `j` `k` | Move the selection (popup) |
| `⏎` | Show the selected row's chart |
| Space | Show the selected row's chart (popup) |
| `←` `→` | Scrub one chart step |
| `h` `l` | Scrub one chart step (popup) |
| `[` `]` | Change the chart range |
| `p` | Replay the chart |
| `a` or `+` | Search and add a symbol |
| `x` | Remove the selected row |
| `u` | Undo the last removal, until a list next changes |
| Delete or Backspace | Remove the selected row (window) |
| `Shift+J` `Shift+K` | Move the selected row up or down, in manual order |
| `o` | Change the list's order |
| `Shift+O` | Reverse a sorted order |
| `w` | Open the list menu |
| `Shift+W` | Manage lists: rename, reorder, delete |
| `m` | Tick the selected row's lists |
| `,` `.` | Previous or next list |
| `c` | Show the day's change as a percent, an amount, or since the open |
| `s` | Switch between smooth and retro |
| `r` | Refresh |
| `1` to `9` | Show that row's chart |
| Tab or `Shift+Tab` | Next or previous panel on the bar (popup) |
| `?` | Open the key sheet |
| `Esc` | Close the sheet, then the scrub, then the popup or window |

## If something's wrong

A "!" on the pill means its stock's quote is late or its last refresh
failed: point at the pill to read which. The row and the line above the
price say the same.

- **A row says "No data" or "Update overdue".** Stonks has waited 90
  seconds on Yahoo: no answer came, or Yahoo turned it away. A row with a
  price keeps it, with the time it's from. Check your connection; if other
  sites load, Yahoo is down or refusing, and there's nothing to do but wait.
  Stonks keeps asking by itself, less often the longer Yahoo stays away,
  and `r` won't hurry it.
- **A row says "No data for this symbol" or "Refresh failed".** Yahoo said
  it has nothing for the symbol, or sent a broken answer three times
  running. A row with a price keeps it, with the time it's from, and `r`
  asks again. A symbol Yahoo has dropped, after a merger, a rename, or a
  delisting, stays this way: search for the company to find what Yahoo
  calls it now. If every row says it, the fault is Yahoo's: Stonks asks
  again at each refresh, and if Yahoo has changed what it answers, only a
  newer Stonks can fix that.
- **A stock or index says "As of" while its market is open.** Yahoo sends
  many exchanges' prices late, and some indexes'. When we measured,
  London's, São Paulo's, and the Cboe's VIX came 15 minutes late and
  Mexico's 20; Nasdaq's, NYSE's, Toronto's, and crypto came within a
  minute. For any other exchange, Tokyo's among them, see [Yahoo's table of delays](https://help.yahoo.com/kb/SLN2310.html).
  Stonks gives the time of any price more than two minutes old while its
  market trades. A thin stock can say it too: its last trade was that long
  ago. The overnight price names its own time, usually 10 to 15 minutes
  back, since Robinhood's prints arrive late, and dims once it's 20
  minutes old.
- **A price looks wrong.** Each price is in its listing's currency, never
  converted, and a price marked GBp is in pence, as Yahoo quotes many
  London listings: 3,580.00 is £35.80. The large price is the regular
  session's; pre-market, after-hours, and overnight trades are the smaller
  line under it, which some apps show as the main price. The change is
  from the previous close, unless you've clicked it to since the open; on
  a longer range, it's from the range's start. Stonks shows Yahoo's prices
  as sent, but for the stray prints Yahoo sometimes drops into a chart,
  which it leaves out.
- **The day's chart says "No trades charted" or "Traded only at" a time.**
  The listing traded too little that day to draw a line.
- **The header says "1W unavailable", with RETRY beside it.** Yahoo didn't
  send that range's chart. Click RETRY, or press `r`. While Yahoo is
  turning Stonks away, a range fails at once.
- **Search says "Search didn't answer".** Yahoo's search didn't answer, or
  Stonks is waiting out a refusal from Yahoo. Try again in a moment.
- **The header says "schedule unavailable".** Stonks carries each
  exchange's holidays through a set date, and this exchange's have run
  out, so it can't say when the market next opens. Stonks doesn't update
  itself: [update it](#update) for a renewed calendar.
- **The footer says "Can't read grvc.stonks.json".** The file holding your
  lists can't be opened or isn't valid JSON, often after a hand edit.
  Stonks keeps the lists it has and writes nothing over the file until it
  reads again. Fix the file, and Stonks reads it as you save; or remove it
  to start over from the starter list.

To report a price or chart that looks wrong, or anything this doesn't
answer, use the [bug form](https://github.com/gmchande/omarchy-stonks/issues/new?template=bug.yml).
For a price, give the symbol, the range, and the time (scrub the chart to
it), what Stonks showed, and what your broker or the exchange showed then.
The shell's log the form asks for can name prints Stonks left out.

## What it runs

- **Needs:** nothing beyond Omarchy 4. It runs `curl`, which Omarchy ships.
- **Commands:** `curl` for every request, and `omarchy restart shell` only
  when you click the update notice.
- **Hosts:** `query1.finance.yahoo.com` for quotes, charts, and the market
  cap and P/E; `query2.finance.yahoo.com` for search; and `api.robinhood.com`
  for overnight prices and which stocks trade overnight. Nothing else.
- **Data:** Yahoo's endpoints are unofficial, and its terms restrict
  automated access; Robinhood's data is for personal use. Either may change
  or stop without notice. Some prices come late: Yahoo delays many
  exchanges' quotes and some indexes', London's and Tokyo's among them, by
  up to 30 minutes in [its table](https://help.yahoo.com/kb/SLN2310.html).
  Stonks isn't investment advice, and isn't affiliated with Yahoo or
  Robinhood.
- **Files it writes:** your lists and settings in
  `~/.config/omarchy/grvc.stonks.json`, and the last quotes in
  `~/.cache/grvc.stonks/quotes.json`. The shell keeps the pill's form on its
  bar entry in `~/.config/omarchy/shell.json`.
- **Limits:** every request has a time limit and a size cap. Quotes come
  up to 20 listings to a request, so a long list refreshes in a few
  requests a minute. Each listing is asked for only as often as its market
  can move, and a host that refuses is left alone for a while.
- **Updates:** never by itself.

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

Until the shell restarts, it runs the old version, and the popup says
"Updated to … · click to restart the shell".

## Remove

```sh
omarchy plugin remove grvc.stonks
```

That removes the plugin and its pill, and leaves the rest. Delete what you
no longer want:

```sh
rm ~/.config/omarchy/grvc.stonks.json   # your lists; keep it to reinstall later
rm -r ~/.cache/grvc.stonks
rm -f ~/.local/share/applications/stonks.desktop ~/.local/share/icons/hicolor/scalable/apps/grvc.stonks.svg
```

If you added them, also delete the `{ "id": "grvc.stonks" }` entry in
`plugins` in `~/.config/omarchy/shell.json`, and the `o.bind` line in
`~/.config/hypr/bindings.lua`.

## Contributing

How Stonks is built, how to run your checkout, the checks, and how to send a
change are in [CONTRIBUTING.md](CONTRIBUTING.md).

License: MIT, see [LICENSE](LICENSE).
