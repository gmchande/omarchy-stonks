pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Cells.js" as Cells
import "Motion.js" as Motion

// The rule between the list's name and its order, drawn as the list's
// breadth: rows up in the up colour from the left, rows down in the down
// colour from the right, as a list sorted by the day's move reads from the
// top. Hover says the counts, where they fit in the rule's length.
Item {
  id: root

  property var breadth: ({ list: "", up: 0, flat: 0, down: 0, none: 0 })
  property Look look

  readonly property int total: breadth.up + breadth.flat + breadth.down + breadth.none
  readonly property string counts: {
    var parts = []
    if (breadth.up) parts.push(breadth.up + " UP")
    if (breadth.flat) parts.push(breadth.flat + " FLAT")
    if (breadth.down) parts.push(breadth.down + " DOWN")
    return parts.join(" · ")
  }
  readonly property bool revealed: hover.hovered && counts !== "" && countsText.implicitWidth <= width
  // At 1 px the colours don't read. The info lines' rules share its ink and
  // grain (`Cells.RULE_*`).
  readonly property int thickness: Cells.RULE_THICKNESS
  readonly property color plain: Util.alpha(look.foreground, Cells.RULE_INK)
  // Retro draws it as cells on the pixel chart's grain.
  readonly property int pitch: Cells.RULE_PITCH
  readonly property int cells: Math.max(0, Math.floor((width + 1) / pitch))
  // Both ends round down, by the same rule, so they never overlap and equal
  // counts draw equal lengths; what rounding leaves over stays plain.
  readonly property int upCells: Math.min(cells, Math.floor(cells * upShare + 1e-9))
  readonly property int downCells: Math.min(cells - upCells, Math.floor(cells * downShare + 1e-9))
  // Smooth and retro both ease the shares, not the lengths, so a rule resized
  // by the name or order beside it redraws at once. They ease across scrubs,
  // ticks, adds/removals, and list switches, snapping only on first open,
  // unseen, reduced motion, or `settle()`. While `still` they stop where they
  // are, and a change waits.
  property bool seen: true
  property bool still: false
  property real upShare: 0
  property real downShare: 0
  // The list the shares were last set for (`null` until first open / settle).
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
  onSeenChanged: if (!seen) Qt.callLater(function() { if (!root.seen && !root.still) root.settle() })
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() { if (Style.reduceMotion) root.settle() }
  }

  // Each scrub step and replay frame brings a new breadth, mostly the same, so
  // ends already resting or easing there are left be.
  function showBreadth() {
    if (still) return
    var all = breadth.up + breadth.flat + breadth.down + breadth.none
    var up = all ? breadth.up / all : 0
    var down = all ? breadth.down / all : 0
    var had = sharesList !== null
    sharesList = breadth.list
    if (had && up === (upEase.running ? upEase.to : upShare) && down === (downEase.running ? downEase.to : downShare)) return
    upEase.stop()
    downEase.stop()
    if (had && seen && visible && Motion.duration(Style, 200) > 0) {
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

  NumberAnimation { id: upEase; target: root; property: "upShare"; duration: Motion.duration(Style, 200); easing.type: Easing.OutCubic }
  NumberAnimation { id: downEase; target: root; property: "downShare"; duration: Motion.duration(Style, 200); easing.type: Easing.OutCubic }
  onUpShareChanged: if (upEase.running && width > 0 && Math.abs(upShare - upEase.to) * width < 0.5) {
    upEase.stop()
    upShare = upEase.to
  }
  onDownShareChanged: if (downEase.running && width > 0 && Math.abs(downShare - downEase.to) * width < 0.5) {
    downEase.stop()
    downShare = downEase.to
  }

  HoverHandler { id: hover }

  Item {
    anchors.fill: parent
    opacity: root.revealed ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }

    Rectangle {
      visible: !root.look.retro
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: 1
      color: root.plain
    }

    // An end with no rows is zero long, so each slides to and from zero rather
    // than vanishing.
    Rectangle {
      visible: !root.look.retro
      anchors.verticalCenter: parent.verticalCenter
      width: Math.floor(parent.width * root.upShare)
      height: root.thickness
      radius: root.thickness / 2
      color: root.look.upColor
    }

    Rectangle {
      visible: !root.look.retro
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.floor(parent.width * root.downShare)
      height: root.thickness
      radius: root.thickness / 2
      color: root.look.downColor
    }

    Row {
      visible: root.look.retro
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.pitch - root.thickness

      Repeater {
        model: root.look.retro ? root.cells : 0

        Rectangle {
          required property int index
          width: root.thickness
          height: root.thickness
          color: index < root.upCells ? root.look.upColor
            : index >= root.cells - root.downCells ? root.look.downColor : root.plain
        }
      }
    }
  }

  Text {
    id: countsText
    anchors.centerIn: parent
    opacity: root.revealed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
    textFormat: Text.PlainText
    text: root.counts
    color: root.look.dim
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }
}
