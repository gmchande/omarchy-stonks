import QtQuick
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// The day Robinhood says each US stock or ETF listed, in one run of
// requests. A fetch while a run is out is dropped: the
// service asks again for what it still wants once that run lands.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  property int askedAt: 0
  property var batches: []
  readonly property bool busy: batches.length > 0

  // While the host is paused, a run fails a turn later, out of the change
  // that asked for it; when the budget merely paces it, it waits for the
  // refill.
  function fetch(symbols, at) {
    if (busy || !symbols.length) return
    var batches = []
    for (var i = 0; i < symbols.length; i += Overnight.LIST_DATE_BATCH) batches.push(symbols.slice(i, i + Overnight.LIST_DATE_BATCH))
    var granted = gate ? gate.take(batches.length) : batches.length
    if (granted === 0) {
      if (gate && gate.paused) {
        root.batches = batches
        root.askedAt = at
        heldTimer.restart()
      }
      return
    }
    root.batches = batches.slice(0, granted)
    root.askedAt = at
    fetchRun.send(root.batches.map(Overnight.listDateUrl), Fetch.instrumentsCap(root.batches[0].length))
  }

  function receive(got) {
    var next = Object.assign({}, entries)
    batches.forEach(function(batch, b) {
      var answer = got.filter(function(a) { return a.index === b })[0]
      var dates = null
      try {
        var json = answer && answer.kind === "ok" ? JSON.parse(answer.body) : null
        dates = json ? Overnight.listDates(json, batch) : null
      } catch (e) { dates = null }
      batch.forEach(function(symbol) { next[symbol] = Overnight.listDateEntry(dates, symbol, entries[symbol], askedAt) })
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
