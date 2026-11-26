import QtQuick
import qs.Commons
import "Motion.js" as Motion
// A view that opens over the rows: a row's menu, the list menu, Manage
// lists, a stock's lists and search. Turned on, it takes the keys a turn
// later, only if still on. Turned off, however it closes, it gives them up
// and fades out over 100 ms without taking pointer or key input. One that
// `fades` fades in over 140 ms as it shows, where Omarchy's surfaces appear.
FocusScope {
  id: root

  property bool open: false
  property bool active: false
  // What takes the keys as the view opens: the view or its field. Null
  // leaves them with a field already typing, as while a list is named.
  property Item keysTo: root
  property bool fades: false
  property bool seen: true
  property bool still: false
  readonly property bool closing: disappear.running

  visible: false
  Component.onCompleted: settle()

  signal settled()

  function settle() {
    appear.stop()
    disappear.stop()
    visible = open
    opacity = 1
    settled()
  }

  onOpenChanged: {
    if (open) {
      disappear.stop()
      visible = true
      if (fades && seen && !still && Motion.duration(Style, 140) > 0) {
        appear.stop()
        opacity = 0
        appear.start()
      } else {
        appear.stop()
        opacity = 1
      }
      return
    }
    if (visible && fades && seen && !still && Motion.duration(Style, 100) > 0) {
      appear.stop()
      disappear.restart()
    } else {
      appear.stop()
      disappear.stop()
      visible = false
      opacity = 1
    }
  }
  onStillChanged: if (still) {
    if (appear.running) appear.pause()
    if (disappear.running) disappear.pause()
  }
  onSeenChanged: if (!seen) Qt.callLater(function() { if (!root.seen && !root.still) root.settle() })
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() { if (Style.reduceMotion) root.settle() }
  }
  NumberAnimation { id: appear; target: root; property: "opacity"; to: 1; duration: Motion.duration(Style, 140); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
  NumberAnimation {
    id: disappear
    target: root
    property: "opacity"
    to: 0
    duration: Motion.duration(Style, 100)
    easing.type: Easing.OutCubic
    onFinished: {
      root.visible = false
      root.opacity = 1
    }
  }
  // Style.easeOut spends its last frames on the last 1%, which no frame shows.
  onOpacityChanged: {
    if (appear.running && opacity > 0.985) {
      appear.stop()
      opacity = 1
    } else if (disappear.running && opacity < 0.01) {
      disappear.stop()
      visible = false
      opacity = 1
    }
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
