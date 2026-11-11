import QtQuick
// A view that opens over the rows: a row's menu, the list menu, Manage
// lists, a stock's lists and search. Turned on, it takes the keys a turn
// later, only if still on. Turned off, however it closes, it gives them up
// and still shows through the close fade, but takes no pointer or key.
FocusScope {
  id: root

  property bool active: false
  // What takes the keys as the view opens: the view or its field. Null
  // leaves them with a field already typing, as while a list is named.
  property Item keysTo: root

  signal opened()
  signal closed()

  enabled: active
  onActiveChanged: {
    if (active) {
      opened()
      Qt.callLater(function() { if (root.active && root.keysTo) root.keysTo.forceActiveFocus() })
    } else {
      closed()
      root.focus = false
    }
  }
}
