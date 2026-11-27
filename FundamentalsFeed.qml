import QtQuick
import "Fetch.js" as Fetch
import "Fundamentals.js" as Fundamentals
// Yahoo's cap and EPS for the symbols on screen, one at a time, and the
// rates their P/Es need, each kept for the day.
Item {
  id: root

  property var entries: ({})
  // By pair ("USDCAD").
  property var rates: ({})
  property var gate: null
  property var mayAsk: null
  // `Service.fundamentalsWanted`, in order.
  property var wanted: []
  // `now` wakes the feed; it reads `clock.wallSecond()`.
  property int now: 0
  property var clock: null
  property var pendingUrls: []
  // `fundamentals` is null until the series is in.
  property var job: null
  // These wait for `retry` or to be wanted anew, so they aren't asked again
  // every second.
  property var failed: []
  // A failed rate holds no rate, and every listing sharing its pair waits
  // with it.
  property var failedPairs: []

  readonly property bool busy: job !== null || wanted.some(root.due)

  onWantedChanged: look()
  onNowChanged: look()

  function wants(symbol) {
    return wanted.some(function(w) { return w.symbol === symbol })
  }

  function due(w) {
    return failed.indexOf(w.symbol) < 0 && Fundamentals.fundamentalsDue(entries[w.symbol], w.currency, rates, failedPairs, clock.wallSecond())
  }

  function miss(symbol) {
    if (root.wants(symbol) && failed.indexOf(symbol) < 0) root.failed = failed.concat([symbol])
  }

  // A reader's refresh, or Yahoo answering again after a pause.
  function retry() {
    if (failed.length) root.failed = []
    if (failedPairs.length) root.failedPairs = []
    root.look()
  }

  // A request not yet sent for a symbol no longer wanted goes, a cap's close
  // as `receive` drops it; one sent still lands.
  function look() {
    var still = failed.filter(root.wants)
    if (still.length !== failed.length) root.failed = still
    var needed = wanted.map(function(w) {
      var current = root.fresh(w.symbol)
      return current ? Fundamentals.ratePair(current.fundamentals, w.currency) : ""
    })
    var pairsStill = failedPairs.filter(function(pair) { return needed.indexOf(pair) >= 0 })
    if (pairsStill.length !== failedPairs.length) root.failedPairs = pairsStill
    if (job) {
      if (pendingUrls.length > 0 && !root.wants(job.symbol)) {
        if (job.step === "close" || job.step === "close+rate") root.fail(job.symbol)
        else root.done()
      }
      return
    }
    var next = wanted.filter(root.due)[0]
    if (!next) return
    var current = root.fresh(next.symbol)
    root.job = { symbol: next.symbol, currency: next.currency, step: "series", fundamentals: null, pair: "" }
    if (current) root.askRate(current.fundamentals)
    else root.run([Fundamentals.fundamentalsUrl(next.symbol, clock.wallSecond())])
  }

  function fresh(symbol) {
    return Fundamentals.freshFundamentals(entries[symbol], clock.wallSecond())
  }

  function run(urls) {
    root.pendingUrls = Array.isArray(urls) ? urls : [urls]
    root.sendWaiting()
  }

  function sendWaiting() {
    if (pendingUrls.length === 0 || (mayAsk && !mayAsk())) return
    // A series held while the screens are off ends at wake, not at the
    // earlier ask; the close's date is fixed.
    var urls = job.step === "series" ? [Fundamentals.fundamentalsUrl(job.symbol, clock.wallSecond())] : pendingUrls
    var granted = gate ? gate.take(urls.length) : urls.length
    if (granted === 0) {
      if (job.step !== "rate") {
        root.fail(job.symbol)
        return
      }
      root.miss(job.symbol)
      root.done()
      return
    }
    if (job.step === "close+rate" && granted < 2) {
      root.job = Object.assign({}, job, { step: "close", pair: "" })
      urls = [urls[0]]
    }
    root.pendingUrls = []
    fetchRun.send(urls, Fetch.FUNDAMENTALS_CAP)
  }

  function applyRate(read) {
    // A rate a day old is asked again before use: it goes as another comes.
    var now = clock.wallSecond()
    var held = {}
    for (var pair in rates) if (now - rates[pair].checkedAt < Fundamentals.FUNDAMENTALS_FRESH) held[pair] = rates[pair]
    if (read) held[job.pair] = { value: read, checkedAt: now }
    else {
      delete held[job.pair]
      if (failedPairs.indexOf(job.pair) < 0) root.failedPairs = failedPairs.concat([job.pair])
      root.miss(job.symbol)
    }
    root.rates = held
  }

  // A throw escaping here would leave the fetch under way, and no cap or P/E
  // would be asked for again until Stonks restarts.
  function receive(got) {
    var step = job.step
    if (step === "close+rate") {
      var closeGot = got.filter(function(a) { return a.index === 0 })[0]
      var rateGot = got.filter(function(a) { return a.index === 1 })[0]
      var closeRead = null
      var rateRead = null
      try {
        var cJson = closeGot && closeGot.kind === "ok" ? JSON.parse(closeGot.body) : null
        closeRead = Fundamentals.withCapClose(job.fundamentals, cJson)
      } catch (e) { closeRead = null }
      try {
        var rJson = rateGot && rateGot.kind === "ok" ? JSON.parse(rateGot.body) : null
        rateRead = Fundamentals.parseRate(rJson, job.pair)
      } catch (e) { rateRead = null }
      root.applyRate(rateRead)
      if (closeRead) {
        root.keep(job.symbol, { status: "ok", fundamentals: closeRead, checkedAt: clock.wallSecond() })
        root.done()
      } else {
        root.fail(job.symbol, true)
      }
      return
    }
    var read = null
    try {
      var json = got.length && got[0].kind === "ok" ? JSON.parse(got[0].body) : null
      read = step === "series" ? Fundamentals.parseFundamentals(json)
        : step === "close" ? Fundamentals.withCapClose(job.fundamentals, json)
        : Fundamentals.parseRate(json, job.pair)
    } catch (e) {
      read = null
    }
    if (step === "rate") {
      root.applyRate(read)
      root.done()
    } else if (!read) {
      root.fail(job.symbol)
    } else if (step === "series" && read.cap) {
      var pair = Fundamentals.ratePair(read, job.currency)
      var needRate = !Fundamentals.rateHeld(pair, rates, failedPairs, clock.wallSecond())
      root.job = Object.assign({}, job, { step: needRate ? "close+rate" : "close", fundamentals: read, pair: needRate ? pair : "" })
      // Off screen by now: the EPS stands, and the cap waits for the next
      // ask.
      if (root.wants(job.symbol)) {
        var closeUrl = Fundamentals.capCloseUrl(job.symbol, read)
        root.run(needRate ? [closeUrl, Fundamentals.rateUrl(pair)] : [closeUrl])
      } else {
        root.fail(job.symbol)
      }
    } else {
      root.keep(job.symbol, { status: "ok", fundamentals: read, checkedAt: clock.wallSecond() })
      root.askRate(read)
    }
  }

  // A stock off screen by now waits for its next ask for the rate.
  function askRate(fundamentals) {
    var pair = Fundamentals.ratePair(fundamentals, job.currency)
    if (!root.wants(job.symbol) || Fundamentals.rateHeld(pair, rates, failedPairs, clock.wallSecond())) {
      root.done()
      return
    }
    root.job = Object.assign({}, job, { step: "rate", pair: pair })
    root.run([Fundamentals.rateUrl(pair)])
  }

  // A failed fetch keeps the last good cap and P/E, but a series that came is
  // the truth for the EPS: it stands, and the cap stays unknown.
  function fail(symbol, skipRate) {
    root.miss(symbol)
    var series = job.fundamentals ? { fundamentals: { cap: null, eps: job.fundamentals.eps } } : {}
    root.keep(symbol, Object.assign({ fundamentals: null, checkedAt: 0 }, entries[symbol], { status: "failed" }, series))
    if (job.fundamentals && !skipRate) root.askRate(job.fundamentals)
    else root.done()
  }

  function keep(symbol, entry) {
    var next = Object.assign({}, entries)
    next[symbol] = entry
    root.entries = next
  }

  function done() {
    root.pendingUrls = []
    root.job = null
    root.look()
  }

  FetchRun {
    id: fetchRun
    gate: root.gate
    onEnded: function(got) { root.receive(got) }
  }
}
