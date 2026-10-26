# The update

A user of an older release learns of a newer one in the footer and updates. From 1.1.0 the footer offers "Update to …" at its right end every time the popup or window opens. A click on it, or `Shift+U`, runs `omarchy plugin update grvc.stonks` in a terminal. Once the update is on disk, the footer says "Updated to … · click to restart the shell". The restarted shell then runs the release, with the user's lists and settings as they were. 1.0.4 said it instead as a note in the add's place, for 5 seconds, once a day.

## Sub-features

- `update-offer`: a newer Stonks on GitHub's main is offered in the footer.
- `update-terminal`: the click runs the update in a terminal, where Omarchy shows the diff and asks before it moves the clone.
- `update-restart`: once the update is on disk, the footer's notice restarts the shell.
- `update-kept`: the restarted release keeps every value the data file held.

## How to get to it (user POV)

- Open the popup or the window while a newer Stonks is out, and click the footer's offer, or press `Shift+U`.
- Answer Omarchy's question in the terminal.
- Open Stonks again and click the footer's restart notice, or press `Shift+U`.

## Driving it with test/tophat

Journey: `test/tophat/journeys/update.sh [--update-from OLD] REF`. OLD defaults to the last release tag before REF. `test/review.sh` runs it on HEAD before a release.

Preconditions: `test/tophat.sh start --update-from OLD REF`. OLD is installed as a git clone of a stand-in GitHub in the run folder, with the data file OLD saved (`test/data-files/VERSION.json`). GitHub's main is REF, or a release commit on it when REF names no newer version. Only the session's curl answers main's manifest. The update's terminal opens as foot in the session. The restarted shell logs to the run's `shell.log`, never the journal.

- **The ask.** OLD asks GitHub for main's manifest (`release/asked`).
- **The note.** Open the popup. The footer is found by sight, since OLD has no locator. The pointer holds the note on it. Shots `02-note`, `02-note-held`.
- **The terminal.** Click the note. A terminal opens in a session of its own, noted in `joined`. `q` leaves the diff's pager and `y` answers Omarchy. The clone moves to main, whose manifest names the release. Return closes the terminal. Shots `03-terminal`, `03-question`, `03-updated`.
- **The restart.** Open the popup and click "Updated to … · click to restart the shell". A new shell comes up with a new process, running the release's locator. Shot `04-restart`.
- **Kept.** The key sheet's credit names the release, and every value of the installed data file is kept. Shot `05-restarted`; data file `05-after.json`.

## Gotchas

- OLD's note lasts 5 seconds unless the pointer is on it: the journey moves there before shooting.
- The terminal and what it runs leave the run's group, in a session the shell's detached start and the script's `setsid` make. `stop` ends the processes carrying the run's mark in that session (`joined`), and still fails on anything else that left.
- An update start alone lets the update's two `systemctl` calls (`omarchy restart shell`'s) through stop. Every other start still fails on them, and on uwsm-app, systemd-cat and logger.
