import QtQuick
import qs.Commons
import "Motion.js" as Motion
// A view that opens over the rows: a row's menu, the list menu, Manage
// lists, a stock's lists and search. Turned on, it takes the keys a turn
// later, only if still on. Turned off, however it closes, it gives them up
// and still shows through the close fade, but takes no pointer or key. One
// that `fades` fades in over 140 ms as it shows, where Omarchy's surfaces
// appear.
FocusScope {
  id: root

  property bool active: false
  // What takes the keys as the view opens: the view or its field. Null
  // leaves them with a field already typing, as while a list is named.
  property Item keysTo: root
  property bool fades: false

  onVisibleChanged: if (fades && visible) {
    opacity = 0
    appear.restart()
  }
  NumberAnimation { id: appear; target: root; property: "opacity"; to: 1; duration: Motion.duration(Style, 140); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
  // Style.easeOut spends its last frames on the last 1%, which no frame shows.
  onOpacityChanged: if (appear.running && opacity > 0.985) {
    appear.stop()
    opacity = 1
  }

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
