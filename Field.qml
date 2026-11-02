import QtQuick
import qs.Ui
// The shell's text field. Its placeholder takes Stonks' dim: the shell's
// Qt.darker(foreground) is as dark as typed text on a light theme.
TextField {
  id: root

  property bool retro: false
  property color dim: foreground

  placeholderTextColor: dim

  Binding {
    target: root.background
    property: "radius"
    value: 0
    when: root.retro
  }
}
