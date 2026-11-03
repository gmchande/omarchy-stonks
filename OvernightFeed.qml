import QtQuick
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Robinhood's prints for every listing asked, in one run of requests. A
// fetch while a run is out is dropped: the service asks again for what it
// still wants once that run lands.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // Kept in each entry as `at`; a user's refresh waits 10 s by it.
  property int askedAt: 0
  property var batches: []
  readonly property bool busy: batches.length > 0
  // While a chart draws itself in, answers wait: a day's answer is one
  // JSON.parse that can't be sliced, 17 to 24 ms for 25 listings.
  property bool holding: false
  onHoldingChanged: if (!holding && landing) landTimer.start()

  // `at`: the clock's own handlers may run before this binding to it has
  // caught up. A run the gate holds back fails a turn later, out of the
  // change that asked for it.
  function fetch(symbols, at) {
    if (busy || !symbols.length) return
    var batches = Overnight.overnightBatches(symbols, entries, at)
    var granted = gate ? gate.take(batches.length) : batches.length
    root.batches = granted > 0 ? batches.slice(0, granted) : batches
    root.askedAt = at
    if (granted === 0) {
      heldTimer.restart()
      return
    }
    var cap = Math.max.apply(null, root.batches.map(function(b) { return Fetch.overnightCap(b.symbols.length, b.span) }))
    fetchRun.send(root.batches.map(function(b) { return Overnight.overnightUrl(b.symbols, b.span) }), cap)
  }

  // Answers are read about 8 ms a turn, an answer's text or one listing at
  // a time, so a long list never holds the shell's thread for long. Prints
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
    if (holding) return
    var until = Date.now() + 8
    while (job.batch < batches.length && Date.now() < until) {
      var batch = batches[job.batch].symbols
      if (!job.results) {
        var answer = job.answers[job.batch]
        try { job.results = answer && answer.kind === "ok" ? Overnight.overnightResults(JSON.parse(answer.body)) : null } catch (e) { job.results = null }
        job.answers[job.batch] = null
        job.read = 0
        if (!job.results) job.batch++
      } else {
        var symbol = batch[job.read]
        var answer = null
        try { answer = Overnight.overnightAnswer(job.results[job.read], symbol) } catch (e) { answer = null }
        var had = entries[symbol]
        // An hour can't stand for a day: a listing whose prints went
        // meanwhile (`Service.forgetLeft`) is left unanswered.
        var hour = batches[job.batch].span === "hour"
        var kept = !answer ? null : !hour ? answer : had ? Overnight.joinHour(had, answer) : null
        if (kept) job.listings[symbol] = { bars: had && Overnight.sameBars(had.bars, kept.bars) ? had.bars : kept.bars, through: kept.through }
        // One listing that can't be read makes the whole answer bad.
        else if (!answer) batch.forEach(function(s) { delete job.listings[s] })
        if (!answer || ++job.read >= batch.length) {
          job.results = null
          job.batch++
        }
      }
    }
    if (job.batch < batches.length) landTimer.start()
    else land(job)
  }

  // A listing asked for an hour with no prints left gets no entry, so its day
  // is asked at once. Stamped failed, a preview left and come back to would
  // show no overnight price for five minutes.
  function land(job) {
    var next = Object.assign({}, entries)
    batches.forEach(function(batch) {
      batch.symbols.forEach(function(symbol) {
        var had = entries[symbol]
        var got = job.listings[symbol]
        if (!got && !had && batch.span === "hour") return
        next[symbol] = got ? { status: "ok", bars: got.bars, through: got.through, at: askedAt }
          : { status: "failed", bars: had ? had.bars : [], through: had ? had.through : null, at: askedAt }
      })
    })
    root.landing = null
    root.batches = []
    root.entries = next
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
