import QtQuick
import Quickshell
import Quickshell.Io
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
  // Midnight starting Wednesday 7 October and Saturday 10 October in New York.
  readonly property int wed7: 1791345600
  readonly property int sat10: 1791604800

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
    return lines.filter(function(line) { return !/^(overnight|instruments) /.test(line) })
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
  Stonks.Plugin { id: plugin; shell: shellApi; manifest: harness.pluginManifest() }
  readonly property var service: plugin.service
  readonly property var app: plugin.windowHost.app

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
  QtObject {
    id: hyprlandStandIn
    property var toplevels: ({ values: [] })
    property var focusedWorkspace: workspaceHere
    function dispatch(request) {}
    // Hyprland's events, which ask the screens again while every one is
    // off. None come: only a step asks them.
    signal rawEvent(var event)
  }
  Binding { target: plugin.windowHost; property: "hyprlandStandIn"; value: hyprlandStandIn }
  Binding { target: plugin.service.screens; property: "hyprlandStandIn"; value: hyprlandStandIn }

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

  // A screen as Hyprland reports it, for the window host (fetch.sh): on or
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
    when: service.pluginsReady && pillWindow.visible

    function runCommand(command) {
      fileProc.command = command
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }
    function touch(name) { runCommand(["touch", harness.state + "/" + name]) }
    function remove(name) { runCommand(["rm", "-f", harness.state + "/" + name]) }

    // No quote run is out, the preview's included: the clock moves on only
    // once each run has landed, as it would in the seconds a run takes.
    function idle() {
      return [service.testFeed, service.testPreviewFeed].every(function(feed) {
        return feed.firstRun.length === 0 && feed.refreshRun.length === 0
      }) && !service.testOvernightFeed.busy && !service.opening
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

    // The clock moves on by `seconds`, a step at a time, each run let land.
    // `each` is called after every step.
    function tick(seconds, step, each) {
      step = step || 5
      for (var t = 0; t < seconds; t += step) {
        service.now += step
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
        var body = app.testBody
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
      var before = Object.keys(service.asked).concat(service.testFeed.landing.length > 0 ? ["a run out"] : [])
      var from = harness.requests().length
      begin()
      tick(seconds - 5, 5, each)
      var got = harness.quoteCounts(harness.requests().slice(from))
      var off = harness.listed.filter(function(s) { return want[s] === 0 ? got[s] !== 0 : Math.abs(got[s] - want[s]) > 1 })
      harness.check(label, before.length === 0 && off.length === 0,
        (before.length ? "asked before it: " + before.join(",") + " | " : "") + harness.listed.map(function(s) { return s + " " + got[s] + "/" + want[s] }).join(", "))
      return harness.requests().slice(from)
    }

    // The clock to `t`, everything due there asked: a window's start.
    function startAt(t) {
      return function() {
        service.now = t
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
      app.testWindow.implicitHeight = 1000
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)
      settle()
    }
    function closeWindow() {
      app.close()
      tryVerify(function() { return service.openSurfaces.length === 0 }, 3000)
    }

    function test_fetching() {
      var gate = service.testYahooGate
      startAt(at(harness.wed7, 10, 45))()
      tick(60)

      // By day: no row is kept fresh for a surface no screen shows.
      countsOver("11:00, nothing open: the pill's stock alone, every minute, though every market but Tokyo trades",
        900, counts([15, 0, 0, 0, 0, 0, 0, 0]), startAt(at(harness.wed7, 11, 0)))
      // London closes at 16:30, 11:30 here, half a minute before this
      // window ends: its last minute's request does not go.
      countsOver("11:15, the window open: every listing trading every minute, London until its close; Tokyo, closed, once in the quarter hour",
        900, counts([15, 15, 15, 15, 15, 14, 1, 15]), openAfter)
      var body = app.testBody

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

      // Yahoo refuses: the run that meets it is the last for a pause of
      // about a minute, then one request goes alone. Back, the next lone
      // request reopens it.
      touch("YAHOO.refuse")
      var askedAt = 0
      tick(70, 1, function() { if (!askedAt && gate.pause === "refused") askedAt = service.now })
      // The header names the trouble once a price is 90 s overdue.
      var said = ""
      var refusedFrom = harness.requests().length
      var lone = []
      tick(78, 1, function() {
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
        pausedLong = gate.pause === "none" && !gate.probing && gate.pausedUntil - service.now >= 30
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

      // Midnight, the window left open on a workspace no screen shows: it
      // asks what a closed one asks, the pill's stock every 15 minutes, not
      // Tokyo though it trades, and Robinhood every 5 minutes through the
      // night. Back in sight, what fell due goes at once.
      hyprlandStandIn.toplevels = { values: [stonksToplevel] }
      plugin.service.screens.monitors = [screenStandIn]
      stonksToplevel.workspace = workspaceThere
      var away = countsOver("00:00, the window open on a workspace no screen shows: the pill's stock every 15 minutes, nothing else",
        1800, counts([2, 0, 0, 0, 0, 0, 0, 0]), function() {
          startAt(at(harness.wed7 + 86400, 0, 0))()
          answerScreens()
          app.open("{}")
          tryVerify(function() { return app.opened }, 3000)
          answerScreens()
        }, answerScreens)
      var night = away.filter(function(l) { return /^overnight /.test(l) })
      harness.check("through the night, Robinhood is asked every 5 minutes for the pill's newest trade", night.length === 6,
        away.filter(function(l) { return /^(overnight|instruments) /.test(l) }).join(", "))
      var backFrom = harness.requests().length
      stonksToplevel.workspace = workspaceHere
      harness.check("back in sight, what fell due goes at once: the crypto",
        within(3000, function() { return harness.quoteCounts(harness.requests().slice(backFrom))["BTC-USD"] === 1 }),
        harness.requests().slice(backFrom).join(", "))
      screensHeard()
      settle()
      closeWindow()
      hyprlandStandIn.toplevels = { values: [] }
      plugin.service.screens.monitors = []

      // Thursday 11:15, nothing open, every screen off: nothing is asked
      // for, the pill's stock and a refresh included. The key press that
      // turns a screen on asks at once for the pill's, with the clock still.
      startAt(at(harness.wed7 + 86400, 11, 15))()
      plugin.service.screens.monitors = [screenStandIn]
      screenStandIn.on = false
      // The screens' last answer, trusted for a second, runs out first.
      wait(1100)
      var darkFrom = harness.requests().length
      tick(600)
      service.refresh()
      screensHeard()
      var dark = harness.quoteCounts(harness.requests().slice(darkFrom))
      wait(1100)
      plugin.service.screens.testInput.isIdle = true
      screenStandIn.on = true
      plugin.service.screens.testInput.isIdle = false
      var woke = within(2000, function() { return harness.quoteCounts(harness.requests().slice(darkFrom)).NEST > 0 })
      settle()
      var lit = harness.quoteCounts(harness.requests().slice(darkFrom))
      harness.check("every screen off, nothing is asked for, a refresh included; the key press that turns a screen on asks for the pill's stock at once",
        woke && harness.listed.every(function(s) { return dark[s] === 0 })
          && harness.listed.every(function(s) { return lit[s] === (s === "NEST" ? 1 : 0) }),
        (woke ? "" : "not within 2 s | ") + "off: " + JSON.stringify(dark) + " | on: " + JSON.stringify(lit))

      harness.finish()
    }
  }
}
