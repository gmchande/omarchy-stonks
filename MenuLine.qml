import QtQuick
import qs.Commons
import qs.Ui
// One line of a menu: the shell's cursor row, what the line says drawn
// over it, and a click anywhere on it.
Item {
  id: line

  property Look look
  property bool isCursor: false
  // A line that can't be taken now takes no click.
  property bool takes: true

  signal taken()

  CursorSurface {
    anchors.fill: parent
    hasCursor: line.isCursor
    foreground: line.look.foreground
    radius: line.look.retro ? 0 : Style.cornerRadius
  }

  MouseArea {
    anchors.fill: parent
    enabled: line.takes
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: line.taken()
  }
}
