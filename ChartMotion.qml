import QtQuick
import "Chart.js" as Chart
import "History.js" as History
import "Quote.js" as Quote
// The chart a surface presents, its moment, and how it arrives: the chart
// on screen, which moment it shows (the scrub, and the replay that drives
// it), and the one motion, a draw-in from the left, for every change of
// the chart on screen. It decides once per change of the view the surface
// holds (`StonksBody`'s held inputs), whoever made it. It draws nothing
// itself.
Item {
  id: root

  // The view the surface holds, value in, and the look, whose retro grain
  // snaps the day's moment to five minutes.
  property var view: null
  property bool surfaceOpen: false
  property bool retro: false
  // The exchanges' calendars, for the breaks in a day (`Chart.chartGeometry`).
  property var calendars: null

  // The chart on screen: the view's once it can be drawn, until then the
  // one already on screen; null only before any chart has been in. A
  // binding, so no reader sees it out of step with the view. `held`, set
  // only by the view handler below, changes only in a change that brings a
  // chart, when this reads the view's instead, and is read here only while
  // the view has no chart, so the order the handler and this binding run
  // in cannot matter.
  readonly property var chart: view && view.chart ? view.chart : held
  property var held: null
  // The chart asked for is still on its way: the one on screen is another.
  readonly property bool loading: !chart || !view || chart.symbol !== view.featured || chart.range !== view.range
  // How far the held chart has dimmed, 0..1: to 1 once the chart asked for
  // has been on its way a quarter of a second since the last change that
  // asked for another, so one that arrives sooner changes nothing; back to
  // 0 as it lands and draws in. Another chart asked for while the dim lifts
  // goes back to it at once; one asked for while it holds keeps it. The
  // hero reads it; this piece runs it.
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
    duration: 160
    easing.type: Easing.OutCubic
  }

  // The chart on screen, measured: a range's history, or the day: Yahoo's
  // quote, the headline and the day's figures, and the day the 1D chart
  // draws and a scrub reads, its last session and the night after it where
  // it has an overnight market (`Chart.viewChart`).
  readonly property bool historyActive: !!chart && chart.range !== "1D"
  readonly property var history: chart ? chart.history : null
  readonly property bool historyShown: historyActive && !!history
  readonly property var quote: chart ? chart.quote : null
  readonly property var day: chart ? chart.day : null
  // The newest print of all, for the line under the price, where the day
  // has one apart from the quote's.
  readonly property var latest: chart ? chart.latest : null
  readonly property var dayGeometry: day ? Chart.chartGeometry(day, calendars) : null
  // A range whose first fetch failed shows the day.
  readonly property var geometry: historyShown ? History.historyGeometry(history) : dayGeometry
  // Scrubbing and replay keep to the prints: from the first to the last.
  // The axis runs on either side, from midnight and to the bell or to
  // midnight, and the hours there hold no price to read and no session to
  // name.
  readonly property int scrubStart: day && day.points.length ? day.points[0].t : 0
  readonly property int scrubEnd: day && Quote.lastPrintTime(day) !== null ? Quote.lastPrintTime(day) : 0

  // The moment shown: 0 for now, otherwise a time on the day or a bar's.
  property int scrubT: 0
  // The moment as the look shows it: retro's day moves in five minutes.
  readonly property int scrubShown: historyActive || !retro || !scrubT ? scrubT : Math.round(scrubT / 300) * 300
  // Where the moment shown sits on the chart, 0..1, or -1.
  readonly property real scrubX: historyShown && scrubShown ? History.historyFraction(history, scrubShown)
    : (!historyActive && day && scrubShown ? Chart.fractionAtTime(day, scrubShown) : -1)
  // How much of the chart's ink the draw-in has drawn, 0..1: the painters
  // sweep it from the left edge to the newest drawn print, so a day partly
  // gone takes its whole time too.
  property real reveal: 1
  // Where a replay has reached, 0..1 along the chart.
  property real replayPosition: 0
  readonly property bool replayRunning: replayAnim.running
  // A replay's length: what plays alongside it keeps to it, and to its
  // InOutSine.
  readonly property int replayDuration: 2000
  // A replay starts, from `from` to `to` along the chart: said before its
  // first frame, so what plays alongside starts with it.
  signal replayStarted(real from, real to)
  // A replay cut short: stopped, or held by a closing surface. One that runs
  // to its end says nothing.
  signal replayCut()
  // Where a replay's scrub has reached along the plot, 0..1, or -1 with no
  // replay running: the painters draw it in behind that, in the plot's own
  // terms, retro's whole columns included, apart from the draw-in's sweep.
  readonly property real replayX: replayRunning && scrubX >= 0 ? scrubX : -1
  // How much of the chart is drawn, 0..1: a replay draws it in behind its
  // scrub, and otherwise the draw-in says.
  readonly property real drawn: replayX >= 0 ? replayX : reveal

  // The view as this piece last saw it. Each change of the view is compared
  // with it once: another chart on screen draws in; a chart asked for and
  // not ready keeps the one on screen whole and still; new data for the
  // same chart is taken as it is.
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
    // that still covers their moment.
    if (moved || asked || (refreshed && scrubT && !covers(next, scrubT))) clearScrub()
    if (moved) {
      if (surfaceOpen) drawIn()
    } else if (asked) {
      drawInAnim.stop()
      reveal = 1
      if (loading && dimmed === 0 && surfaceOpen) slowTimer.restart()
    }
  }

  // A chart's identity: its symbol and range, and whether the day stands in
  // for a range whose first fetch failed, so a retry that lands is a change.
  function chartKeyOf(chart) {
    return chart ? chart.symbol + "|" + chart.range + (chart.failed ? "|failed" : "") : ""
  }

  // Whether `chart`'s data still holds the moment `t`: a refresh that brings
  // a range's new history, or the day's next session, may not.
  function covers(chart, t) {
    if (chart.history) return History.historyFraction(chart.history, t) >= 0
    return !!chart.day && Chart.fractionAtTime(chart.day, t) >= 0
  }

  // A chart kept on show while the next one loads takes no scrub and no
  // replay; nor does a closing surface.
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

  // The one motion: the chart draws in from the left, in 320 ms.
  function drawIn() {
    drawInAnim.restart()
  }

  // An opening surface draws the chart on screen in. While the chart asked
  // for is on its way, the one on screen stays whole, and the new one draws
  // in when it lands; the open is the change the dim counts from.
  function revealChart() {
    drawInAnim.stop()
    reveal = 1
    if (!loading) drawIn()
    else slowTimer.restart()
  }

  // A replay is a scrub that drives itself, with the chart drawing in behind
  // it, so the header, the price, and the bull or bear follow it: along the
  // chart, the way it is laid out: on the day by print for a US listing and
  // by time for any other, and by bar on a range.
  function replay() {
    if (loading) return
    stopReplay()
    drawInAnim.stop()
    reveal = 1
    if (historyActive ? !historyShown || history.bars.length < 2 : !geometry || !scrubEnd) return
    replayAnim.from = historyActive ? 0 : Chart.fractionAtTime(day, scrubStart)
    replayAnim.to = historyActive ? 1 : Chart.fractionAtTime(day, scrubEnd)
    // On its first moment at once, before the animation's first step.
    scrubTo(replayAnim.from)
    replayStarted(replayAnim.from, replayAnim.to)
    replayAnim.start()
  }

  function stopReplay() {
    if (!replayAnim.running) return
    replayAnim.stop()
    replayCut()
  }

  // A closing surface stops what moves where it is: a replay keeps what it
  // had drawn, a draw-in what it had revealed, and the dim where it was.
  // Only what runs can pause.
  function freeze() {
    if (replayAnim.running) {
      replayAnim.pause()
      replayCut()
    }
    drawInAnim.stop()
    slowTimer.stop()
    dimAnim.stop()
  }

  // At rest before an open's first frame: now, whole, and undimmed.
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
    duration: 320
    easing.type: Easing.OutCubic
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
