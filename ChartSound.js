.pragma library

// The chart heard, in each look's voice: the chimes, and the replay.
// The chimes are the chart as a row of bars you run a hand along: the
// pentatonic's eleven notes, low at the chart's floor and high at its
// ceiling, a bar each (`barAt`, `chime`), so no note is sad and a down day
// sounds as kind as an up one.
// The replay is made from the chart on screen as a replay starts. Its time
// is the replay's own: its place along the chart goes from `from` to `to`
// (0..1, the chart's x) over `seconds`, on Qt's InOutSine, as ChartMotion's
// replay scrubs. Smooth strikes the scrub's chimes as the place moves onto
// each bar; retro steps one note per pixel column, on the same bars, and
// where the line crosses its baseline, yesterday's close or the range's
// start, ticks in noise.
// Each sound is levelled by its loudest 50 ms, under the fixed sounds.
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

// A high-pass then a low-pass, in place, in one pass: the high-pass's output
// is the low-pass's input, so the low-pass reads its last two outputs
// (`hy1`, `hy2`) before they move on.
function band(x, low, high) {
  var h = biquad("hp", low, 0.707), l = biquad("lp", high, 0.707)
  var hx1 = 0, hx2 = 0, hy1 = 0, hy2 = 0, ly1 = 0, ly2 = 0
  for (var i = 0; i < x.length; i++) {
    var hy = h.b0 * x[i] + h.b1 * hx1 + h.b2 * hx2 - h.a1 * hy1 - h.a2 * hy2
    hx2 = hx1; hx1 = x[i]
    var ly = l.b0 * hy + l.b1 * hy1 + l.b2 * hy2 - l.a1 * ly1 - l.a2 * ly2
    hy2 = hy1; hy1 = hy; ly2 = ly1; ly1 = ly
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
// which `wav` applies as it writes. The window is a whole number the engine
// keeps as one (`| 0`): indexed by Math.round's result, read as a fraction,
// a retro replay's levelling took 16 ms instead of 2.
function levelled(x, db) {
  var win = Math.round(0.05 * RATE) | 0, best = 0, acc = 0
  for (var i = 0; i < x.length; i++) {
    acc += x[i] * x[i]
    if (i >= win) acc -= x[i - win] * x[i - win]
    if (acc > best) best = acc
  }
  return { samples: x, gain: best > 0 ? Math.pow(10, db / 20) / Math.sqrt(best / win) : 0 }
}

// Smooth: the scrub's chimes, struck as the replay's place moves onto each
// bar of the line (`lineBars` on `geometry`, the chart's), as a pointer
// swept along it strikes them: at most one every 45 ms, a bar struck sooner
// waiting out the gap with the latest waiting winning, none where the chart
// draws no line (a break: Tokyo's lunch), and each ringing out its half
// second over what follows. No tick where the line crosses its baseline:
// it was a short tone at A6, the top bar's own pitch, and among the bars it
// read as one more. Each bar sits as a chime does, so a replay sounds as a
// sweep does.
function smooth(geometry, from, to, seconds) {
  var bars = lineBars(geometry)
  var x = new Float32Array(Math.round((seconds + 0.6) * RATE))
  var gap = Math.round(0.045 * RATE), end = Math.round(seconds * RATE)
  var heard = -1, last = -gap, waiting = -1
  var strike = function(bar, at) {
    var note = smoothBarSamples(bar), n = Math.min(note.length, x.length - at)
    // An index the engine keeps as a whole number: indexed by the sum of
    // the loop's steps, read as a fraction, the mix took eight times as long.
    for (var j = 0, k = at | 0; j < n; j++, k++) x[k] += note[j]
    last = at
    waiting = -1
  }
  for (var i = 0; i < end; i += STEP) {
    var bar = bars(placeAt(i / RATE, from, to, seconds))
    // Where the line lifts, a bar waiting is dropped: nothing starts there.
    if (bar < 0) waiting = -1
    if (waiting >= 0 && i >= last + gap) strike(waiting, last + gap)
    if (bar === heard) continue
    heard = bar
    if (bar < 0) continue
    if (i >= last + gap) strike(bar, i)
    else waiting = bar
  }
  if (waiting >= 0) strike(waiting, last + gap)
  return { samples: x, gain: 1 }
}

// Smooth's bar `bar` as a chime plays it, levelled, made once and kept: a
// replay strikes dozens, and the scrub's chimes are written from it too.
var smoothBars = []
function smoothBarSamples(bar) {
  if (!smoothBars[bar]) {
    var sound = smoothBar(PENTATONIC[bar])
    var note = new Float32Array(sound.samples.length)
    for (var i = 0; i < note.length; i++) note[i] = sound.samples[i] * sound.gain
    smoothBars[bar] = note
  }
  return smoothBars[bar]
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

// Retro's bar `bar` as a pulse cycle at the console's pitch, made once and
// kept, as smooth's bars are: made afresh on every replay, the tables were
// most of a retro replay's synthesis.
var pulseBars = []
function pulseBar(bar) {
  if (!pulseBars[bar]) pulseBars[bar] = pulseTable(nesPitch(PENTATONIC[bar]))
  return pulseBars[bar]
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
        var next = rowBar(grid, row)
        if (next !== note || !wasLit) since = t
        if (next !== note) {
          note = next
          var f = nesPitch(PENTATONIC[note])
          wave = pulseBar(note)
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
  return levelled(fadeEdges(band(x, 90, 6500), 1, 4), -22)
}

// The bar a height on the chart (0 its floor, 1 its ceiling) sounds.
function barOf(height) {
  return Math.round(Math.max(0, Math.min(1, height)) * (PENTATONIC.length - 1))
}

// The bar a row of the retro chart's grid (0 at the top) sounds.
function rowBar(grid, row) {
  return barOf((grid.rows - 1 - row) / Math.max(1, grid.rows - 1))
}

// The bar the chart sounds at `x` (0..1 along it), or -1 where it draws
// nothing: in smooth the line's height there (`lineBars`), as the scrub's
// dot sits; in retro the lit row of the column there (`chart.grid`,
// PixelChart's), dark columns silent.
function barAt(chart, x) {
  if (x < 0) return -1
  if (chart.retro) {
    var grid = chart.grid
    if (!grid || !grid.levels) return -1
    var row = grid.levels[Math.max(0, Math.min(grid.columns - 1, Math.floor(x * grid.columns)))]
    return row === undefined ? -1 : rowBar(grid, row)
  }
  return lineBars(chart.geometry)(x)
}

// The bar under smooth's line at each place along it, as `Chart.yAt` reads
// the line: -1 before its first print, past its last, and across a break
// (`brk`, Tokyo's lunch), where the line lifts. It walks on from where it
// was last asked, so a replay, whose place only moves on, reads the line
// once.
function lineBars(geometry) {
  var pts = geometry ? geometry.points : [], k = 0
  return function(x) {
    if (!pts.length || x < pts[0].x || x > pts[pts.length - 1].x) return -1
    if (pts.length === 1) return barOf(1 - pts[0].y)
    if (x < pts[k].x) k = 0
    while (k < pts.length - 2 && pts[k + 1].x < x) k++
    var a = pts[k], b = pts[k + 1]
    if (b.brk && x > a.x && x < b.x) return -1
    return barOf(1 - (a.y + (b.y - a.y) * (b.x === a.x ? 0 : (x - a.x) / (b.x - a.x))))
  }
}

// A chime: bar `bar` (0..10) struck, in the look's voice. Smooth's is a soft
// metal bar struck with felt, ringing about half a second: a free bar's
// modes (1, 2.756, 5.404), the upper ones dying first, and higher bars
// ringing shorter, as real ones do. Retro's is a pulse blip that falls in
// the console's volume steps, a tenth of a second. Each sits 5 dB under the
// add sound, so a sweep's overlapping bars come to about its level.
function chime(retro, bar) {
  return retro ? retroBar(bar) : { samples: smoothBarSamples(bar), gain: 1 }
}

function smoothBar(f) {
  var ring = 0.55
  var x = new Float32Array(Math.round(ring * RATE))
  var tau = ring / 4.6 * 1.2 * Math.sqrt(440 / f)
  var modes = [[1, 1, 1], [2.756, 0.28, 0.35], [5.404, 0.08, 0.15]]
  for (var m = 0; m < modes.length; m++) {
    // A decaying sine by its recurrence, two products a sample.
    var w = 2 * Math.PI * f * modes[m][0] / RATE
    var r = Math.exp(-1 / (tau * modes[m][2] * RATE))
    var c = 2 * r * Math.cos(w), rr = r * r
    var before = 0, last = modes[m][1] * r * Math.sin(w)
    x[1] += last
    for (var i = 2; i < x.length; i++) {
      var next = c * last - rr * before
      x[i] += next
      before = last
      last = next
    }
  }
  // The felt: a 3 ms rise; and the tail faded to nothing.
  return levelled(fadeEdges(x, 3, 50), -22)
}

function retroBar(bar) {
  var f = nesPitch(PENTATONIC[bar])
  var x = new Float32Array(Math.round(0.113 * RATE))
  var wave = pulseBar(bar), step = f / RATE * TABLE
  var slewK = 1 - Math.exp(-1 / (0.0012 * RATE)), slew = 0, ph = 0
  for (var i = 0; i < x.length; i++) {
    slew += (nesVolume(i / RATE, 9, 12, 0) - slew) * slewK
    ph += step
    if (ph >= TABLE) ph -= TABLE
    var a = ph | 0
    x[i] = slew * (wave[a] + (wave[a + 1] - wave[a]) * (ph - a))
  }
  return levelled(fadeEdges(band(x, 90, 6500), 0.5, 3), -23)
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
