import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Fundamentals.js" as Fundamentals
// Yahoo's dated cap and trailing EPS, one symbol at a time, kept for the
// day, and the rates their P/Es need, kept for the day by pair. Curls in
// turn: the series, then the close on the cap's date, which moves it with
// the price (`Fundamentals.yearLine`). An entry is "ok" with its figures,
// either of which may be null when Yahoo has none, or "failed", keeping the
// last good figures, or once the series came but not the cap's close, their
// EPS and no cap. Then, when the EPS is in another currency than the price
// and its pair's rate is a day old or none was asked, the rate, once
// whichever listing wants it first: a failed one is kept as no rate, so the
// pair has no P/E until it is asked again a day later. While Yahoo's gate
// pauses the host, a fetch fails at once, and a rate is left unasked.
// What it fetches is what the surfaces on screen show (`wanted`), worked out
// by the service: each one not good for the day, in order, one at a time,
// and again as the clock moves past its day. One that failed waits until it
// is wanted anew, or for a reader's refresh or Yahoo answering again after
// a pause (`retry`), so a failure isn't asked again every second.
Item {
  id: root

  property var entries: ({})
  // By pair ("USDCAD"): { value, checkedAt }, value null after a failure.
  property var rates: ({})
  property var gate: null
  property var clearance: null
  // The heroes on show's, each { symbol, currency }, in order
  // (`Service.figuresWanted`).
  property var wanted: []
  // The service's clock: `now` moves the feed to look, and the wall clock
  // (`wallSecond`) is what it reads.
  property int now: 0
  property var clock: null
  property string pendingUrl: ""
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // The fetch under way: { symbol, currency, step, figures, pair }, step
  // "series", "close", or "rate", figures null until the series are in.
  property var job: null
  // The wanted symbols whose fetch failed while they were wanted.
  property var failed: []

  readonly property bool busy: job !== null || wanted.some(root.due)
  readonly property int day: 24 * 60 * 60

  onWantedChanged: look()
  onNowChanged: look()

  function wants(symbol) {
    return wanted.some(function(w) { return w.symbol === symbol })
  }

  // Whether `w` needs fetching: never fetched, or it or its rate a day old;
  // one that failed only once it is wanted anew.
  function due(w) {
    var entry = entries[w.symbol]
    if (entry && entry.status === "failed") return failed.indexOf(w.symbol) < 0
    var current = root.fresh(w.symbol)
    return !current || !root.rateHeld(Fundamentals.ratePair(current.figures, w.currency))
  }

  // What failed is asked again now: a reader's refresh, or Yahoo answering
  // again after a pause.
  function retry() {
    if (failed.length) root.failed = []
    root.look()
  }

  // A symbol no longer wanted is wanted anew when it comes back, and a series
  // not yet sent for it goes; one sent still lands. With nothing under way,
  // the first wanted that is due goes.
  function look() {
    var still = failed.filter(root.wants)
    if (still.length !== failed.length) root.failed = still
    if (job) {
      if (pendingUrl && job.step === "series" && !root.wants(job.symbol)) root.done()
      return
    }
    var next = wanted.filter(root.due)[0]
    if (!next) return
    var current = root.fresh(next.symbol)
    root.job = { symbol: next.symbol, currency: next.currency, step: "series", figures: null, pair: "" }
    if (current) root.askRate(current.figures)
    else root.run(Fundamentals.fundamentalsUrl(next.symbol, clock.wallSecond()))
  }

  // A symbol's entry while it is good for the day, else null.
  function fresh(symbol) {
    var current = entries[symbol]
    return current && current.status === "ok" && clock.wallSecond() - current.checkedAt < day ? current : null
  }

  // Whether a pair needs no asking today: no pair, or one asked within a day.
  function rateHeld(pair) {
    return !pair || (!!rates[pair] && clock.wallSecond() - rates[pair].checkedAt < day)
  }

  function run(url) {
    root.pendingUrl = url
    root.pump()
  }

  function pump() {
    if (!pendingUrl || (clearance && !clearance())) return
    if (gate && gate.take(1) === 0) {
      if (job.step === "rate") root.done()
      else root.fail(job.symbol)
      return
    }
    if (gate) root.ticket = gate.ticket
    // A series held while the screens are off ends at wake, not at the
    // earlier ask. The close refers to a fixed date and keeps its URL.
    var url = job.step === "series" ? Fundamentals.fundamentalsUrl(job.symbol, clock.wallSecond()) : pendingUrl
    fetchProc.command = Fetch.curlCommand([url], Fetch.FUNDAMENTALS_CAP)
    root.pendingUrl = ""
    fetchProc.running = true
  }

  // An answer whose reading throws is a failed one: a throw escaping here
  // leaves the fetch under way, and no cap or P/E is asked for again until
  // Stonks restarts.
  function receive(text) {
    var got = Fetch.answers(text)
    if (gate) gate.report(got.map(function(a) { return a.kind }), got.length ? got[0].retryAfter : 0, root.ticket)
    var step = job.step
    var read = null
    try {
      var json = got.length && got[0].kind === "ok" ? JSON.parse(got[0].body) : null
      read = step === "series" ? Fundamentals.parseFundamentals(json)
        : step === "close" ? Fundamentals.withCapClose(job.figures, json)
        : Fundamentals.parseRate(json, job.pair)
    } catch (e) {
      read = null
    }
    if (step === "rate") {
      var held = Object.assign({}, rates)
      held[job.pair] = { value: read, checkedAt: clock.wallSecond() }
      root.rates = held
      root.done()
    } else if (!read) {
      root.fail(job.symbol)
    } else if (step === "series" && read.cap) {
      root.job = Object.assign({}, job, { step: "close", figures: read })
      root.run(Fundamentals.capCloseUrl(job.symbol, read))
    } else {
      root.keep(job.symbol, { status: "ok", figures: read, checkedAt: clock.wallSecond() })
      root.askRate(read)
    }
  }

  // The rate the figures' P/E needs, unless it needs none or it was asked
  // within a day.
  function askRate(figures) {
    var pair = Fundamentals.ratePair(figures, job.currency)
    if (root.rateHeld(pair)) {
      root.done()
      return
    }
    root.job = Object.assign({}, job, { step: "rate", pair: pair })
    root.run(Fundamentals.rateUrl(pair))
  }

  // A failed fetch keeps the last good figures, unless the series came:
  // they are the truth for the EPS, so it stands, with its rate asked, and
  // the cap stays unknown until its close is.
  function fail(symbol) {
    if (root.wants(symbol) && failed.indexOf(symbol) < 0) root.failed = failed.concat([symbol])
    var series = job.figures ? { figures: { cap: null, eps: job.figures.eps } } : {}
    root.keep(symbol, Object.assign({ figures: null, checkedAt: 0 }, entries[symbol], { status: "failed" }, series))
    if (job.figures) root.askRate(job.figures)
    else root.done()
  }

  function keep(symbol, entry) {
    var next = Object.assign({}, entries)
    next[symbol] = entry
    root.entries = next
  }

  function done() {
    root.pendingUrl = ""
    root.job = null
    root.look()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(String(text || ""))
    }
  }
}
