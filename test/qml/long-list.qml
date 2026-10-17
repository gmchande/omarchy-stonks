import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugin" as Stonks
import "plugin/Figures.js" as Figures

// A power user's list: 154 symbols through the real Plugin, Service, App,
// and a pill, on a clock this harness sets, from Wednesday 7 October 2026 at
// 15:00 New York, with the window open: a busy stock featured (TALL001, the
// AAPL day), a day with a stray print (STRAY), two days with no jump
// (SHOP.TO, BTC-USD), and 150 busy US stocks (LONG<n>, NEST's saved day at
// 14:55). The fake curl counts every request in requests.log and every curl
// call in runs.log. long-list.sh runs this twice: the main run, and the slow
// run (STONKS_LONG_RUN=slow), on a network that takes 3 s a request.
ShellRoot {
  id: harness

  property int failures: 0
  readonly property string mode: Quickshell.env("STONKS_LONG_RUN") || "main"
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  // A fake curl record, read through a fresh view: a FileView that has
  // loaded once returns its old text straight after reload().
  function record(name) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = harness.state + "/" + name
    var text = String(view.text() || "")
    view.destroy()
    return text
  }
  function lines(name) {
    return record(name).split("\n").filter(function(line) { return line !== "" })
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

  TestCase {
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

    function test_slow() {
      if (harness.mode !== "slow") skip("the main run")
      // Every request takes 3 s, as on a weak hotspot: the whole list still
      // answers in one run of a few requests, none of them cut short.
      var began = Date.now()
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)
      var all = function() { return service.library.every(function(s) { return !!service.quotes[s] }) }
      for (var t = 0; t < 600 && !all(); t++) wait(100)
      var took = Date.now() - began
      harness.check("on a network that takes 3 s a request, all 154 symbols answer within 40 s",
        all() && took <= 40000, (took / 1000).toFixed(1) + " s, " + service.library.filter(function(s) { return !!service.quotes[s] }).length + " answered")
      console.log("LONG LIST SLOW DONE")
      done.exitCode = harness.failures ? 1 : 0
      done.start()
    }

    function test_longList() {
      if (harness.mode !== "main") skip("the slow run")
      var start = service.now
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)

      // Loading: the pill's chart and eight spark requests carry the list.
      // Each day with a jump no chart has judged is judged on the chart
      // after, from the budget's spare half. No row says "No data" for any
      // wait of Stonks' own.
      var loadWarned = []
      var answered = 0
      for (var t = 0; t < 600 && (!answered || service.testFeed.toJudge.length > 0); t++) {
        service.now += 1
        settle()
        var w = warned()
        if (w.length) loadWarned.push((service.now - start) + " s: " + w.length)
        if (!answered && service.library.every(function(s) { return !!service.quotes[s] })) answered = service.now - start
      }
      var loadLines = harness.lines("requests.log")
      var firstRun = harness.lines("runs.log")[0] || ""
      harness.check("154 symbols answer in one run, the pill's chart and eight spark requests, within 2 s",
        answered > 0 && answered <= 2 && firstRun.split(" ").length === 9 && /^chart:TALL001( spark:\S+){8}$/.test(firstRun),
        "all answered at " + (answered || "never") + " s; first run " + firstRun.split(" ").map(function(u) { return u.split(":")[0] }).join(" "))
      harness.check("loading warns of nothing, and every day with a jump is judged within 5 minutes",
        loadWarned.length === 0 && service.testFeed.toJudge.length === 0 && service.now - start <= 300,
        loadWarned.slice(0, 3).join(", ") + (loadWarned.length > 3 ? " …" : "") + "; still to judge " + service.testFeed.toJudge.length
          + " after " + (service.now - start) + " s")
      var charted = perSymbol(loadLines, "chart")
      var stray = service.quotes.STRAY
      harness.check("a stray print in a spark day is judged on the chart and left out of the row's line; days with no jump are never charted",
        charted.STRAY === 1 && !!stray && stray.droppedTimes.length === 1
          && !stray.points.some(function(p) { return p.t === stray.droppedTimes[0] })
          && !charted["SHOP.TO"] && !charted["BTC-USD"],
        "STRAY charted " + charted.STRAY + ", dropped " + (stray ? stray.droppedTimes.length : "-") + "; SHOP.TO " + (charted["SHOP.TO"] || 0) + ", BTC-USD " + (charted["BTC-USD"] || 0))

      // Ten minutes of trading: every row is due each minute. The list
      // refreshes whole each minute in a few requests, one curl a minute.
      var reqFrom = harness.lines("requests.log").length
      var runFrom = harness.lines("runs.log").length
      var steadyWarned = 0
      tick(600, 5, function() { if (warned().length) steadyWarned++ })
      var steady = harness.lines("requests.log").slice(reqFrom)
      var runs = harness.lines("runs.log").slice(runFrom)
      var counts = perSymbol(steady)
      var behind = service.library.filter(function(s) { return (counts[encodeURIComponent(s)] || 0) < 9 })
      harness.check("ten minutes of trading: every row refreshed every minute, in at most 15 requests and 2 curl runs a minute",
        behind.length === 0 && steady.length <= 150 && runs.length <= 20,
        (steady.length / 10).toFixed(1) + " requests and " + (runs.length / 10).toFixed(1) + " runs a minute; behind: " + behind.slice(0, 5).join(",")
          + "; first run " + (runs[0] || "").split(" ").map(function(u) { return u.split(":")[0] }).join(" "))
      harness.check("ten minutes of trading on a long list: no row or pill warns",
        steadyWarned === 0, steadyWarned + " of 120 steps warned")

      // A glide from the top to the end of the list, and the wheel back up:
      // on every rendered frame each row in sight is drawn (frames.js
      // `filled`, down the symbols' column), though only rows near sight
      // are built. The longest gap between frames is said, for the cost of
      // building rows as they come.
      var list = app.testBody.watchlist
      list.contentY = 0
      wait(100)
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
      grab.judge("filled:24:8,0,64," + Math.floor(list.height), null, [])
      tryVerify(function() { return grab.verdict !== null }, 10000)
      harness.check("a glide down the whole list and the wheel back up draw every row in sight on every frame",
        grab.verdict.ok && endY > 0 && list.contentY < endY,
        grab.verdict.detail + "; longest gap between frames " + Math.max.apply(null, gaps) + " ms; at " + Math.round(endY) + " then " + Math.round(list.contentY))

      // Yahoo refusing: nothing more goes for the pause. Each row says its
      // update is overdue 90 s after its wait on Yahoo began: at once for
      // those waiting at the refusal, and as each falls due after it.
      touch("YAHOO.refuse")
      var refusedAt = 0
      tick(70, 1, function() { if (!refusedAt && service.testYahooGate.pause === "refused") refusedAt = service.now })
      var firstWarnAt = 0
      var allWarnAt = 0
      tick(170, 1, function() {
        var count = warned().length
        if (!firstWarnAt && count > 0) firstWarnAt = service.now - refusedAt
        if (!allWarnAt && count === service.library.length + 1) allWarnAt = service.now - refusedAt
      })
      harness.check("Yahoo refusing: nothing warns for 85 s, then the pill and every row say their update is overdue within 90 s of falling due",
        refusedAt > 0 && firstWarnAt >= 85 && allWarnAt > 0 && allWarnAt <= 155,
        "refused at " + (refusedAt - start) + " s; first warning " + firstWarnAt + " s after, all " + allWarnAt + " s after; " + warned().length + " warn now")
      remove("YAHOO.refuse")
      // The pause has doubled twice by now: the next probe is up to five
      // minutes away, and its answer reopens Yahoo.
      var clearedAt = 0
      tick(480, 5, function() { if (!clearedAt && warned().length === 0) clearedAt = service.now - refusedAt })
      harness.check("Yahoo back: the next probe reopens it, and every warning clears", clearedAt > 0, (clearedAt || "never") + " s after the refusal")

      console.log("LONG LIST DONE")
      done.exitCode = harness.failures ? 1 : 0
      done.start()
    }
  }

  HarnessExit { id: done }
}
