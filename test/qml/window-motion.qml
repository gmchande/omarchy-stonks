import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks
import "plugin/Quote.js" as Quote

// The window as it moves, through the real App and Service with real keys
// and pointer, judged on its rendered frames and its rows' places: the
// review kit's, by chapter (charts, rows). HOME and curl are scratch.
Harness {
  id: harness
  marker: "WINDOW MOTION DONE"

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }
  // The hero chart's or the body's rendered frames, for frames.js.
  FrameGrab { id: grab }
  // The hero's figures' frames beside the chart's, as the dim lifts.
  FrameGrab { id: heroGrab }
  // Hold AAPL's history answer back, and let it go (see the fake curl).
  Process { id: holdAapl; command: ["touch", Quickshell.env("STONKS_FAKE_STATE") + "/AAPL.history.hold"] }
  Process { id: releaseAapl; command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/AAPL.history.hold"] }
  // AAPL's day cut at noon, and back (see the fake curl's overnight.set).
  Process { id: noonAapl; command: ["sh", "-c", "echo aapl-noon > \"$0/overnight.set\"", Quickshell.env("STONKS_FAKE_STATE")] }
  Process { id: wholeAapl; command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/overnight.set"] }
  Process { id: quoteFile }

  Steps {
    name: "WindowMotion"
    when: service.pluginsReady

    // The empty plot of `body`'s chart as it is now, on the grab's own
    // ground, saved as `name`-plot.ppm: its ink layers hidden and nothing
    // revealed, the baseline and the grid only, whatever the clip does. A
    // draw-in's ink is read against it (frames.js `plot=`), so one that
    // starts part drawn reads as part drawn, a failure, and is never taken
    // for too few frames and filmed again; read against the first frame
    // after the mark, ink already there would be taken for the plot. Call
    // it after grab.end(), before grab.judge(), which takes the ground away.
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
      openAt(body.chromeHeight + 7 * body.rowPitch)
    }

    // Closed, sized, and open again at that size: an offscreen window takes
    // a new size only as it opens. It is filmed once it has drawn there.
    function openAt(height) {
      app.close()
      app.testWindow.implicitHeight = height
      app.open("{}")
      tryVerify(function() { return app.testWindow.height === height }, 2000)
      waitForRendering(app.testBody)
    }

    // Retro's bell appears with the columns, judged only in the review kit.
    function bellDrawIn(body) {
      service.feature("AAPL")
      service.setRange("1D")
      // As the window opens, and as the range comes back to the day.
      service.persist({ style: "retro" })
      // Found afresh each frame: a range change makes the ticks again.
      var bell = function() { return harness.find(body.chartItem, "retroBell") }
      var curtain = harness.find(body.chartItem, "curtain")
      var ahead = function(draw) {
        var early = 0
        var seen = 0
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(function() { seen++; if (bell() && bell().visible && bell().x >= curtain.width) early++ })
        draw()
        within(1500, function() { return body.motion.reveal === 1 && !body.chartLoading })
        // A few frames of the whole chart, after the end.
        var whole = seen
        within(1000, function() { return seen >= whole + 3 })
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
      // stands whole until it lands. As the window opens.
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
    // whole in about 320 ms, for a symbol change in smooth and a range
    // change in retro: both reach the same draw-in. Judged on the pictures
    // (frames.js), not on `reveal`, which can move while the picture fades.
    function drawInFrames(body, keys) {
      var run = function(name, change) {
        grab.source = body.chartItem
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
          } else if (!drawFrom && r > leftAt) drawFrom = animationOrigin(body.motion.testDrawIn, r)
        }
        body.motion.revealChanged.connect(marked)
        change()
        tryVerify(function() { return !body.chartLoading && body.motion.reveal === 1 }, 5000)
        // A few frames of the whole picture, after the end.
        var settledAt = grab.frames.length
        tryVerify(function() { return grab.frames.length >= settledAt + 4 }, 2000)
        grab.end()
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
      ;[["smooth", "symbol"], ["retro", "range"]].forEach(function(film) {
        var look = film[0]
        service.persist({ style: look })
        service.setRange("1D")
        service.feature("AAPL")
        tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
        keys.forceActiveFocus()
        // Enter on the first row that is not AAPL's, or ] to the next range.
        var other = body.watchlist.displayedSymbols.findIndex(function(s) { return s !== "AAPL" })
        body.watchlist.cursorSymbol = body.watchlist.displayedSymbols[other]
        var drawn = run(film[1] + "-" + look, function() { keyClick(film[1] === "symbol" ? Qt.Key_Return : Qt.Key_BracketRight) })
        results.push(look + " " + film[1] + " " + (drawn.ok ? "ok" : "FAILED") + ": " + drawn.detail)
      })

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

      // The same capture and judge fail a wrong draw-in, retro after a
      // loading hold: the real animation made 160 ms. frames.js's own
      // cases fail the other wrong draw-ins on frames drawn in code.
      var fast = holds("retro", { from: 0, ms: 160 })
      service.persist({ style: "smooth" })
      service.setRange("1D")
      harness.check("a draw-in of 160 ms fails the same judgement — " + (fast.landed.ok ? "PASSED" : "failed") + ": " + fast.landed.detail,
        !fast.landed.ok)

      // And a wrong dim fails its own: the real one made at once.
      var sudden = holds("smooth", { delay: 250, dimMs: 0 })
      service.setRange("1D")
      harness.check("a dim at once fails the same judgement — " + (sudden.held ? "PASSED" : "failed") + ": " + sudden.heldDetail,
        !sudden.held)

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
      tryVerify(function() { return !watchlist.settling && watchlist.displayedSymbols.every(function(s) { return watchlist.rowResting(s) }) }, 2000)
      var joins = []
      var switches = []
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        tryVerify(function() { return body.retro === (look === "retro") }, 2000)
        waitForRendering(watchlist)
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
      // Marked before the change, or once it has returned (`after`): an
      // answer taken in holds the thread for its own work, which a loaded
      // machine stretches past a frame.
      var run = function(name, mode, change, after) {
        tryVerify(function() { return body.animal.kind === "bull" && bull.opacity === 1 }, 2000)
        grab.source = slot
        grab.begin(name)
        var at = grab.frames.length
        tryVerify(function() { return grab.frames.length >= at + 3 }, 2000)
        if (!after) grab.markStart()
        change()
        if (after) grab.markStart()
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
      // A range whose first fetch failed shows the day in its place, its
      // bull; the retry that lands down is another chart, so the bear comes
      // at once.
      service.feature("AAPL")
      service.setRange("1M")
      tryVerify(function() { return body.chartSymbol === "AAPL" && body.historyShown && !body.chartLoading && body.motion.drawn === 1 }, 5000)
      var month = service.testHistoryFeed.entries["AAPL|1M"]
      var monthAs = function(entry) {
        var next = Object.assign({}, service.testHistoryFeed.entries)
        next["AAPL|1M"] = entry
        service.testHistoryFeed.entries = next
      }
      monthAs(Object.assign({}, month, { status: "failed", history: null }))
      var standIn = within(2000, function() { return body.historyFailed && body.animal.kind === "bull" })
      var down = Object.assign({}, month.history, { baseline: 10 * service.quotes.AAPL.price })
      var retried = run("animal-retry", "turn:0", function() { monthAs(Object.assign({}, month, { history: down })) }, true)
      harness.check("a failed range's retry that lands down names the bear" + (retried.ok ? " — " + retried.detail : ""),
        standIn && retried.ok && !body.historyFailed && body.animal.kind === "bear", standIn + " " + body.animal.kind + ": " + retried.detail)
      monthAs(month)
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
      var icon = harness.find(body, "lookIcon")
      var bull = harness.find(body, "bullCells")
      var bear = harness.find(body, "bearCells")
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
        tryVerify(function() { return icon.cells === (body.retro ? 0 : 1) }, 2000)
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
      // sides of letting go, and no turn crossfades.
      service.now = close + 2
      var below = body.featuredDay.points.filter(function(p) { return p.p < body.featuredDay.prevClose })
      body.motion.scrubT = below[below.length - 1].t
      tryVerify(function() { return !body.animal.asleep && header.closing === 0 && body.animal.kind === "bear" }, 2000)
      // The scrub's own turn into the bear ends before the film.
      tryVerify(function() { return bull.opacity === 0 && bear.opacity === 1 }, 2000)
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
        // Past the look icon's 200 ms step and the breadth rule's ease.
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
      // waits for the rows' own colours to arrive, which a busy machine's
      // animation clock can run late.
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
      // Past the note's 2.5 s, which a closed surface holds on show.
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

      // By % change, a refresh re-ranks the rows the pointer holds; then
      // the surface closes and the pointer leaves: every frame after the
      // close is the same picture, and the next open shows the new order.
      service.setOrder("pct")
      rest()
      mouseMove(watchlist, 20, watchlist.rowPitch + 10)
      var held = within(1000, function() { return watchlist.sortHeld })
      var shown = watchlist.displayedSymbols.slice()
      var last = shown[shown.length - 1]
      var ranked = Object.assign({}, service.testFeed.quotes)
      ranked[last] = Object.assign({}, ranked[last], { prevClose: Quote.regularClose(ranked[last]) / 1.5 })
      service.testFeed.quotes = ranked
      var pending = within(1000, function() { return service.view.shown[0] === last })
        && watchlist.displayedSymbols.join() === shown.join()
      rest()
      grab.source = body
      grab.begin("closing-pointer-leaves")
      frames(3)
      grab.end()
      tryVerify(function() { return grab.waiting === 0 }, 3000)
      close()
      grab.resume()
      frames(3)
      mouseMove(body, 1, 1)
      frames(6)
      grab.end()
      var leaving = verdict()
      reopen()
      var laidOut = watchlist.displayedSymbols.join() === service.view.shown.join() && watchlist.displayedSymbols[0] === last
      harness.check("a closing surface holds the rows' order as the pointer leaves, and the next open lays them out at once"
        + (leaving.ok ? " — " + leaving.detail : ""), held && pending && leaving.ok && laidOut,
        [held, pending, laidOut].join(",") + ": " + leaving.detail)
      service.testFeed.quotes = quotesBefore
      service.setOrder("manual")
      rest()
    }

    // The rows' places frame by frame: real joins, a pointer hold ending,
    // and the scroll pulled back at a removal.
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
      var resting = function() { return !watchlist.settling && watchlist.displayedSymbols.every(function(s) { return watchlist.rowResting(s) }) }
      tryVerify(resting, 3000)
      var join = function(two, held) {
        service.removeSymbol("SLOW")
        service.removeSymbol("FLAT")
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") < 0 && watchlist.displayedSymbols.indexOf("FLAT") < 0 && resting() }, 3000)
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
        // Longer than a row's 160 ms slide, for one the pointer's leaving
        // set off to show.
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
      openAt(body.chromeHeight + 3 * body.rowPitch)
      tryVerify(resting, 3000)
      watchlist.contentY = watchlist.contentHeight - watchlist.height
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
        openAt(body.chromeHeight + 3 * body.rowPitch)
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

    function test_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)
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
      // frames fails. Every canvas paints a frame late on a window's first
      // show, so the pictures are judged from the first that paints
      // anything, when the first are blank, only the ground; anything drawn
      // on them is judged, its ink read against the empty plot (`plot=`):
      // those painted before the draw-in began may show none, so a whole
      // chart that flashes, clears, and then draws in fails, and so does one
      // painted part way ahead of its animation that stays and sweeps on.
      // Their times run from the draw-in's own origin, read off the
      // animation itself: its first step after the reveal left whole, at
      // its value, is that far along its OutCubic, so the pictures are held
      // to the moment the motion counts from, which a picture drawn ahead of
      // it fails against. An animation started between the clock's ticks
      // can count from the tick before, up to the tick's whole gap. AAPL's
      // day waits for Robinhood's answer, asked as a surface opens, and
      // draws in when it lands.
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
      // The body is built as the window first opens, before its draw-in
      // starts: the watch goes on it as it is built.
      var watchBody = function() { if (app.testBody) app.testBody.motion.revealChanged.connect(watchDraw) }
      app.testBodyChanged.connect(watchBody)
      app.open("{}")
      app.testBodyChanged.disconnect(watchBody)
      var body = app.testBody
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
      tryVerify(function() { return !body.chartLoading && body.motion.reveal === 1 }, 5000)
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
        var laterAt = Date.now()
        app.open("{}")
        later.push(Date.now() - laterAt)
        tryVerify(function() { return !body.chartLoading && body.motion.reveal === 1 }, 5000)
      }
      harness.check("each later open of the window holds the thread at most 20 ms — " + later.join(", ") + " ms", Math.max.apply(null, later) <= 20)
      app.close()
      harness.finish()
    }
  }

}
