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
// back, keeps that mode through each atomic write. A data file new on this
// machine is 0644 for the moment between its first write and the chmod.
Item {
  id: root

  readonly property string folder: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/grvc.stonks"
  property bool made: false
  // The writes waiting for the folder, by path.
  property var held: ({})
  // The paths waiting for `chmod`, and those it is changing now.
  property var owed: []
  property var changing: []

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
    command: ["sh", "-c", "umask 077 && mkdir -p -- \"$1\" && chmod go= -- \"$1\"", "sh", root.folder]
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
    command: ["chmod", "go=", "--"].concat(root.changing)
    onExited: root.next()
  }
}
