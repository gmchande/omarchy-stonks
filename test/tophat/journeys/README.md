# Stonks' feature map

What a user does with Stonks, one file per feature, each with the journey
that drives it in the tophat's nested session (`test/tophat.sh`) through
real keys and pointer and keeps what it saw. Read this index, then the
feature's file, before checking a change that touches it.

## Running a journey

    test/tophat/journeys/ranges.sh [--slow SECONDS] [--zone ZONE] REF

- REF is a committed branch or commit. The journey starts the nested session
  on it, drives the whole journey, stops the session, and prints its evidence
  folder, `~/Work/temporary/tophat/journeys/NAME/TIME-COMMIT` (`JOURNEY_OUT`
  names another). The folder outlives the session.
- The session shows nothing on your desktop and needs no screen. One runs
  per checkout at a time; to run two refs at once, run them from two
  worktrees.
- `--slow 3` for anything fetched, as on a weak hotspot.
- Its last line is `result: PASS`, `FAIL N`, or `INCOMPLETE: N steps
  unreachable`. Only PASS is a pass.

## Evidence

- `steps.log`: each step, the words the named controls showed after it
  (`periodLine: 1Y 243.42 348.36 START 258.45 VOL 12.0B`), the sounds
  Stonks asked for, and PASS or FAIL for each check. Read it first.
- `NN-NAME.png`: the nested output after step NN; `NN-NAME.popup.png`: the
  popup's columns of it, the one to read.
- `NN-NAME.json` and `data.final.json`: the data file as Stonks wrote it.
- `sounds.log`: every sound asked of the stand-in `pw-play`, with its file.
- `silence.log`: each stream of silence the stand-in `pw-cat` held, "start MS"
  and "stopped MS".
- `shell.log`, `stop.log`: the nested shell's log and the session's stop.

## Driving conventions

- Every journey starts from the demo watchlist (`test/tophat/demo.json`):
  All holds AAPL, JNJ, SPY, ^GSPC, BTC-USD, SHEL.L, and 7203.T; US holds
  the first four; AAPL is featured; the range is 1D.
- Keys go through `test/tophat.sh key`, the pointer through `move`, `click`,
  and `scroll`. Nothing calls into Stonks to act.
- A pointer step finds its control by the QML `objectName` through Stonks'
  locator (`Locator.qml`, `test/tophat.sh shell grvc.stonks.tophat where
  NAME`), which loads only in the nested session. A commit from before the
  locator has none: its pointer steps report SKIP, never PASS, and its key
  steps still run, so an old commit's evidence still compares.
- A check waits on what the screen or the data file says. The short fixed
  pauses only let motion (160 to 320 ms) finish before a shot.
- Data is live: prices, clocks, and the market's phase differ between runs.
  Compare what is shown, not the values.

## Comparing before and after

To check a change, run its features' journeys on the commit before it and on
the change, then compare the two folders step by step: `steps.log` side by
side, then the popup shots of the same steps. Every difference is either one
the change asked for or a finding. A feature that disappeared shows as words
or a control present before and gone after.

## Features

- [Scrubbing the day](scrub.md): `scrub.sh`. Keys and pointer, what follows
  the scrub, its chimes, and each way it ends.
- [Ranges and the lines under the chart](ranges.md): `ranges.sh`. Every range
  by key, the lines and marks on each, a click and a wheel notch, and the
  range kept.
- [Adding, removing, and putting back](lists.md): `lists.sh`. Search by key
  and footer, the ×, Delete and its question, the row's menu, Ctrl+Z, and
  PUT BACK.
- [The unit sign](unit.md): `unit.sh`. %, ±, and since the open by `c`, the
  sign, and the change beside the price.
- [Saving](saving.md): `saving.sh`. Every change written at once, a failed
  save said and retried, and what was saved shown again.

## Keeping the map

A change that adds, moves, or removes a way to reach a feature, or what it
shows, updates that feature's file and journey in the same pull request. A
journey that can't reach a precondition fails with the reason, and the
reason goes in the feature's Gotchas; it is never weakened to pass.
