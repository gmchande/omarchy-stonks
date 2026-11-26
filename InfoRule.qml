pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Cells.js" as Cells
import "Motion.js" as Motion

// A range as a thin rule in the breadth rule's ink, low at the left and high
// at the right, with a tick where the price sits. Without both ends and a
// price it is the empty track, as the 1D chart leaves hours still to come.
Item {
  id: root

  property var low: null
  property var high: null
  property var price: null
  property Look look
  property bool seen: true
  property bool still: false

  readonly property int thickness: Cells.RULE_THICKNESS
  readonly property int pitch: Cells.RULE_PITCH
  readonly property color plain: Util.alpha(look.foreground, Cells.RULE_INK)
  readonly property int cells: Math.max(0, Math.floor((width + 1) / pitch))
  // -1 for no tick.
  readonly property real place: low !== null && high !== null && price !== null && high > low
    ? Math.max(0, Math.min(1, (price - low) / (high - low))) : -1
  // On a cell in retro, so both looks put the tick in the same place.
  readonly property int tickX: place < 0 || cells < 1 ? -1 : Math.round(place * (cells - 1)) * pitch

  // Normalized 0..1 while moving, so a resize never lags; at rest, the exact
  // cell `tickX`. Smooth glides on OutCubic; retro steps cell-by-cell.
  property real lastPlace: -1
  property real shownPlace: -1
  property real tickOpacity: 0
  readonly property real drawnX: cells < 1 ? -1
    : !placeAnim.running ? (place >= 0 ? tickX : (shownPlace >= 0 ? Math.round(shownPlace * (cells - 1)) * pitch : -1))
    : (look.retro ? Math.round(shownPlace * (cells - 1)) * pitch : shownPlace * (cells - 1) * pitch)

  Component.onCompleted: settle()
  function settle() {
    placeAnim.stop()
    tickFade.stop()
    lastPlace = place
    shownPlace = place
    tickOpacity = place >= 0 ? 1 : 0
  }
  onStillChanged: if (still) {
    if (placeAnim.running) placeAnim.pause()
    if (tickFade.running) tickFade.pause()
  }
  onSeenChanged: if (!seen) Qt.callLater(function() { if (!root.seen && !root.still) root.settle() })
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() { if (Style.reduceMotion) root.settle() }
  }
  onPlaceChanged: {
    var prev = lastPlace
    lastPlace = place
    if (still) return
    if (!seen || !visible) {
      settle()
      return
    }
    var moveMs = Motion.duration(Style, Motion.SWITCH_MS)
    var fadeMs = Motion.duration(Style, 140)
    if (place < 0) {
      if (prev < 0) return
      if (fadeMs <= 0) {
        settle()
        return
      }
      placeAnim.stop()
      tickFade.stop()
      tickFade.to = 0
      tickFade.start()
      return
    }
    if (prev < 0) {
      placeAnim.stop()
      shownPlace = place
      if (fadeMs <= 0) {
        tickFade.stop()
        tickOpacity = 1
        return
      }
      tickFade.stop()
      tickFade.to = 1
      tickFade.start()
      return
    }
    tickFade.stop()
    tickOpacity = 1
    if (moveMs <= 0 || cells <= 1) {
      placeAnim.stop()
      shownPlace = place
      return
    }
    var span = (cells - 1) * pitch
    var from = placeAnim.running ? shownPlace : Math.round(prev * (cells - 1)) / (cells - 1)
    var to = Math.round(place * (cells - 1)) / (cells - 1)
    if (Math.abs(to - from) * span < 0.5) {
      placeAnim.stop()
      shownPlace = place
      return
    }
    placeAnim.stop()
    shownPlace = from
    placeAnim.to = to
    placeAnim.start()
  }
  NumberAnimation {
    id: placeAnim
    target: root
    property: "shownPlace"
    duration: Motion.duration(Style, Motion.SWITCH_MS)
    easing.type: root.look.retro ? Easing.Linear : Easing.OutCubic
    onFinished: root.shownPlace = root.place
  }
  onShownPlaceChanged: if (placeAnim.running && !look.retro && cells > 1
    && Math.abs(shownPlace - placeAnim.to) * (cells - 1) * pitch < 0.5) {
    placeAnim.stop()
    shownPlace = place
  }
  NumberAnimation {
    id: tickFade
    target: root
    property: "tickOpacity"
    duration: Motion.duration(Style, 140)
    easing.type: Easing.OutCubic
  }
  onTickOpacityChanged: if (tickFade.running && Math.abs(tickOpacity - tickFade.to) < 0.01) {
    tickFade.stop()
    tickOpacity = tickFade.to
  }

  implicitHeight: pitch * 2 + thickness

  Rectangle {
    visible: !root.look.retro
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: root.thickness
    radius: root.thickness / 2
    color: root.plain
  }

  Row {
    visible: root.look.retro
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.pitch - root.thickness

    Repeater {
      model: root.look.retro ? root.cells : 0

      Rectangle {
        width: root.thickness
        height: root.thickness
        color: root.plain
      }
    }
  }

  Rectangle {
    visible: !root.look.retro && root.tickOpacity > 0 && root.drawnX >= 0
    x: root.drawnX
    opacity: root.tickOpacity
    width: root.thickness
    height: root.height
    radius: root.thickness / 2
    color: root.look.foreground
  }

  Column {
    visible: root.look.retro && root.tickOpacity > 0 && root.drawnX >= 0
    x: root.drawnX
    opacity: root.tickOpacity
    spacing: root.pitch - root.thickness

    Repeater {
      model: 3

      Rectangle {
        width: root.thickness
        height: root.thickness
        color: root.look.foreground
      }
    }
  }
}
