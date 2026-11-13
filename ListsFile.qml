import QtQuick
import Quickshell
import Quickshell.Io
import "Settings.js" as Settings
// The lists file, ~/.config/omarchy/<id>.json: read as the shell starts and
// whenever it changes, written on each change, and read back to be sure the
// write landed. A file that can't be read is never written over. It is read
// outside the shell's thread, and only a regular file of at most `cap`
// bytes is read (`FileRead`): one larger, or anything else there, can't be.
Item {
  id: root

  // The plugin's id, which names the file: "" until the shell hands it over.
  property string pluginId: ""
  // The keeper of Stonks' files (`OwnerOnly`), which makes a file its
  // owner's alone.
  property var files: null
  // What the file holds: the defaults until its first read, and what was
  // last asked of it where a write hasn't landed.
  property var fileSettings: Settings.fileSettings(null)
  // The first read is in: `fileSettings` is the file's, or the defaults.
  signal started()

  readonly property string path: pluginId ? Quickshell.env("HOME") + "/" + Settings.listsFile(pluginId) : ""
  // 128 KiB. A lists file of 150 stocks in 12 lists is 8 KB, and a new
  // file's text rides in one environment string, which Linux holds to 128
  // KiB (`OwnerOnly.create`).
  readonly property int cap: 131072
  property bool ready: false
  property bool unreadable: false
  // A change made while the file can't be read: only memory holds it.
  property bool editsUnsaved: false
  onUnreadableChanged: if (!unreadable) editsUnsaved = false
  // A save didn't land: Quickshell said so, or the read-back still held the
  // text before it (`takesRead`). The next save writes everything in memory.
  property bool saveFailed: false
  signal saveChecked(bool saved)

  function persist(values, settles) {
    root.store(Settings.fileSettings(Object.assign({}, root.fileSettings, values)), settles)
  }

  function save(next) {
    if (!Settings.settingsEqual(next, root.fileSettings)) root.store(next)
  }

  function store(next, settles) {
    var changed = !Settings.settingsEqual(next, root.fileSettings)
    root.fileSettings = next
    if (!root.ready) return
    if (root.unreadable) {
      if (changed) root.editsUnsaved = true
      return
    }
    if (settles) {
      settleWrite.restart()
      return
    }
    settleWrite.stop()
    root.writeFile(next)
  }

  // The pill's wheel writes the file once it rests. A read of the file
  // meanwhile keeps the symbol the wheel left.
  Timer {
    id: settleWrite
    interval: 400
    onTriggered: root.writeSettled()
  }
  function writeSettled() {
    if (root.ready && !root.unreadable) root.writeFile(root.fileSettings)
  }
  // The footer's try again.
  function saveAgain() {
    settleWrite.stop()
    root.writeSettled()
  }
  Component.onDestruction: if (settleWrite.running) root.writeSettled()

  // Says when the file changes, and reads nothing.
  FileView {
    path: root.path
    watchChanges: true
    preload: false
    printErrors: false
    onFileChanged: root.readFile()
  }

  // Writes the file.
  FileView {
    id: file
    preload: false
    atomicWrites: true
    // Quickshell 0.3.1's async write, cancelled by the next, compares a
    // third against the cancelled text: a change back to it is never
    // written, and the watch reads the second back over it.
    blockWrites: true
    printErrors: false
    onSaved: root.files.keep([root.path])
    onSaveFailed: function(error) {
      console.warn("stonks: failed to write " + root.path + ": " + error)
    }
  }
  // The text the file held at the last read or write.
  property string known: ""
  // Quickshell skips a write of the text it last wrote or read, and this
  // view reads nothing, so it forgets each write before the next: after a
  // lost save, the same text is written again. A write drops a read still
  // out, which may hold the text before it.
  function writeText(text) {
    reader.drop()
    root.known = text
    file.path = ""
    file.path = root.path
    file.setText(text)
  }

  FileRead {
    id: reader
    onDone: function(answer) { root.take(answer) }
  }
  Component.onCompleted: root.readFile()
  onPathChanged: root.readFile()
  function readFile() {
    if (root.path !== "") reader.read(root.path, root.cap)
  }

  // Only a file not there is missing: one that can't be read is never
  // written over.
  function take(answer) {
    if (answer.text !== undefined) {
      root.missing = false
      root.known = answer.text
      if (root.takesRead(answer.text)) root.takeLoadedSettings(answer.text)
      return
    }
    root.missing = !!answer.missing
    root.known = ""
    if (!root.takesRead(null)) return
    if (root.missing) root.takeMissingFile()
    else root.takeUnreadableFile()
  }

  // While a save awaits its read-back: each text the file may still hold
  // if Stonks' last write was lost, as keys. Quickshell 0.3.2 reports a
  // write done when a full disk fails its commit (fileview.cpp,
  // FileViewWriter::write), so only a read tells.
  property var staleTexts: null
  property string written: ""
  // A read of an earlier text, or none, says the last save was lost, and
  // isn't taken. Any other text ends the wait: a save from elsewhere wins.
  function takesRead(text) {
    if (root.making) return false
    if (root.staleTexts === null) return true
    var lost = text === null || (text !== root.written && root.staleTexts[text] === true)
    if (lost && !root.saveFailed)
      console.warn("stonks: " + root.path + " didn't take the save; keeping the changes until one lands")
    root.saveFailed = lost
    if (!lost) root.staleTexts = null
    root.saveChecked(!lost)
    return !lost
  }

  function adopt(settings) {
    root.fileSettings = Settings.fileSettings(settings)
    if (!root.ready) {
      root.ready = true
      root.started()
    }
  }

  function takeLoadedSettings(text) {
    var parsed = Settings.readListsFile(text)
    if (!parsed) {
      root.takeUnreadableFile()
      return
    }
    root.unreadable = false
    if (settleWrite.running) parsed = Settings.fileSettings(Object.assign({}, parsed, { featured: root.fileSettings.featured }))
    if (root.ready && Settings.settingsEqual(parsed, root.fileSettings)) return
    root.adopt(parsed)
  }

  function takeUnreadableFile() {
    if (!root.unreadable)
      console.warn("stonks: " + root.path + " can't be read; saving nothing until it can")
    root.unreadable = true
    if (!root.ready) root.adopt(root.fileSettings)
  }

  function takeMissingFile() {
    root.unreadable = false
    if (!root.ready) {
      var fromBar = Settings.settingsFromBar(root.parseShell(), root.pluginId)
      if (fromBar) {
        root.adopt(fromBar)
        root.writeFile(fromBar)
        return
      }
    }
    console.warn("stonks: lists file missing; using defaults")
    root.adopt(Settings.fileSettings(null))
  }

  FileView {
    id: shellFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    blockLoading: true
    printErrors: false
  }

  function parseShell() {
    try { return JSON.parse(shellFile.text()) } catch (e) { return null }
  }

  // Read back once written (`takesRead`).
  function writeFile(settings) {
    var body = JSON.stringify(settings, null, 2) + "\n"
    var before = root.known
    if (body === before && root.staleTexts === null) return
    if (root.staleTexts === null) root.staleTexts = {}
    else root.staleTexts[root.written] = true
    root.staleTexts[before] = true
    root.written = body
    if (root.missing) return root.makeFile()
    root.writeText(body)
    root.readFile()
  }

  // A missing lists file is made, not written: Quickshell writes a new file
  // 0644 under the shell's umask, readable by other accounts until a chmod.
  // A write asked for meanwhile goes into it once made, or makes it again.
  property bool missing: false
  property bool making: false
  property bool makeOwed: false
  function makeFile() {
    if (root.making) {
      root.makeOwed = true
      return
    }
    root.making = true
    root.files.create(root.path, root.written, function(made) {
      root.making = false
      if (made) root.missing = false
      var owed = root.makeOwed
      root.makeOwed = false
      if (owed && !made) return root.makeFile()
      if (owed) root.writeText(root.written)
      root.readFile()
    })
  }
}
