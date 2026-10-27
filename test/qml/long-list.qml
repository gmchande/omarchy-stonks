import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugin" as Stonks
import "plugin/Figures.js" as Figures
import "plugin/Format.js" as Format

// A power user's list: 154 symbols through the real Plugin, Service, App,
// and a pill, on a clock this harness sets, from Wednesday 7 October 2026 at
// 15:00 New York, with the window open: a busy stock featured (TALL001, the
// AAPL day), a day with a stray print (STRAY), two days with no jump
// (SHOP.TO, BTC-USD), and 150 busy US stocks (LONG<n>, NEST's saved day at
// 14:55). The fake curl counts every request in requests.log and every curl
// call in runs.log.
Harness {
  id: harness
  marker: "LONG LIST DONE"

  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")

  function lines(name) {
    return readFile(harness.state + "/" + name).split("\n").filter(function(line) { return line !== "" })
  }

  Stonks.Plugin { id: plugin; shell: shellApi }
  readonly property var service: plugin.service
  readonly property var app: plugin.windowHost.app

  QtObject { id: workspaceHere }
  QtObject {
    id: hyprlandStandIn
    property var toplevels: ({ values: [] })
    property var focusedWorkspace: workspaceHere
    function dispatch(request) {}
  }
  Binding { target: plugin.windowHost; property: "hyprlandStandIn"; value: hyprlandStandIn }

  QtObject {
    id: shellApi
    function serviceFor() { return plugin }
    function isPluginOpen(id) { return false }
    function hide(id) {}
    function updateEntryInline(id, settings) { return true }
  }

  PluginBarApi {
    id: barApi
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
  }

  readonly property var pill: pillLoader.item
  FloatingWindow {
    id: pillWindow
    visible: true
    color: "#101315"
    implicitWidth: 320
    implicitHeight: 52
    Loader {
      id: pillLoader
      y: 10
      sourceComponent: Stonks.BarWidget {
        width: implicitWidth
        height: 32
        bar: barApi
        settings: ({ id: "grvc.stonks", barStyle: "text" })
      }
    }
  }

  Process { id: fileProc }

  // The window's rows' rendered frames, for frames.js.
  FrameGrab { id: grab }

  Steps {
    name: "LongList"
    when: service.pluginsReady && pillWindow.visible

    function runCommand(command) {
      fileProc.command = command
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }
    function touch(name) { runCommand(["touch", harness.state + "/" + name]) }
    function remove(name) { runCommand(["rm", "-f", harness.state + "/" + name]) }

    // No quote run is out: the clock moves on only once each run has
    // landed, as it would in the seconds a run takes.
    function idle() {
      return service.testFeed.firstRun.length === 0 && service.testFeed.refreshRun.length === 0
    }
    function settle() {
      if (!idle()) tryVerify(idle, 30000)
    }
    function tick(seconds, step, each) {
      for (var t = 0; t < seconds; t += step) {
        service.now += step
        settle()
        if (each) each()
      }
    }

    // The rows, and the pill, that say "!" now: a row in sight by what it
    // shows, and one out of sight, which works out nothing until it comes
    // into sight, by what it would show there.
    function warned() {
      var body = app.testBody
      var out = service.library.filter(function(s) {
        var row = body.watchlist.rowItem(s)
        if (row && row.inSight) return /^!/.test(row.detail)
        return Figures.freshnessWarns(Figures.freshness(service.entries[s] || null, service.quotes[s] || null, service.now, service.owed[s] || 0))
      })
      if (pill.warns) out.push("pill")
      return out
    }

    // Quote requests among `lines` ("kind name status"), by symbol: a
    // chart's one, and each of a spark's.
    function perSymbol(lines, kind) {
      var counts = {}
      lines.forEach(function(line) {
        var parts = line.split(" ")
        if (kind ? parts[0] !== kind : parts[0] !== "chart" && parts[0] !== "spark") return
        parts[1].split(",").forEach(function(s) { counts[s] = (counts[s] || 0) + 1 })
      })
      return counts
    }

    function test_longList() {
      var start = service.now
      // A tall window, many rows in sight: the glide below builds more of
      // them a frame.
      app.testWindow.implicitHeight = 1400
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)

      // Loading: the pill's chart and eight spark requests carry the list.
      // Each day with a jump no chart has judged is judged on the chart
      // after, from the budget's spare half, and so is each day whose open
      // spark can't send. No row says "No data" for any wait of Stonks' own.
      var loadWarned = []
      var answered = 0
      var wallStart = Date.now()
      var answeredWall = 0
      // Judging yields to a refresh: once the list has answered, the days
      // waiting to be judged are held at the fake curl, so a run of judging
      // is out when the minute passes; the run after it is the refresh.
      var yielded = ""
      var jumped = 0
      for (var t = 0; t < 600 && (!answered || service.testFeed.toJudge.length > 0); t++) {
        if (answered && !yielded && service.testFeed.toJudge.length > 0) {
          var holds = service.testFeed.toJudge.map(function(s) { return harness.state + "/" + s + ".quote.hold" })
          // A full budget, so the run of judging takes as many as it may.
          service.testYahooGate.tokens = service.testYahooGate.capacity
          runCommand(["touch"].concat(holds))
          var runsBefore = harness.lines("runs.log").length
          for (var j = 0; j < 30 && service.testFeed.refreshRun.length === 0; j++) {
            service.now += 1
            wait(20)
          }
          var judging = service.testFeed.refreshSlots.filter(function(slot) { return !slot.spark }).length
          var judgingOnly = judging > 0 && judging === service.testFeed.refreshSlots.length && judging <= service.testFeed.judgeRun
          service.now += 61
          jumped = 61
          runCommand(["rm", "-f"].concat(holds))
          tryVerify(function() { return idle() && harness.lines("runs.log").length >= runsBefore + 2 }, 30000)
          var after = harness.lines("runs.log").slice(runsBefore)
          yielded = judging + " charts judging | " + after.slice(0, 2).map(function(r) { return r.split(" ").map(function(u) { return u.split(":")[0] }).join(" ") }).join(" | ")
          harness.check("a refresh falling due while days are judged goes in the run after the judging one: the pill's chart and eight spark requests",
            judgingOnly && (after[0] || "").split(" ").length === judging && /^chart:TALL001( spark:\S+){8}$/.test(after[1] || ""), yielded)
        }
        service.now += 1
        settle()
        var w = warned()
        if (w.length) loadWarned.push((service.now - start) + " s: " + w.length)
        if (!answered && service.library.every(function(s) { return !!service.quotes[s] })) {
          answered = service.now - start
          answeredWall = Date.now() - wallStart
        }
      }
      var loadLines = harness.lines("requests.log")
      // The first quote run: GitHub's look goes in a run of its own as the
      // service starts.
      var firstRun = harness.lines("runs.log").filter(function(r) { return !/^manifest:/.test(r) })[0] || ""
      harness.check("154 symbols answer in one run, the pill's chart and eight spark requests, within 2 s of the clock and 15 s of the wall",
        answered > 0 && answered <= 2 && answeredWall <= 15000 && firstRun.split(" ").length === 9 && /^chart:TALL001( spark:\S+){8}$/.test(firstRun),
        "all answered at " + (answered || "never") + " s, " + (answeredWall / 1000).toFixed(1) + " s of the wall; first run "
          + firstRun.split(" ").map(function(u) { return u.split(":")[0] }).join(" "))
      harness.check("loading warns of nothing, and every day with a jump is judged within 5 minutes",
        loadWarned.length === 0 && service.testFeed.toJudge.length === 0 && service.now - start - jumped <= 300,
        loadWarned.slice(0, 3).join(", ") + (loadWarned.length > 3 ? " …" : "") + "; still to judge " + service.testFeed.toJudge.length
          + " after " + (service.now - start) + " s")
      var charted = perSymbol(loadLines, "chart")
      var stray = service.quotes.STRAY
      harness.check("a stray print in a spark day is judged on the chart and left out of the row's line; a day with no jump is charted once, for its open",
        charted.STRAY === 1 && !!stray && stray.droppedTimes.length === 1
          && !stray.points.some(function(p) { return p.t === stray.droppedTimes[0] })
          && charted["SHOP.TO"] === 1 && charted["BTC-USD"] === 1
          && service.quotes["SHOP.TO"].dayOpen > 0,
        "STRAY charted " + charted.STRAY + ", dropped " + (stray ? stray.droppedTimes.length : "-") + "; SHOP.TO " + (charted["SHOP.TO"] || 0) + ", BTC-USD " + (charted["BTC-USD"] || 0)
          + "; runs with STRAY: " + harness.lines("runs.log").filter(function(r) { return /STRAY/.test(r) }).map(function(r) { return r.split(" ").filter(function(u) { return /STRAY/.test(u) }).map(function(u) { return u.split(":")[0] }).join("+") + "/" + r.split(" ").length }).join(" "))

      // Ten minutes of trading: every row is due each minute. The list
      // refreshes whole each minute in a few requests, one curl a minute,
      // and no row or the pill warns.
      var reqFrom = harness.lines("requests.log").length
      var runFrom = harness.lines("runs.log").length
      var steadyWarned = 0
      tick(600, 5, function() { if (warned().length) steadyWarned++ })
      var steady = harness.lines("requests.log").slice(reqFrom)
      var runs = harness.lines("runs.log").slice(runFrom)
      var counts = perSymbol(steady)
      var behind = service.library.filter(function(s) { return (counts[encodeURIComponent(s)] || 0) < 9 })
      harness.check("ten minutes of trading: every row refreshed every minute, in at most 15 requests and 2 curl runs a minute",
        behind.length === 0 && steady.length <= 150 && runs.length <= 20 && steadyWarned === 0,
        (steady.length / 10).toFixed(1) + " requests and " + (runs.length / 10).toFixed(1) + " runs a minute; behind: " + behind.slice(0, 5).join(",")
          + "; first run " + (runs[0] || "").split(" ").map(function(u) { return u.split(":")[0] }).join(" ") + "; " + steadyWarned + " of 120 steps warned")
      // Spark sends no opens: each row's open, from its one chart, stays
      // through every spark refresh since, so since the open it reads from
      // the day's open, never from the first bar's close.
      var opened = service.library.filter(function(s) { return service.quotes[s] && service.quotes[s].openSession !== null })
      var openless = opened.filter(function(s) { return !(service.quotes[s].dayOpen > 0) })
      var sparked = opened.filter(function(s) { return service.quotes[s].closesOnly })
      harness.check("after ten minutes of spark refreshes, every opened row still has its day's open",
        opened.length > 100 && sparked.length > 100 && openless.length === 0,
        opened.length + " opened, " + sparked.length + " from spark, without an open: " + openless.slice(0, 5).join(","))

      // A glide from the top to the end of the list, and the wheel back up:
      // on every rendered frame each row in sight is drawn, its symbol, its
      // day line, and its price (frames.js `filled`, down each column),
      // though only rows near sight are built; and no frame waits on the
      // rows built as they come more than 100 ms after the last.
      var list = app.testBody.watchlist
      list.contentY = 0
      wait(100)
      var top = list.rowItem(list.displayedSymbols[0])
      // Each column where the row lays it out (WatchlistRow).
      var columns = [
        ["symbols", top.gap, 64],
        ["day lines", top.width - top.gap - top.priceWidth - top.gap - top.sparkWidth, top.sparkWidth],
        ["prices", top.width - top.gap - top.priceWidth, top.priceWidth]
      ]
      grab.source = list
      grab.begin("glide")
      wait(100)
      grab.markStart()
      list.scrollToRow(list.displayedSymbols.length - 1)
      tryVerify(function() { return !list.settling && list.contentY >= list.contentHeight - list.height - 1 }, 5000)
      var endY = list.contentY
      for (var notch = 0; notch < 10; notch++) mouseWheel(list, 30, 30, 0, 120)
      tryVerify(function() { return !list.settling }, 5000)
      wait(100)
      grab.end()
      tryVerify(function() { return grab.waiting === 0 }, 5000)
      var gaps = grab.frames.slice(1).map(function(f, k) { return f.at - grab.frames[k].at })
      var longestGap = Math.max.apply(null, gaps)
      // A row drawn empty leaves a bare run longer than a row's pitch; a
      // drawn one's words and dashed baseline never do.
      var verdicts = columns.map(function(c) {
        grab.judge("filled:" + Math.round(list.rowPitch) + ":" + Math.round(c[1]) + ",0," + Math.round(c[2]) + "," + Math.floor(list.height), null, [])
        tryVerify(function() { return grab.verdict !== null }, 10000)
        return { name: c[0], ok: grab.verdict.ok, detail: grab.verdict.detail }
      })
      harness.check("a glide down the whole list and the wheel back up draw every row's symbol, day line, and price in sight on every frame, no frame over 100 ms late",
        verdicts.every(function(v) { return v.ok }) && grab.frames.length >= 10 && longestGap <= 100 && endY > 0 && list.contentY < endY,
        verdicts.map(function(v) { return v.name + ": " + v.detail }).join("; ") + "; longest gap between frames " + longestGap + " ms; at "
          + Math.round(endY) + " then " + Math.round(list.contentY))

      // A row featured while its spark request is out: once that lands, the
      // hero's chart goes, so its line and the day's open have the bars'
      // opens. A member previewed through search rests on the hero: its
      // chart goes too.
      touch("LONG020.quote.hold")
      service.now += 60
      tryVerify(function() { return service.testFeed.refreshRun.indexOf("LONG020") >= 0 }, 5000)
      service.feature("LONG020")
      remove("LONG020.quote.hold")
      tryVerify(function() { return idle() && !!service.quotes.LONG020 && !service.quotes.LONG020.closesOnly }, 15000)
      var featuredDay = service.quotes.LONG020
      service.preview(app.testBody, "LONG030")
      tryVerify(function() { return service.previewRests }, 3000)
      tryVerify(function() { return idle() && !!service.quotes.LONG030 && !service.quotes.LONG030.closesOnly }, 15000)
      var previewDay = service.quotes.LONG030
      harness.check("a row featured while its spark request is out, and a member previewed, each get the chart, with the day's open",
        !featuredDay.closesOnly && featuredDay.dayOpen > 0 && !previewDay.closesOnly && previewDay.dayOpen > 0,
        "featured " + featuredDay.closesOnly + " " + featuredDay.dayOpen + ", previewed " + previewDay.closesOnly + " " + previewDay.dayOpen)
      service.preview(app.testBody, "")
      service.feature("TALL001")
      settle()

      // The budget nearly spent and slow to refill: every row falls due and
      // waits its turn for minutes, on Stonks' own pacing alone. No row and
      // not the pill warns; once the budget is back, every row refreshes.
      var gate = service.testYahooGate
      harness.check("loading, ten minutes of trading, a glide and a row featured mid-refresh are never held back by Yahoo's budget", !gate.warned)
      var refill = gate.perMinute
      gate.perMinute = 4
      gate.tokens = 0
      var heldWarned = 0
      var heldMost = 0
      tick(240, 5, function() {
        if (warned().length) heldWarned++
        heldMost = Math.max(heldMost, Object.keys(service.asked).length)
      })
      gate.perMinute = refill
      var heldFrom = service.now
      tick(120, 5)
      var caughtUp = service.library.every(function(s) { return service.entries[s].answeredAt >= heldFrom })
      harness.check("refreshes held back by the budget alone for four minutes warn of nothing, and land once it refills",
        heldMost >= 100 && heldWarned === 0 && caughtUp, heldMost + " waiting at most, " + heldWarned + " steps warned, caught up " + caughtUp)

      // Yahoo refusing: nothing more goes for the pause. Each symbol's
      // update is overdue 90 s after its wait on Yahoo began: at once for
      // those waiting at the refusal, and as each falls due after it. Once
      // every one is, the window's header says so once, and the rows in
      // sight warn of nothing each; the pill still warns.
      touch("YAHOO.refuse")
      var refusedAt = 0
      tick(70, 1, function() { if (!refusedAt && service.testYahooGate.pause === "refused") refusedAt = service.now })
      var firstWarnAt = 0
      var allWarnAt = 0
      var saidOnce = ""
      var overdue = function() {
        return service.library.filter(function(s) {
          return Figures.freshnessWarns(Figures.freshness(service.entries[s] || null, service.quotes[s] || null, service.now, service.owed[s] || 0))
        }).length + (pill.warns ? 1 : 0)
      }
      tick(170, 5, function() {
        var count = overdue()
        if (!firstWarnAt && count > 0) firstWarnAt = service.now - refusedAt
        if (!allWarnAt && count === service.library.length + 1) {
          allWarnAt = service.now - refusedAt
          var body = app.testBody
          var rowsWarning = service.library.filter(function(s) {
            var row = body.watchlist.rowItem(s)
            return row && row.inSight && /^!/.test(row.detail)
          })
          saidOnce = body.headerText + " | " + rowsWarning.length + " rows in sight warn"
        }
      })
      var refusedWords = /^Turned away by the price source · Trying again at \d\d:\d\d \| 0 rows in sight warn$/
      harness.check("Yahoo refusing: nothing warns for 85 s, then the pill and every symbol's update is overdue within 90 s of falling due, and the header says it once instead of every row, with why and when Stonks tries again",
        refusedAt > 0 && firstWarnAt >= 85 && allWarnAt > 0 && allWarnAt <= 155 && refusedWords.test(saidOnce),
        "refused at " + (refusedAt - start) + " s; first warning " + firstWarnAt + " s after, all " + allWarnAt + " s after; " + overdue() + " overdue now; " + saidOnce)
      // The time the header names is when Stonks asks Yahoo again: the
      // refusal that answers it begins the next pause in that minute.
      var named = (/Trying again at (\d\d:\d\d)$/.exec(app.testBody.headerText) || [])[1]
      var pausedUntil = gate.pausedUntil
      for (var waited = 0; waited < 31 * 60 && gate.pausedUntil === pausedUntil; waited++) tick(1, 1)
      var askedAt = Format.hhmm(gate.now(), Format.readerOffset(gate.now()))
      harness.check("Yahoo refusing: Stonks asks again in the minute the header names",
        !!named && askedAt === named, "named " + named + ", asked again at " + askedAt)
      remove("YAHOO.refuse")
      harness.finish()
    }
  }
}
