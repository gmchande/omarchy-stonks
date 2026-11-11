import QtQuick
import "Gate.js" as Rules
// One host's gate, which every request to that host asks first. It keeps the
// gate's state and reads the clock; what a gate lets through, and when it
// pauses, is `Gate.js`. The first time its budget holds a request back it
// says so.
Item {
  id: root

  property string host: ""
  // The service: its wall clock (`wallSecond`), read at each call, never its
  // `now`, which trails the wall between ticks while nothing is open.
  property var clock: null
  property int capacity: 80
  property real perMinute: 40
  property int reserve: 10
  readonly property var limits: ({ capacity: capacity, perMinute: perMinute, reserve: reserve })

  property var gate: Rules.openGate(capacity)
  // Why the host is paused: "" while it answers, "none" or "refused".
  readonly property string pause: gate.pause
  readonly property int pausedUntil: gate.pausedUntil
  readonly property bool paused: pause !== ""
  // The lone request after a pause is out.
  readonly property bool loneOut: gate.loneOut
  readonly property bool warned: gate.warned
  // Moves on as each pause begins: a run notes it as it is sent.
  readonly property int pauses: gate.pauses

  signal reopened()

  function now() {
    return clock ? clock.wallSecond() : 0
  }

  function take(count, bulk) {
    var taken = Rules.takenFromGate(gate, limits, count, bulk, now())
    root.gate = taken.gate
    if (taken.heldBack > 0) console.warn("stonks: " + host + "'s budget held back " + taken.heldBack + " requests")
    return taken.granted
  }

  // Takes nothing.
  function spare() {
    root.gate = Rules.refilledGate(gate, limits, now())
    return Rules.gateHasSpare(gate, limits)
  }

  function report(kinds, retryAfter, sentUnder) {
    var heard = Rules.gateAfterAnswers(gate, kinds, retryAfter, sentUnder, now(), Math.random())
    root.gate = heard.gate
    if (heard.reopened) root.reopened()
  }

  function retryNow() {
    root.gate = Rules.gateRetriedNow(gate, now())
  }
}
