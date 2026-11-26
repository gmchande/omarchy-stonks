import QtQuick
import qs.Commons

// When a chart's live mark plays its burst: smooth's ripples, retro's
// blinks. While the market is open, a new price or the mark's first showing
// (an open, a new chart, a draw-in's end) plays it, and a newer price plays
// it over. A scrub's end, a sheet closing, or the market turning live again
// with the price already played for plays nothing. Hidden mid-burst by an
// open's draw-in, it owes the burst and plays it once it shows; any other
// hide, as a sheet over it, stops it.
Item {
  id: root

  property bool live: false
  property bool still: false
  property bool seen: true
  property bool shown: false
  // Whether the chart is drawing in, asked at a hide: a binding could still
  // hold the value from before the draw-in that hid the mark.
  property var drawing: function() { return false }
  property bool surfaceOpen: false
  property string price: ""
  property Animation burst: null

  property string playedFor: ""
  property bool owed: false
  // From an open until its burst stops.
  property bool opening: false

  function play() {
    if (!live || !shown || still || !seen) return
    // With the shell's animations off, the mark stays still, and the price
    // counts as played for: animations back on, it never plays for it.
    if (Style.reduceMotion) {
      root.owed = false
      root.playedFor = price
      root.opening = false
      return
    }
    if (!owed && price === playedFor) return
    // A restart's stop of a paused burst would end `opening`; an open's burst
    // keeps it.
    var opening = root.opening
    root.owed = false
    root.playedFor = price
    burst.restart()
    root.opening = opening
  }
  property bool ready: false
  Component.onCompleted: {
    ready = true
    if (surfaceOpen && playedFor === "") {
      owed = true
      opening = true
      play()
    }
  }
  onPriceChanged: play()
  onSurfaceOpenChanged: if (ready && surfaceOpen) { owed = true; opening = true; play() }
  onLiveChanged: if (live) play(); else burst.stop()
  onStillChanged: if (!still) play()
  onSeenChanged: {
    if (seen) play()
    else if (!still && burst) burst.stop()
  }
  onShownChanged: {
    if (shown) play()
    else {
      if (burst.running && opening && drawing()) owed = true
      burst.stop()
    }
  }
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() {
      if (!Style.reduceMotion) return
      root.owed = false
      root.opening = false
      if (root.burst) root.burst.stop()
    }
  }
  Connections {
    target: root.burst
    function onRunningChanged() { if (!root.burst.running) root.opening = false }
  }
}
