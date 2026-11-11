.pragma library
// A sound that may wake the sound output opens with up to `LEAD_IN` ms of
// silence, for the waking to eat; see Sounds.qml for why. `output` is
// { wokeAt, awakeAt, asleepAfter, silenceRunning }, in ms: when Stonks last
// woke it, when the silence's stream was heard reaching it (-1 while it
// wakes and nothing has said so, 0 before it first woke), when it counts as
// asleep again, and whether the silence plays.

var LEAD_IN = 150

// The whole lead-in holds until the silence reaches the output, or 550 ms
// without one, then shrinks a third as fast as time passes, in 30 ms steps,
// so no chime, 45 ms apart, overtakes the one before.
function leadInAt(now, output) {
  var from = output.awakeAt >= 0 ? output.awakeAt : output.silenceRunning ? now : output.wokeAt + 550
  return Math.min(LEAD_IN, Math.max(0, Math.ceil((LEAD_IN - (now - from) / 3) / 30) * 30))
}

// Reached `LEAD_IN` ago, so the silence playing since has covered its
// waking; with no silence, a second after it woke.
function outputAwake(now, output) {
  if (now >= output.asleepAfter) return false
  return output.awakeAt >= 0 ? now >= output.awakeAt + LEAD_IN : !output.silenceRunning && now - output.wokeAt >= 1000
}

// A WAV with the plain 44-byte header the chimes and the bundled sounds
// have, opening with `ms` of silence.
function withLeadIn(bytes, ms) {
  var zeros = Math.round(new DataView(bytes).getUint32(24, true) * ms / 1000) * 2
  var out = new ArrayBuffer(bytes.byteLength + zeros)
  new Uint8Array(out).set(new Uint8Array(bytes, 0, 44))
  new Uint8Array(out, 44 + zeros).set(new Uint8Array(bytes, 44))
  var d = new DataView(out)
  d.setUint32(4, out.byteLength - 8, true)
  d.setUint32(40, out.byteLength - 44, true)
  return out
}
