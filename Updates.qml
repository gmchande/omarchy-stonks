import QtQuick
import Quickshell
import Quickshell.Io
import "Release.js" as Release

// `omarchy plugin update` moves the plugin's files, but the shell runs the
// code it started with until it restarts. The manifest is read again as a
// surface opens, so a missed file event can't hide the restart notice.
Item {
  id: root

  // The manifest's id (`Plugin`), which `omarchy plugin update` takes.
  property string pluginId: ""
  // `omarchy plugin update` takes only a folder holding its own clone, a
  // `.git` folder; a copy or a worktree it refuses. There the service never
  // asks GitHub for main's version, so no update is offered.
  property bool updatable: false
  // The manifest's version when first read: the code running.
  property string runningVersion: ""
  property string newVersion: ""
  property string mainVersion: ""
  readonly property string releasedVersion: Release.isNewer(mainVersion, runningVersion) ? mainVersion : ""

  // A fresh set of tries, whatever an earlier read used.
  function check() {
    reread.tries = 0
    readManifest()
  }

  function readManifest() {
    manifest.reload()
    takeManifest(manifest.text())
  }

  // Git's write can end while the shell sets its watch up again, sending no
  // event, so a manifest caught missing or cut off is read again shortly.
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
  // locked, Omarchy refuses the restart.
  function restart() {
    restartShell.startDetached()
  }

  // Detached, so the terminal outlives a restart. Omarchy shows what changes
  // and asks. A no, "up to date", a failed fetch and a rolled-back
  // validation leave HEAD where it was or exit 1, and Omarchy has rescanned
  // the plugins by its exit. The launcher joins its arguments into a
  // `bash -c` script, so the last one is shell code.
  function update(restart) {
    if (restart) updateAndRestart.startDetached()
    else updatePlugin.startDetached()
  }

  Component.onCompleted: takeManifest(manifest.text())

  // `text()` waits for the whole file.
  FileView {
    id: manifest
    path: Qt.resolvedUrl("manifest.json")
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.check()
  }

  FileView {
    path: root.pluginId ? Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId + "/.git/HEAD" : ""
    printErrors: false
    onLoaded: root.updatable = true
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
    command: ["omarchy", "launch", "floating", "terminal", "with", "presentation", "omarchy", "plugin", "update", root.pluginId]
  }

  Process {
    id: updateAndRestart
    command: ["omarchy", "launch", "floating", "terminal", "with", "presentation",
      "p=$HOME/.config/omarchy/plugins/" + root.pluginId + "; was=$(git -C \"$p\" rev-parse HEAD);"
      + " omarchy plugin update " + root.pluginId + " && [[ $(git -C \"$p\" rev-parse HEAD) != \"$was\" ]]"
      + " && echo 'Restarting the shell…' && omarchy restart shell"]
  }
}
