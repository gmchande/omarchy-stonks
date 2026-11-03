import QtQuick
import Quickshell
import Quickshell.Io
// Keeps Stonks' files its owner's alone. Nothing is written in the cache
// folder until it is 0700; writes asked sooner wait, the latest per path.
// Quickshell writes a new file 0644, the shell's umask, and an atomic write
// keeps an old file's mode, so each written file gets `chmod go=`.
Item {
  id: root

  readonly property string folder: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/grvc.stonks"
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
  // mktemp makes the file 0600 and `ln` names it, never over a file there,
  // so no other account reads it and no reader sees it half written. The
  // text rides in the environment, whole as the command starts: a command
  // line is world-readable, /proc/PID/environ is 0400.
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

  Process {
    id: make
    running: true
    command: ["timeout", "5", "sh", "-c", "umask 077 && mkdir -p -- \"$1\" && chmod go= -- \"$1\"", "sh", root.folder]
    onExited: function(code) {
      root.made = code === 0
      if (!root.made) {
        console.warn("stonks: can't make " + root.folder + " yours alone; writing nothing there")
        return
      }
      var waiting = root.held
      root.held = ({})
      for (var path in waiting) root.write(path, waiting[path])
    }
  }

  Process {
    id: chmod
    command: ["timeout", "5", "chmod", "go=", "--"].concat(root.changing)
    onExited: root.next()
  }

  Process {
    id: creating
    command: ["timeout", "5", "sh", "-c", "umask 077 && tmp=$(mktemp -- \"$1.XXXXXX\") || exit 1\n"
      + "printf '%s' \"$STONKS_TEXT\" > \"$tmp\" && ln -- \"$tmp\" \"$1\"\n"
      + "code=$?\n"
      + "rm -f -- \"$tmp\"\n"
      + "exit $code", "sh", root.creatingPath]
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
