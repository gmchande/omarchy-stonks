import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin" as Stonks

// What Stonks plays, through the real popup (Panel.qml, its card in
// CardWindow.qml) by keys and the real window (App.qml) by the pointer, with
// a stand-in pw-play first on PATH (bin/pw-play) that plays nothing and
// records what it was asked to play. sounds.sh's copy counts the output
// asleep after 1.5 s, not 4 s, and writes a look's files ahead 5 ms apart,
// not 100. HOME and curl are scratch.
Harness {
  id: harness
  marker: "SOUNDS DONE"

  // The quantum, in frames, a stream started with `args` holds the graph
  // at, at `rate`: PipeWire rounds its latency down to a power of two. A
  // stream that names no latency in ms gets 0, so it fails any check.
  function quantum(args, rate) {
    var m = / --latency (\d+(?:\.\d+)?)ms /.exec(" " + args + " ")
    if (!m) return 0
    return Math.pow(2, Math.floor(Math.log(Number(m[1]) * rate / 1000) / Math.LN2))
  }

  // The first item under `item` with a property named `name`.
  function findWith(item, name) {
    if (!item) return null
    if (name in item) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = findWith(item.children[i], name)
      if (found) return found
    }
    return null
  }
  readonly property string fakeState: Quickshell.env("STONKS_FAKE_STATE")
  function readBytes(path) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = path
    var bytes = view.data()
    view.destroy()
    return bytes
  }
  function writeText(path, text) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockWrites: true; preload: false; printErrors: false }', harness)
    view.path = path
    view.setText(text)
    view.destroy()
  }
  // Holds a symbol's answer back while the fake curl finds NAME in its
  // state, or lets it through (bin/curl).
  Process { id: fileProc }
  function hold(on, name) {
    fileProc.command = on ? ["touch", fakeState + "/" + name] : ["rm", "-f", fakeState + "/" + name]
    fileProc.running = true
  }

  // The stand-in's record, a line each: "start" with its count `n`, the
  // file it was asked to play, and its other arguments, then "stopped" or
  // "ended" with the same `n`.
  function record() {
    return readFile(fakeState + "/pw-play.log").split("\n").filter(function(line) { return line !== "" }).map(function(line) {
      var words = line.split(" ")
      return { what: words[0], ms: Number(words[1]), n: Number(words[2]), args: words.slice(3, -1).join(" "), file: words[words.length - 1] }
    })
  }
  // A chime is any start of a chime's file, with a lead-in or not; every
  // other start is a sound.
  function isChime(e) {
    return /\/chime-(lead\d+-)?(smooth|retro)-\d+\.wav$/.test(e.file)
  }
  function starts() {
    return record().filter(function(e) { return e.what === "start" && !isChime(e) })
  }
  function chimes() {
    return record().filter(function(e) { return e.what === "start" && isChime(e) })
  }
  // A chime's voice and bar, as "retro-3", with a lead-in or not.
  function bar(chime) {
    return chime.file.replace(/^.*\/chime-(lead\d+-)?/, "").replace(/\.wav$/, "")
  }
  // The lead-in of silence a start's file opens with, in ms: a chime's by
  // its name, a fixed sound's 150.
  function lead(e) {
    var chime = /\/chime-lead(\d+)-[^\/]*\.wav$/.exec(e.file)
    return chime ? Number(chime[1]) : /\/lead-[^\/]*\.wav$/.test(e.file) ? 150 : 0
  }

  Stonks.Service { id: service }
  Stonks.Updates { id: updates }
  Stonks.Sounds { id: sounds; turnedOn: service.soundsOn; retro: service.retro; files: service.files }
  // The screenshot's camera, its commands the stand-ins on PATH (bin/).
  Stonks.Camera { id: camera }
  Component { id: bellMaker; Stonks.Bell {} }
  // The clock the bell's passes hear: the service's quote, featured symbol,
  // calendars, and screens, at the moments a pass sets, which the service's
  // own clock, moving to the wall's second at each step, can't.
  QtObject {
    id: bellClock
    property int now: 0
    readonly property var quotes: service.quotes
    readonly property string featuredSymbol: service.featuredSymbol
    readonly property var calendars: service.calendars
    readonly property bool screensOff: service.screensOff
  }
  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service, updates: updates, sounds: sounds, camera: camera } }
  }
  PluginBarApi {
    id: api
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
    foreground: Commons.Color.foreground
    fontFamily: Style.font.family
  }
  Stonks.Panel { id: panel; bar: api; settings: ({}) }
  Stonks.App { id: app; service: service; updates: updates; sounds: sounds; camera: camera }

  Steps {
    name: "Sounds"
    when: service.pluginsReady

    function quiet() {
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
    }

    // The stand-in's starts, once `count` of them are in, and 100 ms more
    // for one that mustn't follow.
    function startsBy(count) {
      tryVerify(function() { return harness.starts().length >= count }, 3000)
      wait(100)
      return harness.starts()
    }

    // Stonks counts the output asleep: its last sound, or its silence's end,
    // is past the copy's 1.5 s.
    function asleep() {
      tryVerify(function() { return Date.now() >= sounds.asleepAfter }, 4000)
    }

    // The chart on screen has drawn in.
    function drawnIn(body) {
      tryCompare(body.motion, "reveal", 1, 2000)
    }

    // Takes NAME out of the fake state.
    function dropState(name) {
      fileProc.command = ["rm", "-f", harness.fakeState + "/" + name]
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }

    // No chime waits out the gap, and the next strikes at once.
    function chimesRest() {
      tryVerify(function() { return sounds.waiting < 0 && Date.now() >= sounds.lastChime + sounds.chimeGap }, 2000)
    }

    // The sound file a start played, as the plugin names it: a fixed
    // sound's lead-in as the sound it leads.
    function played(start) {
      var lead = /\/lead-(smooth|retro)-(\w+)\.wav$/.exec(start.file)
      return lead ? "sounds/" + lead[1] + "/" + lead[2] + ".wav" : start.file.replace(/^.*\/plugin\//, "")
    }

    // What follows the sound started at `index` (1-based, among sounds, not
    // chimes): "stopped" or "ended", or "" while it plays.
    function endOf(index) {
      var n = harness.starts()[index - 1].n
      var events = harness.record()
      for (var i = 0; i < events.length; i++) {
        if (events[i].what !== "start" && events[i].n === n) return events[i].what
      }
      return ""
    }

    // The sound a start played, as the stand-in kept it: its samples and
    // rate, and the replay's place along the chart `t` seconds in.
    function replaySound(index, chart) {
      var bytes = new DataView(harness.readBytes(harness.fakeState + "/pw-play." + harness.starts()[index - 1].n + ".wav"))
      var rate = bytes.getUint32(24, true)
      var samples = (bytes.byteLength - 44) / 2
      var s = new Float32Array(samples)
      for (var i = 0; i < samples; i++) s[i] = bytes.getInt16(44 + i * 2, true) / 32768
      var ease = function(u) { return -(Math.cos(Math.PI * u) - 1) / 2 }
      return { s: s, rate: rate, samples: samples,
        place: function(t) { return chart.from + (chart.to - chart.from) * ease(Math.min(1, t / 2)) } }
    }
    readonly property var penta: [440, 493.88, 554.37, 659.25, 739.99, 880, 987.77, 1108.73, 1318.51, 1479.98, 1760]

    // Retro's replay, read against the chart it was made from, by what the
    // samples hold and what the chart draws:
    // - pitch: every 25 ms where one note holds through the window, the
    //   pitch read from the samples is the column's pentatonic note, within
    //   a semitone, nine times in ten;
    // - silence: over dark columns, nothing sounds;
    // - ticks: each crossing of the baseline by the lit columns is heard
    //   within 25 ms, and no tick is heard anywhere else. Crossings closer
    //   than 41 ms (30 ms of noise, read over 11 ms) are one.
    function retroHeard(index, chart) {
      var sound = replaySound(index, chart), s = sound.s, rate = sound.rate, samples = sound.samples
      var grid = chart.grid
      var column = function(x) { return Math.max(0, Math.min(grid.columns - 1, Math.floor(x * grid.columns))) }
      // The column's note at `t` seconds in, or 0 over a dark one.
      var expected = function(t) {
        var row = grid.levels[column(sound.place(t))]
        return row === undefined ? 0 : penta[Math.round((grid.rows - 1 - row) / Math.max(1, grid.rows - 1) * (penta.length - 1))]
      }
      var span = Math.round(0.012 * rate)
      // The period, by autocorrelation over 12 ms: the shortest lag within
      // a tenth of the best, so an octave down never wins.
      var pitch = function(start) {
        var scores = [], best = 0
        for (var lag = Math.floor(rate / 2000); lag <= Math.ceil(rate / 250); lag++) {
          var a = 0, e = 0
          for (var i = 0; i < span; i++) { a += s[start + i] * s[start + i + lag]; e += s[start + i] * s[start + i] }
          scores.push(e > 0 ? a / e : 0)
          if (e > 0 && a / e > best) best = a / e
        }
        for (var j = 1; j < scores.length - 1; j++)
          if (scores[j] >= best * 0.9 && scores[j] >= scores[j - 1] && scores[j] >= scores[j + 1]) return rate / (j + Math.floor(rate / 2000))
        return 0
      }
      var rms = function(start, n) { var e = 0; for (var i = start; i < start + n; i++) e += s[i] * s[i]; return Math.sqrt(e / n) }
      var whole = rms(0, samples)
      var hits = 0, total = 0, misses = [], quiet = 0, still = 0, loud = []
      for (var t = 0.15; t < 1.9; t += 0.025) {
        // Where the window and 10 ms either side hold one note.
        var want = expected(t + span / rate / 2)
        if (expected(t - 0.01) !== want || expected(t + span / rate + 0.01) !== want) continue
        if (want === 0) {
          still++
          if (rms(Math.round(t * rate), span) < whole * 0.01) quiet++
          else loud.push(t.toFixed(3) + "s")
          continue
        }
        var heard = pitch(Math.round(t * rate))
        total++
        if (heard > 0 && Math.abs(12 * Math.log(heard / want) / Math.LN2) < 1) hits++
        else misses.push(t.toFixed(3) + "s " + Math.round(heard) + " for " + Math.round(want))
      }
      // The crossings, from the chart: at each lit column on the other side
      // from the lit one before it; nothing crosses a dark column. `every`
      // keeps each one, which a heard tick may be at; `crossings` only those
      // after a gap as long as a tick, which must each be heard.
      var crossings = [], every = [], last = 0, lastCol = -1
      for (var c = 0; c <= 2; c += 0.0005) {
        var col = column(sound.place(c))
        if (col === lastCol) continue
        lastCol = col
        if (grid.levels[col] === undefined) { last = 0; continue }
        var side = Math.sign(grid.baseRow - grid.levels[col])
        if (side && last && side !== last) {
          every.push(c)
          if (!crossings.length || c - crossings[crossings.length - 1] > 0.041) crossings.push(c)
        }
        if (side) last = side
      }
      // The ticks heard, every 4 ms, where noise fills the spectrum between
      // the note's harmonics: over 256 samples (11 ms, Hann), the power
      // between 1 and 6 kHz more than a bin and a half from every harmonic
      // of the notes the chart puts in the window, where the band-limited
      // pulse leaves nothing, against the replay's sounding level. A tick
      // where that passes 0.004 for 12 ms, as 30 ms of noise does and a
      // note's 1 ms onset doesn't, from under it 4 ms before: over a held
      // note, a change of note, or silence alike.
      var win = Math.round(0.004 * rate), energy = [], levels = [], ticks = []
      var fft = 256, binHz = rate / fft, lowBin = Math.ceil(1000 / binHz), highBin = Math.floor(6000 / binHz)
      var between = function(at) {
        var notes = [expected(at / rate), expected((at + fft / 2) / rate), expected((at + fft) / rate)].filter(function(f0) { return f0 > 0 })
        var power = 0
        for (var b = lowBin; b <= highBin; b++) {
          var hz = b * binHz
          if (notes.some(function(f0) { return Math.abs(hz - Math.round(hz / f0) * f0) <= 1.5 * binHz })) continue
          var re = 0, im = 0
          for (var k = 0; k < fft; k++) {
            var v = s[at + k] * (0.5 - 0.5 * Math.cos(2 * Math.PI * k / fft)), phase = 2 * Math.PI * ((b * k) % fft) / fft
            re += v * Math.cos(phase)
            im -= v * Math.sin(phase)
          }
          power += re * re + im * im
        }
        return power
      }
      for (var at = 0; at + fft < samples; at += win) {
        energy.push(between(at))
        var e = rms(at, fft)
        levels.push(e * e)
      }
      var sounding = levels.slice().sort(function(a, b) { return a - b })[Math.floor(levels.length * 0.75)] * fft * fft
      var noisy = function(f) { return energy[f] / sounding > 0.004 }
      // Before the file is silence, so a tick from its first sample is
      // heard too.
      for (var f = 0; f < energy.length - 2; f++) {
        var heardAt = (f * win + fft / 2) / rate
        if (noisy(f) && noisy(f + 1) && noisy(f + 2) && (f === 0 || !noisy(f - 1))
          && (!ticks.length || heardAt - ticks[ticks.length - 1] > 0.035)) ticks.push(heardAt)
      }
      var near = function(list, t) { return list.some(function(u) { return Math.abs(u - t) < 0.025 }) }
      var unheard = crossings.filter(function(t) { return !near(ticks, t) })
      var stray = ticks.filter(function(t) { return !near(every, t) })
      return {
        pitch: { ok: samples > 2 * rate && total >= 20 && hits >= total * 0.9, detail: hits + "/" + total + " windows; " + misses.slice(0, 5).join(", ") },
        silence: { ok: loud.length === 0, detail: quiet + "/" + still + " windows quiet; loud at " + loud.slice(0, 5).join(", ") },
        ticks: { ok: unheard.length === 0 && stray.length === 0, count: crossings.length,
          detail: crossings.length + " crossings, " + ticks.length + " ticks; unheard " + unheard.map(function(t) { return t.toFixed(3) }).join(" ")
            + "; stray " + stray.map(function(t) { return t.toFixed(3) }).join(" ") }
      }
    }

    // Retro's grid on screen, null in smooth.
    function shownGrid(body) {
      var pixel = harness.findAll(body, "curtain").filter(function(c) { return c.parent.visible })[0]
      return pixel ? pixel.parent.grid : null
    }

    // The chart a replay starts on, as the motion hands it to the sounds.
    function capture(body) {
      var seen = {}
      var take = function(from, to) { seen.chart = { from: from, to: to, geometry: body.motion.geometry, grid: shownGrid(body) } }
      body.motion.replayStarted.connect(take)
      return { seen: seen, done: function() { body.motion.replayStarted.disconnect(take) } }
    }

    function test_sounds() {
      quiet()
      var file = function() { try { return JSON.parse(harness.readFile(service.dataPath)) } catch (e) { return null } }

      // On from a data file that has never named them, and nothing played
      // at start.
      panel.open()
      var body = panel.testBody
      tryVerify(function() { return body && body.surfaceOpen && !body.chartLoading }, 5000)
      var icon = harness.find(body, "soundIcon")
      harness.check("sounds are on by default, the header's speaker showing it, and nothing has played",
        service.soundsOn && icon.on === true && harness.starts().length === 0, service.soundsOn + "|" + harness.starts().length)

      // The popup by keys, in smooth.
      // The card takes the keys a turn of the event loop later.
      panel.refocusKeys()
      wait(100)
      // Nothing that happens by itself, and nothing done to look around
      // but the scrub: a refresh and its answers, a range and back, the
      // look and back, the change, the selection, the key sheet, a row's
      // chart. The keys come 60 ms apart, past the chimes' 45 ms gap, so
      // each scrub step strikes its own.
      var quietKeys = [Qt.Key_R, Qt.Key_Left, Qt.Key_Left, Qt.Key_Right, Qt.Key_Escape, Qt.Key_BracketRight, Qt.Key_BracketLeft,
        Qt.Key_S, Qt.Key_S, Qt.Key_C, Qt.Key_C, Qt.Key_C, Qt.Key_Down, Qt.Key_Up, Qt.Key_Question, Qt.Key_Question, Qt.Key_2, Qt.Key_1]
      quietKeys.forEach(function(key) { keyClick(key); wait(60) })
      service.refresh()
      quiet()
      // Time for a sound that mustn't start.
      wait(500)
      var stepChimes = harness.chimes().map(harness.bar)
      harness.check("with sounds on, a refresh, its answers, a range, the look, the change, the selection, the sheet, and a row's chart play nothing, and the scrub's three key steps strike three of smooth's chimes",
        harness.starts().length === 0 && stepChimes.length === 3 && stepChimes.every(function(b) { return /^smooth-([0-9]|10)$/.test(b) }),
        JSON.stringify(harness.record()))

      // Delete, Ctrl+Z, and an add through search: each its own sound, in
      // smooth's voice.
      keyClick(Qt.Key_Delete)
      var removed = startsBy(1)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      var undone = startsBy(2)
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding }, 2000)
      keyClick(Qt.Key_S)
      keyClick(Qt.Key_H)
      tryVerify(function() { return body.adding && body.search.results.length > 1 }, 3000)
      var library = service.library.length
      keyClick(Qt.Key_Return)
      // SHOP's first fetch fails for good: its row joins saying so, and the
      // add is heard then.
      quiet()
      var added = startsBy(3)
      harness.check("in the popup, Delete plays the removal, Ctrl+Z its undo, and an add from search the add, each in smooth's voice",
        played(removed[0]) === "sounds/smooth/remove.wav" && played(undone[1]) === "sounds/smooth/undo.wav"
          && played(added[2]) === "sounds/smooth/add.wav" && service.library.length === library + 1,
        harness.starts().map(played).join(", "))

      // p: a replay heard; left to run, it plays to its end.
      tryVerify(function() { return !body.chartLoading }, 5000)
      keyClick(Qt.Key_P)
      var replayed = startsBy(4)
      tryVerify(function() { return !body.motion.replayRunning }, 4000)
      tryVerify(function() { return endOf(4) !== "" }, 3000)
      harness.check("p plays the replay's sound, written whole before it plays, and a replay left to run plays to its end",
        replayed[3].file === sounds.replayPath && endOf(4) === "ended", replayed[3].file + "|" + endOf(4))

      // Tokyo's day of 19 October, whose line stops for lunch below the
      // close and starts again above it: retro is silent over its dark
      // columns, and ticks only where what is drawn crosses, not at lunch's
      // end. Smooth's replay of it is saved.test.js's.
      harness.writeText(harness.fakeState + "/overnight.set", "demo-2026-10-19-1146\n")
      service.addSymbol("7203.T")
      quiet()
      harness.writeText(harness.fakeState + "/overnight.set", "")
      service.feature("7203.T")
      tryVerify(function() { return body.featuredSymbol === "7203.T" && !body.chartLoading }, 5000)
      service.persist({ style: "retro" })
      tryVerify(function() { return shownGrid(body) !== null }, 2000)
      drawnIn(body)
      var tokyo = capture(body)
      var at = harness.starts().length
      keyClick(Qt.Key_P)
      startsBy(at + 1)
      tokyo.done()
      tryVerify(function() { return endOf(at + 1) !== "" }, 4000)
      var lunch = retroHeard(at + 1, tokyo.seen.chart)
      service.persist({ style: "smooth" })
      harness.check("retro's replay of Tokyo's day sounds nothing new across lunch, where the chart draws nothing, and ticks only where what is drawn crosses",
        lunch.pitch.ok && lunch.silence.ok && /^[1-9]/.test(lunch.silence.detail) && lunch.ticks.ok,
        lunch.pitch.detail + " | " + lunch.silence.detail + " | " + lunch.ticks.detail)
      // The chimes over Tokyo's lunch, in both looks: the scrub moved into
      // the break strikes nothing; moved on to the afternoon's line, it
      // strikes once.
      var hero = harness.findWith(body, "pixelGrid")
      var lunchChimes = [false, true].map(function(retro) {
        service.persist({ style: retro ? "retro" : "smooth" })
        tryVerify(function() { return (shownGrid(body) !== null) === retro }, 2000)
        var pts = body.motion.geometry.points
        var gap = null
        for (var p = 1; p < pts.length && !gap; p++) if (pts[p].brk) gap = [pts[p - 1].x, pts[p].x]
        var struck = harness.chimes().length
        hero.scrubRequested(gap[0] - 0.02)
        tryVerify(function() { return harness.chimes().length > struck }, 2000)
        struck = harness.chimes().length
        // 80 ms apart, past the 45 ms gap, for a chime that mustn't start.
        for (var k = 2; k <= 4; k++) {
          hero.scrubRequested(gap[0] + (gap[1] - gap[0]) * k / 6)
          wait(80)
        }
        var inBreak = harness.chimes().length - struck
        // Steps on, as → takes them, through the rest of lunch, silent, to
        // the afternoon's first print, which strikes.
        for (var step = 0; step < 30 && body.motion.scrubX < gap[1]; step++) {
          body.nudgeScrub(1)
          wait(60)
        }
        var landed = body.motion.scrubX === gap[1]
        within(1000, function() { return harness.chimes().length > struck + inBreak })
        var afterBreak = harness.chimes().length - struck - inBreak
        body.endScrub()
        return { ok: inBreak === 0 && afterBreak === 1 && landed,
          detail: (retro ? "retro: " : "smooth: ") + inBreak + " in the break, " + afterBreak + " after, landed on the first print " + landed }
      })
      service.persist({ style: "smooth" })
      harness.check("the scrub over Tokyo's lunch strikes nothing, and the afternoon's line strikes again, smooth and retro",
        lunchChimes[0].ok && lunchChimes[1].ok, lunchChimes[0].detail + " || " + lunchChimes[1].detail)
      // A bar still waiting out the 45 ms gap as the pointer moves on into
      // lunch is dropped: nothing starts where the line lifts. Two prints
      // before lunch on different bars, struck back to back, then lunch.
      tryVerify(function() { return shownGrid(body) === null }, 2000)
      chimesRest()
      var lunchPts = body.motion.geometry.points, lastMorning = -1
      for (var q = 1; q < lunchPts.length && lastMorning < 0; q++) if (lunchPts[q].brk) lastMorning = q - 1
      var barOfPrint = function(pt) { return Math.round((1 - Math.max(0, Math.min(1, pt.y))) * 10) }
      var otherPrint = lastMorning - 1
      while (otherPrint > 0 && barOfPrint(lunchPts[otherPrint]) === barOfPrint(lunchPts[lastMorning])) otherPrint--
      var chimedBefore = harness.chimes().length
      hero.scrubRequested(lunchPts[otherPrint].x)
      hero.scrubRequested(lunchPts[lastMorning].x)
      hero.scrubRequested((lunchPts[lastMorning].x + lunchPts[lastMorning + 1].x) / 2)
      // Time for the dropped bar to start, were it not dropped.
      wait(300)
      var heardThen = harness.chimes().slice(chimedBefore).map(harness.bar)
      body.endScrub()
      harness.check("a bar waiting out the gap as the pointer moves into lunch is dropped, and only the bar before it sounds",
        heardThen.join(",") === "smooth-" + barOfPrint(lunchPts[otherPrint]),
        heardThen.join(",") + " for smooth-" + barOfPrint(lunchPts[otherPrint]))
      service.removeSymbol("7203.T")
      service.feature("MSFT")
      quiet()
      tryVerify(function() { return body.featuredSymbol === "MSFT" && !body.chartLoading }, 5000)
      drawnIn(body)

      // A replay's sound stops with the replay: Esc, a row's chart, the
      // popup closing. And one sound at a time: Delete mid-replay cuts it.
      var cuts = []
      var cut = function(how) {
        var before = harness.starts().length
        keyClick(Qt.Key_P)
        startsBy(before + 1)
        how()
        tryVerify(function() { return endOf(before + 1) !== "" }, 3000)
        cuts.push(endOf(before + 1))
      }
      cut(function() { keyClick(Qt.Key_Escape) })
      cut(function() { keyClick(Qt.Key_Down); keyClick(Qt.Key_Return) })
      cut(function() { panel.close() })
      harness.check("a replay's sound stops with the replay: Esc, another row's chart, and closing the popup", cuts.join(",") === "stopped,stopped,stopped", cuts.join(","))
      panel.open()
      tryVerify(function() { return body.surfaceOpen && !body.chartLoading }, 5000)
      panel.refocusKeys()
      wait(100)
      var before = harness.starts().length
      keyClick(Qt.Key_P)
      startsBy(before + 1)
      keyClick(Qt.Key_Delete)
      var after = startsBy(before + 2)
      tryVerify(function() { return endOf(before + 1) !== "" }, 3000)
      harness.check("one sound at a time: Delete during a replay stops the replay's sound and plays the removal",
        endOf(before + 1) === "stopped" && played(after[before + 1]) === "sounds/smooth/remove.wav", endOf(before + 1) + "|" + played(after[before + 1]))
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      startsBy(before + 3)
      quiet()

      // Ctrl+C: the screenshot, and with it the shutter once, in smooth's voice.
      before = harness.starts().length
      keyClick(Qt.Key_C, Qt.ControlModifier)
      var shutter = startsBy(before + 1)
      tryVerify(function() { return body.cameraLit && !camera.busy }, 5000)
      // Time for a second shutter that mustn't sound.
      wait(300)
      harness.check("Ctrl+C sounds the shutter once as the screenshot is taken, in smooth's voice",
        harness.starts().length === before + 1 && played(shutter[before]) === "sounds/smooth/shutter.wav",
        harness.starts().slice(before).map(played).join(", "))

      // m: off, saved, the speaker muted, and nothing plays; a replay
      // playing stops. Then Delete, Ctrl+Z, an add, p, and a screenshot play nothing.
      before = harness.starts().length
      keyClick(Qt.Key_P)
      startsBy(before + 1)
      keyClick(Qt.Key_M)
      tryVerify(function() { return endOf(before + 1) !== "" }, 3000)
      tryVerify(function() { var f = file(); return !!f && f.sounds === false }, 3000)
      harness.check("m turns sounds off: saved, the speaker muted, the replay playing stopped",
        !service.soundsOn && icon.on === false && endOf(before + 1) === "stopped", service.soundsOn + "|" + endOf(before + 1))
      before = harness.starts().length
      var count = service.library.length
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Delete)
      tryVerify(function() { return service.library.length === count - 1 }, 2000)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      tryVerify(function() { return service.library.length === count }, 2000)
      body.acceptSymbol("SPY")
      quiet()
      keyClick(Qt.Key_P)
      tryVerify(function() { return body.motion.replayRunning }, 2000)
      tryVerify(function() { return !body.motion.replayRunning }, 4000)
      keyClick(Qt.Key_C, Qt.ControlModifier)
      tryVerify(function() { return !camera.busy && body.note.indexOf("screenshot of SPY") >= 0 }, 5000)
      // Time for a shutter that mustn't sound.
      wait(100)
      harness.check("with sounds off, Delete, Ctrl+Z, an add, p, and a screenshot play nothing", harness.starts().length === before, JSON.stringify(harness.starts().slice(before)))
      service.removeSymbol("SPY")

      // m again: on, saved, and the add sound once, so you hear the level.
      keyClick(Qt.Key_M)
      var onAgain = startsBy(before + 1)
      tryVerify(function() { var f = file(); return !!f && f.sounds === true }, 3000)
      harness.check("m turns sounds back on, saved, and plays the add sound once",
        service.soundsOn && icon.on === true && onAgain.length === before + 1 && played(onAgain[before]) === "sounds/smooth/add.wav",
        harness.starts().slice(before).map(played).join(", "))

      // An add confirmed before its preview has answered: SHOP.TO's day held
      // back, Enter on it as soon as it is chosen. While its answer is held,
      // the header names it as the chart on its way, as the preview did, no
      // row stands for it, and nothing plays; let through, its row joins and
      // the add is heard then.
      before = harness.starts().length
      harness.hold(true, "SHOP.TO.quote.hold")
      tryVerify(function() { return !fileProc.running }, 2000)
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding }, 2000)
      keyClick(Qt.Key_S)
      keyClick(Qt.Key_H)
      tryVerify(function() { return body.adding && body.search.results.length > 1 }, 3000)
      keyClick(Qt.Key_Down)
      tryVerify(function() { return body.previewSymbol === "SHOP.TO" }, 2000)
      keyClick(Qt.Key_Return)
      var header = harness.find(body, "statusText")
      within(2000, function() { return header.text === "LOADING SHOP.TO" })
      var waiting = [header.text, body.watchlist.displayedSymbols.indexOf("SHOP.TO") >= 0 ? "row" : "no row",
        harness.starts().length - before].join("/")
      var released = Date.now()
      harness.hold(false, "SHOP.TO.quote.hold")
      tryVerify(function() { return body.watchlist.displayedSymbols.indexOf("SHOP.TO") >= 0 && service.featuredSymbol === "SHOP.TO" && !body.chartLoading }, 8000)
      var joined = startsBy(before + 1).slice(before)
      quiet()
      harness.check("an add confirmed before its preview answers is named as the chart on its way, silent, until its row joins, and heard then",
        waiting === "LOADING SHOP.TO/no row/0" && joined.length === 1 && played(joined[0]) === "sounds/smooth/add.wav" && joined[0].ms >= released,
        waiting + " || " + joined.map(function(s) { return played(s) + " at " + (s.ms - released) + " ms" }).join(", "))
      service.removeSymbol("SHOP.TO")
      panel.close()
      tryVerify(function() { return !body.surfaceOpen }, 2000)

      // The window by the pointer, in retro, its look picked with a click,
      // on AAPL's day, the popup's failed add gone.
      service.library.filter(function(s) { return ["AAPL", "MSFT", "NVDA"].indexOf(s) < 0 }).forEach(function(s) { service.removeSymbol(s) })
      service.feature("AAPL")
      app.open("{}")
      var win = app.testBody
      tryVerify(function() { return win && win.surfaceOpen && !win.chartLoading && win.featuredSymbol === "AAPL" }, 5000)
      mouseMove(win, 1, 1)
      var look = harness.find(win, "lookToggle")
      mouseClick(look, look.width / 2, look.height / 2)
      tryVerify(function() { return service.retro }, 2000)
      // Retro's chart drawn in, and its files written ahead, so no write
      // holds the thread mid-sweep.
      tryVerify(function() { return shownGrid(win) !== null }, 2000)
      drawnIn(win)
      tryVerify(function() {
        return sounds.aheadOf("retro").every(function(f) { return sounds.madeThisRun[sounds.fileOf("retro", f[0], f[1])] })
      }, 5000)
      var chart = win.chartItem

      // The chimes by the pointer, in retro: a sweep across the chart and
      // back strikes the bars it crosses, the lit row's height each one's
      // pitch, and ends on the bar under the pointer; never more strikes
      // than bars it moved onto. A hand resting on one column strikes
      // nothing more.
      var pixels = harness.findWith(win, "scrubColumn")
      var barHere = function() {
        var g = pixels.grid, row = g.levels[pixels.scrubColumn]
        return row === undefined ? -1 : Math.round((g.rows - 1 - row) / Math.max(1, g.rows - 1) * 10)
      }
      var sweep = function(from, to, seen) {
        var step = from < to ? 2 : -2
        for (var px = from; step > 0 ? px <= to : px >= to; px += step) {
          mouseMove(chart, px, chart.height / 2)
          var b = barHere()
          if (b >= 0 && b !== seen.last) {
            seen.changes++
            if (seen.crossed.indexOf(b) < 0) seen.crossed.push(b)
          }
          seen.last = b
        }
        return seen
      }
      mouseMove(win, 1, 1)
      chimesRest()
      var chimesBefore = harness.chimes().length
      var seen = sweep(chart.width * 0.05, chart.width * 0.9, { last: -1, changes: 0, crossed: [] })
      sweep(chart.width * 0.9, chart.width * 0.3, seen)
      var endBar = "retro-" + barHere()
      tryVerify(function() { var c = harness.chimes(); return c.length > chimesBefore && harness.bar(c[c.length - 1]) === endBar }, 2000)
      wait(200)
      var swept = harness.chimes().slice(chimesBefore).map(harness.bar)
      mouseMove(chart, chart.width * 0.3, chart.height / 3)
      wait(300)
      var rested = harness.chimes().length - chimesBefore - swept.length
      harness.check("a sweep of the pointer over the chart and back strikes retro's bars it crosses, ends on the bar under the pointer, and a hand resting strikes nothing more",
        swept.length > 1 && swept.length <= seen.changes && swept[swept.length - 1] === endBar && rested === 0
          && swept.every(function(b) { return /^retro-/.test(b) && seen.crossed.indexOf(Number(b.slice(6))) >= 0 }),
        swept.length + " struck of " + seen.changes + " moved onto; ends " + swept[swept.length - 1] + " under " + endBar + "; rested " + rested + "; " + swept.join(" "))
      mouseMove(win, 1, 1)

      // The speaker: a click turns sounds off, silently, and on, with the
      // add sound once, now in retro's voice.
      var speaker = harness.find(win, "soundToggle")
      var winIcon = harness.find(win, "soundIcon")
      before = harness.starts().length
      mouseClick(speaker, speaker.width / 2, speaker.height / 2)
      tryVerify(function() { return !service.soundsOn }, 2000)
      var chimesOff = harness.chimes().length
      sweep(chart.width * 0.05, chart.width * 0.9, { last: -1, changes: 0, crossed: [] })
      mouseMove(win, 1, 1)
      // Time for a chime that mustn't sound.
      wait(300)
      var offSilent = harness.starts().length === before && harness.chimes().length === chimesOff && winIcon.on === false
      mouseClick(speaker, speaker.width / 2, speaker.height / 2)
      var clicked = startsBy(before + 1)
      harness.check("a click on the speaker turns sounds off, silently, and on again, with the add sound once in retro's voice",
        offSilent && service.soundsOn && winIcon.on === true && clicked.length === before + 1 && played(clicked[before]) === "sounds/retro/add.wav",
        offSilent + "|" + harness.starts().slice(before).map(played).join(", "))

      // MSFT's chart, a busy US day, every column lit, to replay.
      var msft = win.watchlist.rowItem("MSFT")
      mouseClick(msft, msft.width / 2, msft.height / 2)
      tryVerify(function() { return win.featuredSymbol === "MSFT" && !win.chartLoading && win.animal.kind !== "" }, 5000)
      drawnIn(win)
      var lens = harness.find(win, "cameraButton")

      // A click on the animal: retro's replay, its notes the chart's
      // columns.
      before = harness.starts().length
      var animal = harness.find(win, "animalToggle")
      var watch = capture(win)
      mouseClick(animal, animal.width / 2, animal.height / 2)
      startsBy(before + 1)
      watch.done()
      tryVerify(function() { return endOf(before + 1) !== "" }, 4000)
      var retroReplay = retroHeard(before + 1, watch.seen.chart)
      harness.check("retro's replay is the chart's columns: a note per lit column, its pitch the column's height, silent over dark ones, a tick at each crossing",
        retroReplay.pitch.ok && retroReplay.silence.ok && retroReplay.ticks.ok,
        retroReplay.pitch.detail + " | " + retroReplay.silence.detail + " | " + retroReplay.ticks.detail)

      // Two surfaces, one player: the popup's replay, cut by the window's,
      // whose sound then plays to its end through the popup's close, which
      // stops the popup's replay and with it only the popup's own sound.
      panel.open()
      tryVerify(function() { return body.surfaceOpen && !body.chartLoading }, 5000)
      drawnIn(body)
      body.replay()
      startsBy(before + 2)
      mouseClick(animal, animal.width / 2, animal.height / 2)
      startsBy(before + 3)
      var popupCut = endOf(before + 2)
      var popupReplaying = body.motion.replayRunning
      panel.close()
      tryVerify(function() { return !body.surfaceOpen }, 2000)
      var playing = endOf(before + 3) === "" && win.motion.replayRunning
      tryVerify(function() { return endOf(before + 3) !== "" }, 4000)
      harness.check("the window's replay cuts the popup's sound, and the popup closing mid-replay leaves the window's playing to its end",
        popupCut === "stopped" && popupReplaying && playing && endOf(before + 3) === "ended",
        popupCut + "|" + popupReplaying + "|" + playing + "|" + endOf(before + 3))

      // The output kept awake (the stand-in pw-cat): a stream of silence
      // only while a chart's scrub moves with sounds on, by the pointer on
      // it or by keys, and a second after it last moved or ended; none while
      // the popup and the window are open and nothing is scrubbed, none for
      // a scrub left standing, and none with sounds off. One that ends on
      // its own while it's wanted starts again.
      var silence = function() {
        var lines = harness.readFile(harness.fakeState + "/pw-cat.log").split("\n").filter(function(l) { return l !== "" })
        var stops = lines.filter(function(l) { return /^stopped /.test(l) })
        return { running: lines.length > 0 && /^(start|streaming) /.test(lines[lines.length - 1]),
          starts: lines.filter(function(l) { return /^start /.test(l) }).length, last: lines[lines.length - 1] || "",
          stoppedAt: stops.length ? Number(stops[stops.length - 1].split(" ")[1]) : 0 }
      }
      // The window opened again takes the keys back from the popup's card,
      // which the replay above opened last; it starts no silence.
      tryVerify(function() { return !silence().running }, 3000)
      app.close()
      app.open("{}")
      tryVerify(function() { return app.opened && win.surfaceOpen && !win.chartLoading }, 5000)
      app.testKeyCatcher.forceActiveFocus()
      mouseMove(win, 1, 1)
      var startsOpen = silence().starts
      // Time for a stream that mustn't start.
      wait(300)
      var restsOpen = !silence().running && silence().starts === startsOpen
      // A quiet spell, then a burst of key steps, one about every 50 ms for
      // 1.6 s, each striking a chime, across the output's waking.
      asleep()
      var startsBefore = silence().starts
      var chimesBefore = harness.chimes().length
      var burstFrom = Date.now()
      while (Date.now() - burstFrom < 1600) {
        keyClick(Qt.Key_Left)
        wait(40)
      }
      var burstEnd = Date.now()
      // Time for the burst's last chime to start.
      wait(200)
      var byKeys = silence().running && silence().starts === startsBefore + 1
      var struck = harness.chimes().slice(chimesBefore)
      var awake = struck[struck.length - 1]
      // A scrub left standing lets the output go a second after its last
      // step, and stays where it is.
      tryVerify(function() { return !silence().running }, 3000)
      var parkedKeys = !silence().running && silence().stoppedAt - burstEnd >= 900 && win.motion.scrubT !== 0
      keyClick(Qt.Key_Escape)
      tryVerify(function() { return !silence().running }, 3000)
      startsBefore = silence().starts
      for (var sx = 0.1; sx < 0.6; sx += 0.05) {
        mouseMove(chart, chart.width * sx, chart.height / 2)
        wait(20)
      }
      var restedAt = Date.now()
      tryVerify(function() { return silence().running }, 3000)
      var byPointer = silence().starts === startsBefore + 1
      tryVerify(function() { return !silence().running }, 3000)
      var parkedPointer = !silence().running && silence().stoppedAt - restedAt >= 900 && win.motion.scrubT !== 0
      startsBefore = silence().starts
      mouseMove(chart, chart.width * 0.65, chart.height / 2)
      tryVerify(function() { return silence().running }, 3000)
      var movesAgain = silence().starts === startsBefore + 1
      var leftAt = Date.now()
      mouseMove(win, 1, 1)
      tryVerify(function() { return !silence().running }, 3000)
      var heldAfter = !silence().running && silence().stoppedAt - leftAt >= 900
      startsBefore = silence().starts
      keyClick(Qt.Key_Left)
      tryVerify(function() { return silence().running }, 3000)
      harness.writeText(harness.fakeState + "/pw-cat.exit", "now")
      tryVerify(function() { return /^exited /.test(silence().last) }, 3000)
      dropState("pw-cat.exit")
      // The scrub keeps moving, a step every 300 ms, so the stream is wanted
      // when it comes back.
      for (var step = 0; step < 20 && !silence().running; step++) {
        keyClick(Qt.Key_Left)
        wait(300)
      }
      var backAfterExit = silence().running && silence().starts === startsBefore + 2
      // The output may have gone with the stream: the chime struck as it
      // comes back opens with the lead-in.
      var backAt = Number(silence().last.split(" ")[1])
      var chimesNow = harness.chimes().length
      keyClick(Qt.Key_Left)
      tryVerify(function() { return harness.chimes().length > chimesNow }, 2000)
      var afterExit = harness.chimes()[harness.chimes().length - 1]
      service.persist({ sounds: false })
      tryVerify(function() { return !silence().running }, 3000)
      var offRests = !silence().running
      service.persist({ sounds: true })
      keyClick(Qt.Key_Left)
      tryVerify(function() { return silence().running }, 3000)
      keyClick(Qt.Key_Escape)
      tryVerify(function() { return !silence().running }, 3000)
      var escRests = !silence().running && win.surfaceOpen && win.motion.scrubT === 0
      harness.check("a stream of silence holds the output only while a chart's scrub moves with sounds on, by the pointer or by keys, until a second after it last moved, the pointer leaves, or Esc: not while the window is merely open, not for a scrub left standing, which stays where it is, and not with sounds off; one that ends while it's wanted starts again",
        restsOpen && byPointer && parkedKeys && parkedPointer && movesAgain && heldAfter && byKeys && backAfterExit && escRests && offRests,
        [restsOpen, byPointer, parkedKeys, parkedPointer, movesAgain, heldAfter, byKeys, backAfterExit, escRests, offRests].join(","))

      // A slow scrub, a step every 600 ms, pauses shorter than the hold,
      // keeps one stream after a quiet spell, and once the output is awake
      // each chime plays at once; a stream that reaches its time limit,
      // 2 s here, starts again at once, the chimes still at once.
      asleep()
      sounds.streamSeconds = 2
      startsBefore = silence().starts
      var slowFrom = harness.chimes().length
      var linesFrom = harness.readFile(harness.fakeState + "/pw-cat.log").split("\n").filter(function(l) { return l !== "" }).length
      for (var slow = 0; slow < 9; slow++) {
        keyClick(Qt.Key_Left)
        wait(600)
      }
      var slowChimes = harness.chimes().slice(slowFrom)
      var lines = harness.readFile(harness.fakeState + "/pw-cat.log").split("\n").filter(function(l) { return l !== "" }).slice(linesFrom)
      // From each stream's end at its limit to the next one's start.
      var gaps = lines.map(function(l, i) {
        return /^start /.test(l) && i > 0 && /^stopped /.test(lines[i - 1]) ? Number(l.split(" ")[1]) - Number(lines[i - 1].split(" ")[1]) : -1
      }).filter(function(g) { return g >= 0 })
      keyClick(Qt.Key_Escape)
      tryVerify(function() { return !silence().running }, 3000)
      sounds.streamSeconds = 60
      var slowLeads = slowChimes.map(harness.lead)
      harness.check("a slow scrub, a step every 600 ms, plays its first chime after a quiet spell with the lead-in and every one after at once, through a stream that reaches its time limit and starts again at once",
        slowChimes.length >= 4 && slowLeads[0] === 150 && slowLeads.slice(1).every(function(l) { return l === 0 })
          && silence().starts - startsBefore >= 3 && gaps.length >= 2 && gaps.every(function(g) { return g < 300 }),
        "leads " + slowLeads.join(",") + " | streams " + (silence().starts - startsBefore) + " | gaps " + gaps.join(",") + " ms")

      // A sound that may wake the output opens with silence, then the
      // sound whole: a scrub's chimes as it wakes the output after a quiet
      // spell, 150 ms at first, shrinking once the output is reached, never
      // so fast that a chime rings before one struck ahead of it (each
      // start plus its lead-in, give or take 10 ms for starting the
      // stand-in); a chime as the stream comes back from ending on its own;
      // and a sound after a quiet spell, the shutter here. A chime once the
      // output is awake plays at once.
      var leadsInto = function(start, plain) {
        var a = new Uint8Array(harness.readBytes(harness.fakeState + "/pw-play." + start.n + ".wav"))
        var b = new Uint8Array(harness.readBytes(plain))
        var zeros = Math.round(new DataView(b.buffer).getUint32(24, true) * harness.lead(start) / 1000) * 2
        if (b.length <= 44 || a.length !== b.length + zeros) return false
        for (var i = 44; i < 44 + zeros; i++) if (a[i] !== 0) return false
        for (var j = 44; j < b.length; j++) if (a[j + zeros] !== b[j]) return false
        return true
      }
      asleep()
      before = harness.starts().length
      mouseClick(lens, lens.width / 2, lens.height / 2)
      var quietShutter = startsBy(before + 1)[before]
      tryVerify(function() { return !camera.busy }, 5000)
      var leads = struck.map(harness.lead)
      var chimesLed = leads[0] === 150 && struck.every(function(c) {
        return !harness.lead(c) || leadsInto(c, sounds.folder + "/chime-" + harness.bar(c) + ".wav")
      })
      var inOrder = struck.every(function(c, i) { return i === 0 || c.ms + leads[i] >= struck[i - 1].ms + leads[i - 1] - 10 })
      var shutterLed = harness.lead(quietShutter) === 150 && played(quietShutter) === "sounds/" + sounds.voice + "/shutter.wav"
        && leadsInto(quietShutter, sounds.bundled(sounds.voice, "shutter"))
      harness.check("after a quiet spell, a scrub's first chime and the shutter open with 150 ms of silence, then the sound whole, the scrub's lead-ins shrinking so no chime rings before one struck ahead of it, and a chime as the stream comes back from ending on its own opens with one too; a chime once the output is awake plays at once",
        chimesLed && inOrder && shutterLed && harness.lead(afterExit) > 0 && harness.lead(awake) === 0,
        [chimesLed, inOrder, shutterLed, harness.lead(afterExit) + " ms " + (afterExit.ms - backAt) + " ms after the stream came back",
          "heard at " + struck.map(function(c, i) { return (c.ms - struck[0].ms) + "+" + leads[i] }).join(" "), quietShutter.file].join(" | "))

      // A replay after a quiet spell waits for the output instead: its sound
      // has no lead-in, so it keeps in step with its sweep, and it starts,
      // picture and sound, once the stream of silence has reached the output
      // and played 150 ms.
      asleep()
      before = harness.starts().length
      var silenceLines = harness.readFile(harness.fakeState + "/pw-cat.log").split("\n").length
      keyClick(Qt.Key_P)
      var waited = startsBy(before + 1)[before]
      var replayedAt = win.motion.replayRunning
      var reached = harness.readFile(harness.fakeState + "/pw-cat.log").split("\n").slice(silenceLines - 1)
        .filter(function(l) { return /^streaming /.test(l) }).map(function(l) { return Number(l.split(" ")[1]) })[0]
      tryVerify(function() { return !win.motion.replayRunning }, 4000)
      harness.check("after a quiet spell, p starts the replay once the silence has reached the output and played 150 ms, its sound with no lead-in, in step with its sweep",
        waited.file === sounds.replayPath && replayedAt && reached > 0 && waited.ms >= reached + 150,
        waited.file + " | replaying " + replayedAt + " | sound " + (waited.ms - reached) + " ms after the silence reached the output")

      // The market's bell, in retro's voice: as the clock passes the open
      // or the close of the market of the stock last looked at, once, a
      // Stonks started a moment before it included; never twice, with the
      // clock set back across it; never while an app records from a
      // microphone (the stand-in pw-dump's nodes), or when the answer runs
      // past its 4 MB, and a stalled answer stopped holds no later bell;
      // never with sounds off. Each pass is a Stonks started at its first
      // moment. Late bells are saved.test.js's (`bellBetween`).
      app.close()
      service.feature("AAPL")
      tryVerify(function() { return !!service.quotes.AAPL && service.featuredSymbol === "AAPL" }, 5000)
      var reg = service.quotes.AAPL.session.regular
      var bells = function() { return harness.starts().filter(function(s) { return played(s) === "sounds/retro/bell.wav" }).length }
      // A pass rings `rings` bells: waited for, then 300 ms more for one
      // that mustn't.
      var pass = function(moments, rings) {
        var rung = bells()
        bellClock.now = moments[0]
        var bell = bellMaker.createObject(harness, { service: bellClock, sounds: sounds })
        // Each moment its own minute's tick: a bell rung has played before
        // the next, so a second ring isn't lost to the first's check.
        moments.slice(1).forEach(function(t) {
          bellClock.now = t
          wait(300)
        })
        if (rings) tryVerify(function() { return bells() - rung >= rings }, 5000)
        wait(300)
        bell.destroy()
        return bells() - rung
      }
      var micOn = JSON.stringify([{ type: "PipeWire:Interface:Node", info: { state: "running",
        props: { "media.class": "Stream/Input/Audio", "application.name": "a call" } } }])
      var meterOn = JSON.stringify([{ type: "PipeWire:Interface:Node", info: { state: "running",
        props: { "media.class": "Stream/Input/Audio", "stream.capture.sink": true } } }])
      var rang = [pass([reg.start - 30, reg.start + 30], 1),
        pass([reg.start - 2, reg.start - 1, reg.start, reg.start - 1, reg.start, reg.start + 1], 1)]
      harness.writeText(harness.fakeState + "/pw-dump.json", micOn)
      rang.push(pass([reg.end - 30, reg.end + 30], 0))
      harness.writeText(harness.fakeState + "/pw-dump.json", meterOn)
      rang.push(pass([reg.end - 30, reg.end + 30], 1))
      // An answer that parses but runs past 4 MB: "[]" and 4.1 MB of spaces,
      // whose first 4 MB are themselves a valid list, with no microphone.
      harness.writeText(harness.fakeState + "/pw-dump.json", "[]" + new Array(4100001).join(" "))
      rang.push(pass([reg.end - 30, reg.end + 30], 0))
      harness.writeText(harness.fakeState + "/pw-dump.json", "[]")
      var dumpLog = function() { return harness.readFile(harness.fakeState + "/pw-dump.log").split("\n").filter(function(l) { return l !== "" }) }
      harness.writeText(harness.fakeState + "/pw-dump.stall", "held")
      rang.push(pass([reg.end - 30, reg.end + 30], 0))
      tryVerify(function() { var l = dumpLog(); return l[l.length - 1] === "stopped" }, 6000)
      dropState("pw-dump.stall")
      var stallStopped = dumpLog()[dumpLog().length - 1] === "stopped"
      rang.push(pass([reg.start - 30, reg.start + 30], 1))
      service.persist({ sounds: false })
      rang.push(pass([reg.start - 30, reg.start + 30], 0))
      harness.check("the bell rings at the open in retro's voice, a moment after Stonks starts too, not twice with the clock set back, not while a microphone records though a level meter may run, not when its answer reaches 4 MB, again after a stalled answer is stopped, and not with sounds off",
        rang.join(",") === "1,1,0,1,0,0,1,0" && stallStopped,
        rang.join(",") + " | stalled answer stopped " + stallStopped)

      // Every stream Stonks started, each sound's, chime's, replay's and
      // bell's pw-play and each silence's pw-cat, plays as a notification
      // and asks for a latency that leaves the default quantum, 1024
      // frames, where it is at 48 and 44.1 kHz: each move of it puts
      // AirPods further behind, until they go silent.
      var streams = harness.record().filter(function(e) { return e.what === "start" }).map(function(e) { return e.args })
        .concat(harness.readFile(harness.fakeState + "/pw-cat.log").split("\n").filter(function(l) { return /^start /.test(l) }))
      var moving = streams.filter(function(args) {
        return harness.quantum(args, 48000) !== 1024 || harness.quantum(args, 44100) !== 1024 || !/ --media-role Notification /.test(" " + args + " ")
      })
      harness.check("every stream Stonks started, chimes, sounds, replays, the bell and the silence, asks for a latency that leaves the 1024-frame quantum where it is",
        streams.length > 0 && moving.length === 0, streams.length + " streams | " + moving.slice(0, 3).join(" | "))

      // The chimes and lead-ins in the cache are written once and kept
      // while they hold the current sound: the next start writes none. A
      // file gone, or one rewritten since the look's stamp (as an older
      // Stonks, which keeps no stamp, writes every file each run), is
      // written again; a stamp naming other sources, as after a deploy that
      // changed a sound and kept the version, has the whole look written
      // again, its stamp last. A write that fails leaves the stamp as it
      // was, so the next start writes the look again. Each start is Sounds
      // made again over the same folder, its writes counted on the way to
      // the real ones, or one failed on the way (`failing`).
      var look = sounds.voice
      var names = sounds.aheadOf(look).map(function(f) { return sounds.fileOf(look, f[0], f[1]) })
      var stampPath = sounds.folder + "/stamp-" + look
      tryVerify(function() { return sounds.surveyed && harness.readFile(stampPath).trim() === sounds.sources[look] }, 15000)
      var restarted = function(failing) {
        var spy = spyFiles.createObject(harness, { real: service.files, failing: failing || "" })
        var again = soundsMaker.createObject(harness, { files: spy, retro: sounds.retro })
        tryVerify(function() { return again.surveyed }, 5000)
        return { sounds: again, spy: spy }
      }
      var finished = function(run) {
        tryVerify(function() { return run.spy.log.indexOf("stamp-" + look) >= 0 }, 15000)
        var writes = run.spy.log.slice()
        run.sounds.destroy()
        run.spy.destroy()
        return writes
      }
      var unchanged = restarted()
      var keptAll = names.every(function(n) { return unchanged.sounds.madeThisRun[n] === true })
      // Twenty of the copy's 5 ms ticks, for a write that mustn't come.
      wait(100)
      var keptWrites = unchanged.spy.log.length
      unchanged.sounds.destroy()
      unchanged.spy.destroy()
      fileProc.command = ["sh", "-c", "rm -f -- \"$1/" + names[3] + "\" && touch -- \"$1/" + names[names.length - 1] + "\"", "sh", sounds.folder]
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
      var mended = finished(restarted())
      var stale = "0123456789abcdef0123456789abcdef"
      harness.writeText(stampPath, stale + "\n")
      var redone = finished(restarted())
      harness.writeText(stampPath, stale + "\n")
      var blocked = restarted(names[3])
      tryVerify(function() { return blocked.spy.log.indexOf(names[names.length - 1]) >= 0 }, 15000)
      // Twenty ticks more, for the stamp that mustn't follow.
      wait(100)
      var blockedWrites = blocked.spy.log.slice()
      blocked.sounds.destroy()
      blocked.spy.destroy()
      var stampKept = harness.readFile(stampPath).trim() === stale
      var expected = [names[3], names[names.length - 1], "stamp-" + look].join()
      harness.check("a start writes none of the sounds the cache holds current, only one gone or rewritten since the stamp, and every one after a sound changed, the stamp last, and none when a write failed",
        keptAll && keptWrites === 0 && mended.join() === expected && redone.join() === names.concat(["stamp-" + look]).join()
          && blockedWrites.join() === names.join() && stampKept,
        "kept " + keptAll + ", " + keptWrites + " written | mended " + mended.join() + " | redone " + redone.length + ", last " + redone[redone.length - 1]
          + " | with a failed write " + blockedWrites.length + " written, stamp kept " + stampKept)

      harness.finish()
    }
  }

  Component { id: soundsMaker; Stonks.Sounds {} }
  // A start's files, counting each write on its way to the real ones.
  Component {
    id: spyFiles
    QtObject {
      property var real: null
      property var log: []
      property string failing: ""
      readonly property string folder: real.folder
      readonly property bool made: real.made
      function write(path, data) {
        var name = path.slice(folder.length + 1)
        log.push(name)
        return name !== failing && real.write(path, data)
      }
    }
  }
}
