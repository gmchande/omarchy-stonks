import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Whether Robinhood trades each US stock or ETF all day, its 24 Hour Market
// (`all_day_tradability`), from its keyless instruments, one request for
// every listing asked: only a listing it does draws its overnight prints
// and a calendar day (`Chart.viewChart`). An entry is
// { status, allDay, at }, `at` the service's clock as it asked: "ok" with
// Robinhood's answer, kept a day (`Overnight.allDayDue`); or "failed",
// keeping the last good answer, and not all-day without one. `entries`
// holds answers only. One curl at a time: a request asked for while one is
// out is not sent, and the service asks again for what it still wants once
// that is answered. While Robinhood's gate pauses the host, a request fails
// at once.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  property int askedAt: 0
  // The listings asked for, until they are answered.
  property var asking: []
  readonly property bool busy: asking.length > 0

  // While the gate holds the host, the request fails a turn later, out of
  // the change that asked for it.
  function fetch(symbols, at) {
    if (busy || !symbols.length) return
    root.asking = symbols
    root.askedAt = at
    if (gate && gate.take(1) === 0) {
      heldTimer.restart()
      return
    }
    if (gate) root.ticket = gate.ticket
    fetchProc.command = Fetch.curlCommand([Overnight.allDayUrl(symbols)], Fetch.instrumentsCap(symbols.length))
    fetchProc.running = true
  }

  function receive(text) {
    var got = Fetch.answers(text)
    if (gate && got.length) gate.report(got.map(function(a) { return a.kind }), got[0].retryAfter, root.ticket)
    var parsed = null
    try { parsed = got.length && got[0].kind === "ok" ? Overnight.parseAllDay(JSON.parse(got[0].body), asking) : null } catch (e) { parsed = null }
    var next = Object.assign({}, entries)
    for (var i = 0; i < asking.length; i++) {
      var symbol = asking[i]
      var had = entries[symbol]
      next[symbol] = parsed
        ? { status: "ok", allDay: parsed[symbol], at: askedAt }
        : { status: "failed", allDay: had ? had.allDay : false, at: askedAt }
    }
    root.asking = []
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
