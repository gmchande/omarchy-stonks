import QtQuick
import Quickshell.Io
// Stonks' files are its owner's alone: the data file, everything it writes
// in its cache, and the cache's own folder lose every permission of the
// group's and others' (`chmod go=`, 0600 files and a 0700 folder), each as
// it is first written each run (`keep`). A file keeps its mode through each
// later atomic write (Qt's QSaveFile copies it over), so once a run is
// enough, and a file an older build left readable to every account becomes
// the owner's on its next write. Quickshell writes a new file, and makes a
// missing folder, as the shell's umask has it, 0644 and 0755, so a new one
// is readable to others for the moment until this runs.
Item {
  id: root

  // The paths made owner-only this run, and those waiting for `chmod`.
  property var kept: ({})
  property var owed: []
  property var changing: []

  function keep(paths) {
    var fresh = paths.filter(function(path) { return !!path && root.kept[path] !== true })
    if (fresh.length === 0) return
    fresh.forEach(function(path) { root.kept[path] = true })
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
    id: chmod
    command: ["chmod", "go=", "--"].concat(root.changing)
    onExited: root.next()
  }
}
