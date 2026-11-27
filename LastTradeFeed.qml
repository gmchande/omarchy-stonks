import QtQuick
import "Overnight.js" as Overnight
// Robinhood's quote for every listing asked, its last trade outside the
// regular session (`Overnight.lastTrades`), in one run of requests. A fetch
// while a run is out is dropped: the service asks again for what it still
// wants once that run lands. A failed answer keeps the trade it had.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  property var batches: []
  property int askedAt: 0
  readonly property bool busy: batches.length > 0
  // While a chart draws itself in, answers wait: one changes the chart.
  property bool holding: false
  property var landing: null
  onHoldingChanged: if (!holding && landing) land(landing)

  function fetch(symbols, at) {
    if (busy || !symbols.length) return
    var batches = []
    for (var i = 0; i < symbols.length; i += Overnight.LAST_TRADE_BATCH) batches.push(symbols.slice(i, i + Overnight.LAST_TRADE_BATCH))
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
    fetchRun.send(root.batches.map(Overnight.lastTradeUrl), Overnight.lastTradeCap(Math.max.apply(null, root.batches.map(function(b) { return b.length }))))
  }

  function receive(got) {
    root.landing = got
    if (!holding) land(got)
  }

  // A trade that didn't change keeps its object, so nothing is built again.
  function land(got) {
    var next = Object.assign({}, entries)
    batches.forEach(function(symbols, b) {
      var answer = got.filter(function(a) { return a.index === b })[0]
      var trades = null
      try { trades = answer && answer.kind === "ok" ? Overnight.lastTrades(JSON.parse(answer.body), symbols) : null } catch (e) { trades = null }
      symbols.forEach(function(symbol) {
        var had = entries[symbol]
        var trade = trades ? trades[symbol] : had ? had.trade : null
        if (had && had.trade && trade && had.trade.t === trade.t && had.trade.p === trade.p) trade = had.trade
        next[symbol] = { status: trades ? "ok" : "failed", trade: trade, at: askedAt }
      })
    })
    root.landing = null
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
