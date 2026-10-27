# What Stonks runs

Everything Stonks does outside the shell: the commands it runs, the sites
it asks, and the files it writes. The [README](README.md) has the short
version.

Every request runs through the one curl command in [`Fetch.js`](Fetch.js),
which sets its limits. [`test/boundaries.sh`](test/boundaries.sh) fails if a
command, a file read or write, or a request turns up outside the few files
allowed them. It runs on every push to `dev` and `main`, on every pull
request to them, and when started by hand:

[![Checks](https://github.com/gmchande/omarchy-stonks/actions/workflows/fresh-clone.yml/badge.svg)](https://github.com/gmchande/omarchy-stonks/actions/workflows/fresh-clone.yml)

## What it needs

Nothing beyond Omarchy 4. It runs `curl`, PipeWire's `pw-play`, `pw-cat`,
and `pw-dump`, and `sh`, `bash`, `timeout`, `head`, `md5sum`, `mkdir`,
`chmod`, `mktemp`, `ln`, and `rm`, which Omarchy ships, and, for a
screenshot, `sed`, `tail`, `date`, `wl-copy`, and
`omarchy-notification-send`.

## Commands

Always:

- `curl` for every request.
- As Stonks starts, one `sh` that makes its cache folder with `mkdir` and
  `chmod`, yours alone; and `chmod` as it writes each of its files, to make
  it yours alone too.

When it saves `~/.config/omarchy/grvc.stonks.json` and finds none there,
one `sh` that makes the file yours alone before it holds anything:

- `mktemp` makes a file beside it that only you can read;
- the `sh` writes your settings into it from its environment, never its
  arguments;
- `ln` puts it under its name, never over a file there;
- `rm` takes the extra name away.

Each of these runs under `timeout`, which stops it after 5 seconds. A save
that can't be made this way says your changes aren't saved.

While sounds are on:

- Once a run, one `sh` under `timeout` for 5 seconds that reads, by
  `md5sum`, the files its sounds are made from, and which sound files in
  its cache folder hold them, through `head` for 64 KB.
- `pw-play` to play a sound, with 4 seconds under `timeout`, only when you
  add, remove, or undo a row, take a screenshot, turn sounds on, replay a
  chart, or move along it, or the bell is due.
- One `sh` that starts a `pw-play` for each chime, with 2 seconds each
  under `timeout`, and plays nothing else.
- While your scrub of the chart moves, with the pointer on it or by `←`
  `→`, and for a second after, `pw-cat` playing silence, so each chime
  plays at once. Each stream runs under `timeout` for 60 seconds and starts
  again while you scrub.
- `pw-dump` once as each bell is due, in `bash` under `timeout` for 3
  seconds and through `head` for 4 MB, to see whether an app is recording
  from a microphone, reading only which streams run. An answer that runs
  out of time, fails, or goes over 4 MB counts as recording, so the bell
  stays quiet.

Only when you take a screenshot, each under `timeout`, which stops it after
5 seconds:

- one `sh` that looks for `omasnap`, Omarchy 4.5's screenshot tool, and
  names the picture's file in your screenshots folder, making the folder if
  it isn't there, its answer through `head` for 8 KB;
- another that hands `wl-copy` the picture on its input, to put it on the
  clipboard;
- `omarchy-notification-send` with Omarchy's own words, as Omarchy 4.0's
  own screenshots do.

Only when you click that notification, Omarchy runs your screenshot editor
on the file: `omasnap` where it's installed, else
`OMARCHY_SCREENSHOT_EDITOR`, else Tensaku.

For updates:

- `omarchy restart shell`, only when you click the notice that an update is
  on disk, or press `Shift+U` while it shows;
- `omarchy plugin update grvc.stonks` in a terminal, only when you click
  "Update to …" or press `Shift+U` while it shows.

### What silence costs

While `pw-cat` plays silence, your speakers' amplifier stays powered and
your headphones stay connected to this computer, as when any sound plays,
and it takes about a tenth of a percent of one processor core. It runs only
while your scrub moves, and a second after, or a replay waits for a
sleeping output to wake, never just because the popup or the window is
open or a scrub stands still. A sound after 4 seconds of quiet from Stonks
starts with up to 150 ms of silence of its own, so a sleeping output wakes
before the sound and none of it is cut; a replay waits for the output
instead, so its sound keeps in step with its sweep.

## Sites

- `query1.finance.yahoo.com` for quotes, charts, and the market cap and
  P/E, with the day's currency rate a P/E needs.
- `query2.finance.yahoo.com` for search.
- `api.robinhood.com` for overnight prices and which stocks trade
  overnight.
- `raw.githubusercontent.com` for the newest version number, as the shell
  starts and then once a day; when no answer comes, again once Yahoo
  answers again, or a day later; never with `"updateCheck": false` in
  `~/.config/omarchy/grvc.stonks.json`.

Nothing else.

Yahoo's endpoints are unofficial, and its terms restrict automated access;
Robinhood's data is for personal use. Either may change or stop without
notice. Some prices come late: [Yahoo's table](https://help.yahoo.com/kb/SLN2310.html)
lists delays of up to 30 minutes for many exchanges and some indexes,
London's and Tokyo's among them. Stonks isn't investment advice, and isn't
affiliated with Yahoo or Robinhood.

### How often it asks

- Every request has a time limit and a size cap.
- Quotes come up to 20 listings to a request, so a long list refreshes in
  a few requests a minute, and overnight prices up to 25 for a whole day
  and 75 for the last hour.
- Before a US session opens, from 04:00 New York, and for a listing's first
  price, Stonks asks for two days of prices in place of one, so the chart
  has the last session.
- Stonks fetches each listing only as often as its market can move, and
  leaves a site that refuses it alone for a while, as long as it asks up to
  half an hour.
- A window no screen shows, on another workspace or a screen switched off,
  fetches only what a closed one does.

### Robinhood

Stonks asks Robinhood two questions about your US stocks and ETFs: whether
each trades overnight, and its overnight prices. It asks the first about a
stock once a day, or 5 minutes after an answer fails, and asks for prices
only for a stock that trades overnight or isn't known yet:

- for the stock on the pill, both once each time the shell starts, as its
  first price comes in;
- while the popup or window is open, for the rest and each one you add:
  whether it trades when that's due, and its prices when it has none,
  every 5 minutes through a night that trades, once after each night ends,
  and 5 minutes after an answer fails;
- the same for a search result you rest on before you add it, when it
  isn't in any list;
- when you press `r`, the prices of the charts on show that trade
  overnight, unless it asked for prices in the last 10 seconds.

It asks for the last hour of prices when it has prices from the last half
hour, and for a whole day otherwise.

### Updates

Never by itself. When a newer version is out, the footer offers it.

## Files it writes

- Your lists and settings in `~/.config/omarchy/grvc.stonks.json`.
- In its cache folder, `$XDG_CACHE_HOME/grvc.stonks` when `XDG_CACHE_HOME`
  is set, else `~/.cache/grvc.stonks`:
  - the last quotes in `quotes.json`;
  - while sounds are on, a replay's sound in `replay.wav`, written over at
    each replay of another chart;
  - beside it the chimes' notes, `chime-*.wav`, each also with its silence
    first, and the other sounds with theirs, `lead-*.wav`, written again
    only when what they're made from has changed or one is missing;
  - `stamp-smooth` and `stamp-retro`, which say what they were made from.
- For each screenshot you take, one picture,
  `stonks-<symbol>-<date>_<time>.png`, saved straight into the folder
  Omarchy's own screenshots use, with no copy anywhere else:
  - where Omasnap is installed, `OMASNAP_SCREENSHOT_DIR`, else
    `OMARCHY_SCREENSHOT_DIR`, else the `directory` in Omasnap's `[output]`
    settings, else `Screenshots` in your Pictures folder;
  - without it, `OMARCHY_SCREENSHOT_DIR`, else your Pictures folder.

Everything in the cache folder is readable by you alone (0600, the folder
0700), and so is the data file, from the moment Stonks makes it, and again
from Stonks' next save after an older Stonks or an editor left it readable
to others.

The shell keeps the pill's form on its bar entry in
`~/.config/omarchy/shell.json`.
