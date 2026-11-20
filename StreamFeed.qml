import QtQuick
import Quickshell.Io
import "Commands.js" as Commands
import "Gate.js" as Gate
import "Stream.js" as Stream
// Yahoo's price stream for `symbols` while `wanted` (`Commands.priceStream`).
// stream.py reports every `pace` seconds each symbol's newest trade since its
// last report, and a report lands whole, in one turn, as `ticks`: each
// symbol's newest trade, { t, p, heard, night }. One that ends on its own
// starts again: at once after its hour, else after a pause as a host's gate
// pauses (`Gate.gateAfterAnswers`), 2 s doubling to 60 for one that never
// connected or soon dropped, a minute doubling to 30 for one Yahoo refused.
// Without python3 it never starts again, and every listing is asked as
// before.
Item {
  id: root

  property var symbols: []
  property int pace: Stream.OPEN_PACE
  property bool wanted: false
  property var clock: null
  // The plugin's folder, where stream.py is.
  property string folder: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  property var ticks: ({})
  property bool missing: false
  // While a chart draws itself in, trades wait: each changes its line.
  property bool holding: false
  onHoldingChanged: if (!holding) Qt.callLater(root.land)

  property var gate: Gate.openGate(0)
  readonly property bool runs: wanted && symbols.length > 0 && !missing
  onRunsChanged: sync()
  // A listing scrolled out of sight keeps its last trade, which is still
  // true, and stops being live a minute on (`Stream.liveSymbols`).
  onSymbolsChanged: sync()

  function wall() { return clock ? clock.wallSecond() : Math.floor(Date.now() / 1000) }

  function sync() {
    if (!runs) {
      if (proc.running) {
        root.stopping = true
        proc.running = false
      }
      return
    }
    if (!proc.running) {
      var wait = gate.pausedUntil - wall()
      if (wait <= 0) start()
      else {
        again.interval = wait * 1000
        again.restart()
      }
      return
    }
    tell()
  }

  property string told: ""
  function tell() {
    var line = Stream.wantedLine(pace, symbols)
    if (line === told) return
    root.told = line
    proc.write(line + "\n")
  }

  property bool stopping: false
  property int startedAt: 0
  property bool traded: false
  property string why: ""
  property int code: -1
  function start() {
    root.told = ""
    root.traded = false
    root.why = ""
    root.code = -1
    root.startedAt = wall()
    proc.running = true
  }

  // Read as `running` falls, since a command that fails to start never
  // exits.
  function ended() {
    var code = root.code
    if (root.stopping) {
      root.stopping = false
      sync()
      return
    }
    if (code === 127) {
      root.missing = true
      console.warn("stonks: no python3, so prices are asked as often as before, with no stream")
      return
    }
    var now = wall()
    var lasted = root.traded && now - root.startedAt >= Stream.LIVE_AGE
    var kind = code === 124 || lasted ? "ok" : root.why === "refused" ? "refused" : "none"
    root.gate = Gate.gateAfterAnswers(gate, [kind], 0, gate.pauses, now, Math.random()).gate
    sync()
  }

  Timer {
    id: again
    onTriggered: root.sync()
  }

  property var incoming: ({})
  function heard(line) {
    var got = Stream.parseLine(line, wall())
    if (!got) return
    if (got.end !== undefined) {
      root.why = got.end
      return
    }
    root.traded = true
    root.incoming[got.symbol] = got.tick
    Qt.callLater(root.land)
  }
  function land() {
    var fresh = Object.keys(incoming).filter(function(s) { return symbols.indexOf(s) >= 0 })
    if (holding || fresh.length === 0) return
    var next = Object.assign({}, ticks)
    fresh.forEach(function(s) { next[s] = incoming[s] })
    root.incoming = ({})
    root.ticks = next
  }

  Process {
    id: proc
    stdinEnabled: true
    command: Commands.priceStream(Stream.STREAM_SECONDS, root.folder, Stream.STREAM_CAP)
    stdout: SplitParser { onRead: function(line) { root.heard(line) } }
    onStarted: root.tell()
    onExited: function(exitCode) { root.code = exitCode }
    onRunningChanged: if (!running) Qt.callLater(root.ended)
  }
}
