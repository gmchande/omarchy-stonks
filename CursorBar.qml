import QtQuick
import qs.Commons
import qs.Commons as Commons
// The cursor's one mark on a stock's row, in the shell's selected state
// colour.
Rectangle {
  property bool retro: false
  property color foreground: Commons.Color.foreground

  x: 0
  y: Style.space(6)
  width: Style.space(2)
  height: (parent ? parent.height : 0) - Style.space(12)
  radius: retro ? 0 : width / 2
  color: Style.selectedStateColor(foreground, Commons.Color.accent)
}
