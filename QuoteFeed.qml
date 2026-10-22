import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Quote.js" as Quote
// The quote feed: every symbol asked for goes in one run, one curl over one
// connection, and a run's answers land together. Hand it the members, what
// is watched, and what is due; read quotes, entries, and asks back. The
// panel never touches a Process.
//
// Two lanes, one run each at a time: first answers (a symbol with no
// answer this session) and refreshes, so an add never waits behind a
// refresh. The pill's symbol (`lead`) goes first in a run; it and any other
// hero's (`heroes`) go on the chart endpoint, whose opens a hero's line and
// the day's open need. The rest go in spark batches of up to 20
// (`Quote.sparkUrl`), closes only, judged by each listing's last chart
// verdict (`Quote.sparkQuote`), which also carries the day's open. One whose
// spark day holds a jump that verdict can't speak for, or a session opened
// since it, shows all the same, and waits to be judged on the
// chart (`toJudge`), a few a run from the budget's spare half. A run has no
// limit of its own: curl gives up on each URL within 10 s
// (`Fetch.curlCommand`).
//
// An entry is this symbol's last answer: { status, receivedAt, answeredAt },
// on the service's clock. "ok" or "failed" for the latest answer, or
// "saved" for a quote kept from an earlier session until its first answer;
// receivedAt is the last usable answer and survives failures, so a failed
// row still shows its last price; answeredAt is the last answer of any
// kind, which the service schedules by.
//
// `asked` holds each symbol asked for and not yet answered, with the second
// it was asked, which orders the queue. `owed` holds, of those, each one
// whose wait is on Yahoo, with the second that began: its request went and
// has no answer yet, or Yahoo paused while it waited. One held back only by
// the gate's budget, Stonks' own pacing, is not owed. Freshness calls an
// owed symbol overdue after 90 s. What came back decides
// (`Fetch.answerKind`): a bad answer is tried again 2.5 s later, three
// tries in all, then failed; a missing symbol fails at once; a refusal or
// no answer at all is the host's, not the symbol's, so it stays asked and
// owed, and the gate pauses every feed on that host.
Item {
  id: root

  // Every member: each gets one first answer.
  property var symbols: []
  // The members whose refreshes are owed: a refresh asked for one that is no
  // longer watched is dropped. First answers always stay.
  property var watched: []
  property string lead: ""
  // The symbols a hero shows, the lead and a resting preview of a member:
  // each goes on the chart, whose opens its line and the day's open need.
  property var heroes: lead ? [lead] : []
  property int now: 0
  // The service, whose wall clock stamps each ask and answer of the feed's
  // own (`stamp`): between its ticks `now` can be a minute behind.
  property var clock: null
  function stamp() { return clock ? clock.wallSecond() : now }
  // Asked before each run starts (the service's `screensClear`): false
  // while every screen is off, or while that is being asked; what waits is
  // pumped again once a screen is known on.
  property var clearance: null
  property var gate: null
  // Runs of the list leave the gate's reserve to single requests; the
  // preview's feed is one.
  property bool bulk: true
  // The exchanges whose listings trade in whole cents from $1
  // (`Quote.parseChart`); none unless handed in.
  property var centExchanges: []

  property var quotes: ({})
  property var entries: ({})
  property var asked: ({})
  property var owed: ({})
  // An answer, or leaving the queue, ends what was owed.
  onAskedChanged: {
    var next = null
    for (var symbol in owed) {
      if (symbol in asked) continue
      if (!next) next = Object.assign({}, owed)
      delete next[symbol]
    }
    if (next) root.owed = next
  }
  readonly property bool hostPaused: !!gate && gate.paused
  // Only what waits becomes owed here: the gate is still setting up the
  // pause as this fires, so nothing may be launched from it.
  onHostPausedChanged: oweWaiting()

  readonly property bool busy: firstProc.running || refreshProc.running || landing.length > 0 || Object.keys(asked).length > 0

  // Each lane's run under way, its symbols in the order of their requests.
  property var firstRun: []
  property var refreshRun: []
  // Bad answers so far for a symbol still asked for.
  property var tries: ({})
  // Symbols waiting out the pause after a bad answer.
  property var cooling: []
  // The gate's ticket each lane's run was let through on (`Gate.report`).
  property int firstTicket: 0
  property int refreshTicket: 0

  function firstAnswer(symbol) {
    var entry = entries[symbol]
    return !entry || entry.status === "saved"
  }

  // Asks for each of `list` it does not already owe, as of `at`, the
  // service's clock as it asks: the clock's own handlers may run before this
  // feed's binding to it has caught up.
  function ask(list, at) {
    var next = null
    list.forEach(function(symbol) {
      if (symbols.indexOf(symbol) < 0 || symbol in asked) return
      if (!next) next = Object.assign({}, asked)
      next[symbol] = at
    })
    if (next) root.asked = next
    pump()
  }

  onWatchedChanged: dropUnwatched()
  // The clock: a pause or a budget that held a run may have let go.
  onNowChanged: pump()

  // A refresh owed for a symbol no longer watched leaves the queue, unless
  // its run is still out; first answers always stay.
  function dropUnwatched() {
    var next = {}
    var dropped = false
    for (var symbol in asked) {
      if (firstAnswer(symbol) || watched.indexOf(symbol) >= 0 || inRun(symbol)) next[symbol] = asked[symbol]
      else dropped = true
    }
    if (dropped) root.asked = next
  }

  function inRun(symbol) {
    return firstRun.indexOf(symbol) >= 0 || refreshRun.indexOf(symbol) >= 0
  }

  // A symbol that leaves takes its quote, entry, and ask with it, so if it
  // comes back its first fetch is a first fetch again. A new one is asked
  // for its first answer.
  onSymbolsChanged: {
    root.quotes = kept(quotes)
    root.entries = kept(entries)
    root.tries = kept(tries)
    root.toJudge = toJudge.filter(function(symbol) { return symbols.indexOf(symbol) >= 0 })
    var next = kept(asked)
    symbols.forEach(function(symbol) { if (firstAnswer(symbol) && !(symbol in next)) next[symbol] = root.stamp() })
    root.asked = next
    pump()
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

  function pump() {
    oweWaiting()
    launch(true)
    launch(false)
  }

  // While the host is paused, everything waiting waits on Yahoo.
  function oweWaiting() {
    if (hostPaused) owe(symbols.filter(function(symbol) { return symbol in asked }))
  }

  // Each of `list` not owed already is owed from now.
  function owe(list) {
    var next = null
    var at = root.stamp()
    list.forEach(function(symbol) {
      if (symbol in owed) return
      if (!next) next = Object.assign({}, owed)
      next[symbol] = at
    })
    if (next) root.owed = next
  }

  // The next run of a lane: every symbol it owes that is not cooling or in
  // the other lane's run, as many requests as the gate lets go: the heroes'
  // charts first, the lead's leading, then spark batches in ask order, so
  // one the budget held goes before those asked since. A run with nothing
  // of that in the refresh lane carries instead a chart for each of up to
  // `judgeRun` symbols waiting to be judged, only from the budget's spare
  // half (`Gate.spare`): judging never splits a run, and a refresh falling
  // due waits for at most one run of it. The preview's feed (`bulk` false)
  // asks only the chart.
  readonly property int judgeRun: 4
  function launch(first) {
    var proc = first ? firstProc : refreshProc
    // A lane's run is out from its launch until it lands: its process can
    // say it stopped before its stream has ended. Nothing launches while a
    // run's answers are applied (`applying`).
    if (applying || (first ? firstRun : refreshRun).length > 0) return
    var waiting = symbols.filter(function(symbol) {
      return symbol in asked && firstAnswer(symbol) === first && cooling.indexOf(symbol) < 0 && !inRun(symbol)
    })
    var judging = first ? [] : toJudge.filter(function(symbol) {
      return !(symbol in asked) && cooling.indexOf(symbol) < 0 && !inRun(symbol)
    })
    if ((waiting.length === 0 && judging.length === 0) || (clearance && !clearance())) return
    waiting.sort(function(a, b) {
      return (b === lead) - (a === lead) || asked[a] - asked[b] || symbols.indexOf(a) - symbols.indexOf(b)
    })
    var charted = function(symbol) { return !bulk || heroes.indexOf(symbol) >= 0 }
    var slots = waiting.filter(charted).map(function(symbol) { return { symbols: [symbol], spark: false } })
    var batched = waiting.filter(function(symbol) { return !charted(symbol) })
    // A batch of one is a chart: one request either way, and the chart's
    // has opens, so its day needs no judging.
    for (var i = 0; i < batched.length; i += Quote.SPARK_BATCH) {
      var batch = batched.slice(i, i + Quote.SPARK_BATCH)
      slots.push({ symbols: batch, spark: batch.length > 1 })
    }
    var granted = slots.length > 0 && gate ? gate.take(slots.length, bulk) : slots.length
    var run = slots.slice(0, granted)
    for (var j = 0; slots.length === 0 && j < Math.min(judging.length, judgeRun) && (!gate || (gate.spare() && gate.take(1, bulk) === 1)); j++)
      run.push({ symbols: [judging[j]], spark: false })
    if (run.length === 0) return
    var runSymbols = []
    run.forEach(function(slot) { runSymbols = runSymbols.concat(slot.symbols) })
    // The lane is taken before anything its asks set off can launch again.
    if (first) {
      root.firstSlots = run
      root.firstRun = runSymbols
    } else {
      root.refreshSlots = run
      root.refreshRun = runSymbols
    }
    if (first && gate) root.firstTicket = gate.ticket
    if (!first && gate) root.refreshTicket = gate.ticket
    // A chart that only judges a day already shown owes no answer.
    owe(runSymbols.filter(function(symbol) { return symbol in asked }))
    var spark = run.some(function(slot) { return slot.spark })
    proc.command = Fetch.curlCommand(run.map(function(slot) {
      return slot.spark ? Quote.sparkUrl(slot.symbols) : Quote.chartUrl(slot.symbols[0])
    }), spark ? Fetch.SPARK_CAP : Fetch.DAY_CAP)
    proc.running = true
  }

  // Each lane's run under way as its requests, in the order of their URLs:
  // { symbols, spark }, one symbol to a chart.
  property var firstSlots: []
  property var refreshSlots: []
  // Symbols whose spark day holds a jump no chart verdict speaks for, each
  // waiting for its chart from the budget's spare half.
  property var toJudge: []

  // A hero whose quote came from spark has no opens for its line or the
  // day's open: its chart is asked for as it becomes one, whatever its last
  // answer, and again as a spark answer for it lands, one already out when
  // it became one; after a landing, not for one whose answer just failed,
  // so a failing chart is not asked again at once: its next refresh goes
  // on the chart.
  onHeroesChanged: chartHeroes(false)
  function chartHeroes(afterLanding) {
    ask(heroes.filter(function(symbol) {
      return quotes[symbol] && quotes[symbol].closesOnly && !(afterLanding && entries[symbol] && entries[symbol].status === "failed")
    }), root.stamp())
  }

  // A run's answers are read a little at a time, about 8 ms a turn
  // (`landStep`): a chart answer, a spark answer's text, or one listing of
  // it, so a long run never holds the shell's thread for long. The run lands
  // whole once its last answer is read (`land`), and until then its lane
  // runs nothing new. Each answer gets `outcomes`, by symbol: { quote,
  // unjudged }, null for a bad answer, or "missing". A listing whose reading
  // throws is a bad answer too, so the run still lands and the lane goes on:
  // one spark day that threw left its run out for good, and the lane asked
  // nothing more until Stonks restarted.
  property var landing: []
  function receive(first, text) {
    root.landing = landing.concat([{ first: first, slots: first ? firstSlots : refreshSlots, answers: Fetch.answers(text), read: 0 }])
    landTimer.start()
  }

  function landStep() {
    var job = landing[0]
    if (!job) return
    var until = Date.now() + 8
    while (job.read < job.answers.length && Date.now() < until) {
      var answer = job.answers[job.read]
      var slot = job.slots[answer.index]
      if (answer.kind !== "ok" || !slot) {
        job.read++
      } else if (!slot.spark) {
        var quote = null
        try { quote = Quote.parseChart(JSON.parse(answer.body), root.centExchanges) } catch (e) { quote = null }
        answer.body = null
        answer.outcomes = {}
        answer.outcomes[slot.symbols[0]] = quote ? { quote: quote, unjudged: false } : null
        job.read++
      } else if (!answer.outcomes) {
        try { answer.days = Quote.sparkResults(JSON.parse(answer.body)) } catch (e) { answer.days = null }
        answer.body = null
        answer.outcomes = {}
        answer.done = 0
      } else {
        var symbol = slot.symbols[answer.done++]
        var previous = quotes[symbol]
        var outcome = null
        try {
          outcome = !answer.days ? null : !(symbol in answer.days) ? "missing"
            : Quote.sparkQuote(answer.days[symbol], previous && previous.verdict || null, root.centExchanges)
        } catch (e) { outcome = null }
        answer.outcomes[symbol] = outcome
        if (answer.done >= slot.symbols.length) {
          answer.days = null
          job.read++
        }
      }
    }
    if (job.read < job.answers.length) {
      landTimer.start()
      return
    }
    root.landing = landing.slice(1)
    land(job)
    if (landing.length > 0) landTimer.start()
  }

  Timer {
    id: landTimer
    interval: 0
    onTriggered: root.landStep()
  }

  // While a run's answers are applied nothing launches: what they set off
  // (a new hero, a quote shown) would read the feed half updated.
  property bool applying: false
  function land(job) {
    root.applying = true
    var first = job.first
    if (first) {
      root.firstRun = []
      root.firstSlots = []
    } else {
      root.refreshRun = []
      root.refreshSlots = []
    }
    var at = root.stamp()
    var got = job.answers
    var nextQuotes = null
    var nextEntries = Object.assign({}, entries)
    var nextAsked = Object.assign({}, asked)
    var nextTries = Object.assign({}, tries)
    var nextJudge = toJudge.slice()
    var cool = []
    var kinds = []
    var retryAfter = 0
    var show = function(symbol, quote) {
      var dropped = Quote.bucketTimes(quote.droppedTimes)
      var previous = quotes[symbol]
      var previousDropped = Quote.bucketTimes(previous ? previous.droppedTimes : null)
      if (dropped && dropped !== previousDropped && !quote.closesOnly)
        console.warn("stonks: " + symbol + " dropped stray buckets " + dropped)
      // An answer with nothing new keeps the quote already shown, so nothing
      // is derived from it again and no line repaints; its receipt still moves.
      if (!previous || !Quote.sameQuote(quote, previous)) {
        if (!nextQuotes) nextQuotes = Object.assign({}, quotes)
        nextQuotes[symbol] = quote
      }
      nextEntries[symbol] = { status: "ok", receivedAt: at, answeredAt: at }
    }
    var settle = function(answer, slot, symbol) {
      // Removed while its run was out: the answer belongs to nobody.
      if (symbols.indexOf(symbol) < 0) return
      // A chart answer, whatever it says, is the judging a spark day waited
      // on. It keeps the spark answer's second, so the symbol stays due with
      // the rest of its run; one fetched only to judge that fails changes
      // nothing, and the next spark day asks again.
      var judging = !slot.spark && toJudge.indexOf(symbol) >= 0
      if (!slot.spark) nextJudge = nextJudge.filter(function(s) { return s !== symbol })
      var outcome = answer.kind === "ok" ? answer.outcomes[symbol] : null
      var quote = outcome && outcome !== "missing" ? outcome.quote : null
      if (judging && !(symbol in asked) && !quote) return
      if (quote) {
        // A day with a jump no chart has judged shows, and waits for one.
        if (outcome.unjudged && nextJudge.indexOf(symbol) < 0) nextJudge.push(symbol)
        show(symbol, quote)
        if (judging && entries[symbol]) nextEntries[symbol].answeredAt = entries[symbol].answeredAt
      } else if (answer.kind !== "missing" && outcome !== "missing" && (nextTries[symbol] || 0) < 2) {
        // A bad answer: a short pause, then the same symbol again.
        nextTries[symbol] = (nextTries[symbol] || 0) + 1
        cool.push(symbol)
        return
      } else {
        var entry = nextEntries[symbol] || { receivedAt: 0 }
        nextEntries[symbol] = Object.assign({}, entry, { status: "failed", answeredAt: at })
      }
      delete nextAsked[symbol]
      delete nextTries[symbol]
    }
    for (var i = 0; i < got.length; i++) {
      var answer = got[i]
      var slot = job.slots[answer.index]
      if (!slot) continue
      kinds.push(answer.kind)
      retryAfter = Math.max(retryAfter, answer.retryAfter)
      // A refusal or no answer leaves its symbols asked, for the gate to pace.
      if (answer.kind === "refused" || answer.kind === "none") continue
      for (var k = 0; k < slot.symbols.length; k++) settle(answer, slot, slot.symbols[k])
    }
    if (nextQuotes) root.quotes = nextQuotes
    root.entries = nextEntries
    root.toJudge = nextJudge.filter(function(s) { return symbols.indexOf(s) >= 0 })
    root.asked = nextAsked
    root.tries = nextTries
    dropUnwatched()
    if (cool.length) {
      root.cooling = cooling.concat(cool)
      retryTimer.restart()
    }
    if (gate) gate.report(kinds, retryAfter, first ? firstTicket : refreshTicket)
    root.applying = false
    // Asks for what is due next, a spark hero's chart among it.
    chartHeroes(true)
  }

  // A symbol that comes with its answer, not as a first fetch: a removal
  // taken back, with its quote, or a search's preview added, with its quote
  // or its failed first fetch (`quote` null). One that never left keeps its
  // own.
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

  // Quotes kept from an earlier session, shown until each first answer:
  // { symbol: { quote, receivedAt } }. A symbol already answered keeps its own.
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
    interval: 2500
    onTriggered: {
      root.cooling = []
      root.pump()
    }
  }

  // A run ends with its stream, never with the process stopping: both fire
  // for one run, and a failed curl still ends the stream.
  Process {
    id: firstProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(true, String(text || ""))
    }
  }

  Process {
    id: refreshProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(false, String(text || ""))
    }
  }
}
