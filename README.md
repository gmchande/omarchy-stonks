# Stonks

Stonks puts your stock watchlist in the Omarchy 4 bar. A small pill shows
how one stock is doing today. Click it for the chart and your lists.

<img src="preview.png" alt="Stonks in the Omarchy bar. The pill shows Nebius (NBIS) up 2.88%. Below it, the popup shows Nebius Group at 163.31 over the day's chart in pixel columns. Beside it: 'Stocks in your Omarchy bar. Free · No account · No API key'">

- Stocks, ETFs, indexes, and crypto from New York to London and Tokyo,
  with charts from one day to all time.
- Pre-market and after-hours prices, and overnight prices for the US
  stocks and ETFs that trade overnight.
- Point anywhere on the chart to see the price at that moment.
- Prices as Yahoo and Robinhood send them, in each listing's own currency
  and its exchange's own time. Prices aren't converted.
- Lists of your own, such as a portfolio or a sector.
- A screenshot of any chart, sized so X shows it whole.
- Everything works by mouse alone or by keyboard alone.
- Light on your computer: Stonks fetches nothing while your screens are
  off, and fetches each stock only as often as its market moves.
- Free, with no account and no API key.

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
The center is the default. To read the code before it runs, leave out
`--enable` and say no when Omarchy offers to enable it. Run
`omarchy plugin enable grvc.stonks` when you're ready.

Stonks starts with five symbols so the pill has something to show: NVDA,
AAPL, MSFT, SPY, and TSLA. Add your own and remove the ones you don't
follow.

## The pill

<img src="media/pill.png" width="200" alt="The pill four ways: a sparkline, an arrow, the price as text, and an icon for the day">

The pill shows today's move for the stock you last looked at. It can show
a sparkline, an arrow, the price as text, or an icon: a bull on an up day,
a bear on a down one. Middle-click it to switch. It keeps your choice after
a restart. On a bar at the side of the screen, middle-click switches
between the icon and the symbol over its change.

Scroll over the pill to step through your list. Click it for the popup,
right-click it for the window, and drag it to move it along the bar.

## Reading the day

<img src="media/scrub.png" width="480" alt="The popup scrubbed back an hour and a half, to 10:15 in the morning. The price, the change, and the rows show that moment">

Run the pointer along the chart to go back through the day. The price, the
change, and the rows follow it. Click the icon at the top left to replay
the chart.

Pick a range under the chart, from 1D to ALL. Every stock then shows that
range, even after a restart. The rows always show the day.

Rows show the day's change as a percent or an amount, or the percent change
since the open. To switch, click the %, ±, or bell at the end of the list's
header.

Under the ranges, the first line shows the range's low and high, with the
price between them. Beside it are the open and the volume on 1D, or the
range's starting price and volume on a longer range. The second line shows
the 52-week low and high, with the market cap and P/E. Stonks estimates
the market cap from Yahoo's last reported figure, moved with the price
since. When
a company reports earnings in another currency, Stonks converts them at
Yahoo's rate for the day, inside the P/E and nowhere else.

The top line names the moment in the market's day, such as Power hour, and
says when the market opens or closes, by the exchange's clock. A US stock
that has traded since the close shows that newest price on top, its move
since the close, and its session and time, such as OVERNIGHT 23:25; the
line under it shows the close and the day's move. On a longer range the
chart ends on that price, and the move is the range's, up to it.
Elsewhere, a smaller line under the price shows the pre-market or
after-hours price.
The 1D chart shows one trading day, from the first hour the stock can trade
that day to the last. Over the weekend it shows Friday until Sunday night's
trading begins. A night stays on the chart it began on until 04:00, New
York time. A coin never closes, so its chart, its change, and its low and
high cover the last 24 hours.

A price says "As of" and its time when it's old: more than two minutes
behind while its market trades, or saved from before and not yet
refreshed.

## Your lists

<img src="media/lists.png" width="480" alt="The list menu open over the rows: All with seven symbols, US with four, New list, and Manage lists">

Click the list's name to switch lists, start a new one, or manage them. All
holds every symbol you follow, and your own lists each hold some of them.
To choose which lists a row is in, Ctrl-click it, or select it and press
Ctrl+Enter.

To add a stock, click "+ Add a symbol" and type a name or a symbol. The
chart shows the highlighted result before you add it. Press Enter to add
it, or click any result to add that one.

To remove a row, point at it and click the × beside its symbol, or select
it and press Delete. It leaves the list you're looking at. Removing it from
All removes it from every list, and asks first if one of your lists holds
it. Right-click a row to choose which lists it leaves. For 5 seconds, a
button such as "Undo NVDA" shows beside "+ Add a symbol". `Ctrl+Z` also
undoes it, until you change a list again.

The line beside the list's name shows how many rows are up, in green, and
down, in red. Point at it for the counts. Click the order at the right of
the header, such as MANUAL, to sort by symbol, name, or change, or to go
back to your own order. Click its arrow to reverse the sort. Sorting by
change ranks rows by percent, even while they show amounts, since amounts
in different currencies can't be compared.

## The window

<img src="media/window.png" width="720" alt="Stonks' window: the popup's chart and rows, at the window's width">

Stonks also opens as a tiled window, with the popup's chart and rows at
the window's width. Right-click the pill, or run
`omarchy-shell grvc.stonks toggleWindow`. To float it, add a window rule
that matches class `org.quickshell` and title `Stonks`.

To open the popup and the window from the keyboard, add these lines to
`~/.config/hypr/bindings.lua`. Omarchy doesn't use either key by default:

```lua
o.bind("SUPER + ALT + T", "Stonks popup", "omarchy-shell shell toggle grvc.stonks")
o.bind("SUPER + SHIFT + T", "Stonks window", "omarchy-shell grvc.stonks toggleWindow")
```

To use the window without the pill, run `omarchy plugin disable grvc.stonks`,
then add `{ "id": "grvc.stonks" }` to `plugins` in
`~/.config/omarchy/shell.json` to keep Stonks loaded. To bring the pill
back, remove that entry, then run `omarchy plugin enable grvc.stonks center`.

To add Stonks to the app launcher:

```sh
cp ~/.config/omarchy/plugins/grvc.stonks/share/stonks.desktop ~/.local/share/applications/
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
cp ~/.config/omarchy/plugins/grvc.stonks/share/grvc.stonks.svg ~/.local/share/icons/hicolor/scalable/apps/
```

## Smooth or retro

<img src="media/retro.png" width="480" alt="The popup in retro: block digits and a chart of pixel columns">

Retro draws the price in block digits and the chart in pixel columns, the
way Omarchy draws its logo. Smooth uses plain digits and a line chart. To
switch, press `s`, or click the small chart icon at the top right.

<img src="media/light.png" width="480" alt="The popup on Catppuccin Latte, a light theme, in Stonks' own green and red, made for a light background">

Both use your theme's green for up and its red for down, on light themes
too. Where a theme's pair is missing, too alike, or too faint, Stonks uses
its own.

## Sounds

Sounds are off until you turn them on. Press `m`, or click the speaker at
the top right. With sounds on, adding, removing, or undoing a row makes a
short sound, and the chart chimes as you run the pointer along it. A soft
bell rings as the market of the stock you last looked at opens and closes,
but never while an app is recording from your microphone. Refreshes and
prices make no sound.

## Screenshots

Press `Ctrl+C`, or click the camera at the top right, for a picture of the
chart, sized so X shows it whole. It shows the price, its move, the
exchange, and the time with its zone. If you've scrubbed the chart, it
shows that moment. Your list is never in it.

Stonks treats it like Omarchy's own screenshots. It saves the picture to
your screenshots folder, copies it to the clipboard, and shows a
notification. Click the notification to open the picture in your
screenshot editor.

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
| `c` | Show the day's change as a percent or an amount, or since the open |
| `s` | Switch between smooth and retro |
| `m` | Turn sounds on or off |
| `r` | Refresh |
| `Shift+U` | Update Stonks when a new version is out, and restart the shell to run it |
| Tab or `Shift+Tab` | Next or previous panel on the bar (popup) |
| `?` | Show every key |
| `Esc` | Close |

## If something's wrong

A "!" on the pill means a refresh of its stock failed or is late. Point at
the pill to see which.

<details>
<summary>What each message means, and what to do</summary>

- **"Can't get prices" in the header, or "No data" or "Update overdue" on
  a row.** Yahoo hasn't sent a price Stonks can use in time, or has
  turned Stonks away. Rows keep any price they had, with its time. Check your connection.
  Stonks keeps trying on its own, less often the longer Yahoo stays away.
  `r` asks again at once, unless Yahoo is turning Stonks away. If Yahoo
  has changed what it sends, only a newer Stonks can fix it.
- **"No data for this symbol" or "Refresh failed" on a row.** Yahoo has
  nothing for the symbol, or sent a broken answer three times in a row.
  Press `r` to try again. After a merger or a rename, search for the
  company to find what Yahoo calls it now. A delisted company may be gone
  for good.
- **"As of" while the market is open.** Yahoo sends some prices late. When
  we measured, London, São Paulo, and the VIX came 15 minutes late, and
  Mexico 20. Nasdaq, NYSE, Toronto, and crypto came within a minute.
  [Yahoo's table](https://help.yahoo.com/kb/SLN2310.html) lists the rest.
  A thinly traded stock says "As of" when its last trade was more than two
  minutes ago. Overnight prices usually run 10 to 15 minutes behind, since
  Robinhood reports those trades late.
- **A price looks wrong.** Check the currency: Stonks never converts.
  PENCE means pence, as Yahoo quotes many London listings, so 3,580.00 is
  £35.80. A US stock's large price is its newest trade, after the close
  too, with the close on the line under it. Elsewhere the large price is
  the regular session's, and the smaller line shows trades outside it.
  The change is from the previous close, unless you've switched it to
  since the open. On a longer range, it's from the range's start. Stonks
  leaves out prices of zero or less, and stray points in Yahoo's charts.
- **"No trades charted" or "Traded only at" a time.** The listing traded
  too little that day to draw a line.
- **"1W unavailable" or "Search didn't answer", with RETRY.** Yahoo didn't
  send that chart or those results. Click RETRY.
- **"schedule unavailable".** Stonks' calendar for this exchange has run
  out, so it can't say when the market next opens. Prices and
  times are still right. [Update Stonks](#update) for a new calendar.
- **"Couldn't load your lists" in the footer.** Your lists file,
  `~/.config/omarchy/grvc.stonks.json`, can't be read or isn't valid JSON,
  often after a hand edit. Stonks won't write over it. Changes you make
  meanwhile are lost when Stonks reads the file again or the shell
  restarts. Fix the file and save it, and Stonks reads it at once. Or
  remove it to start over.
- **"Your changes aren't saved" in the footer.** Stonks can't write your
  lists file, because the disk is full or the file or its folder is
  read-only. A restart loses every change since the last save. Free some
  space or fix the permissions, then click the footer.

To report a wrong price or anything else, use the
[bug form](https://github.com/gmchande/omarchy-stonks/issues/new?template=bug.yml).
For a price, give the symbol, the range, and the time, what Stonks showed,
and what your broker or the exchange showed then.

</details>

## What it runs

Stonks isn't investment advice, and isn't affiliated with Yahoo or
Robinhood. Yahoo's endpoints are unofficial, and Robinhood's data is for
personal use, so either may change or stop without notice.

<details>
<summary>The commands it runs, the sites it asks, and the files it writes</summary>

**Commands**, all of which Omarchy ships:

- `curl` for every request, with a time limit and a size cap.
- `sh`, `mkdir`, `chmod`, `mktemp`, `ln`, and `rm`, to make its files and
  keep them readable only by you.
- `timeout`, to stop its file, sound, and screenshot commands if they
  hang.
- With sounds on: `pw-play` for each sound; `pw-cat` playing silence while
  you move along the chart, so each chime plays at once; `pw-dump`, in
  `bash`, as the bell is due, to check that no app is recording; and `sh`
  with `md5sum` and `head`, once a run, to check its saved sounds.
- For a screenshot: `sh` with `sed`, `tail`, `date`, and `head` to find
  your screenshots folder and name the file, `wl-copy` for the clipboard,
  and `omarchy-notification-send`.
- Only when you ask for an update: `omarchy plugin update grvc.stonks` in
  a terminal, then `omarchy restart shell` when `git` shows the update
  moved Stonks' folder.

**Sites**, and nothing else:

- `query1.finance.yahoo.com` for prices, charts, the market cap and P/E,
  and the currency rate a P/E needs. With only the pill on screen, Stonks
  asks for the pill's stock alone: every minute while its market trades,
  every 5 minutes before and after the session, and every 15 minutes while
  it's closed. As the shell starts, it asks once for every row. When you
  open the panel or the window, it asks for the stock at the top, then the
  rows you can see, then the rest of the list, and keeps them fresh while
  it's open: every minute while a row's market trades, and every 5 minutes
  before and after the session (every minute for the stock on show). It
  leaves out a row whose market hasn't traded since its last price.
- `query2.finance.yahoo.com` for search, as you type.
- `api.robinhood.com` for overnight prices: once a day for which stocks
  trade overnight, once for the pill's stock as the shell starts, and
  every 5 minutes through the night for the pill's stock, and for every
  row that trades overnight while the popup or the window is open.
- `raw.githubusercontent.com` for the newest version number, as the shell
  starts and once a day. To turn this off, add `"updateCheck": false` to
  `~/.config/omarchy/grvc.stonks.json`.

Stonks asks for nothing while every screen is off. When a site turns it
away, it waits as long as the site asks, up to half an hour.

**Files:**

- `~/.config/omarchy/grvc.stonks.json`: your lists and settings.
- `~/.cache/grvc.stonks`, or `$XDG_CACHE_HOME/grvc.stonks` when that's
  set: the last prices, and the sounds Stonks makes for itself.
- Each screenshot, as `stonks-<symbol>-<date>_<time>.png` in the folder
  Omarchy's own screenshots use.

Only you can read the cache folder. Stonks makes your lists file readable
only by you when it creates or saves it.
[`test/boundaries.sh`](test/boundaries.sh) fails if any code outside a
few allowed files runs a command, reads or writes a file, or makes a
request.

</details>

## Update

```sh
omarchy plugin update grvc.stonks
omarchy restart shell
```

Or, when the footer says "Update to …", click it or press `Shift+U`. A
terminal opens and shows what changes. Say yes, and it updates Stonks and
restarts the shell, unless Stonks has changes it hasn't saved. Then, or
after an update run anywhere else, the footer says "Updated to … · click to
restart the shell". Stonks never updates itself.

## Remove

```sh
omarchy plugin remove grvc.stonks
```

That removes the plugin and its pill, but leaves your lists, the saved
prices, and the launcher files if you added them. Delete what you don't
want:

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
