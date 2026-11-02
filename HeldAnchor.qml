import QtQuick
import Quickshell

// The open card's anchor, put where the pill is by hold() until the next
// open: the shell follows an anchor live (KeyboardPanel's `cardOrigin`), and
// the pill resizes as its words change. It sits on the bar window's content
// item, which the shell measures against and finds the window through.
Item {
  id: root

  property Item pill: null
  readonly property var barWindow: pill ? pill.QsWindow.window : null

  parent: barWindow ? barWindow.contentItem : null
  visible: false

  function hold() {
    if (!pill || !parent) return
    var at = pill.mapToItem(parent, 0, 0)
    x = at.x
    y = at.y
    width = pill.width
    height = pill.height
  }
}
