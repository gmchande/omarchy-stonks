import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Whether Robinhood trades each US stock or ETF all day in its 24 Hour
// Market (`all_day_tradability`), from its keyless instruments: only a
// listing it does draws its overnight prints after its day
// (`Chart.viewChart`). Every listing asked goes in one run of requests of at
// most 50 listings each (`Overnight.ALL_DAY_BATCH`), so each answer fits one
// page. An entry is { status, allDay, at }, `at` the service's clock as it
// asked: "ok" with Robinhood's answer, kept a day (`Overnight.allDayDue`); or
// "failed", keeping the last good answer, and not all-day without one.
// `entries` holds answers only. One run at a time: a request asked for while
// one is out is not sent, and the service asks again for what it still wants
// once that is answered. The gate's budget may let only some of a run's
// requests go.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  property int askedAt: 0
  // The run out, as its requests' symbols, in the order of their URLs,
  // until it is answered.
  property var batches: []
  readonly property bool busy: batches.length > 0

  // While the gate holds the host, the request fails a turn later, out of
  // the change that asked for it.
  function fetch(symbols, at) {
    if (busy || !symbols.length) return
    var batches = []
    for (var i = 0; i < symbols.length; i += Overnight.ALL_DAY_BATCH) batches.push(symbols.slice(i, i + Overnight.ALL_DAY_BATCH))
    var granted = gate ? gate.take(batches.length) : batches.length
    root.batches = granted > 0 ? batches.slice(0, granted) : batches
    root.askedAt = at
    if (granted === 0) {
      heldTimer.restart()
      return
    }
    if (gate) root.ticket = gate.ticket
    fetchProc.command = Fetch.curlCommand(root.batches.map(Overnight.allDayUrl), Fetch.instrumentsCap(root.batches[0].length))
    fetchProc.running = true
  }

  // Each request's answer is read with its own symbols; a bad one fails
  // them.
  function receive(text) {
    var got = Fetch.answers(text)
    if (gate && got.length) {
      gate.report(got.map(function(a) { return a.kind }),
        Math.max.apply(null, got.map(function(a) { return a.retryAfter })), root.ticket)
    }
    var next = Object.assign({}, entries)
    batches.forEach(function(batch, b) {
      var answer = got.filter(function(a) { return a.index === b })[0]
      var parsed = null
      try { parsed = answer && answer.kind === "ok" ? Overnight.parseAllDay(JSON.parse(answer.body), batch) : null } catch (e) { parsed = null }
      batch.forEach(function(symbol) {
        var had = entries[symbol]
        next[symbol] = parsed
          ? { status: "ok", allDay: parsed[symbol], at: askedAt }
          : { status: "failed", allDay: had ? had.allDay : false, at: askedAt }
      })
    })
    root.batches = []
    root.entries = next
  }

  Timer {
    id: heldTimer
    interval: 0
    onTriggered: root.receive("")
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(String(text || ""))
    }
  }
}
