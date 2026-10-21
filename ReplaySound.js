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
// Ported from the sound study's make.js, which measured them. The shell's
// engine interprets a loop that runs once, so the work per sample is a
// table read and a few sums: the place, the pitch, and the envelope move
// once a millisecond (`STEP`), and each voice reads one cycle from a table.

var RATE = 24000
var STEP = 24
var TABLE = 1024

// Qt's Easing.InOutSine.
function inOutSine(u) {
  return -(Math.cos(Math.PI * u) - 1) / 2
}

// Where the replay is along the chart `t` seconds in.
function placeAt(t, from, to, seconds) {
  return from + (to - from) * inOutSine(Math.min(1, t / seconds))
}

// One cycle of `shape(phase)`, phase 0..1, with a guard point for reading
// between entries.
function cycle(shape) {
  var table = new Float32Array(TABLE + 1)
  for (var i = 0; i <= TABLE; i++) table[i] = shape(i / TABLE)
  return table
}

// An RBJ low- or high-pass biquad's coefficients.
function biquad(type, f, q) {
  var w = 2 * Math.PI * f / RATE, c = Math.cos(w), s = Math.sin(w), a = s / (2 * q)
  var a0 = 1 + a
  var b0 = (type === "lp" ? (1 - c) / 2 : (1 + c) / 2) / a0
  return { b0: b0, b1: (type === "lp" ? 1 - c : -(1 + c)) / a0, b2: b0, a1: -2 * c / a0, a2: (1 - a) / a0 }
}

// A high-pass then a low-pass, in place, in one pass.
function band(x, low, high) {
  var h = biquad("hp", low, 0.707), l = biquad("lp", high, 0.707)
  var hx1 = 0, hx2 = 0, hy1 = 0, hy2 = 0, ly1 = 0, ly2 = 0
  for (var i = 0; i < x.length; i++) {
    var hy = h.b0 * x[i] + h.b1 * hx1 + h.b2 * hx2 - h.a1 * hy1 - h.a2 * hy2
    hx2 = hx1; hx1 = x[i]; hy2 = hy1
    var ly = l.b0 * hy + l.b1 * hy1 + l.b2 * hy2 - l.a1 * ly1 - l.a2 * ly2
    hy1 = hy; ly2 = ly1; ly1 = ly
    x[i] = ly
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

// The sound, and the gain that puts its loudest 50 ms of RMS at `db` dBFS,
// which `wav` applies as it writes.
function levelled(x, db) {
  var win = Math.round(0.05 * RATE), best = 0, acc = 0
  for (var i = 0; i < x.length; i++) {
    acc += x[i] * x[i]
    if (i >= win) acc -= x[i - win] * x[i - win]
    if (acc > best) best = acc
  }
  return { samples: x, gain: best > 0 ? Math.pow(10, db / 20) / Math.sqrt(best / win) : 0 }
}

// Smooth: `geometry` is the chart's, its points' x and y in 0..1 (y down)
// and its baseline's y. The line's height at each moment, interpolated
// between the points the replay passes, is the pitch: E4 at the floor, E5 at
// the ceiling, glided over 22 ms, on a sine with its second and third
// harmonics and a breath of low noise. Where the chart draws no line, across
// a break in the exchange's day (`brk`: Tokyo's lunch), it is silent,
// fading out and in over 5 ms, and the line's next print starts its pitch
// afresh. Where the drawn line crosses the baseline, the add sound's wooden
// bar an octave and a fifth up, 40 ms; a line that ends on one side and
// starts again on the other after a break crosses nothing.
function smooth(geometry, from, to, seconds) {
  var pts = geometry.points
  var n = pts.length
  var x = new Float32Array(Math.round((seconds + 0.15) * RATE))
  var wave = cycle(function(p) { return Math.sin(2 * Math.PI * p) + 0.18 * Math.sin(4 * Math.PI * p) + 0.06 * Math.sin(6 * Math.PI * p) })
  var glideK = 1 - Math.exp(-STEP / (0.022 * RATE))
  var gateStep = STEP / (0.005 * RATE)
  // The breath: seeded noise through a one-pole low-pass at 1.4 kHz.
  var breathK = 1 - Math.exp(-2 * Math.PI * 1400 / RATE), seed = 9, breath = 0
  var ph = 0, glide = -1, k = 0, lastSide = 0, lastTick = -1, gate = 1, level = 0, wasBreak = false
  var ticks = []
  for (var i = 0; i < x.length; i += STEP) {
    var t = i / RATE
    var at = placeAt(t, from, to, seconds)
    // The place only moves on, so the segment it is on only moves on.
    while (k < n - 1 && pts[k + 1].x <= at) k++
    var inBreak = k < n - 1 && !!pts[k + 1].brk && at > pts[k].x
    var y = inBreak || n === 1 || at <= pts[0].x ? pts[k].y : k >= n - 1 ? pts[n - 1].y
      : pts[k].y + (pts[k + 1].y - pts[k].y) * (at - pts[k].x) / Math.max(1e-9, pts[k + 1].x - pts[k].x)
    var target = 329.63 * Math.pow(2, 1 - y)
    glide = glide < 0 || (wasBreak && !inBreak) ? target : glide + (target - glide) * glideK
    wasBreak = inBreak
    gate = inBreak ? Math.max(0, gate - gateStep) : Math.min(1, gate + gateStep)
    var fin = Math.min(1, t / 0.08)
    var fout = Math.max(0, Math.min(1, (seconds + 0.05 - t) / 0.2))
    var envelope = gate * (0.5 - 0.5 * Math.cos(Math.PI * fin)) * (0.5 - 0.5 * Math.cos(Math.PI * fout))
    // The envelope moves across the millisecond, not at its start.
    var rise = (envelope - level) / STEP
    var step = glide / RATE * TABLE
    var end = Math.min(x.length, i + STEP)
    for (var j = i; j < end; j++) {
      level += rise
      ph += step
      if (ph >= TABLE) ph -= TABLE
      var a = ph | 0
      seed = (seed * 1664525 + 1013904223) >>> 0
      breath += (seed / 2147483648 - 1 - breath) * breathK
      x[j] = level * (wave[a] + (wave[a + 1] - wave[a]) * (ph - a) + 0.05 * breath)
    }
    if (inBreak) {
      lastSide = 0
      continue
    }
    var side = Math.sign(geometry.baselineY - y)
    if (side && lastSide && side !== lastSide && t - lastTick > 0.08) {
      ticks.push(i)
      lastTick = t
    }
    if (side) lastSide = side
  }
  for (var m = 0; m < ticks.length; m++) {
    for (var d = 0; d < 0.04 * RATE && ticks[m] + d < x.length; d++) {
      var tt = d / RATE
      x[ticks[m] + d] += 0.55 * Math.exp(-tt / 0.012) * Math.sin(2 * Math.PI * 1760 * tt) * Math.min(1, tt / 0.0015)
    }
  }
  return levelled(fadeEdges(x, 1, 4), -36)
}

// A, B, C♯, E, F♯ over two octaves, from A4.
var PENTATONIC = [440, 493.88, 554.37, 659.25, 739.99, 880, 987.77, 1108.73, 1318.51, 1479.98, 1760]

// The NES's pulse pitches come from an 11-bit period: f = 1.789773 MHz /
// (16 (t + 1)). Snapping to it gives retro the console's slightly-off tuning.
function nesPitch(f) {
  return 1789773 / (16 * Math.round(1789773 / (16 * f)))
}

// One cycle of a 25% pulse at `f`, band-limited to 7 kHz, so nothing folds
// back.
function pulseTable(f) {
  var duty = 0.25, top = Math.max(1, Math.floor(7000 / f))
  return cycle(function(phase) {
    var v = 0
    for (var k = 1; k <= top; k++) v += (2 / (k * Math.PI)) * Math.sin(k * Math.PI * duty) * Math.cos(2 * Math.PI * k * (phase - duty / 2))
    return v
  })
}

// Volume in the console's 16 steps, falling one step every `stepMs`.
function nesVolume(t, start, stepMs, floor) {
  return Math.max(floor, start - Math.floor(t * 1000 / stepMs)) / 15
}

// Retro: `grid` is the retro chart's own (PixelChart's): its columns, its
// rows, each column's lit row (0 at the top), and the baseline's row. Each
// column the replay reaches plays its lit row as a note, low at the floor,
// high at the ceiling; a column with no print, which the chart leaves dark,
// is silent. A repeated note is held, not struck again, its volume falling
// in the console's steps; after silence it is struck again. Where a lit
// column lands on the other side of the baseline from the lit one before
// it, the noise channel ticks, 30 ms; across dark columns nothing crosses.
function retro(grid, from, to, seconds) {
  var x = new Float32Array(Math.round((seconds + 0.1) * RATE))
  var rows = Math.max(1, grid.rows - 1)
  var tables = []
  var slewK = 1 - Math.exp(-1 / (0.0012 * RATE)), slew = 0
  var ph = 0, note = -1, since = 0, lastCol = -1, lastSide = 0, step = 0, wave = null, lit = false
  var ticks = []
  for (var i = 0; i < x.length; i += STEP) {
    var t = i / RATE
    var col = Math.max(0, Math.min(grid.columns - 1, Math.floor(placeAt(t, from, to, seconds) * grid.columns)))
    if (col !== lastCol) {
      lastCol = col
      var row = grid.levels[col]
      var wasLit = lit
      lit = row !== undefined
      if (!lit) lastSide = 0
      if (lit) {
        var next = Math.round((grid.rows - 1 - row) / rows * (PENTATONIC.length - 1))
        if (next !== note || !wasLit) since = t
        if (next !== note) {
          note = next
          var f = nesPitch(PENTATONIC[note])
          if (!tables[note]) tables[note] = pulseTable(f)
          wave = tables[note]
          step = f / RATE * TABLE
        }
        var side = Math.sign(grid.baseRow - row)
        if (side && lastSide && side !== lastSide) ticks.push(i)
        if (side) lastSide = side
      }
    }
    var volume = !lit || t > seconds ? 0 : nesVolume(t - since, 11, 25, 6)
    var end = Math.min(x.length, i + STEP)
    if (!wave) continue
    for (var j = i; j < end; j++) {
      slew += (volume - slew) * slewK
      ph += step
      if (ph >= TABLE) ph -= TABLE
      var a = ph | 0
      x[j] = slew * (wave[a] + (wave[a + 1] - wave[a]) * (ph - a))
    }
  }
  // The noise channel: a 15-bit shift register clocked at 9 kHz.
  var noise = new Float32Array(Math.round(0.03 * RATE))
  var reg = 7, clock = 0
  for (var c = 0; c < noise.length; c++) {
    clock += 9000 / RATE
    while (clock >= 1) {
      clock -= 1
      reg = (reg >> 1) | (((reg & 1) ^ ((reg >> 1) & 1)) << 14)
    }
    noise[c] = (reg & 1) ? -1 : 1
  }
  for (var n = 0; n < ticks.length; n++) {
    for (var m = 0; m < noise.length && ticks[n] + m < x.length; m++) x[ticks[n] + m] += 0.5 * nesVolume(m / RATE, 10, 4, 0) * noise[m]
  }
  return levelled(fadeEdges(band(x, 90, 6500), 1, 4), -37)
}

// A levelled sound as a 16-bit mono WAV, its bytes, with a one-bit TPDF
// dither. The samples go in in the machine's byte order, which on every
// machine Omarchy runs on is the WAV's own, little-endian.
function wav(sound) {
  var samples = sound.samples, gain = sound.gain * 32767
  var bytes = new ArrayBuffer(44 + samples.length * 2)
  var d = new DataView(bytes)
  var text = function(at, s) { for (var c = 0; c < s.length; c++) d.setUint8(at + c, s.charCodeAt(c)) }
  text(0, "RIFF"); d.setUint32(4, 36 + samples.length * 2, true); text(8, "WAVE")
  text(12, "fmt "); d.setUint32(16, 16, true); d.setUint16(20, 1, true); d.setUint16(22, 1, true)
  d.setUint32(24, RATE, true); d.setUint32(28, RATE * 2, true); d.setUint16(32, 2, true); d.setUint16(34, 16, true)
  text(36, "data"); d.setUint32(40, samples.length * 2, true)
  var out = new Int16Array(bytes, 44)
  var seed = 77
  for (var i = 0; i < samples.length; i++) {
    seed = (seed * 1664525 + 1013904223) >>> 0
    var dither = seed / 4294967296
    seed = (seed * 1664525 + 1013904223) >>> 0
    var v = Math.round(samples[i] * gain + dither - seed / 4294967296)
    out[i] = v > 32767 ? 32767 : v < -32768 ? -32768 : v
  }
  return bytes
}
