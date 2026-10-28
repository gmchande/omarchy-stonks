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
// what changes and asks, then restarts the shell once it has moved the
// files, unless a restart would lose changes. An update run anywhere else
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

  // Detached, so the terminal stays whatever the shell does meanwhile, and
  // so Stonks can't wait on it: with `restart`, the terminal's own shell
  // restarts the shell, only when the update exits 0 with the clone's HEAD
  // moved. A no, an "up to date", a failed fetch and a rolled-back
  // validation leave HEAD where it was or exit 1, and Omarchy has rescanned
  // the plugins by its exit. The launcher joins its arguments into a
  // `bash -c` script, so the last one is shell. While the session is locked
  // the restart refuses there. Without `restart`, for changes a restart
  // would lose, the update runs alone. Either way the notice stays for a
  // later click.
  function update(restart) {
    if (restart) updateAndRestart.startDetached()
    else updatePlugin.startDetached()
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
    command: ["omarchy", "launch", "floating", "terminal", "with", "presentation", "omarchy", "plugin", "update", "grvc.stonks"]
  }

  Process {
    id: updateAndRestart
    command: ["omarchy", "launch", "floating", "terminal", "with", "presentation",
      "p=$HOME/.config/omarchy/plugins/grvc.stonks; was=$(git -C \"$p\" rev-parse HEAD);"
      + " omarchy plugin update grvc.stonks && [[ $(git -C \"$p\" rev-parse HEAD) != \"$was\" ]]"
      + " && echo 'Restarting the shell…' && omarchy restart shell"]
  }
}
