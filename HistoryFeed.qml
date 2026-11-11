import QtQuick
import "Fetch.js" as Fetch
import "History.js" as History
import "Quote.js" as Quote
// History for the charts on show and those fetched ahead of a click.
// Charts fetched ahead go as one curl run, so a slow network makes them
// wait once, not once each. `entries` holds answers only; what is on its
// way is `wanted`, so asking changes nothing a reader sees until one lands.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  property var clearance: null
  // The service's wall clock, so answers age by its time.
  property var clock: null
  function stamp() { return clock ? clock.wallSecond() : Math.floor(Date.now() / 1000) }
  // Exchanges whose listings trade in whole cents from $1.
  property var centExchanges: []
  property var wanted: null
  // Launched and not yet answered, its retry pause included.
  property var job: null
  property int attempts: 0
  // The job's curl was stopped; its answer is dropped.
  property bool stopped: false
  property bool waitingForScreen: false

  readonly property bool busy: job !== null || wanted !== null

  signal idle()
  // A chart asked for ahead got no good answer, and keeps none.
  signal missed(string key)

  function keyFor(symbol, range) {
    return History.historyKey(symbol, range)
  }

  function holds(request, key) {
    return !!request && request.charts.some(function(c) { return c.key === key })
  }
  function covers(request, next) {
    return !!request && !!next && next.ahead === request.ahead && next.range === request.range
      && next.charts.every(function(c) { return root.holds(request, c.key) })
  }

  // How many charts it holds, and those in use (`History.historiesKept`).
  readonly property int keep: 40
  property var inUse: []
  function setEntries(values) {
    root.entries = History.historiesKept(entries, values, inUse, keep)
  }

  // `force` is a user's refresh.
  function request(symbol, range, force) {
    var normalizedSymbol = String(symbol || "").toUpperCase()
    if (!History.historyUrl(normalizedSymbol, range)) {
      root.clear()
      return
    }
    var key = keyFor(normalizedSymbol, range)
    if (wanted && !wanted.ahead && wanted.charts[0].key === key) return
    if (!force && History.historyFresh(entries[key], root.stamp())) {
      if (!wanted || !wanted.ahead || wanted.range !== range) root.want(null)
      return
    }
    root.want({ range: range, ahead: false, charts: [{ key: key, symbol: normalizedSymbol }] })
  }

  function requestAhead(symbols, range) {
    var charts = symbols.map(function(s) { return String(s || "").toUpperCase() })
      .filter(function(s) { return !!History.historyUrl(s, range) })
      .map(function(s) { return { key: keyFor(s, range), symbol: s } })
    if (charts.length > 0) root.want({ range: range, ahead: true, charts: charts })
  }

  function drop(keys) {
    var next = {}
    Object.keys(entries).forEach(function(k) { if (keys.indexOf(k) < 0) next[k] = entries[k] })
    if (Object.keys(next).length !== Object.keys(entries).length) root.entries = next
  }

  // The day needs no history.
  function clear() {
    root.want(null)
  }

  function want(next) {
    root.wanted = next
    if (job && !covers(job, next)) {
      if (waitingForScreen || retryTimer.running || heldTimer.running) {
        retryTimer.stop()
        heldTimer.stop()
        root.endJob()
      } else if (!stopped) {
        // Its stream ends at once, empty, and receive drops it.
        root.stopped = true
        fetchRun.stop()
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

  // While the gate holds the host, a chart to show fails a turn later: the
  // change that asked for it is still being told.
  function run() {
    if (clearance && !clearance()) { root.waitingForScreen = true; return }
    root.waitingForScreen = false
    if (job.ahead && gate) {
      var granted = 0
      while (granted < job.charts.length && gate.spare() && gate.take(1) === 1) granted++
      if (granted === 0) {
        root.wanted = null
        root.endJob()
        return
      }
      if (granted < job.charts.length) {
        var cut = Object.assign({}, job, { charts: job.charts.slice(0, granted) })
        root.wanted = cut
        root.job = cut
      }
    } else if (gate && gate.take(1) === 0) {
      heldTimer.restart()
      return
    }
    root.attempts = attempts + 1
    var range = job.range
    fetchRun.send(job.charts.map(function(c) { return History.historyUrl(c.symbol, range) }), Fetch.HISTORY_CAP)
  }

  function pump() {
    if (job && waitingForScreen) root.run()
  }

  function endJob() {
    root.waitingForScreen = false
    root.job = null
    root.attempts = 0
    root.stopped = false
    root.launch()
  }

  function parse(answer, range) {
    if (!answer || answer.kind !== "ok") return null
    try { return History.parseHistory(JSON.parse(answer.body), range, root.centExchanges) } catch (e) { return null }
  }

  function receive(got) {
    var request = job
    if (stopped || !covers(request, wanted)) {
      root.endJob()
      return
    }
    var answers = request.charts.map(function(c, i) { return got.filter(function(a) { return a.index === i })[0] || null })
    var histories = answers.map(function(a) { return root.parse(a, request.range) })
    var answer = answers[0]
    if (!request.ahead && !histories[0] && attempts < 2 && answer && (answer.kind === "bad" || answer.kind === "ok")) {
      retryTimer.restart()
      return
    }
    root.settle(histories)
  }

  function settle(histories) {
    var request = job
    // Cleared before `entries` changes: a reader may want the next chart at
    // once, and that want must stand.
    root.wanted = null
    var now = root.stamp()
    var values = {}
    var misses = []
    request.charts.forEach(function(chart, i) {
      var history = histories[i]
      if (history) {
        var dropped = Quote.bucketTimes(history.droppedTimes)
        var previous = entries[chart.key]
        var previousDropped = Quote.bucketTimes(previous && previous.history
          ? previous.history.droppedTimes : null)
        if (dropped && dropped !== previousDropped)
          console.warn("stonks: " + chart.symbol + " " + request.range
            + " dropped stray buckets " + dropped)
        values[chart.key] = { status: "ok", history: history, receivedAt: now, answeredAt: now }
      } else if (request.ahead) misses.push(chart.key)
      else values[chart.key] = { status: "failed", answeredAt: now }
    })
    misses.forEach(function(key) { root.missed(key) })
    if (Object.keys(values).length > 0) root.setEntries(values)
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
    onTriggered: root.settle([null])
  }

  FetchRun {
    id: fetchRun
    gate: root.gate
    onEnded: function(got) { root.receive(got) }
  }
}
