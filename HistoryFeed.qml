import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "History.js" as History
import "Quote.js" as Quote
// The history for the charts on show, and those fetched ahead of a click.
// One curl at a time, one retry of a bad answer, fifteen minutes of cache,
// last-good kept on failure. The service says which chart it wants; a
// newer want, or none, stops the curl and the retry of the old one at once,
// so nothing nobody is looking at delays the chart that is. While Yahoo's
// gate pauses the host, a request fails at once, so its view says
// unavailable rather than "Loading".
// A chart asked for ahead (`ahead`) waits for the gate's spare budget
// (`Gate.spare`), has no retry, and keeps only a good answer: a row nobody
// clicked never says it is unavailable; its miss is told (`missed`).
// `entries` holds answers only, "ok" or "failed": what is on its way is
// `wanted`, so asking for a chart changes nothing a reader of the answers
// sees until one lands. An entry keeps its last good history and when it
// came (`receivedAt`), and when the last answer of any kind came
// (`answeredAt`). With nothing wanted the feed says so (`idle`), as
// the time to ask for a chart ahead.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // A screen answer lets pending work go; darkness spends no request or retry.
  property var clearance: null
  // The service, whose wall clock stamps each answer and ages the cache
  // (`wallSecond`); the system's without one.
  property var clock: null
  function stamp() { return clock ? clock.wallSecond() : Math.floor(Date.now() / 1000) }
  // The exchanges whose listings trade in whole cents from $1
  // (`History.parseHistory`); none unless handed in.
  property var centExchanges: []
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // The chart wanted, { key, symbol, range, ahead }, until its answer is in;
  // null when none is.
  property var wanted: null
  // The request under way, launched and not yet answered: its curl or its
  // retry pause.
  property var job: null
  property int attempts: 0
  // The job's curl was stopped; its answer, whatever it says, is dropped.
  property bool stopped: false
  property bool waitingForScreen: false

  readonly property bool busy: job !== null || wanted !== null

  // Nothing is wanted or under way.
  signal idle()
  // A chart asked for ahead got no good answer, and keeps none.
  signal missed(string key)

  function keyFor(symbol, range) {
    return String(symbol || "").toUpperCase() + "|" + String(range || "")
  }

  // At most `keep` charts' histories, in the order they were last set: the
  // one set longest ago goes first, but never one `inUse`, the charts on
  // show and the rows in sight fetched ahead (the service holds them to
  // fewer than `keep`): pushed out, one would be fetched again at once,
  // pushing out the next.
  readonly property int keep: 40
  property var inUse: []
  function setEntry(key, values) {
    var next = {}
    var others = Object.keys(entries).filter(function(k) { return k !== key })
    var over = others.length - (keep - 1)
    others.forEach(function(k) {
      if (over > 0 && root.inUse.indexOf(k) < 0) over--
      else next[k] = entries[k]
    })
    next[key] = Object.assign({ history: null, receivedAt: 0 }, entries[key], values)
    root.entries = next
  }

  // A chart to show, or with `ahead`, one fetched ahead of a click. A cached
  // answer under fifteen minutes old is enough unless `force`, a user's
  // refresh, asks for a new one; the charts on show needing nothing, a chart
  // on its way ahead for the same range goes on, and one for another stops.
  // A chart to show that is already on its way ahead is the one to show
  // from then on.
  function request(symbol, range, force, ahead) {
    var normalizedSymbol = String(symbol || "").toUpperCase()
    if (!History.historyUrl(normalizedSymbol, range)) {
      root.clear()
      return
    }
    var key = keyFor(normalizedSymbol, range)
    if (wanted && wanted.key === key) {
      if (wanted.ahead && !ahead) {
        var shown = Object.assign({}, wanted, { ahead: false })
        if (job && job.key === key) root.job = shown
        root.wanted = shown
      }
      return
    }
    var cached = entries[key]
    var now = root.stamp()
    if (!force && cached && cached.status === "ok" && cached.receivedAt && now - cached.receivedAt < 15 * 60) {
      if (!wanted || !wanted.ahead || wanted.range !== range) root.want(null)
      return
    }
    root.want({ key: key, symbol: normalizedSymbol, range: range, ahead: !!ahead })
  }

  // Charts fetched ahead for a range left behind go.
  function drop(keys) {
    var next = {}
    Object.keys(entries).forEach(function(k) { if (keys.indexOf(k) < 0) next[k] = entries[k] })
    if (Object.keys(next).length !== Object.keys(entries).length) root.entries = next
  }

  // No chart on show needs history: the day.
  function clear() {
    root.want(null)
  }

  function want(next) {
    root.wanted = next
    if (job && (!next || next.key !== job.key)) {
      if (waitingForScreen || retryTimer.running || heldTimer.running) {
        retryTimer.stop()
        heldTimer.stop()
        root.endJob()
      } else if (!stopped) {
        // Its stream ends at once, empty, and receive drops it.
        root.stopped = true
        fetchProc.running = false
      }
      return
    }
    root.launch()
  }

  function launch() {
    if (job) return
    if (!wanted) {
      root.idle()
      return
    }
    root.job = wanted
    root.attempts = 0
    root.run()
  }

  // While the gate holds the host, the request fails a turn later: the
  // change that asked for it is still being told. A chart asked for ahead
  // that the gate has no spare budget for is let go, nothing kept.
  function run() {
    if (clearance && !clearance()) { root.waitingForScreen = true; return }
    root.waitingForScreen = false
    if (gate && (job.ahead && !gate.spare() || gate.take(1) === 0)) {
      if (!job.ahead) {
        heldTimer.restart()
        return
      }
      root.wanted = null
      root.endJob()
      return
    }
    if (gate) root.ticket = gate.ticket
    root.attempts = attempts + 1
    fetchProc.command = Fetch.curlCommand([History.historyUrl(job.symbol, job.range)], Fetch.HISTORY_CAP)
    fetchProc.running = true
  }

  function pump() {
    if (job && waitingForScreen) root.run()
  }

  // The job is over; then the chart wanted now, if any, goes.
  function endJob() {
    root.waitingForScreen = false
    root.job = null
    root.attempts = 0
    root.stopped = false
    root.launch()
  }

  function receive(text) {
    var request = job
    var got = Fetch.answers(text)
    if (gate) gate.report(got.map(function(a) { return a.kind }), got.length ? got[0].retryAfter : 0, root.ticket)
    if (stopped || !wanted || wanted.key !== request.key) {
      root.endJob()
      return
    }

    var answer = got.length ? got[0] : null
    var history = null
    if (answer && answer.kind === "ok") {
      try { history = History.parseHistory(JSON.parse(answer.body), request.range, root.centExchanges) } catch (e) { history = null }
    }
    if (!history && !request.ahead && attempts < 2 && answer && (answer.kind === "bad" || answer.kind === "ok")) {
      retryTimer.restart()
      return
    }
    root.settle(history)
  }

  // The job's answer: a history, or null for a failure.
  function settle(history) {
    var request = job
    // Answered, before the answer is told: a reader of `entries` may want
    // the next chart at once, and that want must outlast this one.
    root.wanted = null
    if (!history && request.ahead) {
      root.missed(request.key)
      root.endJob()
      return
    }
    if (history) {
      var dropped = Quote.bucketTimes(history.droppedTimes)
      var previous = entries[request.key]
      var previousDropped = Quote.bucketTimes(previous && previous.history
        ? previous.history.droppedTimes : null)
      if (dropped && dropped !== previousDropped)
        console.warn("stonks: " + request.symbol + " " + request.range
          + " dropped stray buckets " + dropped)
      root.setEntry(request.key, {
        status: "ok",
        history: history,
        receivedAt: root.stamp(),
        answeredAt: root.stamp()
      })
    } else {
      root.setEntry(request.key, { status: "failed", answeredAt: root.stamp() })
    }
    root.endJob()
  }

  Timer {
    id: retryTimer
    interval: 2500
    onTriggered: root.run()
  }

  Timer {
    id: heldTimer
    interval: 0
    onTriggered: root.settle(null)
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(String(text || ""))
    }
  }
}
