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
// refresh. The pill's symbol (`lead`) goes first in a run. A run still
// going after 20 s is stopped, and its host counts as not answering.
//
// An entry is this symbol's last answer: { status, receivedAt, answeredAt },
// on the service's clock. "ok" or "failed" for the latest answer, or
// "saved" for a quote kept from an earlier session until its first answer;
// receivedAt is the last usable answer and survives failures, so a failed
// row still shows its last price; answeredAt is the last answer of any
// kind, which the service schedules by.
//
// `asked` holds each symbol asked for and not yet answered, with the second
// it was asked: freshness calls one overdue after 90 s. What came back
// decides (`Fetch.answerKind`): a bad answer is tried again 2.5 s later,
// three tries in all, then failed; a missing symbol fails at once; a
// refusal or no answer at all is the host's, not the symbol's, so it stays
// asked and the gate pauses every feed on that host.
Item {
  id: root

  // Every member: each gets one first answer.
  property var symbols: []
  // The members whose refreshes are owed: a refresh asked for one that is no
  // longer watched is dropped. First answers always stay.
  property var watched: []
  property string lead: ""
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

  property var quotes: ({})
  property var entries: ({})
  property var asked: ({})

  readonly property bool busy: firstProc.running || refreshProc.running || landing.length > 0 || Object.keys(asked).length > 0

  // Each lane's run under way, its symbols in the order of their URLs.
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
    launch(true)
    launch(false)
  }

  // The next run of a lane: every symbol it owes that is not cooling or in
  // the other lane's run, as many as the gate lets go: the lead first, then
  // the longest asked, so one the budget held goes before those asked since.
  function launch(first) {
    var proc = first ? firstProc : refreshProc
    if (proc.running || landing.some(function(job) { return job.first === first })) return
    var waiting = symbols.filter(function(symbol) {
      return symbol in asked && firstAnswer(symbol) === first && cooling.indexOf(symbol) < 0 && !inRun(symbol)
    })
    if (waiting.length === 0 || (clearance && !clearance())) return
    waiting.sort(function(a, b) {
      return (b === lead) - (a === lead) || asked[a] - asked[b] || symbols.indexOf(a) - symbols.indexOf(b)
    })
    var granted = gate ? gate.take(waiting.length, bulk) : waiting.length
    if (granted === 0) return
    var run = waiting.slice(0, granted)
    if (first) root.firstRun = run
    else root.refreshRun = run
    if (first && gate) root.firstTicket = gate.ticket
    if (!first && gate) root.refreshTicket = gate.ticket
    proc.command = Fetch.curlCommand(run.map(Quote.chartUrl), Fetch.DAY_CAP)
    proc.running = true
    ;(first ? firstLimit : refreshLimit).restart()
  }

  // A run's answers are read a few at a time, about 8 ms a turn
  // (`landStep`), so a long run never holds the shell's thread for long;
  // the run lands whole once its last answer is read (`land`), and until
  // then its lane runs nothing new.
  property var landing: []
  function receive(first, text, stopped) {
    ;(first ? firstLimit : refreshLimit).stop()
    root.landing = landing.concat([{ first: first, answers: Fetch.answers(text), read: 0, stopped: stopped }])
    landTimer.start()
  }

  function landStep() {
    var job = landing[0]
    if (!job) return
    var until = Date.now() + 8
    while (job.read < job.answers.length && Date.now() < until) {
      var answer = job.answers[job.read++]
      if (answer.kind !== "ok") continue
      try { answer.quote = Quote.parseChart(JSON.parse(answer.body)) } catch (e) { answer.quote = null }
      answer.body = null
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

  function land(job) {
    var first = job.first
    var run = first ? firstRun : refreshRun
    if (first) root.firstRun = []
    else root.refreshRun = []
    var at = root.stamp()
    var got = job.answers
    var nextQuotes = null
    var nextEntries = Object.assign({}, entries)
    var nextAsked = Object.assign({}, asked)
    var nextTries = Object.assign({}, tries)
    var cool = []
    var kinds = []
    var retryAfter = 0
    for (var i = 0; i < got.length; i++) {
      var answer = got[i]
      var symbol = run[answer.index]
      if (!symbol) continue
      kinds.push(answer.kind)
      retryAfter = Math.max(retryAfter, answer.retryAfter)
      // Removed while its run was out: the answer belongs to nobody. A
      // refusal or no answer leaves it asked, for the gate to pace.
      if (symbols.indexOf(symbol) < 0 || answer.kind === "refused" || answer.kind === "none") continue
      var quote = answer.kind === "ok" ? answer.quote : null
      var entry = nextEntries[symbol] || { receivedAt: 0 }
      if (quote) {
        var dropped = Quote.bucketTimes(quote.droppedTimes)
        var previous = quotes[symbol]
        var previousDropped = Quote.bucketTimes(previous ? previous.droppedTimes : null)
        if (dropped && dropped !== previousDropped)
          console.warn("stonks: " + symbol + " dropped stray buckets " + dropped)
        // An answer with nothing new keeps the quote already shown, so nothing
        // is derived from it again and no line repaints; its receipt still moves.
        if (!previous || !Quote.sameQuote(quote, previous)) {
          if (!nextQuotes) nextQuotes = Object.assign({}, quotes)
          nextQuotes[symbol] = quote
        }
        nextEntries[symbol] = { status: "ok", receivedAt: at, answeredAt: at }
      } else if (answer.kind !== "missing" && (nextTries[symbol] || 0) < 2) {
        // A bad answer: a short pause, then the same symbol again.
        nextTries[symbol] = (nextTries[symbol] || 0) + 1
        cool.push(symbol)
        continue
      } else {
        nextEntries[symbol] = Object.assign({}, entry, { status: "failed", answeredAt: at })
      }
      delete nextAsked[symbol]
      delete nextTries[symbol]
    }
    if (nextQuotes) root.quotes = nextQuotes
    root.entries = nextEntries
    root.asked = nextAsked
    root.tries = nextTries
    dropUnwatched()
    if (cool.length) {
      root.cooling = cooling.concat(cool)
      retryTimer.restart()
    }
    // A run stopped before its end: the host is not answering.
    if (gate) gate.report(job.stopped ? kinds.concat(["none"]) : kinds, retryAfter, first ? firstTicket : refreshTicket)
    pump()
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

  Timer {
    id: firstLimit
    interval: 20000
    onTriggered: { firstProc.stopped = true; firstProc.running = false }
  }

  Timer {
    id: refreshLimit
    interval: 20000
    onTriggered: { refreshProc.stopped = true; refreshProc.running = false }
  }

  // A run ends with its stream, never with the process stopping: both fire
  // for one run, and a failed curl still ends the stream.
  Process {
    id: firstProc
    property bool stopped: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var stopped = firstProc.stopped
        firstProc.stopped = false
        root.receive(true, String(text || ""), stopped)
      }
    }
  }

  Process {
    id: refreshProc
    property bool stopped: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var stopped = refreshProc.stopped
        refreshProc.stopped = false
        root.receive(false, String(text || ""), stopped)
      }
    }
  }
}
