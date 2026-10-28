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
// EPS and no cap; a failed one is asked again the next time it is
// wanted. Then, when the EPS is in another currency than the price and its
// pair's rate is a day old or none was asked, the rate, once whichever
// listing wants it first: a failed one is kept as no rate, so the pair has
// no P/E until it is asked again a day later. While Yahoo's gate pauses the
// host, a fetch fails at once, and a rate is left unasked.
Item {
  id: root

  property var entries: ({})
  // By pair ("USDCAD"): { value, checkedAt }, value null after a failure.
  property var rates: ({})
  property var gate: null
  property var clearance: null
  property string pendingUrl: ""
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // What waits for the fetch under way, in the order asked: one ask for
  // each asker (`Service.fetchFundamentals`), { asker, symbol, currency }.
  // An asker's new ask replaces its last, whose symbol it no longer shows,
  // and never another's: the stock on show waits behind search's preview.
  // Two askers may wait for one symbol, which one fetch answers.
  property var waiting: []
  // The fetch under way: { symbol, currency, step, figures, pair }, step
  // "series", "close", or "rate", figures null until the series are in.
  property var job: null

  readonly property bool busy: job !== null || waiting.length > 0
  readonly property int day: 24 * 60 * 60

  function fetch(symbol, currency, asker) {
    var normalized = String(symbol || "").toUpperCase()
    if (!normalized) return
    var others = waiting.filter(function(w) { return w.asker !== asker })
    var current = root.fresh(normalized)
    var needless = (job && job.symbol === normalized)
      || (current && root.rateHeld(Fundamentals.ratePair(current.figures, currency)))
    root.waiting = needless ? others
      : others.concat([{ asker: asker, symbol: normalized, currency: String(currency || "") }])
    root.launch()
  }

  // An asker no screen shows any more takes back what it waits for; a
  // fetch under way still lands.
  function withdraw(asker) {
    var left = waiting.filter(function(w) { return w.asker !== asker })
    if (left.length !== waiting.length) root.waiting = left
  }

  function nowSecond() {
    return Math.floor(Date.now() / 1000)
  }

  // A symbol's entry while it is good for the day, else null.
  function fresh(symbol) {
    var current = entries[symbol]
    return current && current.status === "ok" && root.nowSecond() - current.checkedAt < day ? current : null
  }

  // Whether a pair needs no asking today: no pair, or one asked within a day.
  function rateHeld(pair) {
    return !pair || (!!rates[pair] && root.nowSecond() - rates[pair].checkedAt < day)
  }

  function launch() {
    if (job || !waiting.length) return
    var next = waiting[0]
    root.waiting = waiting.filter(function(w) { return w.symbol !== next.symbol })
    var current = root.fresh(next.symbol)
    root.job = { symbol: next.symbol, currency: next.currency, step: "series", figures: null, pair: "" }
    if (current) root.askRate(current.figures)
    else root.run(Fundamentals.fundamentalsUrl(job.symbol, root.nowSecond()))
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
    var url = job.step === "series" ? Fundamentals.fundamentalsUrl(job.symbol, root.nowSecond()) : pendingUrl
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
      held[job.pair] = { value: read, checkedAt: root.nowSecond() }
      root.rates = held
      root.done()
    } else if (!read) {
      root.fail(job.symbol)
    } else if (step === "series" && read.cap) {
      root.job = Object.assign({}, job, { step: "close", figures: read })
      root.run(Fundamentals.capCloseUrl(job.symbol, read))
    } else {
      root.keep(job.symbol, { status: "ok", figures: read, checkedAt: root.nowSecond() })
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
    root.launch()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(String(text || ""))
    }
  }
}
