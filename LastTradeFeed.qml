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
  property int retryAfter: 2500
  property var retrying: []
  property bool retried: false
  readonly property bool busy: batches.length > 0 || retrying.length > 0
  // While a chart draws itself in, answers wait: one changes the chart.
  property bool holding: false
  property var landing: null
  onHoldingChanged: if (!holding && landing) land(landing)

  function fetch(symbols, at) {
    if (busy || !symbols.length) return
    sendBatches(symbols, at, false)
  }

  function sendBatches(symbols, at, isRetry) {
    if (!symbols.length) return
    var batches = []
    for (var i = 0; i < symbols.length; i += Overnight.LAST_TRADE_BATCH) batches.push(symbols.slice(i, i + Overnight.LAST_TRADE_BATCH))
    var granted = gate ? gate.take(batches.length) : batches.length
    if (granted === 0) {
      if (gate && gate.paused && (gate.pause === "refused" || gate.silences >= 2)) {
        root.batches = batches
        root.askedAt = at
        root.retried = true
        heldTimer.restart()
      }
      return
    }
    root.batches = batches.slice(0, granted)
    root.askedAt = at
    root.retried = isRetry
    fetchRun.send(root.batches.map(Overnight.lastTradeUrl), Overnight.lastTradeCap(Math.max.apply(null, root.batches.map(function(b) { return b.length }))))
  }

  function retryFailed() {
    var next = null
    for (var symbol in entries) {
      if (entries[symbol].status === "failed" && !entries[symbol].retry) {
        if (!next) next = Object.assign({}, entries)
        next[symbol] = Object.assign({}, entries[symbol], { retry: true })
      }
    }
    if (next) root.entries = next
  }

  function receive(got) {
    root.landing = got
    if (!holding) land(got)
  }

  // A trade that didn't change keeps its object, so nothing is built again.
  function land(got) {
    var next = Object.assign({}, entries)
    var blip = !!gate && gate.paused && gate.pause === "none" && gate.silences < 2
    var retrySymbols = []
    var changed = false
    batches.forEach(function(symbols, b) {
      var answer = got.filter(function(a) { return a.index === b })[0]
      var trades = null
      try { trades = answer && answer.kind === "ok" ? Overnight.lastTrades(JSON.parse(answer.body), symbols) : null } catch (e) { trades = null }
      if (trades) {
        symbols.forEach(function(symbol) {
          var had = entries[symbol]
          var trade = trades[symbol]
          if (had && had.trade && trade && had.trade.t === trade.t && had.trade.p === trade.p) trade = had.trade
          next[symbol] = { status: "ok", trade: trade, at: askedAt }
          changed = true
        })
      } else if (blip) {
        return
      } else if (!root.retried && (!gate || !gate.paused)) {
        retrySymbols = retrySymbols.concat(symbols)
      } else {
        symbols.forEach(function(symbol) {
          var had = entries[symbol]
          next[symbol] = { status: "failed", trade: had ? had.trade : null, at: askedAt }
          changed = true
        })
      }
    })
    root.landing = null
    root.batches = []
    if (retrySymbols.length > 0) {
      root.retrying = retrySymbols
      retryTimer.restart()
    }
    if (changed) root.entries = next
  }

  Timer {
    id: retryTimer
    interval: root.retryAfter
    onTriggered: {
      var symbols = root.retrying
      root.retrying = []
      root.sendBatches(symbols, root.askedAt, true)
    }
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
