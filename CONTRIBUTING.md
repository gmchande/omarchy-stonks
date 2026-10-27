# Contributing to Stonks

Stonks is QML and plain JavaScript, with no build step. The rules a change
is judged by are in `AGENTS.md`.

## Run it

- Clone the repo, or your fork, into
  `~/.config/omarchy/plugins/grvc.stonks`, then run
  `omarchy-shell shell rescanPlugins` and
  `omarchy plugin enable grvc.stonks center`. If Stonks is installed, that
  folder is already its clone: work there, or run
  `omarchy plugin remove grvc.stonks` first.
- After a change, run `omarchy restart shell`: a hot reload can leave the
  old service answering.
- The popup: `omarchy-shell shell toggle grvc.stonks`. The window:
  `omarchy-shell grvc.stonks openWindow '{"symbol":"AAPL"}'`.
- QML errors go to `journalctl --user -t omarchy-shell -f`.

## Test it

- `test/all.sh` runs every check a pull request needs, in about a minute
  and a half, on a machine with Omarchy and a Wayland session. Its last
  line must be `ALL PASS`.
- Most checks replay saved Yahoo and Robinhood answers, which stay private
  because their terms forbid republishing them. Without them those checks
  skip, the run ends `PASSED, N SKIPPED`, and the maintainer runs them on
  your branch.
- A rule's test goes in `test/model.test.js`, which every clone runs, or in
  `test/saved.test.js` when it needs a saved answer; a flow's goes in the
  harness that walks it, `test/qml/NAME.qml`.
- While you work, run the tests for what you change, such as
  `bun test ./test/model.test.js` or `bash test/qml/lists.sh`, and render
  the states you change, such as `test/qml/render.sh 'popup-lists-*'`.
- `test/review.sh` lists every picture your change moved. The maintainer
  runs it on a visible change.

## Pull requests

- Fixes are welcome. For a new feature or a new look, open an issue first:
  Stonks' product rules turn many ideas down.
- Branch from `dev` and target `dev`: `main` is what users install. Leave
  `manifest.json`'s version alone.
- Rebase onto `dev` and run `test/all.sh` before you open it. Its body says
  what you ran, what you saw, and what you couldn't check, and names no
  one's lists, screens, or home paths. Commit no screenshots: every install
  clones every branch.
- cubic, an AI reviewer, comments on every pull request: fix what holds up,
  and say why when a finding doesn't.
- Report a security problem privately, through the Security tab.

## Releases

A maintainer releases from `dev`.

1. Audit the build one lens at a time: mouse alone, keys alone, a first run,
   a slow network, text size 16 on a short screen, 150 symbols in 12 lists,
   every kind of listing at its odd hours. Fix or file what each finds.
2. Someone who didn't build them reads the changes since the last release
   that run a command, touch a file, fetch, or show fetched text, taking
   every answer and every other account as hostile, and checks the README's
   "What it runs" and "Files it writes" against the code.
3. Bump `manifest.json`'s version in a release commit on `dev`, and render
   the README's pictures with `test/qml/readme.sh` if they should change.
4. Run `STONKS_RENDER_BASE=vLAST test/review.sh --fresh` on it: `ALL PASS`,
   and the marketplace's security scan finds nothing.
5. `git push origin dev:main`, tag `vX.Y.Z`, and publish release notes: what
   the release changes for you, then how to update, then a line for each
   change you'll notice, written as `AGENTS.md`'s Words says.
6. File the marketplace's verify form with `main`'s commit, keep `main`
   still until it's published, and answer its maintainer within seven days.
