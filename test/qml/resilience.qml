import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

ShellRoot {
  id: root
  property int failures: 0
  property int saveFailures: 0
  property int snapshotEnd: 0
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
    target: service.testFundamentals
    function onTestCommandChanged() {
      var feed = service.testFundamentals
      if (!feed.job || feed.job.figures) return
      var end = /period2=(\d+)/.exec(feed.testCommand.join(" "))
      if (end) root.snapshotEnd = Number(end[1])
    }
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
      service.testFundamentals.clockOffset = 0
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

    // A save that doesn't land is said in the window's footer until one
    // does; a real click tries again, and so does any change. Both ways a
    // save is lost: a folder Stonks can't write in, which Quickshell
    // reports, and a full disk, which it reports as saved, so only reading
    // the file back catches it (the folder is a 64 KB tmpfs, resilience.sh).
    function test_1_saveFailure() { guarded("test_1_saveFailure", checks_test_1_saveFailure) }
    function checks_test_1_saveFailure() {
      quiet()
      service.persist({ changeMode: "pct" })
      app.open("{}")
      awaitState(function() { return !!app.testBody }, 3000)
      var body = app.testBody
      var footer = root.find(body, "footer")
      waitForRendering(footer)
      var said = function() { return String(root.find(footer, "footerText").text) + String(root.find(footer, "footerAction").text) }
      var click = function() { mouseClick(footer, footer.width / 2, footer.height / 2) }
      var unsaved = "Your changes aren't saved · click to try again"
      var still = "Still not saved · your disk may be full"
      var holds = function(name, symbol) {
        var list = function(lists) { return (lists || []).filter(function(l) { return l.name === name })[0] }
        var file = null
        try { file = JSON.parse(root.read(service.dataPath)) } catch (e) {}
        return { memory: !!list(service.lists) && list(service.lists).symbols.indexOf(symbol) >= 0,
          file: !!file && !!list(file.lists) && list(file.lists).symbols.indexOf(symbol) >= 0 }
      }

      var before = root.read(service.dataPath)
      var failed = root.saveFailures
      var dir = service.dataPath.slice(0, service.dataPath.lastIndexOf("/"))
      try {
        run(["chmod", "u-w", dir])
        service.createList("Keep")
        service.setMembership("BTC-USD", "Keep", true)
        awaitState(function() { return root.saveFailures === failed + 2 && said() === unsaved }, 3000)
        click()
        awaitState(function() { return root.saveFailures === failed + 3 }, 3000)
        var stillSaid = within(3000, function() { return said() === still })
        root.check("a save into a folder Stonks can't write in is said in the footer, a click that still can't says so, and the change stays in memory, the file as it was",
          stillSaid && root.read(service.dataPath) === before && holds("Keep", "BTC-USD").memory,
          said() + " | save failures " + (root.saveFailures - failed))
      } finally { run(["chmod", "u+w", dir]) }
      click()
      var landed = within(3000, function() { return holds("Keep", "BTC-USD").file && said().indexOf("+  Add a symbol") === 0 })
      root.check("once the folder can be written, a click saves every change, and the footer is the add again", landed, said())
      // All, so the row stays as the next change takes it from Keep.
      service.switchList("")

      var fill = dir + "/fill"
      run(["sh", "-c", "cat /dev/zero > \"$1\" 2> /dev/null; test -s \"$1\"", "_", fill])
      before = root.read(service.dataPath)
      failed = root.saveFailures
      service.setMembership("BTC-USD", "Keep", false)
      var caught = within(3000, function() { return said() === unsaved })
      click()
      var stillFull = within(3000, function() { return said() === still })
      root.check("a full disk, which Quickshell reports as saved, is caught by reading the file back and said, and a click says it still isn't saved",
        caught && stillFull && root.saveFailures === failed && root.read(service.dataPath) === before && !holds("Keep", "BTC-USD").memory,
        said() + " | reported failures " + (root.saveFailures - failed))
      run(["rm", "-f", fill])
      app.testKeys.forceActiveFocus()
      awaitState(function() { return app.testKeys.activeFocus }, 2000)
      keyClick("c")
      var keyed = within(3000, function() {
        var file = null
        try { file = JSON.parse(root.read(service.dataPath)) } catch (e) {}
        return !!file && file.changeMode === service.changeMode && !holds("Keep", "BTC-USD").file && said().indexOf("+  Add a symbol") === 0
      })
      root.check("with room again, a change by key saves it and every change before it, and the footer is the add again", keyed, said())
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
      var pendingHeld = within(5000, function() { return history.waitingForScreen || root.calls("AAPL.history") > count })
      root.check("dark pending history sends nothing and retains only the current range", pendingHeld && root.calls("AAPL.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 5000)
      root.check("wake sends the current held range once", root.calls("AAPL.history") === count + 1 && history.entries["AAPL|2Y"].status === "ok" && !history.entries["AAPL|1Y"])
      // Screens on, but their answer is stale: a new chart waits for the
      // asynchronous answer, then arrives with no other user action.
      screens.answering = true
      service.screensAnsweredMs = 0
      count = root.calls("MSFT.history")
      history.request("MSFT", "1Y", true)
      var screenHeld = within(5000, function() { return history.waitingForScreen || root.calls("MSFT.history") > count })
      root.check("history waits for a current screen answer", screenHeld && root.calls("MSFT.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 5000)
      root.check("a fresh on-screen answer releases the held hero", root.calls("MSFT.history") === count + 1 && history.entries["MSFT|1Y"].status === "ok")
      // A failed answer starts its retry pause while lit, then darkness
      // reaches the retry. The wake must run the still-wanted retry.
      history.request("FAIL", "1Y", true)
      awaitState(function() { return root.calls("FAIL.history") >= 1 }, 3000)
      screens.screensOff = true
      count = root.calls("FAIL.history")
      var retryHeld = within(5000, function() { return history.waitingForScreen || root.calls("FAIL.history") > count })
      root.check("a pending history retry starts no request in darkness", retryHeld && root.calls("FAIL.history") === count)
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
      var chainHeld = within(5000, function() { return history.waitingForScreen || root.calls("MSFT.history") > count })
      root.check("an answer landing in darkness starts no next chart", chainHeld && root.calls("MSFT.history") === count)
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
      var rangeHeld = within(5000, function() { return history.waitingForScreen || root.calls("BTC-USD.history") > count })
      root.check("a shared range change and host reopening in darkness start no history",
        rangeHeld && history.waitingForScreen && history.holds(history.job, "BTC-USD|10Y") && !history.job.ahead
          && root.calls("BTC-USD.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 4000)
      root.check("wake fetches the shared range's current hero", root.calls("BTC-USD.history") === count + 1 && history.entries["BTC-USD|10Y"].status === "ok")
      service.setRange("1D")
      service.surfaceShown(root, false)
      service.screens = null
    }

    function test_4_fundamentalsAndSearchDarkness() { guarded("test_4_fundamentalsAndSearchDarkness", checks_test_4_fundamentalsAndSearchDarkness) }
    function checks_test_4_fundamentalsAndSearchDarkness() {
      // Members of All: a cap and P/E is kept only for All, the preview,
      // and a removal on offer (`Service.forgetLeft`), pruned each minute.
      // Asked for outside All, AAPL's was pruned before the check when the
      // minute turned in between, which a loaded run made likely.
      service.persist({ symbols: ["BTC-USD", "AAPL", "MSFT"] })
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
      var searchHeld = within(5000, function() {
        return (service.testFundamentals.pendingUrl !== "" && body.search.requestedQuery === "ZZZ")
          || root.calls("SEARCH.asked") > searches || root.calls("FUNDAMENTALS") > before
      })
      root.check("dark fundamentals and a first search start no HTTP request",
        searchHeld && root.calls("FUNDAMENTALS") === before && root.calls("SEARCH.asked") === searches)
      var queuedEnd = Number(/period2=(\d+)/.exec(service.testFundamentals.pendingUrl)[1])
      service.testFundamentals.clockOffset = 24 * 60 * 60
      wake()
      awaitState(function() { return body.search.resultsQuery === "ZZZ" && !service.testFundamentals.busy }, 6000)
      root.check("wake resumes both pending search and fundamentals", root.calls("SEARCH.asked") === searches + 1
        && root.calls("FUNDAMENTALS") === before + 2 && service.fundamentals.AAPL.status === "ok")
      root.check("a fundamentals snapshot held overnight ends at wake, not at the earlier ask",
        root.snapshotEnd >= queuedEnd + 24 * 60 * 60, queuedEnd + " queued, " + root.snapshotEnd + " sent")
      service.testFundamentals.clockOffset = 0
      body.cancelAdding()
      // Hold the snapshot answer, turn the screens off, then let it land.
      // Its closes are a separate command and must not start in darkness.
      flag("FUNDAMENTALS.hold", true)
      before = root.calls("FUNDAMENTALS")
      service.testFundamentals.fetch("MSFT")
      awaitState(function() { return root.calls("FUNDAMENTALS") === before + 1 }, 3000)
      screens.screensOff = true
      flag("FUNDAMENTALS.hold", false)
      var closesHeld = within(5000, function() { return service.testFundamentals.pendingUrl !== "" || root.calls("FUNDAMENTALS") > before + 1 })
      root.check("a fundamentals snapshot landing in darkness starts no closes request", closesHeld && root.calls("FUNDAMENTALS") === before + 1)
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
