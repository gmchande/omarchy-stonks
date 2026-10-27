import QtQuick
import Quickshell
import Quickshell.Io

// The root every flow harness stands on: what each one wrote out again
// before. A harness is `Harness { id: harness; marker: "LISTS DONE" ... }`
// and calls these unqualified. lib.sh's finish fails a run that never
// printed its marker.
ShellRoot {
  id: harness

  property string marker
  property int failures: 0

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  // The first item named `name` under `item`, through a popup's or a
  // window's contentItem too. A Flickable's contentItem is already one of
  // its children, so it is walked once.
  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = find(item.children[i], name)
      if (found) return found
    }
    return item.contentItem && item.contentItem.parent !== item ? find(item.contentItem, name) : null
  }

  function findAll(item, name, into) {
    var out = into || []
    if (!item) return out
    if (item.objectName === name) out.push(item)
    for (var i = 0; i < item.children.length; i++) findAll(item.children[i], name, out)
    if (item.contentItem && item.contentItem.parent !== item) findAll(item.contentItem, name, out)
    return out
  }

  // A fresh view per read: a FileView that has loaded once returns its old
  // text straight after reload().
  function readFile(path) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = path
    var text = String(view.text() || "")
    view.destroy()
    return text
  }

  // How many times the fake curl answered `name` (STONKS_FAKE_STATE).
  function calls(name) {
    return Number(readFile(Quickshell.env("STONKS_FAKE_STATE") + "/" + name + ".calls").trim() || "0")
  }

  function finish() {
    console.log(marker)
    exit.exitCode = failures ? 1 : 0
    exit.start()
  }

  HarnessExit { id: exit }
}
