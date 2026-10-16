pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Cells.js" as Cells
import "Tones.js" as Tones

// The rule between the list's name and its order, drawn as the list's
// breadth: the rows that are up in the up colour from the left, the rows
// that are down in the down colour from the right, the way a list sorted by
// the day's move reads from the top. Flat rows and rows with no figure yet
// keep the plain rule between them. Hover says the counts in its place.
Item {
  id: root

  // The list's breadth, and the list it is for.
  property var breadth: ({ list: "", up: 0, flat: 0, down: 0, none: 0 })
  property bool retro: false
  property color foreground: Color.foreground
  property color dim: Tones.dim(foreground, Color.background)
  property color upColor: Color.foreground
  property color downColor: Color.urgent
  property string fontFamily: Style.font.family

  readonly property int total: breadth.up + breadth.flat + breadth.down + breadth.none
  readonly property string counts: {
    var parts = []
    if (breadth.up) parts.push(breadth.up + " UP")
    if (breadth.flat) parts.push(breadth.flat + " FLAT")
    if (breadth.down) parts.push(breadth.down + " DOWN")
    return parts.join(" · ")
  }
  readonly property bool revealed: hover.hovered && counts !== ""
  // At 1 px the colours do not read; 2 px is the thinnest that does. The
  // ink and grain are the info lines' rules' too (`Cells.RULE_*`).
  readonly property int thickness: Cells.RULE_THICKNESS
  readonly property color plain: Qt.rgba(foreground.r, foreground.g, foreground.b, Cells.RULE_INK)
  // Retro draws the rule as cells on the pixel chart's grain.
  readonly property int pitch: Cells.RULE_PITCH
  readonly property int cells: Math.max(0, Math.floor((width + 1) / pitch))
  // Both ends round down, by the same rule, so they never overlap and equal
  // counts draw equal lengths; what rounding leaves over stays plain.
  readonly property int upCells: total ? Math.floor(cells * breadth.up / total) : 0
  readonly property int downCells: total ? Math.floor(cells * breadth.down / total) : 0
  // Smooth eases the shares, not the lengths, so a rule that grows or
  // shrinks with the name or order beside it redraws its ends at once. The
  // ends ease only when the same list's breadth changes (a refresh, an add,
  // a removal); another list's is set at once, as a switch draws its rows.
  // Both ease alike, so they never meet. While it rests (`still`: its
  // surface closing, or the rows covered by search or a list view) they
  // stop where they are and a change waits; as it stops resting, and as a
  // surface opens (`settle`), they are set on the breadth at once.
  property bool still: false
  property real upShare: 0
  property real downShare: 0
  // The list the shares were last set for; null before the first.
  property var sharesList: null
  onBreadthChanged: showBreadth()
  Component.onCompleted: showBreadth()
  onStillChanged: {
    if (!still) {
      settle()
      return
    }
    if (upEase.running) upEase.pause()
    if (downEase.running) downEase.pause()
  }

  // While still, nothing moves: a change waits for the open's `settle`.
  function showBreadth() {
    if (still) return
    var all = breadth.up + breadth.flat + breadth.down + breadth.none
    var up = all ? breadth.up / all : 0
    var down = all ? breadth.down / all : 0
    upEase.stop()
    downEase.stop()
    if (sharesList === breadth.list) {
      upEase.to = up
      downEase.to = down
      upEase.start()
      downEase.start()
    } else {
      upShare = up
      downShare = down
    }
    sharesList = breadth.list
  }

  // At rest on the breadth, as a surface opens.
  function settle() {
    sharesList = null
    showBreadth()
  }

  NumberAnimation { id: upEase; target: root; property: "upShare"; duration: 160; easing.type: Easing.OutCubic }
  NumberAnimation { id: downEase; target: root; property: "downShare"; duration: 160; easing.type: Easing.OutCubic }

  HoverHandler { id: hover }

  Item {
    anchors.fill: parent
    opacity: root.revealed ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    Rectangle {
      visible: !root.retro
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: 1
      color: root.plain
    }

    // Both ends are always there; an end with no rows is zero long and
    // draws nothing, so each slides to and from zero instead of vanishing.
    Rectangle {
      objectName: "breadthUp"
      visible: !root.retro
      anchors.verticalCenter: parent.verticalCenter
      width: Math.floor(parent.width * root.upShare)
      height: root.thickness
      radius: root.thickness / 2
      color: root.upColor
    }

    Rectangle {
      objectName: "breadthDown"
      visible: !root.retro
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.floor(parent.width * root.downShare)
      height: root.thickness
      radius: root.thickness / 2
      color: root.downColor
    }

    Row {
      visible: root.retro
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.pitch - root.thickness

      Repeater {
        model: root.retro ? root.cells : 0

        Rectangle {
          required property int index
          width: root.thickness
          height: root.thickness
          color: index < root.upCells ? root.upColor
            : index >= root.cells - root.downCells ? root.downColor : root.plain
        }
      }
    }
  }

  Text {
    objectName: "breadthCounts"
    anchors.centerIn: parent
    opacity: root.revealed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    textFormat: Text.PlainText
    text: root.counts
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }
}
