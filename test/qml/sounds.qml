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
// records what it was asked to play: on by default, the add, remove, and
// undo sounds in each look's voice, the add as its row joins, a replay's
// sound made from its chart and stopped with it, one sound at a time, the
// scrub's chimes by keys and by the pointer, nothing while off, and nothing
// for what happens on its own or for the rest of looking around. HOME and
// curl are scratch.
ShellRoot {
  id: harness

  property int failures: 0

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = find(item.children[i], name)
      if (found) return found
    }
    return item.contentItem ? find(item.contentItem, name) : null
  }

  function findAll(item, name, into) {
    into = into || []
    if (!item) return into
    if (item.objectName === name) into.push(item)
    for (var i = 0; i < item.children.length; i++) findAll(item.children[i], name, into)
    if (item.contentItem) findAll(item.contentItem, name, into)
    return into
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
  function readFile(path) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = path
    var text = String(view.text())
    view.destroy()
    return text
  }
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
  // A chime is any start of a chime's file; every other start is a sound.
  function isChime(e) {
    return /\/chime-(smooth|retro)-\d+\.wav$/.test(e.file)
  }
  function starts() {
    return record().filter(function(e) { return e.what === "start" && !isChime(e) })
  }
  function chimes() {
    return record().filter(function(e) { return e.what === "start" && isChime(e) })
  }
  // A chime's voice and bar, as "retro-3".
  function bar(chime) {
    return chime.file.replace(/^.*\/chime-/, "").replace(/\.wav$/, "")
  }

  readonly property string onGlyph: "\uDB81\uDD7E"
  readonly property string offGlyph: "\uDB81\uDF5F"

  Stonks.Service { id: service }
  Stonks.Updates { id: updates }
  Stonks.Sounds { id: sounds; turnedOn: service.soundsOn; retro: service.retro }
  Component { id: bellMaker; Stonks.Bell {} }
  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service, updates: updates, sounds: sounds } }
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
  Stonks.App { id: app; service: service; updates: updates; sounds: sounds }

  TestCase {
    name: "Sounds"
    when: service.pluginsReady

    function quiet() {
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
    }

    // The stand-in's starts, once `count` of them are in.
    function startsBy(count) {
      tryVerify(function() { return harness.starts().length >= count }, 3000)
      wait(100)
      return harness.starts()
    }

    // The sound file a start played, as the plugin names it.
    function played(start) {
      return start.file.replace(/^.*\/plugin\//, "")
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

    // The replay's sound, as the stand-in kept it, read against the chart
    // it was made from, by what the samples hold and what the chart draws:
    // - pitch: every 25 ms where the chart draws, the pitch read from the
    //   samples is the chart's, within a semitone, nine times in ten:
    //   smooth's from E4 at the chart's floor to E5 at its ceiling along the
    //   line, retro's a pentatonic note per column of its grid, read where
    //   one note holds through the window;
    // - silence: where the chart draws nothing (smooth's breaks, retro's
    //   dark columns), nothing sounds;
    // - ticks: each crossing of the baseline by the drawn line is heard
    //   within 25 ms, and no tick is heard anywhere else: smooth's a burst
    //   at 1760 Hz, retro's noise above 8 kHz, where its band-limited pulse
    //   has nothing. Crossings closer than the tick is long are one.
    function heardAgainst(index, chart, retro) {
      var bytes = new DataView(harness.readBytes(harness.fakeState + "/pw-play." + harness.starts()[index - 1].n + ".wav"))
      var rate = bytes.getUint32(24, true)
      var samples = (bytes.byteLength - 44) / 2
      var s = new Float32Array(samples)
      for (var i = 0; i < samples; i++) s[i] = bytes.getInt16(44 + i * 2, true) / 32768
      var ease = function(u) { return -(Math.cos(Math.PI * u) - 1) / 2 }
      var place = function(t) { return chart.from + (chart.to - chart.from) * ease(Math.min(1, t / 2)) }
      var penta = [440, 493.88, 554.37, 659.25, 739.99, 880, 987.77, 1108.73, 1318.51, 1479.98, 1760]
      var pts = chart.geometry.points, grid = chart.grid
      // The drawn line at `x`: its height, or null across a break, where the
      // chart draws none.
      var lineY = function(x) {
        if (x <= pts[0].x) return pts[0].y
        for (var k = 0; k < pts.length - 1; k++) {
          if (pts[k + 1].x < x) continue
          if (pts[k + 1].brk && x > pts[k].x) return null
          return pts[k].y + (pts[k + 1].y - pts[k].y) * (x - pts[k].x) / Math.max(1e-9, pts[k + 1].x - pts[k].x)
        }
        return pts[pts.length - 1].y
      }
      var column = function(x) { return Math.max(0, Math.min(grid.columns - 1, Math.floor(x * grid.columns))) }
      // What the chart puts at `t` seconds in: a pitch, or 0 where it draws
      // nothing.
      var expected = function(t) {
        if (retro) {
          var row = grid.levels[column(place(t))]
          return row === undefined ? 0 : penta[Math.round((grid.rows - 1 - row) / Math.max(1, grid.rows - 1) * (penta.length - 1))]
        }
        var y = lineY(place(t))
        return y === null ? 0 : 329.63 * Math.pow(2, 1 - y)
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
        // Where the window and 10 ms either side hold one thing: one note,
        // or for smooth, the line or no line.
        var want = expected(t + span / rate / 2)
        var same = function(other) { return retro ? other === want : (other === 0) === (want === 0) }
        if (!same(expected(t - 0.01)) || !same(expected(t + span / rate + 0.01))) continue
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
      // The crossings of the drawn line, from the chart: smooth's no closer
      // than 80 ms, as its tick and the rule allow; retro's at each lit
      // column on the other side from the lit one before it. Nothing
      // crosses where nothing is drawn: a break, a dark column.
      // `every` keeps each one, which a heard tick may be at; `crossings`
      // only those after a gap as long as a tick, which must each be heard.
      var crossings = [], every = [], last = 0, lastCol = -1, lastAt = -1
      for (var c = 0; c <= 2; c += 0.0005) {
        var side = 0
        if (retro) {
          var col = column(place(c))
          if (col === lastCol) continue
          lastCol = col
          if (grid.levels[col] === undefined) { last = 0; continue }
          side = Math.sign(grid.baseRow - grid.levels[col])
        } else {
          var ly = lineY(place(c))
          if (ly === null) { last = 0; continue }
          side = Math.sign(chart.geometry.baselineY - ly)
        }
        if (side && last && side !== last && (retro || c - lastAt > 0.08)) {
          every.push(c)
          if (!crossings.length || c - crossings[crossings.length - 1] > 0.035) crossings.push(c)
          lastAt = c
        }
        if (side) last = side
      }
      // The ticks heard, every 4 ms, where a band's energy jumps: retro's
      // above 8 kHz, where its band-limited pulse has little, past four
      // times its median for 12 ms, as its 30 ms of noise does and a note's
      // 1 ms onset doesn't, and twice and a half what it was 8 ms before;
      // smooth's at 1760 Hz, past a fifth of the tone's own level there,
      // which the tone's third harmonic (0.06 of it, at 587 Hz) never
      // reaches and the tick (0.55) always does, and four times what it was.
      var win = Math.round(0.004 * rate), energy = [], levels = []
      var w8 = 2 * Math.PI * 8000 / rate, c8 = Math.cos(w8), a8 = Math.sin(w8) / 1.414, n8 = 1 + a8
      var x1 = 0, x2 = 0, y1 = 0, y2 = 0, goertzel = 2 * Math.cos(2 * Math.PI * 1760 / rate)
      for (var st = 0; st + win < samples; st += win) {
        var en = 0, q1 = 0, q2 = 0
        for (var m = st; m < st + win; m++) {
          if (retro) {
            var y = ((1 + c8) / 2 * s[m] - (1 + c8) * x1 + (1 + c8) / 2 * x2 + 2 * c8 * y1 - (1 - a8) * y2) / n8
            x2 = x1; x1 = s[m]; y2 = y1; y1 = y
            en += y * y
          } else {
            var q0 = goertzel * q1 - q2 + s[m]
            q2 = q1; q1 = q0
          }
        }
        energy.push(retro ? en : q1 * q1 + q2 * q2 - goertzel * q1 * q2)
        levels.push(rms(st, win))
      }
      var sorted = energy.slice().sort(function(a, b) { return a - b })
      var median = sorted[Math.floor(sorted.length / 2)]
      // The tone's amplitude: its louder windows' RMS over a sine-like
      // wave's 0.72.
      var tone = levels.slice().sort(function(a, b) { return a - b })[Math.floor(levels.length * 0.75)] / 0.72
      var floor = retro ? 4 * median : Math.pow(win / 2 * 0.2 * tone, 2)
      var ticks = []
      for (var w = 2; w < energy.length - 2; w++) {
        var held = !retro || (energy[w + 1] > floor && energy[w + 2] > floor)
        if (energy[w] > floor && held && energy[w] > (retro ? 2.5 : 4) * energy[w - 2] && (!ticks.length || w * win / rate - ticks[ticks.length - 1] > 0.035)) ticks.push(w * win / rate)
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

    // The chart a replay starts on, as the motion hands it to the sounds.
    function capture(body) {
      var seen = {}
      var take = function(from, to) {
        var pixel = harness.findAll(body, "curtain").filter(function(c) { return c.parent.visible })[0]
        seen.chart = { from: from, to: to, geometry: body.motion.geometry, grid: pixel ? pixel.parent.grid : null }
      }
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
        service.soundsOn && icon.text === harness.onGlyph && harness.starts().length === 0, service.soundsOn + "|" + harness.starts().length)

      // The popup by keys, in smooth.
      panel.refocusKeys()
      wait(100)
      // Nothing that happens by itself, and nothing done to look around
      // but the scrub: a refresh and its answers, a range and back, the
      // look and back, the change, the selection, the key sheet, a row's
      // chart. The scrub's key steps each strike a chime.
      var quietKeys = [Qt.Key_R, Qt.Key_Left, Qt.Key_Left, Qt.Key_Right, Qt.Key_Escape, Qt.Key_BracketRight, Qt.Key_BracketLeft,
        Qt.Key_S, Qt.Key_S, Qt.Key_C, Qt.Key_C, Qt.Key_C, Qt.Key_Down, Qt.Key_Up, Qt.Key_Question, Qt.Key_Question, Qt.Key_2, Qt.Key_1]
      quietKeys.forEach(function(key) { keyClick(key); wait(60) })
      service.refresh()
      quiet()
      wait(500)
      var stepChimes = harness.chimes().map(harness.bar)
      harness.check("with sounds on, a refresh, its answers, a range, the look, the change, the selection, the sheet, and a row's chart play nothing, and the scrub's three key steps strike three of smooth's chimes",
        harness.starts().length === 0 && stepChimes.length === 3 && stepChimes.every(function(b) { return /^smooth-([0-9]|10)$/.test(b) }),
        JSON.stringify(harness.record()))

      // x, u, and an add through search: each its own sound, in smooth's
      // voice, as a notification, at a short latency.
      keyClick(Qt.Key_X)
      var removed = startsBy(1)
      keyClick(Qt.Key_U)
      var undone = startsBy(2)
      keyClick(Qt.Key_A)
      wait(50)
      keyClick(Qt.Key_S)
      keyClick(Qt.Key_H)
      tryVerify(function() { return body.adding && body.search.results.length > 1 }, 3000)
      var library = service.library.length
      keyClick(Qt.Key_Return)
      // SHOP's first fetch fails for good: its row joins saying so, and the
      // add is heard then.
      quiet()
      var added = startsBy(3)
      harness.check("in the popup, x plays the removal, u its undo, and an add from search the add, each in smooth's voice",
        played(removed[0]) === "sounds/smooth/remove.wav" && played(undone[1]) === "sounds/smooth/undo.wav"
          && played(added[2]) === "sounds/smooth/add.wav" && service.library.length === library + 1,
        harness.starts().map(played).join(", "))
      harness.check("each plays through pw-play as a notification, at 20 ms",
        harness.starts().every(function(s) { return s.args === "--media-role Notification --latency 20ms" }), harness.starts()[0].args)

      // p: a replay heard, made from the chart as it starts; left to run,
      // it plays to its end.
      tryVerify(function() { return !body.chartLoading }, 5000)
      var watch = capture(body)
      keyClick(Qt.Key_P)
      var replayed = startsBy(4)
      watch.done()
      tryVerify(function() { return !body.motion.replayRunning }, 4000)
      tryVerify(function() { return endOf(4) !== "" }, 3000)
      var smoothHeard = heardAgainst(4, watch.seen.chart, false)
      harness.check("p plays the replay's sound, written whole before it plays, and a replay left to run plays to its end",
        replayed[3].file === sounds.replayPath && endOf(4) === "ended", replayed[3].file + "|" + endOf(4))
      harness.check("smooth's replay is the chart's line: its pitch follows the line's height as the replay moves along it, a tick at each crossing of the close",
        smoothHeard.pitch.ok && smoothHeard.ticks.ok && smoothHeard.ticks.count > 0, smoothHeard.pitch.detail + " | " + smoothHeard.ticks.detail)

      // Tokyo's day of 19 October, whose line stops for lunch below the
      // close and starts again above it, in both looks: the replay is silent
      // across the break, where smooth draws no line and retro dark columns,
      // and ticks only where what is drawn crosses, not at lunch's end.
      harness.writeText(harness.fakeState + "/overnight.set", "demo-2026-10-19-1146\n")
      service.addSymbol("7203.T")
      quiet()
      harness.writeText(harness.fakeState + "/overnight.set", "")
      service.feature("7203.T")
      tryVerify(function() { return body.featuredSymbol === "7203.T" && !body.chartLoading }, 5000)
      var lunch = [false, true].map(function(retro) {
        service.persist({ style: retro ? "retro" : "smooth" })
        wait(400)
        var tokyo = capture(body)
        var at = harness.starts().length
        keyClick(Qt.Key_P)
        startsBy(at + 1)
        tokyo.done()
        tryVerify(function() { return endOf(at + 1) !== "" }, 4000)
        var heard = heardAgainst(at + 1, tokyo.seen.chart, retro)
        return { ok: heard.pitch.ok && heard.silence.ok && /^[1-9]/.test(heard.silence.detail) && heard.ticks.ok,
          detail: (retro ? "retro: " : "smooth: ") + heard.pitch.detail + " | " + heard.silence.detail + " | " + heard.ticks.detail }
      })
      service.persist({ style: "smooth" })
      harness.check("a replay of Tokyo's day is silent across lunch, where the chart draws nothing, and ticks only where what is drawn crosses, smooth and retro",
        lunch[0].ok && lunch[1].ok, lunch[0].detail + " || " + lunch[1].detail)
      // The chimes over Tokyo's lunch, in both looks: the scrub moved into
      // the break, where the chart draws nothing, strikes nothing; moved on
      // to the afternoon's line, it strikes once.
      var hero = harness.findWith(body, "pixelGrid")
      var lunchChimes = [false, true].map(function(retro) {
        service.persist({ style: retro ? "retro" : "smooth" })
        wait(300)
        var pts = body.motion.geometry.points
        var gap = null
        for (var p = 1; p < pts.length && !gap; p++) if (pts[p].brk) gap = [pts[p - 1].x, pts[p].x]
        hero.scrubRequested(gap[0] - 0.02)
        wait(100)
        var struck = harness.chimes().length
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
        wait(150)
        var afterBreak = harness.chimes().length - struck - inBreak
        body.endScrub()
        return { ok: inBreak === 0 && afterBreak === 1 && landed,
          detail: (retro ? "retro: " : "smooth: ") + inBreak + " in the break, " + afterBreak + " after, landed on the first print " + landed }
      })
      service.persist({ style: "smooth" })
      harness.check("the scrub over Tokyo's lunch strikes nothing, and the afternoon's line strikes again, smooth and retro",
        lunchChimes[0].ok && lunchChimes[1].ok, lunchChimes[0].detail + " || " + lunchChimes[1].detail)
      service.removeSymbol("7203.T")
      service.feature("MSFT")
      quiet()
      tryVerify(function() { return body.featuredSymbol === "MSFT" && !body.chartLoading }, 5000)
      wait(400)

      // A replay's sound stops with the replay: Esc, a row's chart, the
      // popup closing. And one sound at a time: x mid-replay cuts it.
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
      cut(function() { keyClick(Qt.Key_3) })
      cut(function() { panel.close(); wait(300) })
      harness.check("a replay's sound stops with the replay: Esc, another row's chart, and closing the popup", cuts.join(",") === "stopped,stopped,stopped", cuts.join(","))
      panel.open()
      tryVerify(function() { return body.surfaceOpen && !body.chartLoading }, 5000)
      panel.refocusKeys()
      wait(100)
      var before = harness.starts().length
      keyClick(Qt.Key_P)
      startsBy(before + 1)
      keyClick(Qt.Key_X)
      var after = startsBy(before + 2)
      tryVerify(function() { return endOf(before + 1) !== "" }, 3000)
      harness.check("one sound at a time: x during a replay stops the replay's sound and plays the removal",
        endOf(before + 1) === "stopped" && played(after[before + 1]) === "sounds/smooth/remove.wav", endOf(before + 1) + "|" + played(after[before + 1]))
      keyClick(Qt.Key_U)
      startsBy(before + 3)
      quiet()

      // Shift+S: off, saved, the speaker muted, and nothing plays; a replay
      // playing stops. Then x, u, an add, and p play nothing.
      before = harness.starts().length
      keyClick(Qt.Key_P)
      startsBy(before + 1)
      keyClick("S", Qt.ShiftModifier)
      tryVerify(function() { return endOf(before + 1) !== "" }, 3000)
      tryVerify(function() { var f = file(); return !!f && f.sounds === false }, 3000)
      harness.check("Shift+S turns sounds off: saved, the speaker muted, the replay playing stopped",
        !service.soundsOn && icon.text === harness.offGlyph && endOf(before + 1) === "stopped", service.soundsOn + "|" + endOf(before + 1))
      before = harness.starts().length
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_X)
      wait(100)
      keyClick(Qt.Key_U)
      wait(100)
      body.acceptSymbol("SPY")
      quiet()
      keyClick(Qt.Key_P)
      wait(2500)
      harness.check("with sounds off, x, u, an add, and p play nothing", harness.starts().length === before, JSON.stringify(harness.starts().slice(before)))
      service.removeSymbol("SPY")

      // Shift+S again: on, saved, and the add sound once, so you hear the level.
      keyClick("S", Qt.ShiftModifier)
      var onAgain = startsBy(before + 1)
      tryVerify(function() { var f = file(); return !!f && f.sounds === true }, 3000)
      harness.check("Shift+S turns sounds back on, saved, and plays the add sound once",
        service.soundsOn && icon.text === harness.onGlyph && onAgain.length === before + 1 && played(onAgain[before]) === "sounds/smooth/add.wav",
        harness.starts().slice(before).map(played).join(", "))

      // An add confirmed before its preview has answered: SHOP.TO's day held
      // back, Enter on it as soon as it is chosen. While its answer is held,
      // the header names it as the chart on its way, as the preview did, no
      // row stands for it, and nothing plays; let through, its row joins and
      // the add is heard then. Found in the slow walk of 1.0.2: the hero
      // went back to the stock before the add, named by nothing, and the add
      // sounded at Enter.
      before = harness.starts().length
      harness.hold(true, "SHOP.TO.quote.hold")
      tryVerify(function() { return !fileProc.running }, 2000)
      keyClick(Qt.Key_A)
      wait(50)
      keyClick(Qt.Key_S)
      keyClick(Qt.Key_H)
      tryVerify(function() { return body.adding && body.search.results.length > 1 }, 3000)
      keyClick(Qt.Key_Down)
      tryVerify(function() { return body.previewSymbol === "SHOP.TO" }, 2000)
      keyClick(Qt.Key_Return)
      wait(50)
      var header = harness.find(body, "statusText")
      for (var t = 0; t < 2000 && header.text !== "LOADING SHOP.TO"; t += 20) wait(20)
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
      wait(300)

      // The window by the pointer, in retro, its look picked with a click,
      // on AAPL's day, the popup's failed add gone.
      service.library.filter(function(s) { return ["AAPL", "MSFT", "NVDA"].indexOf(s) < 0 }).forEach(function(s) { service.removeSymbol(s) })
      service.feature("AAPL")
      app.open("{}")
      var win = app.testBody
      tryVerify(function() { return win && win.surfaceOpen && !win.chartLoading && win.featuredSymbol === "AAPL" }, 5000)
      // Tall enough for every row, so each is in sight to click.
      app.testWindow.implicitHeight = win.chromeHeight + 7 * win.rowPitch
      wait(300)
      mouseMove(win, 1, 1)
      wait(50)
      before = harness.starts().length
      var look = harness.find(win, "lookToggle")
      mouseClick(look, look.width / 2, look.height / 2)
      tryVerify(function() { return service.retro }, 2000)
      // Looking around by the pointer: the chart scrubbed, a range and
      // back, and a row's chart.
      var chart = win.chartItem
      var scrubbed = false
      for (var x = 0.1; x < 0.9; x += 0.1) {
        mouseMove(chart, chart.width * x, chart.height / 2)
        wait(50)
        if (win.scrubT !== 0) scrubbed = true
      }
      mouseMove(win, 1, 1)
      var tokens = harness.findAll(win, "rangeToken")
      mouseClick(tokens[1], tokens[1].width / 2, tokens[1].height / 2)
      wait(300)
      mouseClick(tokens[0], tokens[0].width / 2, tokens[0].height / 2)
      tryVerify(function() { return service.range === "1D" && !win.chartLoading }, 5000)
      var rows = win.watchlist.displayedSymbols
      var second = win.watchlist.rowItem(rows[1])
      mouseClick(second, second.width / 2, second.height / 2)
      wait(300)
      harness.check("in the window, a click on the look, a scrub by the pointer, a range and back, and a row's chart play no sound but the scrub's chimes",
        scrubbed && harness.starts().length === before, scrubbed + "|" + JSON.stringify(harness.starts().slice(before)))

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
      wait(100)
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
      mouseClick(speaker, speaker.width / 2, speaker.height / 2)
      tryVerify(function() { return !service.soundsOn }, 2000)
      wait(300)
      var chimesOff = harness.chimes().length
      sweep(chart.width * 0.05, chart.width * 0.9, { last: -1, changes: 0, crossed: [] })
      mouseMove(win, 1, 1)
      wait(300)
      var offSilent = harness.starts().length === before && harness.chimes().length === chimesOff && winIcon.text === harness.offGlyph
      mouseClick(speaker, speaker.width / 2, speaker.height / 2)
      var clicked = startsBy(before + 1)
      harness.check("a click on the speaker turns sounds off, silently, and on again, with the add sound once in retro's voice",
        offSilent && service.soundsOn && winIcon.text === harness.onGlyph && clicked.length === before + 1 && played(clicked[before]) === "sounds/retro/add.wav",
        offSilent + "|" + harness.starts().slice(before).map(played).join(", "))

      // A right-click removes a row, a click on the footer's note takes it
      // back, and an add through search's ADD: retro's sounds.
      rows = win.watchlist.displayedSymbols
      var row = win.watchlist.rowItem(rows[rows.length - 1])
      mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton)
      startsBy(before + 2)
      var footer = harness.find(win, "footer")
      mouseClick(footer, footer.width / 2, footer.height / 2)
      startsBy(before + 3)
      quiet()
      mouseClick(footer, footer.width / 2, footer.height / 2)
      tryVerify(function() { return win.adding }, 2000)
      keyClick(Qt.Key_S)
      keyClick(Qt.Key_H)
      tryVerify(function() { return win.search.results.length > 1 }, 3000)
      wait(100)
      var result = harness.findAll(win.search, "searchResult").filter(function(r) { return r.modelData.symbol === "SHOP.TO" })[0]
      var add = harness.find(result, "searchAdd")
      var held = service.library.slice()
      mouseClick(add, add.width / 2, add.height / 2)
      var mouseSounds = startsBy(before + 4).slice(before + 1).map(played)
      quiet()
      harness.check("in the window, a right-click on a row, a click on the footer's undo, and a click on a result's ADD play retro's removal, undo, and add",
        mouseSounds.join(", ") === "sounds/retro/remove.wav, sounds/retro/undo.wav, sounds/retro/add.wav", mouseSounds.join(", "))
      // The add lands; then a click on MSFT's row shows its chart, a busy
      // US day, every column lit, to replay.
      tryVerify(function() { return win.featuredSymbol === "SHOP.TO" && !win.chartLoading }, 8000)
      var msft = win.watchlist.rowItem("MSFT")
      mouseClick(msft, msft.width / 2, msft.height / 2)
      tryVerify(function() { return win.featuredSymbol === "MSFT" && !win.chartLoading && win.animal.kind !== "" }, 5000)
      wait(400)

      // A click on the animal: retro's replay, its notes the chart's
      // columns; a click on another row cuts it.
      before = harness.starts().length
      var animal = harness.find(win, "animalToggle")
      watch = capture(win)
      mouseClick(animal, animal.width / 2, animal.height / 2)
      startsBy(before + 1)
      watch.done()
      tryVerify(function() { return endOf(before + 1) !== "" }, 4000)
      var retroHeard = heardAgainst(before + 1, watch.seen.chart, true)
      harness.check("retro's replay is the chart's columns: a note per lit column, its pitch the column's height, silent over dark ones, a tick at each crossing",
        retroHeard.pitch.ok && retroHeard.silence.ok && retroHeard.ticks.ok,
        retroHeard.pitch.detail + " | " + retroHeard.silence.detail + " | " + retroHeard.ticks.detail)

      // Two surfaces, one player: the popup's replay, cut by the window's,
      // whose sound then plays to its end through the popup's close, which
      // stops the popup's replay and with it only the popup's own sound.
      panel.open()
      tryVerify(function() { return body.surfaceOpen && !body.chartLoading }, 5000)
      wait(300)
      body.replay()
      startsBy(before + 2)
      mouseClick(animal, animal.width / 2, animal.height / 2)
      startsBy(before + 3)
      var popupCut = endOf(before + 2)
      var popupReplaying = body.motion.replayRunning
      panel.close()
      wait(150)
      var playing = endOf(before + 3) === "" && win.motion.replayRunning
      tryVerify(function() { return endOf(before + 3) !== "" }, 4000)
      harness.check("the window's replay cuts the popup's sound, and the popup closing mid-replay leaves the window's playing to its end",
        popupCut === "stopped" && popupReplaying && playing && endOf(before + 3) === "ended",
        popupCut + "|" + popupReplaying + "|" + playing + "|" + endOf(before + 3))
      before++

      app.testKeyCatcher.forceActiveFocus()
      mouseClick(animal, animal.width / 2, animal.height / 2)
      startsBy(before + 3)
      rows = win.watchlist.displayedSymbols
      var other = win.watchlist.rowItem(rows[0] === service.featuredSymbol ? rows[1] : rows[0])
      mouseClick(other, other.width / 2, other.height / 2)
      tryVerify(function() { return endOf(before + 3) !== "" }, 3000)
      harness.check("a click on another row stops the replay's sound with the replay", endOf(before + 3) === "stopped", endOf(before + 3))

      // The market's bell, in retro's voice: as the clock passes the open
      // or the close of the market of the stock last looked at, once, a
      // Stonks started a moment before it included; never late, after a
      // long step of the clock; never twice, with the clock set back across
      // it; never while an app records from a microphone (the stand-in
      // pw-dump's nodes); never with sounds off. Each pass is a Stonks
      // started at its first moment.
      app.close()
      service.feature("AAPL")
      tryVerify(function() { return !!service.quotes.AAPL && service.featuredSymbol === "AAPL" }, 5000)
      var reg = service.quotes.AAPL.session.regular
      var bells = function() { return harness.starts().filter(function(s) { return played(s) === "sounds/retro/bell.wav" }).length }
      var pass = function(moments) {
        var rung = bells()
        service.now = moments[0]
        var bell = bellMaker.createObject(harness, { service: service, sounds: sounds })
        // Each moment its own minute's tick: a bell rung has played before
        // the next, so a second ring isn't lost to the first's check.
        moments.slice(1).forEach(function(t) {
          service.now = t
          wait(300)
        })
        bell.destroy()
        return bells() - rung
      }
      var micOn = JSON.stringify([{ type: "PipeWire:Interface:Node", info: { state: "running",
        props: { "media.class": "Stream/Input/Audio", "application.name": "a call" } } }])
      var meterOn = JSON.stringify([{ type: "PipeWire:Interface:Node", info: { state: "running",
        props: { "media.class": "Stream/Input/Audio", "stream.capture.sink": true } } }])
      var rang = [pass([reg.start - 30, reg.start + 30]), pass([reg.start - 3600, reg.start + 60]),
        pass([reg.start - 2, reg.start - 1, reg.start, reg.start - 1, reg.start, reg.start + 1])]
      harness.writeText(harness.fakeState + "/pw-dump.json", micOn)
      rang.push(pass([reg.end - 30, reg.end + 30]))
      harness.writeText(harness.fakeState + "/pw-dump.json", meterOn)
      rang.push(pass([reg.end - 30, reg.end + 30]))
      service.persist({ sounds: false })
      rang.push(pass([reg.start - 30, reg.start + 30]))
      service.now = Math.floor(Date.now() / 1000)
      harness.check("the bell rings at the open in retro's voice, a moment after Stonks starts too, not late, not twice with the clock set back, not while a microphone records though a level meter may run, and not with sounds off",
        rang.join(",") === "1,0,1,0,1,0", rang.join(","))

      console.log("SOUNDS DONE")
      done.exitCode = harness.failures ? 1 : 0
      done.start()
    }
  }

  HarnessExit { id: done; interval: 100 }
}
