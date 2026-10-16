import QtQuick
import Quickshell.Io

// The plugin's own version. `omarchy plugin update` moves the plugin's files
// under a service the shell keeps loaded, which runs the code it started with
// until the shell restarts. The manifest is read as the service starts and
// again as a surface opens (`check`), where the notice shows, so no missed
// file event can hide it. While it names a version other than the running
// one, a downgrade too, `newVersion` names it, and `restart()` restarts the
// shell.
Item {
  id: root

  // The version this code is, as the manifest said when it was first read;
  // "" until a manifest naming one has been.
  property string runningVersion: ""
  // The manifest's version when it is not the running one; "" otherwise.
  property string newVersion: ""

  function check() {
    manifest.reload()
    takeManifest(manifest.text())
  }

  // A manifest that doesn't parse, half written by git, or that names no
  // version changes nothing.
  function takeManifest(text) {
    var version = ""
    try { version = String(JSON.parse(text).version || "") } catch (e) { return }
    if (version === "") return
    if (runningVersion === "") runningVersion = version
    newVersion = version !== runningVersion ? version : ""
  }

  // Detached, so it outlives the shell it stops. While the session is
  // locked the command refuses, and the notice stays for a later click.
  function restart() {
    restartShell.startDetached()
  }

  Component.onCompleted: takeManifest(manifest.text())

  // Read when asked, and whole: `text()` waits for the read.
  FileView {
    id: manifest
    path: Qt.resolvedUrl("manifest.json")
    blockAllReads: true
    printErrors: false
  }

  Process {
    id: restartShell
    command: ["omarchy", "restart", "shell"]
  }
}
