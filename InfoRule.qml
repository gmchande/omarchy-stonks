pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Cells.js" as Cells

// A range drawn as a thin rule, its low at the left and its high at the
// right, with a tick standing over it where the price sits: the breadth
// rule's ink and thickness, and in retro its cells on the same grain, the
// tick a column of three. Without both ends and a price it is the empty
// track alone, the way the 1D chart leaves the hours still to come.
Item {
  id: root

  property var low: null
  property var high: null
  property var price: null
  property bool retro: false
  property color foreground: Color.foreground

  readonly property int thickness: Cells.RULE_THICKNESS
  readonly property int pitch: Cells.RULE_PITCH
  readonly property color plain: Qt.rgba(foreground.r, foreground.g, foreground.b, Cells.RULE_INK)
  readonly property int cells: Math.max(0, Math.floor((width + 1) / pitch))
  // Where the price sits, 0 to 1, or -1 for no tick.
  readonly property real place: low !== null && high !== null && price !== null && high > low
    ? Math.max(0, Math.min(1, (price - low) / (high - low))) : -1
  // The tick's left edge: on a cell in retro, so both looks put it at the
  // same place.
  readonly property int tickX: place < 0 || cells < 1 ? -1 : Math.round(place * (cells - 1)) * pitch

  implicitHeight: pitch * 2 + thickness

  Rectangle {
    visible: !root.retro
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: root.thickness
    radius: root.thickness / 2
    color: root.plain
  }

  Row {
    visible: root.retro
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.pitch - root.thickness

    Repeater {
      model: root.retro ? root.cells : 0

      Rectangle {
        width: root.thickness
        height: root.thickness
        color: root.plain
      }
    }
  }

  Rectangle {
    objectName: "infoTick"
    visible: !root.retro && root.tickX >= 0
    x: root.tickX
    width: root.thickness
    height: root.height
    radius: root.thickness / 2
    color: root.foreground
  }

  Column {
    objectName: "infoTickCells"
    visible: root.retro && root.tickX >= 0
    x: root.tickX
    spacing: root.pitch - root.thickness

    Repeater {
      model: 3

      Rectangle {
        width: root.thickness
        height: root.thickness
        color: root.foreground
      }
    }
  }
}
