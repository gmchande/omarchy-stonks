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

  // The walk's clock, from Wednesday 7 October at 15:00 New York: the
  // service reads it, and a step moves it on and ticks the service.
  property int time: 1791399600
  function clockOn(seconds) {
    harness.time += seconds
    plugin.service.tick()
  }
  Stonks.Plugin { id: plugin; shell: shellApi; manifest: harness.pluginManifest(); hyprland: hyprlandStandIn
    wallClock: function() { return harness.time } }
  readonly property var service: plugin.service
  readonly property var app: plugin.windowHost.app

  QtObject { id: workspaceHere }
  // Hyprland as the plugin is handed it: no screens, no windows, no events.
  QtObject {
    id: hyprlandStandIn
    property var monitors: ({ values: [] })
    property var toplevels: ({ values: [] })
    property var focusedWorkspace: workspaceHere
    function monitorFor(screen) { return null }
    function refreshMonitors() {}
    function dispatch(request) {}
    signal rawEvent(var event)
  }

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

  // Called after each frame's bindings while a step sets it.
  property var onFrame: null
  Connections {
    target: harness.onFrame ? app.body.watchlist.Window.window : null
    function onAfterAnimating() { harness.onFrame() }
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
      return service.feeds.quotes.firstRun.length === 0 && service.feeds.quotes.refreshRun.length === 0
    }
    function settle() {
      if (!idle()) tryVerify(idle, 30000)
    }
    function tick(seconds, step, each) {
      for (var t = 0; t < seconds; t += step) {
        harness.clockOn(step)
        settle()
        if (each) each()
      }
    }

    // The rows, and the pill, that say "!" now: a row in sight by what it
    // shows, and one out of sight, which works out nothing until it comes
    // into sight, by what it would show there.
    function warned() {
      var body = app.body
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

    // Robinhood's listing answer, as the surface has it, handed to the
    // surface again with each symbol's read counted in `reads`: a US stock's
    // row reads its symbol's once each time it works out its day.
    function countedAllDay(reads) {
      var answer = app.body.allDay
      var out = {}
      service.allSymbols.forEach(function(s) {
        Object.defineProperty(out, s, { enumerable: true, get: function() { reads[s] = (reads[s] || 0) + 1; return answer[s] } })
      })
      app.body.allDay = out
    }
    // The rows in sight, by symbol, the featured one aside: the chart reads
    // its answer too.
    function rowsInSight() {
      var rows = app.body.watchlist.rowItems()
      return Object.keys(rows).filter(function(s) { return rows[s].inSight && s !== service.view.featured })
    }

    function test_cost() {
      // A tall window, many rows in sight.
      app.floatingWindow.implicitHeight = 1400
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)

      // Loading: the pill's chart and eight spark requests carry the list.
      // Then each day with a jump is judged on the chart, a few a run.
      for (var t = 0; t < 600 && (!service.allSymbols.every(function(s) { return !!service.quotes[s] }) || service.feeds.quotes.toJudge.length > 0); t++) {
        harness.clockOn(1)
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
        behind.length === 0 && steady.length <= 150 && runs.length <= 20 && warnedSteps === 0 && !service.yahooGate.warned,
        (steady.length / 10).toFixed(1) + " requests and " + (runs.length / 10).toFixed(1) + " runs a minute; behind: " + behind.slice(0, 5).join(",")
          + "; " + warnedSteps + " of 120 steps warned")

      // The rows built: those within a screen above sight and two below,
      // at the top, at the end of the list, and after the wheel has carried
      // it part of the way back.
      var list = app.body.watchlist
      // Counted as what was made, not what the list says should be: a row's
      // words and line are one `rowContent` each, built by its Loader.
      var built = function() { return harness.findAll(list, "rowContent").length }
      var nearSight = Math.ceil((3 * list.sightHeight + list.rowHeight) / list.rowPitch) + 1
      var rested = function() { return within(5000, function() { return !list.settling }) }
      list.contentY = 0
      rested()
      var atTop = built()
      // A glide to the end, frame by frame: the rows it shows, and those it
      // builds without showing.
      var shown = {}
      var passed = {}
      harness.onFrame = function() {
        var rows = list.rowItems()
        for (var s in rows) {
          if (rows[s].inSight) shown[s] = true
          else if (rows[s].built) passed[s] = true
        }
      }
      list.scrollToRow(list.displayedSymbols.length - 1)
      var moved = within(5000, function() { return !list.settling && list.contentY >= list.contentHeight - list.height - 1 })
      harness.onFrame = null
      var atEnd = built()
      var endRows = list.rowItems()
      var passedOver = Object.keys(passed).filter(function(s) { return !shown[s] && !endRows[s].built })
      for (var notch = 0; notch < 10; notch++) mouseWheel(list, 30, 30, 0, 120)
      rested()
      var back = built()
      harness.check("of 154 rows, only those near sight are built, wherever the list is scrolled, and a glide builds none it only passes over",
        moved && [atTop, atEnd, back].every(function(n) { return n > 0 && n <= nearSight }) && nearSight < 154 && passedOver.length === 0,
        [atTop, atEnd, back].join(", ") + " built of " + nearSight + " near sight; " + passedOver.length + " built only to be passed over")

      // Every row into sight once, then back at the top Robinhood answers.
      list.takeOver()
      for (var y = 0; y <= list.contentHeight; y += list.sightHeight / 2) list.contentY = list.clampY(y)
      list.contentY = 0
      rested()
      var answered = {}
      countedAllDay(answered)
      var seen = rowsInSight()
      var unseen = Object.keys(answered).filter(function(s) { return seen.indexOf(s) < 0 && s !== service.view.featured })
      harness.check("with every row seen once, a Robinhood answer is worked out once by each row in sight and by none out of sight",
        seen.some(function(s) { return answered[s] === 1 }) && seen.every(function(s) { return !(answered[s] > 1) }) && unseen.length === 0,
        seen.filter(function(s) { return answered[s] === 1 }).length + " of " + seen.length + " rows in sight worked it out once; "
          + unseen.length + " out of sight did")

      // To a list of ten and back: the rows out of sight keep the line they
      // drew, and those in sight show the latest.
      var rows = list.rowItems()
      var lines = {}
      for (var s in rows) lines[s] = rows[s].geometry
      service.switchList("Ten")
      tryVerify(function() { return list.displayedSymbols.length === 10 }, 3000)
      service.switchList("")
      tryVerify(function() { return list.displayedSymbols.length === 154 }, 3000)
      rested()
      var redrawn = Object.keys(rows).filter(function(s) { return !rows[s].inSight && rows[s].geometry !== lines[s] })
      var stale = Object.keys(rows).filter(function(s) { return rows[s].inSight && (rows[s].quote !== service.quotes[s] || !rows[s].day) })
      harness.check("a switch to a list and back redraws no row out of sight, and every row in sight shows its latest",
        redrawn.length === 0 && stale.length === 0,
        redrawn.length + " rows out of sight redrawn; in sight without their latest: " + stale.slice(0, 5).join(","))

      // A click on a row and a new range save the lists file, and All holds
      // the same stocks: the feeds go on as they were, and no other row works
      // out its figures again, the clicked stock's chart answer landing too.
      rows = list.rowItems()
      var figures = {}
      for (s in rows) figures[s] = rows[s].view
      var fed = service.feeds.quotes.symbols
      var clicked = rowsInSight()[1]
      var answer = service.entries[clicked]
      mouseMove(rows[clicked], rows[clicked].width / 2, rows[clicked].height / 2)
      mouseClick(rows[clicked], rows[clicked].width / 2, rows[clicked].height / 2)
      var charted = within(5000, function() { return service.entries[clicked] !== answer && idle() })
      service.setRange("1W")
      service.setRange("1D")
      var reworked = Object.keys(rows).filter(function(s) { return s !== clicked && rows[s].view !== figures[s] })
      harness.check("a click on a row, its chart's answer and a new range hand the feeds the same stocks and work out no other row's figures again",
        service.view.featured === clicked && charted && service.feeds.quotes.symbols === fed && reworked.length === 0,
        "featured " + service.view.featured + " after a click on " + clicked + "; its chart answered: " + charted
          + "; feeds' stocks the same: " + (service.feeds.quotes.symbols === fed) + "; " + reworked.length + " other rows worked out again")

      app.close()
      harness.finish()
    }
  }
}
