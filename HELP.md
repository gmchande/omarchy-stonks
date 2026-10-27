# Stonks help

The finer points of what Stonks shows, a few workarounds, and what to do
when something's wrong. The [README](README.md) has the basics.

## Reading the day

A range marks its high and low on the chart, with their dates, and a stock
younger than the range says when it began: "SINCE 31 JUL 2025".

Under the ranges, two lines place the price between its low and high. The
first is the range's: on 1D the day's, beside its open and volume, and on a
longer range that range's, beside START, the price its change is measured
from, and the volume traded over it. The second is the past 52 weeks',
beside the market cap and P/E.

- **Market cap** is an estimate: Yahoo's last reported figure, moved with
  the price since.
- **P/E** is the price over the last year's earnings per share. Where a
  company reports earnings in another currency, as Shopify does in US
  dollars, Stonks converts them at Yahoo's rate of the day, inside the P/E
  alone.

The top line says where the market is, in its own time: counting down to
the open or the close, after hours, or closed. With less room, as at a
larger text size, it says less and keeps the time: "CLOSED AT 16:00".

The smaller line under the price shows the pre-market, after-hours, or
overnight price. The overnight price is for the US stocks and ETFs
Robinhood trades overnight, and is measured from the last close. Until the
next session opens, the 1D chart shows the last session, the one the price
and its move are about, then the night after it and the pre-market.
Pointing anywhere on it measures that price from the dashed line, the close
the chart is drawn against. A stock that trades only now and then shows the
night's trades as dots.

### When "As of" shows

An old price says "As of" and its time, on its row and above the price.
Old means:

- more than two minutes behind while its market trades, or saved from the
  last session;
- for a price nothing kept fresh while the popup and the window were
  closed, such as a coin's, only if its new price takes more than 2 seconds
  to come;
- at the open, for the last close, only if the session's first price takes
  more than a minute to come. Stonks asks for it every 15 seconds until
  then.

If Yahoo sends no regular price, Stonks keeps the last regular chart trade,
labeled "Last trade" with its time. If Yahoo sends a price without its
time, it says "Time not sent", and "Saved" too if kept from the last
session. A refresh that fails, or gets no answer in 90 seconds, says so in
the same places and puts a "!" on the pill.

## Your lists

When you search, the top result shows in the chart before you add it.

After you remove a row with its ×, the row that slides into its place shows
its × only once you move the pointer, so a second click can't remove it by
mistake. Right-click a row to choose where it goes from, such as "Remove
from Growth" or "Remove from all 3 lists". In All, where removing takes a
symbol out of every list, the × and Delete ask first when one of your own
lists holds it too.

For 5 seconds after a removal, "Undo NVDA" shows beside "+ Add a symbol":
click it to bring the row back. Until a list next changes, `Ctrl+Z` does
the same, and so does "+ Add a symbol", where the symbol is the first
result, with PUT BACK. Each puts it back in its lists at its old place,
with the price it had, and Stonks asks for a new one at once.

The sign at the end of the list's header says what the rows' figures are:
% for a percent, ± for an amount, and a bell for since the open. Click it
to step every row to the next. Sorted by change, the rows rank by the
percent they show, from the open when they show since the open. Amounts
can't be ranked across currencies, so while the rows show amounts they stay
in percent order.

## The window

To float the window, match class `org.quickshell` and title `Stonks` in a
window rule.

The window also works with no pill. Run
`omarchy plugin disable grvc.stonks`, then add `{ "id": "grvc.stonks" }` to
`plugins` in `~/.config/omarchy/shell.json` to keep the plugin loaded. To
bring the pill back, remove that entry first, then run
`omarchy plugin enable grvc.stonks center`.

For Stonks in the app launcher, which `omarchy plugin add` doesn't set up:

```sh
cp ~/.config/omarchy/plugins/grvc.stonks/share/stonks.desktop ~/.local/share/applications/
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
cp ~/.config/omarchy/plugins/grvc.stonks/share/grvc.stonks.svg ~/.local/share/icons/hicolor/scalable/apps/
```

## Sounds

While sounds are on:

- Adding a symbol, removing a row, and undoing the removal each make a
  short sound; the undo plays the removal backwards. A screenshot makes a
  shutter.
- Run the pointer along the chart and it plays like a row of chimes, higher
  where the line is higher: the bars you cross ring, up to 22 a second,
  ending on the one under the pointer, and each step of `←` `→` rings too.
- A replay sweeps the same bars along the line; in retro it also ticks
  where the line crosses the chart's baseline: the previous close on 1D,
  the range's first price on the others.
- A soft bell rings as the market of the stock you last looked at opens and
  as it closes, on time or not at all, and never while every screen is off
  or an app records from your microphone.

Each look has its own voice. Nothing else sounds by itself: no refresh or
price. Your system volume sets how loud they are.

## Screenshots

A screenshot is laid out to share: the price large with its currency beside
it (an index's level has none), its move, the day's bull or bear, the
exchange, the time of the price with its zone, the price the move is
measured from, a range's high and low on its chart, and at the foot the
day's date or the range's length and dates. Scrubbed, it shows the moment
you scrubbed to, naming the pre-market, after hours or overnight when it
falls there. Your list is never in it.

It lands where Omarchy's own screenshots do, on Omarchy 4.0 and on 4.5: a
file in your screenshots folder, the picture on the clipboard, and
Omarchy's notification, which opens it in your screenshot editor when you
click it: Omasnap on 4.5, Tensaku on 4.0.

## Updates

Once a day, Stonks asks GitHub for the newest version. When it's newer than
yours, the footer's right end says "Update to …" each time the popup or the
window opens, until you update; "+ Add a symbol" stays where it is. A click
on it, or `Shift+U`, opens a terminal that runs
`omarchy plugin update grvc.stonks`, which shows what changes and asks
before it updates. Until the shell restarts, the old version keeps running,
and the footer says "Updated to … · click to restart the shell"; a click,
or `Shift+U`, restarts it.

To stop the daily look, add `"updateCheck": false` to
`~/.config/omarchy/grvc.stonks.json`; Stonks then asks GitHub nothing, and
you update by the commands in the [README](README.md#update). Take it out
to look again.

## If something's wrong

A "!" on the pill means its stock's quote is late or its last refresh
failed: point at the pill to read which. The row and the line above the
price say the same.

- **The header says "Can't get prices".** Every symbol you follow is
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
  away. When no answer came, `r` asks again at once; when Yahoo turned
  Stonks away, `r` won't hurry it, since Yahoo asked for fewer requests.
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
  holidays and clock changes up to a set date. This exchange's have run
  out, so it can't say when the market next opens. Times still read
  true, by the clock Yahoo sends with each price. Stonks doesn't update
  itself: [update it](README.md#update) for a renewed calendar.
- **The footer says "Couldn't load your lists".** The file holding your
  lists, `~/.config/omarchy/grvc.stonks.json`, can't be opened or isn't
  valid JSON, often after a hand edit. Stonks keeps the lists it has and
  writes nothing over the file until it can read it again. A change you
  make meanwhile shows, and the footer says "Your changes aren't saved ·
  fix or remove grvc.stonks.json": the file read again, or a restart,
  loses it. Fix the file and Stonks reads it as you save, or remove it to
  start over with the five starter symbols.
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
