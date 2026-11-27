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
  property bool refusedStop: false
  property var chunks: []
  property var got: []

  signal arrived(var answers)
  // A stopped run's answers are what came before the stop.
  signal ended(var answers)

  function send(urls, cap) {
    root.count = urls.length
    root.sentUnder = gate ? gate.pauses : 0
    root.told = false
    root.refusedStop = false
    root.chunks = []
    root.got = []
    root.out = true
    proc.command = Fetch.curlCommand(urls, cap)
    proc.running = true
  }

  function stop() {
    proc.running = false
  }

  function readLine(line) {
    if (!root.out || root.refusedStop) return
    var mark = Fetch.parseMarkLine(line)
    if (!mark) {
      root.chunks.push(line)
      return
    }
    var body = root.chunks.length > 0
      ? root.chunks.join("\n") + (mark.leading > 0 ? "\n".repeat(mark.leading) : "")
      : (mark.leading > 1 ? "\n".repeat(mark.leading - 1) : "")
    root.chunks = []
    var answer = Fetch.makeAnswer(body, mark, gate ? gate.now() : 0)
    root.got.push(answer)
    if (root.got.length >= count) tell()
    // The host said no: the gate pauses it, and the rest of the run would
    // only be refused too — stop immediately even for non-streaming runs.
    if (answer.kind === "refused") {
      root.refusedStop = true
      root.tell()
      if (root.streaming) root.arrived([answer])
      root.stop()
      return
    }
    if (root.streaming) root.arrived([answer])
  }

  function tell() {
    if (told) return
    root.told = true
    if (gate) gate.report(got.map(function(a) { return a.kind }),
      Math.max.apply(null, [0].concat(got.map(function(a) { return a.retryAfter }))), sentUnder)
  }

  // The answers go with `ended`: the run keeps none once over.
  function end() {
    root.out = false
    root.chunks = []
    tell()
    var got = root.got
    root.got = []
    root.ended(got)
  }

  Process {
    id: proc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.readLine(line) }
    }
    // SplitParser drains all buffered lines before `running` turns false,
    // and a command that fails to start ends here too with no answers.
    onRunningChanged: if (!running && root.out) root.end()
  }
}
