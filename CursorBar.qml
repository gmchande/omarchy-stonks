import QtQuick
import qs.Commons
// The cursor's one mark, on a watchlist row and in every list view: a bar
// down the row's left edge, in the shell's selected state colour. Its row
// also takes the shell's hover-cursor fill.
Rectangle {
  property bool retro: false
  property color foreground: Color.foreground
  // The row's height; a row that grows under itself keeps its bar.
  property real rowHeight: parent ? parent.height : 0

  objectName: "cursorBar"
  x: 0
  y: Style.space(6)
  width: Style.space(2)
  height: rowHeight - Style.space(12)
  radius: retro ? 0 : width / 2
  color: Style.selectedStateColor(foreground, Color.accent)
}
