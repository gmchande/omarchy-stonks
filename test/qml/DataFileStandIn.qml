import QtQuick

// Stands in for the service's data file, a FileView, in service.sh's
// stepped Service, so the harness drives a read, a save from elsewhere, its
// notice, and the read's end in that order: Quickshell's own read can't be
// held part-way. Keeps what Quickshell 0.3.1's FileView does
// (src/io/fileview.cpp): a read starts as the path is set; a reload() while
// a read is in flight is ignored (loadAsync), and a read is in flight until
// its loaded handlers have run (operationFinished); a write is skipped when
// it equals the text in hand (setText), and drops a read in flight unheard,
// neither loaded nor failed (saveSync's cancelAsync). Here a read sees the
// file as it is when it starts.
QtObject {
  id: standIn
  property string path
  property bool watchChanges
  property bool atomicWrites
  property bool blockWrites
  property bool printErrors
  signal fileChanged()
  signal loaded()
  signal loadFailed(int error)
  signal saved()
  signal saveFailed(int error)

  // What the file holds, the text the last read or write left, and the
  // read in flight with what it read.
  property string disk: ""
  property string held: ""
  property bool reading: false
  property string readText: ""

  function text() { return held }
  function reload() {
    if (reading) return
    reading = true
    readText = disk
  }
  function setText(next) {
    if (next === held) return
    reading = false
    disk = next
    held = next
    saved()
  }

  // The harness's moves: the read in flight ends; a save from elsewhere
  // lands and its notice comes. A notice of the service's own save is
  // fileChanged() alone.
  function endRead() {
    held = readText
    loaded()
    reading = false
  }
  function saveElsewhere(next) {
    disk = next
    fileChanged()
  }

  // The file as the real one holds it when the service starts.
  Component.onCompleted: {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', standIn)
    view.path = path
    disk = String(view.text())
    view.destroy()
    reload()
  }
}
