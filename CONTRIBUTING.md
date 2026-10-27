# Contributing to Stonks

Stonks is QML and plain JavaScript, with no build step. `AGENTS.md` lists
the rules a change is judged by.

## Run it

- Clone the repo, or your fork, into
  `~/.config/omarchy/plugins/grvc.stonks`. Then run
  `omarchy-shell shell rescanPlugins` and
  `omarchy plugin enable grvc.stonks center`. If Stonks is already
  installed, that folder is already a clone: work there, or run
  `omarchy plugin remove grvc.stonks` first.
- After a change, run `omarchy restart shell`. A hot reload can leave the
  old service running.
- To open the popup, run `omarchy-shell shell toggle grvc.stonks`. To open
  the window, run `omarchy-shell grvc.stonks openWindow '{"symbol":"AAPL"}'`.
- QML errors show in `journalctl --user -t omarchy-shell -f`.

## Test it

- `test/all.sh` runs every check a pull request needs. It takes about a
  minute and a half, on a machine with Omarchy and a Wayland session. Its
  last line must be `ALL PASS`.
- Most checks replay saved answers from Yahoo and Robinhood. These stay
  private, since the sites' terms forbid republishing them. Without them,
  those checks skip and the run ends `PASSED, N SKIPPED`. The maintainer
  then runs them on your branch.
- A test of a rule goes in `test/model.test.js`, which every clone runs, or
  in `test/saved.test.js` if it needs a saved answer. A test of a flow goes
  in the harness that walks it, `test/qml/NAME.qml`.
- While you work, run just the checks for what you change, side by side,
  with `test/all.sh NAME…`. Name a harness as its `test/qml/NAME.sh` is
  named, and a quick check by its own name, as in
  `test/all.sh lists keys unit`. A wrong name lists the names. Such a run
  ends `PASSED ONLY` and the names, never `ALL PASS`, so run the whole of
  `test/all.sh` before a pull request. Render the states you change, as in
  `test/qml/render.sh 'popup-lists-*'`.
- `test/review.sh` lists every picture your change moved. The maintainer
  runs it on a visible change.

## Pull requests

- Fixes are welcome. For a new feature or a new look, open an issue first,
  since Stonks' product rules turn many ideas down.
- Branch from `dev` and target `dev`, since `main` is what users install.
  Leave the version in `manifest.json` alone.
- Before you open one, rebase onto `dev` and run `test/all.sh`. In the
  description, say what you ran, what you saw, and what you couldn't
  check. Leave out anyone's lists, screens, and home paths. Commit no
  screenshots, since every install clones every branch.
- cubic, an AI reviewer, comments on every pull request. Fix what holds up,
  and say why when a finding doesn't.
- Report a security problem privately, through the Security tab.

## Releases

A maintainer releases from `dev`.

1. Audit the build one way at a time: by mouse alone, by keys alone, as a
   first run, on a slow network, at text size 16 on a short screen, with
   150 symbols in 12 lists, and with every kind of listing at its odd
   hours. Fix or file what each finds.
2. Someone who didn't build them reads every change since the last release
   that runs a command, touches a file, fetches, or shows fetched text.
   They treat every answer and every other account as hostile, and check
   `WHAT-IT-RUNS.md` against the code.
3. Bump the version in `manifest.json` in a release commit on `dev`. If the
   README's pictures should change, render them with `test/qml/readme.sh`.
4. Run `STONKS_RENDER_BASE=vLAST test/review.sh --fresh` on that commit. It
   must end `ALL PASS`, and the marketplace's security scan must find
   nothing.
5. Run `git push origin dev:main`, tag `vX.Y.Z`, and publish the release
   notes. They say what the release changes for you, then how to update,
   then give a line for each change you'll notice, written as the Words
   section of `AGENTS.md` says.
6. File the marketplace's verify form with `main`'s commit. Keep `main`
   still until the marketplace publishes it, and answer its maintainer
   within seven days.
