import QtQuick
import Quickshell.Io
import "Release.js" as Release

// The plugin's own version. `omarchy plugin update` moves the plugin's files
// under a service the shell keeps loaded, which runs the code it started with
// until the shell restarts. The manifest is read as the service starts, as
// it changes, and again as a surface opens (`check`), where the notice
// shows, so no missed file event can hide it; a read that catches it half
// written goes again shortly (`takeManifest`). While it names a version
// other than the running one, a downgrade too, `newVersion` names it, and
// `restart()` restarts the shell. While main names a newer one than the
// running one (`mainVersion`, the service's, from GitHub),
// `releasedVersion` names it, which every surface offers until it's on
// disk, and `update()` runs the update in a terminal, where Omarchy shows
// what changes and asks. Once the update has moved the files, the terminal
// asks for the restart (`restartForUpdate`). An update run anywhere else
// leaves the restart to the notice.
Item {
  id: root

  // The version this code is, as the manifest said when it was first read;
  // "" until a manifest naming one has been.
  property string runningVersion: ""
  // The manifest's version when it is not the running one; "" otherwise.
  property string newVersion: ""
  // The version on main, "" until GitHub has named one.
  property string mainVersion: ""
  readonly property string releasedVersion: Release.isNewer(mainVersion, runningVersion) ? mainVersion : ""
  // A change Stonks hasn't saved, which a restart would lose (the
  // service's, as the footer says it).
  property bool changesUnsaved: false

  // A read asked for, by a surface opening or the file changing: its own
  // few reads again, whatever an earlier one used.
  function check() {
    reread.tries = 0
    readManifest()
  }

  function readManifest() {
    manifest.reload()
    takeManifest(manifest.text())
  }

  // A manifest that is missing or doesn't parse, half written by git, or
  // that names no version changes nothing, and is read again shortly, a few
  // times: the write it caught can end in the moment the shell's watch on
  // the file is being set up again, and send no event of its own.
  function takeManifest(text) {
    var version = ""
    try { version = String(JSON.parse(text).version || "") } catch (e) {}
    if (version === "") {
      if (reread.tries < 4) {
        reread.tries++
        reread.restart()
      }
      return
    }
    if (runningVersion === "") runningVersion = version
    newVersion = version !== runningVersion ? version : ""
  }

  // Detached, so it outlives the shell it stops. While the session is
  // locked the command refuses, and the notice stays for a later click.
  function restart() {
    restartShell.startDetached()
  }

  // The update's terminal asks once the update has moved Stonks' files: the
  // shell restarts, unless a change is unsaved then, and the notice waits
  // for the save. The answer is what the terminal shows.
  function restartForUpdate() {
    if (changesUnsaved)
      return "The shell didn't restart: Stonks has changes it hasn't saved, which a restart would lose. Once they're saved, click Stonks' footer to restart."
    restart()
    return "Restarting the shell…"
  }

  // Detached, so the terminal stays whatever the shell does meanwhile, and
  // so Stonks can't wait on it: the terminal's own shell asks for the
  // restart, only when the update exits 0 and the clone's last move is this
  // run's fast-forward, which git names after GIT_REFLOG_ACTION. A no, an
  // "up to date" and a failed fetch move nothing, a rolled-back validation
  // moves it again, and so does another update that lands meanwhile, which
  // leaves its restart to the notice. Omarchy has rescanned the plugins by
  // its exit. The launcher joins its arguments into a `bash -c` script, so
  // the last one is shell.
  function update() {
    updatePlugin.startDetached()
  }

  Component.onCompleted: takeManifest(manifest.text())

  // Read when asked, and whole: `text()` waits for the read. Read again as
  // it changes, so an update run from a surface that stays open, the
  // window, says the restart's notice there at once.
  FileView {
    id: manifest
    path: Qt.resolvedUrl("manifest.json")
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.check()
  }

  Timer {
    id: reread
    property int tries: 0
    interval: 250
    onTriggered: root.readManifest()
  }

  Process {
    id: restartShell
    command: ["omarchy", "restart", "shell"]
  }

  Process {
    id: updatePlugin
    command: ["omarchy", "launch", "floating", "terminal", "with", "presentation",
      "export GIT_REFLOG_ACTION=\"grvc.stonks update $EPOCHREALTIME\"; omarchy plugin update grvc.stonks"
      + " && [[ $(git -C \"$HOME/.config/omarchy/plugins/grvc.stonks\" reflog -1 --format=%gs) == \"$GIT_REFLOG_ACTION: Fast-forward\" ]]"
      + " && omarchy-shell grvc.stonks restartForUpdate"]
  }
}
