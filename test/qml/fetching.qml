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
    id: shellApi
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
    when: service.ready && pillWindow.visible

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
      return [service.feeds.quotes, service.feeds.preview].every(function(feed) {
        return feed.firstRun.length === 0 && feed.refreshRun.length === 0
      }) && !service.feeds.overnight.busy && !service.opening
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
        harness.clockTo(harness.time + step)
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

    // The clock to `t`, everything due there asked: a window's start.
    function startAt(t) {
      return function() {
        harness.clockTo(t)
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
      hyprlandStandIn.monitors = { values: [] }

      // Robinhood gone in the night, nothing open: the pill marks its price
      // with a "!" from the trades' failed ask, says the refresh failed, and
      // drops the "!" once Robinhood answers again.
      touch("ROBINHOOD.offline")
      var markedAt = 0, hover = ""
      tick(600, 5, function() {
        if (!markedAt && pill.warns) {
          markedAt = service.now
          hover = pill.warningText
        }
      })
      remove("ROBINHOOD.offline")
      var clearedAt = 0
      tick(600, 5, function() { if (markedAt && !clearedAt && !pill.warns) clearedAt = service.now })
      harness.check("Robinhood gone in the night: the pill says its refresh failed, and once Robinhood answers again the \"!\" goes",
        markedAt > 0 && /^Refresh failed/.test(hover) && clearedAt > 0, [markedAt, hover, clearedAt].join(" | "))

      // A pointer resting on the pill at night: Robinhood answers a bar
      // still forming, then the same bar at a new price, and the hover
      // shows tonight's price as it is now.
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
      mouseMove(pill, pill.width / 2, pill.height / 2)
      var entered = harness.copiedHover
      forming("241.50")
      tick(600, 5, function() {})
      var after = harness.copiedHover
      mouseMove(pillWindow.contentItem, 1, 100)
      remove("NIGHT.bar")
      harness.check("a pointer resting on the pill at night sees tonight's newest price in its hover, a new price on the same bar included",
        joinedFirst && / 240\.00 /.test(entered) && tonight(241.5) && / 241\.50 /.test(after),
        [joinedFirst, entered, pill.newest ? pill.newest.p + " " + pill.newest.joined : "no newest", after].join(" | "))

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
        unseen.filter(function(l) { return /^(overnight|instruments) /.test(l) }).length === 0 && asksAgain,
        unseen.join(", ") + " | back: " + harness.requests().slice(pillFrom).join(", "))

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
        }, answerScreens)
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
      harness.check("the window closed while a cap is on its way asks nothing more for it, and open again shows the cap and P/E",
        seriesOut && seriesIn && quiet && whole,
        [seriesOut, seriesIn, quiet, whole].join(" ") + " | " + harness.requests().slice(capFrom).join(", "))
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

      harness.finish()
    }
  }
}
