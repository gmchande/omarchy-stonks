import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Release.js" as Release
// The newest Stonks, from main's manifest on GitHub (`Release`): what
// `omarchy plugin update` would bring. Asked as the service is ready, then a
// day after each ask, whatever GitHub said, and only while a screen is on
// (`clearance`) and GitHub's gate lets it. An ask that got no answer at
// all, as straight after a wake before the network is back, goes again once
// Yahoo answers again after its own pause (`askAgain`), or a day on: asked
// again each time GitHub's short pause ended, it went about once a minute
// for as long as the network was down. Only a whole answer naming a version
// changes `version`: a failure or a refusal leaves it as it was and says
// nothing, since it is not a quote.
Item {
  id: root

  // The version main names, "" until an answer has named one, and the wall
  // second of the ask whose answer last named it, so a surface can say each
  // day's answer once (`Updates.releaseUnsaid`).
  property string version: ""
  property int namedAt: 0
  property bool ready: false
  // The service's clock: `now` moves the feed to look, and the wall clock
  // (`wallSecond`) is what it reads.
  property int now: 0
  property var clock: null
  property var clearance: null
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  // The wall second of the last ask; 0 before the first.
  property int askedAt: 0
  // The last ask got no answer at all.
  property bool unanswered: false

  readonly property int interval: 24 * 60 * 60

  // Looked at as the clock moves, as the service is ready, and as the
  // screens answer.
  function pump() {
    if (!ready || fetchProc.running) return
    var now = clock.wallSecond()
    if (askedAt > 0 && now - askedAt < interval) return
    if (clearance && !clearance()) return
    if (gate && gate.take(1) === 0) return
    root.askedAt = now
    if (gate) root.ticket = gate.ticket
    fetchProc.command = Fetch.curlCommand([Release.MANIFEST_URL], Fetch.MANIFEST_CAP)
    fetchProc.running = true
  }
  onNowChanged: pump()
  onReadyChanged: pump()

  // The network is back: an ask that got no answer goes now.
  function askAgain() {
    if (!unanswered) return
    root.askedAt = 0
    pump()
  }

  function receive(text) {
    var got = Fetch.answers(text)
    if (gate) gate.report(got.map(function(a) { return a.kind }), got.length ? got[0].retryAfter : 0, root.ticket)
    root.unanswered = got.length > 0 && got.every(function(a) { return a.kind === "none" })
    var named = got.length && got[0].kind === "ok" ? Release.manifestVersion(got[0].body) : ""
    if (named === "") return
    root.version = named
    root.namedAt = root.askedAt
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(String(text || ""))
    }
  }
}
