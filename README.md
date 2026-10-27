# Stonks

Stonks puts a stock watchlist in your Omarchy 4 bar. A small pill shows how
one stock is doing today. Click it for that stock's chart and your lists.

<img src="preview.png" alt="Stonks in the Omarchy bar. The pill shows Nebius (NBIS) up 2.88%, with its sparkline. Below it, the retro popup: Nebius Group at 163.31, the pixel bull, and the day's chart in pixel columns. Beside the popup, the bull, the STONKS wordmark, 'Stocks in your Omarchy bar.' and 'Free · No account · No API key'">

- A pixel bull on up days and a bear on down days. Both sleep while the
  market is closed.
- Pre-market and after-hours prices, and overnight prices for the US stocks
  and ETFs that trade overnight.
- A chart you can scrub: point anywhere on it to see the price at that
  moment.
- A screenshot sized so X shows it whole. It goes where Omarchy's own
  screenshots go, with Omarchy's notification and editor.
- Stonks fetches nothing while your screens are off, and fetches each stock
  only as often as its market moves. When Yahoo turns it away, it backs
  off.

And the basics:

- Stocks, ETFs, indexes, and crypto, from New York to London and Tokyo,
  charted over a day or all time.
- Prices as they arrive, never converted: each in its listing's own
  currency and its exchange's own time. An old price says "As of".
- Lists of your own, such as a portfolio or a sector.
- Retro by default, with block digits and pixel columns. Press `s` for
  smooth. Up is your theme's green and down is its red, on light themes
  too.
- Everything works from the keyboard. `?` lists the keys, Tab moves to the
  next panel on the bar, and Esc closes.
- No account and no API key.

Stonks doesn't track your holdings or send price alerts.

Website: [getstonks.app](https://getstonks.app)

[![Omarchy marketplace](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fgmchande%2Fstonks-site%2Fmarketplace-status%2Fmarketplace.json)](https://plugins.omarchy.org/plugin.html?id=grvc.stonks)
[![Last verified on the Omarchy marketplace](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fgmchande%2Fstonks-site%2Fmarketplace-status%2Fverified.json)](https://plugins.omarchy.org/plugin.html?id=grvc.stonks)

## Install

You need Omarchy 4.

```sh
omarchy plugin add https://github.com/gmchande/omarchy-stonks.git --enable
```

Omarchy warns that plugins run without a sandbox and asks you to confirm.
Then it asks where in the bar to put `grvc.stonks`, which is Stonks' id.
The center is the default.

To read the code before it runs, leave out `--enable` and say no when
Omarchy offers to enable it. When you're ready, run
`omarchy plugin enable grvc.stonks`.

Stonks starts with five symbols so the pill has something to show: NVDA,
AAPL, MSFT, SPY, and TSLA. Add your own and remove the ones you don't
follow.

## The pill

<img src="media/pill.png" width="200" alt="The pill four ways: a sparkline, an arrow, the price as text, and the day's bear">

The pill shows today's move for the stock you last looked at. It can show
it four ways: a sparkline, an arrow, the price as text, or the day's
animal, the bull or the bear. Middle-click the pill to switch. It keeps
your choice after a restart.

On a bar at the side of the screen, the pill shows the animal. Middle-click
it there to show the symbol over its change instead.

Scroll over the pill to step through your list. Click it for the popup,
right-click it for the window, and drag it to move it along the bar.

## Reading the day

<img src="media/scrub.png" width="480" alt="The popup scrubbed back an hour and a half, to 10:15 in the morning. The price, the change, and the rows show that moment">

Run the pointer along the chart to scrub back through the day. The price,
the change, and the rows follow it. Click the bull or the bear to replay
the chart.

Pick a range under the chart, from 1D to ALL. Every stock then shows that
range, even after a restart. The rows always show the day's move.

The rows can show the change as a percent, an amount, or the move since
the open. To switch, click the %, ±, or bell at the end of the list's
header. On 1D, the change beside the price switches it too.

Under the ranges, two lines place the price between a low and a high. The
first is for the range you picked, such as 1D. The second, marked 52W, is
for the past 52 weeks. Beside them are the volume, market cap, and P/E.

The top line names the moment in the market's day, such as Power hour or
After hours, and says when the market opens or closes, by the exchange's
own clock. A smaller line under the price shows the pre-market,
after-hours, or overnight price. An old price says "As of" and its time.
[The help](HELP.md#reading-the-day) explains each figure and when a price
counts as old.

## Your lists

<img src="media/lists.png" width="480" alt="The list menu open over the rows: All with seven symbols, US with four, New list, and Manage lists">

Click the list's name to switch lists, start a new one, or manage them. All
holds every symbol you follow. Your own lists each hold some of them. To
choose which lists a row is in, Ctrl-click it, or select it and press
Ctrl+Enter.

To add a stock, click "+ Add a symbol" and type a name or a symbol. Press
Enter to add the top result, or click the one you want. Search finds
stocks, ETFs, indexes, and crypto.

To remove a row, point at it and click the × beside its symbol, or select
it and press Delete. It leaves the list you're looking at. Removing it from
All removes it from every list. For 5 seconds, a button such as "Undo NVDA"
shows beside "+ Add a symbol". Click it to bring the row back. `Ctrl+Z`
does the same.

The line beside the list's name shows how many rows are up, in green, and
down, in red. Point at it for the counts. Click the order word to sort by
symbol, name, or change, or to go back to your own order. Click its arrow
to reverse the sort. [The help](HELP.md#your-lists) says more about
removing, undoing, and sorting.

## The window

<img src="media/window.png" width="720" alt="Stonks' window: the popup's chart and rows, at the window's width">

Stonks also opens as a tiled window. It shows the popup's chart and rows at
the window's width, with the same lists, range, and prices. Right-click the
pill to open it, or run `omarchy-shell grvc.stonks toggleWindow`.

To open and close the popup and the window from the keyboard, add these
lines to `~/.config/hypr/bindings.lua`. Omarchy doesn't use either key by
default:

```lua
o.bind("SUPER + ALT + T", "Stonks popup", "omarchy-shell shell toggle grvc.stonks")
o.bind("SUPER + SHIFT + T", "Stonks window", "omarchy-shell grvc.stonks toggleWindow")
```

[The help](HELP.md#the-window) says how to float the window, use it without
the pill, and add Stonks to the app launcher.

## Smooth or retro

<img src="media/retro.png" width="480" alt="The popup in retro: block digits and a chart of pixel columns">

Retro draws the price in block digits and the chart in pixel columns, the
way Omarchy draws its logo. Smooth uses plain digits and a line chart. To
switch, click the small chart icon at the top right, or press `s`.

<img src="media/light.png" width="480" alt="The popup on Catppuccin Latte, a light theme, in Stonks' own green and red, made for a light background">

Both looks use your theme's colors, on light themes too: up in its green,
down in its red. Where the theme's pair is missing, too alike, or too
faint, Stonks uses its own.

## Sounds

Sounds start off. To turn them on or off, click the speaker at the top
right, or press `m`. Stonks remembers your choice.

With sounds on, adding, removing, or undoing a row makes a short sound. The
chart rings like chimes as you run the pointer along it. A soft bell rings
when the market opens and when it closes. Refreshes and prices make no
sound. [The help](HELP.md#sounds) lists every sound.

## Screenshots

Click the camera at the top right, or press `Ctrl+C`, for a picture of the
chart you're looking at, laid out to share. Your list is never in it.

Stonks handles it the way Omarchy handles its own screenshots. It saves a
file to your screenshots folder, copies the picture to the clipboard, and
shows a notification. Click the notification to open the picture in your
screenshot editor. [The help](HELP.md#screenshots) says what the picture
shows.

## Keys

`?` lists the same keys as this table:

| Key | Does |
| --- | --- |
| `↑` `↓` | Move the selection |
| `⏎` | Show the selected row's chart |
| `Ctrl+⏎` | Choose the selected row's lists |
| `←` `→` | Scrub the chart one step |
| `[` `]` | Change the range |
| `p` | Replay the chart |
| `Ctrl+C` | Take a screenshot |
| `a` | Add a symbol |
| Delete or Backspace | Remove the selected row |
| `Ctrl+Z` | Undo a removal |
| `Shift+↑` `Shift+↓` | Move the selected row, in your own order |
| `o` | Change the order |
| `Shift+O` | Reverse the order |
| `w` | Open the list menu |
| `c` | Show the change as a percent, an amount, or since the open |
| `s` | Switch between smooth and retro |
| `m` | Turn sounds on or off |
| `r` | Refresh |
| `Shift+U` | Update Stonks when a new version is out, then restart the shell |
| Tab or `Shift+Tab` | Next or previous panel on the bar (popup) |
| `?` | Show every key |
| `Esc` | Close |

## If something's wrong

A "!" on the pill means its stock's last refresh failed or is late. Point
at the pill to see which.
[The help](HELP.md#if-somethings-wrong) explains each message Stonks shows,
what to do about it, and how to report a price that looks wrong.

## What it runs

- **Needs:** nothing beyond Omarchy 4.
- **Sites:** Yahoo Finance's unofficial endpoints for prices, charts, and
  search. Robinhood for overnight prices. GitHub, once a day, for the
  newest version number. No account, no API key, nothing else.
- **Files it writes:** your lists in `~/.config/omarchy/grvc.stonks.json`;
  the last prices and the sounds in `~/.cache/grvc.stonks`, or under
  `$XDG_CACHE_HOME` when it's set; and the screenshots you take.
- **Updates:** never by itself. When a new version is out, the footer
  offers it.

Stonks isn't investment advice, and isn't affiliated with Yahoo or
Robinhood. [WHAT-IT-RUNS.md](WHAT-IT-RUNS.md) lists every command it runs,
every site it asks, and every file it writes.

## Update

```sh
omarchy plugin update grvc.stonks
omarchy restart shell
```

Or, when the footer says "Update to …", click it or press `Shift+U`. A
terminal opens and runs the update. Then click the footer again to restart
the shell. [The help](HELP.md#updates) says how to stop Stonks checking
GitHub.

## Remove

```sh
omarchy plugin remove grvc.stonks
```

That removes the plugin and its pill. It leaves your lists, the saved
prices, and the launcher files, if you added them as
[the help](HELP.md#the-window) says. Delete what you don't want:

```sh
rm ~/.config/omarchy/grvc.stonks.json   # your lists; keep it to reinstall later
rm -r "${XDG_CACHE_HOME:-$HOME/.cache}/grvc.stonks"
rm -f ~/.local/share/applications/stonks.desktop ~/.local/share/icons/hicolor/scalable/apps/grvc.stonks.svg
```

If you added them, also delete the `{ "id": "grvc.stonks" }` entry from
`plugins` in `~/.config/omarchy/shell.json`, and the `o.bind` lines from
`~/.config/hypr/bindings.lua`.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) says how to run your own copy, test it,
and send a change.

License: MIT, see [LICENSE](LICENSE). The sounds in `sounds/`, and the ones
Stonks makes as it runs, were made from code for Stonks. They're MIT too.
