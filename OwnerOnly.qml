import QtQuick
import Quickshell
import Quickshell.Io
import "Commands.js" as Commands
// Keeps Stonks' files its owner's alone. The cache folder is named for the
// plugin's id, and nothing is written in it until the id is known and it is
// 0700; writes asked sooner wait, the latest per path.
// Quickshell writes a new file 0644, the shell's umask, and an atomic write
// keeps an old file's mode, so each written file gets `chmod go=`.
Item {
  id: root

  // The plugin's id, the cache folder's name; "" until the manifest has
  // named it, and meanwhile there is no folder.
  property string pluginId: ""
  readonly property string folder: pluginId ? (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + pluginId : ""
  property bool made: false
  property var held: ({})
  property var owed: []
  property var changing: []
  property string creatingPath: ""
  property string creatingText: ""
  readonly property var creatingEnvironment: ({ STONKS_TEXT: root.creatingText })
  property var creatingDone: null
  property int createdCode: -1

  // With blockWrites, a failed save is heard before setText returns. Bytes
  // the same as the last write's are skipped: neither saved nor failed.
  property bool failed: false
  function write(path, data) {
    if (!root.made) {
      root.held[path] = data
      root.makeFolder()
      return false
    }
    file.path = path
    root.failed = false
    if (typeof data === "string") file.setText(data)
    else file.setData(data)
    return !root.failed
  }

  function keep(paths) {
    var fresh = paths.filter(function(path) { return !!path && root.owed.indexOf(path) < 0 })
    if (fresh.length === 0) return
    root.owed = root.owed.concat(fresh)
    root.next()
  }

  function next() {
    if (chmod.running || root.owed.length === 0) return
    root.changing = root.owed
    root.owed = []
    chmod.running = true
  }

  // Calls done(false) while another create is running, and where the file
  // couldn't be made, even if one is there by then.
  // No other account reads it, and no reader sees it half written
  // (`Commands.createPrivately`).
  function create(path, text, done) {
    if (creating.running || root.creatingDone) return done(false)
    root.creatingPath = path
    root.creatingText = text
    root.creatingDone = done
    root.createdCode = -1
    creating.running = true
  }

  FileView {
    id: file
    preload: false
    blockWrites: true
    atomicWrites: true
    onSaved: root.keep([file.path])
    onSaveFailed: root.failed = true
  }

  // The id comes once: as the service is made, or just after (`Plugin`).
  // The make starts a turn later, once its command names the folder. A make
  // that fails drops what waits, and the next write asks again.
  Component.onCompleted: if (root.folder !== "") Qt.callLater(root.makeFolder)
  onFolderChanged: if (root.folder !== "") Qt.callLater(root.makeFolder)
  function makeFolder() {
    if (root.folder === "" || make.running || root.made) return
    make.code = -1
    make.running = true
  }

  // Each read as `running` falls, since a command that fails to start
  // never exits.
  Process {
    id: make
    property int code: -1
    command: ["timeout", "-k", "1", "5", "sh", "-c", "umask 077 && mkdir -p -- \"$1\" && chmod go= -- \"$1\"", "sh", root.folder]
    onExited: function(code) { make.code = code }
    onRunningChanged: {
      if (running) return
      root.made = make.code === 0
      var waiting = root.held
      root.held = ({})
      if (!root.made) {
        console.warn("stonks: can't make " + root.folder + " yours alone; writing nothing there")
        return
      }
      for (var path in waiting) root.write(path, waiting[path])
    }
  }

  Process {
    id: chmod
    command: ["timeout", "-k", "1", "5", "chmod", "go=", "--"].concat(root.changing)
    onRunningChanged: if (!running) root.next()
  }

  Process {
    id: creating
    command: Commands.createPrivately(root.creatingPath)
    environment: root.creatingEnvironment
    onExited: function(code) { root.createdCode = code }
    // A process that fails to start ends with no exit.
    onRunningChanged: {
      if (creating.running || !root.creatingDone) return
      var done = root.creatingDone
      root.creatingDone = null
      done(root.createdCode === 0)
    }
  }
}
