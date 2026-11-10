import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Ui
import "plugin" as Stonks
import "plugin/Freshness.js" as Freshness
import "plugin/Format.js" as Format

// What a long list costs, counted: 154 symbols through the real Plugin,
// Service, App and a pill, on a clock this walk sets, from Wednesday 7
// October 2026 at 15:00 New York, with the window open. The fake curl logs
// every request it answers and every curl run. A count that grows is a
// stall on the shell's one thread or a refusal from Yahoo; no step reads a
// millisecond.
Harness {
  id: harness
  marker: "COST DONE"

  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")

  function lines(name) {
    return readFile(harness.state + "/" + name).split("\n").filter(function(line) { return line !== "" })
  }

  Stonks.Plugin { id: plugin; shell: shellApi; manifest: harness.pluginManifest() }
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
        moduleName: "grvc.stonks"
        settings: ({ id: "grvc.stonks", barStyle: "text" })
      }
    }
  }

  Process { id: fileProc }

  Steps {
    name: "Cost"
    when: service.ready && pillWindow.visible

    function runCommand(command) {
      fileProc.command = command
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }

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
      var out = service.allSymbols.filter(function(s) {
        var row = body.watchlist.rowItem(s)
        if (row && row.inSight) return /^!/.test(row.detail)
        return Freshness.freshnessWarns(Freshness.freshness(service.entries[s] || null, service.quotes[s] || null, service.now, service.owed[s] || 0))
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

    function test_cost() {
      // A tall window, many rows in sight.
      app.testWindow.implicitHeight = 1400
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)

      // Loading: the pill's chart and eight spark requests carry the list.
      // Then each day with a jump is judged on the chart, a few a run.
      for (var t = 0; t < 600 && (!service.allSymbols.every(function(s) { return !!service.quotes[s] }) || service.testFeed.toJudge.length > 0); t++) {
        service.now += 1
        settle()
      }
      // The first quote run: GitHub's look, and the stock's cap and P/E, go
      // in runs of their own.
      var firstRun = harness.lines("runs.log").filter(function(r) { return /^(chart|spark):/.test(r) })[0] || ""
      harness.check("154 symbols answer in one run of nine requests: the pill's chart and eight for the rest",
        service.allSymbols.length === 154 && service.allSymbols.every(function(s) { return !!service.quotes[s] })
          && /^chart:TALL001( spark:\S+){8}$/.test(firstRun),
        service.allSymbols.length + " symbols; first run " + firstRun.split(" ").map(function(u) { return u.split(":")[0] }).join(" "))

      // Ten minutes of trading: every row is due each minute.
      var reqFrom = harness.lines("requests.log").length
      var runFrom = harness.lines("runs.log").length
      var warnedSteps = 0
      tick(600, 5, function() { if (warned().length) warnedSteps++ })
      var steady = harness.lines("requests.log").slice(reqFrom)
      var runs = harness.lines("runs.log").slice(runFrom)
      var counts = perSymbol(steady)
      var behind = service.allSymbols.filter(function(s) { return (counts[encodeURIComponent(s)] || 0) < 9 })
      harness.check("ten minutes of trading: every row refreshed every minute, in at most 15 requests and 2 curl runs a minute, and nothing warns",
        behind.length === 0 && steady.length <= 150 && runs.length <= 20 && warnedSteps === 0 && !service.testYahooGate.warned,
        (steady.length / 10).toFixed(1) + " requests and " + (runs.length / 10).toFixed(1) + " runs a minute; behind: " + behind.slice(0, 5).join(",")
          + "; " + warnedSteps + " of 120 steps warned")

      // The rows built: those within a screen above sight and two below,
      // at the top, at the end of the list, and back at the top.
      var list = app.testBody.watchlist
      var built = function() {
        var n = 0
        var boxes = list.contentItem.children
        for (var b = 0; b < boxes.length; b++)
          for (var k = 0; k < boxes[b].children.length; k++)
            if (boxes[b].children[k].built === true && boxes[b].children[k].place >= 0) n++
        return n
      }
      var nearSight = Math.ceil((3 * list.sightHeight + list.rowHeight) / list.rowPitch) + 1
      var rested = function() { return within(5000, function() { return !list.settling }) }
      list.contentY = 0
      rested()
      var atTop = built()
      list.scrollToRow(list.displayedSymbols.length - 1)
      var moved = within(5000, function() { return !list.settling && list.contentY >= list.contentHeight - list.height - 1 })
      var atEnd = built()
      for (var notch = 0; notch < 10; notch++) mouseWheel(list, 30, 30, 0, 120)
      rested()
      var back = built()
      harness.check("of 154 rows, only those near sight are built, wherever the list is scrolled",
        moved && [atTop, atEnd, back].every(function(n) { return n > 0 && n <= nearSight }) && nearSight < 154,
        [atTop, atEnd, back].join(", ") + " built of " + nearSight + " near sight")

      app.close()
      harness.finish()
    }
  }
}
