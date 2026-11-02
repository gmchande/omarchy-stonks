import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
// Every request Stonks sends goes through a FetchRun: one curl at a time.
// The gate hears the answers (`Gate.report`) before the feed reads the
// last, so whatever a request sent alone after a pause sets off finds the
// host open again.
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
  property int ticket: 0
  property bool told: false
  property int parsed: 0
  property var got: []

  signal arrived(var answers)
  // A stopped run's answers are what came before the stop.
  signal ended(var answers)

  function send(urls, cap) {
    root.count = urls.length
    root.ticket = gate ? gate.ticket : 0
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
      Math.max.apply(null, [0].concat(got.map(function(a) { return a.retryAfter }))), ticket)
  }

  function end(text) {
    var fresh = read(text)
    root.out = false
    tell()
    if (streaming && fresh.length > 0) root.arrived(fresh)
    root.ended(got)
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: !root.streaming
      onDataChanged: {
        if (!root.streaming) return
        var fresh = root.read(String(text || ""))
        if (fresh.length > 0) root.arrived(fresh)
      }
      onStreamFinished: root.end(String(text || ""))
    }
  }
}
