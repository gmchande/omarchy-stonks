import QtQuick
import Quickshell.Io
import "Commands.js" as Commands
// Reads a file Stonks keeps, or a setting it reads, outside the shell's
// thread (`Commands.readSaved`): a regular file only, up to `cap` bytes.
// `done(answer)` hears what it held (`Commands.readSavedFile`). A read asked
// while one is out ends that one unheard, and `drop()` ends it with nothing
// heard.
Item {
  id: root

  signal done(var answer)

  // { path, cap, dropped } of the read out, and of the one asked after it.
  property var current: null
  property var next: null
  property int code: -1

  function read(path, cap) {
    root.next = { path: path, cap: cap, dropped: false }
    if (reading.running) reading.running = false
    else root.start()
  }

  function drop() {
    root.next = null
    if (root.current) root.current.dropped = true
    reading.running = false
  }

  function start() {
    root.current = root.next
    root.next = null
    root.code = -1
    reading.running = true
  }

  Process {
    id: reading
    command: root.current ? Commands.readSaved(root.current.path, root.current.cap) : []
    stdout: StdioCollector { id: held }
    onExited: function(code) { root.code = code }
    // A command that fails to start ends with no exit.
    onRunningChanged: {
      if (running) return
      var ran = root.current
      if (root.next) return root.start()
      root.current = null
      if (!ran || ran.dropped) return
      root.done(Commands.readSavedFile(root.code, held.data.byteLength, held.text, ran.cap))
    }
  }
}
