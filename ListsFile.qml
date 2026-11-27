import QtQuick
import Quickshell
import Quickshell.Io
import "Commands.js" as Commands
import "Settings.js" as Settings
// The lists file, ~/.config/omarchy/<id>.json: read as the shell starts and
// whenever it changes, written on each change, and read back to be sure the
// write landed. A file that can't be read is never written over. It is read
// outside the shell's thread, and only a regular file of at most `cap`
// bytes is read (`FileRead`): one larger, or anything else there, can't be.
// Nor can one that isn't UTF-8, which Qt reads with U+FFFD in place of a
// name's letter, and a save would write that over the letter.
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
  // A change not yet in the file for sure: one waiting for the wheel to
  // rest, for a read out, for the file to be made, for an async write to
  // finish, or a save awaiting its read-back.
  readonly property bool saving: settleWrite.running || writeOwed || making || writing || writeQueued !== "" || staleTexts !== null

  // Keys changed by `persist(values, ...)` waiting for the debounce timer or an
  // in-flight read so an external edit merges them instead of being overwritten.
  // `wholeWriteOwed` is true once a full `save()` waits on a read in flight.
  property var settledKeys: ({})
  property bool wholeWriteOwed: false

  function persist(values, settles) {
    var next = Settings.withValues(root.fileSettings, values)
    root.store(next, settles, values, next !== root.fileSettings)
  }

  function save(next) {
    if (!Settings.settingsEqual(next, root.fileSettings)) {
      root.store(next, false, null, true)
    }
  }

  function store(next, settles, values, knownChanged) {
    var changed = knownChanged !== undefined ? knownChanged : !Settings.settingsEqual(next, root.fileSettings)
    root.fileSettings = next
    if (!root.ready) return
    if (root.unreadable) {
      if (changed) root.editsUnsaved = true
      return
    }
    if (settles) {
      if (changed || settleWrite.running) {
        if (!root.wholeWriteOwed) {
          var pending = Object.assign({}, root.settledKeys)
          if (values) for (var k in values) pending[k] = true
          root.settledKeys = pending
        }
        settleWrite.restart()
      }
      return
    }
    settleWrite.stop()
    if (reader.out && values && !root.wholeWriteOwed) {
      var owedKeys = Object.assign({}, root.settledKeys)
      for (var ok in values) owedKeys[ok] = true
      root.settledKeys = owedKeys
    } else {
      root.settledKeys = ({})
      if (reader.out) root.wholeWriteOwed = true
    }
    root.writeFile(next)
  }

  // The pill's wheel writes the file once it rests. A read of the file
  // meanwhile keeps every pending key.
  Timer {
    id: settleWrite
    interval: 400
    onTriggered: root.writeSettled()
  }
  function writeSettled() {
    if (!root.ready || root.unreadable) {
      root.settledKeys = ({})
      root.wholeWriteOwed = false
      return
    }
    root.writeFile(root.fileSettings)
    if (!root.writeOwed) {
      root.settledKeys = ({})
      root.wholeWriteOwed = false
    }
  }
  // Flush any pending delayed save at once (surface close, update restart).
  function flush() {
    if (!settleWrite.running) return
    settleWrite.stop()
    root.writeSettled()
  }
  // The footer's try again.
  function saveAgain() {
    settleWrite.stop()
    root.settledKeys = ({})
    if (reader.out) root.wholeWriteOwed = true
    root.writeSettled()
  }
  // The shell is going: any pending delayed or in-flight async change is
  // written synchronously now, unless a read is out. That read can't land
  // any more, and the file it reads may be one Stonks can't read, or another
  // copy's newer one, so the change goes.
  Component.onDestruction: {
    var pending = settleWrite.running || root.writing || root.writeQueued !== ""
    settleWrite.stop()
    root.settledKeys = ({})
    root.wholeWriteOwed = false
    root.writeQueued = ""
    if (!pending || !root.ready || root.unreadable || root.missing || reader.out) return
    var body = JSON.stringify(root.fileSettings, null, 2) + "\n"
    if (Commands.fileBytes(body) > root.cap) return
    syncFile.path = ""
    syncFile.path = root.path
    syncFile.setText(body)
  }

  // Says when the file changes, and reads nothing. Coalesces the single
  // inotify echo of Stonks' own atomic write when its write or read-back is
  // already out.
  property bool skipNextWatch: false
  FileView {
    path: root.path
    watchChanges: true
    preload: false
    printErrors: false
    onFileChanged: {
      if (root.making || root.writing || root.writeQueued !== "") {
        root.skipNextWatch = false
        return
      }
      if (root.skipNextWatch && reader.out) {
        root.skipNextWatch = false
        return
      }
      root.readFile()
    }
  }

  // Writes the file asynchronously off the shell's thread, one write at a
  // time (`writing` / `writeQueued`) so a quick second change never cancels
  // an in-flight write (Quickshell 0.3.1's cancelled-write bug).
  property bool writing: false
  property string writeQueued: ""
  FileView {
    id: file
    preload: false
    atomicWrites: true
    blockWrites: false
    printErrors: false
    onSaved: {
      root.files.keep([root.path])
      if (root.writeQueued !== "") {
        Qt.callLater(root.writeNext)
        return
      }
      root.writing = false
      root.readFile()
    }
    onSaveFailed: function(error) {
      root.skipNextWatch = false
      console.warn("stonks: failed to write " + root.path + ": " + error)
      if (root.writeQueued !== "") {
        Qt.callLater(root.writeNext)
        return
      }
      root.writing = false
      root.readFile()
    }
  }
  // Blocking writer used only on clean exit (`Component.onDestruction`) to
  // land any in-flight or queued change before the shell terminates.
  FileView {
    id: syncFile
    preload: false
    atomicWrites: true
    blockWrites: true
    printErrors: false
  }
  // The text the file held at the last read or write.
  property string known: ""
  // Quickshell skips a write of the text it last wrote or read, and this
  // view reads nothing, so it forgets each write before the next: after a
  // lost save, the same text is written again.
  function writeText(text) {
    if (root.writing) {
      root.writeQueued = text
      return
    }
    root.writing = true
    root.known = text
    root.skipNextWatch = true
    file.path = ""
    file.path = root.path
    file.setText(text)
  }
  // Start a queued write after `onSaved`/`onSaveFailed` unwinds so resetting
  // `file.path` never drops the finishing FileView operation.
  function writeNext() {
    if (!root.writing) return
    root.writing = false
    if (root.writeQueued === "") return
    var next = root.writeQueued
    root.writeQueued = ""
    root.writeText(next)
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

  // A save asked while a read is out waits for it (`writeFile`), since the
  // file may have changed since the last read: one that can't be read now
  // is never written over. Otherwise the change, the newest, is written.
  property bool writeOwed: false

  // Only a file not there is missing: one that can't be read is never
  // written over, a save still awaiting its read-back included. What is
  // there now is no text of Stonks', so that wait ends, as for a save from
  // elsewhere.
  function take(read) {
    root.skipNextWatch = false
    var answer = read.lossy ? { refused: true } : read
    var owed = root.writeOwed
    root.writeOwed = false
    if (root.writing || root.writeQueued !== "") {
      root.writeOwed = owed
      return
    }
    if (answer.text !== undefined) {
      root.missing = false
      if (root.files && answer.text !== root.written) root.files.forget(root.path)
      root.known = answer.text
      // Stonks' own last save, read back while memory holds a change too
      // large to save: the file is readable and the save landed, and the
      // change stays, unsaved.
      if (root.written !== "" && answer.text === root.written && root.tooLarge(root.fileSettings)) {
        root.staleTexts = null
        root.unreadable = false
        root.saveFailed = true
        return
      }
      var taken = root.takesRead(answer.text)
      if (!owed) {
        if (taken) root.takeLoadedSettings(answer.text)
        return
      }
      var parsed = Settings.readListsFile(answer.text)
      if (!parsed) {
        root.settledKeys = ({})
        root.wholeWriteOwed = false
        root.takeUnreadableFile()
        root.editsUnsaved = true
        return
      }
      root.unreadable = false
      var whole = root.wholeWriteOwed
      root.wholeWriteOwed = false
      var keys = Object.keys(root.settledKeys)
      root.settledKeys = ({})
      if (taken && !whole && keys.length > 0) {
        var keep = {}
        for (var i = 0; i < keys.length; i++) keep[keys[i]] = root.fileSettings[keys[i]]
        var merged = Settings.fileSettings(Settings.copyWith(parsed, keep))
        if (!Settings.settingsEqual(merged, root.fileSettings)) root.adopt(merged)
      }
      root.writeFile(root.fileSettings)
      return
    }
    root.missing = !!answer.missing
    root.known = ""
    if (root.files) root.files.forget(root.path)
    if (root.missing) {
      var gone = root.takesRead(null)
      if (owed) {
        root.settledKeys = ({})
        root.wholeWriteOwed = false
        root.writeFile(root.fileSettings)
      } else if (gone) root.takeMissingFile()
      return
    }
    // A read while the file is being made is no answer: a write it held
    // waits for the next.
    if (root.making) {
      root.writeOwed = owed
      return
    }
    root.staleTexts = null
    root.saveFailed = false
    root.takeUnreadableFile()
    if (owed) {
      root.settledKeys = ({})
      root.wholeWriteOwed = false
      root.editsUnsaved = true
    }
  }

  // While a save awaits its read-back: each text the file may still hold
  // if Stonks' last write was lost, by its md5. Quickshell 0.3.2 reports a
  // write done when a full disk fails its commit (fileview.cpp,
  // FileViewWriter::write), so only a read tells. At most 1024, the first
  // kept: the text the file held before the saves began to fail.
  property var staleTexts: null
  property string written: ""
  // A read of an earlier text, or none, says the last save was lost, and
  // isn't taken. Any other text ends the wait: a save from elsewhere wins.
  function takesRead(text) {
    if (root.making || root.writing || root.writeQueued !== "") return false
    if (root.staleTexts === null) {
      root.saveFailed = false
      return true
    }
    var lost = text === null || (text !== root.written && root.staleTexts["m" + Qt.md5(text)] === true)
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
    if (settleWrite.running) {
      var keep = {}
      var keys = Object.keys(root.settledKeys)
      if (keys.length === 0) keep.featured = root.fileSettings.featured
      else for (var i = 0; i < keys.length; i++) keep[keys[i]] = root.fileSettings[keys[i]]
      parsed = Settings.fileSettings(Settings.copyWith(parsed, keep))
    }
    if (root.ready && Settings.settingsEqual(parsed, root.fileSettings)) return
    root.adopt(parsed)
  }

  function takeUnreadableFile() {
    if (!root.unreadable)
      console.warn("stonks: " + root.path + " can't be read; saving nothing until it can")
    if (settleWrite.running) {
      settleWrite.stop()
      root.settledKeys = ({})
      root.editsUnsaved = true
    }
    root.unreadable = true
    if (!root.ready) root.adopt(root.fileSettings)
  }

  // On a first start with no lists file, the bar's own entry in the shell's
  // shell.json, where an older Stonks kept its symbols, starts it
  // (`FileRead`, at most 1 MiB: Omarchy's own is a few KB).
  function takeMissingFile() {
    root.unreadable = false
    if (root.ready) return root.takeDefaults()
    shellReader.read(Quickshell.env("HOME") + "/.config/omarchy/shell.json", 1048576)
  }
  FileRead {
    id: shellReader
    onDone: function(answer) { root.takeShell(answer.text) }
  }
  // A lists file read meanwhile wins.
  function takeShell(text) {
    if (root.ready || !root.missing) return
    var shell = null
    try { shell = JSON.parse(text) } catch (e) {}
    var fromBar = Settings.settingsFromBar(shell, root.pluginId)
    if (!fromBar) return root.takeDefaults()
    root.adopt(fromBar)
    root.writeFile(fromBar)
  }
  function takeDefaults() {
    console.warn("stonks: lists file missing; using defaults")
    root.adopt(Settings.fileSettings(null))
  }

  // Read back once written (`takesRead`). A text over the cap is never
  // written, since Stonks couldn't read it back: the file keeps what it
  // held, and the footer says the changes aren't saved until they fit.
  function tooLarge(settings) {
    return Commands.fileBytes(JSON.stringify(settings, null, 2) + "\n") > root.cap
  }
  function writeFile(settings) {
    var body = JSON.stringify(settings, null, 2) + "\n"
    if (Commands.fileBytes(body) > root.cap) {
      root.saveFailed = true
      return
    }
    if (reader.out) {
      root.writeOwed = true
      return
    }
    var before = root.known
    if (body === before && root.staleTexts === null) {
      root.saveFailed = false
      return
    }
    if (root.staleTexts === null) root.staleTexts = {}
    else root.stale(root.written)
    root.stale(before)
    root.written = body
    if (root.missing) return root.makeFile()
    root.writeText(body)
  }
  // Keys never read as numbers, so they keep the order they came in.
  function stale(text) {
    var keys = Object.keys(root.staleTexts)
    if (keys.length >= 1024) delete root.staleTexts[keys[1]]
    root.staleTexts["m" + Qt.md5(text)] = true
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
      if (owed) return root.writeText(root.written)
      root.readFile()
    })
  }
}
