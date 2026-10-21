import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

ShellRoot {
  id: root
  property int failures: 0
  property int saveFailures: 0
  property bool chainHistory: false
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")
  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (detail === undefined ? "" : " — " + detail))
    if (!ok) failures++
  }
  function read(path) {
    var v = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', root)
    v.path = path
    var text = String(v.text() || "")
    v.destroy()
    return text
  }
  function calls(name) { return Number(read(state + "/" + name + ".calls") || 0) }
  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var got = find(item.children[i], name)
      if (got) return got
    }
    return item.contentItem ? find(item.contentItem, name) : null
  }
  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }
  Stonks.OvernightFeed { id: nights }
  Connections {
    target: service.testDataFile
    function onSaveFailed(error) { root.saveFailures++ }
  }
  Connections {
    target: service.testHistory
    function onEntriesChanged() {
      if (!root.chainHistory) return
      root.chainHistory = false
      service.testHistory.request("MSFT", "5Y", true)
    }
  }
  QtObject {
    id: screens
    property bool screensOff: false
    property bool answering: false
    signal screensAnswered()
    function askScreens() { if (!answering) screenAnswer.restart(); return true }
  }
  Timer { id: screenAnswer; interval: 0; onTriggered: screens.screensAnswered() }
  Process {
    id: command
    property int result: -1
    onExited: function(exitCode, exitStatus) { result = exitCode }
  }
  HarnessExit { id: done }

  TestCase {
    name: "Resilience"
    when: service.pluginsReady
    function cleanup() {
      root.chainHistory = false
      ;["AAPL.history.hold", "FUNDAMENTALS.hold", "SLOW.quote.hold", "LATE.quote.hold", "LATE.down", "OVERNIGHT.malformed"].forEach(function(name) { flag(name, false) })
      screens.screensOff = false
      screens.answering = false
      service.screens = null
      service.clockOffset = 0
      service.tick()
      service.surfaceShown(root, false)
      service.setRange("1D")
      if (app.opened) { app.testBody.cancelAdding(); app.close() }
      service.testHistory.clear()
      service.testFundamentals.pump()
      service.persist({symbols:["BTC-USD"],featured:"BTC-USD",lists:[],list:"",range:"1D"})
    }
    function guarded(label, fn) {
      try { fn() } catch (e) { root.check(label, false, String(e) + " " + e.stack) }
    }
    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 20) wait(20)
      return fn()
    }
    function awaitState(fn, ms) {
      var ok = within(ms || 5000, fn)
      if (!ok) root.check("awaited state " + fn.toString(), false,
        "feed " + service.testFeed.busy + " history " + service.testHistory.busy + " fundamentals " + service.testFundamentals.busy)
      verify(ok)
    }
    function run(args) {
      command.result = -1
      command.command = args
      command.running = true
      awaitState(function() { return command.result !== -1 }, 3000)
      compare(command.result, 0, args.join(" "))
    }
    function flag(name, on) { run(on ? ["touch", root.state + "/" + name] : ["rm", "-f", root.state + "/" + name]) }
    function quiet() { awaitState(function() { return !service.testFeed.busy && !service.testHistory.busy && !service.testFundamentals.busy }, 8000) }
    function wake() {
      screens.screensOff = false
      screens.answering = false
      screens.screensAnswered()
    }

    function test_1_saveFailure() { guarded("test_1_saveFailure", checks_test_1_saveFailure) }
    function checks_test_1_saveFailure() {
      quiet()
      service.persist({ changeMode: "pct" })
      var before = root.read(service.dataPath)
      var failed = root.saveFailures
      var dir = service.dataPath.slice(0, service.dataPath.lastIndexOf("/"))
      try {
        run(["chmod", "u-w", dir])
        service.createList("Keep")
        service.setMembership("BTC-USD", "Keep", true)
        awaitState(function() { return root.saveFailures > failed }, 3000)
        root.check("failed atomic save keeps the last readable bytes and the edits in memory",
          root.read(service.dataPath) === before && service.lists.some(function(l) { return l.name === "Keep" && l.symbols.indexOf("BTC-USD") >= 0 }),
          "save failures " + (root.saveFailures - failed))
      } finally { run(["chmod", "u+w", dir]) }
      // There is no promised visible save-error message or automatic retry.
      // A next change must save all the earlier edits as well as itself.
      service.persist({ changeMode: "abs" })
      var saved = function() {
        try {
          var file = JSON.parse(root.read(service.dataPath))
          return file.changeMode === "abs" && file.lists.some(function(l) { return l.name === "Keep" && l.symbols.indexOf("BTC-USD") >= 0 })
        } catch (e) { return false }
      }
      awaitState(saved, 3000)
      root.check("the next successful save includes edits made during the failed save", saved())
      service.switchList("")
    }

    function test_2_closedDeadlineAndClockSteps() { guarded("test_2_closedDeadlineAndClockSteps", checks_test_2_closedDeadlineAndClockSteps) }
    function checks_test_2_closedDeadlineAndClockSteps() {
      if (app.testBody) app.close()
      quiet()
      var feed = service.testFeed
      var entries = Object.assign({}, feed.entries)
      entries["BTC-USD"] = Object.assign({}, entries["BTC-USD"], { answeredAt: service.wallSecond() - 58 })
      var before = root.calls("BTC-USD")
      feed.entries = entries
      service.askDue()
      var woke = within(6000, function() { return root.calls("BTC-USD") > before })
      root.check("a real deadline refreshes a quote with every surface closed", woke && service.openSurfaces.length === 0)
      quiet()
      before = root.calls("BTC-USD")
      service.clockOffset = -3600
      service.tick()
      var backward = within(4000, function() { return root.calls("BTC-USD") > before && !feed.busy })
      root.check("a backward clock step refreshes instead of waiting for a future receipt",
        backward && feed.entries["BTC-USD"].receivedAt <= service.wallSecond())
      before = root.calls("BTC-USD")
      service.clockOffset = 7200
      service.tick()
      var resumed = within(4000, function() { return root.calls("BTC-USD") > before && !feed.busy })
      root.check("a forward clock step after suspension fetches the overdue quote", resumed)
      service.clockOffset = 0
      service.tick()
      quiet()
    }

    function test_3_historyDarknessAndWake() { guarded("test_3_historyDarknessAndWake", checks_test_3_historyDarknessAndWake) }
    function checks_test_3_historyDarknessAndWake() {
      service.screens = screens
      screens.screensOff = true
      service.screensAnsweredMs = 0
      var history = service.testHistory
      var count = root.calls("AAPL.history")
      history.request("AAPL", "1Y", true)
      history.request("AAPL", "2Y", true)
      wait(300)
      root.check("dark pending history sends nothing and retains only the current range", root.calls("AAPL.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 5000)
      root.check("wake sends the current held range once", root.calls("AAPL.history") === count + 1 && history.entries["AAPL|2Y"].status === "ok" && !history.entries["AAPL|1Y"])
      // Screens on, but their answer is stale: a new chart waits for the
      // asynchronous answer, then arrives with no other user action.
      screens.answering = true
      service.screensAnsweredMs = 0
      count = root.calls("MSFT.history")
      history.request("MSFT", "1Y", true)
      wait(100)
      root.check("history waits for a current screen answer", root.calls("MSFT.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 5000)
      root.check("a fresh on-screen answer releases the held hero", root.calls("MSFT.history") === count + 1 && history.entries["MSFT|1Y"].status === "ok")
      // A failed answer starts its retry pause while lit, then darkness
      // reaches the retry. The wake must run the still-wanted retry.
      history.request("FAIL", "1Y", true)
      awaitState(function() { return root.calls("FAIL.history") >= 1 }, 3000)
      screens.screensOff = true
      count = root.calls("FAIL.history")
      wait(2800)
      root.check("a pending history retry starts no request in darkness", root.calls("FAIL.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 5000)
      root.check("the pending retry runs once after wake", root.calls("FAIL.history") === count + 1 && history.entries["FAIL|1Y"].status === "failed")
      // An answer already in flight may land while dark; starting the
      // next wanted chart must still wait for a screen.
      flag("AAPL.history.hold", true)
      count = root.calls("AAPL.history")
      history.request("AAPL", "6M", true)
      awaitState(function() { return root.calls("AAPL.history") > count }, 3000)
      screens.screensOff = true
      count = root.calls("MSFT.history")
      root.chainHistory = true
      flag("AAPL.history.hold", false)
      awaitState(function() { return !root.chainHistory }, 3000)
      wait(200)
      root.check("an answer landing in darkness starts no next chart", root.calls("MSFT.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 4000)
      root.check("the chained chart resumes once after wake", root.calls("MSFT.history") === count + 1 && history.entries["MSFT|5Y"].status === "ok")
      service.surfaceShown(root, true)
      screens.screensOff = true
      count = root.calls("BTC-USD.history")
      // The shared range can change from another surface or IPC while dark.
      service.setRange("10Y")
      service.testGate.pause = "none"
      service.testGate.report(["ok"], 0, service.testGate.ticket)
      wait(200)
      root.check("a shared range change and host reopening in darkness start no history", root.calls("BTC-USD.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 4000)
      root.check("wake fetches the shared range's current hero", root.calls("BTC-USD.history") === count + 1 && history.entries["BTC-USD|10Y"].status === "ok")
      service.setRange("1D")
      service.surfaceShown(root, false)
      service.screens = null
    }

    function test_4_fundamentalsAndSearchDarkness() { guarded("test_4_fundamentalsAndSearchDarkness", checks_test_4_fundamentalsAndSearchDarkness) }
    function checks_test_4_fundamentalsAndSearchDarkness() {
      quiet()
      service.screens = screens
      screens.screensOff = true
      service.screensAnsweredMs = Date.now()
      var before = root.calls("FUNDAMENTALS")
      service.testFundamentals.fetch("AAPL")
      app.open("{}")
      awaitState(function() { return !!app.testBody }, 3000)
      var body = app.testBody
      app.testKeys.forceActiveFocus()
      awaitState(function() { return app.testKeys.activeFocus }, 2000)
      waitForRendering(app.testKeys)
      keyClick(Qt.Key_A)
      awaitState(function() { return body.search.active }, 3000)
      var searches = root.calls("SEARCH.asked")
      keyClick("Z"); keyClick("Z"); keyClick("Z")
      wait(400)
      root.check("dark fundamentals and a first search start no HTTP request",
        root.calls("FUNDAMENTALS") === before && root.calls("SEARCH.asked") === searches)
      wake()
      awaitState(function() { return body.search.resultsQuery === "ZZZ" && !service.testFundamentals.busy }, 6000)
      root.check("wake resumes both pending search and fundamentals", root.calls("SEARCH.asked") === searches + 1
        && root.calls("FUNDAMENTALS") === before + 2 && service.fundamentals.AAPL.status === "ok")
      body.cancelAdding()
      // Hold the snapshot answer, turn the screens off, then let it land.
      // Its closes are a separate command and must not start in darkness.
      flag("FUNDAMENTALS.hold", true)
      before = root.calls("FUNDAMENTALS")
      service.testFundamentals.fetch("MSFT")
      awaitState(function() { return root.calls("FUNDAMENTALS") === before + 1 }, 3000)
      screens.screensOff = true
      flag("FUNDAMENTALS.hold", false)
      wait(300)
      root.check("a fundamentals snapshot landing in darkness starts no closes request", root.calls("FUNDAMENTALS") === before + 1)
      wake()
      awaitState(function() { return !service.testFundamentals.busy }, 4000)
      root.check("wake sends the held fundamentals closes once", root.calls("FUNDAMENTALS") === before + 2 && service.fundamentals.MSFT.status === "ok")
      app.close()
      service.screens = null
    }

    function test_5_malformedOvernightRecovers() { guarded("test_5_malformedOvernightRecovers", checks_test_5_malformedOvernightRecovers) }
    function checks_test_5_malformedOvernightRecovers() {
      flag("OVERNIGHT.malformed", true)
      nights.entries = { NEST: {status:"ok",bars:[{t:1,o:2,c:3}],at:1} }
      nights.fetch(["NEST", "KILN"], 2)
      var settled = within(3000, function() { return !nights.busy })
      root.check("a malformed overnight listing settles the failed batch and preserves last good prints",
        settled && nights.entries.NEST.status === "failed" && nights.entries.NEST.bars[0].c === 3 && nights.entries.NEST.bars[0].t === 1 && nights.entries.KILN.status === "failed")
      if (!settled) { flag("OVERNIGHT.malformed", false); return }
      flag("OVERNIGHT.malformed", false)
      nights.fetch(["NEST", "KILN"], 3)
      awaitState(function() { return !nights.busy }, 3000)
      root.check("the next valid overnight answer succeeds after a malformed listing",
        nights.entries.NEST.status === "ok" && nights.entries.KILN.status === "ok" && nights.entries.NEST.at === 3)
    }

    function test_6_pendingDayAdds() { guarded("test_6_pendingDayAdds", checks_test_6_pendingDayAdds) }
    function checks_test_6_pendingDayAdds() {
      app.open("{}")
      awaitState(function() { return !!app.testBody }, 3000)
      var body = app.testBody
      service.setRange("1D")
      var attempt = function(query, symbol, mouse, fail) {
        service.feature("BTC-USD")
        flag(symbol + ".quote.hold", true)
        if (fail) flag(symbol + ".down", true)
        app.testKeys.forceActiveFocus()
        keyClick(Qt.Key_A)
        awaitState(function() { return body.search.active }, 2000)
        for (var i = 0; i < query.length; i++) keyClick(query[i])
        awaitState(function() { return body.search.resultsQuery === query && body.search.results[0].symbol === symbol }, 4000)
        awaitState(function() { return root.calls(symbol) > 0 }, 4000)
        root.check("held 1D preview names " + symbol, body.featuredSymbol === symbol && body.headerText === "Loading " + symbol && body.chartLoading)
        if (mouse) {
          var row = root.find(body.search, "searchResult")
          mouseClick(row, row.width / 2, row.height / 2)
        } else keyClick(Qt.Key_Return)
        root.check((mouse ? "click" : "Enter") + " keeps the accepted 1D symbol named while its answer is held",
          !body.adding && body.featuredSymbol === symbol && body.headerText === "Loading " + symbol && body.chartLoading && service.library.indexOf(symbol) >= 0)
        // Selecting a real row while the accepted add is pending takes
        // precedence; the late add must not replace that selected hero.
        if (!mouse) {
          app.testKeys.forceActiveFocus()
          keyClick("1")
          root.check("a number key selects its displayed row over a pending add", service.featuredSymbol === body.watchlist.displayedSymbols[0])
        }
        flag(symbol + ".quote.hold", false)
        awaitState(function() { return service.arriving.indexOf(symbol) < 0 }, 7000)
        root.check(fail ? "failed 1D add falls back truthfully" : "successful 1D add keeps the later key selection",
          fail ? service.entries[symbol].status === "failed" && body.chartSymbol === "BTC-USD" : !!service.quotes[symbol] && service.featuredSymbol === "BTC-USD")
        if (fail) flag(symbol + ".down", false)
      }
      attempt("HELD", "SLOW", false, false)
      attempt("HELDFAIL", "LATE", true, true)
      app.close()
    }

    function cleanupTestCase() {
      run(["chmod", "u+w", service.dataPath.slice(0, service.dataPath.lastIndexOf("/"))])
      console.log("RESILIENCE DONE")
      done.exitCode = root.failures ? 1 : 0
      done.start()
    }
  }
}
