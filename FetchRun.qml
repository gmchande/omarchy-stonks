import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
// Every request Stonks sends goes through a FetchRun: one curl at a time.
// The gate hears the answers (`Gate.report`) before the feed reads the
// last, so whatever a request sent alone after a pause sets off finds the
// gate as that answer left it.
Item {
  id: root

  property var gate: null
  // Answers as each lands (`arrived`): the quote feed shows the rows asked
  // first first.
  property bool streaming: false
  // Until the stream ends, even for a stopped run: its process can say it
  // stopped before that.
  property bool out: false
  property int count: 0
  // The gate's `pauses` as the run was sent (`Gate.js`).
  property int sentUnder: 0
  property bool told: false
  property int parsed: 0
  property var got: []

  signal arrived(var answers)
  // A stopped run's answers are what came before the stop.
  signal ended(var answers)

  function send(urls, cap) {
    root.count = urls.length
    root.sentUnder = gate ? gate.pauses : 0
    root.told = false
    root.parsed = 0
    root.got = []
    root.out = true
    proc.command = Fetch.curlCommand(urls, cap)
    proc.running = true
  }

  function stop() {
    proc.running = false
  }

  function read(text) {
    var fresh = Fetch.answers(text, parsed)
    if (fresh.length === 0) return fresh
    root.parsed = fresh[fresh.length - 1].end
    root.got = got.concat(fresh)
    if (got.length >= count) tell()
    return fresh
  }

  function tell() {
    if (told) return
    root.told = true
    if (gate) gate.report(got.map(function(a) { return a.kind }),
      Math.max.apply(null, [0].concat(got.map(function(a) { return a.retryAfter }))), sentUnder)
  }

  // The answers go with `ended`: the run keeps none once over.
  function end(text) {
    var fresh = read(text)
    root.out = false
    tell()
    if (streaming && fresh.length > 0) root.arrived(fresh)
    var got = root.got
    root.got = []
    root.ended(got)
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: !root.streaming
      onDataChanged: {
        if (!root.streaming) return
        var fresh = root.read(String(text || ""))
        if (fresh.length === 0) return
        // The host said no: the gate pauses it, and the rest of the run
        // would only be refused too.
        var refused = fresh.some(function(a) { return a.kind === "refused" })
        if (refused) root.tell()
        root.arrived(fresh)
        if (refused) root.stop()
      }
      onStreamFinished: root.end(String(text || ""))
    }
    // A command that fails to start ends with no stream's end: the run ends
    // there, with no answers.
    onRunningChanged: if (!running && root.out) root.end("")
  }
}
