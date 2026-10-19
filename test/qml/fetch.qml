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
// in requests.log and every curl call in runs.log. fetch.sh runs this twice:
// the main run, which starts offline with saved quotes, and the holiday
// run (STONKS_FETCH_RUN=holiday), whose calendars close New York on 7
// October while London and Toronto trade.
ShellRoot {
  id: harness

  property int failures: 0
  readonly property string mode: Quickshell.env("STONKS_FETCH_RUN") || "main"
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")
  readonly property var listed: ["NEST", "KILN", "SPY", "^GSPC", "BTC-USD", "SHEL.L", "7203.T", "SHOP.TO"]
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
    console.log(harness.mode === "main" ? "FETCH DONE" : "FETCH HOLIDAY DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  // The plugin as the shell composes it, with this harness as its shell.
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

  // A screen as Hyprland reports it, for the window host (fetch.sh): on or
  // off, as it says when asked again, a turn later, as Hyprland's answer
  // comes. It counts the asks it has not answered yet (`screensHeard`).
  QtObject {
    id: screenStandIn
    property bool on: true
    property var lastIpcObject: ({ dpmsStatus: true })
    property int unanswered: 0
    function refresh() {
      unanswered++
      Qt.callLater(function() {
        screenStandIn.lastIpcObject = { dpmsStatus: screenStandIn.on }
        screenStandIn.unanswered--
      })
    }
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

    // Every ask of the screens answered. A step waits on this before it
    // counts what went while they were off, and before it turns one on, so
    // an answer still out, as on a loaded machine, can't report the next
    // state for the last one. The service trusts an answer for a second of
    // the wall clock (`screensClear`), so a step that needs it asked afresh
    // still waits that long first.
    function screensHeard() {
      tryVerify(function() { return screenStandIn.unanswered === 0 }, 5000)
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
        harness.listed.forEach(function(s) {
          var row = body.watchlist.rowItem(s)
          if (row && (/^!/.test(row.detail) || /^As of/.test(row.detail))) out.push(s + ": " + row.detail)
        })
      }
      return out
    }

    // Requests per listing in the window from `begin` (which sets the clock
    // to the window's start, or opens the window there) to `seconds` later,
    // its start in and its end out, against `want`. A symbol asked for on a
    // period may land a tick either side of the window's edge, so a count
    // may be one off; one expected never to be asked must not be at all.
    function countsOver(label, seconds, want, begin) {
      var from = harness.requests().length
      begin()
      tick(seconds - 5)
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
      if (harness.mode !== "main") skip("the holiday run")
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
      var lateNotes = [pill.warns, nestRow.detail, body.watchlist.rowItem("SHOP.TO").detail].join(" | ")
      harness.check("90 s asked and unanswered: the pill warns, a saved row says its update is overdue, as of Tuesday, and a row with nothing saved says No data",
        /^true \| ! Update overdue · as of Tue \d\d:\d\d \| ! No data$/.test(lateNotes), lateNotes)
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

      // 11:00, the regular session: the rows stay warm with nothing open.
      countsOver("11:00, nothing open: every stock, ETF, and index in its session every minute; the crypto and Tokyo not at all",
        900, counts([15, 15, 15, 15, 0, 15, 0, 15]), startAt(at(harness.wed7, 11, 0)))
      // F2 and F4: an open finds the rows fresh; it asks only for what is
      // stale, in one run, and shows no warning and no "As of" on any frame.
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
      body.selectRange("1D")
      harness.check("a range picked while Yahoo refuses says it is unavailable at once, not Loading", rangeHeader === "1W unavailable", rangeHeader)
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
      // refresh; a removal and its undo fetch nothing.
      runsBefore = harness.runs().length
      service.addSymbol("MSFT")
      tryVerify(function() { return !!service.quotes.MSFT && idle() }, 5000)
      harness.check("an add's first answer goes at once, in a run of its own", harness.runs()[runsBefore] === "chart:MSFT", harness.runs().slice(runsBefore).join(" / "))
      var undoFrom = harness.requests().length
      service.removeSymbol("KILN")
      service.undoRemoval("KILN")
      settle()
      harness.check("a removal and its undo fetch nothing", harness.quoteCounts(harness.requests().slice(undoFrom)).KILN === 0 && !!service.quotes.KILN,
        harness.requests().slice(undoFrom).join(", "))
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
      openWindow()
      app.testBody.selectRange("1W")
      tryVerify(function() { return !!service.histories["NEST|1W"] && service.histories["NEST|1W"].status === "ok" }, 5000)
      settle()
      screenStandIn.on = false
      wait(1100)
      var historyFrom = Number(harness.record("NEST.history.calls") || 0)
      service.refresh()
      screensHeard()
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
      harness.check("a refresh while every screen is off asks the range's history once a screen is on, not before",
        darkHistory === 0 && litHistory === 1, darkHistory + " while off, " + litHistory + " after")

      // Saturday noon, half an hour each.
      countsOver("Saturday noon, nothing open: the pill's symbol every 15 minutes, nothing else",
        1800, counts([2, 0, 0, 0, 0, 0, 0, 0]), startAt(at(harness.sat10, 12, 0)))
      countsOver("Saturday 12:30, the window open: the crypto every minute, the rest every 15",
        1800, counts([2, 2, 2, 2, 30, 2, 2, 2]), openAfter)
      closeWindow()

      harness.finish()
    }

    // New York closed for a holiday while London and Toronto trade.
    function test_holiday() {
      if (harness.mode !== "holiday") skip("the main run")
      tryVerify(function() { return harness.listed.every(function(s) { return !!service.quotes[s] }) && idle() }, 10000)
      // The index is on the US calendar, so the holiday closes it too,
      // whatever Yahoo's periods (a trading day's here) say.
      countsOver("a US holiday, nothing open: the pill's symbol every 15 minutes; London and Toronto, trading, every minute",
        900, counts([1, 0, 0, 0, 0, 15, 0, 15]), startAt(at(harness.wed7, 11, 0)))
      countsOver("a US holiday, the window open: New York every 15 minutes, London, Toronto, and the crypto every minute",
        900, counts([1, 1, 1, 1, 15, 15, 1, 15]), openAfter)
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
