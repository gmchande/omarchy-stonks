# Stonks

Stonks puts your stock watchlist in the Omarchy bar. A small pill shows how
one stock is doing today. Click it for the chart and your lists.

<img src="preview.png" alt="Stonks in the Omarchy bar. The pill shows Nebius (NBIS) up 2.88%. Below it, the panel shows Nebius Group at 163.31 over the day's chart in pixel columns. Beside it: 'Stocks in your Omarchy bar. Free · No account · No API key'">

- Stocks, ETFs, indexes and crypto from New York to London and Tokyo,
  with charts from one day to all time.
- Pre-market and after-hours prices, and overnight prices for the US
  stocks and ETFs that trade at night.
- Point anywhere on the chart to see the price at that moment.
- Prices as Yahoo and Robinhood send them, in each listing's own currency
  and its exchange's own time, never converted.
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

Stonks is made for Omarchy 4.5. On earlier Omarchy 4 releases, back to
4.0.6, it runs without what 4.5 added: moving at the shell's own pace,
keeping still when you turn animations off, pressing in like the bar's
icons, and saving screenshots where Omasnap saves yours.

```sh
omarchy plugin add https://github.com/gmchande/omarchy-stonks.git --enable
```

Omarchy warns that plugins run without a sandbox and asks you to confirm,
then asks where in the bar to put `grvc.stonks`, Stonks' id. The center is
the default. To read the code before it runs, leave out `--enable`, say no
when Omarchy offers to enable it, and run `omarchy plugin enable
grvc.stonks` when you're ready.

Stonks starts with NVDA, AAPL, MSFT, SPY and TSLA, so the pill has
something to show. Add your own and remove the ones you don't follow.

## The pill

<img src="media/pill.png" width="200" alt="The pill four ways: a sparkline, an arrow, the price as text, and an icon for the day">

The pill shows today's move for the stock you last looked at, as a
sparkline, an arrow, the price as text, or an icon: a bull on an up day, a
bear on a down one. Middle-click it to switch, or press `b` in the panel.
On a bar at the side of the screen, it switches between the icon and the
symbol over its change.

Click the pill for the panel, right-click it for the window, scroll over it
to step through your list, and drag it to move it along the bar. Point at
it for what it has no room for, such as the time of the newest price.

At night, after the stock's first trade, the pill keeps the day's close
and move until the new day's first prices arrive, soon after 04:00, and
pointing at it shows tonight's.

## Reading the chart

<img src="media/scrub.png" width="480" alt="The panel scrubbed back an hour and a half, to 10:16 in the morning. The price, the change, and the rows show that moment">

Run the pointer along the chart to see where a stock was at any moment,
such as the morning's low. The price, the change and the rows follow it.
Click the bull or bear at the top left to replay the chart.

Pick a range under the chart, from 1D to ALL, and every stock shows that
range. The rows always show the day: click the %, ± or bell at the end of
the list's header to show their change as a percent, an amount, or the
percent since the open.

Under the ranges are the range's low and high, the open (or a longer
range's first price) and the volume, then the 52-week low and high, the
market cap and the P/E. The market cap is Yahoo's last reported figure,
moved with the price since. When a company reports earnings in another
currency, the P/E converts them at Yahoo's rate for the day, and nothing
else is converted. Yahoo's 52-week low and high leave out trades outside
the session, so when Stonks shows one beyond them, such as a trade
overnight, they widen to take it in.

The top line names the moment in the market's day, such as Power hour, and
says when the market opens or closes, on the exchange's clock. For a US
stock, the large price is its newest trade, after the close too. Elsewhere
it's the regular session's.

The move beside the price counts from the close the chart's dashed line
marks, and the line under the price names it, such as FRI CLOSE 158.74.
While the large price is still the close, that line shows the pre-market
or after-hours price instead. The line under the move names the move and
gives it in the other unit: TODAY ▲4.57, OVERNIGHT ▼1.83 or PRE-MARKET
▼5.74. On a longer range, the move counts from the range's start. A coin
never closes, so its day is its last 24 hours.

The 1D chart shows one trading day, with the regular session bright and
the hours around it dim. For about ten minutes after a market abroad
opens, it keeps the day just closed, with the new day's first trades at
its end.

A US stock that Robinhood trades at night has a day that runs from 20:00
the evening before to 20:00, New York time, and its chart brightens the
session trading now, such as the pre-market or tonight. Through the night,
until about 04:00, the chart keeps the day that just closed and adds
tonight's trades at its end. Those trades belong to the day ahead: from
the night's first trade, the move counts from the close just gone, and the
dashed line steps to that close at the bell. The rows, like the pill, keep
the day's close and move until the new day's prices arrive. Over a weekend
or a holiday, the chart shows the last trading day, and the night before
the next session joins at its end. Where Yahoo has no prices for half an
hour or more of the pre-market or after hours, the chart draws Robinhood's
trades there, never in place of Yahoo's.

A price says "As of" and its time when it's more than two minutes behind
while its market trades, or saved from before and not yet refreshed.

## Your lists

<img src="media/lists.png" width="480" alt="The list menu open over the rows: All with seven symbols, US with four, New list, and Manage lists">

Click the list's name to switch lists, start one, or manage them. All
holds every symbol you follow, and your own lists each hold some of them.
To choose which lists a row is in, right-click it and pick "Choose
lists…", Ctrl-click it, or select it and press Ctrl+Enter.

To find or add a stock, click "+ Find or add a symbol" or press `/`, and
type a name or a symbol. Stocks in the list you're looking at come first,
with today's move. Below them come Yahoo's results: the chart shows the
highlighted one before you add it, and Enter or a click adds it.

To remove a row, click the × beside its symbol, or select it and press
Delete. It leaves the list you're looking at, and removing it from All
removes it from every list, asking first if one of your lists holds it.
For 5 seconds, a button such as "Undo NVDA" brings it back. `Ctrl+Z` does
too, until you change a list again.

The line beside the list's name counts the rows up, in green, and down, in
red. Click the order at the right of the header, such as MANUAL, to sort by
symbol, name or change, and its arrow to reverse it. Sorting by change
ranks by percent, since amounts in different currencies can't be compared.
In your own order, drag a row to move it.

## The window

<img src="media/window.png" width="720" alt="Stonks' window: the panel's chart and rows, at the window's width">

Stonks also opens as a tiled window with the panel's chart and rows.
Right-click the pill, or run `omarchy-shell grvc.stonks toggleWindow`. To
float it, add a window rule for class `org.quickshell` and title `Stonks`.

To open the panel or the window with a key, add an `o.bind` line to
`~/.config/hypr/bindings.lua` with a key of your choice and one of these
commands:

```sh
omarchy-shell shell toggle grvc.stonks     # the panel
omarchy-shell grvc.stonks toggleWindow     # the window
```

To use the window without the pill, run `omarchy plugin disable
grvc.stonks`, then add `{ "id": "grvc.stonks" }` to `plugins` in
`~/.config/omarchy/shell.json` to keep Stonks loaded. To bring the pill
back, remove that entry and run `omarchy plugin enable grvc.stonks`.

To add Stonks to the app launcher:

```sh
cp ~/.config/omarchy/plugins/grvc.stonks/share/stonks.desktop ~/.local/share/applications/
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
cp ~/.config/omarchy/plugins/grvc.stonks/share/grvc.stonks.svg ~/.local/share/icons/hicolor/scalable/apps/
```

## Smooth or retro

<img src="media/retro.png" width="480" alt="The panel in retro: block digits and a chart of pixel columns">

Retro draws the price in block digits and the chart in pixel columns, the
way Omarchy draws its logo. Smooth uses plain digits and a line chart.
Press `s`, or click the small chart icon at the top right, to switch.

<img src="media/light.png" width="480" alt="The panel on Catppuccin Latte, a light theme, in Stonks' own green and red, made for a light background">

Both use your theme's green for up and its red for down, never its accent
color, which Omarchy keeps for what's selected. Where a theme's pair is
missing, too alike or too faint, Stonks uses its own. On a clear bar over
a light wallpaper, the pill's green and red darken with the bar's text.

## Sounds

Sounds are off until you press `m` or click the speaker at the top right.
Then adding, removing or undoing a row makes a short sound, a screenshot
clicks like a shutter, a replay plays the line as it draws, and the chart
chimes as you run the pointer along it. A soft bell rings as the market of
the stock you last looked at opens and closes, except while Do Not Disturb
is on or an app is recording from your microphone. Refreshes and prices
make no sound.

## Screenshots

Press `Ctrl+C`, or click the camera at the top right, for a picture of the
chart, sized so X shows it whole. It shows the company's name, the price
and its move, the two lines under them, and the price's date, time and
zone. If you've moved along the chart, it shows that moment: with the
pointer, press `Ctrl+C` while it's still on the chart. Your list is never
in it.

Like Omarchy's own screenshots, it goes to your screenshots folder and the
clipboard, with a notification that opens it in your screenshot editor.

## Keys

`?` lists the keys you'll use every day. This table has all of Stonks' own:

| Key | Does |
| --- | --- |
| `↑` `↓` | Move the selection |
| `⏎` | Show the selected row's chart |
| `Ctrl+⏎` | Choose the selected row's lists |
| `←` `→` | Move along the chart |
| `[` `]` | Change the range |
| `p` | Replay the chart |
| `Ctrl+C` | Take a screenshot |
| `a` or `/` | Find or add a symbol |
| Delete or Backspace | Remove the selected row |
| `Ctrl+Z` | Undo a removal |
| `Ctrl+↑` `Ctrl+↓` | Move the selected row, in your own order |
| `o` | Change the order |
| `Shift+O` | Reverse the order |
| `w` | Open the list menu |
| `⏎` | Rename the selected list, in Manage lists |
| `Ctrl+↑` `Ctrl+↓` | Move the selected list, in Manage lists |
| Delete or Backspace | Ask to delete the selected list, in Manage lists; `⏎` deletes it |
| `c` | Show the change in %, an amount or since the open |
| `s` | Switch between smooth and retro |
| `m` | Turn sounds on or off |
| `r` | Refresh |
| `Shift+U` | Update Stonks when a new version is out, and restart the shell to run it |
| `b` | Change how the pill looks, as a middle-click on it does (panel only) |
| Tab or `Shift+Tab` | Switch to the bar's next or previous panel (panel only) |
| `?` | Show the keys you'll use every day |
| `Esc` | Close |

In the panel, Omarchy's panel keys work too: `j` `k` move the selection,
`h` `l` move along the chart, Space shows the selected row's chart, and `x`
removes the selected row.

## If something's wrong

A "!" on the pill means a refresh of its stock failed or is late. Point at
the pill to see which, and, where Stonks knows, why and when it tries
again.

<details>
<summary>What each message means, and what to do</summary>

- **"Can't connect".** Yahoo sent nothing back. Rows keep the price they
  had, with its time. Check your internet: if other sites load, Yahoo may
  be down. Stonks retries within two minutes, and `r` retries at once.
- **"Server busy".** Yahoo asked Stonks to send fewer requests. Stonks
  retries at the time shown, at most 36 minutes on, and `r` won't hurry
  it.
- **"Not updating" or "No data" on a row, or "Can't get prices" on the top
  line.** A price hasn't come in time. Rows keep the price they had, with
  its time, and Stonks keeps trying, less often the longer Yahoo stays
  away. If Yahoo has changed what it sends, only a newer Stonks can fix
  it.
- **"Refresh failed" or "No data for this symbol" on a row.** Yahoo has
  nothing for the symbol, or sent a broken answer three times in a row.
  After a merger or a rename, search for the company to find what Yahoo
  calls it now. A delisted company may be gone for good. At night it can
  also mean Robinhood didn't answer, so a newer trade may be missing, and
  Stonks asks again within 5 minutes.
- **"As of" while the market is open.** Yahoo sends some prices late. When
  we measured, London, São Paulo and the VIX came 15 minutes late, and
  Mexico 20, while Nasdaq, NYSE, Toronto and crypto came within a minute.
  [Yahoo's table](https://help.yahoo.com/kb/SLN2310.html) lists the rest.
  Overnight prices run 10 to 15 minutes behind, since Robinhood reports
  those trades late. A thinly traded stock says "As of" when it last
  traded more than two minutes ago.
- **A price looks wrong.** Check the currency: Stonks never converts, since
  a converted price is one nobody traded at. PENCE means pence, as Yahoo
  quotes many London listings, so 3,580.00 is £35.80. For a US stock, the
  large price may be a trade after the close. Stonks leaves out prices of
  zero or less, and stray points in Yahoo's charts.
- **A dash for the move, with FIRST TRADES · MOVE SOON.** For a few
  minutes after a stock in London, Tokyo or Toronto first trades, Yahoo
  can still count its day from the close before last, so Stonks counts
  from the last close it saw itself. If it hasn't seen one, the move shows
  a dash until the stock has traded for ten minutes. Since the open, the
  move and the open stay blank until Yahoo sends the day's first
  five-minute bar, a few minutes into any market's day.
- **"No trades today", "No trades on" a day, or "Traded only at" a time.**
  The listing traded too little that day to draw a line.
- **"1W unavailable" or "Couldn't search", with RETRY.** Yahoo didn't send
  that chart or those results. Click RETRY, or in search reach it with `↓`
  and press `⏎`. After "server busy", RETRY works once Yahoo lets Stonks
  back in, at most 36 minutes on.
- **"Couldn't search · try other words".** Yahoo can't search for what you
  typed, such as an emoji. Type other words.
- **"market hours unknown".** Stonks' calendar of holidays and early
  closes for this exchange has run out, so it can't say when the market
  opens. Prices and times are still right. [Update Stonks](#update) for a
  new calendar.
- **"Couldn't load your lists" in the footer.** Your lists file,
  `~/.config/omarchy/grvc.stonks.json`, can't be read or isn't valid JSON,
  often after a hand edit. Stonks won't write over it, so changes you make
  meanwhile are lost when it reads the file again or the shell restarts.
  Fix the file and save it, and Stonks reads it at once, or remove it to
  start over.
- **"Your changes aren't saved" in the footer.** Stonks can't write your
  lists file, and a restart loses every change since the last save. With
  "click to try again", the disk is full or the file or its folder is
  read-only: free some space or fix the permissions, then click the
  footer. With "fix or remove", Stonks can't read the file: fix it or
  remove it, as above.

To report a wrong price or anything else, use the
[bug form](https://github.com/gmchande/omarchy-stonks/issues/new?template=bug.yml).
For a price, give the symbol, the range and the time, what Stonks showed,
and what your broker or the exchange showed then.

</details>

## What it runs

Stonks isn't investment advice, and isn't affiliated with Yahoo or
Robinhood. Yahoo's endpoints are unofficial and Robinhood's data is for
personal use, so either may change or stop without notice. Robinhood fills
the night, from 20:00 to 04:00 New York time, when Yahoo's charts are
empty.

<details>
<summary>The commands it runs, the sites it asks, and the files it writes</summary>

**Commands**, all of which Omarchy ships:

- `curl` for every request, with a time limit and a size cap.
- `sh`, `mkdir`, `chmod`, `mktemp`, `ln` and `rm`, to make its files and
  keep them readable only by you.
- `timeout`, to stop its file, sound and screenshot commands if they hang.
- With sounds on: `pw-play` for each sound; `pw-cat` playing silence while
  you move along the chart, so each chime plays at once; as the bell is
  due, `bash` with `omarchy-shell notifications isDnd` and `pw-dump`, to
  check Do Not Disturb and that no app is recording; and `sh` with
  `md5sum` and `head`, once a run, to check its saved sounds.
- For a screenshot: `sh` with `sed`, `tail`, `date` and `head` to find
  your screenshots folder and name the file, `wl-copy` for the clipboard,
  and `omarchy-notification-send`. A click on the notification opens the
  picture in `omasnap`, or without it in `tensaku-edit` or the editor
  `OMARCHY_SCREENSHOT_EDITOR` names.
- Only when you ask for an update: `omarchy plugin update grvc.stonks` in
  a terminal, then `omarchy restart shell` when `git` shows the update
  moved Stonks' folder. After an update run elsewhere, `omarchy restart
  shell` alone, when you click the footer or press `Shift+U`.

**Sites**, and nothing else:

- `query1.finance.yahoo.com` for prices, charts, the market cap and P/E,
  and the currency rate a P/E needs. It asks once for every row as the
  shell starts. Then, with only the pill on screen, it asks for the pill's
  stock alone: every minute while its market trades, every 5 minutes
  before and after the session, and every 15 minutes while it's closed.
  With the panel or the window open, it asks for the rest of All too, the
  rows in sight first, every minute while a row's market trades and every
  5 minutes before and after the session, but every minute for the stock
  on show and never for a row whose market hasn't traded since its last
  price. With no pill in a bar, it asks nothing until you open the panel
  or the window. It also asks for a search result you pause on. To change
  "every minute", set `"refreshIntervalSec"` in
  `~/.config/omarchy/grvc.stonks.json` to a number of seconds from 30 to
  900.
- `query2.finance.yahoo.com` for search, as you type, asking each word
  once while search is open.
- `api.robinhood.com` for overnight prices, and for trades that fill a
  stretch Yahoo left empty. It asks once a day which stocks trade
  overnight, again 5 minutes later if that fails, and once for each stock
  the pill shows. Through the night it asks every 5 minutes for the pill's
  stock and, with the panel or the window open, for the stock on show and
  the rows in sight, with one past each edge. It asks once more on a
  morning Yahoo has no prices for half an hour or more of the pre-market,
  and the same for a US stock or ETF you pause on in search.
- `raw.githubusercontent.com` for the newest version number, as the shell
  starts and once a day. To turn this off, add `"updateCheck": false` to
  `~/.config/omarchy/grvc.stonks.json`.

Stonks asks for nothing while every screen is off. When a site turns it
away, it waits about as long as the site asks, or longer each time, up to
36 minutes.

**Files:**

- `~/.config/omarchy/grvc.stonks.json`: your lists and settings.
- `~/.cache/grvc.stonks`, or `$XDG_CACHE_HOME/grvc.stonks` when that's
  set: the last prices, and the sounds Stonks makes for itself.
- Each screenshot, as `stonks-<symbol>-<date>_<time>.png` in the folder
  Omarchy's own screenshots use.

Only you can read the cache folder, and Stonks makes your lists file
readable only by you when it creates or saves it.
[`test/boundaries.sh`](test/boundaries.sh) fails if any code outside a few
allowed files runs a command, reads or writes a file, or makes a request.

</details>

## Update

```sh
omarchy plugin update grvc.stonks
omarchy restart shell
```

Or, when the footer says "Update to …", click it or press `Shift+U`. A
terminal opens and shows what changes. Say yes, and it updates Stonks and
restarts the shell, unless Stonks has changes it hasn't saved or can't read
your lists file. Then, or after an update run anywhere else, the footer
says "Updated to … · click to restart the shell". Stonks never updates
itself.

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

If Stonks earns a place in your bar, a heart on its page helps the next
person find it.
