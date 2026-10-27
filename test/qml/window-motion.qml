import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// The real App and Service with real keys and pointer. The actions chapter
// keeps replay, selection and market-state outcomes in all.sh; charts and
// rows judge rendered motion and positions in the maintainer's review kit.
// HOME and curl are scratch.
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

  function finish() {
    console.log("WINDOW MOTION DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }
  // The hero chart's or the body's rendered frames, for frames.js.
  FrameGrab { id: grab }
  // The hero's figures' frames beside the chart's, as the dim lifts.
  FrameGrab { id: heroGrab }
  // A busy machine, on purpose: from the draw-in's start, each render first
  // holds the GUI thread for 0.3 of the time since, until 200 ms in. Renders
  // and the animation clock share that thread, so the clock ticks later and
  // later and each render shows a moment older than the render: frames
  // timed as they render, not by their moment, read the 320 ms draw-in as
  // about 420. Its handler is connected before the grab's, so it runs first.
  property real busySince: 0
  Connections {
    id: busy
    target: null
    function onAfterAnimating() {
      if (!harness.busySince) return
      var since = Date.now() - harness.busySince
      if (since > 200) return
      var until = Date.now() + since * 0.3
      while (Date.now() < until) {}
    }
  }
  // Hold AAPL's history answer back, and let it go (see the fake curl).
  Process { id: holdAapl; command: ["touch", Quickshell.env("STONKS_FAKE_STATE") + "/AAPL.history.hold"] }
  Process { id: releaseAapl; command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/AAPL.history.hold"] }
  // AAPL's day cut at noon, and back (see the fake curl's overnight.set).
  Process { id: noonAapl; command: ["sh", "-c", "echo aapl-noon > \"$0/overnight.set\"", Quickshell.env("STONKS_FAKE_STATE")] }
  Process { id: wholeAapl; command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/overnight.set"] }
  Process { id: quoteFile }
  // LATE's quote failing, and answering again (see the fake curl).
  Process { id: lateDown; command: ["touch", Quickshell.env("STONKS_FAKE_STATE") + "/LATE.down"] }
  Process { id: lateUp; command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/LATE.down"] }

  TestCase {
    name: "WindowMotion"
    when: service.pluginsReady

    // Waits up to ms for fn to hold and returns whether it does, so the
    // check that reads it is the one that fails.
    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 20) wait(20)
      return fn()
    }

    // The empty plot of `body`'s chart as it is now, on the grab's own
    // ground, saved as `name`-plot.ppm: its ink layers hidden and nothing
    // revealed, the baseline and the grid only, whatever the clip does. A
    // draw-in's ink is read against it (frames.js `plot=`), so one that
    // starts part drawn reads as part drawn, a failure, and is never taken
    // for too few frames and filmed again. Found in Codex's reviews of #33:
    // read against the first frame after the mark, ink already there was
    // taken for the plot. Call it after grab.end(), before grab.judge(),
    // which takes the ground away.
    function emptyPlot(body, name) {
      var path = Quickshell.env("STONKS_FRAMES") + "/" + name + "-plot.ppm"
      var saved = false
      var inks = []
      var findInks = function(item) {
        if (item.objectName === "ink") inks.push(item)
        for (var c = 0; c < item.children.length; c++) findInks(item.children[c])
      }
      findInks(body.chartItem)
      var reveal = body.motion.reveal
      inks.forEach(function(layer) { layer.visible = false })
      body.motion.reveal = 0
      body.chartItem.grabToImage(function(result) { result.saveToFile(path); saved = true })
      tryVerify(function() { return saved }, 3000)
      body.motion.reveal = reveal
      inks.forEach(function(layer) { layer.visible = true })
      return path
    }

    // `symbol`'s quote as the next session's: every time in it a day later.
    function nextDay(symbol) {
      var shift = function(value, key) {
        if (Array.isArray(value)) return value.map(function(v) { return shift(v, "") })
        if (value && typeof value === "object") {
          var out = {}
          for (var k in value) out[k] = shift(value[k], k)
          return out
        }
        return typeof value === "number" && ["t", "start", "end", "marketTime"].indexOf(key) >= 0 ? value + 86400 : value
      }
      var next = Object.assign({}, service.testFeed.quotes)
      next[symbol] = shift(service.quotes[symbol], "")
      service.testFeed.quotes = next
    }

    // The six symbols these flows start from, in manual order, `featured`
    // on `range`, the window tall enough for every row.
    function sixRows(body, featured, range) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      six.forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
      service.setManualOrder(six.concat(service.library.filter(function(s) { return six.indexOf(s) < 0 })))
      service.persist({ order: "manual", featured: featured })
      service.setRange(range)
      mouseMove(body, 1, 1)
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 7 * body.rowPitch
      app.open("{}")
      wait(200)
    }

    // The day's scrub and a new session, and the hero's change as a target.
    function dayActions(body, watchlist, keys) {
      var quotesBefore = service.testFeed.quotes
      service.setRange("1D")
      service.feature("AAPL")
      wait(400)

      // A refresh that brings the next session ends a scrub or a replay on
      // the day before: by keys in smooth, a replay in retro. Found in the
      // transition audit (data 9): the scrub stayed on a time the new day
      // does not have, reading the previous close at 0.00%.
      keys.forceActiveFocus()
      for (var n = 0; n < 3; n++) keyClick(Qt.Key_Left)
      var scrubbed = body.scrubT !== 0
      nextDay("AAPL")
      var scrubEnded = scrubbed + "," + (body.scrubT === 0)
      service.persist({ style: "retro" })
      wait(100)
      keyClick(Qt.Key_P)
      wait(300)
      var replaying = body.motion.replayRunning && body.scrubT !== 0
      nextDay("AAPL")
      var replayEnded = replaying + "," + (!body.motion.replayRunning && body.scrubT === 0)
      service.testFeed.quotes = quotesBefore
      harness.check("the next session ends the day's scrub and replay, smooth and retro",
        scrubEnded === "true,true" && replayEnded === "true,true", scrubEnded + " | " + replayEnded)

      // So does a range's: a refetch whose history no longer covers the bar
      // a replay has reached ends the replay, not only its scrub, in smooth
      // and in retro. Found in the review of the transitions branch: the
      // replay ran on, jumping to another date.
      service.setRange("1W")
      within(5000, function() { return body.historyShown && !body.chartLoading })
      var laterWeek = function() {
        var next = Object.assign({}, service.testHistoryFeed.entries)
        var entry = next["AAPL|1W"]
        var history = Object.assign({}, entry.history)
        history.bars = entry.history.bars.map(function(bar) { return Object.assign({}, bar, { t: bar.t + 30 * 86400 }) })
        next["AAPL|1W"] = Object.assign({}, entry, { history: history })
        service.testHistoryFeed.entries = next
      }
      var rangeReplay = function(look) {
        service.persist({ style: look })
        wait(100)
        body.replay()
        wait(300)
        var replaying = body.motion.replayRunning && body.scrubT !== 0
        laterWeek()
        wait(100)
        return replaying + "," + (!body.motion.replayRunning && body.scrubT === 0)
      }
      var inSmooth = rangeReplay("smooth")
      var inRetro = rangeReplay("retro")
      service.persist({ style: "smooth" })
      service.refresh()
      within(5000, function() { return !service.testHistoryFeed.busy && service.histories["AAPL|1W"].status === "ok" })
      service.setRange("1D")
      within(2000, function() { return !body.chartLoading })
      harness.check("a refetch that no longer covers a range replay ends it, in smooth and in retro",
        inSmooth === "true,true" && inRetro === "true,true", inSmooth + " | " + inRetro)

      // The hero's change is a target only where a click changes it: the
      // day's change, not a range's, which is always its percentage. On 1W in
      // smooth and 1M in retro, then the day. Found in the transition audit
      // (look 1): a click on the range's figure changed only the rows.
      var clickChange = function(range, look) {
        service.persist({ style: look })
        service.setRange(range)
        within(5000, function() { return range === "1D" ? !!body.featuredQuote : body.historyShown })
        wait(100)
        var change = harness.find(body, "changeText")
        var mode = service.changeMode
        mouseClick(change, change.width / 2, change.height / 2)
        wait(50)
        var changed = service.changeMode !== mode
        service.persist({ changeMode: "pct" })
        return changed
      }
      var targets = [clickChange("1W", "smooth"), clickChange("1M", "retro"), clickChange("1D", "smooth")].join(",")
      harness.check("the hero's change cycles the mode only on the day: not on 1W or 1M",
        targets === "false,false,true", targets)
    }

    // Retro's bell appears with the columns, judged only in the review kit.
    function bellDrawIn(body) {
      service.feature("AAPL")
      service.setRange("1D")
      // Retro's bell draws in with the columns, never ahead of them: as the
      // window opens, and as the range comes back to the day. Found in the
      // transition audit (data 3): it stood from the draw-in's first frame.
      service.persist({ style: "retro" })
      // Found afresh each frame: a range change makes the ticks again.
      var bell = function() { return harness.find(body.chartItem, "retroBell") }
      var curtain = harness.find(body.chartItem, "curtain")
      var ahead = function(draw) {
        var early = 0
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(function() { if (bell() && bell().visible && bell().x >= curtain.width) early++ })
        draw()
        within(1500, function() { return body.motion.reveal === 1 && !body.chartLoading })
        wait(50)
        frames.destroy()
        return early + "," + (!!bell() && bell().visible)
      }
      var onOpen = ahead(function() { app.close(); app.open("{}") })
      service.setRange("1W")
      within(5000, function() { return body.historyShown && !body.chartLoading && body.motion.reveal === 1 })
      var onDay = ahead(function() { service.setRange("1D") })
      service.persist({ style: "smooth" })
      harness.check("retro's bell draws in with the columns: on an open and on a range change back to the day",
        onOpen === "0,true" && onDay === "0,true", onOpen + " | " + onDay)
    }

    // Each change of chart ends the last one's motion first: a running
    // draw-in or replay, whatever changed.
    function motionEnds(body, watchlist, keys) {
      var dropEntry = function(key) {
        var next = Object.assign({}, service.testHistoryFeed.entries)
        delete next[key]
        service.testHistoryFeed.entries = next
      }
      var rest = function() {
        tryVerify(function() {
          return !body.chartLoading && body.motion.drawn === 1 && !watchlist.settling
            && watchlist.displayedSymbols.every(function(s) { return watchlist.rowItem(s).resting })
        }, 5000)
      }
      service.setOrder("manual")
      service.summon("AAPL", "1W")
      rest()
      service.setRange("1M")
      rest()
      service.setRange("1W")
      rest()
      // Acts once, on the turn after the first frame that has the motion's
      // `prop` between `lo` and `hi`, and returns its value as it acted: the
      // 320 ms draw-in is mostly over before a 50 ms poll can be sure to
      // catch it part way.
      var midway = function(prop, lo, hi, act) {
        var at = -1
        var acting = false
        var watch = function() {
          var value = body.motion[prop]
          if (acting || value <= lo || value >= hi) return
          acting = true
          Qt.callLater(function() { at = body.motion[prop]; act() })
        }
        body.motion[prop + "Changed"].connect(watch)
        tryVerify(function() { return at >= 0 }, 3000)
        body.motion[prop + "Changed"].disconnect(watch)
        return at
      }

      // A range change during a running draw-in: to a range in hand the new
      // chart draws in from its start; to one on its way the one on show
      // stands whole until it lands. As the window opens. Found in the
      // transition audit (ranges 8) and cubic's review of #24: the new chart
      // appeared part drawn, or the held one kept drawing in under Loading.
      var midDrawIn = function(start, toKey, cached) {
        if (!cached) dropEntry(toKey)
        start()
        var after = -1
        var held = false
        var from = midway("drawn", 0.2, 0.9, function() {
          body.stepRange(1)
          after = body.motion.drawn
          held = body.chartLoading
        })
        // A new draw-in starts over, below where the last one had reached.
        var ok = from > 0 && (cached ? after < from : after === 1 && held)
        rest()
        service.setRange("1W")
        rest()
        return ok + " " + from.toFixed(2) + "->" + after.toFixed(2)
      }
      var openToCached = midDrawIn(function() { app.close(); app.open("{}") }, "AAPL|1M", true)
      var openToUncached = midDrawIn(function() { app.close(); app.open("{}") }, "AAPL|1M", false)
      harness.check("a range change mid draw-in draws the next chart from its start, or holds the one on show whole while it loads",
        [openToCached, openToUncached].every(function(r) { return /^true /.test(r) }),
        [openToCached, openToUncached].join(" | "))

      // A symbol change draws the new chart in from its start: a row
      // featured during a running draw-in or replay starts it over, the
      // replay ended. As the window opens, after a range change, and
      // mid-replay.
      service.setRange("1D")
      rest()
      var startsOver = function(start) {
        var target = watchlist.displayedSymbols.filter(function(s) { return s !== service.featuredSymbol })[0]
        var after = -1
        var replaying = true
        start()
        var cut = midway("drawn", 0.2, 0.9, function() {
          body.featureSymbol(target)
          after = body.motion.drawn
          replaying = body.motion.replayRunning
        })
        rest()
        return (cut > 0 && after < cut && !replaying) + " " + target + " " + cut.toFixed(2) + "->" + after.toFixed(2)
      }
      var afterOpen = startsOver(function() { app.close(); app.open("{}") })
      var afterRange = startsOver(function() { service.setRange("1W"); rest(); service.setRange("1D") })
      var midReplay = startsOver(function() { body.replay() })
      harness.check("a row featured mid draw-in or mid-replay draws its chart in from the start: after an open, a range change, and in a replay",
        /^true /.test(afterOpen) && /^true /.test(afterRange) && /^true /.test(midReplay),
        afterOpen + " | " + afterRange + " | " + midReplay)
      rest()
    }

    // OutCubic's origin: Qt may count from the tick before the change,
    // so a wall-time mark alone makes a correct animation read early.
    function animationOrigin(anim, value) {
      if (anim.duration <= 0 || anim.from === anim.to) return 0
      var progress = Math.max(0, Math.min(1, (value - anim.from) / (anim.to - anim.from)))
      return Date.now() - (1 - Math.cbrt(1 - progress)) * anim.duration
    }

    function captureOrigin(origin, tick, mark) {
      // Only the recorded tick before the change can explain an early start.
      // Frame times have millisecond precision, as does Date.now().
      origin = Math.round(origin)
      return tick > 0 && origin >= tick && origin <= mark ? origin : mark
    }

    // The draw-in as it is rendered: the hero chart grabbed on every frame,
    // its ink advancing from the left over several distinct frames and
    // whole in about 320 ms, for a symbol change and a range change, in both
    // looks. Judged on the pictures (frames.js), not on `reveal`. Found in
    // the motion audit: #33's checks proved a property moved, while its
    // 160 ms fade read as no motion at all.
    function drawInFrames(body, keys) {
      var run = function(name, change, busyMachine) {
        grab.source = body.chartItem
        busy.target = busyMachine ? body.chartItem.Window.window : null
        harness.busySince = 0
        grab.begin(name)
        tryVerify(function() { return grab.tick > 0 && grab.frames.length > 0 }, 2000)
        // The draw-in starts as the chart's reveal leaves whole.
        var started = false
        var leftAt = -1
        var drawFrom = 0
        var beforeTick = 0
        var marked = function() {
          var r = body.motion.reveal
          if (!started) {
            if (r >= 1) return
            started = true
            leftAt = r
            beforeTick = grab.tick
            grab.markStart()
            if (busyMachine) harness.busySince = Date.now()
          } else if (!drawFrom && r > leftAt) drawFrom = animationOrigin(body.motion.testDrawIn, r)
        }
        body.motion.revealChanged.connect(marked)
        change()
        tryVerify(function() { return !body.chartLoading && body.motion.reveal === 1 }, 5000)
        // A few frames of the whole picture, after the end.
        var settledAt = grab.frames.length
        tryVerify(function() { return grab.frames.length >= settledAt + 4 }, 2000)
        grab.end()
        busy.target = null
        harness.busySince = 0
        body.motion.revealChanged.disconnect(marked)
        tryVerify(function() { return grab.waiting === 0 }, 3000)
        var markedAt = grab.start
        grab.start = captureOrigin(drawFrom, beforeTick, markedAt)
        grab.judge("drawin:ink", grab.frames.filter(function(f) { return f.at >= markedAt }), ["plot=" + emptyPlot(body, name)])
        tryVerify(function() { return grab.verdict !== null }, 10000)
        grab.verdict.detail += " | origin " + Math.round(grab.start - markedAt) + ", inferred "
          + (drawFrom ? Math.round(drawFrom - markedAt) : "none") + ", prior tick " + (beforeTick - markedAt) + " ms from mark"
        return grab.verdict
      }
      var results = []
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        service.setRange("1D")
        service.feature("AAPL")
        tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
        keys.forceActiveFocus()
        // Enter on the first row that is not AAPL's.
        var other = body.watchlist.displayedSymbols.findIndex(function(s) { return s !== "AAPL" })
        body.watchlist.cursorSymbol = body.watchlist.displayedSymbols[other]
        var symbol = run("symbol-" + look, function() { keyClick(Qt.Key_Return) })
        var range = run("range-" + look, function() { keyClick(Qt.Key_BracketRight) })
        results.push(look + " symbol " + (symbol.ok ? "ok" : "FAILED") + ": " + symbol.detail)
        results.push(look + " range " + (range.ok ? "ok" : "FAILED") + ": " + range.detail)
      })
      // The same on a busy machine: a range change back, in smooth. Its
      // frames are sparse on purpose, so a stall from the suite's own load
      // can leave too few to read the motion by (frames.js `unreadable`):
      // then it is filmed again, up to three times, back and forth across
      // the range. A wrong draw-in fails on the frames that come.
      service.persist({ style: "smooth" })
      tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
      var busyRange = null
      var tries = []
      for (var attempt = 0; attempt < 3 && (!busyRange || busyRange.unreadable); attempt++) {
        if (attempt) {
          keyClick(Qt.Key_BracketRight)
          tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
        }
        busyRange = run("range-busy-" + attempt, function() { keyClick(Qt.Key_BracketLeft) }, true)
        tries.push(busyRange.unreadable ? "unreadable: " + busyRange.detail : busyRange.ok ? "ok" : "failed")
      }
      harness.check("on a busy machine, whose animation clock ticks later and later, the chart still reads as drawing in over about 320 ms"
        + (busyRange.ok ? " — frames " + busyRange.detail.replace(/^edge [0-9. ]*/, "") : "") + " — " + tries.length + (tries.length === 1 ? " try" : " tries"),
        busyRange.ok, tries.join(" || ") + (busyRange.ok ? "" : " || " + busyRange.detail))

      // Loading holds still, then dims: while the chart asked for is on its
      // way, the one on show is the same picture on every frame for a
      // quarter of a second, then dims to 0.4 of its ink in 160 ms and
      // holds there, still, the label over it naming what is coming; when
      // it lands, the new chart draws in at full ink and the hero's figures
      // come back from the dim in 160 ms. From the day, in both looks,
      // AAPL's month dropped and its answer held back. With a live mark on
      // the held day, layout.sh. The draw-in that lands is the real one
      // unless a check makes it wrong: `wrong.from` where it starts,
      // `wrong.ms` how long it takes; and the dim, `wrong.delay` after the
      // change, in `wrong.dimMs`.
      var right = { from: body.motion.testDrawIn.from, ms: body.motion.testDrawIn.duration,
        delay: body.motion.testSlow.interval, dimMs: body.motion.testDim.duration }
      var made = function(wrong) {
        var w = Object.assign({}, right, wrong || {})
        body.motion.testDrawIn.from = w.from
        body.motion.testDrawIn.duration = w.ms
        body.motion.testSlow.interval = w.delay
        body.motion.testDim.duration = w.dimMs
      }
      var verdictOf = function(grabber, mode, frames, args) {
        grabber.judge(mode, frames, args)
        tryVerify(function() { return grabber.verdict !== null }, 10000)
        return grabber.verdict
      }
      var holds = function(look, wrong) {
        service.persist({ style: look })
        service.feature("AAPL")
        service.setRange("1D")
        tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
        var entries = Object.assign({}, service.testHistoryFeed.entries)
        delete entries["AAPL|1M"]
        service.testHistoryFeed.entries = entries
        holdAapl.running = true
        tryVerify(function() { return !holdAapl.running }, 2000)
        made(wrong)
        grab.source = body.chartItem
        grab.begin("loading-" + look)
        var heldFrom = grab.start
        service.setRange("1M")
        var loading = body.chartLoading
        // Long enough for the dim to rest, and the halo's ripple and the
        // cap's blink to show if they did.
        tryVerify(function() { var f = grab.frames; return f.length > 0 && f[f.length - 1].at - heldFrom >= 900 }, 5000)
        var stillLoading = body.chartLoading
        var label = harness.find(body, "loadingLabel")
        var named = label.visible && label.text === "Loading AAPL 1M…"
        var heldUntil = Date.now()
        heroGrab.source = harness.find(body, "hero")
        heroGrab.begin("lift-" + look)
        tryVerify(function() { return heroGrab.tick > 0 && heroGrab.frames.length > 0 }, 2000)
        var landedAt = 0
        var leftAt = -1
        var drawFrom = 0
        var liftFrom = 0
        var drawTick = 0
        var liftTick = 0
        var marked = function() {
          var r = body.motion.reveal
          if (!landedAt) {
            if (r === 1) return
            drawTick = grab.tick
            liftTick = heroGrab.tick
            grab.markStart()
            heroGrab.markStart()
            landedAt = grab.start
            leftAt = r
          } else if (!drawFrom && r > leftAt) drawFrom = animationOrigin(body.motion.testDrawIn, r)
        }
        var lifting = function() {
          var anim = body.motion.testDim
          var value = body.motion.dimmed
          if (!liftFrom && landedAt && value < anim.from && value > anim.to)
            liftFrom = animationOrigin(anim, value)
        }
        body.motion.revealChanged.connect(marked)
        body.motion.dimmedChanged.connect(lifting)
        releaseAapl.running = true
        tryVerify(function() { return !body.chartLoading && body.motion.reveal === 1 && body.motion.dimmed === 0 }, 5000)
        var settledAt = grab.frames.length
        tryVerify(function() { return grab.frames.length >= settledAt + 4 }, 2000)
        grab.end()
        heroGrab.end()
        made(null)
        body.motion.revealChanged.disconnect(marked)
        body.motion.dimmedChanged.disconnect(lifting)
        tryVerify(function() { return grab.waiting === 0 && heroGrab.waiting === 0 }, 3000)
        var plot = emptyPlot(body, "loading-" + look)
        grab.start = heldFrom
        var held = verdictOf(grab, "dim", grab.frames.filter(function(f) { return f.at >= heldFrom && f.at < heldUntil }))
        grab.start = captureOrigin(drawFrom, drawTick, landedAt)
        var landed = verdictOf(grab, "drawin:ink", grab.frames.filter(function(f) { return f.at >= landedAt }), ["plot=" + plot])
        landed.detail += " | origin " + Math.round(grab.start - landedAt) + ", inferred "
          + (drawFrom ? Math.round(drawFrom - landedAt) : "none") + ", prior tick " + (drawTick - landedAt) + " ms from landing mark"
        // From the last frame before the landing, still dimmed: its price is
        // the same symbol's, so the dim it comes back from is read off it,
        // not off the first frame after, which under load is part lifted.
        var beforeLanding = heroGrab.frames.filter(function(f) { return f.at < landedAt }).slice(-1)
        heroGrab.start = captureOrigin(liftFrom, liftTick, landedAt)
        var lifted = verdictOf(heroGrab, "dim", beforeLanding.concat(heroGrab.frames.filter(function(f) { return f.at >= landedAt })))
        lifted.detail += " | origin " + Math.round(heroGrab.start - landedAt) + ", inferred "
          + (liftFrom ? Math.round(liftFrom - landedAt) : "none") + ", prior tick " + (liftTick - landedAt) + " ms from landing mark"
        return { held: held.ok && loading && stillLoading && named, heldDetail: held.detail + (named ? "" : ", label " + label.visible + " " + label.text),
          landed: landed, lifted: lifted }
      }
      ;["smooth", "retro"].forEach(function(look) {
        var run = holds(look, null)
        results.push(look + " held " + (run.held ? "ok" : "FAILED") + ": " + run.heldDetail)
        results.push(look + " landed " + (run.landed.ok ? "ok" : "FAILED") + ": " + run.landed.detail)
        results.push(look + " lifted " + (run.lifted.ok ? "ok" : "FAILED") + ": " + run.lifted.detail)
      })
      service.persist({ style: "smooth" })
      service.setRange("1D")
      // The numbers stay in the line, pass or fail: they are the proof.
      harness.check("the chart draws in from the left over about 320 ms, as rendered: a symbol and a range change, smooth and retro; a chart on its way holds the one on show, the same picture on every frame for a quarter of a second, then dims it in 160 ms under a label naming what is coming, and when it lands draws in at full ink as the figures come back — "
        + results.join(" || "), results.every(function(r) { return / ok: /.test(r) }))

      // The same capture and judge fail a wrong draw-in where the flaky
      // reading was, retro after a loading hold: the real animation made
      // 160 ms, 400 ms, none, and one that starts 60% drawn and draws the
      // rest in 224 ms.
      var wrong = [{ from: 0, ms: 160 }, { from: 0, ms: 400 }, { from: 0, ms: 0 }, { from: 0.6, ms: 224 }].map(function(w) {
        var run = holds("retro", w)
        return "from " + w.from + " in " + w.ms + " ms " + (run.landed.ok ? "PASSED" : "failed") + ": " + run.landed.detail
      })
      service.persist({ style: "smooth" })
      service.setRange("1D")
      harness.check("a draw-in of 160 ms, 400 ms, none, or one starting part drawn fails the same judgement — " + wrong.join(" || "),
        wrong.every(function(r) { return / failed: /.test(r) }))

      // And a wrong dim fails its own: the real one made at once, 400 ms
      // long, at the change itself, 600 ms after it, and never.
      var wrongDims = [{ delay: 250, dimMs: 0 }, { delay: 250, dimMs: 400 }, { delay: 1, dimMs: 160 }, { delay: 600, dimMs: 160 }, { delay: 100000, dimMs: 160 }].map(function(w) {
        var run = holds("smooth", w)
        return "after " + w.delay + " ms in " + w.dimMs + " ms " + (run.held ? "PASSED" : "failed") + ": " + run.heldDetail
      })
      service.setRange("1D")
      harness.check("a dim at once, over 400 ms, at the change itself, 600 ms after it, or never fails the same judgement — " + wrongDims.join(" || "),
        wrongDims.every(function(r) { return / failed: /.test(r) }))

      // A day half gone: AAPL's cut at noon, its ink ending about halfway
      // along the plot, the rest of the day to come. Its draw-in sweeps to
      // its newest print, so it takes its whole 320 ms; swept across the
      // whole plot, the ink would be whole in about 66 ms. In both looks,
      // retro's in whole columns. The judge reads the ink's extent from the
      // settled picture, and the step holds it against the newest print's
      // place, short of the dot or a column: a sweep that stops short of the
      // print and shows the rest at its end fails either way.
      // A user's refresh fetches only answers over 10 s old: these are aged
      // past it, as a minute on the clock would.
      var refetch = function() {
        var aged = {}
        for (var s in service.testFeed.entries)
          aged[s] = Object.assign({}, service.testFeed.entries[s], { answeredAt: service.testFeed.entries[s].answeredAt - 20 })
        service.testFeed.entries = aged
        service.refresh()
      }
      noonAapl.running = true
      tryVerify(function() { return !noonAapl.running }, 2000)
      refetch()
      tryVerify(function() {
        var q = service.quotes.AAPL
        return !!q && q.points[q.points.length - 1].t < 1788278400 && !service.testFeed.busy
      }, 8000)
      var halves = []
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        service.setRange("1D")
        service.feature(body.watchlist.displayedSymbols.filter(function(s) { return s !== "AAPL" })[0])
        tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
        var half = run("half-day-" + look, function() { service.feature("AAPL") })
        var points = body.featuredGeometry.points
        var newest = points[points.length - 1].x
        var inkEnd = half.inkEnd || 0
        var reached = inkEnd >= newest - 0.005 && inkEnd <= newest + 0.03
        halves.push(look + " " + (half.ok && reached ? "ok" : "FAILED") + " to " + inkEnd.toFixed(3)
          + ", newest print " + newest.toFixed(3) + ": " + half.detail)
      })
      service.persist({ style: "smooth" })
      wholeAapl.running = true
      tryVerify(function() { return !wholeAapl.running }, 2000)
      refetch()
      tryVerify(function() {
        var q = service.quotes.AAPL
        return q.points[q.points.length - 1].t >= 1788278400 && !service.testFeed.busy
      }, 8000)
      harness.check("a day half gone, AAPL at noon, draws in over about 320 ms, sweeping to its newest print, smooth and retro — "
        + halves.join(" || "), halves.every(function(r) { return / ok /.test(r) }))
    }

    // A row that joins draws its day line in from the left over about
    // 320 ms, as rendered, the baseline whole from the start: the undo of a
    // removal from a named list, in smooth and retro, ending on the whole
    // line, never a blank or half-drawn one. And a list switch draws its
    // rows at once: every frame from the switch on is the same picture.
    // The row's line is grabbed alone, so the row's own 160 ms fade is not
    // in its pictures.
    function joinFrames(body, watchlist, keys) {
      service.createList("Joins")
      ;["AAPL", "MSFT", "NVDA"].forEach(function(s) { service.setMembership(s, "Joins", true) })
      service.switchList("Joins")
      mouseMove(body, 1, 1)
      wait(200)
      var joins = []
      var switches = []
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        tryVerify(function() { return body.retro === (look === "retro") }, 2000)
        wait(100)
        var row = watchlist.rowItem("MSFT")
        var line = harness.find(row, look === "retro" ? "rowCells" : "rowLine")
        var joined = null
        var tries = []
        // Filmed again, up to three times, only when too loaded to read.
        for (var attempt = 0; attempt < 3 && (!joined || joined.unreadable); attempt++) {
          var name = "join-" + look + "-" + attempt
          keys.forceActiveFocus()
          watchlist.cursorSymbol = "MSFT"
          keyClick(Qt.Key_Delete)
          tryVerify(function() { return watchlist.displayedSymbols.indexOf("MSFT") < 0 }, 2000)
          // The grab starts as the line's reveal leaves whole, the row just
          // shown: a hidden row has no picture to grab.
          grab.source = line
          var started = false
          var marked = function() {
            if (started || row.reveal >= 1) return
            started = true
            grab.begin(name)
          }
          row.revealChanged.connect(marked)
          keyClick(Qt.Key_Z, Qt.ControlModifier)
          tryVerify(function() { return started && row.reveal === 1 }, 3000)
          var settledAt = grab.frames.length
          tryVerify(function() { return grab.frames.length >= settledAt + 4 }, 2000)
          grab.end()
          row.revealChanged.disconnect(marked)
          tryVerify(function() { return grab.waiting === 0 }, 3000)
          // The empty plot, the baseline alone, on the grab's own ground.
          var plot = Quickshell.env("STONKS_FRAMES") + "/" + name + "-plot.ppm"
          var saved = false
          row.reveal = 0
          line.grabToImage(function(result) { result.saveToFile(plot); saved = true })
          tryVerify(function() { return saved }, 3000)
          row.reveal = 1
          grab.judge("drawin:ink", null, ["plot=" + plot])
          tryVerify(function() { return grab.verdict !== null }, 10000)
          joined = grab.verdict
          tries.push(joined.unreadable ? "unreadable" : joined.ok ? "ok" : "failed")
        }
        joins.push(look + " " + (joined.ok ? "ok" : "FAILED") + " (" + tries.join(",") + "): " + joined.detail)

        // A switch to All and back, each filmed from the switch on, judged
        // on the rows' day line column. The cursor goes back to rest first,
        // so its fill easing off, the shell's hover ease, is not filmed.
        watchlist.cursorSymbol = ""
        ;["", "Joins"].forEach(function(list) {
          grab.source = watchlist
          grab.begin("switch-" + look + "-" + (list || "all"))
          // Past the cursor fill's 60 ms ease before the switch.
          var begun = grab.start
          tryVerify(function() { var f = grab.frames; return f.length > 0 && f[f.length - 1].at - begun >= 160 }, 2000)
          grab.markStart()
          var from = grab.start
          service.switchList(list)
          tryVerify(function() { var f = grab.frames; return f.length > 0 && f[f.length - 1].at - from >= 480 }, 5000)
          grab.end()
          tryVerify(function() { return grab.waiting === 0 }, 3000)
          var column = harness.find(watchlist.rowItem("MSFT"), look === "retro" ? "rowCells" : "rowLine")
          var left = Math.floor(column.mapToItem(watchlist, 0, 0).x)
          grab.judge("same:" + [left, 0, Math.ceil(column.width), Math.floor(watchlist.height)].join(","),
            grab.frames.filter(function(f) { return f.at >= from }))
          tryVerify(function() { return grab.verdict !== null }, 10000)
          switches.push(look + " to " + (list || "All") + " " + (grab.verdict.ok && service.listName === list ? "ok" : "FAILED") + ": " + grab.verdict.detail)
        })
      })
      service.persist({ style: "smooth" })
      service.switchList("")
      service.deleteList("Joins")
      wait(100)
      harness.check("a row that joins, an undo, draws its day line in from the left over about 320 ms, as rendered, ending whole, smooth and retro — "
        + joins.join(" || "), joins.every(function(r) { return / ok /.test(r) }))
      harness.check("a list switch draws its rows at once: the same picture on every frame from the switch on, smooth and retro — "
        + switches.join(" || "), switches.every(function(r) { return / ok: /.test(r) }))
    }

    // The header's animal as it is rendered, in smooth: a scrub across the
    // close turns the bull into the bear in a 160 ms crossfade that never
    // leaves the slot empty, and a new symbol changes it at once. Judged on
    // the slot's pictures (frames.js), each run from a few frames before
    // the change to 400 ms after it.
    function animalFrames(body) {
      var featuredBefore = service.featuredSymbol
      var rangeBefore = service.range
      service.persist({ style: "smooth" })
      service.setRange("1D")
      service.feature("AAPL")
      tryVerify(function() { return body.chartSymbol === "AAPL" && !body.chartLoading && body.motion.drawn === 1 }, 5000)
      var day = body.featuredDay
      var moved = function(p) { return (p.p - day.prevClose) / day.prevClose }
      var above = day.points.filter(function(p) { return moved(p) > 0.001 })
      var below = day.points.filter(function(p) { return moved(p) < -0.001 })
      var slot = harness.find(body, "animal")
      var bull = harness.find(body, "bullCells")
      var run = function(name, mode, change) {
        tryVerify(function() { return body.animal.kind === "bull" && bull.opacity === 1 }, 2000)
        grab.source = slot
        grab.begin(name)
        var at = grab.frames.length
        tryVerify(function() { return grab.frames.length >= at + 3 }, 2000)
        grab.markStart()
        change()
        tryVerify(function() { return grab.frames.length > 0 && grab.frames[grab.frames.length - 1].at - grab.start >= 400 }, 5000)
        grab.end()
        tryVerify(function() { return grab.waiting === 0 }, 3000)
        grab.judge(mode)
        tryVerify(function() { return grab.verdict !== null }, 10000)
        return grab.verdict
      }
      body.motion.scrubT = above[0].t
      var scrubbed = run("animal-scrub", "turn", function() { body.motion.scrubT = below[below.length - 1].t })
      harness.check("a scrub across the close crossfades the bull into the bear in about 160 ms, never through an empty slot"
        + (scrubbed.ok ? " — " + scrubbed.detail : ""), above.length > 0 && below.length > 0 && scrubbed.ok,
        above.length + " prints above, " + below.length + " below: " + scrubbed.detail)
      body.motion.scrubT = 0
      var featured = run("animal-symbol", "turn:0", function() { service.feature("DOWN") })
      harness.check("a new symbol changes the animal at once"
        + (featured.ok ? " — " + featured.detail : ""), featured.ok && body.animal.kind === "bear", body.animal.kind + ": " + featured.detail)
      service.setRange(rangeBefore)
      service.feature(featuredBefore)
      tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
    }

    // The header's animal falling asleep and waking, as it is rendered with
    // its "z", the status words hidden: when the clock closes DOWN's market,
    // Friday 11 September at 20:00 with no night after it, its eyes close
    // over 320 ms in two steps, the same cells in both looks, and when its
    // night starts on Sunday at 20:00 they open the same way. Nothing else
    // moves it: letting go of a scrub puts it back to sleep at once, a new
    // symbol changes it at once, and an open after the close shows it
    // asleep from its first frame.
    function sleepFrames(body) {
      var featuredBefore = service.featuredSymbol
      var rangeBefore = service.range
      var slot = harness.find(body, "animal")
      var header = slot.parent
      var words = harness.find(header, "statusText")
      var verdict = function(mode, judged) {
        tryVerify(function() { return grab.waiting === 0 }, 3000)
        grab.judge(mode, judged)
        tryVerify(function() { return grab.verdict !== null }, 10000)
        return grab.verdict
      }
      var run = function(name, mode, change) {
        grab.source = header
        grab.begin(name)
        var at = grab.frames.length
        tryVerify(function() { return grab.frames.length >= at + 3 }, 2000)
        grab.markStart()
        change()
        tryVerify(function() { return grab.frames.length > 0 && grab.frames[grab.frames.length - 1].at - grab.start >= 480 }, 5000)
        grab.end()
        return verdict(mode)
      }
      var look = function(style) {
        service.persist({ style: style })
        tryVerify(function() { return body.retro === (style === "retro") }, 2000)
        // The look icon steps for 200 ms on a change of look: it rests first.
        wait(300)
      }
      service.setRange("1D")
      service.feature("DOWN")
      tryVerify(function() { return body.chartSymbol === "DOWN" && !body.chartLoading && body.motion.drawn === 1 }, 5000)
      var close = service.quotes.DOWN.session.post.end
      service.testClockHeld = true
      words.visible = false
      var awake = function() {
        service.now = close - 60
        tryVerify(function() { return !body.animal.asleep && header.closing === 0 }, 2000)
      }
      // Retro's clock skips the closing second, as a late tick does.
      var bells = ["smooth", "retro"].map(function(style) {
        look(style)
        awake()
        var bell = run("sleep-bell-" + style, "steps:320", function() {
          service.now = style === "smooth" ? close : close + 2
        })
        return style + ": " + (bell.ok && body.animal.asleep ? "ok" : "not ok") + ", " + bell.detail
      })
      harness.check("the clock closing the market closes the animal's eyes over 320 ms in two steps, in both looks, retro's clock skipping the closing second — "
        + bells.join(" | "), bells.every(function(b) { return /^\w+: ok, /.test(b) }))
      // Sunday at 20:00, DOWN's night starting: it trades all night.
      var wake = close + 2 * 86400
      var wakes = ["smooth", "retro"].map(function(style) {
        look(style)
        service.now = wake - 60
        tryVerify(function() { return body.animal.asleep && header.closing === 1 }, 2000)
        var opened = run("wake-bell-" + style, "steps:320", function() {
          service.now = style === "smooth" ? wake : wake + 2
        })
        return style + ": " + (opened.ok && !body.animal.asleep ? "ok" : "not ok") + ", " + opened.detail
      })
      harness.check("the clock waking the market opens the animal's eyes over 320 ms in two steps, the \"z\" going with them, in both looks — "
        + wakes.join(" | "), wakes.every(function(w) { return /^\w+: ok, /.test(w) }))
      look("smooth")
      // Two seconds after the close, inside the bell's few seconds, a scrub
      // on the same side of the close, so the animal reads a bear on both
      // sides of letting go, and no turn crossfades. Found in review: there
      // its eyes closed over 320 ms.
      service.now = close + 2
      var below = body.featuredDay.points.filter(function(p) { return p.p < body.featuredDay.prevClose })
      body.motion.scrubT = below[below.length - 1].t
      tryVerify(function() { return !body.animal.asleep && header.closing === 0 && body.animal.kind === "bear" }, 2000)
      wait(250)
      var letGo = run("sleep-scrub-end", "turn:0", function() { body.motion.clearScrub() })
      harness.check("letting go of a scrub two seconds after the close puts the animal back to sleep at once, no eye-close — " + letGo.detail,
        letGo.ok && body.animal.asleep, body.animal.asleep + ": " + letGo.detail)
      // DOWN after hours, then Toronto, closed since its 16:00.
      service.addSymbol("SHOP.TO")
      tryVerify(function() { return !!service.quotes["SHOP.TO"] && service.arriving.length === 0 }, 8000)
      awake()
      var symbol = run("sleep-symbol", "turn:0", function() { service.feature("SHOP.TO") })
      harness.check("a new symbol whose market is closed shows its animal asleep at once — " + symbol.detail,
        symbol.ok && body.animal.asleep, body.animal.asleep + ": " + symbol.detail)
      // A first quote that failed, then lands after the close on a retry:
      // its animal comes asleep, with no eye-close, though the chart is the
      // same. Found in review: it closed its eyes over 320 ms.
      service.now = close
      lateDown.running = true
      tryVerify(function() { return !lateDown.running }, 2000)
      service.addSymbol("LATE")
      tryVerify(function() { return service.arriving.indexOf("LATE") < 0 }, 15000)
      service.feature("LATE")
      tryVerify(function() { return body.chartSymbol === "LATE" && !body.featuredQuote && body.animal.kind === "" }, 5000)
      var closings = []
      var note = function() { closings.push(header.closing) }
      header.closingChanged.connect(note)
      lateUp.running = true
      tryVerify(function() { return !lateUp.running }, 2000)
      // A refresh asks what was answered over 10 s ago on the held clock.
      service.now = close + 15
      service.refresh()
      tryVerify(function() { return body.animal.kind !== "" }, 8000)
      wait(400)
      header.closingChanged.disconnect(note)
      harness.check("a first quote landing on a retry after the close shows its animal asleep at once, no eye-close",
        body.animal.asleep && closings.join(",") === "1", body.animal.asleep + ", closing went " + closings.join(","))
      // An open after the bell, the market closing while the window was
      // shut: the frames from its first painted one are all the same.
      service.feature("DOWN")
      tryVerify(function() { return body.chartSymbol === "DOWN" && !body.chartLoading && body.motion.drawn === 1 }, 5000)
      awake()
      app.close()
      service.now = close
      app.open("{}")
      grab.source = header
      grab.begin("sleep-open")
      tryVerify(function() { return !body.chartLoading && body.motion.reveal === 1 && grab.frames.length >= 12 }, 5000)
      grab.end()
      var first = verdict("same")
      var painted = first.blankBefore ? first.changedAt : 0
      var opened = verdict("same", grab.frames.filter(function(f) { return f.at - grab.start >= painted }))
      harness.check("an open after the close shows the animal asleep from its first painted frame — painted " + painted + " ms in | "
        + opened.detail, opened.ok && body.animal.asleep && header.closing === 1, body.animal.asleep + ": " + opened.detail)
      words.visible = true
      service.testClockHeld = false
      service.setRange(rangeBefore)
      service.feature(featuredBefore)
      tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
    }

    // A closing surface holds its picture: from the close until the next
    // open nothing on it changes, whatever was moving or the service does
    // meanwhile. The window hides at once, so its body is put where the
    // popup's close fade leaves the popup's, closed but still on screen.
    // Found in the motion audit (finding 3): the fading card changed chart,
    // and a removed row left a hole; and in its design review: the look
    // icon, the breadth rule, and the footer's note went on.
    function closingHolds(body, watchlist, keys) {
      var icon = harness.find(body, "lookIcon")
      var frames = function(n) {
        var at = grab.frames.length
        tryVerify(function() { return grab.frames.length >= at + n }, 2000)
      }
      var verdict = function(judged) {
        tryVerify(function() { return grab.waiting === 0 }, 3000)
        grab.judge("same", judged)
        tryVerify(function() { return grab.verdict !== null }, 10000)
        return grab.verdict
      }
      var close = function() {
        body.freeze()
        body.surfaceOpen = false
      }
      var reopen = function() {
        body.surfaceOpen = Qt.binding(function() { return app.testWindow.visible })
        app.close()
        app.open("{}")
      }
      var rest = function() {
        tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 && !watchlist.settling }, 5000)
        wait(250)
      }
      service.setRange("1D")
      service.feature("AAPL")
      // From retro, so s turns to smooth, whose rule draws the eased ends:
      // retro's cells draw the breadth itself, and the ease never shows.
      service.persist({ style: "retro" })
      rest()
      mouseMove(body, 1, 1)
      keys.forceActiveFocus()

      // In flight at the close: the look icon's step, the rows closing a
      // removal's gap, and the breadth rule's ends. Every frame after the
      // close is the same picture. x moves the cursor to the next row, whose
      // fill finishes its 60 ms through a close, as any fill does: the close
      // waits for the rows' own colours to arrive, since a fixed 60 ms on a
      // busy machine can come before the animation clock has run them.
      watchlist.cursorSymbol = "NVDA"
      keyClick(Qt.Key_Delete)
      keyClick(Qt.Key_S)
      var filled = function() {
        return watchlist.displayedSymbols.every(function(symbol) {
          var row = watchlist.rowItem(symbol)
          return !row || Qt.colorEqual(row.color, row.fill)
        })
      }
      for (var waited = 0; waited < 1000 && !filled(); waited += 5) wait(5)
      var stepping = icon.cells > 0 && icon.cells < 1
      close()
      grab.source = body
      grab.begin("closing-in-flight")
      frames(12)
      grab.end()
      var inFlight = verdict()
      reopen()
      service.undoRemoval("NVDA")
      service.persist({ style: "smooth" })
      rest()

      // At rest, a note on show, u's refusal with nothing to undo: the
      // frames before the close are the picture every frame after it keeps,
      // through an answer that lands (AAPL's next quote, its line turned and
      // its price new), a hero chosen on another surface, the hero leaving
      // All, and past the note's moment. The next open takes the latest and
      // draws in.
      var quotesBefore = service.testFeed.quotes
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      rest()
      var noted = body.note === "Nothing to undo"
      grab.begin("closing-at-rest")
      frames(3)
      grab.end()
      tryVerify(function() { return grab.waiting === 0 }, 3000)
      close()
      grab.resume()
      frames(3)
      var next = Object.assign({}, service.testFeed.quotes)
      var quote = next.AAPL
      var prices = quote.points.map(function(point) { return point.p })
      var mid = (Math.max.apply(null, prices) + Math.min.apply(null, prices)) / 2
      next.AAPL = Object.assign({}, quote, { price: quote.price + 5,
        points: quote.points.map(function(point) { return { t: point.t, p: 2 * mid - point.p } }) })
      service.testFeed.quotes = next
      frames(3)
      service.feature("MSFT")
      frames(3)
      service.removeSymbol("AAPL")
      frames(3)
      grab.end()
      wait(2700)
      grab.resume()
      frames(3)
      grab.end()
      var atRest = verdict()
      reopen()
      var adopted = [service.featuredSymbol === "MSFT", body.chartSymbol === "MSFT",
        watchlist.displayedSymbols.indexOf("AAPL") < 0, body.motion.reveal < 1].join(",")
      harness.check("a closing surface stops the look icon, the rows, and the rule where they are, and holds its chart, figures, rows, and note through an answer, another surface's choice, a removal from All, and the note's time; the next open takes the latest and draws in — in flight "
        + stepping + " " + inFlight.detail + " | at rest " + noted + " " + atRest.detail + " | open " + adopted,
        stepping && inFlight.ok && noted && atRest.ok && adopted === "true,true,true,true")
      service.undoRemoval("AAPL")
      service.testFeed.quotes = quotesBefore
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
      service.feature("AAPL")
      rest()
    }

    // Position clauses moved from the behavior flows. These observe real
    // joins, a pointer hold ending, and the scroll pulled back at a removal;
    // the renderer's paused poses show their ink, not these transitions.
    function holdQuote(symbol, held) {
      var path = Quickshell.env("STONKS_FAKE_STATE") + "/" + symbol + ".quote.hold"
      quoteFile.command = held ? ["touch", path] : ["rm", "-f", path]
      quoteFile.running = true
      tryVerify(function() { return !quoteFile.running }, 2000)
    }

    function pickSymbol(body, keys, symbol) {
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding && body.search.active }, 2000)
      var field = harness.find(body.search, "searchField")
      field.forceActiveFocus()
      keyClick(Qt.Key_A, Qt.ControlModifier)
      for (var c = 0; c < symbol.length; c++) keyClick(symbol.charAt(c))
      tryVerify(function() { return body.search.resultsQuery === symbol && body.search.results.length === 1 }, 3000)
      keyClick(Qt.Key_Return)
      tryVerify(function() { return !body.adding }, 2000)
    }

    function rowPlaces(body, watchlist, keys) {
      sixRows(body, "NVDA", "1D")
      service.setOrder("pct")
      wait(400)
      var join = function(two, held) {
        service.removeSymbol("SLOW")
        service.removeSymbol("FLAT")
        wait(200)
        var positions = []
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(function() {
          var seen = watchlist.rowItem("SLOW")
          if (!seen || !seen.visible || seen.opacity <= 0) return
          var top = seen.y - watchlist.contentY
          if (top + seen.height > 0 && top < watchlist.height) positions.push(top)
        })
        holdQuote("SLOW", true)
        pickSymbol(body, keys, "SLOW")
        if (two) pickSymbol(body, keys, "FLAT")
        if (held) {
          mouseMove(watchlist, 20, watchlist.rowPitch + 10)
          tryVerify(function() { return watchlist.sortHeld }, 2000)
        }
        else mouseMove(body, 1, 1)
        tryVerify(function() { return !!watchlist.rowItem("SLOW") }, 2000)
        var row = watchlist.rowItem("SLOW")
        var stillWaiting = !service.quotes.SLOW
        waitForRendering(watchlist)
        holdQuote("SLOW", false)
        tryVerify(function() { return !!service.quotes.SLOW && (!two || !!service.quotes.FLAT) }, 5000)
        tryVerify(function() { return row.resting && !watchlist.settling }, 3000)
        var place = watchlist.displayedSymbols.indexOf("SLOW")
        mouseMove(body, 1, 1)
        wait(400)
        frames.destroy()
        var at = place * watchlist.rowPitch - watchlist.contentY
        return stillWaiting && positions.length > 1 && positions.every(function(y) { return Math.abs(y - at) < 0.5 })
          && place >= 0 && watchlist.displayedSymbols.indexOf("SLOW") === place
      }
      var single = join(false, false)
      var second = join(true, false)
      var pointer = join(false, true)
      harness.check("an arriving row fades at its own place without sliding across the rows, alone or before a second add", single && second,
        "single=" + single + " two=" + second)
      harness.check("a pointer-held arrival stays at its place when the pointer leaves", pointer)

      service.removeSymbol("SLOW")
      sixRows(body, "NVDA", "1D")
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 3 * body.rowPitch
      app.open("{}")
      wait(400)
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      wait(100)
      var screenY = function(s) { return Math.round(watchlist.rowItem(s).y - watchlist.contentY) }
      var below = watchlist.displayedSymbols[5]
      var above = watchlist.displayedSymbols[3]
      var belowAt = [screenY(below)]
      var aboveAt = [screenY(above)]
      var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
      frames.triggered.connect(function() { belowAt.push(screenY(below)); aboveAt.push(screenY(above)) })
      body.removeRow(watchlist.displayedSymbols[4])
      tryVerify(function() { return !watchlist.settling && watchlist.displayedSymbols.every(function(s) { return watchlist.rowItem(s).resting }) }, 3000)
      frames.destroy()
      var end = aboveAt[aboveAt.length - 1]
      harness.check("an end removal keeps the row below still while the rows above close the gap",
        belowAt.every(function(y) { return y === belowAt[0] }) && end === aboveAt[0] + watchlist.rowPitch
          && aboveAt.some(function(y) { return y > aboveAt[0] && y < end })
          && aboveAt.every(function(y, i) { return i === 0 || y >= aboveAt[i - 1] }),
        belowAt.join(",") + " / " + aboveAt.join(","))
    }

    // The wheel moves the list below a held row, never the row away from
    // its pointer. Observe every animation frame, including the glide's
    // middle: the final drop order alone cannot catch a drifting picture.
    function wheelKeepsLift(body, watchlist) {
      var results = []
      ;["smooth", "retro"].forEach(function(look) {
        sixRows(body, "NVDA", "1D")
        service.persist({ style: look })
        app.close()
        app.testWindow.implicitHeight = body.chromeHeight + 3 * body.rowPitch
        app.open("{}")
        waitForRendering(body)
        tryVerify(function() { return !watchlist.settling && watchlist.displayedSymbols.every(function(s) { return watchlist.rowResting(s) }) }, 3000)
        var up = look === "retro"
        watchlist.contentY = up ? watchlist.contentHeight - watchlist.height : 0
        var symbol = watchlist.displayedSymbols[up ? watchlist.displayedSymbols.length - 1 : 0]
        var row = watchlist.rowItem(symbol)
        var at = row.mapToItem(body, row.width / 2, row.height / 2)
        var by = up ? -8 : 8
        mousePress(body, at.x, at.y)
        mouseMove(body, at.x, at.y + by / 2, -1, Qt.LeftButton)
        mouseMove(body, at.x, at.y + by, -1, Qt.LeftButton)
        tryVerify(function() { return watchlist.dragSymbol === symbol }, 2000)
        var top = row.mapToItem(body, 0, 0).y
        var scrollBefore = watchlist.contentY
        var offsets = [0]
        var scrolls = [scrollBefore]
        var sample = function() {
          offsets.push(row.mapToItem(body, 0, 0).y - top)
          scrolls.push(watchlist.contentY)
        }
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(sample)
        mouseWheel(body, at.x, at.y + by, 0, up ? 120 : -120, Qt.LeftButton)
        tryVerify(function() { return !watchlist.settling }, 3000)
        waitForRendering(watchlist)
        sample()
        frames.destroy()
        var scrollAfter = watchlist.contentY
        var inBetween = scrolls.some(function(y) { return y > Math.min(scrollBefore, scrollAfter) && y < Math.max(scrollBefore, scrollAfter) })
        var kept = Math.abs(Math.abs(scrollAfter - scrollBefore) - watchlist.rowPitch) < 1
          && inBetween && offsets.every(function(y) { return Math.abs(y) < 0.5 })
        results.push(look + ":" + kept + " offsets=" + offsets.join(","))
        mouseRelease(body, at.x, at.y + by)
        tryVerify(function() { return watchlist.dragSymbol === "" && watchlist.rowResting(symbol) }, 3000)
      })
      harness.check("a lifted row stays under the pointer throughout a wheel glide, down in smooth and up in retro",
        results.every(function(r) { return /:true offsets=/.test(r) }), results.join(" | "))
    }

    // The window's replay keys and clicks, with their displayed moments:
    // these run in all.sh even when nobody runs the motion review kit.
    function replayActions(body, keys) {
      service.feature("AAPL")
      app.testBody.selectRange("1Y")
      tryVerify(function() {
        return !service.testHistoryFeed.busy && service.histories["AAPL|1Y"]
          && service.histories["AAPL|1Y"].status === "ok" && body.historyShown && !body.chartLoading
      }, 10000)

      keys.forceActiveFocus()
      keyClick(Qt.Key_P, Qt.ControlModifier)
      harness.check("Ctrl+P does not replay", !body.motion.replayRunning && body.scrubT === 0)

      keys.forceActiveFocus()
      keyClick(Qt.Key_P, Qt.AltModifier)
      harness.check("Alt+P does not replay", !body.motion.replayRunning && body.scrubT === 0)

      // A click on the header's animal replays the chart shown, in both looks.
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        tryVerify(function() { return body.retro === (look === "retro") && body.animal.kind !== "" }, 2000)
        mouseClick(body, 20, body.margins + 14, Qt.LeftButton)
        // A replay owns a real historical moment, whatever the render rate.
        harness.check(look + "'s animal click replays a historical range",
          within(2000, function() { return body.motion.replayRunning && body.scrubT !== 0 }),
          body.motion.replayRunning + "|" + body.scrubT)
        body.resetInteraction()
      })
      service.persist({ style: "smooth" })
      tryVerify(function() { return !body.retro }, 2000)

      // A Shift-click on the chart does what a click does: back to now, with
      // no replay.
      var middle = [body.chartItem.width / 2, body.chartItem.height / 2]
      mouseMove(body.chartItem, middle[0], middle[1])
      wait(20)
      var scrubbed = body.scrubT !== 0
      mouseClick(body.chartItem, middle[0], middle[1], Qt.LeftButton, Qt.ShiftModifier)
      wait(50)
      harness.check("a Shift-click on the chart goes back to now, as a click does, and replays nothing",
        scrubbed && body.scrubT === 0 && !body.motion.replayRunning,
        scrubbed + "|" + body.scrubT + "|" + body.motion.replayRunning)
      body.resetInteraction()

      keys.forceActiveFocus()
      keyClick(Qt.Key_P)
      harness.check("P replays a historical range",
        within(2000, function() { return body.motion.replayRunning && body.scrubT !== 0 }),
        body.motion.replayRunning + "|" + body.scrubT)
      // Hold the real replay at its moment, so this judges who owns the
      // scrub, independent of how much time a pointer command takes.
      body.motion.testReplay.pause()
      var replayT = body.scrubT
      mouseMove(body.chartItem, body.chartItem.width * 3 / 4, body.chartItem.height / 2)
      harness.check("range replay suppresses hover scrubbing",
        body.motion.replayRunning && body.scrubT === replayT, replayT + " -> " + body.scrubT)
      keys.forceActiveFocus()
      keyClick(Qt.Key_Escape)
      wait(20)
      harness.check("Escape stops range replay before closing the window",
        app.testWindow.visible && !body.motion.replayRunning && body.scrubT === 0)

      app.open("{}")
      keys.forceActiveFocus()
      keyClick(Qt.Key_P)
      var started = within(2000, function() { return body.motion.replayRunning && body.scrubT !== 0 })
      var other = body.watchlist.displayedSymbols.findIndex(function(s) { return s !== service.featuredSymbol })
      var target = body.watchlist.displayedSymbols[other]
      body.watchlist.cursorSymbol = target
      keyClick(Qt.Key_Return)
      var ended = !body.motion.replayRunning && body.scrubT === 0
      harness.check("featuring a row during a replay ends that replay and its scrub",
        started && ended && service.featuredSymbol === target && within(5000, function() { return body.chartSymbol === target && !body.chartLoading }))
    }

    // The sleep state is part of what the animal says. Its eye-close and
    // first-frame appearance are separate judgments in sleepFrames.
    function sleepStates(body) {
      service.setRange("1D")
      service.feature("DOWN")
      tryVerify(function() { return body.chartSymbol === "DOWN" && !body.chartLoading }, 5000)
      var close = service.quotes.DOWN.session.post.end
      var wake = close + 2 * 86400
      service.testClockHeld = true
      var bells = []
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        service.now = close - 60
        var awake = within(2000, function() { return !body.animal.asleep })
        service.now = close + 2
        var closed = within(2000, function() { return body.animal.asleep })
        service.now = wake - 60
        var asleep = within(2000, function() { return body.animal.asleep })
        service.now = wake + 2
        var opened = within(2000, function() { return !body.animal.asleep })
        bells.push(look + ":" + [awake, closed, asleep, opened].join(","))
      })
      harness.check("the clock closes and wakes the animal with its market in both looks",
        bells.join("|") === "smooth:true,true,true,true|retro:true,true,true,true", bells.join("|"))
      service.persist({ style: "smooth" })
      service.now = close + 2
      var below = body.featuredDay.points.filter(function(p) { return p.p < body.featuredDay.prevClose })
      body.motion.scrubT = below[below.length - 1].t
      var scrubAwake = within(2000, function() { return !body.animal.asleep && body.animal.kind === "bear" })
      body.motion.clearScrub()
      harness.check("letting go of a scrub after the close puts the animal back to sleep",
        scrubAwake && within(2000, function() { return body.animal.asleep }))

      service.now = close
      lateDown.running = true
      tryVerify(function() { return !lateDown.running }, 2000)
      service.addSymbol("LATE")
      tryVerify(function() { return service.arriving.indexOf("LATE") < 0 }, 15000)
      service.feature("LATE")
      tryVerify(function() { return body.chartSymbol === "LATE" && !body.featuredQuote && body.animal.kind === "" }, 5000)
      lateUp.running = true
      tryVerify(function() { return !lateUp.running }, 2000)
      service.now = close + 15
      service.refresh()
      tryVerify(function() { return !!body.featuredQuote }, 8000)
      harness.check("a first quote landing on a retry after the close shows its animal asleep",
        body.animal.kind !== "" && body.animal.asleep)

      service.feature("DOWN")
      tryVerify(function() { return body.chartSymbol === "DOWN" && !body.chartLoading }, 5000)
      service.now = close - 60
      tryVerify(function() { return !body.animal.asleep }, 2000)
      app.close()
      service.now = close
      app.open("{}")
      harness.check("opening after the market closed shows its animal asleep",
        within(2000, function() { return body.animal.asleep }))
      service.testClockHeld = false
    }

    function test_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)
      if (Quickshell.env("STONKS_MOTION_FLOW") === "actions") {
        app.open("{}")
        tryVerify(function() { return !!app.testBody }, 3000)
        var body = app.testBody
        var keys = app.testKeyCatcher
        replayActions(body, keys)
        sixRows(body, "MSFT", "1D")
        dayActions(body, body.watchlist, keys)
        sleepStates(body)
        app.close()
        harness.finish()
        return
      }
      if (Quickshell.env("STONKS_MOTION_FLOW") === "rows") {
        app.open("{}")
        tryVerify(function() { return !!app.testBody }, 3000)
        rowPlaces(app.testBody, app.testBody.watchlist, app.testKeyCatcher)
        wheelKeepsLift(app.testBody, app.testBody.watchlist)
        app.close()
        harness.finish()
        return
      }

      // The window's first open in this process draws its chart in over
      // about 320 ms, as rendered: a draw-in spent before the window's first
      // frames, as the popup's first open once showed live, fails. Every
      // canvas paints a frame late on a window's first show (accepted in the
      // transition audit, look 2), so the pictures are judged from the first
      // that paints anything, when the first are blank, only the ground;
      // anything drawn on them is judged, its ink read against the empty
      // plot (`plot=`): those painted before the draw-in began may show
      // none, so a whole chart that flashes, clears, and then draws in
      // fails, and so does one painted part way ahead of its animation that
      // stays and sweeps on. Found in Codex's reviews of #33: timed from the
      // animation, those frames fell before zero and went unjudged, and read
      // against the first frame after the draw-in began, ink still there
      // was taken for the plot. Their times run from the
      // draw-in's own origin, read off the animation itself: its first step
      // after the reveal left whole, at its value, is that far along its
      // OutCubic, so the pictures are held to the moment the motion counts
      // from, which a picture drawn ahead of it fails against. Found under
      // load: timed from the first painted frame, which came from 17 ms
      // before the draw-in to about 30 ms after it, the start read 25 ms
      // early to 56 late, and failed at 25 and 32 early; timed from the
      // reveal leaving whole, 28 early to 32 late, since an animation
      // started between the clock's ticks can count from the tick before,
      // up to the tick's whole gap. AAPL's day waits for Robinhood's answer,
      // asked as a surface opens, and draws in when it lands.
      var drawFrom = 0
      var leftAt = -1
      var watchDraw = function() {
        var anim = app.testBody.motion.testDrawIn
        var r = app.testBody.motion.reveal
        if (leftAt < 0) {
          if (r < 1) leftAt = r
          return
        }
        if (drawFrom || r <= leftAt || anim.duration <= 0) return
        drawFrom = animationOrigin(anim, r)
      }
      // The body is built a second after the service is ready, before this
      // first open: the watch goes on it before the open. The open itself
      // holds the thread at most 150 ms.
      tryVerify(function() { return !!app.testBody }, 3000)
      var body = app.testBody
      body.motion.revealChanged.connect(watchDraw)
      var openedAt = Date.now()
      app.open("{}")
      var firstOpen = Date.now() - openedAt
      harness.check("the window's first open holds the thread at most 150 ms — " + firstOpen + " ms", firstOpen <= 150)
      grab.source = body.chartItem
      grab.begin("first-open")
      tryVerify(function() { return !body.chartLoading && body.motion.reveal === 1 }, 5000)
      var settledAt = grab.frames.length
      tryVerify(function() { return grab.frames.length >= settledAt + 4 }, 2000)
      grab.end()
      body.motion.revealChanged.disconnect(watchDraw)
      tryVerify(function() { return grab.waiting === 0 }, 3000)
      // The empty plot, read before the first judgement takes the ground.
      var plotPath = emptyPlot(body, "first-open")
      grab.judge("same")
      tryVerify(function() { return grab.verdict !== null }, 10000)
      var paintedAt = grab.start + (grab.verdict.blankBefore ? grab.verdict.changedAt : 0)
      // No draw-in at all is judged from the open, and fails as none.
      grab.start = drawFrom || grab.start
      grab.judge("drawin:ink:first", grab.frames.filter(function(f) { return f.at >= paintedAt }), ["plot=" + plotPath])
      tryVerify(function() { return grab.verdict !== null }, 10000)
      harness.check("the window's first open draws its chart in over about 320 ms — first painted "
        + (paintedAt - grab.start) + " ms from the draw-in's start | " + grab.verdict.detail, grab.verdict.ok)
      wait(200)
      var watchlist = body.watchlist
      var keys = app.testKeyCatcher

      sixRows(body, "MSFT", "1D")

      bellDrawIn(body)
      motionEnds(body, watchlist, keys)
      drawInFrames(body, keys)
      joinFrames(body, watchlist, keys)
      animalFrames(body)
      sleepFrames(body)
      closingHolds(body, watchlist, keys)
      // Each later open holds the thread at most 20 ms.
      var later = []
      for (var n = 0; n < 5; n++) {
        app.close()
        wait(200)
        var laterAt = Date.now()
        app.open("{}")
        later.push(Date.now() - laterAt)
        wait(400)
      }
      harness.check("each later open of the window holds the thread at most 20 ms — " + later.join(", ") + " ms", Math.max.apply(null, later) <= 20)
      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done }
}
