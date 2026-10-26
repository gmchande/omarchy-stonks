import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugin" as Stonks

// The fetch policy through the real Plugin, Service, App, and two pills, on
// a clock this harness sets, moving forward through Wednesday 7 October
// 2026 and Saturday the 10th, New York time. The fake curl answers every
// listing from its saved day of 7 October (test/fixtures/moments/
// fetch-2026-10-07, then listings-2026-10-07-1455): a busy US stock (NEST, featured), a thin one (KILN),
// an ETF (SPY), an index (^GSPC), a cryptocurrency (BTC-USD), London
// (SHEL.L), Tokyo (7203.T), and Toronto (SHOP.TO). It counts every request
// in requests.log and every curl call in runs.log. fetch.sh runs this three
// times: the main run, which starts offline with saved quotes; the holiday
// run (STONKS_FETCH_RUN=holiday), whose calendars close New York on 7
// October while London and Toronto trade; and the bell run
// (STONKS_FETCH_RUN=bell), AAPL and the S&P 500 across Friday 23 October's
// open, from Yahoo's answers either side of it.
ShellRoot {
  id: harness

  property int failures: 0
  readonly property string mode: Quickshell.env("STONKS_FETCH_RUN") || "main"
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")
  readonly property var listed: mode === "bell" ? ["AAPL", "^GSPC"] : ["NEST", "KILN", "SPY", "^GSPC", "BTC-USD", "SHEL.L", "7203.T", "SHOP.TO"]
  // Midnight starting Wednesday 7 October and Saturday 10 October in New York.
  readonly property int wed7: 1791345600
  readonly property int sat10: 1791604800

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  function at(day, hour, minute) {
    return day + hour * 3600 + (minute || 0) * 60
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

  // The last good quotes the service saved, by symbol.
  function cached() {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = Quickshell.env("XDG_CACHE_HOME") + "/grvc.stonks/quotes.json"
    var quotes = {}
    try { quotes = JSON.parse(String(view.text() || "")).quotes || {} } catch (e) { quotes = {} }
    view.destroy()
    return quotes
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

  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = find(item.children[i], name)
      if (found) return found
    }
    return null
  }

  function finish() {
    console.log(harness.mode === "main" ? "FETCH DONE" : harness.mode === "holiday" ? "FETCH HOLIDAY DONE" : "FETCH BELL DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  // The plugin as the shell composes it, with this harness as its shell.
  Stonks.Plugin { id: plugin; shell: shellApi }
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
  // Each path's mode, as `stat` gives it ("600").
  Process {
    id: statProc
    stdout: StdioCollector { id: statOut; waitForEnd: true }
  }

  // A screen as Hyprland reports it, for the window host (fetch.sh): on or
  // off, as it says when asked again, a turn later, as Hyprland's answer
  // comes, showing this workspace. It counts the asks it has not answered
  // yet (`screensHeard`).
  QtObject {
    id: screenStandIn
    property bool on: true
    property var lastIpcObject: ({ dpmsStatus: true })
    property var activeWorkspace: workspaceHere
    property int unanswered: 0
    function refresh() {
      unanswered++
      Qt.callLater(function() {
        screenStandIn.lastIpcObject = { dpmsStatus: screenStandIn.on }
        screenStandIn.unanswered--
      })
    }
  }
  // A second screen, always on, showing the other workspace.
  QtObject {
    id: otherScreen
    property var lastIpcObject: ({ dpmsStatus: true })
    property var activeWorkspace: workspaceThere
    function refresh() { Qt.callLater(function() { otherScreen.lastIpcObject = { dpmsStatus: true } }) }
  }

  // The service's writes of the data file, each as it is saved.
  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  property int dataWrites: 0
  Connections {
    target: service.testDataFile
    function onSaved() { harness.dataWrites++ }
  }
  function savedFeatured() {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = harness.dataPath
    var featured = ""
    try { featured = JSON.parse(String(view.text() || "")).featured } catch (e) { featured = "" }
    view.destroy()
    return featured
  }

  TestCase {
    name: "Fetch"
    when: service.pluginsReady && pillWindow.visible

    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 50) wait(50)
      return fn()
    }

    function runCommand(command) {
      fileProc.command = command
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }
    function touch(name) { runCommand(["touch", harness.state + "/" + name]) }
    function remove(name) { runCommand(["rm", "-f", harness.state + "/" + name]) }
    function modes(paths) {
      statProc.command = ["stat", "-c", "%a"].concat(paths)
      statProc.running = true
      tryVerify(function() { return !statProc.running }, 2000)
      return String(statOut.text).trim().split("\n").join(",")
    }

    // No quote run is out, the preview's included: the clock moves on only
    // once each run has landed, as it would in the seconds a run takes.
    function idle() {
      return [service.testFeed, service.testPreviewFeed].every(function(feed) {
        return feed.firstRun.length === 0 && feed.refreshRun.length === 0
      })
    }
    function settle() {
      if (!idle()) tryVerify(idle, 10000)
    }

    // What the window's header says from now, each change as it happens:
    // the function returned stops listening and gives them. Read on the
    // header's own change, not on frames: under load no frame may be drawn
    // between an answer landing and the step reading what was said.
    function listen() {
      var body = app.testBody
      var said = [body.headerText]
      var heard = function() { if (said[said.length - 1] !== body.headerText) said.push(body.headerText) }
      body.headerTextChanged.connect(heard)
      return function() {
        body.headerTextChanged.disconnect(heard)
        return said
      }
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
    function countsOver(label, seconds, want, begin, each) {
      var from = harness.requests().length
      begin()
      tick(seconds - 5, 5, each)
      var got = harness.quoteCounts(harness.requests().slice(from))
      var off = harness.listed.filter(function(s) { return want[s] === 0 ? got[s] !== 0 : Math.abs(got[s] - want[s]) > 1 })
      harness.check(label, off.length === 0, harness.listed.map(function(s) { return s + " " + got[s] + "/" + want[s] }).join(", "))
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

    function test_main() {
      if (harness.mode !== "main") skip("another run")
      var start = service.now

      // 05:59, offline, with last session's quotes saved: NEST's Tuesday
      // close and London's Thursday. The pill shows NEST's saved change at
      // once, no "!"; the window's rows say when each is from.
      harness.check("an offline start shows the saved figures at once, as old, with no warning",
        !!pill.featured && pill.changeText !== "…" && !pill.warns && service.entries.NEST.status === "saved",
        pill.changeText + " | " + JSON.stringify(service.entries.NEST))
      openWindow()
      var body = app.testBody
      var nestRow = body.watchlist.rowItem("NEST")
      var shelRow = body.watchlist.rowItem("SHEL.L")
      within(3000, function() { return body.featuredFreshness.state === "saved" })
      // London's row into sight, wherever the window's height leaves it: a
      // row far out of sight keeps what it last showed.
      body.watchlist.scrollToRow(body.watchlist.displayedSymbols.indexOf("SHEL.L"))
      within(3000, function() { return body.watchlist.sightSymbols.indexOf("SHEL.L") >= 0 && shelRow.quote !== null })
      var savedNotes = [nestRow ? nestRow.detail : "", shelRow ? shelRow.detail : "", body.featuredFreshness.state].join(" | ")
      body.watchlist.scrollToRow(0)
      within(3000, function() { return body.watchlist.contentY === 0 })
      // London's time names its zone for the harness's reader in New York.
      harness.check("the saved rows and hero say their day and time, plainly: Tuesday's close, London's Thursday",
        /^As of Tue \d\d:\d\d \| As of Thu \d\d:\d\d BST \| saved$/.test(savedNotes), savedNotes)
      var warned = []
      tick(85, 1, function() { if (marks().some(function(m) { return /!/.test(m) })) warned.push(service.now - start) })
      harness.check("no warning for the first 90 s with no answer", warned.length === 0, warned.join(","))
      tick(6, 1)
      var lateNotes = [pill.warns, nestRow.detail, body.watchlist.rowItem("SHOP.TO").detail, body.headerText].join(" | ")
      // Every listing unanswered is Yahoo's trouble, said once in the
      // header, not by every row. Found by the design panel of 23 October:
      // every row said "No data for this symbol".
      harness.check("90 s asked and unanswered for every listing: the pill warns, the window's header says once that it can't get prices, a saved row says when its price is from, and a row with nothing saved says nothing",
        /^true \| As of Tue \d\d:\d\d \|  \| Can't get prices · Stonks keeps trying$/.test(lateNotes), lateNotes)
      // A chart asked for meanwhile, SHOP.TO's, with nothing saved: the
      // chart says nothing of loading under a header that says no prices
      // come. Found in check-77: "Loading AAPL…" under that header. The
      // pill, on SHOP.TO with no price, says the header's words, not "No
      // data", which is for a symbol Yahoo answered without one (range.qml).
      service.feature("SHOP.TO")
      tryVerify(function() { return body.chartLoading && body.motion.dimmed > 0 }, 3000)
      var coming = [body.chartLoading, harness.find(body, "loadingLabel").visible, body.headerText].join(" | ")
      var pillUnanswered = pill.changeText
      service.feature("NEST")
      tryVerify(function() { return !body.chartLoading }, 3000)
      harness.check("with no prices coming, a chart asked for says nothing of loading under the header that says so",
        coming === "true | false | Can't get prices · Stonks keeps trying", coming)
      harness.check("a pill with no price, its symbol unanswered for 90 s, says it can't get prices",
        pillUnanswered === "! Can't get prices", pillUnanswered)
      tick(9, 1)
      // The run is two requests: the pill's chart and one spark of the rest.
      var tries = harness.requests().filter(function(l) { return / 000$/.test(l) })
      harness.check("with no network, a run, then one request alone at 2, 6, 14, 30, and 62 s: no more",
        tries.length >= 5 && tries.length <= 9, tries.length + " requests unanswered in 100 s")
      remove("YAHOO.offline")
      var back = service.now
      var landed = 0
      tick(80, 1, function() { if (!landed && service.entries.NEST.status === "ok") landed = service.now - back })
      harness.check("the network back: the pill's symbol lands within the next pause, a minute at most",
        landed > 0 && landed <= 75 && harness.listed.every(function(s) { return !!service.quotes[s] }), landed + " s")
      harness.check("once answered, the marks clear", marks().length === 0, marks().join(" | "))
      var cache = harness.cached()
      harness.check("the first answer is saved for the next start at once",
        !!cache.NEST && cache.NEST.quote.marketTime === service.quotes.NEST.marketTime, Object.keys(cache).join(","))
      closeWindow()

      // 06:05, pre-market: nothing open, then the window. 15 minutes each.
      // The index has no pre- or post-market: it is closed until its
      // session, on the slow clock with the window open.
      countsOver("06:05, nothing open: only the pill's symbol, every 5 minutes, and London, trading, every minute",
        900, counts([3, 0, 0, 0, 0, 15, 0, 0]), startAt(at(harness.wed7, 6, 5)))
      countsOver("06:20, the window open: the hero every minute, the pre-market rows every 5, closed markets every 15, London and the crypto every minute",
        900, counts([15, 3, 3, 1, 15, 15, 1, 1]), openAfter)
      closeWindow()
      cache = harness.cached()
      harness.check("the rest of the first answers are saved within ten minutes on the clock, every listing's",
        harness.listed.every(function(s) { return cache[s] && cache[s].quote.marketTime === service.quotes[s].marketTime }),
        Object.keys(cache).join(","))

      // A removal taken back with the next write due: the file holds the
      // symbol again. Written as its quote came back, before All took it
      // back, the file left it out, and an unchanged price never put it in.
      service.removeSymbol("KILN")
      tick(21 * 60, 60)
      var since = service.now - service.quotesSavedAt
      service.undoRemoval("KILN")
      for (var w = 0; w < 50 && !harness.cached().KILN; w++) wait(20)
      cache = harness.cached()
      harness.check("a removal taken back with a write due is saved again for the next start",
        service.library.indexOf("KILN") >= 0 && !!cache.KILN,
        since + " s since the last write | " + Object.keys(cache).join(","))

      // 11:00, the regular session: the rows stay warm with nothing open.
      countsOver("11:00, nothing open: every stock, ETF, and index in its session every minute; the crypto and Tokyo not at all",
        900, counts([15, 15, 15, 15, 0, 15, 0, 15]), startAt(at(harness.wed7, 11, 0)))
      // F2 and F4: an open finds the rows fresh; it asks only for what is
      // stale, in one run, and shows no warning and no "As of" on any frame.
      // It opens past the minute's run, when no row falls due for most of a
      // minute: an ask takes with it what falls due within half a minute.
      tick(20)
      var shownMarks = []
      var watchFrames = function() { marks().forEach(function(m) { if (shownMarks.indexOf(m) < 0) shownMarks.push(m) }) }
      frames.each = watchFrames
      var runsBefore = harness.runs().length
      frames.running = true
      openWindow()
      wait(300)
      frames.running = false
      var openRuns = harness.runs().slice(runsBefore)
      harness.check("an open mid-session asks only for the stale, the crypto and Tokyo, in one run, one spark request",
        openRuns.length === 1 && openRuns[0] === "spark:BTC-USD,7203.T", openRuns.join(" / "))
      harness.check("an open mid-session shows no warning and no As of on any frame", shownMarks.length === 0, shownMarks.join(" | "))
      closeWindow()
      tick(30)
      runsBefore = harness.runs().length
      openWindow()
      harness.check("an open 30 s later asks for nothing", harness.runs().length === runsBefore, harness.runs().slice(runsBefore).join(" / "))
      // London closes at 16:30, 11:30 here, half a minute before this
      // window ends: its last minute's request does not go.
      countsOver("11:15, the window open: every listing trading every minute, London until its close; Tokyo, closed, every 15",
        900, counts([15, 15, 15, 15, 15, 14, 1, 15]), startAt(service.now + 5))

      // Five rows featured 12 seconds apart, across a minute: each new
      // hero's chart is asked at once, at a second of its own, and the next
      // run takes each with it, however far from the list's second, so the
      // list goes on refreshing in one run a minute. Each used to keep its
      // own second, five or six runs a minute.
      ;["KILN", "SPY", "^GSPC", "SHOP.TO", "NEST"].forEach(function(s) {
        service.feature(s)
        tick(12, 1)
      })
      tick(60)
      var featuredFrom = harness.runs().length
      tick(300)
      var featuredRuns = harness.runs().slice(featuredFrom)
      harness.check("five rows featured across a minute: the list still refreshes in one run a minute",
        featuredRuns.length <= 6, featuredRuns.length + " runs in 5 minutes: " + featuredRuns.join(" / "))
      // The next run, so r below finds every answer older than 10 s.
      var runsNow = harness.runs().length
      for (var w = 0; w < 61 && harness.runs().length === runsNow; w++) tick(1, 1)

      // F7: r twice within 5 s sends one run.
      tick(20)
      runsBefore = harness.runs().length
      app.refresh()
      tick(2, 1)
      app.refresh()
      tick(3, 1)
      var rRuns = harness.runs().slice(runsBefore).filter(function(r) { return /chart:/.test(r) })
      harness.check("r twice within 5 s sends one run", rRuns.length === 1, rRuns.join(" / "))

      // F5: Yahoo refuses. The run that meets it is the last for a pause of
      // a minute, give or take a fifth; then one request goes alone; then
      // the pause doubles. An answer to a request let through before the
      // refusal, the hero's 1M history held back until then, reopens
      // nothing. 90 s after the ask, the pill and the rows warn, quietly. A
      // range picked meanwhile fails at once. Closing the window drops the
      // asks nobody watches.
      touch("NEST.history.hold")
      body.selectRange("1M")
      // The history is out, and held, before Yahoo starts refusing.
      tryVerify(function() { return harness.record("NEST.history.calls") !== "" }, 3000)
      touch("YAHOO.refuse")
      var askedAt = 0
      tick(70, 1, function() { if (!askedAt && service.testYahooGate.pause === "refused") askedAt = service.now })
      remove("NEST.history.hold")
      tryVerify(function() { return !!service.histories["NEST|1M"] }, 5000)
      harness.check("an answer to a request let through before the refusal reopens nothing",
        service.histories["NEST|1M"].status === "ok" && service.testYahooGate.pause === "refused",
        service.histories["NEST|1M"].status + " | " + service.testYahooGate.pause)
      body.selectRange("1D")
      var refusedFrom = harness.requests().length
      var lone = []
      var warnedAt = 0
      tick(78, 1, function() {
        var sent = harness.yahoo(harness.requests().slice(refusedFrom)).length
        if (sent > lone.length) lone.push(service.now - askedAt)
        if (!warnedAt && pill.warns && /^! Update overdue/.test(body.watchlist.rowItem("KILN").detail)) warnedAt = service.now - askedAt
      })
      harness.check("refused: nothing goes for the pause, then one request alone, between 48 and 72 s",
        askedAt > 0 && lone.length === 1 && lone[0] >= 48 && lone[0] <= 73, "refused at " + askedAt + ", alone at " + lone.join(","))
      harness.check("refused: from 90 s after the ask, the pill and the rows say the update is overdue",
        warnedAt >= 85 && warnedAt <= 96, warnedAt + " s")
      body.selectRange("1W")
      var rangeHeader = ""
      within(1000, function() { rangeHeader = body.headerText; return rangeHeader === "1W unavailable" })
      // r while Yahoo refuses sends nothing, and says nothing: the header
      // stays on the range's failure, its retry failing at once.
      var failedWeek = service.histories["NEST|1W"]
      var heard = listen()
      app.refresh()
      var retried = within(1000, function() { return service.histories["NEST|1W"] !== failedWeek })
      wait(50)
      var pausedSaid = heard()
      body.selectRange("1D")
      harness.check("a range picked while Yahoo refuses says it is unavailable at once, not Loading", rangeHeader === "1W unavailable", rangeHeader)
      harness.check("r while Yahoo refuses sends nothing and says nothing: the header stays on the range's failure",
        retried && pausedSaid.join(" / ") === "1W unavailable", retried + " " + pausedSaid.join(" / "))
      closeWindow()
      harness.check("closing drops the asks nobody watches: the crypto and Tokyo are no longer owed",
        !("BTC-USD" in service.asked) && !("7203.T" in service.asked) && "NEST" in service.asked, JSON.stringify(service.asked))
      openWindow()
      remove("YAHOO.refuse")
      var recovered = 0
      tick(180, 1, function() { if (!recovered && service.testYahooGate.pause === "" && idle() && Object.keys(service.asked).length === 0) recovered = service.now })
      var refused = harness.yahoo(harness.requests().slice(refusedFrom)).filter(function(l) { return / 429$/.test(l) })
      harness.check("Yahoo back: the next lone request reopens it, the next run carries everything, and the marks clear",
        recovered > 0 && marks().length === 0, (recovered ? recovered - askedAt : "never") + " s | " + marks().join(" | "))
      harness.check("through the refusal, one request per pause: one alone before the one that found Yahoo back",
        refused.length === 1, refused.join(", "))

      // F6: back within seconds of the network, as after a wake: it goes
      // with the next run, and comes back 10 s later. A search's preview
      // that rests meanwhile waits for it too, and goes once it is back.
      touch("YAHOO.offline")
      var offFrom = harness.requests().length
      var downAt = 0
      for (var wait6 = 0; wait6 < 70 && !downAt; wait6++) {
        tick(1, 1)
        if (harness.requests().slice(offFrom).some(function(l) { return / 000$/.test(l) })) downAt = service.now
      }
      service.preview(body, "AAPL")
      wait(400)
      tick(10, 1)
      remove("YAHOO.offline")
      var upAt = service.now
      var back6 = 0
      var bang = []
      tick(20, 1, function() {
        if (!back6 && service.entries.NEST.answeredAt >= upAt) back6 = service.now - downAt
        if (marks().some(function(m) { return /!/.test(m) })) bang.push(service.now - downAt)
      })
      // The ladder's waits are 2, 4, and 8 s, each a fifth either way, and
      // whole seconds on this clock: the third try lands 14 to 18 s on.
      harness.check("a network back 10 s after it went is used within 18 s, with no warning on the way",
        downAt > 0 && back6 > 0 && back6 <= 18 && bang.length === 0,
        back6 + " s, warned at " + bang.join(",") + "; went at " + downAt + ", " + harness.requests().slice(offFrom).join(", "))
      // The preview's run is its own feed's: let it land.
      tryVerify(function() { return service.testPreviewFeed.firstRun.length === 0 }, 3000)
      harness.check("a preview held while the network was down is fetched once it is back",
        harness.requests().slice(offFrom).some(function(l) { return l === "chart AAPL 200" }), harness.requests().slice(offFrom).join(", "))
      service.preview(body, "")

      // Back after two minutes off, as on a train: the pause between tries
      // has grown to about a minute, and r tries at once instead of waiting
      // it out. It went 53 s after r, the header on "Update overdue" all
      // the while. A refusal's pause still holds (above).
      touch("YAHOO.offline")
      var gate = service.testYahooGate
      var pausedLong = false
      for (var offFor = 0; offFor < 240 && !pausedLong; offFor++) {
        tick(1, 1)
        pausedLong = gate.pause === "none" && !gate.probing && gate.pausedUntil - service.now >= 30
      }
      remove("YAHOO.offline")
      var rFrom = harness.requests().length
      var pressedAt = service.now
      app.refresh()
      var tried = within(2000, function() { return harness.yahoo(harness.requests().slice(rFrom)).length > 0 })
      settle()
      harness.check("the network back after two minutes off: r asks Yahoo at once, not when the minute's pause runs out, and its answer reopens Yahoo",
        pausedLong && tried && service.now === pressedAt && gate.pause === "",
        pausedLong + " " + tried + " " + (service.now - pressedAt) + " s, pause " + gate.pause + ": " + harness.requests().slice(rFrom).join(", "))

      // A longer list: 42 more busy stocks, 50 in all. The first add goes
      // at once, the rest's first answers together in the next run, three
      // spark requests; each day holds jumps no chart has judged, so each is
      // asked on the chart next. Then every row refreshes every minute, the
      // pill's symbol too, with no warning and well inside the budget.
      service.now = at(harness.wed7, 12, 0)
      settle()
      var more = []
      for (var n = 1; n <= 42; n++) more.push("LONG" + (n < 10 ? "0" : "") + n)
      runsBefore = harness.runs().length
      more.forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && idle() }, 20000)
      var firstRuns = harness.runs().slice(runsBefore).filter(function(r) { return /LONG/.test(r) })
      harness.check("42 symbols added at once have their first answers in two runs: the first add's, and the rest's in two spark requests and a lone chart",
        firstRuns[0] === "chart:LONG01"
          && firstRuns.some(function(r) { return r === "spark:" + more.slice(1, 21).join(",") + " spark:" + more.slice(21, 41).join(",") + " chart:LONG42" }),
        firstRuns.slice(0, 2).join(" / "))
      var longFrom = harness.requests().length
      var longBang = []
      tick(600, 5, function() { if (marks().some(function(m) { return /!/.test(m) })) longBang.push(service.now) })
      var longReqs = harness.requests().slice(longFrom)
      var longCounts = { NEST: 0 }
      more.forEach(function(s) { longCounts[s] = 0 })
      longReqs.forEach(function(l) {
        var p = l.split(" ")
        if (p[0] === "chart" || p[0] === "spark") p[1].split(",").forEach(function(s) { if (s in longCounts) longCounts[s]++ })
      })
      var starved = more.filter(function(s) { return longCounts[s] < 9 })
      harness.check("50 symbols: the pill's symbol and every row every minute, in a few requests, no warning",
        Math.abs(longCounts.NEST - 10) <= 1 && starved.length === 0 && longBang.length === 0 && longReqs.length <= 60,
        "NEST " + longCounts.NEST + ", LONG01 " + longCounts.LONG01 + ", LONG42 " + longCounts.LONG42 + ", starved " + starved
          + ", warned " + longBang.length + ", " + longReqs.length + " requests in 10 min")
      more.forEach(function(s) { service.removeSymbol(s) })
      closeWindow()

      // 15:00, the window left on 1W: its history is asked again every 15
      // minutes while New York trades, and once after the close for its
      // last bars, then not again, so its line and its low and high keep up
      // with the price over them. A refresh that fails, tried twice, is
      // asked again 15 minutes on. It was asked once, and kept all session.
      service.now = at(harness.wed7, 15, 0)
      settle()
      openWindow()
      body.selectRange("1W")
      tryVerify(function() { return !!service.histories["NEST|1W"] && service.histories["NEST|1W"].status === "ok" }, 5000)
      var weekFrom = Number(harness.record("NEST.history.calls") || 0)
      tick(20 * 60, 15)
      touch("NEST.history.down")
      tick(15 * 60, 15)
      tryVerify(function() { return service.histories["NEST|1W"].status === "failed" }, 8000)
      remove("NEST.history.down")
      tick(45 * 60, 15)
      var weekAsked = Number(harness.record("NEST.history.calls") || 0) - weekFrom
      harness.check("the window left on 1W from 15:00 to 16:20: its history asked again every 15 minutes until the close, a failed refresh twice and again 15 minutes on, then once for its last bars",
        weekAsked === 5, weekAsked + " asks")
      body.selectRange("1D")
      settle()
      closeWindow()

      // 16:30, after hours. The pill's wheel moves to KILN, which nothing
      // watched: it is asked for at once, and shown without a warning.
      service.now = at(harness.wed7, 16, 30)
      settle()
      var wheelFrom = harness.requests().length
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, -120)
      settle()
      var wheeled = harness.quoteCounts(harness.requests().slice(wheelFrom))
      harness.check("the pill's wheel asks for the symbol it lands on at once",
        service.featuredSymbol === "KILN" && wheeled.KILN === 1 && !pill.warns, service.featuredSymbol + " " + JSON.stringify(wheeled))
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, 120)
      settle()
      // A spin's notches are saved once the wheel rests: three down and one
      // back write the data file once, naming where it stopped.
      wait(600)
      var writesBefore = harness.dataWrites
      var visited = []
      var visit = function() { visited.push(service.featuredSymbol) }
      service.featuredSymbolChanged.connect(visit)
      for (var notch = 0; notch < 4; notch++) mouseWheel(pill, pill.width / 2, pill.height / 2, 0, notch < 3 ? -120 : 120)
      wait(150)
      var duringSpin = harness.dataWrites - writesBefore
      within(3000, function() { return harness.dataWrites > writesBefore })
      wait(300)
      settle()
      service.featuredSymbolChanged.disconnect(visit)
      harness.check("a spin of the pill's wheel writes the data file once, as the wheel rests",
        visited.join(" ") === "KILN SPY ^GSPC SPY" && duringSpin === 0 && harness.dataWrites - writesBefore === 1 && harness.savedFeatured() === "SPY",
        visited.join(" ") + ": " + duringSpin + " writes during the spin, " + (harness.dataWrites - writesBefore) + " in all, saved " + harness.savedFeatured())
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, 120)
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, 120)
      wait(600)
      settle()
      // The index is closed after its session, as its calendar says: not
      // asked with nothing open, on the slow clock with the window open.
      countsOver("16:35, nothing open: only the pill's symbol, every 5 minutes",
        900, counts([3, 0, 0, 0, 0, 0, 0, 0]), startAt(at(harness.wed7, 16, 35)))
      countsOver("16:50, the window open: the hero every minute, the after-hours rows every 5 (Toronto's until its 17:00 end), the closed every 15, the crypto every minute",
        900, counts([15, 3, 3, 1, 15, 1, 1, 2]), openAfter)

      // An add's first answer goes in a run of its own, ahead of any
      // refresh.
      runsBefore = harness.runs().length
      service.addSymbol("MSFT")
      tryVerify(function() { return !!service.quotes.MSFT && idle() }, 5000)
      harness.check("an add's first answer goes at once, in a run of its own", harness.runs()[runsBefore] === "chart:MSFT", harness.runs().slice(runsBefore).join(" / "))
      service.removeSymbol("MSFT")

      // A search's preview outside All: its quote once, as the choice rests,
      // and never again, through the same gate.
      var previewFrom = harness.requests().length
      service.preview(body, "AAPL")
      tryVerify(function() { return harness.requests().slice(previewFrom).some(function(l) { return /^chart AAPL /.test(l) }) }, 3000)
      tick(600)
      var previewed = harness.requests().slice(previewFrom).filter(function(l) { return /^chart AAPL /.test(l) })
      harness.check("a preview outside All is fetched once as the choice rests, never on the schedule", previewed.length === 1, previewed.join(", "))
      service.preview(body, "")
      closeWindow()

      // 17:20, the crypto's saved quote two hours old and nothing kept it
      // fresh for five minutes: an open asks for it, its answer held out,
      // as on a real network. Its row shows its last price with no "As of"
      // for the 2 s an answer takes (`Figures.ASKED_GRACE`), says "As of"
      // from then on, and goes on saying it once its answer, as old, lands:
      // the source is late, not Stonks. Found in the speed QA of 23
      // October: "As of 06:46 UTC" flashed on each open. The service's
      // clock runs as a real one does, its next second 100 ms after the
      // open, so the ask goes 0.9 s into its second: counted in whole
      // seconds, the grace ended 1.1 s on. Found in the check of #69.
      tick(300)
      var start = service.now
      touch("BTC-USD.quote.hold")
      app.testWindow.implicitHeight = 1000
      app.open("{}")
      var opened = Date.now()
      var heldOut = false
      var asOfAt = 0
      for (var t = 0; t < 4000 && !asOfAt; t = Date.now() - opened) {
        service.now = start + Math.floor((t + 900) / 1000)
        heldOut = heldOut || ("BTC-USD" in service.asked && !idle())
        var btcRow = app.opened ? app.testBody.watchlist.rowItem("BTC-USD") : null
        if (btcRow && /^As of /.test(btcRow.detail)) asOfAt = t
        wait(20)
      }
      remove("BTC-USD.quote.hold")
      settle()
      harness.check("an open on a crypto nothing kept fresh shows no As of on its row for the first 2 s of its answer's wait, then As of while it stays out, and after its old answer",
        heldOut && asOfAt >= 1900 && asOfAt <= 2600 && /^As of /.test(app.testBody.watchlist.rowItem("BTC-USD").detail),
        heldOut + " | As of at " + asOfAt + " ms | " + app.testBody.watchlist.rowItem("BTC-USD").detail)
      closeWindow()

      // 23:00, Tokyo's lunch break until 23:30; New York's night, with
      // Robinhood for the window's hero. Half an hour each, so a pill's
      // symbol never asked cannot pass for one asked every 15 minutes.
      var quiet = countsOver("23:00, nothing open: the pill's symbol every 15 minutes, the index, closed by its calendar, and Tokyo at lunch not at all",
        1800, counts([2, 0, 0, 0, 0, 0, 0, 0]), startAt(at(harness.wed7, 23, 0)))
      harness.check("with nothing open, Robinhood is never asked", quiet.every(function(l) { return !/^(overnight|instruments) /.test(l) }))
      var night = countsOver("23:30, the window open: the crypto and Tokyo, back from lunch, every minute; every closed market every 15",
        900, counts([1, 1, 1, 1, 15, 1, 15, 1]), openAfter)
      var prints = night.filter(function(l) { return /^overnight /.test(l) }).length
      harness.check("23:30, the window open: Robinhood's prints every 5 minutes through the night", Math.abs(prints - 3) <= 1, prints + " requests")
      closeWindow()

      // Midnight, the window left open on a workspace no screen shows: it
      // asks what a closed one asks, the pill's symbol every 15 minutes and
      // Tokyo, trading, every minute, and nothing of Robinhood, whose prints
      // a window in sight asks every 5 minutes through the night. Back in
      // sight, what fell due goes at once.
      hyprlandStandIn.toplevels = { values: [stonksToplevel] }
      plugin.windowHost.monitors = [screenStandIn]
      stonksToplevel.workspace = workspaceThere
      var away = countsOver("00:00, the window open on a workspace no screen shows: the pill's symbol every 15 minutes, Tokyo, trading, every minute, nothing else",
        1800, counts([2, 0, 0, 0, 0, 0, 30, 0]), function() {
          startAt(at(harness.wed7 + 86400, 0, 0))()
          answerScreens()
          app.open("{}")
          tryVerify(function() { return app.opened }, 3000)
          answerScreens()
        }, answerScreens)
      harness.check("out of sight, the window asks nothing of Robinhood", away.every(function(l) { return !/^(overnight|instruments) /.test(l) }),
        away.filter(function(l) { return /^(overnight|instruments) /.test(l) }).join(", "))
      var backFrom = harness.requests().length
      stonksToplevel.workspace = workspaceHere
      var caughtUp = within(3000, function() {
        var back = harness.requests().slice(backFrom)
        return harness.quoteCounts(back)["BTC-USD"] === 1 && back.some(function(l) { return /^overnight /.test(l) })
      })
      harness.check("back in sight, what fell due goes at once: the crypto, and Robinhood's prints", caughtUp,
        harness.requests().slice(backFrom).join(", "))
      settle()
      // Out of sight again, the pill steps to SHEL.L, whose cap and P/E no
      // one has asked for: the window asks for them only once it is back in
      // sight, as a closed one would on its next open.
      stonksToplevel.workspace = workspaceThere
      answerScreens()
      var stepFrom = harness.requests().length
      service.feature("SHEL.L")
      settle()
      var figures = function() { return harness.requests().slice(stepFrom).filter(function(l) { return /^fundamentals SHEL\.L /.test(l) }) }
      var unseenAsked = within(1500, function() { return figures().length > 0 })
      stonksToplevel.workspace = workspaceHere
      var seenAsked = within(3000, function() { return figures().length > 0 })
      harness.check("out of sight, the window asks for no cap and P/E as the pill steps, and back in sight it asks",
        !unseenAsked && seenAsked, (unseenAsked ? "asked while out of sight" : "none while out of sight") + "; then " + figures().join(", "))
      service.feature("NEST")
      settle()

      // 00:35, two screens: the window's switched off, the other on and
      // showing another workspace. No screen shows the window, so it asks
      // what a closed one asks, though not every screen is off.
      plugin.windowHost.monitors = [screenStandIn, otherScreen]
      var dark = countsOver("00:35, the window's screen off and the other on: the pill's symbol, Tokyo every minute, nothing else",
        900, counts([1, 0, 0, 0, 0, 0, 15, 0]), function() {
          screenStandIn.on = false
          screenStandIn.refresh()
          screensHeard()
          startAt(at(harness.wed7 + 86400, 0, 35))()
          answerScreens()
        }, answerScreens)
      harness.check("its screen off, the window asks nothing of Robinhood", dark.every(function(l) { return !/^(overnight|instruments) /.test(l) }),
        dark.filter(function(l) { return /^(overnight|instruments) /.test(l) }).join(", "))
      screenStandIn.on = true
      screenStandIn.refresh()
      screensHeard()
      settle()
      closeWindow()
      hyprlandStandIn.toplevels = { values: [] }
      plugin.windowHost.monitors = []

      // Thursday 11:00, nothing open, every quote still Wednesday's: the
      // calendars say New York, London, and Toronto trade, so their rows
      // stay warm and learn of Thursday's session, the index on the US
      // calendar too. They used to wait for an open.
      countsOver("Thursday 11:00, nothing open, the quotes a day old: every row whose calendar trades kept warm",
        900, counts([15, 15, 15, 15, 0, 15, 0, 15]), startAt(at(harness.wed7 + 86400, 11, 0)))

      // 11:15, every screen off: nothing is asked for, the pill's symbol
      // included. With a screen on again, the next look asks at once for
      // every row that fell due meanwhile.
      plugin.windowHost.monitors = [screenStandIn]
      screenStandIn.on = false
      var darkFrom = harness.requests().length
      tick(600)
      // A refresh asked for meanwhile, by IPC or a script, waits too.
      service.refresh()
      screensHeard()
      var dark = harness.quoteCounts(harness.requests().slice(darkFrom))
      screenStandIn.on = true
      // The next look comes a minute on, when the screens' last answer is
      // long past.
      wait(1100)
      service.now += 60
      within(3000, function() { return harness.quoteCounts(harness.requests().slice(darkFrom)).NEST > 0 })
      settle()
      var lit = harness.quoteCounts(harness.requests().slice(darkFrom))
      harness.check("every screen off, nothing is asked for, a refresh included; a screen on, the next look asks for every warm row at once",
        harness.listed.every(function(s) { return dark[s] === 0 })
          && ["NEST", "KILN", "SPY", "SHOP.TO"].every(function(s) { return lit[s] === 1 }) && lit["BTC-USD"] === 0,
        "off: " + JSON.stringify(dark) + " | on: " + JSON.stringify(lit))

      // A run queued behind a host's pause, the screens gone off since
      // their last answer: the pause ending between minute looks starts
      // nothing until a fresh answer says a screen is on.
      // The network goes; two minutes on, the warm rows fall due and their
      // run finds no answer, which pauses the host.
      touch("YAHOO.offline")
      var outageFrom = harness.runs().length
      service.now = (Math.floor(service.now / 60) + 2) * 60 + 5
      within(3000, function() { return harness.runs().length > outageFrom && idle() })
      settle()
      var pausedRuns = harness.runs().length - outageFrom
      wait(1100)
      screenStandIn.on = false
      var pausedFrom = harness.runs().length
      service.now += 5
      screensHeard()
      var whilePausedDark = harness.runs().length - pausedFrom
      remove("YAHOO.offline")
      screenStandIn.on = true
      wait(1100)
      service.now += 60
      within(3000, function() { return harness.runs().length > pausedFrom })
      settle()
      harness.check("a run held by a host's pause starts nothing once every screen is off, and goes once one is on",
        pausedRuns === 1 && whilePausedDark === 0 && harness.runs().length > pausedFrom,
        pausedRuns + " run into the outage, " + whilePausedDark + " with the screens off, " + (harness.runs().length - pausedFrom) + " after")

      // A refresh with the window on a range while every screen is off,
      // its quotes too fresh to ask again, owes the range's history: it is
      // asked fresh once a screen is on, with no quote due to prompt it.
      // Until then nothing is out, and the header says nothing of it.
      openWindow()
      app.testBody.selectRange("1W")
      tryVerify(function() { return !!service.histories["NEST|1W"] && service.histories["NEST|1W"].status === "ok" }, 5000)
      settle()
      screenStandIn.on = false
      wait(1100)
      var historyFrom = Number(harness.record("NEST.history.calls") || 0)
      heard = listen()
      service.refresh()
      screensHeard()
      wait(50)
      var darkSaid = heard()
      var darkHistory = Number(harness.record("NEST.history.calls") || 0) - historyFrom
      screenStandIn.on = true
      wait(1100)
      service.now += 5
      within(3000, function() { return Number(harness.record("NEST.history.calls") || 0) > historyFrom })
      var litHistory = Number(harness.record("NEST.history.calls") || 0) - historyFrom
      app.testBody.selectRange("1D")
      settle()
      closeWindow()
      plugin.windowHost.monitors = []
      harness.check("a refresh while every screen is off asks the range's history once a screen is on, not before, and says nothing meanwhile",
        darkHistory === 0 && litHistory === 1 && darkSaid.length === 1 && darkSaid[0] !== "Refreshing",
        darkHistory + " while off, " + litHistory + " after | " + darkSaid.join(" / "))

      // Thursday, the window open on the day: r says "Refreshing" in the
      // header while the quotes it asked for are out, NEST's held back
      // here, and the market again once they land; the next run on the
      // schedule, held back the same, says nothing. The owner asked for
      // "Refreshing" on r alone (21 October). The rows are answered over
      // 10 s ago first, so r asks for them.
      openWindow()
      tick(20)
      touch("NEST.quote.hold")
      heard = listen()
      app.refresh()
      within(3000, function() { return app.testBody.headerText === "Refreshing" })
      remove("NEST.quote.hold")
      settle()
      tryVerify(function() { return !service.refreshing }, 3000)
      var byR = heard()
      touch("NEST.quote.hold")
      heard = listen()
      var scheduled = false
      for (var due = 0; due < 61 && !scheduled; due++) {
        service.now += 1
        scheduled = within(100, function() { return service.testFeed.refreshRun.indexOf("NEST") >= 0 })
      }
      wait(300)
      remove("NEST.quote.hold")
      settle()
      var bySchedule = heard()
      harness.check("r says Refreshing while its quotes are out, then the market once they land; a run on the schedule says nothing",
        byR.length === 3 && byR[1] === "Refreshing" && byR[0] === byR[2] && scheduled
          && bySchedule.every(function(t) { return t !== "Refreshing" }),
        byR.join(" / ") + " | " + scheduled + " " + bySchedule.join(" / "))
      closeWindow()

      // Thursday, trading: a day whose current after-hours period ends at
      // {"toString": null} fails its own listing, as a bad answer does, and
      // the rest of the list is still asked for on its schedule. The day read
      // as a quote, and every look for what was due threw on it, so no row
      // was asked for again (the 1.0.4 security review's finding).
      openWindow()
      service.addSymbol("HOSTILE")
      var hostileFailed = within(15000, function() {
        return !!service.entries.HOSTILE && service.entries.HOSTILE.status === "failed" && idle()
      })
      var hostileFrom = harness.requests().length
      tick(120, 5)
      var afterHostile = harness.quoteCounts(harness.requests().slice(hostileFrom))
      var trading = ["NEST", "KILN", "SPY", "BTC-USD"]
      harness.check("a day whose period ends at an object fails its own listing, and the list's next runs go on the schedule",
        hostileFailed && trading.every(function(s) { return afterHostile[s] > 0 }),
        (service.entries.HOSTILE ? service.entries.HOSTILE.status : "no answer") + " | "
          + trading.map(function(s) { return s + " " + afterHostile[s] }).join(", "))
      closeWindow()

      // Saturday noon, half an hour each.
      countsOver("Saturday noon, nothing open: the pill's symbol every 15 minutes, nothing else",
        1800, counts([2, 0, 0, 0, 0, 0, 0, 0]), startAt(at(harness.sat10, 12, 0)))
      countsOver("Saturday 12:30, the window open: the crypto every minute, the rest every 15",
        1800, counts([2, 2, 2, 2, 30, 2, 2, 2]), openAfter)
      closeWindow()

      // A malformed answer, a day whose pre-market period is null, in a
      // spark run with the rest of the list: that listing fails, as a bad
      // answer does, and the rest of the run lands, so the next refresh goes
      // as ever. The day threw as it was read, and the feed asked nothing
      // more until Stonks restarted.
      openWindow()
      service.addSymbol("MANGLED")
      within(15000, function() { return !!service.entries.MANGLED && service.entries.MANGLED.status === "failed" && idle() })
      // A refresh's spark run carries MANGLED with the rest of the list, once
      // they are all due again.
      var sparkFrom = harness.requests().length
      var carried = false
      for (var round = 0; round < 4 && !carried; round++) {
        tick(15, 1)
        service.refresh()
        carried = within(5000, function() {
          return harness.requests().slice(sparkFrom).some(function(l) { return /^spark \S*\bMANGLED\b/.test(l) })
        })
      }
      var landed = carried && within(15000, function() { return service.testFeed.refreshRun.length === 0 && idle() })
      tick(15, 1)
      var againFrom = harness.requests().length
      service.refresh()
      var nextLanded = within(15000, function() {
        return harness.requests().slice(againFrom).some(function(l) { return /^(spark|chart) /.test(l) })
          && service.testFeed.refreshRun.length === 0 && idle()
      })
      harness.check("a malformed day in a spark run fails its own listing and stops nothing: the run lands, and the next refresh goes too",
        carried && landed && nextLanded && service.entries.MANGLED.status === "failed",
        [carried, landed, nextLanded, service.entries.MANGLED.status, JSON.stringify(service.testFeed.refreshRun)].join(" | "))
      closeWindow()

      // A refusal asking for a year's rest (Retry-After 31536000): Stonks
      // rests half an hour at most, give or take a fifth, then asks again.
      // It rested as long as it was told.
      openWindow()
      runCommand(["bash", "-c", "printf 31536000 > \"$1\"", "--", harness.state + "/YAHOO.retry-after"])
      touch("YAHOO.refuse")
      var longFrom = harness.requests().length
      var restFrom = 0
      tick(120, 1, function() { if (!restFrom && service.testYahooGate.pause === "refused") restFrom = service.now })
      remove("YAHOO.refuse")
      remove("YAHOO.retry-after")
      var askedAgain = 0
      tick(40 * 60, 30, function() {
        if (!askedAgain && harness.yahoo(harness.requests().slice(longFrom)).some(function(l) { return / 200$/.test(l) })) askedAgain = service.now
      })
      harness.check("a refusal asking for a year's rest holds Yahoo for half an hour at most, then Stonks asks again",
        restFrom > 0 && askedAgain > 0 && askedAgain - restFrom <= 36 * 60,
        restFrom ? (askedAgain ? (askedAgain - restFrom) + " s at rest" : "never asked again in 40 minutes") : "never refused")
      closeWindow()

      // The data file and the saved quotes, each there before Stonks started
      // and readable by every account (0644), and the cache folder (0755),
      // are owner-only once Stonks has written them: 0600 and 0700.
      var cacheDir = Quickshell.env("XDG_CACHE_HOME") + "/grvc.stonks"
      var owned = ""
      within(3000, function() { owned = modes([harness.dataPath, cacheDir + "/quotes.json", cacheDir]); return owned === "600,600,700" })
      harness.check("the data file and the saved quotes are the owner's alone once written, and so is their folder in the cache",
        owned === "600,600,700", owned)
      // A hand edit saved by an editor that writes a new file, 0644, and
      // moves it over: Stonks' next write makes it the owner's again.
      runCommand(["bash", "-c", "cp \"$1\" \"$1.tmp\" && chmod 644 \"$1.tmp\" && mv -f \"$1.tmp\" \"$1\"", "--", harness.dataPath])
      var edited = modes([harness.dataPath])
      service.persist({ changeMode: service.changeMode === "pct" ? "abs" : "pct" })
      var rewritten = ""
      within(3000, function() { rewritten = modes([harness.dataPath]); return rewritten === "600" })
      harness.check("a data file a hand edit left open to every account is the owner's again on Stonks' next write",
        edited === "644" && rewritten === "600", edited + " then " + rewritten)

      // The window left open on SHOP.TO, its cap and P/E and the USDCAD rate
      // its P/E reads in, a day and more old: the next minute asks for both
      // again, as the popup's next open would. Nothing else asks: the window
      // stays open on one stock.
      var funds = service.testFundamentalsFeed
      openWindow()
      service.feature("SHOP.TO")
      within(5000, function() { return !!funds.fresh("SHOP.TO") && funds.rateHeld("USDCAD") && !funds.busy })
      var day = 24 * 60 * 60
      var entries = Object.assign({}, funds.entries)
      entries["SHOP.TO"] = Object.assign({}, entries["SHOP.TO"], { checkedAt: entries["SHOP.TO"].checkedAt - 2 * day })
      funds.entries = entries
      funds.rates = Object.assign({}, funds.rates, { USDCAD: Object.assign({}, funds.rates.USDCAD, { checkedAt: funds.rates.USDCAD.checkedAt - 2 * day }) })
      var agedFrom = harness.requests().length
      tick(60)
      var asked = within(3000, function() { return !!funds.fresh("SHOP.TO") && funds.rateHeld("USDCAD") && !funds.busy })
      var agedAsks = harness.requests().slice(agedFrom).filter(function(l) { return /^(fundamentals SHOP\.TO|rate USDCAD) /.test(l) })
      harness.check("a window left open on a stock asks again for its cap and P/E, and their rate, once they are a day old",
        asked && agedAsks.some(function(l) { return /^fundamentals /.test(l) }) && agedAsks.some(function(l) { return /^rate /.test(l) }),
        agedAsks.join(", ") || "nothing asked")
      service.feature("NEST")
      closeWindow()

      harness.finish()
    }

    // New York closed for a holiday while London and Toronto trade.
    function test_holiday() {
      if (harness.mode !== "holiday") skip("another run")
      tryVerify(function() { return harness.listed.every(function(s) { return !!service.quotes[s] }) && idle() }, 10000)
      // The index is on the US calendar, so the holiday closes it too,
      // whatever Yahoo's periods (a trading day's here) say.
      countsOver("a US holiday, nothing open: the pill's symbol every 15 minutes; London and Toronto, trading, every minute",
        900, counts([1, 0, 0, 0, 0, 15, 0, 15]), startAt(at(harness.wed7, 11, 0)))
      countsOver("a US holiday, the window open: New York every 15 minutes, London, Toronto, and the crypto every minute",
        900, counts([1, 1, 1, 1, 15, 15, 1, 15]), openAfter)
      closeWindow()
      // This run's cache began empty: the folder and the saved quotes are
      // new, and the owner's alone from their first write.
      var newDir = Quickshell.env("XDG_CACHE_HOME") + "/grvc.stonks"
      var newModes = ""
      within(3000, function() { newModes = modes([newDir + "/quotes.json", newDir]); return newModes === "600,700" })
      harness.check("a new cache folder and its saved quotes are the owner's alone", newModes === "600,700", newModes)
      harness.finish()
    }

    // Friday 23 October's open, the window showing AAPL and the S&P 500.
    // Yahoo answers with Thursday's quotes (bell-2026-10-23-0929) until
    // 09:30:10, then with the session's first (bell-2026-10-23-0930), as it
    // did that morning. Found in the daytime QA: every row said "As of Thu
    // 16:00" from 09:30:02 until its next ask a minute after its last.
    function test_bell() {
      if (harness.mode !== "bell") skip("another run")
      tryVerify(function() { return harness.listed.every(function(s) { return !!service.quotes[s] }) && idle() }, 10000)
      var bell = 1792762200
      openWindow()
      // Before the bell, its pre-market begun, the index has no open since
      // the open, as the stock beside it has none: its answer came after its
      // next day's pre-market began, its bars still Thursday's.
      service.persist({ changeMode: "open" })
      var openLines = []
      var blank = within(3000, function() {
        openLines = harness.listed.map(function(s) { return s + " " + app.testBody.watchlist.rowItem(s).view.changeLine })
        return openLines.join(",") === "AAPL —,^GSPC —"
      })
      harness.check("before the bell the index and the stock beside it have no open yet, since the open", blank, openLines.join(", "))
      service.persist({ changeMode: "pct" })
      // Before the bell a stock's day is asked for two days, so the chart has
      // Thursday's session; from the bell, for one. An index's answer stays
      // Thursday's until the bell, and is asked for one.
      var dayAsks = function() { return harness.record("days.log").split("\n").filter(function(l) { return l !== "" }) }
      var firstAsks = dayAsks().length
      tick(bell - 1 - service.now, 1)
      var preAsks = dayAsks().slice(firstAsks)
      var bellAsks = dayAsks().length
      tick(1, 1)
      var said = []
      var landed = 0
      var from = harness.requests().length
      tick(45, 1, function() {
        if (service.now === bell + 10)
          runCommand(["bash", "-c", "echo bell-2026-10-23-0930 listings-2026-10-07-1455 > \"$1\"", "--", harness.state + "/overnight.set"])
        marks().forEach(function(m) { said.push((service.now - bell) + " s " + m) })
        var rows = harness.listed.map(function(s) { return app.testBody.watchlist.rowItem(s) })
        if (!landed && rows[0].view.priceText === "349.62" && rows[1].view.priceText === "7,623.41") landed = service.now - bell
      })
      var asked = harness.quoteCounts(harness.requests().slice(from))
      harness.check("at the open no row and no hero says As of while the session's first price is on its way, asked again within 15 s, and both rows have it by 09:30:30",
        said.length === 0 && landed > 0 && landed <= 30,
        (said.length ? said.slice(0, 4).join(" | ") : "nothing said") + "; landed " + (landed ? landed + " s on" : "never")
          + "; asked " + harness.listed.map(function(s) { return s + " " + asked[s] }).join(", "))
      var postAsks = dayAsks().slice(bellAsks)
      var aaplPre = preAsks.filter(function(l) { return / AAPL /.test(l) })
      harness.check("before the bell AAPL's day is asked for two days, the index's for one; from the bell every day for one",
        aaplPre.length > 0 && aaplPre.every(function(l) { return / 2d$/.test(l) })
          && preAsks.filter(function(l) { return /%5EGSPC/.test(l) }).every(function(l) { return / 1d$/.test(l) })
          && postAsks.length > 0 && postAsks.every(function(l) { return / 1d$/.test(l) }),
        "before: " + preAsks.join(" / ") + "; after: " + postAsks.join(" / "))
      closeWindow()
      harness.finish()
    }
  }

  // Calls `each` on every frame while running: what the screen says, read as
  // each frame is made.
  FrameAnimation {
    id: frames
    property var each: null
    onTriggered: if (each) each()
  }

  HarnessExit { id: done }
}
