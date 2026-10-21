import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// The charts in sight fetched ahead, through the real Service and App with
// real Qt pointer, on every kind of listing a range can meet: a busy US
// stock (NEST, featured), a thin one (KILN), an ETF (SPY), an index
// (^GSPC), a cryptocurrency (BTC-USD), London (SHEL.L), Tokyo (7203.T), each
// answering its own saved year, and Toronto (SHOP.TO), whose history fails;
// then a long list in a window taller than the history cache. The fake curl
// logs every request in requests.log, "kind name status".
ShellRoot {
  id: harness

  property int failures: 0
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")
  readonly property var listed: ["NEST", "KILN", "SPY", "^GSPC", "BTC-USD", "SHEL.L", "7203.T", "SHOP.TO"]

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  // Every request answered, read through a fresh view each time.
  function requests() {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = harness.state + "/requests.log"
    var lines = String(view.text() || "").split("\n").filter(function(line) { return line !== "" })
    view.destroy()
    return lines
  }
  function requestCount() { return requests().length }
  // The symbol of every history request answered from request `from` on.
  function histories(from) {
    return requests().slice(from).filter(function(line) { return /^history /.test(line) })
      .map(function(line) { return line.split(" ")[1].replace("%5E", "^") })
  }

  function finish() {
    console.log("AHEAD DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }

  // Whether every screen is off, as the window's host would say.
  QtObject {
    id: screens
    property bool screensOff: false
    signal screensAnswered()
    function askScreens() { screenAnswer.restart(); return true }
  }

  Process { id: fileProc }

  Timer { id: screenAnswer; interval: 0; onTriggered: screens.screensAnswered() }

  TestCase {
    name: "Ahead"
    when: service.pluginsReady

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

    // Nothing wanted and nothing out, for a while: every chart asked for,
    // ahead too, has its answer.
    function quiet() {
      var still = 0
      for (var t = 0; t < 20000 && still < 400; t += 50) {
        wait(50)
        still = service.testHistoryFeed.busy ? 0 : still + 50
      }
      return still >= 400
    }
    function ok(symbol, range) {
      var entry = service.histories[symbol + "|" + range]
      return !!entry && entry.status === "ok"
    }
    function clickRow(body, symbol) {
      var row = body.watchlist.rowItem(symbol)
      mouseClick(row, 40, row.height / 2)
    }
    // The rows any of which shows, top first, as the list lays them out.
    function inSight(body) {
      var list = body.watchlist
      return list.displayedSymbols.filter(function(s, i) { return list.partInSight(i, list.contentY) })
    }

    function test_ahead() {
      tryVerify(function() { return harness.listed.every(function(s) { return !!service.quotes[s] }) }, 15000)
      // Tall enough for every row.
      app.testWindow.implicitHeight = 1000
      app.open("{}")
      var body = app.testBody
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)
      within(3000, function() { return inSight(body).length === harness.listed.length })
      var sight = inSight(body)
      harness.check("the window shows every row", sight.length === harness.listed.length,
        sight.join(",") + " in " + app.testWindow.height + " px")
      var gate = service.testYahooGate

      // On a range, the hero's chart first, then each row in sight, top
      // first, one at a time; a row whose answer fails keeps none.
      var from = harness.requestCount()
      body.selectRange("1Y")
      quiet()
      var asked = harness.histories(from)
      var rows = sight.filter(function(s) { return s !== "NEST" })
      harness.check("on 1Y the hero's chart is asked first, then every row in sight, top first, each once",
        asked.join(",") === ["NEST"].concat(rows).join(","), "asked " + asked.join(",") + " | in sight " + sight.join(","))
      var kept = rows.filter(function(s) { return ok(s, "1Y") })
      harness.check("each kind's chart fetched ahead is kept, and Toronto's failed one keeps nothing",
        kept.join(",") === rows.filter(function(s) { return s !== "SHOP.TO" }).join(",") && !service.histories["SHOP.TO|1Y"],
        "kept " + kept.join(",") + " | SHOP.TO " + JSON.stringify(service.histories["SHOP.TO|1Y"] || null))

      // A click on a row fetched ahead shows its chart at once, asking
      // nothing; one whose fetch ahead failed asks, as the hero, and loads.
      from = harness.requestCount()
      var waited = []
      ;["KILN", "SPY", "^GSPC", "BTC-USD", "SHEL.L", "7203.T"].forEach(function(s) {
        clickRow(body, s)
        if (body.chartLoading || body.chartSymbol !== s || body.headerText.indexOf("Loading") === 0) waited.push(s)
        wait(100)
      })
      var clickAsked = harness.histories(from)
      harness.check("a click on a row fetched ahead shows its 1Y at once, on every kind, asking nothing",
        waited.length === 0 && clickAsked.length === 0, "waited " + waited.join(",") + " | asked " + clickAsked.join(","))
      clickRow(body, "SHOP.TO")
      var shopLoads = body.chartLoading
      within(8000, function() { return !body.chartLoading })
      harness.check("a click on a row whose fetch ahead failed asks for it as the hero, and loads",
        shopLoads && harness.histories(from).join(",") === "SHOP.TO,SHOP.TO" && body.headerText === "1Y unavailable",
        shopLoads + " | " + harness.histories(from).join(",") + " | " + body.headerText)
      clickRow(body, "NEST")
      quiet()

      // The hero's chart never waits on one fetched ahead: SPY's is held
      // out, and BTC-USD clicked meanwhile lands while SPY's is still held.
      touch("SPY.history.hold")
      from = harness.requestCount()
      body.selectRange("6M")
      tryVerify(function() { return !!service.testHistoryFeed.wanted && service.testHistoryFeed.wanted.symbol === "SPY" }, 5000)
      clickRow(body, "BTC-USD")
      var heroLanded = within(3000, function() { return ok("BTC-USD", "6M") && !body.chartLoading })
      remove("SPY.history.hold")
      quiet()
      harness.check("a row clicked while another's chart is fetched ahead gets its own at once, and the cut one is asked again after",
        heroLanded && ok("SPY", "6M"), heroLanded + " | " + harness.histories(from).join(","))

      // A new range drops what was fetched ahead for the last one and never
      // shown; the heroes' charts stay.
      body.selectRange("1W")
      wait(50)
      var stillAhead = ["KILN", "SPY", "^GSPC", "SHEL.L", "7203.T"].filter(function(s) { return !!service.histories[s + "|6M"] })
      var heroesGone = ["NEST|6M", "BTC-USD|6M"].concat(rows.map(function(s) { return s + "|1Y" }))
        .filter(function(k) { return !service.histories[k] })
      harness.check("a new range drops the last range's charts fetched ahead and never shown, and keeps every hero's",
        stillAhead.length === 0 && heroesGone.length === 0, "still there " + stillAhead.join(",") + " | heroes gone " + heroesGone.join(","))
      quiet()

      // A user's refresh asks for the hero's chart fresh, and none fetched
      // ahead.
      from = harness.requestCount()
      service.refresh()
      quiet()
      harness.check("r asks for the hero's chart fresh, not those fetched ahead", harness.histories(from).join(",") === "BTC-USD",
        harness.histories(from).join(","))

      // The day fetches no history, ahead or not.
      from = harness.requestCount()
      body.selectRange("1D")
      wait(1500)
      harness.check("the day fetches nothing ahead", harness.histories(from).length === 0, harness.histories(from).join(","))

      // Fetching ahead waits for half of Yahoo's budget, and for Yahoo to
      // answer; the hero's chart does not.
      gate.tokens = 30
      from = harness.requestCount()
      body.selectRange("3M")
      wait(1500)
      var underHalf = harness.histories(from).join(",")
      gate.tokens = gate.capacity
      var afterRefill = within(3000, function() { return harness.histories(from).length > 1 })
      quiet()
      harness.check("with under half of Yahoo's budget left only the hero's chart goes; the rows' go once it is back",
        underHalf === "BTC-USD" && afterRefill, underHalf + " | then " + harness.histories(from).join(","))
      gate.pause = "none"
      gate.pausedUntil = gate.now() + 600
      from = harness.requestCount()
      body.selectRange("5Y")
      wait(1500)
      var whilePaused = harness.histories(from).length
      var pausedHeader = body.headerText
      gate.pause = ""
      gate.pausedUntil = 0
      var afterPause = within(3000, function() { return harness.histories(from).length > 0 })
      quiet()
      harness.check("while Yahoo is paused nothing is fetched ahead, and the rows' go once it answers again",
        whilePaused === 0 && pausedHeader === "5Y unavailable" && afterPause,
        whilePaused + " | " + pausedHeader + " | then " + harness.histories(from).join(","))

      // Nor while every screen is off.
      service.screens = screens
      screens.screensOff = true
      from = harness.requestCount()
      body.selectRange("2Y")
      wait(1500)
      var dark = harness.histories(from).join(",")
      screens.screensOff = false
      screens.screensAnswered()
      var lit = within(3000, function() { return harness.histories(from).length > 1 })
      quiet()
      service.screens = null
      harness.check("while every screen is off no history goes; the requested hero goes first once one is on",
        dark === "" && lit && harness.histories(from)[0] === "BTC-USD", dark + " | then " + harness.histories(from).join(","))

      // A chart fetched ahead and shown through search's preview is a
      // hero's: the next range keeps it. Found in the review of this
      // change: only the featured symbol's was kept.
      body.startAdding()
      wait(100)
      body.search.chose("SPY")
      var previewed = within(1000, function() { return body.chartSymbol === "SPY" && !body.chartLoading })
      body.cancelAdding()
      wait(100)
      // An ahead request for the last range stops when the next one's hero
      // is already in hand, and keeps nothing: SHEL.L's month held out, then
      // 6M, whose hero BTC-USD has. Found in the same review: it went on
      // and left a chart nobody would drop.
      touch("SHEL.L.history.hold")
      body.selectRange("1M")
      wait(50)
      var previewKept = !!service.histories["SPY|2Y"]
      tryVerify(function() { var w = service.testHistoryFeed.wanted; return !!w && w.key === "SHEL.L|1M" }, 10000)
      var heroInHand = ok("BTC-USD", "6M")
      body.selectRange("6M")
      var cut = within(1000, function() { var w = service.testHistoryFeed.wanted; return !w || w.range === "6M" })
      remove("SHEL.L.history.hold")
      quiet()
      harness.check("a chart fetched ahead and previewed through search is kept on the next range, and one fetched ahead for the last range stops on a cached hero, keeping nothing",
        previewed && previewKept && heroInHand && cut && !service.histories["SHEL.L|1M"],
        [previewed, previewKept, heroInHand, cut, JSON.stringify(service.histories["SHEL.L|1M"] || null)].join(" | "))

      // Closing the window stops the chart fetched ahead, and with none
      // open nothing is fetched.
      touch("KILN.history.hold")
      body.selectRange("10Y")
      tryVerify(function() { return !!service.testHistoryFeed.wanted && service.testHistoryFeed.wanted.symbol === "KILN" }, 5000)
      app.close()
      var stopped = within(1000, function() { return !service.testHistoryFeed.busy })
      remove("KILN.history.hold")
      from = harness.requestCount()
      service.setRange("YTD")
      wait(1500)
      harness.check("closing the window stops the chart fetched ahead, and with none open nothing is fetched",
        stopped && harness.histories(from).length === 0, stopped + " | " + harness.histories(from).join(","))

      // A window tall enough to show more rows than the cache keeps, on a
      // long list: fetching ahead stops at what the cache holds beside the
      // hero's chart, and nothing asks on after; scrolled to the end, the
      // rows coming into sight are fetched as those that left go, and the
      // hero's chart, the oldest kept, stays on show throughout. The budget
      // is topped up for the run of 45 first answers and for the rows,
      // which would otherwise wait for it to refill; the 45 days are judged
      // on the chart first, from the spare budget fetching ahead also uses.
      var tall = []
      for (var n = 1; n <= 45; n++) tall.push("TALL" + (n < 10 ? "0" : "") + n)
      gate.tokens = gate.capacity
      tall.forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 }, 20000)
      for (var top = 0; top < 30 && service.testFeed.toJudge.length > 0; top++) {
        gate.tokens = gate.capacity
        wait(200)
      }
      app.testWindow.implicitHeight = 2600
      app.open("{}")
      var everyRow = harness.listed.length + tall.length
      tryVerify(function() { return inSight(body).length > service.testHistoryFeed.keep }, 3000)
      var tallSight = inSight(body).length
      quiet()
      gate.tokens = gate.capacity
      var landed = false
      var lost = false
      var watchHero = function() {
        if (!body.chartLoading) landed = true
        else if (landed) lost = true
      }
      body.chartLoadingChanged.connect(watchHero)
      from = harness.requestCount()
      body.selectRange("1Y")
      landed = !body.chartLoading
      var settled = quiet()
      var tallAsked = harness.histories(from).length
      wait(2000)
      var askedOn = harness.histories(from).length - tallAsked
      var room = service.testHistoryFeed.keep
      harness.check("a window showing more rows than the cache keeps fetches ahead no more than the cache holds beside the hero's chart, and nothing asks on",
        settled && tallAsked > 0 && tallAsked <= room && askedOn === 0 && tallSight < everyRow,
        settled + " | " + tallAsked + " asked of " + room + " (" + harness.histories(from).slice(0, 3).join(",") + "…), then " + askedOn
          + ", " + tallSight + " rows of " + everyRow + " in sight")
      gate.tokens = gate.capacity
      var pickAsked = harness.histories(from)
      from = harness.requestCount()
      body.watchlist.contentY = body.watchlist.contentHeight - body.watchlist.height
      var scrolled = quiet()
      var scrollAsked = harness.histories(from)
      wait(2000)
      var scrollOn = harness.histories(from).length - scrollAsked.length
      body.chartLoadingChanged.disconnect(watchHero)
      var again = scrollAsked.filter(function(s) { return pickAsked.indexOf(s) >= 0 })
      harness.check("scrolled to the end, only the rows coming into sight are fetched ahead, none of those fetched before, and the hero's chart stays on show",
        scrolled && scrollAsked.length > 0 && again.length === 0 && scrollOn === 0 && !lost && !!service.histories[body.featuredSymbol + "|1Y"],
        scrolled + " | " + scrollAsked.join(",") + " asked, " + again.length + " of them again, then " + scrollOn + " | hero lost " + lost + " | " + body.featuredSymbol)
      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done; interval: 100 }
}
