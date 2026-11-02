import QtQuick
// Reports only a hand's move over a list of rows. Qt hovers as the pointer
// is first seen, whether it comes in or the view opens or shows under a
// resting pointer, and again as rows scroll under a still pointer; neither
// is a move, so the cursor stays where the view or the keys put it.
HoverHandler {
  id: root

  property point scenePosition: Qt.point(-1, -1)
  property bool within: false
  // After rest(), reports within `jitter` px of the first are the resting
  // pointer: the compositor can report it a pixel off as the view comes back.
  readonly property real jitter: 2
  property bool resting: false
  property point restPlace: Qt.point(-1, -1)

  // In scene coordinates: a list's content moves under the handler.
  signal moved(real x, real y)

  function rest() {
    resting = true
    within = false
  }

  onPointChanged: {
    var next = point.scenePosition
    if (resting && hovered) {
      if (!within) restPlace = next
      if (Math.abs(next.x - restPlace.x) <= jitter && Math.abs(next.y - restPlace.y) <= jitter) {
        scenePosition = next
        within = true
        return
      }
      resting = false
    }
    var changed = within && (next.x !== scenePosition.x || next.y !== scenePosition.y)
    scenePosition = next
    within = hovered
    if (hovered && changed) moved(next.x, next.y)
  }
  onHoveredChanged: if (!hovered) within = false
}
