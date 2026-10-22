import QtQuick
import Quickshell.Io
// Stonks' files are its owner's alone. Its cache `folder` is made, or kept,
// 0700 as it starts (`made`, once that has worked), and its writers write
// nothing in it before, so a file new in it is never open to another
// account; where it can't be made private, nothing is written there. Each
// file Stonks writes, there or the data file, loses the group's and others'
// permissions as it is written (`keep`, `chmod go=`): Quickshell writes a
// new file as the shell's umask has it, 0644, and a file an older build
// left 0644, or a hand edit put back, keeps that mode through each atomic
// write. A data file new on this machine is 0644 for the moment between
// its first write and the chmod.
Item {
  id: root

  property string folder: ""
  property bool made: false
  // The paths waiting for `chmod`, and those it is changing now.
  property var owed: []
  property var changing: []

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

  Process {
    id: make
    running: root.folder !== ""
    command: ["sh", "-c", "umask 077 && mkdir -p -- \"$1\" && chmod go= -- \"$1\"", "sh", root.folder]
    onExited: function(code) {
      root.made = code === 0
      if (!root.made) console.warn("stonks: can't make " + root.folder + " yours alone; writing nothing there")
    }
  }

  Process {
    id: chmod
    command: ["chmod", "go=", "--"].concat(root.changing)
    onExited: root.next()
  }
}
