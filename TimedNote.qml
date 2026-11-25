import QtQuick
import qs.Commons
import "Motion.js" as Motion

// The time something the footer says lasts: `lasts` ms, the last 600 of
// them fading `shown` to nothing, then `ended`. It waits while the pointer
// is on it, and a closed surface's stays as the close left it. The surface
// keeps what is said; `says` tells this whether there is any.
Item {
  id: root

  property int lasts: 2500
  property bool says: false
  property bool hovered: false
  property bool surfaceOpen: false
  property real shown: 1

  signal ended()

  onHoveredChanged: hold()

  // From the start again, as something is said or the pointer comes or goes.
  function hold() {
    if (!surfaceOpen) {
      wait.stop()
      return
    }
    fade.stop()
    shown = 1
    if (says && !hovered) wait.restart()
    else wait.stop()
  }

  function freeze() {
    wait.stop()
    fade.stop()
  }

  function reset() {
    freeze()
    shown = 1
  }

  Timer {
    id: wait
    interval: root.lasts - fade.duration
    onTriggered: fade.start()
  }

  NumberAnimation {
    id: fade
    target: root
    property: "shown"
    from: 1
    to: 0
    duration: Motion.duration(Style, 600)
    onFinished: root.ended()
  }
}
