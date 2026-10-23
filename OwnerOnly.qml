import QtQuick
import Quickshell
import Quickshell.Io
// Stonks' files are its owner's alone, and this is the one place that says
// how. The service makes one and hands it to whatever keeps a file in the
// cache (`folder`); nothing else writes there.
//
// The folder is made, or kept, 0700 as Stonks starts (`made`, once that has
// worked), and `write` writes nothing in it before: a write asked for sooner
// waits, the latest for each path, and lands once the folder is private, so
// a file new in it is never open to another account. Where the folder can't
// be made private, nothing is written there. Each file Stonks writes, in the
// cache or the data file (`keep`), loses the group's and others' permissions
// as it is written (`chmod go=`): Quickshell writes a new file as the shell's
// umask has it, 0644, and a file an older build left 0644, or a hand edit put
// back, keeps that mode through each atomic write. A data file that isn't
// there is made here instead (`create`), 0600 before it holds a byte, and
// each write after keeps that mode. Each command has 5 seconds.
Item {
  id: root

  readonly property string folder: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/grvc.stonks"
  property bool made: false
  // The writes waiting for the folder, by path.
  property var held: ({})
  // The paths waiting for `chmod`, and those it is changing now.
  property var owed: []
  property var changing: []
  // The file `create` is making, what it will hold, and who hears the end.
  property string creatingPath: ""
  property string creatingText: ""
  property var creatingDone: null
  property int createdCode: -1

  // Writes `data`, text or bytes, whole to `path` in the folder, by a
  // rename, so a reader of the last one keeps it; true once it is there,
  // false while it waits for the folder.
  function write(path, data) {
    if (!root.made) {
      root.held[path] = data
      return false
    }
    file.path = path
    if (typeof data === "string") file.setText(data)
    else file.setData(data)
    return true
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

  // Makes `path`, a file that isn't there, holding `text`, then calls
  // `done(true)`, or `done(false)` where it couldn't, a file there by then
  // included. The text is written whole to a file beside it that `mktemp`
  // makes 0600, which `ln` then puts under the name, never over a file
  // there: no other account can read it from its first byte, and no reader
  // sees it part written. The text goes in the command's environment,
  // which only its owner can read (/proc/PID/environ is 0400), never in its
  // arguments, which every account can, and it is there whole as the
  // command starts, so a shell that stops meanwhile can't cut it short. One
  // at a time: another asked for meanwhile isn't made.
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
    environment: ({ STONKS_TEXT: root.creatingText })
    onExited: function(code) { root.createdCode = code }
    // Heard as it ends, or as it fails to start, which says no exit.
    onRunningChanged: {
      if (creating.running || !root.creatingDone) return
      var done = root.creatingDone
      root.creatingDone = null
      done(root.createdCode === 0)
    }
  }
}
