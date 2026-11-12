import QtQuick
import "Asks.js" as Asks
import "Fetch.js" as Fetch
import "Quote.js" as Quote
// Every symbol due goes in one curl run over one connection, and the
// symbols waiting for their first answer go in a run of their own.
// `FetchRun` reads each answer as it lands. The panel never touches a Process.
Item {
  id: root

  property var symbols: []
  // The members refreshes and judging charts are owed for; first answers
  // always stay.
  property var watched: []
  property string featured: ""
  // The featured stock and a resting preview: each goes on a chart, for its
  // opens.
  property var charted: featured ? [featured] : []
  // Read as a run is sent (`Asks.readingOrder`): the order it asks in.
  property var reading: null
  // Answers wait while a chart draws itself in, so reading never stutters it.
  property bool holding: false
  onHoldingChanged: if (!holding) landTimer.start()
  property int now: 0
  // Asks and answers take the service's wall clock: between its ticks `now`
  // can be a minute behind.
  property var clock: null
  function stamp() { return clock ? clock.wallSecond() : now }
  // Asked before each run (the service's `screensClear`): nothing goes while
  // every screen is off, and what waits goes once a screen is on.
  property var mayAsk: null
  property var gate: null
  // The list's runs leave the gate's reserve to single requests, such as the
  // preview's feed.
  property bool bulk: true
  property var centExchanges: []
  // A spark batch asks two days for all when one wants two (`Asks.twoDays`),
  // so the requests stay as many.
  property var calendars: null
  function twoDays(symbol) { return Asks.twoDays(quotes[symbol] || null, stamp(), calendars) }

  property var quotes: ({})
  // Each symbol's last answer, by the service's clock. "saved": a quote kept
  // from an earlier session, until its first answer. receivedAt is the last
  // usable answer, so a failed row keeps its price; answeredAt, any answer.
  property var entries: ({})
  // `asked`: each symbol asked for and unanswered, from when, which orders the
  // queue. `owed`: those whose wait is on Yahoo, from when: a request out, or
  // Yahoo paused. One held only by the gate's budget isn't owed.
  property var asked: ({})
  property var owed: ({})
  // What a reader's refresh waits on, until its answer, the end of its run,
  // or Yahoo pausing Stonks. `userOut`: one of them is on a request now.
  property var userAsked: ({})
  readonly property bool userOut: refreshRun.some(function(symbol) { return symbol in userAsked })
  onAskedChanged: {
    var owing = queued(owed)
    if (owing !== owed) root.owed = owing
    var waiting = queued(userAsked)
    if (waiting !== userAsked) root.userAsked = waiting
  }
  function queued(map) {
    var next = null
    for (var symbol in map) {
      if (symbol in asked) continue
      if (!next) next = Object.assign({}, map)
      delete next[symbol]
    }
    return next || map
  }
  function without(map, list) {
    var next = null
    list.forEach(function(symbol) {
      if (!(symbol in map)) return
      if (!next) next = Object.assign({}, map)
      delete next[symbol]
    })
    return next || map
  }
  readonly property bool hostPaused: !!gate && gate.paused
  // The gate is still setting up the pause as this fires: nothing may be sent
  // from it.
  onHostPausedChanged: {
    markOwedWhilePaused()
    if (hostPaused) root.userAsked = ({})
  }

  readonly property bool busy: firstFetch.out || refreshFetch.out || landing.length > 0 || Object.keys(asked).length > 0

  // The first answers' run and the refresh run under way, in request order.
  // First answers have a run of their own, so an add never waits behind a
  // refresh.
  property var firstRun: []
  property var refreshRun: []
  property var tries: ({})
  // Symbols waiting out the pause after a bad answer, `retryAfter`
  // milliseconds (`retryTimer`).
  property var retrying: []
  property int retryAfter: 2500

  function firstAnswer(symbol) {
    return Asks.firstAnswer(entries[symbol])
  }

  // `at` is the service's clock as it asks: its handlers may run before this
  // feed's binding to it has caught up.
  function ask(list, at, user) {
    var next = null
    list.forEach(function(symbol) {
      if (symbols.indexOf(symbol) < 0 || symbol in asked) return
      if (!next) next = Object.assign({}, asked)
      next[symbol] = at
    })
    if (next) root.asked = next
    if (user && !hostPaused) {
      var waiting = null
      list.forEach(function(symbol) {
        if (!(symbol in asked) || symbol in userAsked) return
        if (!waiting) waiting = Object.assign({}, userAsked)
        waiting[symbol] = true
      })
      if (waiting) root.userAsked = waiting
    }
    sendWaiting()
  }

  onWatchedChanged: dropUnwatched()
  // A pause or a budget that held a run may have let go.
  onNowChanged: sendWaiting()

  function dropUnwatched() {
    var next = Asks.keptAsks(asked, watched, entries, firstRun.concat(refreshRun))
    if (next !== asked) root.asked = next
  }

  function inRun(symbol) {
    return firstRun.indexOf(symbol) >= 0 || refreshRun.indexOf(symbol) >= 0
  }

  onSymbolsChanged: {
    root.quotes = kept(quotes)
    root.entries = kept(entries)
    root.tries = kept(tries)
    root.toJudge = toJudge.filter(function(symbol) { return symbols.indexOf(symbol) >= 0 })
    var next = kept(asked)
    symbols.forEach(function(symbol) { if (firstAnswer(symbol) && !(symbol in next)) next[symbol] = root.stamp() })
    root.asked = next
    sendWaiting()
  }

  function kept(map) {
    var out = {}
    var same = true
    for (var key in map) {
      if (symbols.indexOf(key) >= 0) out[key] = map[key]
      else same = false
    }
    return same ? map : out
  }

  function sendWaiting() {
    markOwedWhilePaused()
    sendRun(true)
    sendRun(false)
  }

  function markOwedWhilePaused() {
    if (hostPaused) markOwed(symbols.filter(function(symbol) { return symbol in asked }))
  }

  function markOwed(list) {
    var next = null
    var at = root.stamp()
    list.forEach(function(symbol) {
      if (symbol in owed) return
      if (!next) next = Object.assign({}, owed)
      next[symbol] = at
    })
    if (next) root.owed = next
  }

  // Judging takes only a refresh run with nothing else in it, from the
  // budget's spare half: it never splits a run, and a refresh falling due
  // waits at most one run of it. A run has no limit of its own: curl gives
  // up on each URL within 10 s.
  readonly property int judgeRun: 4
  function sendRun(first) {
    // A run is out until it lands: its process can say it stopped before its
    // stream has ended.
    if (applying || (first ? firstRun : refreshRun).length > 0) return
    var held = retrying.concat(firstRun, refreshRun)
    var waiting = Asks.runWaiting(symbols, asked, entries, first, held)
    var judging = first ? [] : Asks.runJudging(toJudge, asked, held, watched)
    if ((waiting.length === 0 && judging.length === 0) || (mayAsk && !mayAsk())) return
    var coins = waiting.filter(function(s) { return !!quotes[s] && !!quotes[s].crypto })
    var requests = Asks.quoteRequests(waiting, asked, reading ? reading() : symbols, featured, charted, bulk, coins)
    var granted = requests.length > 0 && gate ? gate.take(requests.length, bulk) : requests.length
    var run = requests.slice(0, granted)
    for (var j = 0; requests.length === 0 && j < Math.min(judging.length, judgeRun); j++) {
      if (gate && !(gate.spare() && gate.take(1, bulk) === 1)) break
      run.push({ symbols: [judging[j]], spark: false })
    }
    if (run.length === 0) return
    var runSymbols = []
    run.forEach(function(request) { runSymbols = runSymbols.concat(request.symbols) })
    // The run is taken before anything its asks set off can send another.
    if (first) root.firstRun = runSymbols
    else root.refreshRun = runSymbols
    root.landing = landing.concat([{ first: first, requests: run, answers: [], read: 0, ended: false, retry: [], back: [] }])
    // A chart that only judges a day already shown owes no answer.
    markOwed(runSymbols.filter(function(symbol) { return symbol in asked }))
    var spark = run.some(function(request) { return request.spark })
    var urls = run.map(function(request) {
      return request.spark ? Quote.sparkUrl(request.symbols, request.symbols.some(root.twoDays)) : Quote.chartUrl(request.symbols[0], root.twoDays(request.symbols[0]))
    })
    ;(first ? firstFetch : refreshFetch).send(urls, spark ? Fetch.SPARK_CAP : Fetch.DAY_CAP)
  }

  // Symbols whose spark day holds a jump no chart verdict speaks for.
  property var toJudge: []

  // A charted stock from spark has no opens for its line or the day's open,
  // so its chart is asked for.
  onChartedChanged: askCharts(false)
  function askCharts(afterLanding) {
    ask(Asks.sparkCharted(charted, quotes, entries, afterLanding), root.stamp())
  }

  // Answers are read about 8 ms a turn, so a long run never holds the shell's
  // thread for long, and each turn's are applied at once, so the rows asked
  // first show first. A listing whose reading throws is a bad answer, so
  // the run still ends.
  property var landing: []
  function runOf(first) {
    for (var i = 0; i < landing.length; i++) if (landing[i].first === first && !landing[i].ended) return landing[i]
    return null
  }
  function arrived(first, got) {
    var job = runOf(first)
    if (!job) return
    job.answers = job.answers.concat(got)
    landTimer.start()
  }
  function ended(first) {
    var job = runOf(first)
    if (!job) return
    job.ended = true
    landTimer.start()
  }

  function landStep() {
    if (holding) return
    var until = Date.now() + 8
    var more = false
    landing.forEach(function(job) {
      var read = []
      while (job.read < job.answers.length && Date.now() < until) {
        var answer = job.answers[job.read]
        if (!readAnswer(answer, job.requests[answer.index])) continue
        read.push(answer)
        job.read++
      }
      if (read.length > 0) apply(job, read)
      if (job.read < job.answers.length) more = true
    })
    var ended = landing.filter(function(job) { return job.ended && job.read >= job.answers.length })
    if (ended.length > 0) {
      root.landing = landing.filter(function(job) { return ended.indexOf(job) < 0 })
      ended.forEach(finish)
    }
    if (more) landTimer.start()
  }

  function readAnswer(answer, request) {
    if (answer.kind !== "ok" || !request) return true
    if (!request.spark) {
      var quote = null
      try { quote = Quote.parseChart(JSON.parse(answer.body), root.centExchanges, root.stamp()) } catch (e) { quote = null }
      answer.body = null
      answer.outcomes = {}
      answer.outcomes[request.symbols[0]] = quote ? { quote: quote, unjudged: false } : null
      return true
    }
    if (!answer.outcomes) {
      try { answer.days = Quote.sparkResults(JSON.parse(answer.body)) } catch (e) { answer.days = null }
      answer.body = null
      answer.outcomes = {}
      answer.done = 0
      return false
    }
    var symbol = request.symbols[answer.done++]
    var previous = quotes[symbol]
    var outcome = null
    try {
      outcome = !answer.days ? null : !(symbol in answer.days) ? "missing"
        : Quote.sparkQuote(answer.days[symbol], previous && previous.verdict || null, root.centExchanges, root.stamp())
    } catch (e) { outcome = null }
    answer.outcomes[symbol] = outcome
    if (answer.done < request.symbols.length) return false
    answer.days = null
    return true
  }

  Timer {
    id: landTimer
    interval: 0
    onTriggered: root.landStep()
  }

  // What answers set off, a new charted stock or a quote shown, would read the feed
  // half updated.
  property bool applying: false
  function apply(job, got) {
    root.applying = true
    var next = Asks.quotesLanded({ quotes: quotes, entries: entries, asked: asked, tries: tries, toJudge: toJudge },
      job.requests, got, symbols, calendars, root.stamp())
    next.warnings.forEach(function(warning) { console.warn("stonks: " + warning) })
    job.retry = job.retry.concat(next.retry)
    if (!job.first) {
      job.back = job.back.concat(next.back)
      root.userAsked = without(userAsked, next.back)
    }
    if (next.quotes !== quotes) root.quotes = next.quotes
    root.entries = next.entries
    root.toJudge = next.toJudge
    root.asked = next.asked
    root.tries = next.tries
    root.applying = false
  }

  // The gate heard every answer before the last was read (`FetchRun`).
  function finish(job) {
    root.applying = true
    if (job.first) {
      root.firstRun = []
    } else {
      root.userAsked = without(userAsked, refreshRun.filter(function(s) { return job.back.indexOf(s) < 0 }))
      root.refreshRun = []
    }
    dropUnwatched()
    if (job.retry.length) {
      root.retrying = retrying.concat(job.retry)
      retryTimer.restart()
    }
    root.applying = false
    askCharts(true)
  }

  // A symbol that comes back with its answer: a removal taken back, or a
  // search's preview added (`quote` null for its failed first fetch).
  function restore(symbol, quote, entry) {
    if (quotes[symbol] && !firstAnswer(symbol)) return
    if (quote) {
      var nextQuotes = Object.assign({}, quotes)
      nextQuotes[symbol] = quote
      root.quotes = nextQuotes
    }
    var nextEntries = Object.assign({}, entries)
    nextEntries[symbol] = Object.assign({ status: "ok", receivedAt: 0, answeredAt: 0 }, entry)
    root.entries = nextEntries
    if (symbol in asked && !inRun(symbol)) {
      var nextAsked = Object.assign({}, asked)
      delete nextAsked[symbol]
      root.asked = nextAsked
    }
  }

  // Quotes kept from an earlier session: { symbol: { quote, receivedAt } }.
  function seed(saved) {
    var nextQuotes = Object.assign({}, quotes)
    var nextEntries = Object.assign({}, entries)
    for (var symbol in saved) {
      if (symbols.indexOf(symbol) < 0 || !firstAnswer(symbol) || quotes[symbol]) continue
      nextQuotes[symbol] = saved[symbol].quote
      nextEntries[symbol] = { status: "saved", receivedAt: saved[symbol].receivedAt, answeredAt: 0 }
    }
    root.quotes = nextQuotes
    root.entries = nextEntries
  }

  Timer {
    id: retryTimer
    interval: root.retryAfter
    onTriggered: {
      root.retrying = []
      root.sendWaiting()
    }
  }

  FetchRun {
    id: firstFetch
    gate: root.gate
    streaming: true
    onArrived: function(got) { root.arrived(true, got) }
    onEnded: root.ended(true)
  }

  FetchRun {
    id: refreshFetch
    gate: root.gate
    streaming: true
    onArrived: function(got) { root.arrived(false, got) }
    onEnded: root.ended(false)
  }
}
