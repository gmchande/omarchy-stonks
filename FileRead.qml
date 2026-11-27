pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "Commands.js" as Commands
// Reads a file Stonks keeps, or a setting it reads, outside the shell's
// thread (`Commands.readSaved`): a regular file only, up to `cap` bytes.
// `done(answer)` hears what it held (`Commands.readSavedFile`). A read asked
// while one is out ends that one unheard. The Process and its StdioCollector
// live in a Loader so large file buffers (such as quotes.json) are freed as
// soon as the read finishes.
Item {
  id: root

  signal done(var answer)

  // { path, cap } of the read out, and of the one asked after it.
  property var current: null
  property var next: null
  property int code: -1
  // A read is out: `done` is still to come.
  readonly property bool out: current !== null
  readonly property Process reading: procLoader.item as Process

  function read(path, cap) {
    root.next = { path: path, cap: cap }
    if (reading && reading.running) reading.running = false
    else root.start()
  }

  function start() {
    root.current = root.next
    root.next = null
    root.code = -1
    if (reading) reading.running = true
  }

  Loader {
    id: procLoader
    active: root.current !== null
    sourceComponent: Process {
      id: proc
      command: root.current ? Commands.readSaved(root.current.path, root.current.cap) : []
      stdout: StdioCollector { id: held }
      onExited: function(code) { root.code = code }
      // A command that fails to start ends with no exit.
      onRunningChanged: {
        if (running) return
        var ran = root.current
        if (root.next) return root.start()
        var answer = ran ? Commands.readSavedFile(root.code, held.data.byteLength, held.text, ran.cap) : null
        root.current = null
        if (answer) root.done(answer)
      }
    }
  }
}
