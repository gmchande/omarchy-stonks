import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Fundamentals.js" as Fundamentals
// Yahoo's dated cap and trailing EPS, one symbol at a time, kept for the
// day. Curls in turn: the series, then the close on the cap's date, which
// moves it with the price (`Fundamentals.yearLine`), then, when the EPS is
// in another currency than the price, the rate between the two, kept for
// the day by pair, so listings that share a pair ask it once. An entry is
// "ok" with its figures, either of which may be null when Yahoo has none,
// or "failed", keeping the last good figures; one whose rate failed keeps
// its new cap, with no P/E. A failed one is asked again the next time it is
// wanted. While Yahoo's gate pauses the host, a fetch fails at once.
Item {
  id: root

  property var entries: ({})
  // Rates by pair ("USDCAD"): { value, checkedAt }.
  property var rates: ({})
  property var gate: null
  property var clearance: null
  property string pendingUrl: ""
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // The symbol, and its price's currency, to fetch once the one under way is
  // done.
  property string wanted: ""
  property string wantedCurrency: ""
  // The fetch under way: { symbol, currency, step, figures }, step "series",
  // "close", or "rate", figures null until the series are in.
  property var job: null

  readonly property bool busy: job !== null || wanted !== ""

  function fetch(symbol, currency) {
    var normalized = String(symbol || "").toUpperCase()
    if (!normalized || (job && job.symbol === normalized)) return
    var current = entries[normalized]
    if (current && current.status === "ok" && root.nowSecond() - current.checkedAt < 24 * 60 * 60) return
    root.wanted = normalized
    root.wantedCurrency = String(currency || "")
    root.launch()
  }

  function nowSecond() {
    return Math.floor(Date.now() / 1000)
  }

  function launch() {
    if (job || !wanted) return
    root.job = { symbol: wanted, currency: wantedCurrency, step: "series", figures: null }
    root.wanted = ""
    root.run(Fundamentals.fundamentalsUrl(job.symbol, root.nowSecond()))
  }

  function run(url) {
    root.pendingUrl = url
    root.pump()
  }

  function pump() {
    if (!pendingUrl || (clearance && !clearance())) return
    if (gate && gate.take(1) === 0) {
      root.fail(job.symbol, null)
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

  // An answer whose reading throws is a failed one. Found in the check of
  // the 1.0.4 security review: closes whose offset was {"toString": null}
  // threw out of here with the fetch still under way, so no symbol's cap
  // and P/E would be asked for again until Stonks restarted.
  function receive(text) {
    var got = Fetch.answers(text)
    if (gate) gate.report(got.map(function(a) { return a.kind }), got.length ? got[0].retryAfter : 0, root.ticket)
    var symbol = job.symbol
    var step = job.step
    var json = null
    try {
      json = got.length && got[0].kind === "ok" ? JSON.parse(got[0].body) : null
    } catch (e) {
      json = null
    }
    if (step === "rate") {
      var pair = Fundamentals.ratePair(job.figures, job.currency)
      var rate = null
      try {
        rate = Fundamentals.parseRate(json, pair)
      } catch (e) {
        rate = null
      }
      if (rate === null) {
        root.fail(symbol, job.figures)
        return
      }
      var held = Object.assign({}, rates)
      held[pair] = { value: rate, checkedAt: root.nowSecond() }
      root.rates = held
      root.settle(symbol, Fundamentals.withRate(job.figures, rate))
      return
    }
    var figures = null
    try {
      figures = step === "series" ? Fundamentals.parseFundamentals(json) : Fundamentals.withCapClose(job.figures, json)
    } catch (e) {
      figures = null
    }
    if (!figures) {
      root.fail(symbol, null)
      return
    }
    root.advance(step === "series" && figures.cap ? "close" : "rate", figures)
  }

  // The figures in hand, and the step they need next: the cap's close, or
  // the EPS's rate, unless it needs none or a rate held from today serves.
  function advance(step, figures) {
    var pair = Fundamentals.ratePair(figures, job.currency)
    var held = rates[pair]
    if (step === "rate" && !pair) {
      root.settle(job.symbol, figures)
    } else if (step === "rate" && held && root.nowSecond() - held.checkedAt < 24 * 60 * 60) {
      root.settle(job.symbol, Fundamentals.withRate(figures, held.value))
    } else {
      root.job = Object.assign({}, job, { step: step, figures: figures })
      root.run(step === "close" ? Fundamentals.capCloseUrl(job.symbol, figures) : Fundamentals.rateUrl(pair))
    }
  }

  function settle(symbol, figures) {
    root.finish(symbol, { status: "ok", figures: figures, checkedAt: root.nowSecond() })
  }

  // A failed fetch keeps the last good figures, unless it brings newer ones.
  function fail(symbol, figures) {
    root.finish(symbol, Object.assign({ figures: null, checkedAt: 0 }, entries[symbol], { status: "failed" },
      figures ? { figures: figures } : {}))
  }

  function finish(symbol, entry) {
    root.pendingUrl = ""
    var next = Object.assign({}, entries)
    next[symbol] = entry
    root.entries = next
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
