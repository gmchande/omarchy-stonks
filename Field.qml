import QtQuick
import qs.Ui
// The shell's text field, in Stonks' looks: search's, a new list's name, and
// a rename. Its hint is secondary text's dim, as the shell's own
// Qt.darker(foreground) is as dark as typed text on a light theme, and in
// retro its corners are square, as every fill there is (the design QA of
// 19 October). The shell's focus and hover borders stay.
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
