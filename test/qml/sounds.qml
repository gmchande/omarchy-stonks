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
// undo sounds in each look's voice, a replay's sound made from its chart and
// stopped with it, one sound at a time, nothing while off, and nothing for
// what happens on its own or for looking around. HOME and curl are scratch.
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

  // The stand-in's record, a line each: "start" with the file it was asked
  // to play and its other arguments, "stopped", or "ended".
  function record() {
    return readFile(fakeState + "/pw-play.log").split("\n").filter(function(line) { return line !== "" }).map(function(line) {
      var words = line.split(" ")
      return { what: words[0], ms: Number(words[1]), args: words.slice(2, -1).join(" "), file: words[words.length - 1] }
    })
  }
  function starts() {
    return record().filter(function(e) { return e.what === "start" })
  }

  readonly property string onGlyph: "\uDB81\uDD7E"
  readonly property string offGlyph: "\uDB81\uDF5F"

  Stonks.Service { id: service }
  Stonks.Updates { id: updates }
  Stonks.Sounds { id: sounds; turnedOn: service.soundsOn; retro: service.retro }
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

    // What follows the replay started at `index` (1-based, the stand-in's
    // count): "stopped" or "ended", or "" while it plays.
    function endOf(index) {
      var seen = 0
      var events = harness.record()
      for (var i = 0; i < events.length; i++) {
        if (events[i].what === "start") seen++
        else if (seen === index) return events[i].what
      }
      return ""
    }

    // Whether the replay's sound, as the stand-in kept it, is the chart's
    // line: its pitch every 25 ms, read from the samples, is the one the
    // chart puts there, within a semitone, nine times in ten. Smooth's runs
    // from E4 at the chart's floor to E5 at its ceiling along the line;
    // retro's steps a pentatonic note per column of its grid, judged where
    // one note holds through the window read.
    function followsChart(index, chart, retro) {
      var bytes = new DataView(harness.readBytes(harness.fakeState + "/pw-play." + index + ".wav"))
      var rate = bytes.getUint32(24, true)
      var samples = (bytes.byteLength - 44) / 2
      var at = function(i) { return bytes.getInt16(44 + i * 2, true) }
      var ease = function(u) { return -(Math.cos(Math.PI * u) - 1) / 2 }
      var place = function(t) { return chart.from + (chart.to - chart.from) * ease(Math.min(1, t / 2)) }
      var penta = [440, 493.88, 554.37, 659.25, 739.99, 880, 987.77, 1108.73, 1318.51, 1479.98, 1760]
      var pts = chart.geometry.points
      var lineY = function(x) {
        if (x <= pts[0].x) return pts[0].y
        for (var k = 0; k < pts.length - 1; k++)
          if (pts[k + 1].x >= x) return pts[k].y + (pts[k + 1].y - pts[k].y) * (x - pts[k].x) / Math.max(1e-9, pts[k + 1].x - pts[k].x)
        return pts[pts.length - 1].y
      }
      var noteAt = function(x) {
        var grid = chart.grid
        var col = Math.max(0, Math.min(grid.columns - 1, Math.floor(x * grid.columns)))
        for (var c = col; c >= 0; c--) {
          if (grid.levels[c] !== undefined)
            return penta[Math.round((grid.rows - 1 - grid.levels[c]) / Math.max(1, grid.rows - 1) * (penta.length - 1))]
        }
        return 0
      }
      var expected = function(t) { return retro ? noteAt(place(t)) : 329.63 * Math.pow(2, 1 - lineY(place(t))) }
      // The period, by autocorrelation over 12 ms: the shortest lag within
      // a tenth of the best, so an octave down never wins.
      var span = Math.round(0.012 * rate)
      var pitch = function(start) {
        var n = span, scores = [], best = 0
        for (var lag = Math.floor(rate / 2000); lag <= Math.ceil(rate / 250); lag++) {
          var s = 0, e = 0
          for (var i = 0; i < n; i++) { s += at(start + i) * at(start + i + lag); e += at(start + i) * at(start + i) }
          scores.push({ lag: lag, score: e > 0 ? s / e : 0 })
          if (s / e > best) best = s / e
        }
        for (var j = 1; j < scores.length - 1; j++) {
          var sc = scores[j]
          if (sc.score >= best * 0.9 && sc.score >= scores[j - 1].score && sc.score >= scores[j + 1].score) return rate / sc.lag
        }
        return 0
      }
      var hits = 0, total = 0, misses = []
      for (var t = 0.15; t < 1.9; t += 0.025) {
        var want = expected(t + span / rate / 2)
        if (retro && (expected(t) !== want || expected(t + span / rate) !== want)) continue
        var heard = pitch(Math.round(t * rate))
        total++
        if (heard > 0 && want > 0 && Math.abs(12 * Math.log(heard / want) / Math.LN2) < 1) hits++
        else misses.push(t.toFixed(3) + "s " + Math.round(heard) + " for " + Math.round(want))
      }
      return { ok: samples > 2 * rate && total >= 20 && hits >= total * 0.9, detail: hits + "/" + total + " windows; " + misses.slice(0, 5).join(", ") }
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
      // Nothing that happens by itself, and nothing done to look around:
      // a refresh and its answers, the scrub, a range and back, the look and
      // back, the change, the selection, the key sheet, a row's chart.
      var quietKeys = [Qt.Key_R, Qt.Key_Left, Qt.Key_Left, Qt.Key_Right, Qt.Key_Escape, Qt.Key_BracketRight, Qt.Key_BracketLeft,
        Qt.Key_S, Qt.Key_S, Qt.Key_C, Qt.Key_C, Qt.Key_C, Qt.Key_Down, Qt.Key_Up, Qt.Key_Question, Qt.Key_Question, Qt.Key_2, Qt.Key_1]
      quietKeys.forEach(function(key) { keyClick(key); wait(60) })
      service.refresh()
      quiet()
      wait(500)
      harness.check("with sounds on, a refresh, its answers, a scrub, a range, the look, the change, the selection, the sheet, and a row's chart play nothing",
        harness.starts().length === 0, JSON.stringify(harness.record()))

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
      var added = startsBy(3)
      quiet()
      harness.check("in the popup, x plays the removal, u its undo, and an add from search the add, each in smooth's voice",
        played(removed[0]) === "sounds/smooth/remove.wav" && played(undone[1]) === "sounds/smooth/undo.wav"
          && played(added[2]) === "sounds/smooth/add.wav" && service.library.length === library + 1,
        harness.starts().map(played).join(", "))
      harness.check("each plays through pw-play as a notification, at 20 ms",
        harness.starts().every(function(s) { return s.args === "--media-role Notification --latency 20ms" }), harness.starts()[0].args)

      // p: a replay heard, made from the chart as it starts; left to run,
      // it plays to its end.
      var featured = service.featuredSymbol
      tryVerify(function() { return !body.chartLoading }, 5000)
      var watch = capture(body)
      keyClick(Qt.Key_P)
      var replayed = startsBy(4)
      watch.done()
      tryVerify(function() { return !body.motion.replayRunning }, 4000)
      tryVerify(function() { return endOf(4) !== "" }, 3000)
      var smoothHeard = followsChart(4, watch.seen.chart, false)
      harness.check("p plays the replay's sound, written whole before it plays, and a replay left to run plays to its end",
        replayed[3].file === sounds.replayPath && endOf(4) === "ended", replayed[3].file + "|" + endOf(4))
      harness.check("smooth's replay is the chart's line: its pitch follows the line's height as the replay moves along it", smoothHeard.ok, smoothHeard.detail)

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
      harness.check("in the window, a click on the look, a scrub by the pointer, a range and back, and a row's chart play nothing",
        scrubbed && harness.starts().length === before, scrubbed + "|" + JSON.stringify(harness.starts().slice(before)))

      // The speaker: a click turns sounds off, silently, and on, with the
      // add sound once, now in retro's voice.
      var speaker = harness.find(win, "soundToggle")
      var winIcon = harness.find(win, "soundIcon")
      mouseClick(speaker, speaker.width / 2, speaker.height / 2)
      tryVerify(function() { return !service.soundsOn }, 2000)
      wait(300)
      var offSilent = harness.starts().length === before && winIcon.text === harness.offGlyph
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
      // The add lands: its chart, a Toronto listing's day, is the one to replay.
      tryVerify(function() { return win.featuredSymbol === "SHOP.TO" && !win.chartLoading }, 8000)

      // A click on the animal: retro's replay, its notes the chart's
      // columns; a click on another row cuts it.
      tryVerify(function() { return !win.chartLoading && win.animal.kind !== "" }, 5000)
      before = harness.starts().length
      var animal = harness.find(win, "animalToggle")
      watch = capture(win)
      mouseClick(animal, animal.width / 2, animal.height / 2)
      startsBy(before + 1)
      watch.done()
      tryVerify(function() { return endOf(before + 1) !== "" }, 4000)
      var retroHeard = followsChart(before + 1, watch.seen.chart, true)
      harness.check("retro's replay is the chart's columns: a note per column, its pitch the column's height", retroHeard.ok, retroHeard.detail)
      mouseClick(animal, animal.width / 2, animal.height / 2)
      startsBy(before + 2)
      var running = win.motion.replayRunning
      rows = win.watchlist.displayedSymbols
      var target = rows[0] === service.featuredSymbol ? rows[1] : rows[0]
      var other = win.watchlist.rowItem(target)
      mouseClick(other, other.width / 2, other.height / 2)
      wait(100)
      var featuredNow = service.featuredSymbol
      tryVerify(function() { return endOf(before + 2) !== "" }, 3000)
      harness.check("a click on another row stops the replay's sound with the replay", endOf(before + 2) === "stopped",
        endOf(before + 2) + "|" + running + "|" + target + "|" + featuredNow + "|" + rows.join(","))

      app.close()
      console.log("SOUNDS DONE")
      done.exitCode = harness.failures ? 1 : 0
      done.start()
    }
  }

  HarnessExit { id: done; interval: 100 }
}
