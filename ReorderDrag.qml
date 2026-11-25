import QtQuick
import qs.Commons
import "Motion.js" as Motion
import "Rows.js" as Rows

// A row lifted by its key and carried among the others, which make room
// (`slotOf`), then dropped into the place it is over, where it glides to
// rest. It stays under the pointer as the wheel scrolls the rows. Rows
// before `first` stay put. The other surface can remove or rename the
// lifted row, or one below the place it's over: the drag ends where things
// are.
Item {
  id: root

  // The rows' keys in order, `pitch` apart, scrolled `contentY` down.
  property var keys: []
  property real pitch: 1
  property real contentY: 0
  property int first: 0

  // The lifted row's key, "" while none is; where it's drawn; and the place
  // it's over.
  property string lifted: ""
  property real liftedY: 0
  property int slot: -1
  // Where the pointer took the row, and where the pointer is in the view.
  property real offset: 0
  property real pointer: 0

  // Dropped from one place to another, or the same, before it glides.
  signal dropped(int from, int to)
  // It rests at `at`, its place as the glide ended.
  signal landed(int at)

  onContentYChanged: if (lifted !== "" && !glide.running) moveTo(pointer + contentY)
  // A turn later: the drag's end can change the keys again, as the rows a
  // held drag kept back take their places, which within this change would
  // be a binding loop.
  onKeysChanged: if (lifted !== "") Qt.callLater(endIfGone)
  function endIfGone() {
    if (lifted !== "" && (keys.indexOf(lifted) < first || slot >= keys.length)) cancel()
  }

  function slotOf(key) {
    return Rows.slotOf(keys, key, lifted, slot)
  }

  // `y` is the pointer's, down the rows. Says whether the row lifted.
  function begin(key, y) {
    var from = keys.indexOf(key)
    if (from < first) return false
    glide.stop()
    offset = y - from * pitch
    pointer = y - contentY
    liftedY = from * pitch
    slot = from
    lifted = key
    return true
  }

  function moveTo(y) {
    if (lifted === "") return
    pointer = y - contentY
    liftedY = Math.max(first * pitch, Math.min((keys.length - 1) * pitch, y - offset))
    slot = Math.max(first, Rows.dragSlot(liftedY / pitch, slot, keys.length))
  }

  function end() {
    var from = keys.indexOf(lifted)
    var to = slot
    if (from < first || to < first) { cancel(); return }
    dropped(from, to)
    glide.to = to * pitch
    glide.start()
  }

  function cancel() {
    glide.stop()
    lifted = ""
  }

  NumberAnimation {
    id: glide
    target: root
    property: "liftedY"
    duration: Motion.duration(Style, 160)
    easing.type: Easing.Bezier
    easing.bezierCurve: Motion.curve(Style)
    onFinished: {
      var at = root.keys.indexOf(root.lifted)
      root.cancel()
      root.landed(at)
    }
  }
}
