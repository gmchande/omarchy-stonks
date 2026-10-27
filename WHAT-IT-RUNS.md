# What Stonks runs

This page lists everything Stonks does outside the shell: the commands it
runs, the sites it asks, and the files it writes. The [README](README.md)
has the short version.

Every request goes through one curl command, in [`Fetch.js`](Fetch.js),
which sets its limits. [`test/boundaries.sh`](test/boundaries.sh) fails if
a command, a file read or write, or a request shows up anywhere but the few
files allowed to make them. It runs on every push and pull request to `dev`
and `main`, and whenever someone starts it by hand:

[![Checks](https://github.com/gmchande/omarchy-stonks/actions/workflows/fresh-clone.yml/badge.svg)](https://github.com/gmchande/omarchy-stonks/actions/workflows/fresh-clone.yml)

## What it needs

Nothing beyond Omarchy 4. Stonks runs these programs, and Omarchy ships
them all:

- `curl`;
- PipeWire's `pw-play`, `pw-cat`, and `pw-dump`;
- `sh`, `bash`, `timeout`, `head`, `md5sum`, `mkdir`, `chmod`, `mktemp`,
  `ln`, and `rm`;
- for a screenshot, `sed`, `tail`, `date`, `wl-copy`, and
  `omarchy-notification-send`.

## Commands

Always:

- `curl`, for every request.
- As Stonks starts, one `sh` that makes its cache folder with `mkdir` and
  `chmod`, so it's yours alone.
- `chmod` as Stonks writes each of its files, so each is yours alone too.

When Stonks saves `~/.config/omarchy/grvc.stonks.json` and finds no file
there, one `sh` makes the file yours alone before it holds anything:

- `mktemp` makes a file beside it that only you can read;
- the `sh` writes your settings into it from its environment, never from
  its arguments;
- `ln` gives it its name, and never replaces a file already there;
- `rm` removes the temporary name.

These run under `timeout`, which stops each after 5 seconds: the `sh` at
the start, each `chmod`, and the `sh` that saves. If a save can't be made
this way, the footer says your changes aren't saved.

While sounds are on:

- Once a run, one `sh`, under `timeout` for 5 seconds. It reads, by
  `md5sum`, the files the sounds are made from, and lists which sound files
  in the cache folder still match them. Its answer passes through `head`,
  capped at 64 KB.
- `pw-play` to play a sound, under `timeout` for 4 seconds. It runs only
  when you add, remove, or undo a row, take a screenshot, turn sounds on,
  replay a chart, or run the pointer along it, or when the bell is due.
- One `sh` that starts a `pw-play` for each chime, each under `timeout` for
  2 seconds, and plays nothing else.
- `pw-cat`, playing silence while you scrub the chart, with the pointer or
  with `←` `→`, and for a second after, so each chime plays at once. Each
  stream runs under `timeout` for 60 seconds, and starts again while you
  scrub.
- `pw-dump` once as each bell is due, in `bash`, under `timeout` for 3
  seconds, and through `head` capped at 4 MB. It checks whether an app is
  recording from a microphone, and reads only which streams are running. If
  its answer runs out of time, fails, or goes over 4 MB, Stonks counts that
  as recording, and the bell stays quiet.

Only when you take a screenshot, each under `timeout`, which stops it after
5 seconds:

- one `sh` that looks for `omasnap`, Omarchy 4.5's screenshot tool, and
  picks the picture's file name in your screenshots folder, making the
  folder if it's missing. Its answer passes through `head`, capped at 8 KB;
- another `sh` that pipes the picture into `wl-copy`, to put it on the
  clipboard;
- `omarchy-notification-send`, with the words Omarchy 4.0's own
  screenshots use.

When you click that notification, Omarchy runs your screenshot editor on
the file: `omasnap` where it's installed, else `OMARCHY_SCREENSHOT_EDITOR`,
else Tensaku.

For updates, and only when you ask:

- `omarchy plugin update grvc.stonks`, in a terminal, when you click
  "Update to …" or press `Shift+U` while it shows;
- `omarchy restart shell`, when you click the footer's notice that an
  update is on disk, or press `Shift+U` while it shows.

### What silence costs

While `pw-cat` plays silence, your speakers' amplifier stays on and your
headphones stay connected to this computer, just as when any sound plays.
It uses about a tenth of a percent of one processor core. It runs only
while your scrub moves and for a second after, or while a replay waits for
a sleeping output to wake. It never runs just because the popup or the
window is open, or while a scrub stands still.

After 4 seconds of quiet from Stonks, a sound starts with up to 150 ms of
its own silence. That gives a sleeping output time to wake, so none of the
sound is cut off. A replay waits for the output instead, so its sound keeps
in step with its sweep.

## Sites

- `query1.finance.yahoo.com` for quotes, charts, the market cap, and the
  P/E, with the day's currency rate when a P/E needs one.
- `query2.finance.yahoo.com` for search.
- `api.robinhood.com` for overnight prices, and for which stocks trade
  overnight.
- `raw.githubusercontent.com` for the newest version number, as the shell
  starts and then once a day. When no answer comes, Stonks asks again once
  Yahoo answers again, or a day later. With `"updateCheck": false` in
  `~/.config/omarchy/grvc.stonks.json`, it never asks.

Nothing else.

Yahoo's endpoints are unofficial, and its terms restrict automated access.
Robinhood's data is for personal use. Either may change or stop without
notice. Some prices come late:
[Yahoo's table](https://help.yahoo.com/kb/SLN2310.html) lists delays of up
to 30 minutes for many exchanges and some indexes, London and Tokyo among
them. Stonks isn't investment advice, and isn't affiliated with Yahoo or
Robinhood.

### How often it asks

- Every request has a time limit and a size cap.
- One request fetches quotes for up to 20 listings, so even a long list
  refreshes in a few requests a minute. One request fetches overnight
  prices for up to 25 listings over a whole day, or 75 over the last hour.
- From 04:00 New York time until a US session opens, and for a listing's
  first price, Stonks asks for two days of prices instead of one, so the
  chart still has the last session.
- Stonks fetches each listing only as often as its market can move. When a
  site refuses it, Stonks leaves that site alone for as long as the site
  asks, up to half an hour.
- A window no screen shows, because it's on another workspace or its
  screen is off, fetches only what a closed window would.

### Robinhood

Stonks asks Robinhood two things about your US stocks and ETFs: whether
each trades overnight, and its overnight prices. It asks whether a stock
trades overnight once a day, or 5 minutes after an answer fails. It asks
for prices only for a stock that trades overnight, or one it doesn't know
about yet:

- For the stock on the pill, it asks both once each time the shell starts,
  as the stock's first price comes in.
- While the popup or the window is open, it asks about the rest, and about
  each one you add. It asks whether each trades when that's due. It asks
  for prices when it has none, every 5 minutes through a night that
  trades, once after each night ends, and 5 minutes after an answer fails.
- It does the same for a search result you rest on before you add it, if
  the result isn't in any list.
- When you press `r`, it asks for the prices of the charts on show that
  trade overnight, unless it asked in the last 10 seconds.

It asks for the last hour of prices when it has prices from the last half
hour, and for a whole day otherwise.

### Updates

Stonks never updates itself. When a new version is out, the footer offers
it.

## Files it writes

- Your lists and settings, in `~/.config/omarchy/grvc.stonks.json`.
- In its cache folder, which is `$XDG_CACHE_HOME/grvc.stonks` when
  `XDG_CACHE_HOME` is set, and `~/.cache/grvc.stonks` otherwise:
  - the last quotes, in `quotes.json`;
  - while sounds are on, a replay's sound, in `replay.wav`, written over
    when you replay a different chart;
  - the chimes' notes, `chime-*.wav`, each also in copies that open with
    silence, and the other sounds, each opening with its silence,
    `lead-*.wav`. Stonks writes these again only when what they're made
    from has changed, or one is missing;
  - `stamp-smooth` and `stamp-retro`, which record what the sounds were
    made from.
- For each screenshot you take, one picture,
  `stonks-<symbol>-<date>_<time>.png`. It goes straight into the folder
  Omarchy's own screenshots use, with no copy anywhere else. That folder
  is:
  - where Omasnap is installed, `OMASNAP_SCREENSHOT_DIR`, else
    `OMARCHY_SCREENSHOT_DIR`, else the `directory` in Omasnap's `[output]`
    settings, else `Screenshots` in your Pictures folder;
  - without Omasnap, `OMARCHY_SCREENSHOT_DIR`, else your Pictures folder.

Only you can read the files in the cache folder (0600, the folder 0700).
The same goes for the data file, from the moment Stonks makes it. If an
older Stonks or an editor left it readable to others, Stonks' next save
makes it yours alone again.

The shell itself keeps the pill's form, on Stonks' bar entry in
`~/.config/omarchy/shell.json`.
