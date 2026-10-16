import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Fundamentals.js" as Fundamentals
// Yahoo's dated cap and P/E, one symbol at a time, kept for the day. Two
// curls in turn: the snapshots, then the closes on their dates, which move
// them with the price (`Fundamentals.yearLine`). An entry is "ok" with its
// figures, either of which may be null when Yahoo has none, or "failed",
// keeping the last good figures; a failed one is asked again the next time
// it is wanted. While Yahoo's gate pauses the host, a fetch fails at once.
Item {
  id: root

  property var entries: ({})
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // The symbol to fetch once the one under way is done.
  property string wanted: ""
  // The fetch under way: { symbol, figures }, figures null until the
  // snapshots are in and their closes are out.
  property var job: null

  readonly property bool busy: job !== null || wanted !== ""

  function fetch(symbol) {
    var normalized = String(symbol || "").toUpperCase()
    if (!normalized || (job && job.symbol === normalized)) return
    var current = entries[normalized]
    if (current && current.status === "ok" && Math.floor(Date.now() / 1000) - current.checkedAt < 24 * 60 * 60) return
    root.wanted = normalized
    root.launch()
  }

  function launch() {
    if (job || !wanted) return
    root.job = { symbol: wanted, figures: null }
    root.wanted = ""
    root.run(Fundamentals.fundamentalsUrl(job.symbol, Math.floor(Date.now() / 1000)))
  }

  function run(url) {
    if (gate && gate.take(1) === 0) {
      root.settle(job.symbol, null)
      return
    }
    if (gate) root.ticket = gate.ticket
    fetchProc.command = Fetch.curlCommand([url], Fetch.FUNDAMENTALS_CAP)
    fetchProc.running = true
  }

  function receive(text) {
    var got = Fetch.answers(text)
    if (gate) gate.report(got.map(function(a) { return a.kind }), got.length ? got[0].retryAfter : 0, root.ticket)
    var json = null
    try { json = got.length && got[0].kind === "ok" ? JSON.parse(got[0].body) : null } catch (e) { json = null }
    var symbol = job.symbol
    if (job.figures) {
      root.settle(symbol, Fundamentals.withSnapshotCloses(job.figures, json))
      return
    }
    var figures = Fundamentals.parseFundamentals(json)
    var closesUrl = figures ? Fundamentals.snapshotClosesUrl(symbol, figures) : null
    if (!closesUrl) {
      root.settle(symbol, figures)
      return
    }
    root.job = { symbol: symbol, figures: figures }
    root.run(closesUrl)
  }

  function settle(symbol, figures) {
    var next = Object.assign({}, entries)
    next[symbol] = figures
      ? { status: "ok", figures: figures, checkedAt: Math.floor(Date.now() / 1000) }
      : Object.assign({ figures: null, checkedAt: 0 }, entries[symbol], { status: "failed" })
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
