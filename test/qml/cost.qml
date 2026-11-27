import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Ui
import "plugin" as Stonks
import "plugin/Freshness.js" as Freshness
import "plugin/Format.js" as Format
import "plugin/Gate.js" as Gate

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

    // Robinhood's prints, as the surface has them, handed to the surface
    // again with each symbol's read counted in `reads`: a US stock's row
    // reads its symbol's once each time it works out its day.
    function countedNights(reads) {
      var answer = app.body.nights
      var out = {}
      service.allSymbols.forEach(function(s) {
        Object.defineProperty(out, s, { enumerable: true, get: function() { reads[s] = (reads[s] || 0) + 1; return answer[s] } })
      })
      app.body.nights = out
    }
    // The rows in sight, by symbol, the featured one aside: the chart reads
    // its answer too.
    function rowsInSight() {
      var rows = app.body.watchlist.rowItems()
      return Object.keys(rows).filter(function(s) { return rows[s].inSight && s !== service.view.featured })
    }
    // `source` again, each of `keys` read through a getter that counts in
    // `reads.n` while `reads.on`.
    function counted(source, keys, reads) {
      var out = {}
      keys.forEach(function(s) {
        Object.defineProperty(out, s, { enumerable: true, get: function() { if (reads.on) reads.n++; return source[s] } })
      })
      return out
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

      // A look switch swaps at once only the lines of the rows near sight,
      // the rest soon after, and a jump through the list straight after
      // shows no row in the old look.
      list.contentY = 0
      rested()
      var body = app.body
      var wearing = function() {
        var rows = list.rowItems()
        return Object.keys(rows).filter(function(s) { return rows[s].lineRetro === body.look.retro })
      }
      body.toggleStyle()
      var swapped = wearing().length
      var oldSeen = {}
      var framesSeen = 0
      harness.onFrame = function() {
        framesSeen++
        var rows = list.rowItems()
        for (var s in rows) if (rows[s].inSight && rows[s].visible && rows[s].lineRetro !== body.look.retro) oldSeen[s] = true
      }
      list.takeOver()
      list.contentY = list.clampY(list.contentHeight)
      // A frame drawn at the end, then a jump to the middle.
      within(1000, function() { return framesSeen > 0 })
      list.contentY = list.clampY(list.contentHeight / 2)
      var swept = within(3000, function() {
        var active = Object.keys(list.rowItems()).length
        return active > 0 && active <= nearSight && wearing().length === active
      })
      harness.onFrame = null
      body.toggleStyle()
      within(3000, function() {
        var active = Object.keys(list.rowItems()).length
        return active > 0 && wearing().length === active
      })
      harness.check("a look switch swaps at once only the lines of rows near sight, the rest soon after, and a jump straight after shows no row in the old look",
        swapped > 0 && swapped <= nearSight && swept && Object.keys(oldSeen).length === 0,
        swapped + " swapped at once of " + nearSight + " near sight; all swapped " + swept + "; old look seen on " + Object.keys(oldSeen).slice(0, 5).join(","))

      // Every row into sight once, then back at the top Robinhood answers.
      list.takeOver()
      for (var y = 0; y <= list.contentHeight; y += list.sightHeight / 2) list.contentY = list.clampY(y)
      list.contentY = 0
      rested()
      var answered = {}
      countedNights(answered)
      var seen = rowsInSight()
      var unseen = Object.keys(answered).filter(function(s) { return seen.indexOf(s) < 0 && s !== service.view.featured })
      harness.check("with every row seen once, a Robinhood answer is worked out once by each row in sight and by none out of sight",
        seen.some(function(s) { return answered[s] === 1 }) && seen.every(function(s) { return !(answered[s] > 1) }) && unseen.length === 0,
        seen.filter(function(s) { return answered[s] === 1 }).length + " of " + seen.length + " rows in sight worked it out once; "
          + unseen.length + " out of sight did")

      // To a list of ten and back: the recycled pool allocates no extra row
      // items, keeps only near-sight rows active, and every row in sight shows
      // its latest.
      var poolBefore = built()
      service.switchList("Ten")
      tryVerify(function() { return list.displayedSymbols.length === 10 }, 3000)
      var poolInTen = built()
      service.switchList("")
      tryVerify(function() { return list.displayedSymbols.length === 154 }, 3000)
      rested()
      var poolAfter = built()
      var rows = list.rowItems()
      var activeCount = Object.keys(rows).length
      var stale = Object.keys(rows).filter(function(s) { return rows[s].inSight && (rows[s].quote !== service.quotes[s] || !rows[s].day) })
      harness.check("a switch to a list and back recycles its row pool without allocating extra rows, and every row in sight shows its latest",
        poolBefore > 0 && poolBefore <= nearSight && poolInTen === poolBefore && poolAfter === poolBefore
          && activeCount <= nearSight && stale.length === 0,
        "pool=" + [poolBefore, poolInTen, poolAfter].join("/") + " active=" + activeCount + "/" + nearSight
          + "; in sight without their latest: " + stale.slice(0, 5).join(","))

      // Returning to a scrolled list asks Robinhood only for the rows visible
      // at the restored scroll position, never for the top rows of that list.
      var ovIdle = function() { return !service.feeds.overnight.busy && !service.feeds.listDates.busy && !service.overnightWanted() }
      list.takeOver()
      list.contentY = list.clampY(50 * list.rowPitch)
      var scrolledSym = list.displayedSymbols[51]
      tryVerify(function() { return service.rowsInSight().indexOf(scrolledSym) >= 0 }, 2000)
      tryVerify(ovIdle, 10000)
      service.switchList("Ten")
      tryVerify(function() { return list.displayedSymbols.length === 10 && list.contentY === 0 }, 2000)
      tryVerify(ovIdle, 10000)
      var clearFrom = function(entries) {
        var out = Object.assign({}, entries)
        service.allSymbols.forEach(function(s) {
          if (list.displayedSymbols.indexOf(s) < 0) delete out[s]
        })
        return out
      }
      var backFrom = harness.lines("requests.log").length
      service.feeds.overnight.entries = clearFrom(service.feeds.overnight.entries)
      service.feeds.listDates.entries = clearFrom(service.feeds.listDates.entries)
      service.switchList("")
      tryVerify(function() { return list.displayedSymbols.length === 154 && service.rowsInSight().indexOf(scrolledSym) >= 0 }, 2000)
      var restoredSight = service.rowsInSight().concat([service.view.featured])
      within(250, function() { return service.feeds.overnight.busy || service.feeds.listDates.busy })
      tryVerify(ovIdle, 15000)
      var backRh = harness.lines("requests.log").slice(backFrom).filter(function(l) { return /^overnight /.test(l) })
      var backExtra = [].concat.apply([], backRh.map(function(l) { return l.split(" ")[1].split(",") }))
        .filter(function(s) { return restoredSight.indexOf(s) < 0 })
      list.takeOver()
      list.contentY = 0
      tryVerify(ovIdle, 15000)
      rested()
      harness.check("returning to a scrolled list asks Robinhood only for its visible rows, never the skipped top",
        backRh.length > 0 && backExtra.length === 0,
        "sight=" + restoredSight.join(",") + " | requests=" + backRh.join(" | ") + " | extra=" + backExtra.join(","))

      // A click on a row and a new range save the lists file, and All holds
      // the same stocks: the feeds go on as they were, and no other row works
      // out its figures again, the clicked stock's chart answer landing too.
      rows = list.rowItems()
      var figures = {}
      for (var fs in rows) figures[fs] = rows[fs].view
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

      // Three costs, each counted as it is today, so a change that makes
      // one grow fails here: what the shell does every second a surface is
      // open, for each batch of prices, and for each new trade at night.
      settle()
      var quotesFeed = service.feeds.quotes
      var held = quotesFeed.quotes

      // A second of the clock. The header's count of stocks that warn and
      // the rows' day read no quote at its ticks.
      var reads = { on: false, n: 0 }
      var watched = counted(held, Object.keys(held), reads)
      quotesFeed.quotes = watched
      reads.on = true
      harness.clockOn(1)
      reads.on = false
      var unlanded = quotesFeed.quotes === watched
      quotesFeed.quotes = held
      settle()
      harness.check("a tick with the window open reads a stock's quote at most 22 times in all",
        unlanded && reads.n > 0 && reads.n <= 22, reads.n + " reads" + (unlanded ? "" : "; a quote run landed during the tick"))

      // A batch of prices for the rows in sight lands: the whole view is
      // made again, the stock on show's day with it.
      var fresh = Object.assign({}, held)
      rowsInSight().forEach(function(s) { fresh[s] = Object.assign({}, held[s]) })
      var batchReads = { on: true, n: 0 }
      quotesFeed.quotes = counted(fresh, Object.keys(fresh), batchReads)
      batchReads.on = false
      quotesFeed.quotes = held
      settle()
      harness.check("a batch of prices for the rows in sight reads a stock's quote at most 643 times in all",
        batchReads.n > 0 && batchReads.n <= 643, batchReads.n + " reads")

      // One stock's new trade: the service hands the surfaces a new map of
      // newest trades, and only the rows in sight (and breadth) read it.
      var trades = service.newestTrades
      var tradeReads = { on: true, n: 0 }
      service.newestTrades = counted(trades, service.allSymbols, tradeReads)
      tradeReads.on = false
      service.newestTrades = trades
      harness.check("one stock's new trade reads the newest trades at most 175 times in all",
        tradeReads.n > 0 && tradeReads.n <= 175, tradeReads.n + " reads")

      // Night trading on the 154-stock list, sorted by % change: whole-list
      // quotes land up front while fuller overnight bars stay to rows in
      // sight, so scrolling through all 154 rows keeps sort order and breadth
      // unchanged and stays inside Robinhood's budget with no "!". With the
      // window closed, only the pill's stock is asked. Even when the budget
      // does pace requests, no row says "Refresh failed", while a real
      // Robinhood outage still warns on US rows trading tonight and leaves
      // non-US listings alone.
      var rhGate = service.feeds.lastTrade.gate
      var rhIdle = function() {
        var f = service.feeds
        return idle() && !f.overnight.busy && !f.lastTrade.busy && !f.listDates.busy
      }
      var settleAll = function() {
        tryVerify(function() { return rhIdle() && (!service.overnightWanted() || rhGate.paused) }, 15000)
        tryVerify(rhIdle, 15000)
      }
      runCommand(["sh", "-c", "echo listings-2026-10-07-1455 > \"$STONKS_FAKE_STATE/overnight.set\" && echo '2026-10-08T04:45:00.000Z 248.04' > \"$STONKS_FAKE_STATE/NIGHT.trade\""])
      service.feeds.overnight.entries = ({})
      service.feeds.listDates.entries = ({})
      service.feeds.lastTrade.entries = ({})
      rhGate.gate = Gate.openGate(rhGate.capacity)
      rhGate.budgetDueAt = 0
      app.floatingWindow.implicitHeight = 800
      service.persist({ order: "pct", reversed: false })
      body.featureSymbol("LONG005")
      list.takeOver()
      list.contentY = 0
      var nightStart = harness.lines("requests.log").length
      harness.time = 1791434760 // Thu 8 Oct 2026 00:46 NY
      service.tick()
      settleAll()
      var openSight = service.rowsInSight().concat([service.view.featured])
      var openOvAsked = [].concat.apply([], harness.lines("requests.log").slice(nightStart)
        .filter(function(l) { return /^overnight /.test(l) })
        .map(function(l) { return l.split(" ")[1].split(",") }))
      var unseenOv = openOvAsked.filter(function(s) { return openSight.indexOf(s) < 0 })
      var orderBefore = list.displayedSymbols.join(",")
      var breadthBefore = JSON.stringify(body.breadth)
      var upBefore = body.breadth.up
      var orderDrift = 0
      var breadthDrift = 0
      for (var stop = 1; stop <= 12; stop++) {
        list.contentY = list.clampY(stop * 6 * list.rowPitch)
        harness.clockOn(2)
        settleAll()
        if (list.displayedSymbols.join(",") !== orderBefore) orderDrift++
        if (JSON.stringify(body.breadth) !== breadthBefore) breadthDrift++
      }
      list.contentY = 0
      harness.clockOn(36)
      settleAll()
      var scrollFailed = Object.keys(service.nightFailed)
      var scrollRows = list.rowItems()
      var scrollWarned = Object.keys(scrollRows).filter(function(s) { return scrollRows[s].inSight && /^!/.test(scrollRows[s].detail) })
      harness.check("154 stocks sorted by change at night: whole-list quotes keep sort order and breadth steady while scrolling, bars stay to rows in sight, and Robinhood's budget holds",
        upBefore >= 150 && unseenOv.length === 0 && orderDrift === 0 && breadthDrift === 0
          && !rhGate.warned && scrollFailed.length === 0 && scrollWarned.length === 0,
        "upBefore=" + upBefore + "; unseenOv=" + unseenOv.length + "; orderDrift=" + orderDrift + "; breadthDrift=" + breadthDrift
          + "; gate warned=" + rhGate.warned + "; nightFailed=" + scrollFailed.length + "; warnedInSight=" + scrollWarned.slice(0, 5).join(","))

      // Five steady-state minutes at night with the window open (whole-list
      // quotes in batches of 75 + bars for rows in sight), then five closed
      // (pill's stock alone).
      var rhOnly = function(lines) { return lines.filter(function(l) { return /^(overnight|instruments|lasttrade) /.test(l) }) }
      var steadyOpenFrom = harness.lines("requests.log").length
      for (var m1 = 0; m1 < 5; m1++) { harness.clockOn(60); settleAll() }
      var steadyOpen = rhOnly(harness.lines("requests.log").slice(steadyOpenFrom))
      app.close()
      tryVerify(function() { return service.openSurfaces.length === 0 }, 3000)
      var steadyClosedFrom = harness.lines("requests.log").length
      for (var m2 = 0; m2 < 5; m2++) { harness.clockOn(60); settleAll() }
      var steadyClosed = rhOnly(harness.lines("requests.log").slice(steadyClosedFrom))
      var closedExtra = steadyClosed.filter(function(l) { return l.split(" ")[1] !== "LONG005" })
      harness.check("154 stocks steady state at night: at most 3.2 Robinhood requests/min open and 1.2/min closed (pill alone)",
        steadyOpen.length <= 16 && steadyClosed.length <= 7 && closedExtra.length === 0 && !rhGate.warned,
        "open=" + (steadyOpen.length / 5).toFixed(1) + "/min (" + steadyOpen.length + " in 5m); closed=" + (steadyClosed.length / 5).toFixed(1)
          + "/min (" + steadyClosed.length + " in 5m); closedExtra=" + closedExtra.slice(0, 3).join(","))
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)
      list = app.body.watchlist
      list.takeOver()
      list.contentY = 0
      settleAll()

      // Force the local budget dry (not paused) right before the next minute's
      // refresh: it waits on budgetDueAt without stamping any row failed, then
      // lands once a token refills.
      var beforePace = service.feeds.lastTrade.entries.LONG005 ? service.feeds.lastTrade.entries.LONG005.at : 0
      harness.clockOn(59)
      settleAll()
      rhGate.gate = Object.assign({}, rhGate.gate, { left: 0, filledAt: harness.time, warned: true })
      harness.clockOn(1)
      var pacedAt = harness.time
      within(2000, function() { return rhGate.budgetDueAt > pacedAt })
      var pacedRows = list.rowItems()
      var pacedWarned = Object.keys(pacedRows).filter(function(s) { return pacedRows[s].inSight && /^!/.test(pacedRows[s].detail) })
      var pacedFailed = Object.keys(service.nightFailed)
      var pacedDue = rhGate.budgetDueAt
      for (var p = 0; p < 5 && rhGate.budgetDueAt > harness.time; p++) {
        harness.time = rhGate.budgetDueAt
        service.tick()
        tryVerify(rhIdle, 15000)
      }
      settleAll()
      var refilledAt = service.feeds.lastTrade.entries.LONG005 ? service.feeds.lastTrade.entries.LONG005.at : 0
      harness.check("when Robinhood's budget holds a night refresh back, no row says Refresh failed and it lands once refilled",
        pacedWarned.length === 0 && pacedFailed.length === 0 && pacedDue > pacedAt && refilledAt >= pacedDue && refilledAt > beforePace,
        "pacedWarned=" + pacedWarned.slice(0, 5).map(function(s) { return s + ":" + pacedRows[s].detail }).join(" | ")
          + "; pacedFailed=" + pacedFailed.length + "; due=" + (pacedDue - pacedAt) + "s; refilled=" + (refilledAt - beforePace) + "s")

      // Real Robinhood outage still warns on US rows trading tonight (and the
      // featured row) after the 2 s probe fails too, while leaving a single
      // blip and non-US SHOP.TO normal, and clears once back.
      runCommand(["touch", harness.state + "/ROBINHOOD.offline"])
      rhGate.gate = Gate.openGate(rhGate.capacity)
      harness.clockOn(60)
      settleAll()
      var blipFailed = Object.keys(service.nightFailed).length
      if (rhGate.pausedUntil > harness.time) harness.time = rhGate.pausedUntil
      else harness.time += 5
      service.tick()
      settleAll()
      var downRows = list.rowItems()
      var long5Down = downRows.LONG005 ? downRows.LONG005.detail : ""
      var shopDown = downRows["SHOP.TO"] ? downRows["SHOP.TO"].detail : ""
      runCommand(["rm", "-f", harness.state + "/ROBINHOOD.offline"])
      if (rhGate.pausedUntil > harness.time) harness.time = rhGate.pausedUntil
      else harness.time += 60
      service.tick()
      settleAll()
      var backRows = list.rowItems()
      var long5Back = backRows.LONG005 ? backRows.LONG005.detail : ""
      runCommand(["rm", "-f", harness.state + "/overnight.set", harness.state + "/NIGHT.trade"])
      harness.check("a real Robinhood outage still shows Refresh failed on US rows trading tonight, leaves SHOP.TO normal, and clears once back",
        blipFailed === 0 && /^! Refresh failed · overnight /.test(long5Down) && !/^!/.test(shopDown) && !/^!/.test(long5Back),
        "blipFailed=" + blipFailed + " | down=" + long5Down + " | SHOP.TO=" + shopDown + " | back=" + long5Back)

      app.close()
      harness.finish()
    }
  }
}
