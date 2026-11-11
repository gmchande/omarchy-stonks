pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Cells.js" as Cells

// A range as a thin rule in the breadth rule's ink, low at the left and high
// at the right, with a tick where the price sits. Without both ends and a
// price it is the empty track, as the 1D chart leaves hours still to come.
Item {
  id: root

  property var low: null
  property var high: null
  property var price: null
  property Look look

  readonly property int thickness: Cells.RULE_THICKNESS
  readonly property int pitch: Cells.RULE_PITCH
  readonly property color plain: Util.alpha(look.foreground, Cells.RULE_INK)
  readonly property int cells: Math.max(0, Math.floor((width + 1) / pitch))
  // -1 for no tick.
  readonly property real place: low !== null && high !== null && price !== null && high > low
    ? Math.max(0, Math.min(1, (price - low) / (high - low))) : -1
  // On a cell in retro, so both looks put the tick in the same place.
  readonly property int tickX: place < 0 || cells < 1 ? -1 : Math.round(place * (cells - 1)) * pitch

  implicitHeight: pitch * 2 + thickness

  Rectangle {
    visible: !root.look.retro
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: root.thickness
    radius: root.thickness / 2
    color: root.plain
  }

  Row {
    visible: root.look.retro
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.pitch - root.thickness

    Repeater {
      model: root.look.retro ? root.cells : 0

      Rectangle {
        width: root.thickness
        height: root.thickness
        color: root.plain
      }
    }
  }

  Rectangle {
    objectName: "infoTick"
    visible: !root.look.retro && root.tickX >= 0
    x: root.tickX
    width: root.thickness
    height: root.height
    radius: root.thickness / 2
    color: root.look.foreground
  }

  Column {
    objectName: "infoTickCells"
    visible: root.look.retro && root.tickX >= 0
    x: root.tickX
    spacing: root.pitch - root.thickness

    Repeater {
      model: 3

      Rectangle {
        width: root.thickness
        height: root.thickness
        color: root.look.foreground
      }
    }
  }
}
