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

  // The rows' keys in order, `pitch` apart, scrolled `contentY` down, in a
  // view `sight` high that scrolls as far as `reach`.
  property var keys: []
  property real pitch: 1
  property real contentY: 0
  property real sight: 0
  property real reach: 0
  property int first: 0

  // The lifted row's key, "" while none is; where it's drawn; and the place
  // it's over.
  property string lifted: ""
  property real liftedY: 0
  property int slot: -1
  // Where the pointer took the row, and where the pointer is in the view.
  property real offset: 0
  property real pointer: 0
  // Furthest the pointer has pulled back from each edge during this drag,
  // starting where the row lifted.
  property real topAnchor: 0
  property real bottomAnchor: 0

  // Dropped from one place to another, or the same, before it glides.
  signal dropped(int from, int to)
  // It rests at `at`, its place as the glide ended.
  signal landed(int at)
  // Held at an edge, the row asks the list to scroll to `y`.
  signal scrollTo(real y)

  // Within a row of the view's top or bottom, or past it, the held row
  // scrolls the list, faster the deeper it's held, until the list ends. A
  // row lifted within that row starts the edge where it was lifted so only
  // a move toward the edge scrolls; pulling away widens the edge back to a
  // full row, and speed scales to the active edge span so the border still
  // reaches full speed.
  readonly property real topEdge: Math.min(pitch, topAnchor)
  readonly property real bottomEdge: Math.max(sight - pitch, bottomAnchor)
  readonly property real depth: pointer < topEdge ? pointer - topEdge : pointer > bottomEdge ? pointer - bottomEdge : 0
  readonly property real edgeSpan: Math.max(1, depth < 0 ? topEdge : sight - bottomEdge)
  readonly property bool edgeHeld: lifted !== "" && !glide.running && (depth < 0 ? contentY > 0 : depth > 0 && contentY < reach)
  FrameAnimation {
    running: root.edgeHeld
    onTriggered: {
      var rowsPerSecond = 8 * Math.max(-2, Math.min(2, root.depth / root.edgeSpan))
      var by = rowsPerSecond * root.pitch * Math.min(frameTime, 0.05)
      root.scrollTo(Math.max(0, Math.min(root.reach, root.contentY + by)))
    }
  }

  onContentYChanged: if (lifted !== "" && !glide.running) moveTo(pointer + contentY)
  // A turn later: the drag's end can change the keys again, as the rows a
  // held drag kept back take their places, which within this change would
  // be a binding loop.
  onKeysChanged: if (lifted !== "") Qt.callLater(endIfGone)
  function endIfGone() {
    if (lifted !== "" && (keys.indexOf(lifted) < first || slot >= keys.length)) cancel()
  }

  readonly property var keyIndex: {
    var map = {}
    for (var i = 0; i < keys.length; i++) map[keys[i]] = i
    return map
  }
  readonly property int liftedIndex: lifted !== "" && keyIndex[lifted] !== undefined ? keyIndex[lifted] : -1

  function slotOf(key) {
    var i = keyIndex[key]
    if (i === undefined) return -1
    if (lifted === "") return i
    var from = liftedIndex
    if (from < 0) return i
    if (from < slot && i > from && i <= slot) return i - 1
    if (slot < from && i >= slot && i < from) return i + 1
    return i
  }

  // `y` is the pointer's, down the rows. Says whether the row lifted.
  function begin(key, y) {
    var from = keys.indexOf(key)
    if (from < first) return false
    glide.stop()
    offset = y - from * pitch
    pointer = y - contentY
    topAnchor = pointer
    bottomAnchor = pointer
    liftedY = from * pitch
    slot = from
    lifted = key
    return true
  }

  function moveTo(y) {
    if (lifted === "") return
    pointer = y - contentY
    if (pointer > topAnchor) topAnchor = pointer
    if (pointer < bottomAnchor) bottomAnchor = pointer
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
    easing.type: Easing.OutCubic
    onFinished: {
      var at = root.keys.indexOf(root.lifted)
      root.cancel()
      root.landed(at)
    }
  }
}
