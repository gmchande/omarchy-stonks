import QtQuick
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Robinhood's trades for every listing asked, in one run of requests. A
// fetch while a run is out is dropped: the service asks again for what it
// still wants once that run lands.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // Kept in each entry as `at`; a user's refresh waits 10 s by it.
  property int askedAt: 0
  property var batches: []
  property int retryAfter: 2500
  property var retrying: []
  property bool retried: false
  readonly property bool busy: batches.length > 0 || retrying.length > 0
  // While a chart draws itself in, large answers wait: a 25-listing day's
  // JSON.parse can take 17 to 24 ms. Small visible-row batches parse in a few
  // milliseconds, so they land at once instead of holding row sparklines blank.
  property bool holding: false
  onHoldingChanged: if (!holding && landing) landTimer.start()
  function batchHeld(batch, answer) {
    if (!holding) return false
    if (batch.symbols.length > 10) return true
    return !!answer && !!answer.body && answer.body.length > 750000
  }

  // `at`: the clock's own handlers may run before this binding to it has
  // caught up. While the host is paused past its first blip, a run fails a
  // turn later, out of the change that asked for it; on a single timeout
  // blip or local budget pacing, it waits for the probe or refill.
  function fetch(symbols, at) {
    if (busy || !symbols.length) return
    sendBatches(symbols, at, false)
  }

  function sendBatches(symbols, at, isRetry) {
    if (!symbols.length) return
    var batches = Overnight.overnightBatches(symbols, entries, at)
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
    var cap = Math.max.apply(null, root.batches.map(function(b) { return Fetch.overnightCap(b.symbols.length, b.span) }))
    fetchRun.send(root.batches.map(function(b) { return Overnight.overnightUrl(b.symbols, b.span) }), cap)
  }

  // Marks failed entries so `askOvernight` retries them right away once
  // Robinhood reopens instead of waiting out the five-minute interval.
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

  // Answers are read about 8 ms a turn, an answer's text or one listing at
  // a time, so a long list never holds the shell's thread for long. Trades
  // that didn't change keep their array, so the chart isn't built again.
  property var landing: null
  function receive(got) {
    root.landing = {
      answers: batches.map(function(batch, b) { return got.filter(function(a) { return a.index === b })[0] || null }),
      batch: 0, results: null, read: 0, listings: {}
    }
    landTimer.start()
  }

  function landStep() {
    var job = landing
    var until = Date.now() + 8
    while (job.batch < batches.length && Date.now() < until) {
      var batch = batches[job.batch].symbols
      if (!job.results) {
        var answer = job.answers[job.batch]
        if (batchHeld(batches[job.batch], answer)) return
        try { job.results = answer && answer.kind === "ok" ? Overnight.overnightResults(JSON.parse(answer.body)) : null } catch (e) { job.results = null }
        job.answers[job.batch] = null
        job.read = 0
        if (!job.results) job.batch++
      } else {
        var symbol = batch[job.read]
        var answer = null
        var unreadable = false
        try { answer = Overnight.overnightAnswer(job.results, batch, job.read) } catch (e) { unreadable = true }
        var had = entries[symbol]
        var kept = Overnight.keptTrades(had, answer, batches[job.batch].span)
        if (kept) job.listings[symbol] = { bars: had && Overnight.sameBars(had.bars, kept.bars) ? had.bars : kept.bars, through: kept.through }
        // One listing that can't be read makes the whole answer bad. One
        // the answer left out fails alone (`land`).
        else if (unreadable) batch.forEach(function(s) { delete job.listings[s] })
        if (unreadable || ++job.read >= batch.length) {
          job.results = null
          job.batch++
        }
      }
    }
    if (job.batch < batches.length) landTimer.start()
    else land(job)
  }

  // A listing asked for an hour with no trades left gets no entry, so its day
  // is asked at once. Stamped failed, a preview left and come back to would
  // show no overnight price for five minutes.
  function land(job) {
    var next = Object.assign({}, entries)
    var blip = !!gate && gate.paused && gate.pause === "none" && gate.silences < 2
    var retrySymbols = []
    var changed = false
    batches.forEach(function(batch) {
      batch.symbols.forEach(function(symbol) {
        var had = entries[symbol]
        var got = job.listings[symbol]
        if (!got && !had && batch.span === "hour") return
        if (got) {
          next[symbol] = { status: "ok", bars: got.bars, through: got.through, at: askedAt }
          changed = true
        } else if (blip) {
          return
        } else if (!root.retried && (!gate || !gate.paused)) {
          retrySymbols.push(symbol)
        } else {
          next[symbol] = { status: "failed", bars: had ? had.bars : [], through: had ? had.through : null, at: askedAt }
          changed = true
        }
      })
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
    id: landTimer
    interval: 0
    onTriggered: root.landStep()
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
