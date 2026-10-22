import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Overnight.js" as Overnight
// Robinhood's prints for every listing asked, in one run of requests of at
// most 25 listings each (`Overnight.OVERNIGHT_BATCH`), a third of its limit:
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
  // When the last request went out, answered or not, which each of its
  // listings' entries keeps (`at`): the service asks again by those
  // (`Overnight.overnightDue`), and a user's refresh waits 10 s by this.
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

  // Each request's answer is read with its own symbols, a little at a time,
  // about 8 ms a turn (`landStep`), as the quote feed reads its runs: an
  // answer's text, or one listing of it, so a long list's prints never hold
  // the shell's thread for long. The run lands whole once its last listing
  // is read (`land`), and is out (`busy`) until then. An answer with nothing
  // new for a symbol keeps the prints it had, so its chart is not built
  // again. Each symbol's entry says when it was asked (`at`), so a symbol no
  // longer asked for ages on its own.
  property var landing: null
  function receive(text) {
    var got = Fetch.answers(text)
    if (gate && got.length) {
      gate.report(got.map(function(a) { return a.kind }),
        Math.max.apply(null, got.map(function(a) { return a.retryAfter })), root.ticket)
    }
    // `results` is the batch's answer once read, null before and for a bad
    // one; `bars` holds each symbol read, by symbol.
    root.landing = {
      answers: batches.map(function(batch, b) { return got.filter(function(a) { return a.index === b })[0] || null }),
      batch: 0, results: null, read: 0, bars: {}
    }
    landTimer.start()
  }

  function landStep() {
    var job = landing
    var until = Date.now() + 8
    while (job.batch < batches.length && Date.now() < until) {
      var batch = batches[job.batch]
      if (!job.results) {
        var answer = job.answers[job.batch]
        try { job.results = answer && answer.kind === "ok" ? Overnight.overnightResults(JSON.parse(answer.body)) : null } catch (e) { job.results = null }
        job.answers[job.batch] = null
        job.read = 0
        // A bad answer reads nothing: its symbols fail.
        if (!job.results) job.batch++
      } else {
        var symbol = batch[job.read]
        var bars = null
        try { bars = Overnight.overnightBars(job.results[job.read], symbol) } catch (e) { bars = null }
        var had = entries[symbol]
        if (bars) job.bars[symbol] = had && Overnight.sameBars(had.bars, bars) ? had.bars : bars
        // An answer with a listing that can't be read is a bad answer too:
        // none of its symbols is read.
        else batch.forEach(function(s) { delete job.bars[s] })
        if (!bars || ++job.read >= batch.length) {
          job.results = null
          job.batch++
        }
      }
    }
    if (job.batch < batches.length) landTimer.start()
    else land(job)
  }

  function land(job) {
    var next = Object.assign({}, entries)
    batches.forEach(function(batch) {
      batch.forEach(function(symbol) {
        var had = entries[symbol]
        next[symbol] = symbol in job.bars ? { status: "ok", bars: job.bars[symbol], at: askedAt }
          : { status: "failed", bars: had ? had.bars : [], at: askedAt }
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
