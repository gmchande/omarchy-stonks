import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Robinhood's prints for every listing with an overnight market, in one
// request: the overnight session's, and the hours outside Yahoo's day that
// the 1D chart draws (`Overnight.dayChart`). Each answer is a day, the last
// 288 slots the 24/5 market traded, which reaches every hour a chart can
// draw, so it replaces the prints kept. An entry is { status, bars }: "ok"
// with the prints Robinhood has, none for a listing it does not trade; or
// "failed", keeping the last good prints. `entries` holds answers only. One
// curl at a time; symbols asked for while one is out, and not in it, are
// asked for once it is answered. While Robinhood's gate pauses the host, a
// request fails at once, keeping the last good prints.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // The service's clock, which stamps a request the feed sends of its own
  // accord: one held while another was out.
  property int now: 0
  // When the last request went out, answered or not: the service asks again
  // by it (`Overnight.overnightDue`).
  property int askedAt: 0
  property var asking: []
  property var wanted: []

  // `at` is the service's clock as it asks: the clock's own handlers may run
  // before this binding to it has caught up. While the gate holds the host,
  // the request fails a turn later, out of the change that asked for it.
  function fetch(symbols, at) {
    if (fetchProc.running || heldTimer.running) {
      var more = symbols.filter(function(s) { return asking.indexOf(s) < 0 && wanted.indexOf(s) < 0 })
      if (more.length) root.wanted = wanted.concat(more)
      return
    }
    if (!symbols.length) return
    root.asking = symbols
    root.askedAt = at
    if (gate && gate.take(1) === 0) {
      heldTimer.restart()
      return
    }
    if (gate) root.ticket = gate.ticket
    fetchProc.command = Fetch.curlCommand([Overnight.overnightUrl(symbols)], Fetch.overnightCap(symbols.length))
    fetchProc.running = true
  }

  // An answer with nothing new for a symbol keeps the prints it had, so its
  // chart is not built again. Each symbol's entry says when it was asked
  // (`at`), so a symbol no longer asked for ages on its own.
  function receive(text) {
    var got = Fetch.answers(text)
    if (gate && got.length) gate.report(got.map(function(a) { return a.kind }), got[0].retryAfter, root.ticket)
    var parsed = null
    try { parsed = got.length && got[0].kind === "ok" ? Overnight.parseOvernight(JSON.parse(got[0].body), asking) : null } catch (e) { parsed = null }
    var next = Object.assign({}, entries)
    for (var i = 0; i < asking.length; i++) {
      var symbol = asking[i]
      var had = entries[symbol]
      if (!parsed) {
        next[symbol] = { status: "failed", bars: had ? had.bars : [], at: askedAt }
        continue
      }
      var bars = parsed[symbol]
      if (had && JSON.stringify(had.bars) === JSON.stringify(bars)) bars = had.bars
      next[symbol] = { status: "ok", bars: bars, at: askedAt }
    }
    root.entries = next
    var again = wanted
    root.wanted = []
    fetch(again, now)
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
