import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

Harness {
  id: harness
  marker: "RESILIENCE DONE"
  property int saveFailures: 0
  property int snapshotEnd: 0
  property bool chainHistory: false
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")
  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }
  Stonks.OvernightFeed { id: nights }
  Connections {
    target: service.testDataFile
    function onSaveFailed(error) { harness.saveFailures++ }
  }
  Connections {
    target: service.testFundamentals
    function onTestCommandChanged() {
      var feed = service.testFundamentals
      if (!feed.job || feed.job.figures) return
      var end = /period2=(\d+)/.exec(feed.testCommand.join(" "))
      if (end) harness.snapshotEnd = Number(end[1])
    }
  }
  Connections {
    target: service.testHistory
    function onEntriesChanged() {
      if (!harness.chainHistory) return
      harness.chainHistory = false
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

  Steps {
    name: "Resilience"
    when: service.pluginsReady
    function cleanup() {
      harness.chainHistory = false
      ;["AAPL.history.hold", "FUNDAMENTALS.hold", "OVERNIGHT.malformed"].forEach(function(name) { flag(name, false) })
      screens.screensOff = false
      screens.answering = false
      service.screens = null
      service.clockOffset = 0
      service.tick()
      service.surfaceShown(harness, false)
      service.setRange("1D")
      if (app.opened) { app.testBody.cancelAdding(); app.close() }
      service.testHistory.clear()
      service.testFundamentals.pump()
      service.persist({symbols:["BTC-USD"],featured:"BTC-USD",lists:[],list:"",range:"1D"})
    }
    function guarded(label, fn) {
      try { fn() } catch (e) { check(label, false, String(e) + " " + e.stack) }
    }
    function awaitState(fn, ms) {
      var ok = within(ms || 5000, fn)
      if (!ok) check("awaited state " + fn.toString(), false,
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
    function flag(name, on) { run(on ? ["touch", harness.state + "/" + name] : ["rm", "-f", harness.state + "/" + name]) }
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
      var footer = find(body, "footer")
      waitForRendering(footer)
      var said = function() { return String(find(footer, "footerText").text) + String(find(footer, "footerAction").text) }
      var click = function() { mouseClick(footer, footer.width / 2, footer.height / 2) }
      var unsaved = "Your changes aren't saved · click to try again"
      var still = "Still not saved · your disk may be full"
      var holds = function(name, symbol) {
        var list = function(lists) { return (lists || []).filter(function(l) { return l.name === name })[0] }
        var file = null
        try { file = JSON.parse(readFile(service.dataPath)) } catch (e) {}
        return { memory: !!list(service.lists) && list(service.lists).symbols.indexOf(symbol) >= 0,
          file: !!file && !!list(file.lists) && list(file.lists).symbols.indexOf(symbol) >= 0 }
      }

      var before = readFile(service.dataPath)
      var failed = harness.saveFailures
      var dir = service.dataPath.slice(0, service.dataPath.lastIndexOf("/"))
      try {
        run(["chmod", "u-w", dir])
        service.createList("Keep")
        service.setMembership("BTC-USD", "Keep", true)
        awaitState(function() { return harness.saveFailures === failed + 2 && said() === unsaved }, 3000)
        click()
        awaitState(function() { return harness.saveFailures === failed + 3 }, 3000)
        var stillSaid = within(3000, function() { return said() === still })
        check("a save into a folder Stonks can't write in is said in the footer, a click that still can't says so, and the change stays in memory, the file as it was",
          stillSaid && readFile(service.dataPath) === before && holds("Keep", "BTC-USD").memory,
          said() + " | save failures " + (harness.saveFailures - failed))
      } finally { run(["chmod", "u+w", dir]) }
      click()
      var landed = within(3000, function() { return holds("Keep", "BTC-USD").file && said().indexOf("+  Add a symbol") === 0 })
      check("once the folder can be written, a click saves every change, and the footer is the add again", landed, said())
      // All, so the row stays as the next change takes it from Keep.
      service.switchList("")

      var fill = dir + "/fill"
      run(["sh", "-c", "cat /dev/zero > \"$1\" 2> /dev/null; test -s \"$1\"", "_", fill])
      before = readFile(service.dataPath)
      failed = harness.saveFailures
      service.setMembership("BTC-USD", "Keep", false)
      var caught = within(3000, function() { return said() === unsaved })
      click()
      var stillFull = within(3000, function() { return said() === still })
      check("a full disk, which Quickshell reports as saved, is caught by reading the file back and said, and a click says it still isn't saved",
        caught && stillFull && harness.saveFailures === failed && readFile(service.dataPath) === before && !holds("Keep", "BTC-USD").memory,
        said() + " | reported failures " + (harness.saveFailures - failed))
      run(["rm", "-f", fill])
      service.switchList("")
    }

    function test_2_closedDeadlineAndClockSteps() { guarded("test_2_closedDeadlineAndClockSteps", checks_test_2_closedDeadlineAndClockSteps) }
    function checks_test_2_closedDeadlineAndClockSteps() {
      if (app.testBody) app.close()
      quiet()
      var feed = service.testFeed
      var entries = Object.assign({}, feed.entries)
      entries["BTC-USD"] = Object.assign({}, entries["BTC-USD"], { answeredAt: service.wallSecond() - 58 })
      var before = calls("BTC-USD")
      feed.entries = entries
      service.askDue()
      var woke = within(6000, function() { return calls("BTC-USD") > before })
      check("a real deadline refreshes a quote with every surface closed", woke && service.openSurfaces.length === 0)
      quiet()
      before = calls("BTC-USD")
      service.clockOffset = -3600
      service.tick()
      var backward = within(4000, function() { return calls("BTC-USD") > before && !feed.busy })
      check("a backward clock step refreshes instead of waiting for a future receipt",
        backward && feed.entries["BTC-USD"].receivedAt <= service.wallSecond())
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
      var count = calls("AAPL.history")
      history.request("AAPL", "1Y", true)
      history.request("AAPL", "2Y", true)
      var pendingHeld = within(5000, function() { return history.waitingForScreen || calls("AAPL.history") > count })
      check("dark pending history sends nothing and retains only the current range", pendingHeld && calls("AAPL.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 5000)
      check("wake sends the current held range once", calls("AAPL.history") === count + 1 && history.entries["AAPL|2Y"].status === "ok" && !history.entries["AAPL|1Y"])
      // Screens on, but their answer is stale.
      screens.answering = true
      service.screensAnsweredMs = 0
      count = calls("MSFT.history")
      history.request("MSFT", "1Y", true)
      var screenHeld = within(5000, function() { return history.waitingForScreen || calls("MSFT.history") > count })
      check("history waits for a current screen answer", screenHeld && calls("MSFT.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 5000)
      check("a fresh on-screen answer releases the held hero", calls("MSFT.history") === count + 1 && history.entries["MSFT|1Y"].status === "ok")
      // A retry pause that starts while lit and ends in the dark.
      history.request("FAIL", "1Y", true)
      awaitState(function() { return calls("FAIL.history") >= 1 }, 3000)
      screens.screensOff = true
      count = calls("FAIL.history")
      var retryHeld = within(5000, function() { return history.waitingForScreen || calls("FAIL.history") > count })
      check("a pending history retry starts no request in darkness", retryHeld && calls("FAIL.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 5000)
      check("the pending retry runs once after wake", calls("FAIL.history") === count + 1 && history.entries["FAIL|1Y"].status === "failed")
      // An answer already in flight lands in the dark.
      flag("AAPL.history.hold", true)
      count = calls("AAPL.history")
      history.request("AAPL", "6M", true)
      awaitState(function() { return calls("AAPL.history") > count }, 3000)
      screens.screensOff = true
      count = calls("MSFT.history")
      harness.chainHistory = true
      flag("AAPL.history.hold", false)
      awaitState(function() { return !harness.chainHistory }, 3000)
      var chainHeld = within(5000, function() { return history.waitingForScreen || calls("MSFT.history") > count })
      check("an answer landing in darkness starts no next chart", chainHeld && calls("MSFT.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 4000)
      check("the chained chart resumes once after wake", calls("MSFT.history") === count + 1 && history.entries["MSFT|5Y"].status === "ok")
      service.surfaceShown(harness, true)
      screens.screensOff = true
      count = calls("BTC-USD.history")
      // The shared range can change from another surface or IPC while dark.
      service.setRange("10Y")
      service.testGate.pause = "none"
      service.testGate.report(["ok"], 0, service.testGate.ticket)
      var rangeHeld = within(5000, function() { return history.waitingForScreen || calls("BTC-USD.history") > count })
      check("a shared range change and host reopening in darkness start no history",
        rangeHeld && history.waitingForScreen && history.holds(history.job, "BTC-USD|10Y") && !history.job.ahead
          && calls("BTC-USD.history") === count)
      wake()
      awaitState(function() { return !history.busy }, 4000)
      service.setRange("1D")
      service.surfaceShown(harness, false)
      service.screens = null
    }

    function test_4_fundamentalsAndSearchDarkness() { guarded("test_4_fundamentalsAndSearchDarkness", checks_test_4_fundamentalsAndSearchDarkness) }
    function checks_test_4_fundamentalsAndSearchDarkness() {
      // AAPL in All: a cap and P/E is kept only for All, the preview, and a
      // removal on offer, pruned each minute (`Service.forgetLeft`), which
      // could otherwise drop AAPL's before the check.
      service.persist({ symbols: ["BTC-USD", "AAPL", "MSFT"] })
      quiet()
      service.screens = screens
      screens.screensOff = true
      service.screensAnsweredMs = Date.now()
      var before = calls("FUNDAMENTALS")
      // The window's stock is what's wanted (`Service.figuresWanted`).
      service.feature("AAPL")
      app.open("{}")
      awaitState(function() { return !!app.testBody }, 3000)
      var body = app.testBody
      app.testKeys.forceActiveFocus()
      awaitState(function() { return app.testKeys.activeFocus }, 2000)
      waitForRendering(app.testKeys)
      keyClick(Qt.Key_A)
      awaitState(function() { return body.search.active }, 3000)
      var searches = calls("SEARCH.asked")
      keyClick("Z"); keyClick("Z"); keyClick("Z")
      var searchHeld = within(5000, function() {
        return (service.testFundamentals.pendingUrl !== "" && body.search.requestedQuery === "ZZZ")
          || calls("SEARCH.asked") > searches || calls("FUNDAMENTALS") > before
      })
      check("dark fundamentals and a first search start no HTTP request",
        searchHeld && calls("FUNDAMENTALS") === before && calls("SEARCH.asked") === searches)
      var queuedEnd = Number(/period2=(\d+)/.exec(service.testFundamentals.pendingUrl)[1])
      service.clockOffset = 24 * 60 * 60
      wake()
      awaitState(function() { return body.search.resultsQuery === "ZZZ" && !service.testFundamentals.busy }, 6000)
      check("wake resumes both pending search and fundamentals", calls("SEARCH.asked") === searches + 1
        && calls("FUNDAMENTALS") === before + 2 && service.fundamentals.AAPL.status === "ok")
      check("a fundamentals snapshot held overnight ends at wake, not at the earlier ask",
        harness.snapshotEnd >= queuedEnd + 24 * 60 * 60, queuedEnd + " queued, " + harness.snapshotEnd + " sent")
      service.clockOffset = 0
      service.tick()
      body.cancelAdding()
      // The snapshot lands in the dark; its closes, a separate command, must
      // wait for a screen.
      flag("FUNDAMENTALS.hold", true)
      before = calls("FUNDAMENTALS")
      service.feature("MSFT")
      awaitState(function() { return calls("FUNDAMENTALS") === before + 1 }, 3000)
      screens.screensOff = true
      flag("FUNDAMENTALS.hold", false)
      var closesHeld = within(5000, function() { return service.testFundamentals.pendingUrl !== "" || calls("FUNDAMENTALS") > before + 1 })
      check("a fundamentals snapshot landing in darkness starts no closes request", closesHeld && calls("FUNDAMENTALS") === before + 1)
      wake()
      awaitState(function() { return !service.testFundamentals.busy }, 4000)
      check("wake sends the held fundamentals closes once", calls("FUNDAMENTALS") === before + 2 && service.fundamentals.MSFT.status === "ok")
      app.close()
      service.screens = null
      // The feed's own rules from here, on what it is handed, as no stock on
      // show can be: closes that throw, and a P/E in another currency.
      // Closes whose offset is {"toString": null} throw as they are read.
      var feed = service.testFundamentals
      before = calls("FUNDAMENTALS")
      feed.wanted = [{ symbol: "SKEWED", currency: "USD" }]
      awaitState(function() { return calls("FUNDAMENTALS") === before + 2 }, 3000)
      feed.wanted = [{ symbol: "NVDA", currency: "USD" }]
      var nextCame = within(5000, function() { return !feed.busy && !!feed.entries.NVDA && feed.entries.NVDA.status === "ok" })
      check("closes that throw as they are read fail their own cap and P/E, and the next symbol's still comes",
        nextCame && !!feed.entries.SKEWED && feed.entries.SKEWED.status === "failed",
        JSON.stringify({ skewed: feed.entries.SKEWED, nvda: feed.entries.NVDA && feed.entries.NVDA.status, busy: feed.busy }))
      // A rate the gate holds back waits for Yahoo: MSFT's figures fresh, as
      // if priced in CAD with earnings in USD and no USDCAD rate yet, while
      // Yahoo refuses. Nothing goes and the feed settles, and the rate comes
      // once Yahoo answers again.
      var gate = service.testGate
      var noRate = Object.assign({}, feed.rates)
      delete noRate.USDCAD
      feed.rates = noRate
      var rateCalls = calls("RATE")
      gate.report(["refused"], 60, gate.ticket)
      feed.wanted = [{ symbol: "MSFT", currency: "CAD" }]
      var heldSettled = within(2000, function() { return !feed.busy })
      var heldCalls = calls("RATE")
      gate.report(["ok"], 0, gate.ticket)
      var rateCame = within(5000, function() { return !!feed.rates.USDCAD && !feed.busy })
      check("a rate Yahoo's pause holds back asks nothing more, and comes once Yahoo answers again",
        heldSettled && heldCalls === rateCalls && rateCame && calls("RATE") === rateCalls + 1,
        JSON.stringify({ settled: heldSettled, whilePaused: heldCalls - rateCalls, came: rateCame, asked: calls("RATE") - rateCalls }))
      // A rate whose fetch fails waits as a failed cap and P/E does: no P/E,
      // nothing asked again on its own, and a reader's refresh asks once
      // more, and it comes.
      noRate = Object.assign({}, feed.rates)
      delete noRate.USDCAD
      feed.rates = noRate
      flag("RATE.down", true)
      rateCalls = calls("RATE")
      feed.wanted = []
      feed.wanted = [{ symbol: "MSFT", currency: "CAD" }]
      var failSettled = within(3000, function() { return calls("RATE") === rateCalls + 1 && !feed.busy })
      // Time for an ask that mustn't come: the service's clock moves on.
      wait(1500)
      var failedCalls = calls("RATE") - rateCalls
      var withoutRate = !(feed.rates.USDCAD && feed.rates.USDCAD.value)
      flag("RATE.down", false)
      service.refresh()
      var refreshedRate = within(5000, function() { return !!feed.rates.USDCAD && !!feed.rates.USDCAD.value && !feed.busy })
      check("a rate whose fetch failed asks nothing more on its own, and a refresh asks again, once, and it comes",
        failSettled && failedCalls === 1 && withoutRate && refreshedRate && calls("RATE") === rateCalls + 2,
        JSON.stringify({ settled: failSettled, beforeRefresh: failedCalls, came: refreshedRate, asked: calls("RATE") - rateCalls, held: feed.rates.USDCAD }))
      feed.wanted = Qt.binding(function() { return service.figuresWanted })
    }

    function test_5_malformedOvernightRecovers() { guarded("test_5_malformedOvernightRecovers", checks_test_5_malformedOvernightRecovers) }
    function checks_test_5_malformedOvernightRecovers() {
      flag("OVERNIGHT.malformed", true)
      nights.entries = { NEST: {status:"ok",bars:[{t:1,o:2,c:3}],at:1} }
      nights.fetch(["NEST", "KILN"], 2)
      var settled = within(3000, function() { return !nights.busy })
      check("a malformed overnight listing settles the failed batch and preserves last good prints",
        settled && nights.entries.NEST.status === "failed" && nights.entries.NEST.bars[0].c === 3 && nights.entries.NEST.bars[0].t === 1 && nights.entries.KILN.status === "failed")
      if (!settled) { flag("OVERNIGHT.malformed", false); return }
      flag("OVERNIGHT.malformed", false)
      nights.fetch(["NEST", "KILN"], 3)
      awaitState(function() { return !nights.busy }, 3000)
      check("the next valid overnight answer succeeds after a malformed listing",
        nights.entries.NEST.status === "ok" && nights.entries.KILN.status === "ok" && nights.entries.NEST.at === 3)
      // An hour asked for prints in hand that the service forgets while it
      // is out (a preview left five minutes on) leaves the listing with no
      // entry, so its next ask is its day, at once.
      nights.entries = { NEST: { status: "ok", bars: [{ t: 1000, p: 3, s: "overnight" }], through: 1000, at: 1000 } }
      nights.fetch(["NEST"], 1300)
      var askedHour = nights.batches.length === 1 && nights.batches[0].span === "hour"
      nights.entries = ({})
      awaitState(function() { return !nights.busy }, 3000)
      check("an hour's answer for prints the service forgot meanwhile leaves the listing unanswered",
        askedHour && !("NEST" in nights.entries), askedHour + " " + JSON.stringify(nights.entries))
    }

    function cleanupTestCase() {
      run(["chmod", "u+w", service.dataPath.slice(0, service.dataPath.lastIndexOf("/"))])
      finish()
    }
  }
}
