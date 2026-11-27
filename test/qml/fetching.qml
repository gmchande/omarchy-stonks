import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui
import "plugin" as Stonks

// Fetching's promises, through the real Plugin, Service, App and two pills
// on a clock this walk sets, through Wednesday 7 October 2026 and the night
// after, New York time. The fake curl answers every listing from its saved
// day (test/fixtures/moments/fetch-2026-10-07): a busy US stock (NEST, the
// pill's), a thin one (KILN), an ETF (SPY), an index (^GSPC), a
// cryptocurrency (BTC-USD), London (SHEL.L), Tokyo (7203.T) and Toronto
// (SHOP.TO). It logs every request it answers, which each step counts.
Harness {
  id: harness
  marker: "FETCHING DONE"

  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")
  readonly property var listed: ["NEST", "KILN", "SPY", "^GSPC", "BTC-USD", "SHEL.L", "7203.T", "SHOP.TO"]
  // Midnight starting Wednesday 7 October, Saturday 10 October, Thanksgiving
  // (Thursday 26 November) and Saturday 28 November in New York.
  readonly property int wed7: 1791345600
  readonly property int sat10: 1791604800
  readonly property int thu26: 1795669200
  readonly property int sat28: 1795842000

  function at(day, hour, minute) {
    return day + hour * 3600 + (minute || 0) * 60
  }

  // A fake curl record.
  function record(name) {
    return readFile(harness.state + "/" + name)
  }

  // Every request answered, as "kind name status", in order.
  function requests() {
    return record("requests.log").split("\n").filter(function(line) { return line !== "" })
  }

  // Every curl call, its URLs as kind:name.
  function runs() {
    return record("runs.log").split("\n").filter(function(line) { return line !== "" })
  }

  function yahoo(lines) {
    return lines.filter(function(line) { return !/^(overnight|instruments|lasttrade) /.test(line) })
  }

  // Quote requests per listing among `lines`: a chart's symbol, and each of
  // a spark's.
  function quoteCounts(lines) {
    var counts = {}
    harness.listed.forEach(function(s) { counts[s] = 0 })
    lines.forEach(function(line) {
      var parts = line.split(" ")
      if (parts[0] !== "chart" && parts[0] !== "spark") return
      parts[1].split(",").forEach(function(name) {
        var symbol = name.replace("%5E", "^")
        if (symbol in counts) counts[symbol]++
      })
    })
    return counts
  }

  // The plugin as the shell composes it, with this harness as its shell.
  // The walk's clock, from Wednesday 7 October at 05:59 New York: the
  // service reads it, and a step sets it and ticks the service.
  property int time: 1791367140
  function clockTo(t) {
    harness.time = t
    plugin.service.tick()
  }
  Stonks.Plugin { id: plugin; shell: shellApi; manifest: harness.pluginManifest(); hyprland: hyprlandStandIn
    input: inputStandIn; wallClock: function() { return harness.time } }
  readonly property var service: plugin.service
  // A bad answer is tried again in a fifth of a second, not 2.5: the walk's
  // clock runs faster than the wall's.
  Binding { target: plugin.service.feeds.quotes; property: "retryAfter"; value: 200 }
  Binding { target: plugin.service.feeds.preview; property: "retryAfter"; value: 200 }
  Binding { target: plugin.service.feeds.overnight; property: "retryAfter"; value: 200 }
  Binding { target: plugin.service.feeds.lastTrade; property: "retryAfter"; value: 200 }
  readonly property var app: plugin.windowHost.app
  // The newest version's check, on the walk's clock: a step turns it on,
  // and says when Yahoo answers again, as the service does.
  Stonks.ReleaseFeed { id: release; clock: plugin.service }

  QtObject { id: workspaceHere }
  QtObject { id: workspaceThere }
  // The window as Hyprland lists it, on the workspace a step puts it.
  QtObject {
    id: stonksToplevel
    property string title: "Stonks"
    property var wayland: ({ appId: "org.quickshell" })
    property string address: "5ab1e"
    property var workspace: workspaceHere
  }
  // The input that wakes the screens, which a step moves: never the owner's
  // own keys and pointer.
  QtObject {
    id: inputStandIn
    property bool isIdle: false
  }
  // Hyprland as the plugin is handed it: the screens and the windows a step
  // gives it, each screen asked as the real ones are.
  QtObject {
    id: hyprlandStandIn
    property var monitors: ({ values: [] })
    property var toplevels: ({ values: [] })
    property var focusedWorkspace: workspaceHere
    // The screen a pill's panel sits on, which a step names.
    property var panelScreen: null
    function monitorFor(screen) { return panelScreen }
    function refreshMonitors() { monitors.values.forEach(function(m) { m.refresh() }) }
    function dispatch(request) {}
    // Hyprland's events, which ask the screens again while every one is
    // off. None come: only a step asks them.
    signal rawEvent(var event)
  }

  QtObject {
    id: barState
    property bool barHidden: false
  }

  QtObject {
    id: shellApi
    property var bar: barState
    function serviceFor() { return plugin }
    function isPluginOpen(id) { return false }
    function hide(id) {}
    function updateEntryInline(id, settings) { return true }
  }

  // The pill's hover as the shell's bar shows it: copied as the pointer
  // enters, and again whenever the pill asks.
  property string copiedHover: ""
  PluginBarApi {
    id: barApi
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
    _showTooltip: function(target, text) { harness.copiedHover = text }
    _hideTooltip: function(target) { harness.copiedHover = "" }
  }

  // A pill per screen, sharing the one service.
  readonly property var pill: pillLoader.item
  readonly property var otherPill: otherPillLoader.item
  Component {
    id: pillComponent
    Stonks.BarWidget {
      width: implicitWidth
      height: 32
      bar: barApi
      moduleName: "grvc.stonks"
      settings: ({ id: "grvc.stonks", barStyle: "text" })
    }
  }

  FloatingWindow {
    id: pillWindow
    visible: true
    color: "#101315"
    implicitWidth: 320
    implicitHeight: 104
    Loader { id: pillLoader; y: 10; sourceComponent: pillComponent }
    Loader { id: otherPillLoader; y: 62; sourceComponent: pillComponent }
  }

  Process { id: fileProc }

  // A screen as Hyprland reports it, for the window host (WindowHost.qml): on or
  // off, as it says when asked again, a turn later, as Hyprland's answer
  // comes, showing this workspace. It counts the asks it has not answered
  // yet (`screensHeard`). While `holding`, it answers none asked meanwhile,
  // and once let go, those all at once.
  QtObject {
    id: screenStandIn
    property bool on: true
    property var lastIpcObject: ({ dpmsStatus: true })
    property var activeWorkspace: workspaceHere
    property int unanswered: 0
    property bool holding: false
    property int held: 0
    function refresh() {
      unanswered++
      if (holding) held++
      else Qt.callLater(function() { screenStandIn.answer(1) })
    }
    function answer(asks) {
      screenStandIn.lastIpcObject = { dpmsStatus: screenStandIn.on }
      screenStandIn.unanswered -= asks
    }
    onHoldingChanged: {
      var asks = held
      if (holding || asks === 0) return
      held = 0
      Qt.callLater(function() { screenStandIn.answer(asks) })
    }
  }
  // A second screen, always on, showing the other workspace.
  QtObject {
    id: otherScreen
    property var lastIpcObject: ({ dpmsStatus: true })
    property var activeWorkspace: workspaceThere
    function refresh() { Qt.callLater(function() { otherScreen.lastIpcObject = { dpmsStatus: true } }) }
  }

  Steps {
    name: "Fetch"
    when: service.ready && pillWindow.visible

    function runCommand(command) {
      fileProc.command = command
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }
    function touch(name) { runCommand(["touch", harness.state + "/" + name]) }
    function remove(name) { runCommand(["rm", "-f", harness.state + "/" + name]) }

    // No feed has a run out, a quote feed's runs included: the clock moves
    // on only once each run has landed, as it would in the seconds a run
    // takes.
    function idle() {
      return Object.keys(service.feeds).every(function(name) {
        var feed = service.feeds[name]
        return feed.firstRun ? feed.firstRun.length === 0 && feed.refreshRun.length === 0 : !feed.busy
      }) && !service.opening
    }
    function settle() {
      verify(within(10000, idle), "a quote run never landed")
    }

    // Every ask of the screens answered. A step waits on this before it
    // counts what went while they were off, and before it turns one on, so
    // an answer still out, as on a loaded machine, can't report the next
    // state for the last one. The service trusts an answer for a second of
    // the wall clock (`screensClear`), so a step that needs it asked afresh
    // still waits that long first.
    function screensHeard() {
      tryVerify(function() { return screenStandIn.unanswered === 0 }, 5000)
    }
    // A run waiting on the stand-in screen's answer goes once it comes, a
    // turn or two later: let it come, and the run land.
    function answerScreens() {
      if (screenStandIn.unanswered === 0) return
      screensHeard()
      wait(20)
      settle()
    }

    // The clock moves on by `seconds`, a step at a time, each ask of the
    // screens answered and each run let land, as both are between the
    // service's seconds: the answer, not the next step, lets what waits on
    // it go. `each` is called after every step.
    function tick(seconds, step, each) {
      step = step || 5
      for (var t = 0; t < seconds; t += step) {
        harness.clockTo(harness.time + step)
        answerScreens()
        settle()
        if (each) each()
      }
    }

    // What every surface says about freshness now: the pills, and the rows
    // and hero of the window while it is open.
    function marks() {
      var out = []
      if (pill.warns) out.push("pill !")
      if (otherPill.warns) out.push("other pill !")
      if (app.opened) {
        var body = app.body
        var hero = harness.find(body, "hero")
        if (!hero || !hero.visible) out.push("! missing hero")
        else if (/^!/.test(hero.listingLead) || hero.freshnessText !== "") out.push("hero: " + hero.listingLead)
        harness.listed.forEach(function(s) {
          var row = body.watchlist.rowItem(s)
          if (!row || !row.visible || !harness.find(row, "rowContent")
              || row.y + row.height <= body.watchlist.contentY || row.y >= body.watchlist.contentY + body.watchlist.height)
            out.push("! missing visible row " + s)
          else if (/^!/.test(row.detail) || /^As of/.test(row.detail)) out.push(s + ": " + row.detail)
        })
      }
      return out
    }

    // Requests per listing in the window from `begin` (which sets the clock
    // to the window's start, or opens the window there) to `seconds` later,
    // its start in and its end out, against `want`. A symbol asked for on a
    // period may land a tick either side of the window's edge, so a count
    // may be one off; one expected never to be asked must not be at all.
    // `each` is called after every step of the clock (`tick`).
    // A count starts with nothing asked or out, so a step before can't
    // land its answers in it, as the fake curl logs a request as it answers.
    function countsOver(label, seconds, want, begin, each) {
      var before = Object.keys(service.asked).concat(service.feeds.quotes.landing.length > 0 ? ["a run out"] : [])
      var from = harness.requests().length
      begin()
      tick(seconds - 5, 5, each)
      var got = harness.quoteCounts(harness.requests().slice(from))
      var off = harness.listed.filter(function(s) { return want[s] === 0 ? got[s] !== 0 : Math.abs(got[s] - want[s]) > 1 })
      harness.check(label, before.length === 0 && off.length === 0,
        (before.length ? "asked before it: " + before.join(",") + " | " : "") + harness.listed.map(function(s) { return s + " " + got[s] + "/" + want[s] }).join(", "))
      return harness.requests().slice(from)
    }

    // The clock to `t`, everything due there asked (waiting on any expired
    // screen check so queued refreshes start before the window opens).
    function startAt(t) {
      return function() {
        harness.clockTo(t)
        answerScreens()
        settle()
      }
    }

    // The window opened where the last count's window ended, a step after
    // its last tick.
    function openAfter() {
      startAt(service.now + 5)()
      openWindow()
    }

    function counts(values) {
      var out = {}
      harness.listed.forEach(function(s, i) { out[s] = values[i] })
      return out
    }

    // Tall enough that every listing's row is in sight: a row out of sight
    // works out no freshness, so it could say nothing either way.
    function openWindow() {
      app.floatingWindow.implicitHeight = 1000
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)
      settle()
    }
    function closeWindow() {
      app.close()
      tryVerify(function() { return service.openSurfaces.length === 0 }, 3000)
    }

    function test_fetching() {
      var gate = service.yahooGate
      startAt(at(harness.wed7, 10, 45))()
      tick(60)

      // Nothing open: no other listing has its day judged on a chart.
      var judgedAway = harness.yahoo(harness.requests()).filter(function(l) { return /^chart /.test(l) && l.split(" ")[1] !== "NEST" })
      harness.check("nothing open: no listing but the pill's is asked a chart", judgedAway.length === 0, judgedAway.join(", "))

      // The window open with a row in sight: the rows drawn (it and the one
      // past each edge) have their days judged, and Robinhood is asked the
      // night's trades for them and the stock on show alone. A row scrolled
      // into sight has its trades asked at once.
      var nightsFrom = harness.requests().length
      app.floatingWindow.implicitHeight = 560
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)
      settle()
      var inSight = function() { return [].concat.apply([], service.sights.map(function(s) { return s.symbols })) }
      var traded = function(from) {
        return [].concat.apply([], harness.requests().slice(from).filter(function(l) { return /^overnight /.test(l) })
          .map(function(l) { return l.split(" ")[1].split(",") }))
      }
      var judged = within(10000, function() {
        return inSight().length > 0 && inSight().every(function(s) { return service.feeds.quotes.toJudge.indexOf(s) < 0 })
      })
      within(3000, function() { return traded(nightsFrom).length > 0 })
      var seen = inSight()
      var tradedUnseen = traded(nightsFrom).filter(function(s) { return s !== "NEST" && seen.indexOf(s) < 0 })
      var scrollFrom = harness.requests().length
      app.body.watchlist.scrollToRow(app.body.watchlist.displayedSymbols.indexOf("SPY"))
      var scrolledIn = within(3000, function() { return traded(scrollFrom).indexOf("SPY") >= 0 })
      harness.check("the window open: the rows in sight have their days judged, Robinhood is asked trades for no row out of sight, and a row scrolled into sight has them at once",
        judged && seen.indexOf("SPY") < 0 && tradedUnseen.length === 0 && scrolledIn,
        [judged, "in sight " + seen.join(","), "asked out of sight " + tradedUnseen.join(","), scrolledIn].join(" | "))
      settle()
      closeWindow()

      // By day: no row is kept fresh for a surface no screen shows.
      countsOver("11:00, nothing open: the pill's stock alone, every minute, though every market but Tokyo trades",
        900, counts([15, 0, 0, 0, 0, 0, 0, 0]), startAt(at(harness.wed7, 11, 0)))
      // London closes at 16:30, 11:30 here, half a minute before this
      // window ends: its last minute's request does not go.
      countsOver("11:15, the window open: every listing trading every minute, London until its close; Tokyo, closed, once in the quarter hour",
        900, counts([15, 15, 15, 15, 15, 14, 1, 15]), openAfter)
      var body = app.body

      // The next run, so r finds every answer older than 10 s.
      var runsNow = harness.runs().length
      for (var w = 0; w < 61 && harness.runs().length === runsNow; w++) tick(1, 1)
      tick(20)
      var runsBefore = harness.runs().length
      app.refresh()
      tick(2, 1)
      app.refresh()
      tick(3, 1)
      var rRuns = harness.runs().slice(runsBefore).filter(function(r) { return /chart:/.test(r) })
      harness.check("r twice within 5 s asks once", rRuns.length === 1, rRuns.join(" / "))

      // omarchy-shell's refresh asks as r does, through the shell's own
      // socket where the shell has one (Omarchy 4.0.6 has none).
      tick(20)
      var socketFrom = harness.runs().length
      var socket = Commons.IpcRegistry ? Commons.IpcRegistry.call(plugin.pluginId, "refresh", []) : null
      tick(2, 1)
      var socketRuns = harness.runs().slice(socketFrom).filter(function(r) { return /chart:/.test(r) })
      if (socket) harness.check("omarchy-shell's refresh reaches Stonks through the shell's own socket and asks again",
        socket.ran && socketRuns.length === 1, socket.ran + " | " + socketRuns.join(" / "))

      // A range's history is asked once, and kept a quarter hour: picked
      // again inside it, nothing is asked, and after it, once more.
      var asked = function() { return harness.calls("NEST.history") }
      // The month's chart on show: a count read sooner is of a selection
      // that hasn't reached the feed.
      var month = function() { return within(3000, function() { return body.historyShown && body.chartRange === "1M" }) }
      var day = function() { body.selectRange("1D"); within(3000, function() { return !body.historyActive }) }
      var historyFrom = asked()
      body.selectRange("1M")
      var once = month() && asked() === historyFrom + 1
      day()
      tick(300)
      body.selectRange("1M")
      var shown = month()
      // Time for a request that must not go.
      wait(700)
      var kept = shown && asked() === historyFrom + 1
      day()
      tick(900)
      body.selectRange("1M")
      var again = within(3000, function() { return asked() === historyFrom + 2 }) && month()
      day()
      harness.check("a range's history is asked once, kept a quarter hour, and asked again after it",
        once && kept && again, [once, kept, again, asked() - historyFrom].join(" "))

      // The rows' charts fetched ahead on a range stay theirs: back on it
      // from another, none is downloaded again inside its quarter hour.
      var rows = harness.listed.filter(function(s) { return s !== "NEST" })
      var aheadDone = function(range) {
        return rows.every(function(s) { var key = s + "|" + range; return !!service.histories[key] || !!service.aheadMissed[key] })
      }
      var onRange = function(range) { return body.historyShown && body.chartRange === range }
      body.selectRange("3M")
      var aheadIn = within(20000, function() { return onRange("3M") && aheadDone("3M") })
      // A row whose chart failed is tried again on a return.
      var held = rows.filter(function(s) { return !!service.histories[s + "|3M"] })
      var rowCalls = function() { return held.map(function(s) { return s + " " + harness.calls(s.replace("^", "%5E") + ".history") }).join(", ") }
      var rowsBefore = rowCalls()
      body.selectRange("6M")
      var sixIn = within(3000, function() { return onRange("6M") })
      body.selectRange("3M")
      var backIn = within(3000, function() { return onRange("3M") })
      // Time for a download that must not go.
      var rowsAgain = within(2000, function() { return rowCalls() !== rowsBefore })
      harness.check("back on a range inside its quarter hour, no row's chart fetched ahead is downloaded again",
        aheadIn && sixIn && backIn && !rowsAgain, [aheadIn, sixIn, backIn, rowsBefore + " -> " + rowCalls()].join(" | "))

      // r once the chart is over 10 s old, its chart in, then r again 3 s
      // later: the chart is downloaded once, as the quotes are asked once.
      tick(15)
      var heroFrom = asked()
      app.refresh()
      var heroIn = within(5000, function() { return asked() === heroFrom + 1 && !service.refreshing })
      tick(3, 1)
      app.refresh()
      var heroAgain = within(1000, function() { return asked() !== heroFrom + 1 })
      harness.check("r again 3 s after r's chart came downloads the chart no more", heroIn && !heroAgain, [heroIn, asked() - heroFrom].join(" "))
      settle()
      day()

      // Yahoo refuses: the run that meets it stops at that refusal, and is
      // the last for a pause of about a minute, then one request goes
      // alone. Back, the next lone request reopens it.
      var beforeRefusal = harness.requests().length
      touch("YAHOO.refuse")
      var askedAt = 0, metRefusal = []
      tick(70, 1, function() {
        if (askedAt || gate.pause !== "refused") return
        askedAt = service.now
        metRefusal = harness.requests().slice(beforeRefusal).filter(function(line) { return / 429$/.test(line) })
      })
      harness.check("Yahoo refusing: the run that meets it asks nothing after the refusal",
        metRefusal.length === 1, metRefusal.join(" | "))
      // The header names the trouble once a price is 90 s overdue: on to
      // 100 s after the refusal, wherever in the minute it came.
      var said = ""
      var refusedFrom = harness.requests().length
      var lone = []
      while (askedAt > 0 && service.now - askedAt < 100) tick(1, 1, function() {
        var sent = harness.yahoo(harness.requests().slice(refusedFrom)).length
        if (sent > lone.length) lone.push(service.now - askedAt)
        if (/busy/i.test(body.headerText)) said = body.headerText
      })
      harness.check("Yahoo refusing: the header says the server is busy and when Stonks tries again, nothing goes for the pause, then one request alone",
        askedAt > 0 && /^(The price server is busy|Server busy)/.test(said) && lone.length === 1 && lone[0] >= 48 && lone[0] <= 73,
        said + " | refused at " + askedAt + ", alone at " + lone.join(","))
      remove("YAHOO.refuse")
      var recovered = 0
      tick(180, 1, function() { if (!recovered && gate.pause === "" && idle() && Object.keys(service.asked).length === 0) recovered = service.now })
      harness.check("Yahoo back: its next lone request reopens it, the next run carries everything, and no row or pill warns",
        recovered > 0 && marks().length === 0, (recovered ? recovered - askedAt : "never") + " s | " + marks().join(" | "))

      // No network for two minutes, as on a train: the pause between tries
      // grows to about a minute, and r tries at once instead of waiting it
      // out.
      touch("YAHOO.offline")
      var pausedLong = false, offline = ""
      for (var offFor = 0; offFor < 240 && !(pausedLong && offline !== ""); offFor++) {
        tick(1, 1)
        pausedLong = gate.pause === "none" && !gate.loneOut && gate.pausedUntil - service.now >= 30
        if (/^Can't connect/.test(body.headerText)) offline = body.headerText
      }
      remove("YAHOO.offline")
      var rFrom = harness.requests().length
      var pressedAt = service.now
      app.refresh()
      var tried = within(2000, function() { return harness.yahoo(harness.requests().slice(rFrom)).length > 0 })
      settle()
      harness.check("no network: the header says it can't connect, and once it is back r asks at once and its answer reopens Yahoo",
        pausedLong && /^Can't connect/.test(offline) && tried && service.now === pressedAt && gate.pause === "",
        [pausedLong, offline, tried, service.now - pressedAt, gate.pause].join(" | "))
      closeWindow()

      // Fault 6: scrubbing a delayed/aged stock hides its resting "As of"
      // subtitle on the row while scrubbed, and restores it when scrub ends.
      startAt(at(harness.wed7, 15, 10))()
      openWindow()
      var agedRow = null
      var rowAged = within(3000, function() {
        agedRow = body.watchlist.rowItem("NEST")
        return !!agedRow && !!agedRow.day && /^As of /.test(agedRow.detail)
      })
      var scrubTarget = harness.find(body, "heroChart")
      mouseMove(scrubTarget, scrubTarget.width / 2, scrubTarget.height / 2)
      var scrubbedClean = within(2000, function() {
        return body.scrubT !== 0 && agedRow.scrubX >= 0 && !/^As of /.test(agedRow.detail) && agedRow.detail === agedRow.view.name
      })
      mouseClick(scrubTarget, scrubTarget.width / 2, scrubTarget.height / 2)
      var restoredAged = within(2000, function() {
        return body.scrubT === 0 && agedRow.scrubX < 0 && /^As of /.test(agedRow.detail)
      })
      harness.check("scrubbing an aged stock hides its resting As of subtitle on the row until scrub ends",
        rowAged && scrubbedClean && restoredAged,
        [rowAged, scrubbedClean, restoredAged, agedRow ? agedRow.detail : "no row", agedRow ? agedRow.scrubX : -1].join(" | "))
      closeWindow()

      // Fault 17: at 20:00:00 NY before the first overnight trade, Service.keptDay
      // and BarWidget.lineDay update when tonight and litFrom flip even though
      // axis.start and axis.end stay 04:00-20:00.
      var flipSettings = pill.settings
      pill.settings = ({ id: "grvc.stonks", barStyle: "sparkline" })
      startAt(at(harness.wed7, 19, 55))()
      openWindow()
      var pre20 = within(3000, function() {
        return !!service.view.chart && !!service.view.chart.day && !!pill.lineDay
          && service.view.chart.day.tonight === null && pill.lineDay.tonight === null
      })
      harness.clockTo(at(harness.wed7, 20, 0))
      answerScreens()
      var at20 = within(3000, function() {
        return !!service.view.chart && !!service.view.chart.day && !!pill.lineDay
          && service.view.chart.day.tonight === at(harness.wed7, 20, 0)
          && pill.lineDay.tonight === at(harness.wed7, 20, 0)
          && service.view.chart.day.litFrom === null && pill.lineDay.litFrom === null
      })
      var pillAt20 = pill.lineDay ? pill.lineDay.tonight + "/" + pill.lineDay.litFrom : "no pill"
      pill.settings = flipSettings
      harness.check("at 20:00 NY before any night trade, keptDay and pill.lineDay update when tonight and litFrom flip",
        pre20 && at20,
        [pre20, at20, service.view.chart && service.view.chart.day ? service.view.chart.day.tonight + "/" + service.view.chart.day.litFrom : "no day",
          pillAt20].join(" | "))
      closeWindow()
      settle()

      // Midnight, the window left open on a workspace no screen shows: it
      // asks what a closed one asks, the pill's stock every 15 minutes, not
      // Tokyo though it trades, and Robinhood every 5 minutes through the
      // night. Back in sight, what fell due goes at once.
      hyprlandStandIn.toplevels = { values: [stonksToplevel] }
      hyprlandStandIn.monitors = { values: [screenStandIn] }
      stonksToplevel.workspace = workspaceThere
      var away = countsOver("00:00, the window open on a workspace no screen shows: the pill's stock every 15 minutes, nothing else",
        1800, counts([2, 0, 0, 0, 0, 0, 0, 0]), function() {
          startAt(at(harness.wed7 + 86400, 0, 0))()
          answerScreens()
          app.open("{}")
          tryVerify(function() { return app.opened }, 3000)
          answerScreens()
        })
      var night = away.filter(function(l) { return /^overnight /.test(l) })
      var lastTrades = away.filter(function(l) { return /^lasttrade NEST /.test(l) })
      harness.check("through the night, Robinhood is asked every 5 minutes for the pill's trades, and every minute for its last trade",
        night.length === 6 && lastTrades.length === 30, away.filter(function(l) { return /^(overnight|instruments|lasttrade) /.test(l) }).join(", "))
      var backFrom = harness.requests().length
      stonksToplevel.workspace = workspaceHere
      harness.check("back in sight, what fell due goes at once: the crypto",
        within(3000, function() { return harness.quoteCounts(harness.requests().slice(backFrom))["BTC-USD"] === 1 }),
        harness.requests().slice(backFrom).join(", "))
      screensHeard()
      settle()
      closeWindow()
      hyprlandStandIn.toplevels = { values: [] }
      hyprlandStandIn.monitors = { values: [] }

      // Robinhood gone in the night, nothing open: the pill marks its price
      // with a "!" from the trades' failed ask, says the refresh failed, and
      // drops the "!" once Robinhood answers again.
      touch("ROBINHOOD.offline")
      var markedAt = 0, hover = "", warnInkOk = false
      tick(600, 5, function() {
        if (!markedAt && pill.warns) {
          markedAt = service.now
          hover = pill.warningText
          // The pill's "!" stays in the bar's own ink in every horizontal
          // style, never the move's green or red.
          var wasStyle = pill.settings
          warnInkOk = ["text", "arrow", "sparkline"].every(function(style) {
            pill.settings = ({ id: "grvc.stonks", barStyle: style })
            var warn = harness.find(pill, "pillWarning")
            var move = harness.find(pill, "pillMove")
            return !!warn && warn.visible && warn.text === "! "
              && Qt.colorEqual(warn.color, barApi.foreground)
              && !!move && move.visible && !/^!/.test(move.text)
          })
          pill.settings = wasStyle
        }
      })
      remove("ROBINHOOD.offline")
      // r asks again at once for the pill's last trade, failed while
      // Robinhood was gone, with the clock still.
      var quoteFailed = !!service.feeds.lastTrade.entries.NEST && service.feeds.lastTrade.entries.NEST.status === "failed"
      var rFromNight = harness.requests().length
      service.refresh()
      var reasked = within(3000, function() { return harness.requests().slice(rFromNight).some(function(l) { return /^lasttrade NEST 200$/.test(l) }) })
      settle()
      harness.check("r at night asks again at once for the pill's last trade that failed while Robinhood was gone",
        quoteFailed && reasked && service.feeds.lastTrade.entries.NEST.status === "ok", [quoteFailed, harness.requests().slice(rFromNight).join(", ")].join(" | "))
      var clearedAt = 0
      tick(600, 5, function() { if (markedAt && !clearedAt && !pill.warns) clearedAt = service.now })
      harness.check("Robinhood gone in the night: the pill says its refresh failed with a neutral \"!\", and once Robinhood answers again the \"!\" goes",
        markedAt > 0 && warnInkOk && /^Refresh failed/.test(hover) && clearedAt > 0, [markedAt, warnInkOk, hover, clearedAt].join(" | "))

      // A pointer resting on the pill at night: Robinhood answers a bar
      // still forming, then the same bar at a new price; the pill shows
      // tonight's move as it is now, and its hover says overnight with the
      // bar's time (since it is late) and how the closed day ended.
      startAt(at(harness.wed7 + 86400, 1, 0))()
      var forming = function(price) {
        runCommand(["sh", "-c", "echo 2026-10-08T05:00:00Z " + price + " > \"$STONKS_FAKE_STATE/NIGHT.bar\""])
      }
      var tonight = function(price) {
        return !!pill.newest && pill.newest.joined && pill.newest.p === price
      }
      forming("240.00")
      tick(600, 5, function() {})
      var joinedFirst = tonight(240)
      var pillFirst = pill.featured ? pill.featured.changeText : ""
      mouseMove(pill, pill.width / 2, pill.height / 2)
      var entered = harness.copiedHover
      forming("241.50")
      tick(600, 5, function() {})
      var pillAfter = pill.featured ? pill.featured.changeText : ""
      var after = harness.copiedHover
      mouseMove(pillWindow.contentItem, 1, 100)
      remove("NIGHT.bar")
      harness.check("at night the pill shows tonight's newest move, a new price on the same bar included, and its hover shows the closed day",
        joinedFirst && pillFirst === "+1.99%" && entered === "Overnight as of 01:00 · Wed \u22125.82%"
          && tonight(241.5) && pillAfter === "+2.62%" && after === "Overnight as of 01:00 · Wed \u22125.82%",
        [joinedFirst, pillFirst, entered, pillAfter, after].join(" | "))

      // Robinhood's quote then brings a trade at 01:19:30, newer than that
      // bar: within a minute the pill shows its move, and the hover drops
      // the time since the trade is fresh.
      runCommand(["sh", "-c", "echo 2026-10-08T05:19:30.250Z 242.25 > \"$STONKS_FAKE_STATE/NIGHT.trade\""])
      tick(60, 5, function() {})
      var pillQuoted = pill.featured ? pill.featured.changeText : ""
      mouseMove(pill, pill.width / 2, pill.height / 2)
      var quoted = harness.copiedHover
      mouseMove(pillWindow.contentItem, 1, 100)
      remove("NIGHT.trade")
      harness.check("Robinhood's quote brings a newer trade than its bars, and within a minute the pill shows its move, with no time in its hover while fresh",
        pillQuoted === "+2.94%" && quoted === "Overnight · Wed \u22125.82%" && !!pill.newest && pill.newest.t === at(harness.wed7 + 86400, 1, 19) + 30,
        [pillQuoted, quoted, pill.newest ? pill.newest.p + " " + pill.newest.t : "no newest"].join(" | "))

      // Without a 1 Hz open clock, that overnight trade still wakes the clock
      // on the exact second it turns stale (01:21:31, 2 minutes + 1 s on).
      // While stale, the arrow dims with the move; in "open" mode at night,
      // the pill sparkline stays colored by the day's move against the close.
      var findPillItem = function(rootItem, match) {
        if (!rootItem) return null
        if (match(rootItem)) return rootItem
        var kids = rootItem.children || []
        for (var i = 0; i < kids.length; i++) {
          var hit = findPillItem(kids[i], match)
          if (hit) return hit
        }
        return null
      }
      openWindow()
      var nightHero = harness.find(app.body, "hero")
      harness.clockTo(at(harness.wed7 + 86400, 1, 21) + 29)
      var staleWake = service.clockInterval
      var freshOld = pill.newestOld
      var freshHeroLead = nightHero ? nightHero.listingLead : "missing"
      var freshHover = ""
      var staleHover = ""
      mouseMove(pill, pill.width / 2, pill.height / 2)
      freshHover = harness.copiedHover
      mouseMove(pillWindow.contentItem, 1, 100)
      harness.clockTo(at(harness.wed7 + 86400, 1, 21) + 31)
      var staleOld = pill.newestOld
      var staleHeroLead = nightHero ? nightHero.listingLead : "missing"
      mouseMove(pill, pill.width / 2, pill.height / 2)
      staleHover = harness.copiedHover
      mouseMove(pillWindow.contentItem, 1, 100)
      var wasPillSettings = pill.settings
      pill.settings = ({ id: "grvc.stonks", barStyle: "arrow" })
      var arrowText = findPillItem(pill, function(item) { return item.text === "➜" })
      var arrowDimmed = !!arrowText && Qt.colorEqual(arrowText.color, pill.dimColor)
      pill.settings = ({ id: "grvc.stonks", barStyle: "sparkline" })
      var wasMode = service.changeMode
      service.persist({ changeMode: "open" })
      var sparkItem = null
      within(1500, function() {
        sparkItem = findPillItem(pill, function(item) { return item.geometry !== undefined && (item.lineColor !== undefined || item.upColor !== undefined) })
        return service.changeMode === "open" && !!sparkItem
      })
      var sparkColor = sparkItem ? (sparkItem.lineColor !== undefined ? sparkItem.lineColor : sparkItem.upColor) : "transparent"
      var sparkColoredInOpen = !!sparkItem && !Qt.colorEqual(sparkColor, pill.dimColor)
      service.persist({ changeMode: wasMode })
      within(1500, function() { return service.changeMode === wasMode })
      pill.settings = wasPillSettings
      closeWindow()
      harness.check("without a 1 Hz open clock, an overnight trade's stale turn wakes the clock on its exact second, shows AS OF on the hero, dims the pill arrow, and keeps the pill sparkline colored in open mode",
        staleWake === 2005 && !freshOld && staleOld
          && freshHeroLead === "" && staleHeroLead === "AS OF 01:19"
          && freshHover === "Overnight · Wed \u22125.82%" && staleHover === "Overnight as of 01:19 · Wed \u22125.82%"
          && arrowDimmed && sparkColoredInOpen,
        ["staleWake=" + staleWake, "old=" + freshOld + "->" + staleOld, "hero=" + freshHeroLead + "->" + staleHeroLead,
          "fresh=" + freshHover, "stale=" + staleHover, "arrowDimmed=" + arrowDimmed, "sparkOpen=" + sparkColoredInOpen].join(" | "))

      // Thursday 11:15, nothing open, every screen off: nothing is asked
      // for, the pill's stock and a refresh included. The key press that
      // turns a screen on asks at once for the pill's, with the clock still.
      startAt(at(harness.wed7 + 86400, 11, 15))()
      hyprlandStandIn.monitors = { values: [screenStandIn] }
      screenStandIn.on = false
      // The screens' last answer, trusted for a second, runs out first.
      wait(1100)
      var darkFrom = harness.requests().length
      tick(600)
      service.refresh()
      screensHeard()
      var dark = harness.quoteCounts(harness.requests().slice(darkFrom))
      wait(1100)
      inputStandIn.isIdle = true
      screenStandIn.on = true
      inputStandIn.isIdle = false
      var woke = within(2000, function() { return harness.quoteCounts(harness.requests().slice(darkFrom)).NEST > 0 })
      settle()
      var lit = harness.quoteCounts(harness.requests().slice(darkFrom))
      harness.check("every screen off, nothing is asked for, a refresh included; the key press that turns a screen on asks for the pill's stock at once",
        woke && harness.listed.every(function(s) { return dark[s] === 0 })
          && harness.listed.every(function(s) { return lit[s] === (s === "NEST" ? 1 : 0) }),
        (woke ? "" : "not within 2 s | ") + "off: " + JSON.stringify(dark) + " | on: " + JSON.stringify(lit))

      // Words typed into search with every screen off ask Yahoo nothing,
      // and the key that wakes a screen sends them, once.
      openWindow()
      body.startAdding()
      var field = null
      within(3000, function() { field = harness.find(body, "searchField"); return body.search.active && !!field })
      screenStandIn.on = false
      wait(1100)
      var searchesFrom = harness.calls("SEARCH.asked")
      field.text = "zzz"
      var held = within(3000, function() { return body.search.feed.requestedQuery === "zzz" })
      screensHeard()
      var darkSearches = harness.calls("SEARCH.asked") - searchesFrom
      wait(1100)
      inputStandIn.isIdle = true
      screenStandIn.on = true
      inputStandIn.isIdle = false
      var sent = within(3000, function() { return harness.calls("SEARCH.asked") === searchesFrom + 1 })
      harness.check("every screen off, words typed into search ask nothing, and the key that wakes a screen sends them, once",
        held && darkSearches === 0 && sent, [held, darkSearches, harness.calls("SEARCH.asked") - searchesFrom].join(" "))
      body.cancelAdding()
      closeWindow()

      // No pill in any bar and nothing open: nothing is asked for the stock
      // you last looked at, though its market trades. A pill put back in a
      // bar asks for it at once.
      var unseen = countsOver("Thursday, no pill in any bar and nothing open: nothing is asked for, the stock you last looked at included",
        900, counts([0, 0, 0, 0, 0, 0, 0, 0]), function() {
          pillLoader.active = false
          otherPillLoader.active = false
          startAt(service.now + 5)()
        })
      var pillFrom = harness.requests().length
      pillLoader.active = true
      var asksAgain = within(2000, function() { return harness.quoteCounts(harness.requests().slice(pillFrom)).NEST === 1 })
      settle()
      harness.check("with no pill, Robinhood is asked nothing either, and a pill put back asks for its stock at once",
        unseen.filter(function(l) { return /^(overnight|instruments|lasttrade) /.test(l) }).length === 0 && asksAgain,
        unseen.join(", ") + " | back: " + harness.requests().slice(pillFrom).join(", "))

      // With the bar hidden and nothing open, the pill asks for nothing;
      // showing the bar again asks for its stock at once.
      var hiddenReqs = countsOver("Thursday, bar hidden and nothing open: nothing is asked for",
        300, counts([0, 0, 0, 0, 0, 0, 0, 0]), function() {
          barState.barHidden = true
          startAt(service.now + 5)()
        })
      var unhideFrom = harness.requests().length
      barState.barHidden = false
      var unhidAsks = within(2000, function() { return harness.quoteCounts(harness.requests().slice(unhideFrom)).NEST === 1 })
      settle()
      harness.check("with the bar hidden, Robinhood is asked nothing either, and unhiding asks for the pill's stock at once",
        hiddenReqs.filter(function(l) { return /^(overnight|instruments|lasttrade) /.test(l) }).length === 0 && unhidAsks,
        hiddenReqs.join(", ") + " | unhid: " + harness.requests().slice(unhideFrom).join(", "))

      // The panel open on a screen that's off, the other screen on: its rows
      // are asked as with the panel closed, the pill's stock alone. The key
      // that wakes its screen asks for them at once, with the clock still.
      hyprlandStandIn.monitors = { values: [otherScreen, screenStandIn] }
      hyprlandStandIn.panelScreen = screenStandIn
      pill.open()
      tryVerify(function() { return !!pill.panel && !!pill.panel.body && service.openSurfaces.length === 1 }, 3000)
      settle()
      screenStandIn.on = false
      hyprlandStandIn.refreshMonitors()
      screensHeard()
      countsOver("the panel open on a screen that's off, another on: the pill's stock alone, every minute",
        300, counts([5, 0, 0, 0, 0, 0, 0, 0]), function() {
          startAt(service.now + 5)()
          answerScreens()
        })
      var wakeFrom = harness.requests().length
      inputStandIn.isIdle = true
      screenStandIn.on = true
      inputStandIn.isIdle = false
      var rowsBack = within(2000, function() { return harness.quoteCounts(harness.requests().slice(wakeFrom)).KILN > 0 })
      harness.check("the key that wakes the panel's screen asks for its rows at once", rowsBack,
        harness.requests().slice(wakeFrom).join(", "))
      settle()
      pill.close()
      tryVerify(function() { return service.openSurfaces.length === 0 }, 3000)
      hyprlandStandIn.panelScreen = null
      hyprlandStandIn.monitors = { values: [] }

      // A click that stops a run ahead shows its chart from the answers the
      // run already has: KILN's is in, SPY's still on its way.
      openWindow()
      var kilnFrom = harness.calls("KILN.history")
      var spyFrom = harness.calls("SPY.history")
      var aheadFrom = harness.requests().length
      touch("history.SPY.hold")
      body.selectRange("1Y")
      var kilnIn = within(10000, function() {
        return harness.calls("SPY.history") > spyFrom && harness.requests().slice(aheadFrom).indexOf("history KILN 200") >= 0
      })
      body.featureSymbol("KILN")
      var kilnShown = within(3000, function() { return body.historyShown && body.chartSymbol === "KILN" && body.chartRange === "1Y" })
      remove("history.SPY.hold")
      settle()
      harness.check("a click on a chart a run ahead already holds shows it without downloading it again",
        kilnIn && kilnShown && harness.calls("KILN.history") === kilnFrom + 1,
        [kilnIn, kilnShown, harness.calls("KILN.history") - kilnFrom].join(" "))
      body.selectRange("1D")

      // The window closed while a stock's cap waits on a screen check: once
      // the screens answer, nothing more is asked for it, its close or its
      // rate. Open again, the cap and P/E come whole.
      hyprlandStandIn.monitors = { values: [screenStandIn] }
      touch("fundamentals.SHEL.L.hold")
      var shelFrom = harness.calls("SHEL.L.fundamentals")
      body.featureSymbol("SHEL.L")
      var shelOut = within(5000, function() { return harness.calls("SHEL.L.fundamentals") === shelFrom + 1 })
      screensHeard()
      screenStandIn.holding = true
      // The screens' last answer, trusted for a second, runs out first.
      within(2000, function() { return Date.now() - service.screensAnsweredMs >= 1000 })
      var waitingFrom = harness.requests().length
      remove("fundamentals.SHEL.L.hold")
      var shelIn = within(3000, function() { return harness.requests().slice(waitingFrom).indexOf("fundamentals SHEL.L 200") >= 0 })
      var checking = within(1000, function() { return screenStandIn.unanswered > 0 })
      var shelFundamentalsAt = harness.calls("FUNDAMENTALS")
      var shelRatesAt = harness.calls("RATE")
      closeWindow()
      screenStandIn.holding = false
      screensHeard()
      // Time for a request that must not go.
      var shelQuiet = !within(1000, function() {
        return harness.calls("FUNDAMENTALS") !== shelFundamentalsAt || harness.calls("RATE") !== shelRatesAt
      })
      openWindow()
      var shelWhole = within(5000, function() {
        var facts = body.yearLine ? body.yearLine.facts : []
        return facts.length === 2 && facts.every(function(f) { return f.value !== "" })
      })
      harness.check("the window closed while a cap's close waits on the screens asks nothing more for it once they answer, and open again shows the cap and P/E",
        shelOut && shelIn && checking && shelQuiet && shelWhole,
        [shelOut, shelIn, checking, shelQuiet, shelWhole].join(" ") + " | " + harness.requests().slice(waitingFrom).join(", "))
      hyprlandStandIn.monitors = { values: [] }

      // The window closed while a stock's cap is on its way: nothing more is
      // asked for it, its close or its rate. Open again, the cap and P/E
      // come whole.
      touch("fundamentals.SHOP.TO.hold")
      var seriesFrom = harness.calls("SHOP.TO.fundamentals")
      body.featureSymbol("SHOP.TO")
      var seriesOut = within(5000, function() { return harness.calls("SHOP.TO.fundamentals") === seriesFrom + 1 })
      closeWindow()
      var capFrom = harness.requests().length
      var fundamentalsAt = harness.calls("FUNDAMENTALS")
      var ratesAt = harness.calls("RATE")
      remove("fundamentals.SHOP.TO.hold")
      var seriesIn = within(3000, function() { return harness.requests().slice(capFrom).indexOf("fundamentals SHOP.TO 200") >= 0 })
      // Time for a request that must not go.
      var quiet = !within(1000, function() {
        return harness.calls("FUNDAMENTALS") !== fundamentalsAt || harness.calls("RATE") !== ratesAt
      })
      openWindow()
      var whole = within(5000, function() {
        var facts = body.yearLine ? body.yearLine.facts : []
        return facts.length === 2 && facts.every(function(f) { return f.value !== "" })
      })
      var batchedCloseRate = harness.record("runs.log").split("\n").some(function(line) {
        return line.indexOf("fundamentals:SHOP.TO") >= 0 && line.indexOf("rate:USDCAD") >= 0
      })
      harness.check("the window closed while a cap is on its way asks nothing more for it, and open again shows the cap and P/E in one batched close+rate run",
        seriesOut && seriesIn && quiet && whole && batchedCloseRate,
        [seriesOut, seriesIn, quiet, whole, batchedCloseRate].join(" ") + " | " + harness.requests().slice(capFrom).join(", "))
      closeWindow()

      // The bell, sounds on, Do Not Disturb and the microphone answering a
      // second after it is due: at Thursday's close, a screen on as it is
      // due and every screen off before they answer, it keeps quiet; at
      // Friday's open, a screen on, it rings.
      var bells = function() {
        return harness.record("played").split("\n").filter(function(line) { return /bell\.wav$/.test(line) }).length
      }
      service.persist({ sounds: true })
      verify(within(3000, function() { return service.soundsOn }), "sounds never turned on")
      runCommand(["sh", "-c", "echo 1 > \"$0/pw-dump.delay\"", harness.state])
      hyprlandStandIn.monitors = { values: [screenStandIn] }
      startAt(at(harness.wed7 + 86400, 15, 59) + 55)()
      var closeFrom = bells()
      harness.clockTo(at(harness.wed7 + 86400, 16, 0) + 5)
      screenStandIn.on = false
      hyprlandStandIn.refreshMonitors()
      screensHeard()
      var dark = within(1000, function() { return service.screensOff })
      // Time for the bell, past Do Not Disturb's and the microphone's answer.
      within(2500, function() { return bells() > closeFrom })
      var atClose = bells() - closeFrom
      screenStandIn.on = true
      hyprlandStandIn.refreshMonitors()
      screensHeard()
      startAt(at(harness.wed7 + 2 * 86400, 9, 29) + 55)()
      var openFrom = bells()
      harness.clockTo(at(harness.wed7 + 2 * 86400, 9, 30) + 5)
      var rang = within(4000, function() { return bells() > openFrom })
      harness.check("the bell keeps quiet once every screen goes off before Do Not Disturb and the microphone answer, and rings with a screen on",
        dark && atClose === 0 && rang, "screens off " + dark + ", bells at the close " + atClose + ", at the open " + (bells() - openFrom))

      // Sunday night, Robinhood gone as the day's check of the day each
      // stock listed falls due, so it and the night's asks fail together:
      // once it answers again, the "!" goes at the next try, not five
      // minutes after it. The check answers in 2 s, as on a loaded machine,
      // and the clock waits.
      service.feature("NEST")
      touch("ROBINHOOD.offline")
      runCommand(["sh", "-c", "echo 2 > \"$0/instruments.instruments.slow\"", harness.state])
      startAt(at(harness.wed7 + 4 * 86400, 21, 0))()
      var goneMarked = false
      tick(600, 5, function() { goneMarked = goneMarked || pill.warns })
      remove("ROBINHOOD.offline")
      var backAt = service.now, backClearedAt = 0
      tick(900, 5, function() { if (!backClearedAt && !pill.warns) backClearedAt = service.now })
      harness.check("Robinhood gone as its daily check falls due: once it answers again, the \"!\" goes at the next try",
        goneMarked && backClearedAt > 0 && backClearedAt - backAt <= 5 * 60 + 60,
        [goneMarked, backClearedAt - backAt].join(" | "))

      // Without a 1 Hz open clock, stepping only to each scheduled Robinhood
      // deadline re-asks both last-trade quotes (1 min) and overnight bars
      // (5 min) for all visible overnight rows at their exact second.
      startAt(at(harness.wed7 + 4 * 86400, 22, 0) + 17)()
      answerScreens()
      openWindow()
      answerScreens()
      var noOneHz = service.clockInterval === 0 || service.clockInterval > 1000
      var ltDue = service.lastTradeDueAt
      var ovDue = service.overnightDueAt
      var ltFrom = harness.requests().length
      harness.clockTo(ltDue)
      answerScreens()
      settle()
      var ltAsked = harness.requests().slice(ltFrom).some(function(l) { return /^lasttrade /.test(l) })
      var ovFrom = harness.requests().length
      harness.clockTo(ovDue)
      answerScreens()
      settle()
      var ovAsked = harness.requests().slice(ovFrom).some(function(l) {
        return /^overnight /.test(l) && l.indexOf("NEST") >= 0 && l.indexOf("KILN") >= 0 && l.indexOf("SPY") >= 0
      })
      harness.check("without a 1 Hz open clock, overnight and last-trade deadlines re-ask all visible overnight rows on their exact second",
        noOneHz && ltDue === at(harness.wed7 + 4 * 86400, 22, 1) + 17 && ovDue === at(harness.wed7 + 4 * 86400, 22, 5) + 17
          && ltAsked && ovAsked,
        ["interval=" + service.clockInterval, "ltDue=" + ltDue, "ovDue=" + ovDue, "ltAsked=" + ltAsked, "ovAsked=" + ovAsked,
          "ov=" + harness.requests().slice(ovFrom).join(", ")].join(" | "))
      closeWindow()

      // GitHub asked as the network comes back: Yahoo answering again while
      // that ask is out, which then gets no answer either, has GitHub asked
      // again at once, not a day later.
      var manifests = function() { return requests().filter(function(line) { return line.indexOf("manifest manifest ") === 0 }).length }
      var manifestsBefore = manifests()
      touch("GITHUB.offline")
      release.ready = true
      var githubOut = within(3000, function() { return release.askedAt > 0 })
      release.askAgain()
      var askedAgain = within(5000, function() { return manifests() === manifestsBefore + 2 })
      remove("GITHUB.offline")
      harness.check("Yahoo answering again while GitHub's ask is out, which gets no answer, has GitHub asked again at once",
        githubOut && askedAgain, [githubOut, manifests() - manifestsBefore, JSON.stringify(requests().slice(-2))].join(" | "))

      // A holiday asks as a closed day does: an over-the-counter stock,
      // TCEHY, added on Thanksgiving, when OTC Markets is closed, in the
      // window through the hour from 12:15, and through the same hour on the
      // Saturday after, each time answered from Yahoo's answer saved at
      // 12:10 on Thanksgiving.
      var otcAsks = function(from) {
        return harness.yahoo(harness.requests().slice(from)).filter(function(line) {
          var parts = line.split(" ")
          return (parts[0] === "chart" || parts[0] === "spark") && parts[1].split(",").indexOf("TCEHY") >= 0
        }).length
      }
      var hourFrom = function(t) {
        startAt(t)()
        var from = harness.requests().length
        tick(3600, 15)
        return otcAsks(from)
      }
      startAt(at(harness.thu26, 12, 10))()
      service.addSymbol("TCEHY")
      openWindow()
      var added = within(3000, function() { return !!service.quotes["TCEHY"] })
      var holiday = hourFrom(at(harness.thu26, 12, 15))
      // Expire the 1 s screen trust so startAt exercises the async screen check.
      within(2000, function() { return Date.now() - service.screensAnsweredMs >= 1000 })
      var saturday = hourFrom(at(harness.sat28, 12, 15))
      harness.check("a holiday asks as a closed day does: an over-the-counter stock through Thanksgiving's hour from 12:15 as through the Saturday's",
        added && holiday === saturday, [added, "Thanksgiving " + holiday, "Saturday " + saturday].join(" | "))
      closeWindow()

      // A closed market keeps its history fresh past 15 minutes once answered
      // after its regular close: Saturday 12:15 -> 12:35 revisiting 2Y sends
      // no new download.
      startAt(at(harness.sat28, 12, 15))()
      openWindow()
      service.feature("NEST")
      var satBefore = harness.calls("NEST.history")
      body.selectRange("2Y")
      var satFirst = within(5000, function() { return harness.calls("NEST.history") === satBefore + 1 && body.historyShown && body.chartRange === "2Y" })
      var satAskedBefore = harness.calls("NEST.history")
      body.selectRange("1D")
      tick(1200, 60)
      body.selectRange("2Y")
      var satShown = within(2000, function() { return body.historyShown && body.chartRange === "2Y" })
      // Time for a download that must not go.
      var satReasked = within(500, function() { return harness.calls("NEST.history") !== satAskedBefore })
      harness.check("on a closed market, revisiting a range past 15 minutes reuses its history without re-downloading",
        satFirst && satShown && !satReasked, [satFirst, satShown, "reasked=" + satReasked].join(" "))
      body.selectRange("1D")
      closeWindow()

      // Non-streaming history ahead batch stops immediately on Yahoo 429 rather
      // than hammering the remaining URLs in the batch.
      startAt(at(harness.wed7, 14, 0))()
      openWindow()
      var ref429From = harness.requests().length
      touch("YAHOO.refuse")
      body.selectRange("5Y")
      var ref429Hit = within(5000, function() {
        return harness.requests().slice(ref429From).some(function(l) { return / 429$/.test(l) })
      })
      // Time for any second 429 that must not go.
      within(600, function() {
        return harness.requests().slice(ref429From).filter(function(l) { return / 429$/.test(l) }).length > 1
      })
      var ref429Count = harness.requests().slice(ref429From).filter(function(l) { return / 429$/.test(l) }).length
      remove("YAHOO.refuse")
      harness.check("a non-streaming multi-URL fetch stops on the first 429 instead of hammering remaining URLs",
        ref429Hit && ref429Count === 1, ["hit=" + ref429Hit, "429s=" + ref429Count].join(" "))
      body.selectRange("1D")
      closeWindow()

      // Switching changeMode to "open" judges open spark rows that deferred
      // dayOpen while in pct mode, filling in their open prices.
      startAt(at(harness.wed7, 14, 30))()
      openWindow()
      service.persist({ changeMode: "open" })
      var openFilled = within(10000, function() {
        var qs = service.quotes
        return ["NEST", "KILN", "SPY"].every(function(s) { return !!qs[s] && qs[s].dayOpen !== null })
      })
      service.persist({ changeMode: "pct" })
      harness.check("switching changeMode to open judges deferred spark rows and fills in dayOpen",
        openFilled, ["openFilled=" + openFilled].join(" "))
      closeWindow()

      // Fault 1: a single Robinhood blip (502 or 1st offline timeout) never
      // stamps "! Refresh failed"; after a real outage, recovery clears every
      // visible row right away (not 5 minutes later), and r retries non-featured
      // failed visible rows too; a 19:58 failure never bleeds into 20:00.
      var rhGate = service.feeds.lastTrade.gate
      var sun29 = harness.sat28 + 86400
      var mon30 = sun29 + 86400
      rhGate.gate = Object.assign({}, rhGate.gate, { left: rhGate.capacity, filledAt: at(sun29, 20, 30), pause: "", pausedUntil: 0, silences: 0, refusals: 0, loneOut: false, warned: false })
      rhGate.budgetDueAt = 0
      gate.gate = Object.assign({}, gate.gate, { left: gate.capacity, filledAt: at(sun29, 20, 30), pause: "", pausedUntil: 0, silences: 0, refusals: 0, loneOut: false, warned: false })
      gate.budgetDueAt = 0
      startAt(at(sun29, 20, 30))()
      openWindow()
      // 1a: single 502 blip on lastTrade retries once and never warns.
      touch("ROBINHOOD.bad")
      var blipWarned = false
      var blipFrom = harness.requests().length
      harness.clockTo(service.lastTradeDueAt)
      within(3000, function() {
        if (pill.warns || Object.keys(service.nightFailed).length > 0) blipWarned = true
        return harness.requests().slice(blipFrom).some(function(l) { return /^lasttrade .* 502$/.test(l) })
      })
      remove("ROBINHOOD.bad")
      settle()
      if (pill.warns || Object.keys(service.nightFailed).length > 0) blipWarned = true
      // 1b: real outage marks visible US rows failed, and recovery clears
      // NEST, KILN and SPY right after the pause expires (not stuck for 5 min).
      touch("ROBINHOOD.offline")
      harness.clockTo(service.overnightDueAt)
      answerScreens()
      settle()
      if (rhGate.pausedUntil > service.now) {
        harness.clockTo(rhGate.pausedUntil)
        answerScreens()
        settle()
      }
      var failedDuringOutage = !!service.nightFailed["NEST"] && !!service.nightFailed["KILN"] && !!service.nightFailed["SPY"]
      remove("ROBINHOOD.offline")
      var recoverStart = service.now
      var allClearedAt = 0
      tick(60, 5, function() {
        if (!allClearedAt && !service.nightFailed["NEST"] && !service.nightFailed["KILN"] && !service.nightFailed["SPY"])
          allClearedAt = service.now
      })
      var recoveredQuickly = allClearedAt > 0 && allClearedAt - recoverStart <= 30
      // 1c: r retries non-featured failed visible rows (KILN, SPY) even inside 10 s.
      touch("ROBINHOOD.bad")
      harness.clockTo(service.overnightDueAt)
      answerScreens()
      settle()
      var kilnFailed = !!service.nightFailed["KILN"] && !!service.nightFailed["SPY"]
      remove("ROBINHOOD.bad")
      var rNightFrom = harness.requests().length
      service.refresh()
      var rClearedNonFeatured = within(5000, function() {
        return !service.nightFailed["KILN"] && !service.nightFailed["SPY"]
          && harness.requests().slice(rNightFrom).some(function(l) { return /^overnight .*KILN.* 200$/.test(l) })
      })
      settle()
      // 1d: failure at 19:58 NY does not bleed into 20:00 NY.
      startAt(at(mon30, 19, 58))()
      touch("ROBINHOOD.bad")
      service.feeds.overnight.entries = ({})
      harness.clockTo(at(mon30, 19, 58) + 1)
      answerScreens()
      settle()
      var preNightFailed = !!service.feeds.overnight.entries["NEST"] && service.feeds.overnight.entries["NEST"].status === "failed"
      remove("ROBINHOOD.bad")
      harness.clockTo(at(mon30, 20, 0))
      var bledAtOpen = Object.keys(service.nightFailed).length > 0
      answerScreens()
      settle()
      var cleanAtOpen = !bledAtOpen && Object.keys(service.nightFailed).length === 0
      harness.check("Robinhood: a single blip never warns, recovery clears visible rows quickly, r retries non-featured failed rows, and pre-night failures don't bleed into 20:00",
        !blipWarned && failedDuringOutage && recoveredQuickly && kilnFailed && rClearedNonFeatured && preNightFailed && cleanAtOpen,
        [blipWarned, failedDuringOutage, recoveredQuickly, allClearedAt - recoverStart, kilnFailed, rClearedNonFeatured, preNightFailed, bledAtOpen, Object.keys(service.nightFailed).join(",")].join(" | "))
      closeWindow()

      // Fault 12: budget-paced HistoryFeed waits for refill instead of showing
      // sticky "<RANGE> UNAVAILABLE".
      var tue1 = mon30 + 86400
      startAt(at(tue1, 14, 30))()
      openWindow()
      service.feature("NEST")
      within(2000, function() { return service.featuredSymbol === "NEST" })
      body.selectRange("1D")
      within(2000, function() { return !body.historyActive })
      gate.gate = Object.assign({}, gate.gate, { left: 0, filledAt: service.now, pause: "", pausedUntil: 0, warned: true })
      gate.budgetDueAt = 0
      body.selectRange("10Y")
      var budgetSet = within(2000, function() { return gate.budgetDueAt > service.now })
      var noStickyFail = budgetSet && !body.historyFailed
      var refillAt = gate.budgetDueAt
      harness.clockTo(refillAt)
      answerScreens()
      var refilledHistory = within(5000, function() { return body.historyShown && body.chartRange === "10Y" && !body.historyFailed })
      body.selectRange("1D")
      gate.gate = Object.assign({}, gate.gate, { left: gate.capacity, filledAt: service.now, warned: false })
      gate.budgetDueAt = 0
      harness.check("a budget-paced range history waits for budget refill instead of failing with sticky unavailable",
        budgetSet && noStickyFail && refilledHistory,
        [budgetSet, noStickyFail, refilledHistory, body.historyFailed, body.historyShown].join(" | "))
      closeWindow()

      // Fault 14: search preview stalled while Yahoo is paused on a quiet
      // weekend turns overdue and surfaces the header pause warning.
      var sat5 = tue1 + 4 * 86400
      startAt(at(sat5, 12, 15))()
      openWindow()
      touch("YAHOO.refuse")
      gate.gate = Object.assign({}, gate.gate, { pause: "refused", pausedUntil: service.now + 300, refusals: 1, loneOut: false })
      body.startAdding()
      body.previewTo("AAPL")
      var previewOwed = within(2000, function() { return (service.owed["AAPL"] || 0) > 0 })
      harness.clockTo(service.now + 95)
      answerScreens()
      var previewHeaderWarn = within(2000, function() { return /busy/i.test(body.headerText) })
      var previewOverdue = (service.owed["AAPL"] || 0) > 0 && service.now - service.owed["AAPL"] >= 90
      body.cancelAdding()
      remove("YAHOO.refuse")
      gate.gate = Object.assign({}, gate.gate, { left: gate.capacity, filledAt: service.now, pause: "", pausedUntil: 0, refusals: 0, silences: 0, loneOut: false })
      harness.check("a stalled search preview while Yahoo is paused turns overdue and shows the header pause warning",
        previewOwed && previewOverdue && previewHeaderWarn,
        [previewOwed, previewOverdue, previewHeaderWarn, body.headerText, body.featuredFreshness.state].join(" | "))
      closeWindow()

      // Fault 13: a 1-symbol watchlist with a 404 symbol shows "! No data for
      // this symbol" instead of false global "Can't get prices", and a mixed
      // list with a delisted 404 symbol still quiets per-row warnings when
      // Yahoo actually goes offline.
      var savedSettings = service.fileSettings
      service.save(Object.assign({}, savedSettings, { symbols: ["ZZZZBADSYM"], lists: [], list: "", featured: "ZZZZBADSYM" }))
      openWindow()
      var badLanded = within(5000, function() {
        var e = service.entries["ZZZZBADSYM"]
        var r = body.watchlist.rowItem("ZZZZBADSYM")
        return body.lists.length > 0 && body.lists[0].symbols.join(",") === "ZZZZBADSYM"
          && service.featuredSymbol === "ZZZZBADSYM" && !!e && e.status === "failed"
          && !!r && r.detail !== "Loading…"
      })
      var badHero = harness.find(body, "hero")
      var badRow = body.watchlist.rowItem("ZZZZBADSYM")
      var badNotDown = badLanded && !body.yahooDown && !/Can't get prices/.test(body.headerText)
      var badSaysSymbol = !!badHero && /NO DATA FOR THIS SYMBOL/.test(badHero.listingLead)
        && !!badRow && /No data for this symbol/.test(badRow.detail)
      // Fault 19d: in icon mode with no price and a warning, the pill hover
      // never repeats "! No data · No data" or "! Can't get prices · No data".
      var savedPillSettings = pill.settings
      pill.settings = Object.assign({}, savedPillSettings, { barStyle: "icon" })
      var badButton = null
      for (var pi = 0; pi < pill.children.length; pi++) {
        if (typeof pill.children[pi].tooltipText === "string") badButton = pill.children[pi]
      }
      var iconFailTip = badButton ? badButton.tooltipText : ""
      var iconFailClean = iconFailTip === "ZZZZBADSYM ! · No data for this symbol"
      pill.settings = savedPillSettings
      // Now a mixed list (NEST + KILN + delisted ZZZZBADSYM) going offline
      // during regular hours: yahooDown still turns on so rows stay quiet.
      var mon7 = sat5 + 2 * 86400
      service.save(Object.assign({}, savedSettings, { symbols: ["NEST", "KILN", "ZZZZBADSYM"], lists: [], list: "", featured: "NEST" }))
      startAt(at(mon7, 11, 0))()
      var mixedReady = within(5000, function() {
        return !!service.quotes["NEST"] && !!service.quotes["KILN"]
          && !!service.entries["ZZZZBADSYM"] && service.entries["ZZZZBADSYM"].status === "failed"
      })
      touch("YAHOO.offline")
      tick(160, 10)
      var nestRow = body.watchlist.rowItem("NEST")
      var kilnRow = body.watchlist.rowItem("KILN")
      var mixedDown = mixedReady && body.yahooDown && /^Can't connect/.test(body.headerText)
        && !!nestRow && !/^!/.test(nestRow.detail) && !!kilnRow && !/^!/.test(kilnRow.detail)
      remove("YAHOO.offline")
      gate.gate = Object.assign({}, gate.gate, { left: gate.capacity, filledAt: service.now, pause: "", pausedUntil: 0, refusals: 0, silences: 0, loneOut: false })
      service.save(savedSettings)
      within(5000, function() { return service.allSymbols.indexOf("SPY") >= 0 })
      harness.check("a 1-symbol 404 list says No data for this symbol, icon pill hover never repeats No data, and a mixed list with a 404 symbol still quiets rows when Yahoo goes offline",
        badLanded && badNotDown && badSaysSymbol && iconFailClean && mixedDown,
        [badLanded, body.yahooDown, badHero ? badHero.listingLead : "no hero", badRow ? badRow.detail : "no row",
          "iconTip:" + iconFailTip, mixedReady, mixedDown, body.headerText, nestRow ? nestRow.detail : "no nest"].join(" | "))
      closeWindow()

      harness.finish()
    }
  }
}
