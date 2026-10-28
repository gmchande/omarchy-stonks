import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks
import "plugin/Chart.js" as Chart
import "plugin/Figures.js" as Figures
import "plugin/Format.js" as Format

// Overnight prices through the real Service, its feeds, and the App window,
// on a clock this harness moves forward. The fake curl answers Yahoo and
// Robinhood from test/fixtures/moments, one saved moment at a time. The
// library holds three US stocks, an index, a cryptocurrency, and a Toronto
// listing; others join it on the way.
Harness {
  id: harness
  marker: "OVERNIGHT DONE"

  readonly property int saturday: 1790438400
  readonly property int sunday: 1790562600
  readonly property int night: 1790910000
  readonly property int live: 1791175013
  // Midnight in New York.
  readonly property var midnight: ({ fri25: 1790308800, thu1: 1790827200, fri2: 1790913600, tue6: 1791259200,
    wed7: 1791345600, thu8: 1791432000 })
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")

  function record(name) { return readFile(harness.state + "/" + name).trim() }

  // Every symbol in a Robinhood request log, as Stonks names it, once each,
  // sorted.
  function asked(log) {
    var seen = []
    harness.record(log).split(/[\n,]/).forEach(function(sent) {
      var s = decodeURIComponent(sent).replace(/\.USD$/, "-USD")
      if (s && seen.indexOf(s) < 0) seen.push(s)
    })
    return seen.sort()
  }

  function requestsFor(log, symbol) {
    return harness.record(log).split("\n").filter(function(line) {
      return line.split(",").indexOf(symbol) >= 0
    }).length
  }
  function allDayAsked(symbol) { return requestsFor("INSTRUMENTS.asked", symbol) }
  function printsAsked(symbol) { return requestsFor("OVERNIGHT.asked", symbol) }

  function sleep() { return app.testBody.animal.asleep ? "asleep" : "awake" }

  // The words and figures of the line under the price.
  function strip() {
    var row = find(app.testBody, "extendedLine")
    if (!row || !row.visible) return ""
    var words = []
    for (var i = 0; i < row.children.length; i++) {
      var child = row.children[i]
      if (child.visible && child.text) words.push(child.text)
    }
    return words.join(" ")
  }

  // What's on top while the listing on show has traded since its close: the
  // session and time, the newest price, and its move since the close
  // ("OVERNIGHT 22:20 234.84 −1.05%"); "" without.
  function top() {
    var body = app.testBody
    if (!body.featured || !body.featured.newest) return ""
    return [find(body, "changeCaption").text, body.featured.priceText, body.featured.changeText].join(" ")
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }

  Process { id: setProc }

  Steps {
    name: "Overnight"
    when: service.pluginsReady

    function featureShown(symbol) {
      service.feature(symbol)
      return within(3000, function() {
        var body = app.testBody
        return body.chartSymbol === symbol && !body.chartLoading
      })
    }

    function runCommand(command) {
      setProc.command = command
      setProc.running = true
      tryVerify(function() { return !setProc.running }, 2000)
    }

    // Points the fake curl at another saved moment.
    function useSet(name) {
      runCommand(["sh", "-c", "echo \"$1\" > \"$2\"", "--", name, harness.state + "/overnight.set"])
    }

    function pressKey(key) {
      app.testKeyCatcher.forceActiveFocus()
      keyClick(key)
    }

    function useLook(retro) {
      if (service.retro === retro) return
      pressKey(Qt.Key_S)
      within(2000, function() { return service.retro === retro })
    }

    // A pointer over the 1D chart at `fraction` of its width, as a scrub.
    function scrubAt(fraction) {
      var chart = app.testBody.chartItem
      mouseMove(chart, 3 + fraction * (chart.width - 6), chart.height / 2)
      within(1000, function() { return app.testBody.scrubT !== 0 })
    }

    function endScrub() {
      mouseMove(app.testBody.chartItem, -20, -20)
      app.testBody.motion.clearScrub()
    }

    function lastSpan() {
      var spans = harness.record("OVERNIGHT.spans").split("\n")
      return spans[spans.length - 1]
    }

    function test_overnight() {
      service.now = harness.saturday
      var all = ["NEST", "SILK", "REED", "^GSPC", "BTC-USD", "SHOP.TO"]
      within(8000, function() { return all.every(function(s) { return !!service.quotes[s] }) })
      // overnight.sh holds Robinhood's answers from the start, so both
      // questions are out before either answers.
      var bothOut = within(5000, function() {
        return harness.record("INSTRUMENTS.calls") === "1" && harness.record("OVERNIGHT.calls") === "1"
      })
      check("with nothing open, the pill's first live answer asks Robinhood whether it trades it all day and for its prints at once, for it alone",
        bothOut && harness.record("INSTRUMENTS.asked") === "NEST" && harness.record("OVERNIGHT.asked") === "NEST",
        harness.record("INSTRUMENTS.asked") + " | " + harness.record("OVERNIGHT.asked"))
      runCommand(["rm", "-f", harness.state + "/ROBINHOOD.hold"])
      within(3000, function() { return !!service.testAllDayFeed.entries.NEST && !!service.testOvernightFeed.entries.NEST })
      // Two five-minute steps with nothing open: time for an ask that must
      // not come.
      service.now += 5 * 60
      wait(300)
      service.now += 5 * 60
      wait(300)
      check("with nothing open, Robinhood is asked once, and never again",
        harness.record("INSTRUMENTS.calls") === "1" && harness.record("OVERNIGHT.calls") === "1",
        harness.record("INSTRUMENTS.calls") + ", " + harness.record("OVERNIGHT.calls"))
      service.now = harness.saturday

      // Saturday noon, after Friday 25 September.
      runCommand(["touch", harness.state + "/ROBINHOOD.hold"])
      app.open("{}")
      var body = app.testBody
      var firstFrame = body.chartSymbol + (body.chartLoading ? " loading" : "")
      var restOut = within(5000, function() {
        return harness.record("INSTRUMENTS.calls") === "2" && harness.record("OVERNIGHT.calls") === "2"
      })
      runCommand(["rm", "-f", harness.state + "/ROBINHOOD.hold"])
      check("a window opened after them shows the pill's 1D chart at once", firstFrame === "NEST", firstFrame)
      check("the first open asks for the rest's instruments and prints together: both out before either answers",
        restOut && harness.record("INSTRUMENTS.asked").split("\n")[1] === "SILK,REED"
          && harness.record("OVERNIGHT.asked").split("\n")[1] === "SILK,REED",
        harness.record("INSTRUMENTS.asked") + " | " + harness.record("OVERNIGHT.asked"))
      featureShown("NEST")
      // Read at the end, where every later ask is in the logs too.
      var openAsked = harness.record("OVERNIGHT.calls") + " calls for " + harness.asked("OVERNIGHT.asked").join(",") + ", " + lastSpan()

      // r asks Robinhood again for the chart on show alone.
      // The open's answers in first: a feed with a request out sends none.
      within(3000, function() { return !service.testOvernightFeed.busy && !service.testAllDayFeed.busy })
      var calls = harness.record("OVERNIGHT.calls")
      service.now = harness.saturday + 40 * 60
      pressKey(Qt.Key_R)
      var rAsked = within(2000, function() { return Number(harness.record("OVERNIGHT.calls")) === Number(calls) + 1 })
      var rListings = harness.record("OVERNIGHT.asked").split("\n").filter(function(l) { return l !== "" }).pop()
      // While r's answers are out the header says "Refreshing".
      var rLanded = within(3000, function() { return !service.refreshing })
      check("r asks Robinhood for the chart on show alone, never the rows",
        rAsked && rLanded && body.chartSymbol === "NEST" && rListings === "NEST",
        harness.record("OVERNIGHT.calls") + " calls, the last for " + rListings + (rLanded ? "" : ", still refreshing"))
      calls = harness.record("OVERNIGHT.calls")

      // Sunday 22:30, the week's first night, Yahoo's day still Friday's:
      // the open surface asks by itself, and five minutes on, again.
      useSet("sunday")
      service.now = harness.sunday
      within(3000, function() { return harness.top().indexOf("OVERNIGHT") === 0 })
      check("Sunday night trades on top, measured from Friday's close, the close beneath",
        harness.top() === "OVERNIGHT 22:20 234.84 \u22121.05%" && harness.strip() === "FRI CLOSE 237.33 \u22122.53%",
        harness.top() + " | " + harness.strip())
      var sundayCalls = Number(harness.record("OVERNIGHT.calls"))
      service.now = harness.sunday + 5 * 60
      within(2000, function() { return Number(harness.record("OVERNIGHT.calls")) > sundayCalls })
      check("while a night trades, the open surface asks every five minutes, for the last hour only, the chart Sunday's night from 20:00",
        Number(calls) + 1 === sundayCalls && Number(harness.record("OVERNIGHT.calls")) === sundayCalls + 1 && lastSpan() === "hour"
          && within(2000, function() { return body.featuredGeometry.start === harness.midnight.fri25 + 2 * 86400 + 20 * 3600 && harness.top() === "OVERNIGHT 22:20 234.84 \u22121.05%" }),
        calls + ", " + sundayCalls + ", " + harness.record("OVERNIGHT.calls") + " " + lastSpan() + " | " + harness.top())

      // Monday 04:11, the night's last bars due, and Robinhood down.
      var feed = service.testOvernightFeed
      runCommand(["touch", harness.state + "/OVERNIGHT.down"])
      var before = Number(harness.record("OVERNIGHT.calls"))
      service.now = 1790583060
      within(2000, function() { return feed.entries.NEST.status === "failed" })
      var keptLine = harness.top()
      runCommand(["rm", "-f", harness.state + "/OVERNIGHT.down"])
      service.now = 1790583060 + 2 * 60
      // Two minutes on nothing may be asked: time for an ask to show.
      wait(300)
      var paced = Number(harness.record("OVERNIGHT.calls"))
      service.now = 1790583060 + 6 * 60
      within(2000, function() { return feed.entries.NEST.status === "ok" })
      check("a failed answer keeps the last good prints, and is asked again five minutes on until it answers",
        keptLine.indexOf("OVERNIGHT SUN 22:20") === 0 && paced === before + 1 && feed.entries.NEST.status === "ok"
          && Number(harness.record("OVERNIGHT.calls")) === before + 2,
        keptLine + " | " + before + ", " + paced + ", " + harness.record("OVERNIGHT.calls") + " " + feed.entries.NEST.status)

      // r's request for the prints meets a 429, and the gate holds the
      // next r's.
      var line = harness.top()
      runCommand(["touch", harness.state + "/ROBINHOOD.refuse"])
      service.now = 1790583060 + 12 * 60
      pressKey(Qt.Key_R)
      within(2000, function() { return service.testRobinhoodGate.pause === "refused" })
      var quotesBefore = harness.record("requests.log").split("\n").filter(function(l) { return /^(chart|spark) /.test(l) }).length
      service.now += 20
      keyClick(Qt.Key_R)
      // The held request must not go: time for it to show.
      wait(500)
      var refusedCalls = Number(harness.record("ROBINHOOD.refused.calls"))
      var quotesAfter = harness.record("requests.log").split("\n").filter(function(l) { return /^(chart|spark) /.test(l) }).length
      check("a Robinhood refusal pauses Robinhood alone: one request refused, the next held, Yahoo's quotes still asked, the prints kept",
        service.testRobinhoodGate.pause === "refused" && refusedCalls === 1 && service.testYahooGate.pause === ""
          && quotesAfter > quotesBefore && harness.top() === line,
        [service.testRobinhoodGate.pause, refusedCalls, service.testYahooGate.pause, quotesBefore + " → " + quotesAfter, line + " → " + harness.top()].join(" | "))
      runCommand(["rm", "-f", harness.state + "/ROBINHOOD.refuse"])
      service.now += 5 * 60
      within(2000, function() { return feed.entries.NEST.status === "ok" && service.testRobinhoodGate.pause === "" })

      // Thursday 1 October, 23:00, the night after Thursday's close.
      useSet("night")
      service.now = harness.night
      keyClick(Qt.Key_R)
      // Every saved day of the night in, so the breadth is the night's.
      within(5000, function() {
        return harness.strip().indexOf("CLOSE 232.28 ") === 0 && !body.chartLoading
          && ["SILK", "REED", "^GSPC"].every(function(s) {
            return service.quotes[s].session.regular.start === service.quotes.NEST.session.regular.start
          })
      })
      within(3000, function() { return harness.top().indexOf("OVERNIGHT") === 0 })
      var info = body.dayLine
      check("the night's newest price is on top, Thursday's close beneath, and the night is never in the day's high: its 243.20 leaves Thursday's 239.63",
        /^OVERNIGHT \d\d:\d\d 234\.27 /.test(harness.top()) && harness.strip().indexOf("CLOSE 232.28 ") === 0
          && !!info && info.range.highText === "239.63", harness.top() + " | " + harness.strip() + " | " + JSON.stringify(info))

      var row = body.watchlist.rowItem("NEST")
      var breadth = JSON.stringify(body.breadth)
      var onTop = body.featured.priceText
      scrubAt(Chart.fractionAtTime(body.featuredDay, harness.night - 90 * 60))
      var nightScrub = body.headerText + " | " + body.featured.priceText + " | row " + row.view.priceText + " | " + JSON.stringify(body.breadth)
      var heroMoved = body.featured.priceText !== onTop
      var rowsStill = row.view.priceText === onTop && JSON.stringify(body.breadth) === breadth
      endScrub()
      check("a scrub of the night reads the night on the hero, and leaves the rows and the breadth on now",
        nightScrub.indexOf("At 21:") === 0 && heroMoved && rowsStill, nightScrub + " vs " + onTop + " " + breadth)

      // SILK's quote came from the list's spark run, closes only: its day
      // is read once the hero's chart is in.
      featureShown("SILK")
      var silkCharted = within(3000, function() { return !service.quotes.SILK.closesOnly })
      var silkNight = body.featuredGeometry

      // Search's choice on the hero. AAPL's quote is held out until both of
      // Robinhood's asks are out.
      pressKey(Qt.Key_A)
      within(2000, function() { return body.adding })
      body.previewTo("SILK")
      within(3000, function() { return body.chartSymbol === "SILK" && !body.chartLoading })
      var listed = body.featuredGeometry
      runCommand(["touch", harness.state + "/AAPL.quote.hold"])
      body.search.results = [{ symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", instrumentType: "EQUITY" }]
      body.search.answer = "results"
      body.search.choose(0)
      var beside = within(3000, function() { return harness.allDayAsked("AAPL") === 1 && harness.printsAsked("AAPL") === 1 })
        && !service.previewEntries.AAPL
      runCommand(["rm", "-f", harness.state + "/AAPL.quote.hold"])
      within(4000, function() { return body.chartSymbol === "AAPL" && !body.chartLoading })
      var unadded = service.previewView.chart
      // Its calendar day: from New York's midnight, 9½ hours before the bell.
      var fromMidnight = !!unadded && Chart.chartSpan(unadded.day).start === unadded.quote.session.regular.start - 9.5 * 3600
      var previewSaid = [body.chartSymbol, body.adding, silkCharted && listed.start === silkNight.start && listed.end === silkNight.end,
        listed.points.length + "/" + silkNight.points.length, beside, harness.allDayAsked("AAPL"), harness.printsAsked("AAPL"),
        !!unadded && unadded.allDay, fromMidnight]
      check("search's preview of a symbol in All shows its chart as featured; one not yet added, a US stock, is asked of Robinhood while its quote is out, and trades all night, as it will added",
        previewSaid.join(" ") === "AAPL true true " + silkNight.points.length + "/" + silkNight.points.length + " true 1 1 true true",
        "symbol, adding, SILK's span, its points, Robinhood asked while the quote was out, AAPL's all-day and prints asks, all day, from midnight: " + previewSaid.join(" "))
      body.cancelAdding()
      within(3000, function() { return !body.adding && body.chartSymbol === "SILK" && !body.chartLoading })

      // Monday 5 October, 00:36, the first live night: TOY traded five
      // times since Sunday 20:00, the last at 00:20, and its chart is that
      // night's, running on past midnight.
      useSet("live-2026-10-05")
      service.now = harness.live
      pressKey(Qt.Key_R)
      service.addSymbol("TOY")
      within(8000, function() { return !!service.quotes.TOY && service.arriving.length === 0 })
      ;[false, true].forEach(function(retro) {
        useLook(retro)
        var look = retro ? "retro" : "smooth"
        featureShown("TOY")
        var toy = body.featuredDay
        var offset = service.quotes.TOY.gmtoffset
        var sunday = harness.midnight.fri2 + 2 * 86400
        var trades = toy.points.filter(function(p) { return p.t >= sunday + 20 * 3600 })
        // The 00:20 dot, the newest, at the right edge.
        scrubAt(Chart.fractionAtTime(toy, 1791174000))
        var scrubbed = [body.headerText, body.featured.priceText].join(" | ")
        endScrub()
        check(look + ": a scrub at TOY's 00:20 dot lands on it and says its time",
          scrubbed === "At 00:20 · Overnight | 322.00", scrubbed)
        scrubAt(0)
        var edge = body.headerText
        endScrub()
        var replayRead = []
        var watch = function() { if (body.motion.replayRunning) replayRead.push(body.headerText) }
        body.headerTextChanged.connect(watch)
        body.replay()
        var replayed = body.headerText + " | " + body.featured.priceText
        within(4000, function() { return !body.motion.replayRunning })
        body.headerTextChanged.disconnect(watch)
        // A trade before midnight is Sunday's, and says so. The first is
        // where the replay starts.
        var read = replayRead.concat([replayed.split(" | ")[0]])
        var missed = trades.map(function(p) { return "At " + (p.t < sunday + 86400 ? "Sun " : "") + Format.hhmm(p.t, offset) + " · Overnight" })
          .filter(function(said) { return read.indexOf(said) < 0 })
        check(look + ": the left edge and a replay's first moment read the night's first trade, and the replay reads every one of them",
          trades.length === 5 && trades.length === toy.points.length && edge === "At Sun 20:00 · Overnight"
            && replayed === "At Sun 20:00 · Overnight | 325.96" && missed.length === 0,
          trades.length + " trades ; " + edge + " ; " + replayed + " ; missed " + missed.join(", "))
      })

      // On 1M, with its history in.
      useLook(false)
      featureShown("NEST")
      pressKey(Qt.Key_BracketRight)
      keyClick(Qt.Key_BracketRight)
      within(5000, function() { return body.chartRange === "1M" && body.historyShown && !body.historyFailed && !body.chartLoading })
      var month = harness.strip()
      scrubAt(0.5)
      var legend = find(body, "baselineLegend")
      var scrubbedMonth = harness.strip() + " | " + (legend.visible ? legend.text : "")
      endScrub()
      check("smooth: a 1M scrub rests the line, and the baseline's legend takes its place; the scrub's end brings it back",
        month.indexOf("OVERNIGHT ") === 0 && scrubbedMonth.indexOf(" | ┄ 1M START ") === 0 && harness.strip() === month,
        month + " | " + scrubbedMonth + " then " + harness.strip())

      // Wednesday 7 October, 01:00, back on 1D: Tuesday's chart, its night
      // after midnight at the right end.
      pressKey(Qt.Key_BracketLeft)
      keyClick(Qt.Key_BracketLeft)
      useSet("2026-10-07-0100")
      service.now = 1791349200
      service.refresh()
      within(8000, function() {
        return body.chartRange === "1D" && body.featuredQuote && body.featuredQuote.session.regular.start === 1791293400
          && !body.chartLoading && body.featuredGeometry.end > harness.midnight.wed7 && harness.strip().indexOf("OVERNIGHT 00:") === 0
      })
      line = harness.strip().split(" ")
      pressKey(Qt.Key_C)
      within(2000, function() { return service.changeMode === "abs" })
      var asAmount = harness.strip().split(" ")
      var amountSays = [asAmount.slice(0, 3).join(" ") === line.slice(0, 3).join(" "),
        /^[+\u2212]\d+\.\d\d$/.test(asAmount[3]), asAmount[3].charAt(0) === line[3].charAt(0)].join(",")
      keyClick(Qt.Key_C)
      within(2000, function() { return service.changeMode === "open" })
      check("the line under the price follows c: an amount of the same sign as an amount, the percent from the close since the open",
        amountSays === "true,true,true" && harness.strip() === line.join(" "),
        line.join(" ") + " -> " + asAmount.join(" ") + " (" + amountSays + ") -> " + harness.strip())
      var nestRow = body.watchlist.rowItem("NEST")
      check("since the open, at rest, with Tuesday's chart and its night on show, the hero's change is Tuesday's, as its row's is",
        body.featuredGeometry.start === harness.midnight.tue6
          && body.featured.changeText === nestRow.view.changeText && body.featured.changeText !== "+7.44%",
        body.featuredGeometry.start + " | " + body.featured.changeText + " vs " + nestRow.view.changeText)
      keyClick(Qt.Key_C)
      within(2000, function() { return service.changeMode === "pct" })

      // KILN and BOLT, which Robinhood does not trade all day, join.
      useSet("listings-2026-10-07-0100")
      service.addSymbol("KILN")
      service.addSymbol("BOLT")
      within(8000, function() { return !!service.quotes.KILN && !!service.quotes.BOLT && service.arriving.length === 0 })
      featureShown("NEST")
      var nest = harness.sleep()
      var nestHeader = body.headerText + " | " + harness.top()
      featureShown("KILN")
      var kiln = harness.sleep()
      var kilnHeader = body.headerText + " | " + harness.top()
      scrubAt(0.5)
      var scrubbedAwake = harness.sleep()
      endScrub()
      within(1000, function() { return body.scrubT === 0 })
      var sleeps = "NEST " + nest + ", KILN " + kiln + ", scrubbed " + scrubbedAwake + ", let go " + harness.sleep()
      check("01:00: NEST, whose night trades, is awake; KILN sleeps, a scrub wakes it, and letting go puts it back to sleep at once",
        sleeps === "NEST awake, KILN asleep, scrubbed awake, let go asleep", sleeps)
      check("01:00: NEST's header says Overnight, as the caption by its price does; KILN's says Closed, its price on top Tuesday's after hours",
        nestHeader.indexOf("Overnight · opens Wed 09:30 | OVERNIGHT ") === 0 && kilnHeader.indexOf("Closed · opens Wed 09:30 | AFTER HOURS TUE ") === 0,
        nestHeader + " || " + kilnHeader)
      // The clock reaching KILN's pre-market wakes it while it is on show.
      service.now = harness.midnight.wed7 + 4 * 3600 - 2
      var beforeWake = within(1000, function() { return harness.sleep() === "asleep" })
      service.now = harness.midnight.wed7 + 4 * 3600
      var woke = within(2000, function() { return harness.sleep() === "awake" })
      check("04:00: KILN's pre-market starting wakes its animal", body.chartSymbol === "KILN" && beforeWake && woke,
        body.chartSymbol + " " + beforeWake + " " + woke)

      // 14:55. NEST's newest print, 235.32 at 14:55:42, is no five-minute
      // mark: retro rounding it back would read the print before, 235.31.
      useSet("listings-2026-10-07-1455")
      service.now = 1791399300
      service.refresh()
      within(8000, function() { return service.quotes.KILN.session.regular.start === 1791379800 && service.quotes.BOLT.session.regular.start === 1791379800 })
      featureShown("NEST")
      within(8000, function() { return body.featuredQuote.session.regular.start === 1791379800 })
      var edgeRead = [false, true].map(function(retro) {
        useLook(retro)
        scrubAt(1)
        var read = body.featured.priceText
        endScrub()
        return read
      })
      useLook(false)
      check("a scrub at NEST's newest print, 14:55:42, reads 235.32 there in both looks",
        edgeRead[0] === edgeRead[1] && edgeRead[0] === "235.32", edgeRead.join(" vs "))
      check("Robinhood's answer on all-day trading holds the day: KILN and BOLT asked once, their prints never again",
        harness.allDayAsked("KILN") === 1 && harness.allDayAsked("BOLT") === 1 && harness.printsAsked("KILN") === 1
          && harness.printsAsked("BOLT") === 1,
        harness.allDayAsked("KILN") + ", " + harness.allDayAsked("BOLT") + " | prints " + harness.printsAsked("KILN") + ", " + harness.printsAsked("BOLT"))

      // Robinhood's instruments down as SPY joins: not all-day meanwhile.
      runCommand(["touch", harness.state + "/INSTRUMENTS.down"])
      service.addSymbol("SPY")
      within(8000, function() { return !!service.quotes.SPY && service.arriving.length === 0 })
      var landed = featureShown("SPY")
      var down = body.featuredGeometry.start + " | " + harness.strip()
      runCommand(["rm", "-f", harness.state + "/INSTRUMENTS.down"])
      service.now = 1791399300 + 6 * 60
      within(4000, function() { return body.featuredGeometry.start === harness.midnight.wed7 })
      check("with Robinhood's instruments down, SPY lands on Yahoo's day; asked again five minutes on, it turns to the calendar day",
        landed && down.indexOf(String(harness.midnight.wed7 + 4 * 3600)) === 0 && body.featuredGeometry.start === harness.midnight.wed7
          && harness.allDayAsked("SPY") === 2,
        down + " then " + body.featuredGeometry.start + ", asked " + harness.allDayAsked("SPY"))

      // A symbol that leaves All, with no edit to prompt the pruning.
      var prints = service.testOvernightFeed
      var allDay = service.testAllDayFeed
      // Answered for `symbol` at the clock's present second.
      var answeredNow = function(feed, symbol) { return !!feed.entries[symbol] && feed.entries[symbol].at === service.now }
      service.now += 60
      prints.fetch(["NEST", "SILK"], service.now)
      allDay.fetch(["SILK"], service.now)
      var answered = within(3000, function() { return answeredNow(prints, "SILK") && answeredNow(allDay, "SILK") })
      service.removeSymbol("SILK")
      // A second removal: SILK's can no longer be undone.
      service.removeSymbol("REED")
      // Time for a prune that must not come yet.
      wait(50)
      var keptFresh = !!prints.entries.SILK && !!allDay.entries.SILK
      var leftAt = service.now
      for (var m = 1; m <= 6; m++) {
        service.now = leftAt + m * 60
        prints.fetch(["NEST"], service.now)
        answered = within(3000, function() { return answeredNow(prints, "NEST") }) && answered
      }
      var printsGone = !prints.entries.SILK && !!prints.entries.NEST
      var allDayKept = !!allDay.entries.SILK
      service.now = leftAt + 25 * 3600
      var allDayGone = within(1000, function() { return !allDay.entries.SILK })
      check("a symbol gone keeps Robinhood's prints five minutes and its all-day answer a day, then neither, with no edit",
        answered && keptFresh && printsGone && allDayKept && allDayGone,
        [answered, keptFresh, printsGone, allDayKept, allDayGone].join(","))

      // Robinhood answers 100 results a page.
      useSet("2026-10-07-0100")
      var hundred = []
      for (var h = 1; h <= 110; h++) hundred.push("LONG" + ("00" + h).slice(-3))
      var hundredFrom = harness.record("INSTRUMENTS.asked").split("\n").length
      service.now += 60
      // The clock's own ask out first: a feed with a request out sends none.
      within(3000, function() { return !allDay.busy })
      allDay.fetch(hundred, service.now)
      var hundredAnswered = within(5000, function() { return hundred.every(function(s) { return answeredNow(allDay, s) }) })
      var hundredAsked = harness.record("INSTRUMENTS.asked").split("\n").slice(hundredFrom).map(function(line) { return line.split(",").length })
      var notAllDay = hundred.filter(function(s) { return !allDay.entries[s] || !allDay.entries[s].allDay })
      check("110 US stocks asked of Robinhood's instruments, which pages at 100: every one is answered as trading all day",
        hundredAnswered && notAllDay.length === 0, "requests of " + hundredAsked.join(", ") + "; not all day: " + notAllDay.join(","))

      // 80 US stocks Robinhood trades all day, added with the window open.
      var longs = []
      for (var n = 1; n <= 80; n++) longs.push("LONG" + (n < 10 ? "0" : "") + n)
      var askedBefore = harness.record("OVERNIGHT.asked").split("\n").length
      longs.forEach(function(s) { service.addSymbol(s) })
      var nights = within(20000, function() {
        return service.arriving.length === 0 && longs.every(function(s) {
          return !!prints.entries[s] && prints.entries[s].status === "ok" && prints.entries[s].bars.length > 0
        })
      })
      var requests = harness.record("OVERNIGHT.asked").split("\n").slice(askedBefore).map(function(line) { return line.split(",") })
      var each = longs.filter(function(s) { return requests.filter(function(r) { return r.indexOf(s) >= 0 }).length === 1 })
      featureShown("LONG80")
      var drawn = body.featuredGeometry.start === harness.midnight.wed7
        && body.featuredDay.points.some(function(p) { return p.t < harness.midnight.wed7 + 4 * 3600 })
      check("80 all-day listings: their prints in requests of at most 25, each asked once, and every one's night drawn",
        nights && requests.every(function(r) { return r.length <= 25 }) && each.length === 80 && drawn,
        "requests of " + requests.map(function(r) { return r.length }).join(", ") + "; " + each.length + " asked once; nights "
          + nights + "; LONG80 drawn " + drawn)

      // Thursday 23:00, a trading night, Robinhood refusing the list's
      // refresh, four requests now.
      var thursdayNight = harness.midnight.thu8 + 23 * 3600
      runCommand(["touch", harness.state + "/ROBINHOOD.refuse"])
      service.now = thursdayNight
      var refused = within(3000, function() { return service.testRobinhoodGate.pause === "refused" && !prints.busy })
      runCommand(["rm", "-f", harness.state + "/ROBINHOOD.refuse"])
      var probedFrom = harness.record("OVERNIGHT.asked").split("\n").length
      service.now = thursdayNight + 5 * 60 + 5
      var caughtUp = within(5000, function() {
        return longs.every(function(s) { return prints.entries[s].status === "ok" && prints.entries[s].at > thursdayNight })
      })
      var afterProbe = harness.record("OVERNIGHT.asked").split("\n").slice(probedFrom).map(function(line) { return line.split(",").length })
      check("a trading night, Robinhood back after a refusal: its first probe lets one request go alone, and the rest goes once that reopens it",
        refused && caughtUp && afterProbe.length > 2 && afterProbe[0] === 25,
        "refused " + refused + "; requests after the pause of " + afterProbe.join(", ") + "; every night refreshed " + caughtUp)

      // Friday 23 October at 06:00: NVDA's chart is Friday from midnight,
      // its night and pre-market, which its quote holds after Thursday.
      useSet("night-2026-10-23-0600")
      service.now = 1792749600
      service.addSymbol("NVDA")
      within(8000, function() { return !!service.quotes.NVDA && service.arriving.length === 0 })
      featureShown("NVDA")
      within(5000, function() { return body.chartSymbol === "NVDA" && !body.chartLoading && body.featuredGeometry.start === 1792728000
        && harness.strip().indexOf("PRE-MARKET") === 0 })
      scrubAt(1.003)
      var rowsAt = body.watchlistScrubShown
      var rowView = Figures.rowModel(service.quotes.NVDA, rowsAt, service.changeMode)
      var rowFollows = rowsAt === body.scrubShown && rowsAt >= 1792742400
        && rowView.priceText === body.featured.priceText && rowView.changeText === body.featured.changeText
      var rowRead = rowsAt + " vs " + body.scrubShown + ": " + rowView.priceText + " " + rowView.changeText + " vs " + body.featured.priceText + " " + body.featured.changeText
      endScrub()
      check("Friday 06:00: NVDA's row follows its scrub into the pre-market",
        rowFollows, rowRead)

      // Every request of the run, Robinhood's instruments' too.
      var never = ["^GSPC", "BTC-USD", "SHOP.TO"]
      var strays = harness.asked("OVERNIGHT.asked").concat(harness.asked("INSTRUMENTS.asked"))
        .filter(function(s) { return never.indexOf(s) >= 0 })
      check("Robinhood is asked for a day, for the stocks on US exchanges only: never the index, the cryptocurrency, or the Toronto listing",
        openAsked === "2 calls for NEST,REED,SILK, day" && strays.length === 0,
        openAsked + " | asked for " + strays.join(","))
      finish()
    }
  }
}
