import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Robinhood's prints for every listing asked, in one run of requests: a day
// for a listing with no prints in hand, or whose newest is over half an hour
// old, at most 25 listings to a request (`Overnight.OVERNIGHT_BATCH`), a
// third of its limit; and the last hour for the rest, at most 75 to a
// request (`Overnight.HOUR_BATCH`), joined on to the prints in hand
// (`Overnight.overnightSpan`, `Overnight.joinHour`). A day is the last 288
// slots the 24/5 market traded, which reaches every hour a chart can draw
// (`Overnight.dayChart`), so it replaces the prints kept. An entry is
// { status, bars, through }: "ok" with the prints Robinhood has, none for a
// listing it does not trade, and how far its answers reached
// (`Overnight.overnightAnswer`); or "failed", keeping the last good ones.
// `entries` holds answers only. One run at a time: a request asked for
// while one is out is not sent, and the service asks again for what it
// still wants once that is answered, so nothing goes once nothing wants it.
// While Robinhood's gate pauses the host, a request fails at once, keeping
// the last good prints; the gate's budget may let only some of a run's
// requests go.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // When the last request went out, answered or not, which each of its
  // listings' entries keeps (`at`): the service asks again by those
  // (`Overnight.overnightDue`), and a user's refresh waits 10 s by this.
  property int askedAt: 0
  // The run out, as its requests, { span, symbols }, in the order of their
  // URLs, until it is answered.
  property var batches: []
  readonly property bool busy: batches.length > 0
  // While the service holds answers, as a chart draws itself in, a run is
  // read only if it carries the chart waited on (`waited`); the rest wait
  // for the motion to end, since a day's answer is read in one piece that
  // can't be sliced: 17 to 24 ms for 25 listings.
  property bool holding: false
  property string waited: ""
  onHoldingChanged: if (!holding && landing) landTimer.start()

  // `at` is the service's clock as it asks: the clock's own handlers may run
  // before this binding to it has caught up. While the gate holds the host,
  // the request fails a turn later, out of the change that asked for it.
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
    if (gate) root.ticket = gate.ticket
    var cap = Math.max.apply(null, root.batches.map(function(b) { return Fetch.overnightCap(b.symbols.length, b.span) }))
    fetchProc.command = Fetch.curlCommand(root.batches.map(function(b) { return Overnight.overnightUrl(b.symbols, b.span) }), cap)
    fetchProc.running = true
  }

  // Each request's answer is read with its own symbols, a little at a time,
  // about 8 ms a turn (`landStep`), as the quote feed reads its runs: an
  // answer's text, or one listing of it, so a long list's prints never hold
  // the shell's thread for long. The run lands whole once its last listing
  // is read (`land`), and is out (`busy`) until then. An answer with
  // nothing new for a symbol keeps the prints it had, so its chart is not
  // built again. Each symbol's entry says when it was asked (`at`), so a
  // symbol no longer asked for ages on its own.
  property var landing: null
  function receive(text) {
    var got = Fetch.answers(text)
    if (gate && got.length) {
      gate.report(got.map(function(a) { return a.kind }),
        Math.max.apply(null, got.map(function(a) { return a.retryAfter })), root.ticket)
    }
    // `results` is the batch's answer once read, null before and for a bad
    // one; `listings` holds each symbol's answer read, by symbol.
    root.landing = {
      answers: batches.map(function(batch, b) { return got.filter(function(a) { return a.index === b })[0] || null }),
      batch: 0, results: null, read: 0, listings: {}
    }
    landTimer.start()
  }

  function landStep() {
    var job = landing
    if (holding && !batches.some(function(b) { return b.symbols.indexOf(waited) >= 0 })) return
    var until = Date.now() + 8
    while (job.batch < batches.length && Date.now() < until) {
      var batch = batches[job.batch].symbols
      if (!job.results) {
        var answer = job.answers[job.batch]
        try { job.results = answer && answer.kind === "ok" ? Overnight.overnightResults(JSON.parse(answer.body)) : null } catch (e) { job.results = null }
        job.answers[job.batch] = null
        job.read = 0
        // A bad answer reads nothing: its symbols fail.
        if (!job.results) job.batch++
      } else {
        var symbol = batch[job.read]
        var answer = null
        try { answer = Overnight.overnightAnswer(job.results[job.read], symbol) } catch (e) { answer = null }
        var had = entries[symbol]
        // An hour's answer joins on to the prints in hand; for a listing
        // whose entry went meanwhile (`Service.forgetLeft`) it is no day,
        // and the listing is left unanswered.
        var hour = batches[job.batch].span === "hour"
        var kept = !answer ? null : !hour ? answer : had ? Overnight.joinHour(had, answer) : null
        if (kept) job.listings[symbol] = { bars: had && Overnight.sameBars(had.bars, kept.bars) ? had.bars : kept.bars, through: kept.through }
        // An answer with a listing that can't be read is a bad answer too:
        // none of its symbols is read.
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

  // A listing asked for an hour whose prints in hand went meanwhile
  // (`Service.forgetLeft`) is left with no entry, answered or not, so the
  // next ask is for its day, at once. Stamped as failed with nothing in it
  // instead, a preview left and come back to would show no overnight price
  // for five minutes.
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
