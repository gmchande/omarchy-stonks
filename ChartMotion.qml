import QtQuick
import qs.Commons
import "Chart.js" as Chart
import "History.js" as History
import "Quote.js" as Quote
import "Motion.js" as Motion
// The chart a surface shows, the moment it shows (the scrub, and the replay
// that drives it), and the one motion, a draw-in from the left, for every
// change of chart. It decides once per change of the view the surface holds,
// whoever made it, and draws nothing itself.
Item {
  id: root

  property var view: null
  property bool surfaceOpen: false
  // Retro snaps the day's moment to five minutes.
  property bool retro: false
  property var calendars: null

  // The view's chart once it can be drawn, until then the one already on
  // screen. A binding, so no reader sees it out of step with the view. `held`
  // changes only with a view that brings a chart, and is read only while the
  // view has none, so the order the handler and this binding run in can't
  // matter.
  readonly property var chart: view && view.chart ? view.chart : held
  property var held: null
  readonly property bool loading: !chart || !view || chart.symbol !== view.featured || chart.range !== view.range
  // The held chart dims once the next is a quarter of a second on its way, so
  // one that comes sooner changes nothing, and lifts as it lands. Another chart
  // asked for while the dim lifts goes back to it at once.
  property real dimmed: 0
  onLoadingChanged: {
    if (!loading) {
      slowTimer.stop()
      dimTo(0)
    } else if (dimmed > 0) dimTo(1)
    else if (surfaceOpen) slowTimer.restart()
  }
  function dimTo(target) {
    dimAnim.stop()
    if (dimmed === target) return
    dimAnim.from = dimmed
    dimAnim.to = target
    dimAnim.start()
  }
  Timer {
    id: slowTimer
    interval: 250
    onTriggered: if (root.loading) root.dimTo(1)
  }
  NumberAnimation {
    id: dimAnim
    target: root
    property: "dimmed"
    duration: Motion.duration(Style, 160)
    easing.type: Easing.Bezier
    easing.bezierCurve: Motion.curve(Style)
  }

  readonly property bool historyActive: !!chart && chart.range !== "1D"
  readonly property var history: chart ? chart.history : null
  readonly property bool historyShown: historyActive && !!history
  readonly property var quote: chart ? chart.quote : null
  readonly property var day: chart ? chart.day : null
  // Where the day has a newer print than the quote's own, for the line under
  // the price.
  readonly property var latest: chart ? chart.latest : null
  readonly property var dayGeometry: day ? Chart.chartGeometry(day, calendars) : null
  // A range whose first fetch failed shows the day.
  readonly property var geometry: historyShown ? History.historyGeometry(history) : dayGeometry
  // Scrubbing and replay keep from the first print to the last: while the day
  // runs, its axis runs past them, through hours with no price to read.
  readonly property int scrubStart: day && day.points.length ? day.points[0].t : 0
  readonly property int scrubEnd: day && Quote.lastPrintTime(day) !== null ? Quote.lastPrintTime(day) : 0

  // 0 for now.
  property int scrubT: 0
  // Retro's day moves in five minutes, but a scrub held at either end reads
  // that print, so a lone trade or the newest isn't swapped for the one before.
  readonly property int scrubShown: historyActive || !retro || !scrubT || scrubT === scrubStart || scrubT === scrubEnd ? scrubT
    : Math.max(scrubStart, Math.min(scrubEnd, Math.round(scrubT / 300) * 300))
  readonly property real scrubX: historyShown && scrubShown ? History.historyFraction(history, scrubShown)
    : (!historyActive && day && scrubShown ? Chart.fractionAtTime(day, scrubShown) : -1)
  // The painters sweep the draw-in to the newest print, so a day partly gone
  // takes its whole time too.
  property real reveal: 1
  property real replayPosition: 0
  readonly property bool replayRunning: replayAnim.running
  // What plays alongside keeps to it, and to its InOutSine. With the
  // shell's animations off it is 0, and a replay shows the whole chart at
  // once, with no sound.
  readonly property int replayDuration: Motion.duration(Style, 2000)
  // Said before its first frame, so what plays alongside starts with it.
  signal replayStarted(real from, real to)
  // Stopped, or held by a closing surface; one that runs to its end says
  // nothing.
  signal replayCut()
  // The painters draw in behind it in the plot's terms, retro's whole columns
  // included.
  readonly property real replayX: replayRunning && scrubX >= 0 ? scrubX : -1
  readonly property real drawn: replayX >= 0 ? replayX : reveal

  // Each change of the view is compared with this once: another chart on
  // screen draws in; one asked for and not ready keeps the chart on screen
  // whole and still; new data for the same chart is taken as it is.
  property var seen: null
  onViewChanged: {
    var before = seen
    seen = view
    var last = held
    var next = view && view.chart ? view.chart : held
    held = next
    if (!before) return
    var moved = chartKeyOf(next) !== chartKeyOf(last)
    var refreshed = !moved && next !== last
    var asked = view.featured !== before.featured || view.range !== before.range
    // A replay and a scrub belong to the chart they started on, and to data
    // that still holds their moment.
    if (moved || asked || (refreshed && scrubT && !covers(next, scrubT))) clearScrub()
    if (moved) {
      if (surfaceOpen) drawIn()
    } else if (asked) {
      drawInAnim.stop()
      reveal = 1
      if (loading && dimmed === 0 && surfaceOpen) slowTimer.restart()
    }
  }

  // With the day standing in for a failed range, a retry that lands is a
  // change.
  function chartKeyOf(chart) {
    return chart ? chart.symbol + "|" + chart.range + (chart.failed ? "|failed" : "") : ""
  }

  // A refresh that brings a range's new history, or the day's next session,
  // may not hold `t`.
  function covers(chart, t) {
    if (chart.history) return History.historyFraction(chart.history, t) >= 0
    return !!chart.day && Chart.fractionAtTime(chart.day, t) >= 0
  }

  // A chart held while the next loads takes no scrub and no replay; a closing
  // surface takes no scrub.
  function scrubTo(fraction) {
    if (loading || !surfaceOpen) return
    if (historyActive) {
      if (!historyShown) return
      var bar = History.historyBarAt(history, fraction)
      scrubT = bar ? bar.t : 0
      return
    }
    if (!day || !scrubEnd) return
    var t = Chart.timeAtFraction(day, fraction)
    scrubT = Math.max(scrubStart, Math.min(t, scrubEnd))
  }

  function nudgeScrub(steps) {
    if (loading) return
    if (historyActive) {
      if (!historyShown || history.bars.length < 2) return
      var fraction = scrubT ? History.historyFraction(history, scrubT) : 1
      scrubTo(fraction + steps / (history.bars.length - 1))
      return
    }
    if (!day || !scrubEnd) return
    scrubT = Math.max(scrubStart, Chart.stepTime(day, scrubT || scrubEnd, steps, scrubEnd))
  }

  function clearScrub() {
    stopReplay()
    scrubT = 0
  }

  readonly property bool drawingIn: drawInAnim.running
  function drawIn() {
    drawInAnim.restart()
  }

  // While the chart asked for is on its way, the one on screen stays whole and
  // the new one draws in when it lands; the open is what the dim counts from.
  function revealChart() {
    drawInAnim.stop()
    reveal = 1
    if (!loading) drawIn()
    else slowTimer.restart()
  }

  // A scrub that drives itself, the chart drawing in behind it, so the header,
  // the price and the animal follow it: by print on a US listing's day, by
  // time on any other's, and by bar on a range.
  function replay() {
    if (loading) return
    stopReplay()
    drawInAnim.stop()
    reveal = 1
    if (historyActive ? !historyShown || history.bars.length < 2 : !geometry || !scrubEnd) return
    if (!replayDuration) return
    replayAnim.from = historyActive ? 0 : Chart.fractionAtTime(day, scrubStart)
    replayAnim.to = historyActive ? 1 : Chart.fractionAtTime(day, scrubEnd)
    // Its first moment at once, before the animation's first step.
    scrubTo(replayAnim.from)
    replayStarted(replayAnim.from, replayAnim.to)
    replayAnim.start()
  }

  function stopReplay() {
    if (!replayAnim.running) return
    replayAnim.stop()
    replayCut()
  }

  // A closing surface stops what moves where it is: a replay keeps what it had
  // drawn, a draw-in what it had revealed, the dim where it was.
  function freeze() {
    if (replayAnim.running) {
      replayAnim.pause()
      replayCut()
    }
    drawInAnim.stop()
    slowTimer.stop()
    dimAnim.stop()
  }

  // Before an open's first frame.
  function reset() {
    stopReplay()
    reveal = 1
    scrubT = 0
    dimmed = 0
  }

  NumberAnimation {
    id: drawInAnim
    target: root
    property: "reveal"
    from: 0
    to: 1
    duration: Motion.duration(Style, 320)
    easing.type: Easing.Bezier
    easing.bezierCurve: Motion.curve(Style)
  }

  NumberAnimation {
    id: replayAnim
    target: root
    property: "replayPosition"
    duration: root.replayDuration
    easing.type: Easing.InOutSine
    onFinished: root.scrubT = 0
  }
  onReplayPositionChanged: if (replayAnim.running) scrubTo(replayPosition)
}
