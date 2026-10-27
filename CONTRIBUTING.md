# Contributing to Stonks

A watchlist for the Omarchy shell: a bar pill, a popup with a day chart you
can scrub, and a tiled window that works with the pill turned off. It is QML
and plain JavaScript, with no build step: shell plugins must be QML, and the
shell already ships the UI kit, theme tokens, and popup machinery.

Every file opens with a comment saying what it owns and why. Read that before
changing it. This page holds only what the code can't tell you.

Fixes are welcome. For a new feature or a change to how something looks, open
an issue first: Stonks' product rules, in `AGENTS.md`, turn many ideas down,
and an issue saves building one that won't merge.

## Run it

- Clone the repo, or your fork, into
  `~/.config/omarchy/plugins/grvc.stonks`, then
  `omarchy-shell shell rescanPlugins` and
  `omarchy plugin enable grvc.stonks center`.
- After a change, run `omarchy restart shell`. A hot reload isn't enough: the
  service stays loaded and can keep answering with the old code.
- If Stonks is installed, that folder is already its clone: work there, or
  run `omarchy plugin remove grvc.stonks` first.
- The popup: `omarchy-shell shell toggle grvc.stonks`. The window:
  `omarchy-shell grvc.stonks openWindow '{}'`, or with a payload such as
  `'{"symbol":"AAPL","range":"1Y"}'`.
- QML errors go to the shell's log: `journalctl --user -t omarchy-shell -f`.

## Verify it

- `test/all.sh` runs the checks a pull request needs: every `*.test.js`
  (`test/unit.sh` finds them), the source boundaries, QML lint against the
  installed shell, the manifest and launcher, and the flow harnesses, which
  drive the real service and surfaces with real keys and pointer. It needs
  Omarchy installed and a Wayland session. A second run on the same machine
  waits for the first to end. With the saved answers it takes about 1 min
  50 s, and its last line must be `ALL PASS`. A run on a clean tree is
  recorded against it (`test/ran.sh`), a failed one with the steps that
  failed, and neither suite runs a tree that already passed, until a
  package changes; `--again` runs it anyway, as when chasing a flaky test.
- A run's work folders (renders, temporary homes) are on disk, in
  `~/.cache/stonks-test` (`STONKS_TEST_TMP` names another), never in `/tmp`,
  which can be a tmpfs in memory. Each run removes the ones it made, however
  it ends. Only a Quickshell's runtime folder stays in `/tmp`, because its
  sockets need a short path; it holds links, sockets, and a log.
- Most harnesses replay saved Yahoo and Robinhood answers, and the rules'
  tests in `test/saved.test.js` read them. They are private: their terms
  don't allow republishing them. On a clone without them, those checks skip,
  and the run takes under 10 seconds and ends `PASSED, N SKIPPED`. The
  maintainer runs them on your branch.
- GitHub runs the checks a fresh clone can on every push and pull request to
  `dev` and `main` (`.github/workflows/fresh-clone.yml`).
- While you work, run `test/touched.sh`: it runs the steps of both suites,
  and the journeys, that your diff from `dev` can reach, and says what it
  left out and why. A change to a file most of Stonks loads, such as
  `StonksBody.qml`, reaches nearly every check. For one area alone,
  `bash test/qml/lists.sh` runs its harness and
  `test/qml/render.sh 'popup-lists-*'` renders the states you name.
- A test checks what Stonks does: what it fetches, saves, and says, and what
  a key or a click changes. It never checks a picture, a position, or a
  timing. How Stonks looks and moves is the maintainer's to review, on your
  branch, with `test/review.sh`, which lists every picture your change
  moved.
- Tests are few and end to end. A new behaviour gets a step in a flow harness
  under `test/qml/` that drives the real service and surfaces with real keys
  and pointer. `bun test` is only for pure data rules, such as parsers and
  calendars.
- Before adding a test, name what a user would see break. A bug fix's test
  fails on the code before the fix.
- Wait on events or counts, never on fixed sleeps: a wait on time passes
  alone and fails beside other harnesses. A step that fails without a cause
  is fixed or deleted the day it's seen, never rerun past.
- A new key goes in the README's table, which `test/qml/keys.sh` presses.
- Check a change to what a chart, row, or figure shows on every kind of
  listing: a busy US stock, a thin one, an ETF, an index, a cryptocurrency,
  and a non-US listing.
- Each `test/data-files/VERSION.json` is a data file as that release saved
  it. Every version must keep loading each with nothing lost
  (`test/qml/data-files.sh`). A new shape of the file adds its release's own
  file beside them (`test/qml/data-files.sh write VERSION`), and never edits
  one.
- Before a pull request, use your change the way a user would: open the popup
  from the pill, add a symbol through search, switch lists, remove and undo,
  show a row's chart, change the range and the look, and use the window.
- `test/tophat.sh start REF` runs a commit in a nested Hyprland that shows
  nothing on your desktop: Stonks runs on an invisible 1416x850 screen inside
  it, with a demo watchlist, its own home and session bus, and the shell's
  services that reach your session turned off. `key`, `click`, `shot`,
  `record` and the rest drive and capture it, and `stop` fails if the run
  put a window on your desktop, crashed, or reached your session. Each
  checkout runs one session at a time, and sessions from different checkouts
  run side by side. It moves like your desktop: the session takes its
  animations from Omarchy's look'n'feel files, yours included. Each `start`
  removes the run folders in `~/Work/temporary/tophat/` that are more than a
  day old and not in use. The commands are listed at the top of the file.
- `test/tophat/journeys/` is the feature map: what a user does with each
  feature, and a script that drives it in that session with real keys and
  pointer and keeps what it saw. Run the journeys of the features your
  change touches, on the commit before it and on your branch, and compare
  the two (its `README.md`). A change to how a feature is reached or what it
  shows updates its entry.

## Layout

- `manifest.json`: the plugin's id, kinds, and the pill's settings.
- `Plugin.qml`: the service entry. It composes `Service.qml`, the one data
  owner, with the theme's colours, the version watch, the window's host, and
  the IPC target. In the tophat's nested session alone it adds
  `Locator.qml`, which says where a named control is, for the journeys'
  clicks.
- `BarWidget.qml` is the pill and owns `Panel.qml`, the popup. `App.qml` is
  the window. Both surfaces show `StonksBody.qml`.
- The feeds (`*Feed.qml`) and search's lookup are the only parts that fetch,
  each through its host's `Gate.qml`. The rule files (`*.js`) are pure
  functions, one concern each, with no drawing and no clock.
- `calendars.json` holds the exchange calendars, each good through its
  `validThrough` date: renew one before it passes, or the header says the
  schedule is unavailable.
- `share/` holds the optional launcher entry and icon. `test/boundaries.sh`
  checks which files may run a command, touch a file, or name an endpoint.

## Branches and pull requests

- Work happens on `dev`. Users get `main`: `omarchy plugin add` checks it out
  and `omarchy plugin update` moves to it, so `main` moves only at a release.
- Start each change on a branch named for it, from `dev`. A pull request
  targets `dev`. One built on another unmerged branch targets that branch and
  says so.
- Rebase onto the base before the final `test/all.sh`. Where tests conflict,
  keep the base's rules and repairs. Open the pull request once it passes.
  Its body says what you ran and what you saw, in words, and what you
  couldn't check, and names no one's lists, screens, or home paths.
- Commit no screenshots or large files beyond the README's own pictures:
  every install clones every branch.
- An AI reviewer (cubic) comments on every pull request: fix what holds up,
  and say why when a finding doesn't.
- Leave `manifest.json`'s version alone.
- Report a security problem privately, through the repository's Security
  tab, not in an issue: Stonks runs unsandboxed inside the shell.

## Releases

A maintainer releases from `dev`. The update notice watches the version, so
every release bumps it.

1. Audit the build one lens at a time: by mouse alone, by keys alone, a
   first run, a slow network (`test/tophat.sh start --slow 3`: every wait
   says what's coming, and nothing looks frozen), text size 16 on a short
   screen, 150 symbols in 12 lists, every kind of listing at its odd hours,
   and every render against the last release's. Fix or file what each
   finds.
2. Review it as the marketplace will. A reviewer who didn't build them
   reads every change since the last release that runs a command, reads or
   writes a file, fetches, or shows fetched text, taking Yahoo's, Robinhood's
   and GitHub's answers, and other accounts on the computer, as hostile.
   Every list read from an answer is a real array within a budget, its
   numbers finite and its strings bounded. Every process has a time limit,
   and every output kept in the shell a byte cap. No private text goes in a
   process's arguments, fetched text shows as plain text, and nothing is
   written where other accounts can read it. "What it runs" and "Files it
   writes" match the code. Each problem comes with the answer, file or
   command that shows it, and is fixed before the release.
3. Bump `manifest.json`'s version in a release commit on `dev`. When what
   the README's pictures show has changed, render them again with
   `test/qml/readme.sh` in that commit.
4. Run `test/review.sh --fresh` on the release commit, with
   `STONKS_RENDER_BASE` set to the last release's tag so its render diff
   shows every picture the release moved: the renders, layout, motion,
   the long list, and the README pictures run only there.
   `--fresh` draws every picture rather than reuse a set an earlier run
   kept, since this run has to catch a change from outside the repo. Its
   last line must be `ALL PASS`. The marketplace's own security scan passes
   on it with nothing to review.
5. Fast-forward `main` to it: `git push origin dev:main`.
6. Tag it (`vX.Y.Z`) and publish release notes, written as `AGENTS.md`'s
   Words says.
7. File the Omarchy plugin marketplace's verify form with `main`'s new
   commit. Until then the listing says Unverified. Keep `main` still until
   the marketplace publishes it, and answer its maintainer within seven
   days.

## Agents

An agent can write your change, but you're its author: read the diff and be
able to explain every line.

`AGENTS.md` is public, and an agent working in this repo reads it. Keep your
own machine's rules in `AGENTS.local.md`, which git ignores, as it does
`CLAUDE.md` and other agent files. To copy it into each new worktree, turn on
the hook once in your main checkout:
`git config core.hooksPath test/hooks`.
