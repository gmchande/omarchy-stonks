# Contributing to Stonks

A watchlist for the Omarchy shell: a bar pill, a popup with a day chart you
can scrub, and a tiled window that works with the pill turned off. It is QML
and plain JavaScript, with no build step: shell plugins must be QML, and the
shell already ships the UI kit, theme tokens, and popup machinery.

Every file opens with a comment saying what it owns and why. Read that before
changing it. This page holds only what the code can't tell you.

Fixes are welcome. For a new feature or a change to how something looks, open
an issue first: Stonks' product rules turn many ideas down, and an issue saves
building one that won't merge.

## Simplicity

- Simple means untangled, not short: each piece does one job and can change on its own. Refuse state braided with time, one component knowing two concerns, a flag that couples two paths, a result that depends on hidden order.
- Leave the code simpler than you found it.
- No handling for cases this data and its users can't produce.
- Delete what nothing uses.
- Confirm a limit you blame on the shell in its code
  (`/usr/share/omarchy/shell/`) before designing around it.

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

- `test/all.sh` runs the checks a pull request needs: the pure rules, the
  source boundaries, QML lint against the installed shell, the manifest and
  launcher, and the flow harnesses, which drive the real service and
  surfaces with real keys and pointer. It needs Omarchy installed and a
  Wayland session. A second run on the same machine waits for the first to
  end. With the saved answers it takes about 2 min 20 s, and its last line
  must be `ALL PASS`.
- Most harnesses replay saved Yahoo and Robinhood answers, which are
  private: their terms don't allow republishing them. On a clone without
  them, those harnesses skip, and the run takes under 10 seconds and ends
  `PASSED, N SKIPPED`. The maintainer runs them on your branch.
- GitHub runs the checks a fresh clone can on every push and pull request to
  `dev` and `main` (`.github/workflows/fresh-clone.yml`).
- While you work, run the harness for the area you change, such as
  `bash test/qml/lists.sh`.
- A test checks what Stonks does: what it fetches, saves, and says, and what
  a key or a click changes. It never checks a picture, a position, or a
  timing. How Stonks looks and moves is the maintainer's to review, on your
  branch, with `test/review.sh`.
- Tests are few and end to end. A new behaviour gets a step in a flow harness
  under `test/qml/` that drives the real service and surfaces with real keys
  and pointer. `bun test` is only for pure data rules, such as parsers and
  calendars.
- Before adding a test, name what a user would see break. A bug fix's test
  fails on the code before the fix.
- Wait on events or counts, never on fixed sleeps: a wait on time passes
  alone and fails beside other harnesses.
- A new key goes in the README's table, which `test/qml/keys.sh` presses.
- Check a change to what a chart, row, or figure shows on every kind of
  listing: a busy US stock, a thin one, an ETF, an index, a cryptocurrency,
  and a non-US listing.
- `test/data-files/1.0.0.json` is a data file as 1.0.0 saved it. Every version
  must keep loading it with nothing lost (`test/qml/data-files.sh`). A new
  shape of the file adds its release's own file beside it, and never edits
  this one.
- Before a pull request, use your change the way a user would: open the popup
  from the pill, add a symbol through search, switch lists, remove and undo,
  show a row's chart, change the range and the look, and use the window.

## Layout

- `manifest.json`: the plugin's id, kinds, and the pill's settings.
- `Plugin.qml`: the service entry. It composes `Service.qml`, the one data
  owner, with the theme's colours, the version watch, the window's host, and
  the IPC target.
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

## Product rules

- **Data.** Quotes come from Yahoo's unofficial chart, spark, and search
  endpoints, and overnight prices from Robinhood's public price history, with
  no account or key. The README says so plainly, and nothing shows
  Robinhood's logo.
- **Only what's true.** Show what the source sent, never an adjustment,
  precision, or coverage it didn't. Leave out a figure that isn't known; never
  guess it. The headline price is Yahoo's regular-market quote, never the last
  chart bar. Only a failed or overdue refresh shows a "!".
- **Money.** No currency conversion: each listing in its own currency, with
  its code beside the exchange, as Apple's Stocks does.
- **Time.** An exchange's times are its own, with its zone named when it
  differs from the reader's. Never assume New York.
- **Colour.** Up is the theme's green and down its red (the shell's urgent),
  everywhere; never the accent, which in Omarchy means selected. Where a
  theme's green and red are no real pair (two greys, two greens, two blues)
  or the fainter is under 3:1 on a surface's ground, up and down there are
  Stonks' own pair for that ground, dark or light. Never adjust a theme's
  colours.
- **Calm.** Nothing moves when the look, range, list, order, or charted
  stock changes, except the footer for a list of another length: it rides
  the popup's easing edge, and sits one gap under a short list in the
  window.
- **Character.** Stonks has a few signs of life: the bull and the bear,
  their sleep while the market rests, the live dot's ripples, and the day's
  named moments, such as "Power hour". Each says something true and none
  cheers a number. They are part of the product, so a cleanup keeps them.
- **Fetching.** Stonks fetches each listing only as often as its market can
  move, fetches nothing while every screen is off, and leaves a site that
  refuses it alone for a while.
- **Lists.** All holds every symbol, and named lists hold some of them. The
  data file at `~/.config/omarchy/grvc.stonks.json` keeps its version-1 keys,
  so an older build still reads All, and one that can't be read is never
  written over. When Stonks writes the file, it keeps every key it doesn't
  know, so a newer build's settings survive an older one.
- **Mouse and keys.** Every flow works by mouse alone and by keys alone, and
  anything that looks clickable acts when clicked. A button says only what it
  does, and no word on screen names a key: the keys are on the `?` sheet.
- **Tooltips.** Few: a control has one only where it can't say what it does
  by itself, and only where the tip covers nothing.
- **Text.** Every character drawn is one JetBrainsMono Nerd Font has.

## Words

The README, the release notes, the manifest, the forms, and every word on
screen are written for one reader who has never seen Stonks and has thirty
seconds to give it.

- Open with what Stonks does for the reader, in a sentence with a verb. The
  second sentence says something the first didn't.
- Change the words with the code, and promise nothing it doesn't do.
- Use the reader's words, not the code's: "the stock you last looked at",
  not "the featured symbol"; "show the selected row's chart", not "feature
  the cursor row".
- One name for each thing, the same on screen and in the docs: the pill,
  the popup, the window, a row, a list, All, smooth and retro.
- Present tense and active verbs, with Stonks or "you" doing something:
  "Stonks keeps the lists it has", not "the lists are kept". British
  spelling: colour, centre.
- Specific over general: a number, a time, the words the reader will see.
  "150 symbols refresh every minute", not "long lists stay fast".
- Say it once. Cut "very", "just", "simply", "quite", and any sentence that
  repeats the one before.
- Trouble starts from the words on screen, then says why, then what to do.
- Release notes open with a sentence on what the release changes for you,
  then the update commands, then a line per change saying what you'll
  notice. Add a section headed by who must act only when someone must.

## Style

- QML: value-in components, `readonly property` for derived state, a
  `Process` for every side effect, animations at the shell's 160 ms
  OutCubic.
- Secondary text is the foreground mixed toward its ground (`Tones.dim`),
  never `Qt.darker`, which gets louder on a light theme.
- Read Omarchy's colours as `Commons.Color`, after
  `import qs.Commons as Commons`. A plain `Color` names Qt 6.12's own
  `Color` type, not Omarchy's.
- Rule files: `.pragma library` first, so QML loads each once rather than
  once per row; top-level functions only, read through `.import`, imports
  one way with no cycles.

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

1. Walk the build in a nested session on a slow network
   (`test/tophat.sh start --slow 3`): every wait says what's coming, and
   nothing looks frozen.
2. Bump `manifest.json`'s version in a release commit on `dev`. When what
   the README's pictures show has changed, render them again with
   `test/qml/readme.sh` in that commit.
3. Run `test/review.sh` on the release commit: the renders, layout, motion,
   the long list, and the README pictures run only there. Its last line must
   be `ALL PASS`.
4. Fast-forward `main` to it: `git push origin dev:main`.
5. Tag it (`vX.Y.Z`) and publish release notes, written as Words says.
6. File the Omarchy plugin marketplace's verify form with `main`'s new
   commit. Until then the listing says Unverified.

## Agents

An agent can write your change, but you're its author: read the diff and be
able to explain every line.

`AGENTS.md`, `CLAUDE.md`, and other agent files are ignored: an installed copy
would hand them to the user's own coding agents, and the marketplace's review
refuses them. Keep your own local `AGENTS.md` and have it point here. To copy
it into each new worktree, turn on the hook once in your main checkout:
`git config core.hooksPath test/hooks`.
