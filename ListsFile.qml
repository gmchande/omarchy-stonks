import QtQuick
import Quickshell
import Quickshell.Io
import "Settings.js" as Settings
// The lists file, ~/.config/omarchy/<id>.json: read as the shell starts and
// whenever it changes, written on each change, and read back to be sure the
// write landed. A file that can't be read is never written over.
Item {
  id: root

  // The plugin's id, which names the file: "" until the shell hands it over.
  property string pluginId: ""
  // The keeper of Stonks' files (`OwnerOnly`), which makes a file its
  // owner's alone.
  property var files: null
  // What the file holds: the defaults until its first read, and what was
  // last asked of it where a write hasn't landed.
  property var dataSettings: Settings.fileSettings(null)
  // The first read is in: `dataSettings` is the file's, or the defaults.
  signal started()

  readonly property string dataPath: pluginId ? Quickshell.env("HOME") + "/" + Settings.listsFile(pluginId) : ""
  property bool ready: false
  property bool settingsUnreadable: false
  // A change made while the file can't be read: only memory holds it.
  property bool editsUnsaved: false
  onSettingsUnreadableChanged: if (!settingsUnreadable) editsUnsaved = false
  // A save didn't land: Quickshell said so, or the read-back still held the
  // text before it (`takesRead`). The next save writes everything in memory.
  property bool saveFailed: false
  signal saveChecked(bool saved)

  function persist(values, settles) {
    root.store(Settings.fileSettings(Object.assign({}, root.dataSettings, values)), settles)
  }

  function save(next) {
    if (!Settings.settingsEqual(next, root.dataSettings)) root.store(next)
  }

  function store(next, settles) {
    var changed = !Settings.settingsEqual(next, root.dataSettings)
    root.dataSettings = next
    if (!root.ready) return
    if (root.settingsUnreadable) {
      if (changed) root.editsUnsaved = true
      return
    }
    if (settles) {
      settleWrite.restart()
      return
    }
    settleWrite.stop()
    root.writeDataFile(next)
  }

  // The pill's wheel writes the file once it rests. A read of the file
  // meanwhile keeps the symbol the wheel left.
  Timer {
    id: settleWrite
    interval: 400
    onTriggered: root.writeSettled()
  }
  function writeSettled() {
    if (root.ready && !root.settingsUnreadable) root.writeDataFile(root.dataSettings)
  }
  // The footer's try again.
  function saveAgain() {
    settleWrite.stop()
    root.writeSettled()
  }
  Component.onDestruction: if (settleWrite.running) root.writeSettled()

  FileView {
    id: dataFile
    path: root.dataPath
    watchChanges: true
    atomicWrites: true
    // Quickshell 0.3.1's async write, cancelled by the next, compares a
    // third against the cancelled text: a change back to it is never
    // written, and the watch reads the second back over it.
    blockWrites: true
    printErrors: false
    onFileChanged: root.readDataFile()
    onLoaded: {
      root.dataMissing = false
      root.dataReadEnded(root.takesRead(dataFile.text()) ? root.takeLoadedSettings : null)
    }
    // Only a file not there is missing: one that can't be read is never
    // written over.
    onLoadFailed: function(error) {
      root.dataMissing = error === FileViewError.FileNotFound
      if (!root.takesRead(null)) root.dataReadEnded(null)
      else root.dataReadEnded(root.dataMissing ? root.takeMissingFile : root.takeUnreadableFile)
    }
    // A write drops a read in flight unheard.
    onSaved: {
      root.files.keep([root.dataPath])
      root.dataReadEnded(null)
    }
    onSaveFailed: function(error) {
      console.warn("stonks: failed to write " + root.dataPath + ": " + error)
      root.dataReadEnded(null)
    }
  }
  // Quickshell 0.3.1 ignores reload() while a read is in flight, so a
  // change meanwhile is held and read once that read ends.
  property bool dataReading: true
  property bool dataChangedMeanwhile: false
  function readDataFile() {
    if (root.dataReading) {
      root.dataChangedMeanwhile = true
      return
    }
    root.startDataRead()
  }
  function startDataRead() {
    root.dataReading = true
    dataFile.reload()
  }
  // Quickshell lets go of a read only after its handlers have run, so a
  // held read starts a turn later.
  function dataReadEnded(take) {
    var again = root.dataChangedMeanwhile
    root.dataReading = again
    root.dataChangedMeanwhile = false
    if (take) take()
    if (again) Qt.callLater(root.startDataRead)
  }

  // While a save awaits its read-back: each text the file may still hold
  // if Stonks' last write was lost, as keys. Quickshell 0.3.2 reports a
  // write done when a full disk fails its commit (fileview.cpp,
  // FileViewWriter::write), so only a read tells.
  property var staleTexts: null
  property string dataWritten: ""
  // A read of an earlier text, or none, says the last save was lost, and
  // isn't taken. Any other text ends the wait: a save from elsewhere wins.
  function takesRead(text) {
    if (root.dataMaking) return false
    if (root.staleTexts === null) return true
    var lost = text === null || (text !== root.dataWritten && root.staleTexts[text] === true)
    if (lost && !root.saveFailed)
      console.warn("stonks: " + root.dataPath + " didn't take the save; keeping the changes until one lands")
    root.saveFailed = lost
    if (!lost) root.staleTexts = null
    root.saveChecked(!lost)
    return !lost
  }

  function parseDataText(text) {
    try {
      var parsed = JSON.parse(String(text || "").trim())
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
      return Settings.fileSettings(parsed)
    } catch (e) {
      return null
    }
  }

  function adopt(settings) {
    root.dataSettings = Settings.fileSettings(settings)
    if (!root.ready) {
      root.ready = true
      root.started()
    }
  }

  function takeLoadedSettings() {
    var parsed = root.parseDataText(dataFile.text())
    if (!parsed) {
      root.takeUnreadableFile()
      return
    }
    root.settingsUnreadable = false
    if (settleWrite.running) parsed = Settings.fileSettings(Object.assign({}, parsed, { featured: root.dataSettings.featured }))
    if (root.ready && Settings.settingsEqual(parsed, root.dataSettings)) return
    root.adopt(parsed)
  }

  function takeUnreadableFile() {
    if (!root.settingsUnreadable)
      console.warn("stonks: " + root.dataPath + " can't be read; saving nothing until it can")
    root.settingsUnreadable = true
    if (!root.ready) root.adopt(root.dataSettings)
  }

  function takeMissingFile() {
    root.settingsUnreadable = false
    if (!root.ready) {
      var fromBar = Settings.settingsFromBar(root.parseShell(), root.pluginId)
      if (fromBar) {
        root.adopt(fromBar)
        root.writeDataFile(fromBar)
        return
      }
    }
    console.warn("stonks: settings file missing; using defaults")
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

  // Read back once written (`takesRead`). The read also hands Quickshell
  // the text it compares a write with: after a lost save it would skip the
  // same text. It starts a turn later: Quickshell 0.3.2 forgets a read
  // started inside a read's handlers (fileview.cpp, operationFinished).
  function writeDataFile(settings) {
    var body = JSON.stringify(settings, null, 2) + "\n"
    var before = dataFile.text()
    if (body === before && root.staleTexts === null) return
    if (root.staleTexts === null) root.staleTexts = {}
    else root.staleTexts[root.dataWritten] = true
    root.staleTexts[before] = true
    root.dataWritten = body
    if (root.dataMissing) return root.makeDataFile()
    dataFile.setText(body)
    Qt.callLater(root.readDataFile)
  }

  // A missing data file is made, not written: Quickshell writes a new file
  // 0644 under the shell's umask, readable by other accounts until a chmod.
  // A write asked for meanwhile goes into it once made, or makes it again.
  property bool dataMissing: false
  property bool dataMaking: false
  property bool dataMakeOwed: false
  function makeDataFile() {
    if (root.dataMaking) {
      root.dataMakeOwed = true
      return
    }
    root.dataMaking = true
    root.files.create(root.dataPath, root.dataWritten, function(made) {
      root.dataMaking = false
      if (made) root.dataMissing = false
      var owed = root.dataMakeOwed
      root.dataMakeOwed = false
      if (owed && !made) return root.makeDataFile()
      if (owed) dataFile.setText(root.dataWritten)
      Qt.callLater(root.readDataFile)
    })
  }
}
