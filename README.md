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
- Two looks, smooth and retro, in your theme's colors, light or dark.
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
asks where in the bar to put `grvc.stonks`, which is Stonks' id. The center
is the default. To read the code first, leave out `--enable`, say no when
Omarchy offers to enable it, and run `omarchy plugin enable grvc.stonks`
when you're ready.

Stonks starts with five symbols so the pill has something to show: NVDA,
AAPL, MSFT, SPY, and TSLA. Add your own and remove any you don't follow.

## The pill

<img src="media/pill.png" width="200" alt="The pill's four forms: a sparkline, an arrow, the price as text, and the day's bear">

The pill shows today's move for the stock you last looked at, as a
sparkline, an arrow, the price as text, or the day's animal: the bull on an
up day, the bear on a down one. Middle-click it to change its form. On a
bar at the side of the screen it shows the animal, and a middle-click there
switches to the symbol over its change.

Scroll over it to step through your list, left-click for the popup,
right-click for the window, and drag it to move it along the bar.

## Reading the day

<img src="media/scrub.png" width="480" alt="The popup scrubbed back an hour and a half, to 10:15 in the morning: the price, the change, and the rows follow the pointer">

Hover the chart to scrub back through the day: the price, the change, and
the rows follow the pointer. Click the bull, or on a down day the bear, to
replay the chart.

Pick a range under the chart, from 1D to All. Every stock then shows that
range, even after a restart, while the rows stay on the day's move. To show
the change as a percent, an amount, or since the open, click the %, ±, or
bell at the end of the list's header, or on 1D the change beside the price.

Under the ranges, two lines show the low and the high with the price
between them: one marked with the range, such as 1D, and one marked 52W for
the past 52 weeks. Beside them are the volume, market cap, and P/E. The
top line says where the market is, in its own time, and a smaller line
under the price shows the pre-market, after-hours, or overnight price. An
old price says "As of" and its time. [The help](HELP.md#reading-the-day)
says what each figure means and when a price counts as old.

## Your lists

<img src="media/lists.png" width="480" alt="The list menu open over the rows: All with seven symbols, US with four, New list, and Manage lists">

Click the list's name to switch lists, start one, or manage them. All holds
every symbol you follow, and your own lists hold some of them. Ctrl-click a
row, or select it and press Ctrl+Enter, to choose the lists it's in.

Click "+ Add a symbol" and type a name or a symbol: Enter or a click adds
the top result. Search finds stocks, ETFs, indexes, and crypto.

To remove a row, point at it and click the × beside its symbol, or press
Delete: it goes from the list you're looking at, and removing it from All
removes it everywhere. For 5 seconds after, "Undo NVDA" shows beside
"+ Add a symbol" to bring it back, and `Ctrl+Z` does the same.

The line beside the list's name counts the rows up, in green, and down, in
red. Click the order word to sort by symbol, name, or change, and its arrow
to reverse the sort. [The help](HELP.md#your-lists) has more on removing,
undoing, and sorting.

## The window

<img src="media/window.png" width="720" alt="Stonks' window: the popup's chart and rows at the window's width">

Stonks also opens in a tiled window: the popup's chart and rows at the
window's width, with the same lists, range, and quotes. Right-click the
pill, or run `omarchy-shell grvc.stonks toggleWindow`.

For keys that open and close the popup and the window, add these lines to
`~/.config/hypr/bindings.lua`. Omarchy doesn't use either key by default:

```lua
o.bind("SUPER + ALT + T", "Stonks popup", "omarchy-shell shell toggle grvc.stonks")
o.bind("SUPER + SHIFT + T", "Stonks window", "omarchy-shell grvc.stonks toggleWindow")
```

[The help](HELP.md#the-window) says how to float the window, use it without
the pill, and add Stonks to the app launcher.

## Smooth or retro

<img src="media/retro.png" width="480" alt="The popup in retro: block digits and a chart of pixel columns">

Stonks opens in retro: the price in block digits and the charts in pixel
columns, the way Omarchy draws its logo. Click the small chart icon at the
top right to switch between smooth and retro.

<img src="media/light.png" width="480" alt="The popup in Catppuccin Latte, a light theme: Stonks' own green and red, for a light ground, on the theme's pale background">

Both looks draw in your theme's colors, light themes too: up in its green
and down in its red, or in Stonks' own pair where the theme's are missing,
too alike, or too faint.

## Sounds

Sounds start off. Click the speaker at the top right, or press `m`, to turn
them on, and again to turn them off; Stonks remembers. While they're on,
adding, removing, and undoing a row make a short sound, the chart plays
like chimes as you run the pointer along it, and a soft bell rings as the
market opens and closes. No refresh or price makes a sound.
[The help](HELP.md#sounds) lists every sound.

## Screenshots

Click the camera at the top right, or press `Ctrl+C`, for a picture of the
chart you're looking at, laid out to share. Your list is never in it. It
lands where Omarchy's own screenshots do: a file in your screenshots
folder, the picture on the clipboard, and a notification that opens it in
your screenshot editor. [The help](HELP.md#screenshots) says what's in it.

## Keys

`?` opens a sheet of every key, the same as this table:

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
| `Shift+↑` `Shift+↓` | Move the row in your own order |
| `o` | Change the order |
| `Shift+O` | Reverse the order |
| `w` | Open the list menu |
| `c` | Show the change as %, amount or since the open |
| `s` | Smooth or retro |
| `m` | Sound on or off |
| `r` | Refresh |
| `Shift+U` | Update Stonks when a newer one is out, then restart the shell |
| Tab or `Shift+Tab` | Next or previous panel on the bar (popup) |
| `?` | All keys |
| `Esc` | Close |

## If something's wrong

A "!" on the pill means its stock's quote is late or its last refresh
failed: point at the pill to read which. [The help](HELP.md#if-somethings-wrong)
explains each message Stonks shows, what to do about it, and how to report
a price that looks wrong.

## What it runs

- **Needs:** nothing beyond Omarchy 4.
- **Sites:** Yahoo Finance's unofficial endpoints for prices, charts, and
  search; Robinhood for overnight prices; GitHub once a day for the newest
  version number. No account, no API key, nothing else.
- **Files it writes:** your lists in `~/.config/omarchy/grvc.stonks.json`,
  the last quotes and sounds in `~/.cache/grvc.stonks` (or under
  `$XDG_CACHE_HOME`), and the screenshots
  you take.
- **Updates:** never by itself. When a newer version is out, the footer
  offers it.

Stonks isn't investment advice, and isn't affiliated with Yahoo or
Robinhood. [WHAT-IT-RUNS.md](WHAT-IT-RUNS.md) lists every command it runs,
every site it asks, and every file it writes.

## Update

```sh
omarchy plugin update grvc.stonks
omarchy restart shell
```

Or, when the footer says "Update to …", click it or press `Shift+U`: a
terminal runs the update, and a click on the footer then restarts the shell.
[The help](HELP.md#updates) says how to stop Stonks checking GitHub.

## Remove

```sh
omarchy plugin remove grvc.stonks
```

That removes the plugin and its pill. Your lists, the saved quotes, and the
launcher files, if you added them as [the help](HELP.md#the-window) says,
stay. Delete what you no longer want:

```sh
rm ~/.config/omarchy/grvc.stonks.json   # your lists; keep it to reinstall later
rm -r "${XDG_CACHE_HOME:-$HOME/.cache}/grvc.stonks"
rm -f ~/.local/share/applications/stonks.desktop ~/.local/share/icons/hicolor/scalable/apps/grvc.stonks.svg
```

If you added them, also delete the `{ "id": "grvc.stonks" }` entry in
`plugins` in `~/.config/omarchy/shell.json`, and the `o.bind` lines in
`~/.config/hypr/bindings.lua`.

## Contributing

How to run your checkout, its tests, and how to send a change are in
[CONTRIBUTING.md](CONTRIBUTING.md).

License: MIT, see [LICENSE](LICENSE). The sounds in `sounds/` and the ones
Stonks makes as it runs were made for Stonks, from code, and are MIT too.
