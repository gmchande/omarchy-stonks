import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Robinhood's prints for every listing asked, in one run of requests of at
// most 75 listings each (`Overnight.OVERNIGHT_BATCH`), Robinhood's limit:
// the overnight session's, and the hours outside Yahoo's day that the 1D
// chart draws (`Overnight.dayChart`). Each answer is a day, the last 288
// slots the 24/5 market traded, which reaches every hour a chart can draw,
// so it replaces the prints kept. An entry is { status, bars }: "ok" with
// the prints Robinhood has, none for a listing it does not trade; or
// "failed", keeping the last good prints. `entries` holds answers only. One
// run at a time: a request asked for while one is out is not sent, and the
// service asks again for what it still wants once that is answered, so
// nothing goes once nothing wants it. While Robinhood's gate pauses the
// host, a request fails at once, keeping the last good prints; the gate's
// budget may let only some of a run's requests go.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // When the last request went out, answered or not: the service asks again
  // by it (`Overnight.overnightDue`).
  property int askedAt: 0
  // The run out, as its requests' symbols, in the order of their URLs,
  // until it is answered.
  property var batches: []
  readonly property bool busy: batches.length > 0

  // `at` is the service's clock as it asks: the clock's own handlers may run
  // before this binding to it has caught up. While the gate holds the host,
  // the request fails a turn later, out of the change that asked for it.
  function fetch(symbols, at) {
    if (busy || !symbols.length) return
    var batches = []
    for (var i = 0; i < symbols.length; i += Overnight.OVERNIGHT_BATCH) batches.push(symbols.slice(i, i + Overnight.OVERNIGHT_BATCH))
    var granted = gate ? gate.take(batches.length) : batches.length
    root.batches = granted > 0 ? batches.slice(0, granted) : batches
    root.askedAt = at
    if (granted === 0) {
      heldTimer.restart()
      return
    }
    if (gate) root.ticket = gate.ticket
    fetchProc.command = Fetch.curlCommand(root.batches.map(Overnight.overnightUrl), Fetch.overnightCap(root.batches[0].length))
    fetchProc.running = true
  }

  // Each request's answer is read with its own symbols. An answer with
  // nothing new for a symbol keeps the prints it had, so its chart is not
  // built again. Each symbol's entry says when it was asked (`at`), so a
  // symbol no longer asked for ages on its own.
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
      try { parsed = answer && answer.kind === "ok" ? Overnight.parseOvernight(JSON.parse(answer.body), batch) : null } catch (e) { parsed = null }
      batch.forEach(function(symbol) {
        var had = entries[symbol]
        if (!parsed) {
          next[symbol] = { status: "failed", bars: had ? had.bars : [], at: askedAt }
          return
        }
        var bars = parsed[symbol]
        if (had && JSON.stringify(had.bars) === JSON.stringify(bars)) bars = had.bars
        next[symbol] = { status: "ok", bars: bars, at: askedAt }
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
