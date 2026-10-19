// Judges frames a harness grabbed (FrameGrab.qml), as rendered pictures,
// not animation properties. Each frame is a binary PPM, laid on the
// window's colour, with the time its picture shows, in ms since the
// harness marked the change that starts the motion. Prints one JSON
// verdict: { ok, detail }.
//
//   bun frames.js drawin[:END[:first]] [plot=PLOT] FRAME@T...
//                                      the chart draws in from the left over
//                                      about 320 ms, across its ink's extent:
//                                      END of the picture's width (1 by
//                                      default), or `ink`, read from the last
//                                      frame's own ink, where a day's newest
//                                      print leaves the hours to come empty;
//                                      its ink read against PLOT, a picture
//                                      of the empty plot; with `first`, a
//                                      surface's first frames, none before
//                                      the mark may show any
//   bun frames.js same[:X,Y,W,H] FRAME@T...
//                                      every frame is the same picture, or
//                                      the same within that rectangle
//   bun frames.js edge BAND FRAME@T...
//                                      the card's bottom edge eases to its
//                                      new place over about 160 ms, and the
//                                      BAND px above it, the footer riding
//                                      it, are the same picture on every
//                                      frame: nothing draws through them
//   bun frames.js edgeheld FRAME@T... every frame that shows the card shows
//                                      its bottom edge where the last does
//   bun frames.js press R,G,B,A X,Y,W,H FRAME@T...
//                                      a control pressed at the mark takes
//                                      the fill R,G,B,A (0 to 1, as Qt
//                                      gives it) over what was under it, in
//                                      the X,Y,W,H box, from the next frame
//                                      on, held there while the button is
//                                      down
//   bun frames.js dim[:DELAY[:X,Y,W,H]] FRAME@T...
//                                      what is on show dims to 0.4 of its
//                                      ink in about 160 ms OutCubic, DELAY
//                                      ms after the mark (250 by default),
//                                      the first picture on every frame till
//                                      then; or, its first frame dimmer than
//                                      its last, comes back whole in about
//                                      160 ms from the mark; within that
//                                      rectangle, if given
//   bun frames.js turn[:0] FRAME@T... the header's animal crossfades to its
//                                      new picture in about 160 ms, or with
//                                      :0 changes at once, never through a
//                                      blank or faint frame
//   bun frames.js columns:LENGTH:N FRAME@T...
//                                      the pill's mark, N columns across the
//                                      picture, turns from the first picture
//                                      to the last left to right, each
//                                      column whole, over about LENGTH ms
//                                      OutCubic, never through a blank or
//                                      faint frame
//   bun frames.js filled:GAP[:X,Y,W,H] FRAME@T...
//                                      every frame shows ink all the way
//                                      down, within that rectangle if
//                                      given: no run of more than GAP
//                                      pixel rows bare, as a row in sight
//                                      drawn empty would leave
//   bun frames.js self-check          wrong pictures fail, a right one passes
//
// A draw-in is read against its own first and last frames: a pixel is ink
// where the last frame differs from the first. A frame's edge is the
// rightmost ink column already showing the last frame's pixel, and every
// ink pixel left of it must show it too, so a slit that runs ahead of
// erased ink is no draw-in. Edges are read as shares of the ink's extent,
// so a day half gone sweeps its half in the whole 320 ms; read from the
// last frame's own ink, a sweep that stops short and shows the rest at the
// end fails. The last frame's ink must reach that extent: a chart cut short
// is not whole. Any ink counts, in either look, the area and the dim hours
// too.
import { readFileSync } from "node:fs"

// P6: magic, width, height, maximum, each after whitespace, then RGB bytes.
function picture(bytes) {
  let pos = 0
  const fields = []
  while (fields.length < 4) {
    while (/\s/.test(String.fromCharCode(bytes[pos]))) pos++
    const start = pos
    while (!/\s/.test(String.fromCharCode(bytes[pos]))) pos++
    fields.push(bytes.toString("latin1", start, pos))
  }
  return { width: Number(fields[1]), height: Number(fields[2]), data: bytes.subarray(pos + 1) }
}

// The picture's ground: its most common colour.
function groundIn(data) {
  const counts = new Map()
  for (let i = 0; i < data.length; i += 3) {
    const key = data.readUIntBE(i, 3)
    counts.set(key, (counts.get(key) || 0) + 1)
  }
  return [...counts].reduce((a, b) => b[1] > a[1] ? b : a)[0]
}

// The part of `image` inside `rect`, "X,Y,W,H" in pixels.
function cropped(image, rect) {
  const [x, y, w, h] = rect.split(",").map(Number)
  const data = Buffer.alloc(w * h * 3)
  for (let row = 0; row < h; row++) {
    const from = ((y + row) * image.width + x) * 3
    image.data.copy(data, row * w * 3, from, from + w * 3)
  }
  return { width: w, height: h, data }
}

// A verdict that the picture changed says when: `changedAt`, the time of
// the first frame that differs from the first; and `blankBefore`, whether
// the frames up to it show nothing but the ground, the last frame's most
// common colour.
function same(frames) {
  if (frames.length < 2) return { ok: false, detail: frames.length + " frames grabbed" }
  const first = frames.findIndex(f => !f.image.data.equals(frames[0].image.data))
  const ground = groundIn(frames[frames.length - 1].image.data)
  const data = frames[0].image.data
  let blankBefore = true
  for (let i = 0; i < data.length && blankBefore; i += 3) blankBefore = data.readUIntBE(i, 3) === ground
  return first < 0 ? { ok: true, detail: frames.length + " frames, all the same picture" }
    : { ok: false, changedAt: frames[first].t, blankBefore,
      detail: "frame " + first + " at " + frames[first].t + " ms differs from the first" + (blankBefore ? ", which is blank" : "") }
}

// How much of the ink of `whole` a picture shows, 0..1: for each pixel of
// `whole` that stands well off the ground, how far the picture's stands from
// the ground against how far whole's does, the median of them all, so a few
// pixels drawn over it (the label naming what is coming) weigh nothing.
// Only pixels at least 64 levels off the ground count, the line, caps, and
// type: a smooth chart's faint wash is most of its pixels, and dimmed to a
// few levels each it rounds to whole levels, which moved the median
// 0.395, 0.421 across the last two frames of a dim whose line read 0.404,
// 0.403. Where nothing stands that far off, any pixel 24 off does.
// The ground is what a dim fades toward: the most common colour among the
// pixels two of its pictures share (`groundUnder`).
function inkShare(image, whole, ground) {
  const g = [ground >> 16, (ground >> 8) & 255, ground & 255]
  const read = least => {
    const shares = []
    for (let i = 0; i < whole.data.length; i += 3) {
      const off = [0, 1, 2].map(c => whole.data[i + c] - g[c])
      const far = off.reduce((a, b) => Math.abs(b) > Math.abs(a) ? b : a)
      if (Math.abs(far) < least) continue
      const c = off.indexOf(far)
      shares.push((image.data[i + c] - g[c]) / far)
    }
    return shares
  }
  let shares = read(64)
  if (shares.length < 50) shares = read(24)
  if (!shares.length) return 1
  shares.sort((a, b) => a - b)
  return shares[Math.floor(shares.length / 2)]
}

function groundUnder(a, b) {
  const counts = new Map()
  for (let i = 0; i < a.data.length; i += 3) {
    if (a.data[i] !== b.data[i] || a.data[i + 1] !== b.data[i + 1] || a.data[i + 2] !== b.data[i + 2]) continue
    const key = a.data.readUIntBE(i, 3)
    counts.set(key, (counts.get(key) || 0) + 1)
  }
  return counts.size ? [...counts].reduce((x, y) => y[1] > x[1] ? y : x)[0] : groundIn(a.data)
}

// What is on show dimming, or coming back. Each frame's share of the ink
// of the picture at full ink, the brighter of the first and last frames
// (`inkShare`). Dimming: until `delay` ms after the mark, short of a
// frame's grace, every frame is the first picture, so a chart that lands
// sooner changes nothing; then an ease to 0.4 of the ink (0.33 to 0.47),
// OutCubic over about 160 ms, read off its own curve as an edge's is
// (∛(1 − p) a straight line in time), starting within a few frames of
// `delay`, through at least three distinct partial frames, never back,
// within a trace of its end once the curve has ended, and from 100 ms
// after that the same picture on every frame: what was held stays still.
// Coming back: the same ease, from about 0.4 to whole, from the mark.
function dim(frames, delay) {
  if (frames.length < 3) return { ok: false, detail: frames.length + " frames grabbed" }
  const first = frames[0].image, last = frames[frames.length - 1].image
  const ground = groundUnder(first, last)
  const lifting = inkShare(first, last, ground) < inkShare(last, first, ground)
  const whole = lifting ? last : first
  const shares = frames.map(f => inkShare(f.image, whole, ground))
  const from = lifting ? shares[0] : 1
  const to = lifting ? 1 : shares[shares.length - 1]
  const at = lifting ? 0 : delay
  const span = to - from
  const progress = s => span ? (s - from) / span : 1
  const early = lifting ? -1 : frames.findIndex(f => f.t >= 0 && f.t < delay - 16 && !f.image.data.equals(first.data))
  const after = frames.map((f, i) => ({ t: f.t, p: progress(shares[i]) })).filter(f => f.t >= (lifting ? 0 : delay - 16))
  // A share is a median of whole pixel steps: under load it reads up to a
  // few hundredths either way of the curve.
  const backwards = after.findIndex((f, i) => i > 0 && f.p < after[i - 1].p - 0.05)
  const partial = after.filter(f => f.p > 0.02 && f.p < 0.98)
  const distinct = new Set(partial.map(f => f.p.toFixed(2))).size
  // A share is read off every pixel, not a column's step: the curve reads
  // to 0.97 of the way, so a busy machine's few frames still draw it.
  const line = partial.filter(f => f.p < 0.97).map(f => ({ t: f.t, y: Math.cbrt(1 - f.p) }))
  const median = values => values.sort((a, b) => a - b)[Math.floor(values.length / 2)]
  const slopes = []
  for (let i = 0; i < line.length; i++)
    for (let j = i + 1; j < line.length; j++)
      if (line[j].t > line[i].t) slopes.push((line[j].y - line[i].y) / (line[j].t - line[i].t))
  const slope = slopes.length ? median(slopes) : 0
  const length = slope < 0 ? -1 / slope : 0
  const start = length ? median(line.map(f => f.t - (1 - f.y) * length)) : 0
  const settled = frames.findIndex((f, i) => frames.slice(i).every(later => later.image.data.equals(last.data)))
  const finish = frames[settled].t
  // Two frames' grace: the curve read off a few frames under load ends a
  // frame or so before the picture rests. Its last hundredths are a level
  // or two of a pixel, which the next frame may still show.
  const tail = after.some(f => f.t > start + length + 32 && Math.abs(f.p - 1) > 0.02)
  const restFrom = start + length + 100
  const resting = frames.filter(f => f.t >= restFrom)
  const rests = resting.length >= 2 && resting.every(f => f.image.data.equals(last.data))
  const level = lifting ? from : to
  const ok = early < 0 && backwards < 0 && distinct >= 3 && line.length >= 3 && length >= 120 && length <= 220
    && start >= at - 24 && start <= at + 40 && !tail && rests && level >= 0.33 && level <= 0.47
  return { ok, detail: (lifting ? "comes back" : "dims") + ": ink " + shares.map(s => s.toFixed(2)).join(" ") + " at " + frames.map(f => f.t).join(" ")
    + " ms | " + distinct + " partial, " + Math.round(length) + " ms from " + Math.round(start) + " ms, at rest at " + finish + " ms, dim at " + level.toFixed(2)
    + (early >= 0 ? ", frame " + early + " (" + frames[early].t + " ms) changed before " + delay + " ms" : "")
    + (line.length < 3 ? ", " + line.length + " frames to read the curve from" : "")
    + (tail ? ", still moving after the curve ended" : "")
    + (!rests ? ", " + (resting.length < 2 ? "too few frames after it" : "not the same picture from " + Math.round(restFrom) + " ms") : "")
    + (backwards >= 0 ? ", went back at " + after[backwards].t + " ms" : "") }
}

// The header's animal turning, from the first frame's picture to the
// last's, both of them an animal: neither may be the bare ground. A turn
// over `length` ms (the crossfade's 160, the eyes' close's 320) leaves the
// first picture within a few frames of the mark, shows the two mixed on
// three or more distinct frames, and rests on the last from about `length`
// on. A change at once (`length` 0) shows the first picture until a few
// frames past the mark and the last from then on, no mix and no way back.
// Neither shows a blank or faint frame: each frame's strongest pixel stands
// at least a third as far from the ground as the fainter picture's does, so
// a fade out and then in, through nothing, fails.
function turn(frames, length) {
  const ends = turnEnds(frames)
  if (ends.detail) return ends
  const { first, last, bare, faint, mixed, distinct, leftAt, restAt, settled, left } = ends
  const ok = !bare && faint < 0 && leftAt <= 50 && (length === 0 ? mixed.length === 0 && settled === left
    : distinct >= 3 && restAt >= length * 0.625 && restAt <= length * 1.5)
  return { ok, detail: describe(ends) }
}

// Retro's eyes closing over `length` ms in whole steps: the first picture
// until about halfway, then one step, the half-shut eyes, on every frame
// until about `length`, then the last; no blank or faint frame.
function steps(frames, length) {
  const ends = turnEnds(frames)
  if (ends.detail) return ends
  const { bare, faint, distinct, leftAt, restAt } = ends
  const ok = !bare && faint < 0 && distinct === 1 && leftAt >= length * 0.35 && leftAt <= length * 0.7
    && restAt >= length * 0.85 && restAt <= length * 1.4
  return { ok, detail: describe(ends) }
}

// The pill's mark turning column by column, `n` columns across the picture
// with a pixel's gap between them. Every frame shows each column whole, as
// the first picture's or the last's, the turned ones (the last's) left of
// the rest, never fewer than the frame before. The count turned keeps to an
// OutCubic step over about `length` ms (0.8 to 1.25 of it) starting at the
// mark, give or take a frame: a column turns once the step passes its
// middle, as the look icon's columns do (Math.round). At least two frames
// show part turned, and none is blank or faint.
function columnTurn(frames, length, n) {
  const ends = turnEnds(frames)
  if (ends.detail) return ends
  const { width, height } = frames[0].image
  const slice = (width + 1) / n
  const column = (data, k) => {
    const parts = []
    for (let y = 0; y < height; y++)
      parts.push(data.subarray((y * width + Math.round(k * slice)) * 3, (y * width + Math.round((k + 1) * slice) - 1) * 3))
    return Buffer.concat(parts)
  }
  const ks = [...Array(n).keys()]
  const before = ks.map(k => column(ends.first, k))
  const after = ks.map(k => column(ends.last, k))
  const still = ks.filter(k => before[k].equals(after[k]))
  const states = frames.map(f => ks.map(k => {
    const c = column(f.image.data, k)
    return c.equals(after[k]) ? "n" : c.equals(before[k]) ? "o" : "x"
  }).join(""))
  const counts = states.map(s => (s.match(/n/g) || []).length)
  const wrong = states.findIndex(s => !/^n*o*$/.test(s))
  const backwards = counts.findIndex((c, i) => i > 0 && c < counts[i - 1])
  const partial = new Set(counts.filter(c => c > 0 && c < n)).size
  // Columns an OutCubic step of `l` ms from `s` has turned by `t`.
  const due = (t, s, l) => ks.filter(k => t - s >= l * (1 - Math.cbrt(1 - (k + 0.5) / n))).length
  // A frame shows the clock's last tick, up to a frame before its time.
  const fits = (s, l) => frames.every((f, i) => counts[i] >= due(f.t - 24, s, l) && counts[i] <= due(f.t + 8, s, l))
  const lengths = []
  for (let l = 100; l <= 400; l += 5)
    for (let s = -8; s <= 32; s += 2) if (fits(s, l)) { lengths.push(l); break }
  const fitted = lengths.filter(l => l >= length * 0.8 && l <= length * 1.25)
  const ok = !ends.bare && ends.faint < 0 && still.length === 0 && wrong < 0 && backwards < 0 && partial >= 2 && fitted.length > 0
  return { ok, detail: "columns " + states.join(" ") + " at " + frames.map(f => f.t).join(" ") + " ms | " + partial + " partial, "
    + (lengths.length ? "fits " + lengths[0] + " to " + lengths[lengths.length - 1] + " ms" : "fits no step of 100 to 400 ms")
    + (ends.bare ? ", the first or last picture is the bare ground" : "")
    + (ends.faint >= 0 && !ends.bare ? ", frame " + ends.faint + " (" + frames[ends.faint].t + " ms) is blank or faint" : "")
    + (still.length ? ", column " + still.join(", ") + " the same in the first and last pictures" : "")
    + (wrong >= 0 ? ", frame " + wrong + " (" + frames[wrong].t + " ms) not turned left to right, column by whole column" : "")
    + (backwards >= 0 ? ", went back at frame " + backwards : "") }
}

function turnEnds(frames) {
  if (frames.length < 2) return { ok: false, detail: frames.length + " frames grabbed" }
  const first = frames[0].image.data
  const last = frames[frames.length - 1].image.data
  if (first.equals(last)) return { ok: false, detail: frames.length + " frames, all the same picture" }
  const ground = groundIn(last)
  const g = [ground >> 16, (ground >> 8) & 255, ground & 255]
  const strength = data => {
    let most = 0
    for (let i = 0; i < data.length; i++) most = Math.max(most, Math.abs(data[i] - g[i % 3]))
    return most
  }
  const ends = Math.min(strength(first), strength(last))
  const mixed = frames.filter(f => !f.image.data.equals(first) && !f.image.data.equals(last))
  const left = frames.findIndex(f => !f.image.data.equals(first))
  const settled = frames.findIndex((f, i) => frames.slice(i).every(later => later.image.data.equals(last)))
  return {
    frames, first, last, bare: ends < 24, faint: frames.findIndex(f => strength(f.image.data) < ends / 3), mixed,
    distinct: new Set(mixed.map(f => f.image.data.toString("base64"))).size,
    left, settled, leftAt: frames[left].t, restAt: frames[settled].t
  }
}

function describe({ frames, bare, faint, distinct, leftAt, restAt }) {
  return "leaves the first picture at " + leftAt + " ms, at rest at " + restAt + " ms, "
    + distinct + " distinct mixed frames"
    + (bare ? ", the first or last picture is the bare ground" : "")
    + (faint >= 0 && !bare ? ", frame " + faint + " (" + frames[faint].t + " ms) is blank or faint" : "")
}

// The draw-in is judged from the frame it started on: what was grabbed
// before that (a chart held while the next one loads) is another run's,
// unless `first`, a surface's first frames: then no frame before the
// draw-in may show its ink, so a chart that flashes whole and then draws
// in fails, and so does one painted part way ahead of its animation that
// stays. Ink is read against `plot`, a picture of the empty plot, the
// chart with its ink hidden, where a harness has one: without it, ink is
// read against the first frame after the draw-in began, and a chart
// already part drawn there reads as starting from nothing. `end` is how
// far along the picture the ink reaches, or "ink" to read it from the last
// frame's own ink, so no painter supplies its own extent.
function drawin(all, end = 1, plot = null, first = false) {
  const frames = all.filter(f => f.t >= 0)
  if (frames.length < 2) return { ok: false, detail: frames.length + " frames grabbed" }
  const { width, height } = frames[0].image
  const empty = plot ? plot.data : frames[0].image.data
  const whole = frames[frames.length - 1].image.data
  const match = (a, b, i) => a[i] === b[i] && a[i + 1] === b[i + 1] && a[i + 2] === b[i + 2]
  const ink = i => !match(whole, empty, i)
  let inkEnd = 0
  for (let i = 0; i < whole.length; i += 3) if (ink(i)) inkEnd = Math.max(inkEnd, (i / 3) % width + 1)
  if (end === "ink") end = Math.max(1, inkEnd) / width
  // The rightmost ink column where `data` already shows the last frame.
  const edgeColumn = data => {
    for (let x = width - 1; x >= 0; x--)
      for (let y = 0; y < height; y++) {
        const i = (y * width + x) * 3
        if (ink(i) && match(data, whole, i)) return x + 1
      }
    return 0
  }
  // The share of the ink left of the edge, short of a column's grace for
  // the clip's own edge, that does not yet show the last frame. A mark that
  // comes only once the chart is whole (the day's dot) is a few pixels of
  // it; a slit that erased what it passed is nearly all.
  const missing = (data, edge) => {
    let behind = 0, n = 0
    for (let x = 0; x < edge - 2; x++)
      for (let y = 0; y < height; y++) {
        const i = (y * width + x) * 3
        if (!ink(i)) continue
        behind++
        if (!match(data, whole, i)) n++
      }
    return behind ? n / behind : 0
  }
  const columns = frames.map(f => edgeColumn(f.image.data))
  const edges = columns.map(c => Math.min(1, c / width / end))
  const last = edges[edges.length - 1]
  const step = 2 / width / end
  const backwards = edges.findIndex((e, i) => i > 0 && e < edges[i - 1] - step)
  const gaps = frames.map((f, i) => missing(f.image.data, columns[i]))
  const gapAt = gaps.findIndex(share => share > 0.05)
  const partial = edges.map((e, i) => ({ e, t: frames[i].t })).filter(f => f.e > 0 && f.e < last - step)
  const distinct = new Set(partial.map(f => f.e.toFixed(3))).size
  // OutCubic over `length` ms from `start`: an edge e at t has
  // ∛(1 − e) = 1 − (t − start) / length, a straight line in time. Its slope
  // gives the length and where it leaves 1 the start, from the pictures and
  // their own times, however late after the mark the motion began and
  // however unevenly the frames came. The median of the slopes between
  // every two frames up to 0.9 of the plot, where a retro column's whole
  // step weighs least, so one odd frame cannot tilt it.
  const line = partial.filter(f => f.e < 0.9).map(f => ({ t: f.t, y: Math.cbrt(1 - f.e) }))
  const median = values => values.sort((a, b) => a - b)[Math.floor(values.length / 2)]
  const slopes = []
  for (let i = 0; i < line.length; i++)
    for (let j = i + 1; j < line.length; j++)
      if (line[j].t > line[i].t) slopes.push((line[j].y - line[i].y) / (line[j].t - line[i].t))
  const slope = slopes.length ? median(slopes) : 0
  const length = slope < 0 ? -1 / slope : 0
  const start = length ? median(line.map(f => f.t - (1 - f.y) * length)) : 0
  // When the line has reached a point of the plot.
  const reaches = e => start + length * (1 - Math.cbrt(1 - Math.min(1, Math.max(0, e))))
  // Whole: the first frame from which every frame is the last picture. Not
  // before the line reaches the ink's right end, short of a retro column (a
  // column shows whole once the clip enters it) and a pixel of the line's
  // smoothing; and nothing still drawing in once the line has ended. The
  // slack is the line's own error, a few ms either way.
  const settled = frames.findIndex((f, i) => frames.slice(i).every(later => later.image.data.equals(whole)))
  const finish = frames[settled].t
  const wholeFrom = reaches((inkEnd - 8) / width / end)
  const slack = 16
  const early = finish < wholeFrom - slack
  const tail = frames.slice(0, settled).filter(f => f.t > start + length + slack).length
  // The motion starts at the left edge as the change is made: its line
  // starts no earlier than the mark, short of its own error (right
  // draw-ins have read up to 10 ms early), so a chart that begins a
  // quarter drawn or more reads as starting 24 ms or more before it, its
  // length right or not; and within a few frames of the mark, counted in
  // frames, which load does not stretch.
  const startsEarly = start < -24
  const lead = frames.filter(f => f.t < start).length
  // Ink before the draw-in began, a share of its extent, on the frame that
  // showed the most: a few columns' grace for the frames' own timing.
  const before = first ? all.filter(f => f.t < 0) : []
  const shownBefore = Math.max(0, ...before.map(f => Math.min(1, edgeColumn(f.image.data) / width / end)))
  const flashed = shownBefore > 0.05
  const ok = last >= 0.95 && backwards < 0 && gapAt < 0 && distinct >= 4 && line.length >= 3
    && length >= 270 && length <= 380 && !early && tail === 0 && !startsEarly && lead <= 4 && !flashed
  // Too few frames to read the motion by: a machine too loaded to render
  // it, not a wrong draw-in. Found under the suite's load: the busy
  // machine's draw-in showed its edge at 0, 0.88, then whole at 364 ms; and
  // pinned to two cores beside the suite its frames came at 0, 93, 139, 191
  // ms, and on one core at 0, 76, 117, 171 ms. A verdict is unreadable only
  // when it failed for want of a curve to read (fewer than three frames on
  // it under 0.9 of the way, or fewer than four distinct), with fewer than
  // three frames in the first 150 ms, where a right one is still short of
  // 0.85, and the frames say nothing either way: some allowed draw-in, 270
  // to 380 ms OutCubic starting within 24 ms before the mark to 32 after,
  // shows every one of them, give or take 10 ms of a frame's time and a
  // column of edge (0.02 behind, 0.06 ahead for retro's whole columns);
  // the chart is not whole before 200 ms, which a right one never is
  // (retro's whole columns were whole from 225 ms); a curve read off three
  // frames or more has its length, start, and end in bounds; and no ink is
  // missing behind the edge, no edge goes back, the ink is not cut short,
  // and none showed before it began. It needs the empty plot: without it a
  // chart that starts part drawn reads as starting from nothing, so a
  // capture judged without one is never unreadable. Frames no allowed
  // draw-in could show, a 160 ms one at 0, 50, 80, 208 ms, contradict the
  // motion and fail as wrong. A harness can film an unreadable draw-in
  // again; it never passes as one.
  const readable = frames.filter(f => f.t > 0 && f.t <= 150).length
  const reach = (t, s, l) => t <= s ? 0 : t - s >= l ? 1 : 1 - Math.pow(1 - (t - s) / l, 3)
  const shows = (s, l) => frames.every((f, i) => edges[i] >= reach(f.t - 10, s, l) - 0.02 && edges[i] <= reach(f.t + 10, s, l) + 0.06)
  let possible = false
  for (let l = 270; l <= 380 && !possible; l += 5)
    for (let s = -24; s <= 32 && !possible; s += 2) possible = shows(s, l)
  const measuredWrong = line.length >= 3
    && (length < 270 || length > 380 || early || tail > 0 || startsEarly || lead > 4)
  const unreadable = !!plot && !ok && (line.length < 3 || distinct < 4) && readable < 3 && possible && !measuredWrong
    && finish >= 200 && last >= 0.95 && backwards < 0 && gapAt < 0 && !flashed
  // `inkEnd`: where the last frame's ink ends, a share of the picture's
  // width, for a harness to hold against the data's newest print.
  return { ok, unreadable, inkEnd: inkEnd / width, detail: "edge " + edges.map(e => e.toFixed(2)).join(" ") + " at " + frames.map(f => f.t).join(" ") + " ms | " + distinct + " partial, "
    + Math.round(length) + " ms from " + Math.round(start) + " ms (" + lead + (lead === 1 ? " frame" : " frames") + " after the mark), whole at "
    + finish + " ms, from " + Math.round(wholeFrom) + " ms"
    + (unreadable ? ", " + readable + (readable === 1 ? " frame" : " frames") + " in its first 150 ms, too few to read the motion by" : "")
    + (flashed ? ", " + shownBefore.toFixed(2) + " of its ink shown before the draw-in began" : "")
    + (!ok && !unreadable && !possible && readable < 3 ? ", frames no allowed draw-in shows" : "")
    + (last < 0.95 ? ", the ink ends at " + last.toFixed(2) + " of its extent" : "")
    + (line.length < 3 ? ", " + line.length + " frames to read the curve from" : "")
    + (early ? ", whole before the curve reached the ink's end" : "")
    + (tail ? ", " + tail + " frames still drawing in after the curve ended" : "")
    + (startsEarly ? ", the curve starts before the mark: the chart began part drawn" : "")
    + (backwards >= 0 ? ", went back at frame " + backwards : "")
    + (gapAt >= 0 ? ", " + Math.round(gaps[gapAt] * 100) + "% of the ink behind the edge missing at frame " + gapAt : "") }
}

// The card's bottom edge: one past the lowest row that is not the ground,
// the colour of the picture's bottom-left pixel, which the card never
// reaches. 0 when no card shows.
function edgeRow(image, ground) {
  const { width, height, data } = image
  for (let y = height - 1; y >= 0; y--)
    for (let x = 0; x < width; x++)
      if (data.readUIntBE((y * width + x) * 3, 3) !== ground) return y + 1
  return 0
}

function groundOf(image) {
  return image.data.readUIntBE((image.height - 1) * image.width * 3, 3)
}

// The `band` rows above `edge`, as bytes.
function bandAt(image, edge, band) {
  const row = image.width * 3
  return image.data.subarray(Math.max(0, edge - band) * row, edge * row)
}

// The edge eases from where it was to its new place in OutCubic over about
// 160 ms, read from its own curve the way a draw-in is (∛(1 − p) is a
// straight line in time), and from the mark on every frame's `band` rows
// above its edge are the last frame's: the footer rides the edge whole, and
// no row shows through it as it passes. Before the mark the footer may say
// something else (another list's name).
function edge(all, band) {
  if (all.length < 2) return { ok: false, detail: all.length + " frames grabbed" }
  const ground = groundOf(all[all.length - 1].image)
  const edges = all.map(f => edgeRow(f.image, ground))
  const to = edges[edges.length - 1]
  const lastBand = bandAt(all[all.length - 1].image, to, band)
  const through = all.findIndex((f, i) => f.t >= 0 && edges[i] > 0 && !bandAt(f.image, edges[i], band).equals(lastBand))
  const frames = all.map((f, i) => ({ t: f.t, e: edges[i] })).filter(f => f.t >= 0 && f.e > 0)
  if (frames.length < 2) return { ok: false, detail: frames.length + " frames with the card after the mark" }
  // The travel starts where the card stood before the mark, so a jump at
  // the mark is part of the curve, and reads as a start before it.
  const before = all.map((f, i) => ({ t: f.t, e: edges[i] })).filter(f => f.t < 0 && f.e > 0)
  const from = before.length ? before[before.length - 1].e : frames[0].e
  const span = to - from
  const progress = e => span ? (e - from) / span : 1
  const backwards = frames.findIndex((f, i) => i > 0 && progress(f.e) < progress(frames[i - 1].e))
  const partial = frames.filter(f => f.e !== from && f.e !== to)
  const distinct = new Set(partial.map(f => f.e)).size
  const line = partial.filter(f => progress(f.e) < 0.9).map(f => ({ t: f.t, y: Math.cbrt(1 - progress(f.e)) }))
  const median = values => values.sort((a, b) => a - b)[Math.floor(values.length / 2)]
  const slopes = []
  for (let i = 0; i < line.length; i++)
    for (let j = i + 1; j < line.length; j++)
      if (line[j].t > line[i].t) slopes.push((line[j].y - line[i].y) / (line[j].t - line[i].t))
  const slope = slopes.length ? median(slopes) : 0
  const length = slope < 0 ? -1 / slope : 0
  const start = length ? median(line.map(f => f.t - (1 - f.y) * length)) : 0
  const settled = frames.findIndex((f, i) => frames.slice(i).every(later => later.e === to))
  const finish = frames[settled].t
  // Whole within a pixel of the curve's end, short of its own error. A
  // span of a few rows reads its curve from few pixels: real 160 ms eases
  // have read 130 to 204 ms, starting up to 23 ms before the mark, so 100
  // and 240 ms read as wrong and 160 never does, and a jump of 60% at the
  // mark reads as a start 50 ms before it. A jump of a quarter or less
  // reads within that error.
  const slack = 16
  const tail = finish > start + length + slack
  const lead = frames.filter(f => f.t < start).length
  const ok = span !== 0 && through < 0 && backwards < 0 && distinct >= 3 && line.length >= 3
    && length >= 120 && length <= 220 && !tail && start >= -32 && lead <= 4
  return { ok, detail: "edge " + frames.map(f => f.e).join(" ") + " | " + distinct + " partial, "
    + Math.round(length) + " ms from " + Math.round(start) + " ms (" + lead + (lead === 1 ? " frame" : " frames")
    + " after the mark), at rest at " + finish + " ms"
    + (span === 0 ? ", the edge never moved" : "")
    + (line.length < 3 ? ", " + line.length + " frames to read the curve from" : "")
    + (tail ? ", still moving after the curve ended" : "")
    + (backwards >= 0 ? ", went back at frame " + backwards : "")
    + (through >= 0 ? ", the " + band + " px above the edge differ from the footer at rest at frame " + through
      + " (" + all[through].t + " ms)" : "") }
}

// An open from closed: every frame that shows the card shows its edge where
// the last one does.
function edgeheld(frames) {
  const ground = groundOf(frames[frames.length - 1].image)
  const edges = frames.map(f => edgeRow(f.image, ground)).filter(e => e > 0)
  const to = edges[edges.length - 1]
  const moved = edges.findIndex(e => e !== to)
  return { ok: edges.length >= 2 && moved < 0, detail: "edge " + edges.join(" ")
    + (edges.length < 2 ? ", " + edges.length + " frames show the card" : "")
    + (moved >= 0 ? ", frame " + moved + " shows it at " + edges[moved] + ", not " + to : "") }
}

// The most common colour inside a box of the picture, as [r, g, b].
function colourIn(image, [x0, y0, w, h]) {
  const counts = new Map()
  for (let y = y0; y < y0 + h; y++)
    for (let x = x0; x < x0 + w; x++) {
      const key = image.data.readUIntBE((y * image.width + x) * 3, 3)
      counts.set(key, (counts.get(key) || 0) + 1)
    }
  const key = [...counts].reduce((a, b) => b[1] > a[1] ? b : a)[0]
  return [key >> 16, (key >> 8) & 255, key & 255]
}

const apart = (a, b) => Math.max(...a.map((v, i) => Math.abs(v - b[i])))

// A press, as the shell's buttons answer one: the box's colour before the
// mark is what lies under the control, and every frame from 20 ms on shows
// something else (the first of them by 50 ms), a fill on its way; from
// 240 ms on, the fill laid over that ground, within rounding. A fill that
// waits for the release, or a hover's fainter fill, fails.
function press(frames, fill, box) {
  const before = frames.filter(f => f.t < 0)
  const after = frames.filter(f => f.t >= 20)
  const at = f => f.t + " ms " + colourIn(f.image, box).join(",")
  if (!before.length || !after.length || after[after.length - 1].t < 240)
    return { ok: false, detail: before.length + " frames before the press, the last at " + (frames.length ? frames[frames.length - 1].t : "-") + " ms" }
  const ground = colourIn(before[before.length - 1].image, box)
  const wants = ground.map((g, i) => Math.round(g * (1 - fill[3]) + fill[i] * 255 * fill[3]))
  const still = after.find(f => apart(colourIn(f.image, box), ground) <= 2)
  const wrong = after.filter(f => f.t >= 240).find(f => apart(colourIn(f.image, box), wants) > 3)
  const problem = after[0].t > 50 ? "no frame from 20 to 50 ms"
    : still ? "the ground's colour still at " + at(still)
    : wrong ? "not the pressed fill at " + at(wrong) : ""
  return { ok: problem === "", detail: "ground " + ground.join(",") + ", the pressed fill over it " + wants.join(",")
    + (problem ? ": " + problem : ", from " + at(after[0]) + " to " + at(after[after.length - 1])) }
}

// Draw-ins drawn here, frame by frame, as a harness would grab them: a line
// and the area under it across a 120 × 20 plot. `shown(x, t)` says whether
// column x shows its ink t ms after the mark. Frames come every 16 ms, or
// at the gaps `uneven` steps through, as a busy machine draws them.
function synthetic(shown, until = 480, uneven = null) {
  const width = 120, height = 20
  const frames = []
  for (let t = 0, k = 0; t <= until; t += uneven ? uneven[k++ % uneven.length] : 16) {
    const data = Buffer.alloc(width * height * 3, 16)
    for (let x = 0; x < width; x++) {
      if (!shown(x / width, t)) continue
      const top = 6 + Math.round(5 * Math.sin(x / 9))
      for (let y = top; y < height; y++) data.fill(y === top ? 220 : 80, (y * width + x) * 3, (y * width + x) * 3 + 3)
    }
    frames.push({ t, image: { width, height, data } })
  }
  return frames
}

// A card drawn here, frame by frame: its ground from the top to its edge,
// `edgeAt(t)`, on a 60 × 120 picture, the rows laid out to row 90 at once,
// and a 14 px footer on the edge, painted in the card's ground when it
// `covers`, else drawn over whatever is under it. Frames start 48 ms before
// the mark, as a harness grabs the card at rest first.
function cardFrames(edgeAt, covers = true, until = 360, uneven = null) {
  const width = 60, height = 120, band = 14
  const frames = []
  for (let t = -48, k = 0; t <= until; t += uneven ? uneven[k++ % uneven.length] : 16) {
    const data = Buffer.alloc(width * height * 3, 16)
    const e = Math.round(edgeAt(t))
    for (let y = 0; y < e; y++)
      for (let x = 0; x < width; x++) {
        const footer = y >= e - band
        const row = y < 90 && y % 10 < 3 && !(footer && covers)
        const word = footer && y >= e - 8 && y < e - 5 && x >= 20 && x < 40
        data.fill(word ? 230 : row ? 200 : 40, (y * width + x) * 3, (y * width + x) * 3 + 3)
      }
    frames.push({ t, image: { width, height, data } })
  }
  return frames
}

function selfCheck() {
  // OutCubic over `length` ms, starting `from` ms after the mark.
  const outCubic = (t, length, from = 0) => t < from ? 0 : t - from >= length ? 1 : 1 - Math.pow(1 - (t - from) / length, 3)
  // Retro's whole columns, 6 px of the 120: a column shows once the clip enters it.
  const columns = e => Math.ceil(20 * e) / 20
  const busy = [12, 41, 9, 27, 50, 14, 33, 18]
  const cases = [
    ["320 ms draw-in", true, (x, t) => x < outCubic(t, 320)],
    ["320 ms, frames 9 to 50 ms apart, starting 20 ms after the mark", true, (x, t) => x < outCubic(t, 320, 20), 520, busy],
    ["320 ms in whole columns, whole from about 200 ms", true, (x, t) => x < columns(outCubic(t, 320))],
    ["0 ms", false, (x, t) => t > 0],
    ["160 ms draw-in", false, (x, t) => x < outCubic(t, 160)],
    ["160 ms, frames 9 to 50 ms apart", false, (x, t) => x < outCubic(t, 160), 480, busy],
    ["ink hidden until the end", false, (x, t) => t >= 320],
    ["a slit erasing what it passed", false, (x, t) => t >= 320 || Math.abs(x - outCubic(t, 320)) < 0.02],
    ["cut short at 80%", false, (x, t) => x < Math.min(0.8, outCubic(t, 320))],
    ["400 ms draw-in", false, (x, t) => x < outCubic(t, 400), 560],
    ["400 ms, frames 9 to 50 ms apart", false, (x, t) => x < outCubic(t, 400), 640, busy],
    ["320 ms, starting 200 ms after the mark", false, (x, t) => x < outCubic(t, 320, 200), 680],
    ["whole at once 150 ms in", false, (x, t) => x < (t >= 150 ? 1 : outCubic(t, 320))],
    ["its last tenth 200 ms after the rest", false, (x, t) => x < (x < 0.9 ? outCubic(t, 320) : outCubic(t, 320, 200)), 680],
    ["a quarter drawn at once, the rest as if 320 ms all along", false, (x, t) => x < 0.25 + 0.75 * outCubic(t, 291)],
    ["60% drawn at once, the rest in 224 ms", false, (x, t) => x < 0.6 + 0.4 * outCubic(t, 224)],
    ["60% drawn at once, the rest in 224 ms, frames 9 to 50 ms apart", false, (x, t) => x < 0.6 + 0.4 * outCubic(t, 224), 480, busy],
    // A day half gone: its ink ends at 50% of the plot, the rest to come,
    // the extent read from the last frame's ink.
    ["a half day swept to its newest print in 320 ms", true, (x, t) => x < 0.5 && x < 0.5 * outCubic(t, 320), 480, null, "ink"],
    ["a half day swept to its newest print in 320 ms in whole columns", true, (x, t) => x < 0.5 && x < columns(0.5 * outCubic(t, 320)), 480, null, "ink"],
    ["a half day swept across the whole plot in 320 ms, its ink whole in 66 ms", false, (x, t) => x < 0.5 && x < outCubic(t, 320), 480, null, "ink"],
    ["a half day swept to 45% in 320 ms, the rest shown at its end", false, (x, t) => x < 0.5 && (t >= 320 || x < 0.45 * outCubic(t, 320)), 480, null, "ink"],
    ["a half day cut short at 30%", false, (x, t) => x < 0.3 && x < 0.5 * outCubic(t, 320), 480, null, 0.5],
  ]
  let failed = 0
  for (const [name, expected, shown, until, uneven, end] of cases) {
    const verdict = drawin(synthetic(shown, until, uneven), end)
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + name + (expected ? " passes" : " fails") + " — " + verdict.detail.replace(/^edge [^|]*\| /, ""))
  }
  // Too few frames to read is no verdict on the draw-in: a right one on
  // frames that skip its first 150 ms fails as unreadable, and a wrong one
  // on frames that come fails as wrong.
  const stalled = [162, 103, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16]
  // The frames busy runs gave pinned to two cores beside the suite, and to one.
  const pinned = [93, 46, 52, 70, 27, 13, 8, 25, 8, 17, 15, 24, 12, 21, 14]
  const oneCore = [76, 41, 54, 68, 25, 14, 10, 15, 17, 22, 17, 12, 22, 14, 10, 15]
  const sparse = [
    ["320 ms, on a busy run's frames on one core, 0, 76, 117, 171 ms", (x, t) => x < outCubic(t, 320), oneCore, true],
    ["320 ms, its frames stalled 162 ms after the mark", (x, t) => x < outCubic(t, 320), stalled, true],
    ["320 ms, on a pinned busy run's frames, 0, 93, 139, 191 ms", (x, t) => x < outCubic(t, 320), pinned, true],
    ["none, on even frames", (x, t) => t > 0, null, false],
    ["160 ms, on even frames", (x, t) => x < outCubic(t, 160), null, false],
    ["160 ms, on a busy machine's frames, 9 to 50 ms apart", (x, t) => x < outCubic(t, 160), busy, false],
    ["ink hidden until the end, on even frames", (x, t) => t >= 320, null, false],
    // Wrong on sparse frames, and plainly so: read, not retried.
    ["400 ms, on a pinned busy run's frames", (x, t) => x < outCubic(t, 400), pinned, false],
    ["a slit erasing what it passed, on a pinned busy run's frames", (x, t) => t >= 320 || Math.abs(x - outCubic(t, 320)) < 0.02, pinned, false],
    ["cut short at 80%, on a pinned busy run's frames", (x, t) => x < Math.min(0.8, outCubic(t, 320)), pinned, false],
    ["none, its frames stalled 162 ms after the mark", (x, t) => t > 0, stalled, false],
    ["160 ms, its frames stalled 162 ms after the mark", (x, t) => x < outCubic(t, 160), stalled, false],
    ["400 ms, its frames stalled after the third partial, 0, 93, 139, 191, 400 ms", (x, t) => x < outCubic(t, 400), [93, 46, 52, 209, 16, 16, 16, 16], false],
    // Two partial frames that already contradict every allowed draw-in:
    // too fast, too slow.
    ["160 ms, on frames at 0, 50, 80, 208 ms", (x, t) => x < outCubic(t, 160), [50, 30, 128, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16], false],
    ["600 ms, on frames at 0, 93, 139, 560 ms", (x, t) => x < outCubic(t, 600), [93, 46, 421, 16, 16, 16, 16, 16], false, 680],
    // Within a frame's error of an allowed 380 ms one: it says nothing.
    ["400 ms, on frames at 0, 93, 139, 400 ms", (x, t) => x < outCubic(t, 400), [93, 46, 261, 16, 16, 16, 16, 16], true],
    // A busy run that starts 60% drawn, on frames at 0, 93, 139, 400 ms:
    // read against the empty plot its first frame is 0.60 drawn, and judged
    // without one, as the busy run once was, it is never unreadable.
    ["one starting 60% drawn, on frames at 0, 93, 139, 400 ms", (x, t) => x < 0.6 + 0.4 * outCubic(t, 320), [93, 46, 261, 16, 16, 16, 16, 16], false],
    ["one starting 60% drawn, on frames at 0, 93, 139, 400 ms, judged without the empty plot", (x, t) => x < 0.6 + 0.4 * outCubic(t, 320), [93, 46, 261, 16, 16, 16, 16, 16], false, 480, false],
  ]
  const blankPlot = synthetic(() => false, 0)[0].image
  for (const [name, shown, uneven, unreadable, until = 480, withPlot = true] of sparse) {
    const verdict = drawin(synthetic(shown, until, uneven), 1, withPlot ? blankPlot : null)
    const right = !verdict.ok && !!verdict.unreadable === unreadable
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + name + " fails " + (unreadable ? "as too few frames to read" : "as wrong, not as too few frames")
      + " — " + verdict.detail.replace(/^edge [^|]*\| /, ""))
  }
  // A surface's first frames, ink read against its empty plot: any before
  // its draw-in began fails, so a chart that flashes whole, clears, and
  // then draws in is caught, and so is one painted 60% ahead of its
  // animation that sweeps on from there; frames before it that show
  // nothing pass; and before another run's draw-in, not a first, a held
  // chart is that run's own.
  const rightIn = synthetic((x, t) => x < outCubic(t, 320))
  const emptyPlot = rightIn[0].image
  const flash = [{ t: -64, image: rightIn[rightIn.length - 1].image }].concat(rightIn)
  const blankFirst = [{ t: -32, image: emptyPlot }].concat(rightIn)
  const sixtyAhead = synthetic(x => x < 0.6, 0)[0].image
  const ahead = [-128, -112, -96, -80, -64, -48, -32, -16].map(t => ({ t, image: sixtyAhead }))
    .concat(synthetic((x, t) => x < Math.max(0.6, outCubic(t, 320))))
  const firstCases = [
    ["a chart whole before its draw-in began, cleared, then drawn in, on a first open", false, flash, emptyPlot, true],
    ["a chart painted 60% ahead of its animation, then sweeping on from there, on a first open", false, ahead, emptyPlot, true],
    ["a blank frame before its draw-in began, on a first open", true, blankFirst, emptyPlot, true],
    ["a whole chart before another run's draw-in, held while it loaded", true, flash, emptyPlot, false],
  ]
  for (const [name, expected, frames, plot, first] of firstCases) {
    const verdict = drawin(frames, 1, plot, first)
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + name + (expected ? " passes" : " fails") + " — " + verdict.detail.replace(/^edge [^|]*\| /, ""))
  }
  const sameRight = same(synthetic(() => true, 100)).ok && !same(synthetic((x, t) => x < outCubic(t, 320), 100)).ok
  if (!sameRight) failed++
  console.log((sameRight ? "PASS " : "FAIL ") + "a still picture is the same on every frame, a moving one is not")
  const changedRight = synthetic((x, t) => x >= 0.9 && t > 50, 100)
  const crop = rect => same(changedRight.map(f => ({ ...f, image: cropped(f.image, rect) })))
  const cropRight = crop("0,0,100,20").ok && !crop("100,0,20,20").ok
  if (!cropRight) failed++
  console.log((cropRight ? "PASS " : "FAIL ") + "a crop is the same while only what is outside it changes, and not when what is inside does")
  // The card's edge, from 60 to 100 px or back.
  const ease = (t, length, from = 0) => 60 + 40 * outCubic(t, length, from)
  const edgeCases = [
    ["grows in 160 ms, the footer covering the rows", true, t => ease(t, 160)],
    ["shrinks in 160 ms", true, t => 160 - ease(t, 160)],
    ["grows in 160 ms, frames 9 to 50 ms apart", true, t => ease(t, 160), true, 480, busy],
    ["grows in 160 ms, the rows drawn through the footer", false, t => ease(t, 160), false],
    ["jumps in one frame", false, t => t > 0 ? 100 : 60],
    ["never moves", false, t => 60],
    ["grows in 100 ms", false, t => ease(t, 100)],
    ["grows in 240 ms", false, t => ease(t, 240), true, 480],
    ["grows in 400 ms", false, t => ease(t, 400), true, 560],
    ["grows in 160 ms, starting 200 ms after the mark", false, t => ease(t, 160, 200), true, 560],
    ["jumps 60% at the mark, then eases the rest in 160 ms", false, t => t < 0 ? 60 : 84 + 16 * outCubic(t, 160)],
  ]
  for (const [name, expected, edgeAt, covers, until, uneven] of edgeCases) {
    const verdict = edge(cardFrames(edgeAt, covers, until, uneven), 14)
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + name + (expected ? " passes" : " fails") + " — " + verdict.detail.replace(/^edge [^|]*\| /, ""))
  }
  const heldRight = edgeheld(cardFrames(() => 100)).ok && !edgeheld(cardFrames(t => ease(t, 160))).ok
  if (!heldRight) failed++
  console.log((heldRight ? "PASS " : "FAIL ") + "an open held at its height passes, one that grows fails")
  // What is on show dimming: the draw-in's whole picture laid over its
  // ground at `share(t)` of its ink, with a label in the foreground at the
  // dim's own progress, `label(t)`, over its middle.
  const dimFrames = (share, label, until = 720, uneven = null, from = -48) => {
    const whole = synthetic(() => true, 0)[0].image
    const frames = []
    for (let t = from, k = 0; t <= until; t += uneven ? uneven[k++ % uneven.length] : 16) {
      const s = share(t), l = label(t)
      const data = Buffer.from(whole.data.map(v => Math.round(16 + (v - 16) * s)))
      for (let x = 50; x < 70; x += 2) data.fill(Math.round(16 + 214 * l), (10 * whole.width + x) * 3, (10 * whole.width + x) * 3 + 3)
      frames.push({ t, image: { width: whole.width, height: whole.height, data } })
    }
    return frames
  }
  const dimming = (length, at = 250, to = 0.4) => t => 1 - (1 - to) * outCubic(t, length, at)
  const shown = (length, at = 250) => t => outCubic(t, length, at)
  const lifting = length => t => t < 0 ? 0.4 : 0.4 + 0.6 * outCubic(t, length)
  const dimCases = [
    ["dims to 0.4 over 160 ms from 250 ms", true, dimming(160), shown(160)],
    ["dims over 160 ms from 250 ms, frames 9 to 50 ms apart", true, dimming(160), shown(160), 800, busy],
    ["dims at once at 250 ms", false, dimming(0), shown(0)],
    ["dims over 400 ms", false, dimming(400), shown(400), 900],
    ["dims over 160 ms from the mark", false, dimming(160, 0), shown(160, 0)],
    ["dims over 160 ms from 600 ms", false, dimming(160, 600), shown(160, 600), 1000],
    ["never dims, the label alone showing", false, t => 1, shown(160)],
    ["dims only to 0.8", false, dimming(160, 250, 0.8), shown(160)],
    ["comes back over 160 ms from the mark", true, lifting(160), t => 0, 360, null, 0],
    ["comes back at once", false, lifting(0), t => 0, 360, null, 0],
    ["comes back over 400 ms", false, lifting(400), t => 0, 560, null, 0],
    ["dims over 160 ms, then a mark on it goes on moving", false, dimming(160), t => t < 450 ? shown(160)(t) : 0.5 + 0.5 * Math.sin(t / 40)],
  ]
  for (const [name, expected, share, label, until, uneven, from] of dimCases) {
    const verdict = dim(dimFrames(share, label, until, uneven, from).filter(f => f.t >= 0), 250)
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + "what is on show " + name + (expected ? " passes" : " fails") + " — " + verdict.detail.replace(/^[a-z ]+: ink [^|]*\| /, ""))
  }
  // The animal: a bull-like picture A turning into a bear-like B, each
  // layer at its own opacity over the ground, as the header draws them.
  const animal = (alphas, until = 400, uneven = null) => {
    const width = 40, height = 28
    const frames = []
    for (let t = -48, k = 0; t <= until; t += uneven ? uneven[k++ % uneven.length] : 16) {
      const [a, b] = alphas(t)
      const data = Buffer.alloc(width * height * 3)
      for (let p = 0; p < width * height; p++) {
        const x = p % width, y = Math.floor(p / width)
        let c = [16, 18, 21]
        if (y >= 4 && y < 14 && x >= 6 && x < 34 && (x + y) % 3 === 0) c = c.map((v, i) => v * (1 - a) + [120, 200, 100][i] * a)
        if (y >= 12 && y < 24 && x >= 4 && x < 36 && (x * y) % 4 === 1) c = c.map((v, i) => v * (1 - b) + [220, 90, 110][i] * b)
        data.set(c.map(Math.round), p * 3)
      }
      frames.push({ t, image: { width, height, data } })
    }
    return frames
  }
  const fade = (t, length, from = 0) => { const p = outCubic(t, length, from); return [1 - p, p] }
  const turnCases = [
    ["crossfades in 160 ms", true, false, t => fade(t, 160)],
    ["crossfades in 160 ms, frames 9 to 50 ms apart", true, false, t => fade(t, 160), 480, busy],
    ["changes at once, judged as a turn", false, false, t => t >= 0 ? [0, 1] : [1, 0]],
    ["crossfades in 60 ms", false, false, t => fade(t, 60)],
    ["crossfades in 320 ms", false, false, t => fade(t, 320), 560],
    ["crossfades in 160 ms, starting 200 ms after the mark", false, false, t => fade(t, 160, 200), 560],
    ["fades out in 160 ms, then in", false, false, t => [1 - outCubic(t, 160), outCubic(t, 160, 160)], 560],
    ["changes at once", true, true, t => t >= 0 ? [0, 1] : [1, 0]],
    ["changes at once through a blank frame", false, true, t => t < 0 ? [1, 0] : t < 16 ? [0, 0] : [0, 1]],
    ["crossfades in 160 ms, judged as at once", false, true, t => fade(t, 160)],
    ["fades away for good in 160 ms, nothing taking its place", false, false, t => [1 - outCubic(t, 160), 0]],
    ["changes at once 320 ms after the mark", false, true, t => t >= 320 ? [0, 1] : [1, 0], 480],
    ["changes at once, back at 160 ms, and again at 240", false, true, t => t >= 0 && (t < 160 || t >= 240) ? [0, 1] : [1, 0], 400],
  ]
  for (const [name, expected, atOnce, alphas, until, uneven] of turnCases) {
    const verdict = turn(animal(alphas, until, uneven), atOnce ? 0 : 160)
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + "the animal " + name + (expected ? " passes" : " fails") + " — " + verdict.detail)
  }
  // The eyes' close: smooth's over 320 ms, retro's in two steps.
  const halfway = (t, at) => t < at ? [1, 0] : t < 320 ? [0.5, 0.5] : [0, 1]
  const closeCases = [
    ["eyes close in 320 ms", true, turn, t => fade(t, 320)],
    ["eyes close in 160 ms, judged as 320", false, turn, t => fade(t, 160)],
    ["eyes close in 640 ms, judged as 320", false, turn, t => fade(t, 640), 800],
    ["eyes step half shut at 160 ms and shut at 320", true, steps, t => halfway(t, 160)],
    ["eyes shut at once, judged as steps", false, steps, t => t >= 0 ? [0, 1] : [1, 0]],
    ["eyes close smoothly, judged as steps", false, steps, t => fade(t, 320)],
    ["eyes step half shut at the mark and shut at 320", false, steps, t => halfway(t, 0)],
  ]
  for (const [name, expected, judge, alphas, until] of closeCases) {
    const verdict = judge(animal(alphas, until || 560), 320)
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + "the animal's " + name + (expected ? " passes" : " fails") + " — " + verdict.detail)
  }
  // A control 30 × 12 on a dark ground, its word in light ink, its fill
  // laid over the ground at `share(t)` of the pressed fill's alpha.
  const pressFill = [0.9, 0.9, 0.9, 0.22]
  const control = (share, until = 360, uneven = null) => {
    const width = 30, height = 12
    const frames = []
    for (let t = -48, k = 0; t <= until; t += uneven ? uneven[k++ % uneven.length] : 16) {
      const a = pressFill[3] * share(t)
      const data = Buffer.alloc(width * height * 3)
      for (let p = 0; p < width * height; p++) {
        const x = p % width, y = Math.floor(p / width)
        const word = y >= 4 && y < 8 && x >= 10 && x < 20 && (x + y) % 2 === 0
        data.set(word ? [210, 210, 210] : [20, 22, 26].map((g, i) => Math.round(g * (1 - a) + pressFill[i] * 255 * a)), p * 3)
      }
      frames.push({ t, image: { width, height, data } })
    }
    return frames
  }
  const pressCases = [
    ["eases to the pressed fill in 160 ms", true, t => outCubic(t, 160)],
    ["takes the pressed fill at once", true, t => t >= 0 ? 1 : 0],
    ["eases in 160 ms, frames 9 to 50 ms apart", true, t => outCubic(t, 160), 480, busy],
    ["waits for a release 400 ms in", false, t => t >= 400 ? 1 : 0, 480],
    ["settles on the hover's fill", false, t => outCubic(t, 160) * 0.08 / 0.22],
    ["starts 100 ms late", false, t => outCubic(t, 160, 100)],
    ["lets go while still held", false, t => t >= 0 && t < 200 ? 1 : 0],
  ]
  for (const [name, expected, share, until, uneven] of pressCases) {
    const verdict = press(control(share, until, uneven), pressFill, [0, 0, 30, 12])
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + "a press that " + name + (expected ? " passes" : " fails") + " — " + verdict.detail)
  }
  // A column of rows 40 px apart, each with two 8 px lines of text, as a
  // list scrolls by `scroll(t)` px; `bare(t)` names a row drawn empty.
  const column = (scroll, bare = () => -1) => {
    const width = 20, height = 200
    const frames = []
    for (let t = -48; t <= 360; t += 16) {
      const data = Buffer.alloc(width * height * 3)
      for (let y = 0; y < height; y++) {
        const at = y + scroll(t)
        const row = Math.floor(at / 40), inRow = at % 40
        const text = row !== bare(t) && ((inRow >= 4 && inRow < 12) || (inRow >= 26 && inRow < 34))
        for (let x = 0; x < width; x++) data.set(text && x % 3 ? [220, 220, 220] : [20, 22, 26], (y * width + x) * 3)
      }
      frames.push({ t, image: { width, height, data } })
    }
    return frames
  }
  const fillCases = [
    ["scrolls with every row drawn", true, t => Math.max(0, t) * 20],
    ["leaves a row empty for a frame", false, t => Math.max(0, t) * 20, t => t === 112 ? Math.floor((112 * 20 + 100) / 40) : -1],
  ]
  for (const [name, expected, scroll, bare] of fillCases) {
    const verdict = filled(column(scroll, bare), 24)
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + "a list that " + name + (expected ? " passes" : " fails") + " — " + verdict.detail)
  }
  // The pill's mark, five columns of 2 px a pixel apart, each a cap and a
  // stem down to the floor, turning from falling in red to climbing in
  // green: `turned(t)` columns from the left, or `pick(k, t)` per column.
  const markTurn = (turned, until = 360, uneven = null, pick = null) => {
    const width = 14, height = 11
    const climbs = [3, 1, 2, 1, 0], falls = [0, 1, 2, 1, 3]
    const frames = []
    for (let t = -48, k = 0; t <= until; t += uneven ? uneven[k++ % uneven.length] : 16) {
      const data = Buffer.alloc(width * height * 3, 20)
      for (let c = 0; c < 5; c++) {
        const way = pick ? pick(c, t) : c < turned(t) ? "new" : "old"
        if (way === "blank") continue
        // "half": the new colour on the old shape.
        const level = (way === "new" ? climbs[c] : falls[c]) * 3
        const ink = way === "old" ? [247, 118, 142] : [158, 206, 106]
        for (let y = level; y < height; y++)
          for (let x = c * 3; x < c * 3 + 2; x++) data.set(ink, (y * width + x) * 3)
      }
      frames.push({ t, image: { width, height, data } })
    }
    return frames
  }
  const stepped = (length, from = 0) => t => Math.round(outCubic(t, length, from) * 5)
  const markCases = [
    ["turns left to right in 200 ms", true, stepped(200)],
    ["turns in 200 ms, frames 9 to 50 ms apart", true, stepped(200), 480, busy],
    ["turns at once", false, t => t >= 0 ? 5 : 0],
    ["turns in 400 ms", false, stepped(400), 560],
    ["turns in 100 ms", false, stepped(100)],
    ["turns right to left in 200 ms", false, null, 360, null, (c, t) => 4 - c < stepped(200)(t) ? "new" : "old"],
    ["turns through a blank frame", false, null, 360, null, (c, t) => t === 32 ? "blank" : c < stepped(200)(t) ? "new" : "old"],
    ["takes its new colour before its new shape", false, null, 360, null, (c, t) => c < stepped(200)(t) ? "new" : t >= 0 ? "half" : "old"],
  ]
  for (const [name, expected, turned, until, uneven, pick] of markCases) {
    const verdict = columnTurn(markTurn(turned, until, uneven, pick), 200, 5)
    const right = verdict.ok === expected
    if (!right) failed++
    console.log((right ? "PASS " : "FAIL ") + "a mark that " + name + (expected ? " passes" : " fails") + " — " + verdict.detail.replace(/^columns [^|]*\| /, ""))
  }
  process.exit(failed ? 1 : 0)
}

// Every frame shows ink all the way down: no run of more than `gap` pixel
// rows with nothing but the picture's ground on them. Rows of text keep
// their gaps shorter than a row; a row in sight drawn empty leaves a run
// as tall as it.
function filled(frames, gap) {
  if (frames.length < 2) return { ok: false, detail: frames.length + " frames grabbed" }
  const bare = []
  let longest = 0
  for (const f of frames) {
    const { width, height, data } = f.image
    const ground = groundIn(data)
    let run = 0, most = 0
    for (let y = 0; y < height; y++) {
      let ink = false
      for (let x = 0; x < width && !ink; x++) ink = data.readUIntBE((y * width + x) * 3, 3) !== ground
      run = ink ? 0 : run + 1
      most = Math.max(most, run)
    }
    longest = Math.max(longest, most)
    if (most > gap) bare.push(f.t + " ms: " + most + " px bare")
  }
  return { ok: bare.length === 0, detail: frames.length + " frames, the longest bare run " + longest + " px" + (bare.length ? "; " + bare.slice(0, 5).join(", ") : "") }
}

const [mode, ...rest] = process.argv.slice(2)
if (mode === "self-check") selfCheck()
else {
  const [kind, end, flag] = mode.split(":")
  const band = kind === "edge" ? Number(rest[0]) : 0
  const plotArg = rest.find(arg => arg.startsWith("plot="))
  const plot = plotArg ? picture(readFileSync(plotArg.slice(5))) : null
  const args = (kind === "edge" ? rest.slice(1) : kind === "press" ? rest.slice(2) : rest).filter(arg => arg !== plotArg)
  const frames = args.map(arg => {
    const at = arg.lastIndexOf("@")
    return { t: Number(arg.slice(at + 1)), image: picture(readFileSync(arg.slice(0, at))) }
  }).sort((a, b) => a.t - b.t)
  const verdict = kind === "same" ? same(end === undefined ? frames : frames.map(f => ({ ...f, image: cropped(f.image, end) })))
    : kind === "drawin" ? drawin(frames, end === undefined ? 1 : end === "ink" ? end : Number(end), plot, flag === "first")
    : kind === "edge" ? edge(frames, band) : kind === "edgeheld" ? edgeheld(frames)
    : kind === "dim" ? dim(flag === undefined ? frames : frames.map(f => ({ ...f, image: cropped(f.image, flag) })), end === undefined ? 250 : Number(end))
    : kind === "turn" ? turn(frames, end === undefined ? 160 : Number(end))
    : kind === "steps" ? steps(frames, Number(end))
    : kind === "columns" ? columnTurn(frames, Number(end), Number(flag))
    : kind === "filled" ? filled(flag === undefined ? frames : frames.map(f => ({ ...f, image: cropped(f.image, flag) })), Number(end))
    : kind === "press" ? press(frames, rest[0].split(",").map(Number), rest[1].split(",").map(Number))
    : { ok: false, detail: "unknown mode " + mode }
  console.log(JSON.stringify(verdict))
}
