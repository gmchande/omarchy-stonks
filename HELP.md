# Stonks help

This page covers the finer points of what Stonks shows, a few workarounds,
and what to do when something's wrong. The [README](README.md) has the
basics.

## Reading the day

The chart marks the range's high and low, with their dates. When a stock is
younger than the range, the chart says when it began, such as "SINCE 31
JUL 2025".

Under the ranges, two lines place the price between a low and a high. The
first line is for the range you picked. On 1D it's the day's, with the open
and the volume beside it. On a longer range it's that range's, with START,
the price the change is measured from, and the volume traded over the
range. The second line is for the past 52 weeks, with the market cap and
P/E beside it.

- **Market cap** is an estimate: Yahoo's last reported figure, moved in
  step with the price since.
- **P/E** is the price divided by the last year's earnings per share. Some
  companies report earnings in another currency, as Shopify does in US
  dollars. Stonks then converts the earnings at Yahoo's rate for the day,
  inside the P/E and nowhere else.

The top line names the moment in the market's day, such as "OPENING BELL"
or "AFTER HOURS", and says when the market opens or closes, by the
exchange's own clock. With less room, as at a larger text size, it says
less but keeps the time, as in "CLOSED AT 16:00".

The smaller line under the price shows the pre-market, after-hours, or
overnight price. Overnight prices come from Robinhood, for the US stocks
and ETFs it trades overnight, and are measured from the last close.

Until the next session opens, the 1D chart shows the last session, the one
the price and its move are about. Then it runs on through the night and the
pre-market. Point anywhere on it to measure that price from the dashed
line, which is the close the chart is drawn against. A stock that trades
only now and then shows the night's trades as dots.

### When "As of" shows

An old price says "As of" and its time, on its row and above the price. A
price is old when it's more than two minutes behind while its market
trades, or when it was saved from the last session. Two cases wait a moment
before saying so:

- A price nothing kept fresh while the popup and the window were closed,
  such as a coin's, gets 2 seconds for its new price to come.
- At the open, the last close gets a minute for the session's first price
  to come. Stonks asks for that price every 15 seconds until then.

If Yahoo sends no regular price, Stonks shows the chart's last regular
trade, labeled "Last trade" with its time. If Yahoo sends a price without
its time, Stonks says "Time not sent", and also "Saved" if the price was
kept from the last session. A refresh that fails, or gets no answer in 90
seconds, says so in the same places and puts a "!" on the pill.

## Your lists

When you search, the chart shows the top result, or the one you move to
with `↑` `↓`, before you add it.

When you remove a row with its ×, the next row slides into its place. That
row's × shows only once you move the pointer, so a second click can't
remove it by mistake.

Right-click a row to choose which lists it leaves, such as "Remove from
Growth" or "Remove from all 3 lists". Removing a symbol from All takes it
out of every list, so in All the × and Delete ask first when one of your
own lists holds it too.

For 5 seconds after a removal, "Undo NVDA" shows beside "+ Add a symbol".
Click it to bring the row back. Until a list next changes, `Ctrl+Z` does
the same, and so does "+ Add a symbol", which offers the symbol first,
marked PUT BACK. Each way puts the row back in its lists, in its old place,
with the price it had, and Stonks asks for a new price at once.

The sign at the end of the list's header says what the rows' figures are:
% for a percent, ± for an amount, and a bell for the move since the open.
Click it to switch every row to the next one. Sorted by change, the rows
rank by percent: the day's, or since the open when that's what they show.
Amounts in different currencies can't be ranked against each other, so
while the rows show amounts, they stay in percent order.

## The window

To float the window, add a window rule that matches class `org.quickshell`
and title `Stonks`.

You can use the window without the pill. Run
`omarchy plugin disable grvc.stonks`, then add `{ "id": "grvc.stonks" }` to
`plugins` in `~/.config/omarchy/shell.json`, which keeps the plugin loaded.
To bring the pill back, first remove that entry, then run
`omarchy plugin enable grvc.stonks center`.

`omarchy plugin add` doesn't put Stonks in the app launcher. To add it:

```sh
cp ~/.config/omarchy/plugins/grvc.stonks/share/stonks.desktop ~/.local/share/applications/
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
cp ~/.config/omarchy/plugins/grvc.stonks/share/grvc.stonks.svg ~/.local/share/icons/hicolor/scalable/apps/
```

## Sounds

With sounds on:

- Turning sounds on plays the add sound once, so you hear how loud they
  are.
- Adding a symbol, removing a row, and undoing a removal each make a short
  sound. The undo plays the removal backwards. A screenshot makes a
  shutter sound.
- Run the pointer along the chart and it plays like a row of chimes,
  higher where the line is higher. Each bar you cross rings, up to 22 a
  second, ending on the one under the pointer. Each step of `←` `→` rings
  too.
- A replay sweeps the same chimes along the line. In retro it also ticks
  where the line crosses the chart's baseline: the previous close on 1D,
  and the range's first price on the others.
- A soft bell rings when the market of the stock you last looked at opens,
  and again when it closes. It rings on time or not at all, and never
  while every screen is off or an app is recording from your microphone.

Smooth and retro each have their own sounds. Nothing else makes a sound by
itself: no refresh, no price. Your system volume sets how loud they are.

## Screenshots

A screenshot is laid out to share. It shows the price, large, with its
currency beside it; an index's level has none. It also shows the move and
the price it's measured from, the day's bull or bear, the exchange, and the
time of the price with its zone. The chart marks the range's high and low.
The foot gives the day's date, or the range's length and dates.

If you've scrubbed the chart, the screenshot shows the moment you scrubbed
to. When that moment falls in the pre-market, after hours, or overnight, it
says so. Your list is never in it.

On Omarchy 4.0 and 4.5 alike, Stonks handles a screenshot the way Omarchy
handles its own. It saves a file to your screenshots folder, copies the
picture to the clipboard, and shows Omarchy's notification. Click the
notification to open the picture in your screenshot editor: Omasnap on
4.5, Tensaku on 4.0.

## Updates

Once a day, Stonks asks GitHub for the newest version number. When a newer
version is out, the right end of the footer says "Update to …" each time
the popup or the window opens, until you update. "+ Add a symbol" stays
where it is.

Click "Update to …", or press `Shift+U`, and a terminal runs
`omarchy plugin update grvc.stonks`. It shows what changes and asks before
it updates. The old version keeps running until the shell restarts, and
the footer says "Updated to … · click to restart the shell". Click it, or
press `Shift+U`, to restart.

To stop the daily check, add `"updateCheck": false` to
`~/.config/omarchy/grvc.stonks.json`. Stonks then asks GitHub nothing, and
you update with the commands in the [README](README.md#update). Take the
line out to turn the check back on.

## If something's wrong

A "!" on the pill means its stock's last refresh failed or is late. Point
at the pill to see which. The row and the line above the price say the
same.

- **The header says "Can't get prices".** Every symbol you follow is
  waiting on Yahoo, or Yahoo turned them all away, so Stonks says it once
  instead of on every row. Rows with a price keep it, with the time it's
  from. The rest show only their symbol. Do as for "No data" below. If
  Yahoo has changed what it sends, only a newer Stonks can fix it.
- **A row says "No data" or "Update overdue".** Stonks waited 90 seconds
  for Yahoo. Either no answer came, or Yahoo turned Stonks away. A row with
  a price keeps it, with the time it's from. Check your connection. If
  other sites load, Yahoo is down or refusing Stonks, and all you can do is
  wait. Stonks keeps trying on its own, less often the longer Yahoo stays
  away. If no answer came, `r` asks again at once. If Yahoo turned Stonks
  away, `r` won't hurry it, since Yahoo asked for fewer requests.
- **A row says "No data for this symbol" or "Refresh failed".** Yahoo said
  it has nothing for the symbol, or sent a broken answer three times in a
  row. A row with a price keeps it, with the time it's from. Press `r` to
  try again. A symbol Yahoo dropped after a merger, a rename, or a
  delisting stays this way. Search for the company to find what Yahoo
  calls it now.
- **A stock or index says "As of" while its market is open.** Yahoo sends
  prices late for many exchanges and some indexes. When we measured,
  London, São Paulo, and the Cboe's VIX came 15 minutes late, and Mexico
  20. Nasdaq, NYSE, Toronto, and crypto came within a minute. For other
  exchanges, Tokyo among them, see
  [Yahoo's table of delays](https://help.yahoo.com/kb/SLN2310.html). A
  thinly traded stock says "As of" too when its last trade was more than
  two minutes ago. The overnight price shows its own time, usually 10 to
  15 minutes back, since Robinhood reports those trades late. It dims once
  it's 20 minutes old.
- **A price looks wrong.** Each price is in its listing's own currency,
  never converted. Where Yahoo names no currency, as for some indexes, none
  shows. A price marked PENCE is in pence, as Yahoo quotes many London
  listings: 3,580.00 is £35.80. The large price is the regular session's.
  Pre-market, after-hours, and overnight trades show on the smaller line
  under it, though some apps show them as the main price. The change is
  from the previous close, unless you've switched it to since the open. On
  a longer range, it's from the range's start. Stonks shows Yahoo's prices
  as sent, except the odd stray price Yahoo drops into a chart, which it
  leaves out. If a price still looks wrong, report it as below.
- **The day's chart says "No trades charted" or "Traded only at" a time.**
  The listing traded too little that day to draw a line.
- **The header says "1W unavailable", with RETRY beside it.** Yahoo didn't
  send the chart for that range. Click RETRY, or press `r`. While Yahoo is
  turning Stonks away, a range fails at once.
- **Search says "Search didn't answer", with RETRY beside it.** Yahoo's
  search didn't answer. Click RETRY, or press Enter. While Yahoo is turning
  Stonks away, a search fails at once, so try again in a moment.
- **The header says "schedule unavailable".** Stonks knows each exchange's
  holidays and clock changes up to a set date. For this exchange that date
  has passed, so Stonks can't say when the market next opens. Times are
  still right, since Yahoo sends its clock with each price. Stonks doesn't
  update itself, so [update it](README.md#update) for a new calendar.
- **The footer says "Couldn't load your lists".** Stonks can't open the
  file that holds your lists, `~/.config/omarchy/grvc.stonks.json`, or the
  file isn't valid JSON, often after a hand edit. Stonks keeps the lists it
  has and won't write over the file until it can read it again. Changes you
  make meanwhile show on screen, and the footer says "Your changes aren't
  saved · fix or remove grvc.stonks.json". Reading the file again, or a
  restart, loses them. Fix the file and Stonks reads it as soon as you
  save. Or remove it to start over with the five starter symbols.
- **The footer says "Your changes aren't saved".** Stonks couldn't write
  the file that holds your lists. The disk is full, or the file or its
  folder, `~/.config/omarchy`, is read-only. Your lists stay as you see
  them until the shell restarts, and a restart loses every change since
  the last save. Free some space or fix the permissions, then click the
  footer. Any change you make also tries again.

To report a price or chart that looks wrong, or anything this page doesn't
answer, use the
[bug form](https://github.com/gmchande/omarchy-stonks/issues/new?template=bug.yml).
For a price, give the symbol, the range, and the time; scrub the chart to
find it. Say what Stonks showed, and what your broker or the exchange
showed at that time. The form asks for the shell's log, which can name the
prices Stonks left out.
