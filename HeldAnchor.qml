import QtQuick
import Quickshell

// Where the popup's card stands along the bar, held from an open until the
// next. The shell places a card under its anchor live (KeyboardPanel's
// `cardOrigin`, through a TransformWatcher), and the pill widens or narrows
// as `c` or a featured symbol changes what it says, which moved the open
// card sideways. So the card's anchor is this stand-in, put where the pill
// is by `hold()`. It sits on its pill's bar window's content, the item the
// shell measures an anchor against, so the shell finds the window through it
// and sees it move; that window comes from the pill, never from the card,
// which finds its window through this.
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
