import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
import "Release.js" as Release
// The newest Stonks, from main's manifest on GitHub (`Release`): what
// `omarchy plugin update` would bring. Asked as the service is ready, then a
// day after each ask, whatever came back, and only while a screen is on
// (`clearance`). Only a whole answer naming a version changes `version`: a
// failure or a refusal leaves it as it was and says nothing, since it is
// not a quote. While GitHub's gate pauses the host, the ask goes unsent and
// waits its day.
Item {
  id: root

  // The version main names, "" until an answer has named one.
  property string version: ""
  property bool ready: false
  // The service's clock: `now` moves the feed to look, and the wall clock
  // (`wallSecond`) is what it reads.
  property int now: 0
  property var clock: null
  property var clearance: null
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0
  property int askedAt: 0

  readonly property int interval: 24 * 60 * 60

  // Looked at as the clock moves, as the service is ready, and as the
  // screens answer.
  function pump() {
    if (!ready || fetchProc.running) return
    var now = clock.wallSecond()
    if (askedAt > 0 && now - askedAt < interval) return
    if (clearance && !clearance()) return
    root.askedAt = now
    if (gate && gate.take(1) === 0) return
    if (gate) root.ticket = gate.ticket
    fetchProc.command = Fetch.curlCommand([Release.MANIFEST_URL], Fetch.MANIFEST_CAP)
    fetchProc.running = true
  }
  onNowChanged: pump()
  onReadyChanged: pump()

  function receive(text) {
    var got = Fetch.answers(text)
    if (gate) gate.report(got.map(function(a) { return a.kind }), got.length ? got[0].retryAfter : 0, root.ticket)
    var named = got.length && got[0].kind === "ok" ? Release.manifestVersion(got[0].body) : ""
    if (named !== "") root.version = named
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(String(text || ""))
    }
  }
}
