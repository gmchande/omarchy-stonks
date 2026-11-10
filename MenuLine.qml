import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Motion.js" as Motion
// One line of a menu: the cursor's fill and bar, what the line says drawn
// over them, and a click anywhere on it.
Item {
  id: line

  property Look look
  property bool isCursor: false
  // A line that can't be taken now takes no click.
  property bool takes: true

  signal taken()

  Rectangle {
    anchors.fill: parent
    radius: line.look.retro ? 0 : Style.cornerRadius
    color: line.isCursor ? Style.hoverFillFor(line.look.foreground, Commons.Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 60) } }
  }

  CursorBar {
    visible: line.isCursor
    retro: line.look.retro
    foreground: line.look.foreground
  }

  MouseArea {
    anchors.fill: parent
    enabled: line.takes
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: line.taken()
  }
}
