import QtQuick
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Whether Robinhood trades each US stock or ETF all day, in one run of
// requests. A fetch while a run is out is dropped: the service asks again
// for what it still wants once that run lands.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  property int askedAt: 0
  property var batches: []
  readonly property bool busy: batches.length > 0

  // A run the gate holds back fails a turn later, out of the change that
  // asked for it.
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
    fetchRun.send(root.batches.map(Overnight.allDayUrl), Fetch.instrumentsCap(root.batches[0].length))
  }

  function receive(got) {
    var next = Object.assign({}, entries)
    batches.forEach(function(batch, b) {
      var answer = got.filter(function(a) { return a.index === b })[0]
      var parsed = null
      try { parsed = answer && answer.kind === "ok" ? Overnight.parseAllDay(JSON.parse(answer.body), batch) : null } catch (e) { parsed = null }
      batch.forEach(function(symbol) { next[symbol] = Overnight.allDayEntry(parsed, symbol, entries[symbol], askedAt) })
    })
    root.batches = []
    root.entries = next
  }

  Timer {
    id: heldTimer
    interval: 0
    onTriggered: root.receive([])
  }

  FetchRun {
    id: fetchRun
    gate: root.gate
    onEnded: function(got) { root.receive(got) }
  }
}
