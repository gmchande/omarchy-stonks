import QtQuick
import Quickshell.Io
import "Fetch.js" as Fetch
// One feed's curl, one run at a time, and every request Stonks sends goes
// through one: the URLs a feed has let through its host's gate, compressed
// and capped (`Fetch.curlCommand`), on the gate's ticket as they went. The
// gate hears the run's answers (`Gate.report`) as soon as there is one for
// every URL, or as the stream ends, before the feed reads the last of them:
// the request sent alone after a pause has one answer, and whatever reading
// it sets off finds the host open again. What to send, what to do when the
// gate or the screens say no, and what an answer means stay the feed's. A
// run is out from its send until its stream has ended, a stopped run's too:
// its process can say it stopped before that.
Item {
  id: root

  property var gate: null
  // Answers are told as each one lands (`arrived`), not only as the run
  // ends: the quote feed shows the rows asked first first.
  property bool streaming: false
  property bool out: false
  // The run's URL count, the gate's ticket it went on, whether the gate has
  // heard it, how far its output is read, and its answers so far.
  property int count: 0
  property int ticket: 0
  property bool told: false
  property int parsed: 0
  property var got: []

  // Answers new since the last, in order, while `streaming`.
  signal arrived(var answers)
  // Every answer the run got, once its stream has ended; a stopped run's are
  // what came before the stop.
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

  // The run ends now; its stream ends with what came.
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
