pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Tones.js" as Tones

// The rule between the list's name and its order, drawn as the list's
// breadth: rows up in the up colour from the left, rows down in the down
// colour from the right, as a list sorted by the day's move reads from the
// top. Hover says the counts.
Item {
  id: root

  property var breadth: ({ list: "", up: 0, flat: 0, down: 0, none: 0 })
  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
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
  // At 1 px the colours don't read. The info lines' rules share its ink and
  // grain (`Cells.RULE_*`).
  readonly property int thickness: Cells.RULE_THICKNESS
  readonly property color plain: Qt.rgba(foreground.r, foreground.g, foreground.b, Cells.RULE_INK)
  // Retro draws it as cells on the pixel chart's grain.
  readonly property int pitch: Cells.RULE_PITCH
  readonly property int cells: Math.max(0, Math.floor((width + 1) / pitch))
  // Both ends round down, by the same rule, so they never overlap and equal
  // counts draw equal lengths; what rounding leaves over stays plain.
  readonly property int upCells: total ? Math.floor(cells * breadth.up / total) : 0
  readonly property int downCells: total ? Math.floor(cells * breadth.down / total) : 0
  // Smooth eases the shares, not the lengths, so a rule resized by the name or
  // order beside it redraws at once. The ends ease only for the same list's
  // breadth; another list's is set at once, as a switch draws its rows. While
  // `still` they stop where they are, and a change waits.
  property bool still: false
  property real upShare: 0
  property real downShare: 0
  // The list the shares were last set for.
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

  // Each scrub step and replay frame brings a new breadth, mostly the same, so
  // ends already resting or easing there are left be.
  function showBreadth() {
    if (still) return
    var all = breadth.up + breadth.flat + breadth.down + breadth.none
    var up = all ? breadth.up / all : 0
    var down = all ? breadth.down / all : 0
    var same = sharesList === breadth.list
    sharesList = breadth.list
    if (same && up === (upEase.running ? upEase.to : upShare) && down === (downEase.running ? downEase.to : downShare)) return
    upEase.stop()
    downEase.stop()
    if (same) {
      upEase.to = up
      downEase.to = down
      upEase.start()
      downEase.start()
    } else {
      upShare = up
      downShare = down
    }
  }

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

    // An end with no rows is zero long, so each slides to and from zero rather
    // than vanishing.
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
