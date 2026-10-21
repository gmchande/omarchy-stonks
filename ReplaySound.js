.pragma library

// The replay heard: the chart's line as sound, made from the chart on screen
// as a replay starts, in each look's voice. Its time is the replay's own: its
// place along the chart goes from `from` to `to` (0..1, the chart's x) over
// `seconds`, on Qt's InOutSine, as ChartMotion's replay scrubs. Pitch is the
// line's height on the chart, from its floor to its ceiling, so it reads the
// day the way the chart does, and where the line crosses its baseline,
// yesterday's close or the range's start, there is a tick. Smooth glides
// one octave on a sine with a little breath, and ticks on wood; retro steps
// one note per pixel column, on a two-octave pentatonic, so no note is sad
// and a down day sounds as kind as an up one, and ticks in noise. Each is
// levelled by its loudest 50 ms, under the fixed sounds.
// Ported from the sound study's make.js, which measured them.

var RATE = 24000

// Qt's Easing.InOutSine.
function inOutSine(u) {
  return -(Math.cos(Math.PI * u) - 1) / 2
}

// Where the replay is along the chart `t` seconds in.
function placeAt(t, from, to, seconds) {
  return from + (to - from) * inOutSine(Math.min(1, t / seconds))
}

// A seeded generator, the study's, so a chart makes the same bytes each time.
function random(seed) {
  var a = seed >>> 0
  return function() {
    a |= 0; a = a + 0x6D2B79F5 | 0
    var t = Math.imul(a ^ a >>> 15, 1 | a)
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t
    return ((t ^ t >>> 14) >>> 0) / 4294967296
  }
}

function fromDb(db) {
  return Math.pow(10, db / 20)
}

// RBJ low- and high-pass biquads, run in place.
function filter(x, type, f, q) {
  var w = 2 * Math.PI * f / RATE, c = Math.cos(w), s = Math.sin(w), a = s / (2 * q)
  var b0 = type === "lp" ? (1 - c) / 2 : (1 + c) / 2
  var b1 = type === "lp" ? 1 - c : -(1 + c)
  var a0 = 1 + a, a1 = -2 * c, a2 = 1 - a
  b0 /= a0; b1 /= a0; a1 /= a0; a2 /= a0
  var x1 = 0, x2 = 0, y1 = 0, y2 = 0
  for (var i = 0; i < x.length; i++) {
    var y = b0 * x[i] + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
    x2 = x1; x1 = x[i]; y2 = y1; y1 = y
    x[i] = y
  }
  return x
}

// Raised-cosine edges, so neither end clicks.
function fadeEdges(x, inMs, outMs) {
  var a = Math.round(inMs / 1000 * RATE), b = Math.round(outMs / 1000 * RATE)
  for (var i = 0; i < a && i < x.length; i++) x[i] *= 0.5 - 0.5 * Math.cos(Math.PI * i / a)
  for (var j = 0; j < b && j < x.length; j++) x[x.length - 1 - j] *= 0.5 - 0.5 * Math.cos(Math.PI * j / b)
  return x
}

// Scaled so its loudest 50 ms of RMS is `db` dBFS.
function level(x, db) {
  var win = Math.round(0.05 * RATE), best = 0, acc = 0
  for (var i = 0; i < x.length; i++) {
    acc += x[i] * x[i]
    if (i >= win) acc -= x[i - win] * x[i - win]
    if (acc / win > best) best = acc / win
  }
  var gain = best > 0 ? fromDb(db) / Math.sqrt(best) : 0
  for (var k = 0; k < x.length; k++) x[k] *= gain
  return x
}

// Smooth: `geometry` is the chart's, its points' x and y in 0..1 (y down)
// and its baseline's y. The line's height at each moment, interpolated
// between the points the replay passes, is the pitch: E4 at the floor, E5 at
// the ceiling, glided over 22 ms. Where the line crosses the baseline, the
// add sound's wooden bar an octave and a fifth up, 40 ms.
function smooth(geometry, from, to, seconds) {
  var pts = geometry.points
  var n = pts.length
  var x = new Float32Array(Math.round((seconds + 0.15) * RATE))
  var r = random(9)
  var breath = new Float32Array(x.length)
  for (var b = 0; b < breath.length; b++) breath[b] = r() * 2 - 1
  filter(breath, "lp", 1400, 0.7)
  var glideK = 1 - Math.exp(-1 / (0.022 * RATE))
  var ph = 0, glide = -1, k = 0, lastSide = 0, lastTick = -1
  var ticks = []
  for (var i = 0; i < x.length; i++) {
    var t = i / RATE
    var at = placeAt(t, from, to, seconds)
    // The place only moves on, so the segment it is on only moves on.
    while (k < n - 1 && pts[k + 1].x <= at) k++
    var y = n === 1 || at <= pts[0].x ? pts[0].y : k >= n - 1 ? pts[n - 1].y
      : pts[k].y + (pts[k + 1].y - pts[k].y) * (at - pts[k].x) / Math.max(1e-9, pts[k + 1].x - pts[k].x)
    var target = 329.63 * Math.pow(2, 1 - y)
    glide = glide < 0 ? target : glide + (target - glide) * glideK
    ph += glide / RATE
    var s = Math.sin(2 * Math.PI * ph) + 0.18 * Math.sin(4 * Math.PI * ph) + 0.06 * Math.sin(6 * Math.PI * ph)
    var fin = Math.min(1, t / 0.08)
    var fout = Math.max(0, Math.min(1, (seconds + 0.05 - t) / 0.2))
    x[i] = (0.5 - 0.5 * Math.cos(Math.PI * fin)) * (0.5 - 0.5 * Math.cos(Math.PI * fout)) * (s + 0.05 * breath[i])
    var side = Math.sign(geometry.baselineY - y)
    if (side && lastSide && side !== lastSide && t - lastTick > 0.08) {
      ticks.push(i)
      lastTick = t
    }
    if (side) lastSide = side
  }
  for (var j = 0; j < ticks.length; j++) {
    for (var m = 0; m < 0.04 * RATE && ticks[j] + m < x.length; m++) {
      var tt = m / RATE
      x[ticks[j] + m] += 0.55 * Math.exp(-tt / 0.012) * Math.sin(2 * Math.PI * 1760 * tt) * Math.min(1, tt / 0.0015)
    }
  }
  return level(fadeEdges(x, 1, 4), -36)
}

// A, B, C♯, E, F♯ over two octaves, from A4.
var PENTATONIC = [440, 493.88, 554.37, 659.25, 739.99, 880, 987.77, 1108.73, 1318.51, 1479.98, 1760]

// The NES's pulse pitches come from an 11-bit period: f = 1.789773 MHz /
// (16 (t + 1)). Snapping to it gives retro the console's slightly-off tuning.
function nesPitch(f) {
  return 1789773 / (16 * Math.round(1789773 / (16 * f)))
}

// One cycle of a 25% pulse at `f`, band-limited to 7 kHz, so nothing folds
// back: one table per note, read with the phase, rather than summing the
// harmonics at every sample.
var TABLE = 512
function pulseTable(f) {
  var duty = 0.25, top = Math.max(1, Math.floor(7000 / f))
  var table = new Float32Array(TABLE + 1)
  for (var i = 0; i <= TABLE; i++) {
    var phase = i / TABLE, v = 0
    for (var k = 1; k <= top; k++) v += (2 / (k * Math.PI)) * Math.sin(k * Math.PI * duty) * Math.cos(2 * Math.PI * k * (phase - duty / 2))
    table[i] = v
  }
  return table
}

// Volume in the console's 16 steps, falling one step every `stepMs`.
function nesVolume(t, start, stepMs, floor) {
  return Math.max(floor, start - Math.floor(t * 1000 / stepMs)) / 15
}

// Retro: `grid` is the retro chart's own (PixelChart's): its columns, its
// rows, each column's lit row (0 at the top), and the baseline's row. Each
// column the replay reaches plays its lit row as a note, low at the floor,
// high at the ceiling; a column with no print holds the note before, and a
// repeated note is held, not struck again. Where a column lands on the
// other side of the baseline from the last, the noise channel ticks, 30 ms.
function retro(grid, from, to, seconds) {
  var x = new Float32Array(Math.round((seconds + 0.1) * RATE))
  var rows = Math.max(1, grid.rows - 1)
  var tables = []
  var slewK = 1 - Math.exp(-1 / (0.0012 * RATE)), slew = 0
  var ph = 0, note = -1, since = 0, lastCol = -1, lastSide = 0
  var ticks = []
  for (var i = 0; i < x.length; i++) {
    var t = i / RATE
    var col = Math.max(0, Math.min(grid.columns - 1, Math.floor(placeAt(t, from, to, seconds) * grid.columns)))
    if (col !== lastCol) {
      lastCol = col
      var row = grid.levels[col]
      if (row !== undefined) {
        var next = Math.round((grid.rows - 1 - row) / rows * (PENTATONIC.length - 1))
        if (next !== note) {
          note = next
          since = t
        }
        var side = Math.sign(grid.baseRow - row)
        if (side && lastSide && side !== lastSide) ticks.push(i)
        if (side) lastSide = side
      }
    }
    var volume = note < 0 || t > seconds ? 0 : nesVolume(t - since, 11, 25, 6)
    slew += (volume - slew) * slewK
    if (note < 0) continue
    var f = nesPitch(PENTATONIC[note])
    if (!tables[note]) tables[note] = pulseTable(f)
    ph = (ph + f / RATE) % 1
    var at = ph * TABLE, a = Math.floor(at)
    x[i] = slew * (tables[note][a] + (tables[note][a + 1] - tables[note][a]) * (at - a))
  }
  // The noise channel: a 15-bit shift register clocked at 9 kHz.
  var noise = new Float32Array(Math.round(0.03 * RATE))
  var reg = 7, clock = 0
  for (var j = 0; j < noise.length; j++) {
    clock += 9000 / RATE
    while (clock >= 1) {
      clock -= 1
      reg = (reg >> 1) | ((((reg & 1) ^ ((reg >> 1) & 1))) << 14)
    }
    noise[j] = (reg & 1) ? -1 : 1
  }
  for (var n = 0; n < ticks.length; n++) {
    for (var m = 0; m < noise.length && ticks[n] + m < x.length; m++) x[ticks[n] + m] += 0.5 * nesVolume(m / RATE, 10, 4, 0) * noise[m]
  }
  filter(x, "hp", 90, 0.707)
  filter(x, "lp", 6500, 0.707)
  return level(fadeEdges(x, 1, 4), -37)
}

// The samples as a 16-bit mono WAV, its bytes, with a one-bit TPDF dither.
function wav(samples) {
  var bytes = new ArrayBuffer(44 + samples.length * 2)
  var d = new DataView(bytes)
  var text = function(at, s) { for (var c = 0; c < s.length; c++) d.setUint8(at + c, s.charCodeAt(c)) }
  text(0, "RIFF"); d.setUint32(4, 36 + samples.length * 2, true); text(8, "WAVE")
  text(12, "fmt "); d.setUint32(16, 16, true); d.setUint16(20, 1, true); d.setUint16(22, 1, true)
  d.setUint32(24, RATE, true); d.setUint32(28, RATE * 2, true); d.setUint16(32, 2, true); d.setUint16(34, 16, true)
  text(36, "data"); d.setUint32(40, samples.length * 2, true)
  var r = random(77)
  for (var i = 0; i < samples.length; i++)
    d.setInt16(44 + i * 2, Math.max(-32768, Math.min(32767, Math.round(samples[i] * 32767 + r() - r()))), true)
  return bytes
}
