import QtQuick
// The pointer over a list of rows, said only when it really moves within
// them. The first place the pointer is seen at, as it comes in or as the
// view opens or shows again under a resting pointer, is where it starts,
// no move: Qt's first hover there says nothing about a hand, so the cursor
// stays where the view put it. And Qt sends the hover again as rows scroll
// under a still pointer; that is no move either, so a key gliding a list
// never hands its cursor back to the pointer.
HoverHandler {
  id: root

  // The pointer's last place in the scene, wherever it was.
  property point scenePosition: Qt.point(-1, -1)
  // Whether the pointer was already here at its last place.
  property bool within: false
  // Set as the view opens or shows again (rest): the first place the
  // pointer is seen at after that is where it rests, and reports within
  // `jitter` of it are that resting pointer, no move: the compositor can
  // report it again a pixel off as the view comes back. The first report
  // farther away is a hand's move, and counts.
  readonly property real jitter: 2
  property bool resting: false
  property point restPlace: Qt.point(-1, -1)

  // The pointer moved to (x, y) in the scene: a list maps it to its own
  // rows, since a handler's own point may be read in a list's moving content.
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
