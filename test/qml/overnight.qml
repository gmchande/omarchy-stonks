import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks
import "plugin/Cells.js" as Cells
import "plugin/Chart.js" as Chart
import "plugin/Format.js" as Format
// Overnight prices through the real Service, its feeds, and the App window,
// on a clock this harness sets, moving forward. The fake curl answers Yahoo
// and Robinhood from test/fixtures/moments, one saved moment at a time:
// Saturday 26 September at noon, Sunday night at 22:30, Monday at 04:11 and
// 08:00, then Thursday 1 October at 23:00, the first live night, Monday
// 5 October at 00:36, and a night held open across midnight: Tuesday
// 6 October at 23:00, Wednesday at 00:05, 01:00, 06:00, 11:53, and 14:55,
// New York time; at 01:00 and 14:55 the listing sweep's saved answers too,
// with Robinhood's word on which listings it trades all day; and a thin
// stock's day on Wednesday 21 October at 10:06. The library holds three US
// stocks, an index, a cryptocurrency, and a Toronto listing; KILN, BOLT,
// SPY, and VANE join it there.
ShellRoot {
  id: harness

  property int failures: 0
  readonly property int saturday: 1790438400
  readonly property int sunday: 1790562600
  readonly property int monday: 1790596800
  readonly property int night: 1790910000
  readonly property int live: 1791175013
  // Midnight in New York: Friday 25 September, Saturday 26, Monday 28,
  // Thursday 1 October, Friday 2, Tuesday 6, Wednesday 7, Thursday 8.
  readonly property var midnight: ({ fri25: 1790308800, sat26: 1790395200, mon28: 1790568000, thu1: 1790827200,
    fri2: 1790913600, tue6: 1791259200, wed7: 1791345600, thu8: 1791432000 })
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  // A fake curl record, read through a fresh view: a FileView that has
  // loaded once returns its old text straight after reload().
  function record(name) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = harness.state + "/" + name
    var text = String(view.text() || "").trim()
    view.destroy()
    return text
  }

  // Every symbol Robinhood was asked for, once each, sorted.
  function asked() {
    var seen = []
    harness.record("OVERNIGHT.asked").split(/[\n,]/).forEach(function(s) {
      if (s && seen.indexOf(s) < 0) seen.push(s)
    })
    return seen.sort().join(",")
  }

  // How many requests to Robinhood's instruments named `symbol`.
  function allDayAsked(symbol) {
    return harness.record("INSTRUMENTS.asked").split("\n").filter(function(line) {
      return line.split(",").indexOf(symbol) >= 0
    }).length
  }

  // How many requests for Robinhood's prints named `symbol`.
  function printsAsked(symbol) {
    return harness.record("OVERNIGHT.asked").split("\n").filter(function(line) {
      return line.split(",").indexOf(symbol) >= 0
    }).length
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

  // How the header's animal is drawn, the same cells in both looks:
  // "asleep", its eyes shut and the "z" shown, "awake", eyes open and no
  // "z", else how far its lids are down and whether the "z" shows. A "z"
  // reaching past the header's box is cut off: the popup's body starts at
  // the header's top and clips what draws above it.
  function sleep() {
    var body = app.testBody
    var header = find(body, "animal").parent
    var mark = find(header, "sleepCells")
    var z = mark.visible
    var whole = mark.y >= 0 && mark.y + mark.height <= header.height
    var bull = body.animal.kind === "bull"
    var drawn = JSON.stringify(find(header, bull ? "bullCells" : "bearCells").pixels)
    var lids = [0, 1, 2].filter(function(l) { return drawn === JSON.stringify(Cells.spriteFor(bull, l)) })[0] / 2
    return lids === 1 && z && whole ? "asleep" : lids === 0 && !z ? "awake"
      : "lids " + lids + ", z " + z + (whole ? "" : " at " + mark.y + " to " + (mark.y + mark.height) + " of the header's " + header.height)
  }

  // The line under the price as drawn: its words, "dim" when every one of
  // them, price and change too, is drawn in the dim colour, and "faded"
  // when the line is drawn at less than full ink, which an old print never
  // is: faded, its words fell to 2.1:1 (design pass 3).
  function strip() {
    var row = find(app.testBody, "extendedLine")
    if (!row || !row.visible) return ""
    var dim = String(app.testBody.dim)
    var words = []
    var allDim = true
    for (var i = 0; i < row.children.length; i++) {
      var child = row.children[i]
      if (!child.visible || !child.text) continue
      words.push(child.text)
      if (String(child.color) !== dim) allDim = false
    }
    return words.join(" ") + (allDim ? " dim" : "") + (row.opacity < 1 ? " faded" : "")
  }

  function findAll(item, name, out) {
    if (!item) return out
    if (item.objectName === name) out.push(item)
    for (var i = 0; i < item.children.length; i++) findAll(item.children[i], name, out)
    return out
  }

  // The hero chart's ink at the print at `fraction` along it, in the look
  // shown: the most opaque pixel around it, smooth's line or retro's cap (0
  // when nothing is drawn there), how many pixels wide the ink is across
  // the print's row, seven either side of it, and the ink a row of cells, or
  // six pixels, under it.
  function inkAt(fraction) {
    var canvas = findAll(app.testBody, "ink", []).filter(function(c) { return c.visible })[0]
    var chart = canvas.parent.parent
    var x, y
    if (chart.grid) {
      var g = chart.grid
      var column = Math.min(g.columns - 1, Math.floor(fraction * g.columns))
      if (g.levels[column] === undefined) return { alpha: 0, width: 0 }
      x = column * g.pitch + chart.pixel / 2
      y = g.levels[column] * chart.pixel + chart.pixel / 2
    } else {
      var w = canvas.width - chart.pad * 2
      var h = canvas.height - chart.pad * 2
      x = chart.pad + fraction * w
      y = chart.pad + Chart.yAt(app.testBody.featuredGeometry.points, fraction) * h
    }
    var ctx = canvas.getContext("2d")
    var data = ctx.getImageData(Math.round(x) - 1, Math.round(y) - 1, 3, 3).data
    var most = 0
    for (var i = 3; i < data.length; i += 4) most = Math.max(most, data[i])
    var row = ctx.getImageData(Math.round(x) - 7, Math.round(y), 15, 1).data
    var width = 0
    for (var j = 3; j < row.length; j += 4) if (row[j] > 0) width++
    var under = ctx.getImageData(Math.round(x), Math.round(y + (chart.grid ? chart.pixel * 1.5 : 6)), 1, 1).data[3]
    return { alpha: most, width: width, cell: chart.grid ? chart.pixel : 0, under: under }
  }

  // The hero's retro chart, shown.
  function retroChart() {
    return findAll(app.testBody, "curtain", []).filter(function(c) { return c.parent.visible })[0].parent
  }

  function finish() {
    console.log("OVERNIGHT DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }

  Process { id: setProc }

  TestCase {
    name: "Overnight"
    when: service.pluginsReady

    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 50) wait(50)
      return fn()
    }

    function featureShown(symbol) {
      service.feature(symbol)
      return within(3000, function() {
        var body = app.testBody
        return body.chartSymbol === symbol && !body.chartLoading && body.motion.reveal === 1
      })
    }

    // Points the fake curl at another saved moment.
    function useSet(name) {
      setProc.command = ["sh", "-c", "echo \"$1\" > \"$2\"", "--", name, harness.state + "/overnight.set"]
      setProc.running = true
      tryVerify(function() { return !setProc.running }, 2000)
    }

    function runCommand(command) {
      setProc.command = command
      setProc.running = true
      tryVerify(function() { return !setProc.running }, 2000)
    }

    // A pointer over the 1D chart at `fraction` of its width, as a scrub.
    function scrubAt(fraction) {
      var chart = app.testBody.chartItem
      mouseMove(chart, 3 + fraction * (chart.width - 6), chart.height / 2)
      wait(50)
    }

    function endScrub() {
      mouseMove(app.testBody.chartItem, -20, -20)
      app.testBody.motion.clearScrub()
    }

    // The retro hero's clip at every moment of a replay of the chart on
    // show: the replay draws the chart in behind its scrub, in the plot's
    // own whole columns, so the clip reaches the scrub's column, its edge at
    // least, and shows no column of ink right of it. `ahead` and `behind`
    // name the moments that miss.
    function replayClip() {
      var body = app.testBody
      var pixelChart = harness.findAll(body, "curtain", []).filter(function(c) { return c.parent.visible })[0].parent
      var curtain = harness.find(pixelChart, "curtain")
      var seen = { moments: 0, ahead: [], behind: [] }
      var watch = function() {
        if (!body.motion.replayRunning || pixelChart.scrubColumn < 0) return
        seen.moments++
        var shown = Math.round(curtain.width / pixelChart.grid.pitch)
        var at = body.headerText.replace("At ", "") + ": " + shown + " columns shown, scrub's " + pixelChart.scrubColumn
        if (shown < pixelChart.scrubColumn) seen.behind.push(at)
        for (var c = pixelChart.scrubColumn + 1; c < shown; c++) {
          if (pixelChart.grid.levels[c] !== undefined) {
            seen.ahead.push(at)
            break
          }
        }
      }
      curtain.widthChanged.connect(watch)
      pixelChart.scrubColumnChanged.connect(watch)
      body.replay()
      within(4000, function() { return !body.motion.replayRunning })
      curtain.widthChanged.disconnect(watch)
      pixelChart.scrubColumnChanged.disconnect(watch)
      return seen
    }

    // The latest span Robinhood was asked for.
    function lastSpan() {
      var spans = harness.record("OVERNIGHT.spans").split("\n")
      return spans[spans.length - 1]
    }

    // The featured 1D chart's day: where its axis starts and ends.
    function dayAxis() {
      return Chart.chartSpan(app.testBody.featuredDay)
    }

    function test_overnight() {
      service.now = harness.saturday
      var all = ["NEST", "SILK", "REED", "^GSPC", "BTC-USD", "SHOP.TO"]
      within(8000, function() { return all.every(function(s) { return !!service.quotes[s] }) })
      // With nothing open, the pill's first live answer asks Robinhood both
      // its questions for it, side by side: overnight.sh holds Robinhood's
      // answers from the start, so both are out before either answers.
      var bothOut = within(5000, function() {
        return harness.record("INSTRUMENTS.calls") === "1" && harness.record("OVERNIGHT.calls") === "1"
      })
      harness.check("with nothing open, the pill's first live answer asks Robinhood whether it trades it all day and for its prints at once, for it alone",
        bothOut && harness.record("INSTRUMENTS.asked") === "NEST" && harness.record("OVERNIGHT.asked") === "NEST",
        harness.record("INSTRUMENTS.asked") + " | " + harness.record("OVERNIGHT.asked"))
      runCommand(["rm", "-f", harness.state + "/ROBINHOOD.hold"])
      within(3000, function() { return !!service.testAllDayFeed.entries.NEST && !!service.testOvernightFeed.entries.NEST })
      service.now += 5 * 60
      wait(300)
      service.now += 5 * 60
      wait(300)
      harness.check("with nothing open, Robinhood is asked once, and never again",
        harness.record("INSTRUMENTS.calls") === "1" && harness.record("OVERNIGHT.calls") === "1",
        harness.record("INSTRUMENTS.calls") + ", " + harness.record("OVERNIGHT.calls"))

      // Saturday noon, after Friday 25 September. The first open finds the
      // pill's chart in hand, and asks for the rest of the list's two
      // answers side by side.
      service.now = harness.saturday
      runCommand(["touch", harness.state + "/ROBINHOOD.hold"])
      app.open("{}")
      var body = app.testBody
      var firstFrame = body.chartSymbol + (body.chartLoading ? " loading" : "")
      var restOut = within(5000, function() {
        return harness.record("INSTRUMENTS.calls") === "2" && harness.record("OVERNIGHT.calls") === "2"
      })
      runCommand(["rm", "-f", harness.state + "/ROBINHOOD.hold"])
      harness.check("a window opened after them shows the pill's 1D chart at once", firstFrame === "NEST", firstFrame)
      harness.check("the first open asks for the rest's instruments and prints together: both out before either answers",
        restOut && harness.record("INSTRUMENTS.asked").split("\n")[1] === "SILK,REED"
          && harness.record("OVERNIGHT.asked").split("\n")[1] === "SILK,REED",
        harness.record("INSTRUMENTS.asked") + " | " + harness.record("OVERNIGHT.asked"))
      harness.check("the window's 1D chart lands once Robinhood has answered", featureShown("NEST"))
      harness.check("Robinhood is asked for a day, for the stocks on US exchanges only: never the index, the cryptocurrency, or the Toronto listing",
        harness.record("OVERNIGHT.calls") === "2" && harness.asked() === "NEST,REED,SILK" && lastSpan() === "day",
        harness.record("OVERNIGHT.calls") + " calls for " + harness.asked() + ", " + lastSpan())
      within(3000, function() { return harness.strip().indexOf("AFTER HOURS") === 0 })
      harness.check("Saturday noon: no session Friday night, so Friday's after-hours is the line",
        harness.strip() === "AFTER HOURS 238.22 +0.38%", harness.strip())
      var friday = body.featuredGeometry
      harness.check("and the chart is Friday, midnight to midnight, its last print at 19:55 and the evening empty",
        friday.start === harness.midnight.fri25 && friday.end === harness.midnight.sat26
          && body.motion.scrubEnd === 1790380500,
        friday.start + " to " + friday.end + ", last " + body.motion.scrubEnd)
      // Saturday noon, the header's animal sleeps; the cryptocurrency's
      // never does.
      var saturdayNest = harness.sleep()
      featureShown("BTC-USD")
      var saturdayBtc = harness.sleep()
      featureShown("NEST")
      harness.check("Saturday noon: NEST's animal sleeps, BTC-USD's never does",
        saturdayNest === "asleep" && saturdayBtc === "awake", saturdayNest + ", " + saturdayBtc)
      service.now = 1790388000
      harness.check("Friday 22:00 reads the same", harness.strip() === "AFTER HOURS 238.22 +0.38%", harness.strip())
      var calls = harness.record("OVERNIGHT.calls")
      service.now = harness.saturday + 30 * 60
      wait(300)
      service.now = 1790388000 + 30 * 60
      wait(300)
      harness.check("with the surface open on Friday night and Saturday, Robinhood is not asked again",
        harness.record("OVERNIGHT.calls") === calls, calls + " then " + harness.record("OVERNIGHT.calls"))

      // r asks Robinhood again for the chart on show alone: no row draws
      // its prints. It asked for every listing Robinhood trades all day.
      service.now = harness.saturday + 40 * 60
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_R)
      var rAsked = within(2000, function() { return Number(harness.record("OVERNIGHT.calls")) === Number(calls) + 1 })
      var rListings = harness.record("OVERNIGHT.asked").split("\n").filter(function(l) { return l !== "" }).pop()
      harness.check("r asks Robinhood for the chart on show alone, never the rows",
        rAsked && body.chartSymbol === "NEST" && rListings === "NEST", harness.record("OVERNIGHT.calls") + " calls, the last for " + rListings)
      calls = harness.record("OVERNIGHT.calls")

      // Sunday 22:30, the week's first night, Yahoo's day still Friday's:
      // the open surface asks again by itself, and five minutes on, again.
      useSet("sunday")
      service.now = harness.sunday
      within(3000, function() { return harness.strip().indexOf("OVERNIGHT") === 0 })
      harness.check("Sunday night trades, measured from Friday's close",
        harness.strip() === "OVERNIGHT 22:20 234.84 \u22121.05%" && body.featured.priceText === "237.33",
        harness.strip() + " | " + body.featured.priceText)
      harness.check("Sunday 22:30, its night trading, NEST's animal is awake", harness.sleep() === "awake", harness.sleep())
      // The header names the session the line under the price names: it
      // said "Weekend" over OVERNIGHT.
      harness.check("Sunday 22:30, its night trading, NEST's header says Overnight, as the line under its price does",
        body.headerText === "Overnight · opens Mon 09:30", body.headerText)
      // The chart stays on Friday (provisional: Sunday's captures settle
      // it), Thursday night's prints at its left edge, which a scrub reads,
      // never the previous close.
      var sundayChart = body.featuredGeometry
      scrubAt(0.03)
      var sundayScrub = body.headerText + " | " + body.featured.priceText
      endScrub()
      harness.check("on Sunday night the chart is still Friday's, and a scrub at its left edge reads Thursday night's print",
        sundayChart.start === harness.midnight.fri25 && sundayChart.end === harness.midnight.sat26
          && sundayScrub.indexOf("At 00:") === 0 && sundayScrub.indexOf("Overnight") > 0 && body.featured.priceText === "237.33"
          && sundayScrub.indexOf("| 243.48") < 0 && lastSpan() === "day",
        sundayScrub + " | " + sundayChart.start + " to " + sundayChart.end + ", " + lastSpan())
      var sundayCalls = Number(harness.record("OVERNIGHT.calls"))
      service.now = harness.sunday + 5 * 60
      within(2000, function() { return Number(harness.record("OVERNIGHT.calls")) > sundayCalls })
      harness.check("while a night trades, the open surface asks every five minutes, for a day",
        Number(calls) + 1 === sundayCalls && Number(harness.record("OVERNIGHT.calls")) === sundayCalls + 1 && lastSpan() === "day"
          && body.featuredGeometry.start === harness.midnight.fri25,
        calls + ", " + sundayCalls + ", " + harness.record("OVERNIGHT.calls") + " " + lastSpan())

      // Monday 04:11, the night's last bars due, and Robinhood down: the
      // last good prints stay, and once it is back, the open surface asks
      // again by itself five minutes on, outside any night.
      var feed = service.testOvernightFeed
      runCommand(["touch", harness.state + "/OVERNIGHT.down"])
      var before = Number(harness.record("OVERNIGHT.calls"))
      service.now = 1790583060
      within(2000, function() { return feed.entries.NEST.status === "failed" })
      var keptLine = harness.strip()
      runCommand(["rm", "-f", harness.state + "/OVERNIGHT.down"])
      service.now = 1790583060 + 2 * 60
      wait(300)
      var paced = Number(harness.record("OVERNIGHT.calls"))
      service.now = 1790583060 + 6 * 60
      within(2000, function() { return feed.entries.NEST.status === "ok" })
      harness.check("a failed answer keeps the last good prints, and is asked again five minutes on until it answers",
        keptLine.indexOf("OVERNIGHT 22:20") === 0 && paced === before + 1 && feed.entries.NEST.status === "ok"
          && Number(harness.record("OVERNIGHT.calls")) === before + 2,
        keptLine + " | " + before + ", " + paced + ", " + harness.record("OVERNIGHT.calls") + " " + feed.entries.NEST.status)

      // Robinhood refusing pauses Robinhood alone: r's request for its prints
      // meets a 429, and its gate holds the next r's; Yahoo's quotes go on,
      // and the prints already in stay. Back, its next request is answered.
      var line = harness.strip()
      runCommand(["touch", harness.state + "/ROBINHOOD.refuse"])
      service.now = 1790583060 + 12 * 60
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_R)
      within(2000, function() { return service.testRobinhoodGate.pause === "refused" })
      var quotesBefore = harness.record("requests.log").split("\n").filter(function(l) { return /^(chart|spark) /.test(l) }).length
      service.now += 20
      keyClick(Qt.Key_R)
      wait(500)
      var refusedCalls = Number(harness.record("ROBINHOOD.refused.calls"))
      var quotesAfter = harness.record("requests.log").split("\n").filter(function(l) { return /^(chart|spark) /.test(l) }).length
      harness.check("a Robinhood refusal pauses Robinhood alone: one request refused, the next held, Yahoo's quotes still asked, the prints kept",
        service.testRobinhoodGate.pause === "refused" && refusedCalls === 1 && service.testYahooGate.pause === ""
          && quotesAfter > quotesBefore && harness.strip() === line,
        [service.testRobinhoodGate.pause, refusedCalls, service.testYahooGate.pause, quotesBefore + " → " + quotesAfter, line + " → " + harness.strip()].join(" | "))
      runCommand(["rm", "-f", harness.state + "/ROBINHOOD.refuse"])
      service.now += 5 * 60
      within(2000, function() { return feed.entries.NEST.status === "ok" && service.testRobinhoodGate.pause === "" })
      harness.check("Robinhood back: its next request, five minutes on, is answered and reopens it",
        feed.entries.NEST.status === "ok" && service.testRobinhoodGate.pause === "",
        [feed.entries.NEST.status, service.testRobinhoodGate.pause, service.testRobinhoodGate.pausedUntil - service.now, service.testRobinhoodGate.probing,
          harness.record("ROBINHOOD.refused.calls"), harness.record("OVERNIGHT.calls"), feed.askedAt - service.now].join(" | "))

      // Monday 08:00, pre-market: Yahoo's day is Monday's, and the chart is
      // Monday from midnight, Sunday night's prints after it.
      useSet("monday")
      service.now = harness.monday
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_R)
      // Robinhood's answer for Monday in too: until it lands the chart holds
      // the last prints, and a scrub reads Yahoo's morning, not the night.
      within(5000, function() {
        return body.featuredQuote && body.featuredQuote.session.regular.start === 1790602200 && !body.chartLoading
          && service.testOvernightFeed.askedAt === harness.monday && !service.testOvernightFeed.busy
      })
      var mondayChart = body.featuredGeometry
      scrubAt(0.1)
      var mondayScrub = body.headerText + " | " + body.featured.priceText
      endScrub()
      harness.check("Monday 08:00: the chart is Monday from midnight, and a scrub at 02:24 reads the night's print against Friday's close",
        lastSpan() === "day" && mondayChart.start === harness.midnight.mon28 && mondayChart.end === harness.midnight.mon28 + 86400
          && mondayScrub.indexOf("At 02:") === 0 && mondayScrub.indexOf("Overnight") > 0 && mondayScrub.indexOf("| 237.33") < 0,
        mondayScrub + " | " + mondayChart.start + " to " + mondayChart.end + ", " + lastSpan())

      // Thursday 1 October, 23:00, the night after Thursday's close.
      useSet("night")
      service.now = harness.night
      keyClick(Qt.Key_R)
      // Every saved day of the night in, so the breadth is the night's.
      within(5000, function() {
        return body.featured && body.featured.priceText === "232.28" && !body.chartLoading
          && ["SILK", "REED", "^GSPC"].every(function(s) {
            return service.quotes[s].session.regular.start === service.quotes.NEST.session.regular.start
          })
      })
      within(3000, function() { return harness.strip().indexOf("OVERNIGHT") === 0 })
      var geometry = body.featuredGeometry
      harness.check("NEST's 1D is Thursday, midnight to midnight, with ticks at the night's end, the close, and tonight's start",
        geometry.start === harness.midnight.thu1 && geometry.end === harness.midnight.fri2 && geometry.ticks.length === 3
          && lastSpan() === "day",
        geometry.start + " to " + geometry.end + ", " + geometry.ticks.length + " ticks, " + lastSpan())
      harness.check("the overnight print is its own line under the price, with its time, measured from the close",
        harness.strip() === "OVERNIGHT 22:50 234.27 +0.86%", harness.strip())
      var info = body.dayLine
      harness.check("it is never the headline, nor in the day's high: the night's 243.20 leaves Thursday's 239.63",
        body.featured.priceText === "232.28" && !!info && info.range.highText === "239.63", body.featured.priceText + " | " + JSON.stringify(info))

      // A scrub of the night moves the hero and the header, never the rows
      // or the breadth, which show the day.
      var row = body.watchlist.rowItem("NEST")
      var breadth = JSON.stringify(body.breadth)
      scrubAt(Chart.fractionAtTime(body.featuredDay, harness.night - 90 * 60))
      var nightScrub = body.headerText + " | " + body.featured.priceText + " | row " + row.view.priceText + " | " + JSON.stringify(body.breadth)
      var heroMoved = body.featured.priceText !== "232.28"
      var rowsStill = row.view.priceText === "232.28" && JSON.stringify(body.breadth) === breadth
      endScrub()
      harness.check("a scrub of the night reads the night on the hero, and leaves the rows and the breadth on now",
        nightScrub.indexOf("At 21:") === 0 && heroMoved && rowsStill, nightScrub + " vs " + breadth)

      service.now = harness.night + 11 * 60
      harness.check("twenty minutes on with nothing newer, the print dims", harness.strip() === "OVERNIGHT 22:50 234.27 +0.86% dim",
        harness.strip())
      service.now = harness.night

      featureShown("SILK")
      harness.check("SILK's last print, at 22:20, is forty minutes old and dim", harness.strip() === "OVERNIGHT 22:20 342.13 +0.04% dim",
        harness.strip())
      // SILK traded in 13 of the night's 35 five-minute slots so far: its 1D
      // is Thursday's day from 04:00, then the night to Friday 04:00, each of
      // its trades a dot where the clock puts it, joined to nothing. NEST,
      // which traded in every one, keeps its calendar day, midnight to
      // midnight (`geometry`, above). On dev it was Thursday midnight to
      // midnight, its night a line run on through the quiet slots.
      var silkNight = body.featuredGeometry
      var silkDay = body.featuredDay
      var dayStart = harness.midnight.thu1 + 4 * 3600
      var silkDots = silkNight.points.filter(function(p) { return p.dot })
      var dotsByClock = silkDay.points.every(function(p, k) {
        var g = silkNight.points[k]
        return g.dot === (p.t >= harness.midnight.thu1 + 20 * 3600) && (!g.dot || (g.brk && Math.abs(g.x - (p.t - dayStart) / 86400) < 1e-9))
      })
      harness.check("SILK's thin night: Thursday's day from 04:00, then its 13 trades as dots by the clock to 04:00; NEST's night, traded through, stays midnight to midnight",
        silkNight.start === dayStart && silkNight.end === harness.midnight.fri2 + 4 * 3600 && silkDots.length === 13 && dotsByClock
          && geometry.start === harness.midnight.thu1 && geometry.end === harness.midnight.fri2,
        silkNight.start + " to " + silkNight.end + ", " + silkDots.length + " dots, by the clock " + dotsByClock + " | NEST " + geometry.start + " to " + geometry.end)
      featureShown("REED")
      var reed = body.featuredGeometry
      harness.check("REED has not traded tonight: no overnight line, its after-hours stays, and its chart is Thursday's day, its night empty",
        harness.strip() === "AFTER HOURS 21.50 +0.84%" && reed.start === dayStart && reed.end === harness.midnight.fri2 + 4 * 3600
          && !reed.points.some(function(p) { return p.dot }),
        harness.strip() + " | " + reed.start + " to " + reed.end)

      // Search's choice on the hero: a symbol in All shows its chart as it
      // does featured, SILK's thin night; one not yet added keeps its
      // session day, and Robinhood is never asked for it.
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_A)
      within(2000, function() { return body.adding })
      body.previewTo("SILK")
      within(3000, function() { return body.chartSymbol === "SILK" && !body.chartLoading && body.motion.reveal === 1 })
      var listed = body.featuredGeometry
      body.previewTo("AAPL")
      within(4000, function() { return body.chartSymbol === "AAPL" && !body.chartLoading && body.motion.reveal === 1 })
      var unadded = body.featuredGeometry
      var unaddedLast = unadded.points.length - 1
      var unaddedEven = unadded.points.every(function(p, k) { return Math.abs(p.x - unadded.points[unaddedLast].x * k / unaddedLast) < 1e-9 })
      harness.check("search's preview of a symbol in All shows its chart as featured; one not yet added, a US stock, draws Yahoo's own day, 04:00 to 20:00, a print a step, never asked of Robinhood",
        body.adding && listed.start === silkNight.start && listed.end === silkNight.end && listed.points.length === silkNight.points.length && body.chartSymbol === "AAPL"
          && unadded.end - unadded.start === 16 * 3600 && unaddedEven && harness.asked() === "NEST,REED,SILK"
          && harness.allDayAsked("AAPL") === 0,
        body.chartSymbol + " | " + (listed.end - listed.start) + " s, " + (unadded.end - unadded.start) + " s, even " + unaddedEven
          + " | asked " + harness.asked() + ", all-day asked " + harness.allDayAsked("AAPL"))
      body.cancelAdding()
      within(3000, function() { return !body.adding && body.chartSymbol === "REED" && !body.chartLoading })
      featureShown("^GSPC")
      var index = body.featuredGeometry
      harness.check("an index has no overnight: never asked for, no line, and its 1D is its session",
        harness.strip() === "" && index.end - index.start < 8 * 3600 && harness.asked() === "NEST,REED,SILK",
        harness.strip() + " | " + (index.end - index.start) + " s | asked " + harness.asked())
      featureShown("BTC-USD")
      harness.check("a cryptocurrency has no overnight: never asked for, and no line",
        harness.strip().indexOf("OVERNIGHT") < 0 && harness.asked() === "NEST,REED,SILK", harness.strip() + " | asked " + harness.asked())

      // After the close, a scrub to the day's end reads the close the hero
      // shows at rest, at its time; the after-hours reads its own prints.
      // On dev, ^GSPC's right edge read "At 15:55" at 7,668.82, its last
      // bar, and SILK's last regular print 341.89. Found by the PM: "AT
      // 15:55 · CLOSING BELL" at 7,811.09 against a 7,811.54 close.
      featureShown("^GSPC")
      var indexRest = body.featured.priceText
      scrubAt(1)
      var indexEnd = body.headerText + " | " + body.featured.priceText
      endScrub()
      featureShown("SILK")
      var silkRest = body.featured.priceText
      var silk = body.featuredDay
      var bell = silk.points.findIndex(function(p) { return p.t >= silk.session.regular.end })
      var readAt = function(k) {
        body.motion.scrubT = silk.points[k].t
        var read = body.headerText + " | " + body.featured.priceText
        endScrub()
        return read
      }
      var silkClose = readAt(bell - 1)
      // The first after-hours print whose price is not the close's, so
      // reading the close there would show.
      var off = bell
      while (Format.money(silk.points[off].p, silk.priceDigits) === silkRest) off++
      var offText = Format.money(silk.points[off].p, silk.priceDigits)
      var silkAfter = readAt(off)
      harness.check("Saturday: a scrub to the index's right edge, or to a stock's last regular print, reads the close at 16:00; its after-hours reads its own print",
        indexEnd === "At 16:00 · Closing bell | " + indexRest && silkClose === "At 16:00 · Closing bell | " + silkRest
          && /^At \d\d:\d\d · After hours \| /.test(silkAfter) && silkAfter.split(" | ")[1] === offText,
        indexEnd + " ; " + silkClose + " ; " + silkAfter + " | at rest " + indexRest + ", " + silkRest + "; that print " + offText)

      // Monday 5 October, 00:36: the first live night, saved as it was. EZ
      // traded once since Sunday 20:00, at 22:40, and TOY five times, the
      // last at 00:20: both thin nights, so each chart is Friday's day from
      // 04:00, never blank, then the night's trades after it as dots, the
      // weekend between taking no room, and the line under the price names
      // the night. On dev, EZ drew Friday midnight to midnight and TOY its
      // one print after midnight, alone at the left edge of an empty Monday.
      useSet("live-2026-10-05")
      service.now = harness.live
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_R)
      service.addSymbol("EZ")
      service.addSymbol("TOY")
      within(8000, function() { return !!service.quotes.EZ && !!service.quotes.TOY && service.arriving.length === 0 })
      featureShown("EZ")
      within(3000, function() { return harness.strip().indexOf("OVERNIGHT") === 0 })
      var ezChart = body.featuredGeometry
      var ezDots = ezChart.points.filter(function(p) { return p.dot })
      harness.check("EZ, one trade since Sunday 20:00: Monday 00:36 shows Friday's day from 04:00 and that trade a dot after it, and the line names the night",
        ezChart.start === harness.midnight.fri2 + 4 * 3600 && ezChart.points.length > 1 && ezDots.length === 1
          && harness.strip() === "OVERNIGHT 22:40 19.71 \u22123.71% dim",
        ezChart.start + ", " + ezChart.points.length + " points, " + ezDots.length + " dots | " + harness.strip())
      var looks = [false, true]
      looks.forEach(function(retro) {
        if (service.retro !== retro) {
          app.testKeyCatcher.forceActiveFocus()
          keyClick(Qt.Key_S)
          within(2000, function() { return service.retro === retro })
        }
        var look = retro ? "retro" : "smooth"
        featureShown("TOY")
        var toy = body.featuredDay
        var offset = service.quotes.TOY.gmtoffset
        var trades = toy.points.filter(function(p) { return p.t >= harness.midnight.fri2 + 3 * 86400 - 4 * 3600 })
        // Smooth's dot is twice the line's width; retro's is a cell, as wide
        // as every other column's, with no column under it. A look just
        // switched paints on its next frame.
        var at = Chart.fractionAtTime(toy, 1791174000)
        within(2000, function() { return harness.inkAt(at).alpha > 0 })
        var ink = harness.inkAt(at)
        harness.check(look + ": TOY's five trades since Sunday 20:00 are dots after Friday's day; its 00:20 trade draws dim, "
          + (retro ? "a whole cell" : "twice the line's width") + ", with nothing under it",
          trades.length === 5 && body.featuredGeometry.points.filter(function(p) { return p.dot }).length === 5
            && ink.alpha > 0 && ink.alpha < 200 && ink.under === 0 && (retro ? ink.width >= ink.cell : ink.width >= 3 && ink.width <= 6),
          trades.length + " trades | alpha " + ink.alpha + ", " + ink.width + " px wide, " + ink.under + " under it")
        // Four minutes into its bar, a pixel or two at this width: the scrub
        // lands on the dot and says its time, and its move from Friday's
        // close, the line under the price's; the legend names both closes.
        // It read the move from Thursday's close, the dashed line's.
        var restLine = harness.strip().split(" ")
        scrubAt(Chart.fractionAtTime(toy, 1791174000 + 240))
        var legend = harness.find(body, "baselineLegend")
        var scrubbed = [body.headerText, body.featured.priceText, body.featured.changeText, legend.visible ? legend.text : ""].join(" | ")
        endScrub()
        harness.check(look + ": a scrub at TOY's 00:20 dot lands on it, says its time, reads its move from Friday's close as the line under the price does, and the legend says which close each part reads from",
          scrubbed === ["At 00:20 · Overnight", "322.00", "+0.38%", "┄ PREV CLOSE 323.09 · NIGHT FROM CLOSE 320.77"].join(" | ")
            && restLine.slice(0, 4).join(" ") === "OVERNIGHT 00:20 322.00 " + Format.lookSigns("+0.38%", retro),
          scrubbed + " | at rest " + restLine.join(" "))
        // The left edge and a replay's first moment read Friday's first print,
        // and the replay reads each of the night's trades on its way.
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
        var missed = trades.map(function(p) { return "At " + Format.hhmm(p.t, offset) + " · Overnight" })
          .filter(function(said) { return replayRead.indexOf(said) < 0 })
        harness.check(look + ": the left edge and a replay's first moment read Friday's first print, and the replay reads every one of the night's trades",
          edge.indexOf("At 04:") === 0 && replayed === "At 04:00 · Pre-market | 328.38" && missed.length === 0,
          edge + " ; " + replayed + " ; missed " + missed.join(", "))
      })

      // Still in retro, NEST's Monday from midnight to 00:30, its last print
      // early in its column: a replay draws in up to its scrub's column and
      // no further, never 00:30's column while the scrub reads 00:25, never
      // a column short of the scrub's.
      featureShown("NEST")
      var monday = replayClip()
      harness.check("retro: every moment of a replay of Monday's night reaches its scrub's column and shows no column of ink right of it",
        monday.moments >= 3 && monday.ahead.length === 0 && monday.behind.length === 0,
        monday.moments + " moments | ahead: " + monday.ahead.join(" ; ") + " | behind: " + monday.behind.join(" ; "))

      // On 1M, with its history in: the overnight
      // line shows at rest, rests while the history is scrubbed, where the
      // baseline's legend shows, and comes back when the scrub ends. In
      // retro, then smooth.
      featureShown("NEST")
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_BracketRight)
      keyClick(Qt.Key_BracketRight)
      within(5000, function() { return body.chartRange === "1M" && body.historyShown && !body.historyFailed && !body.chartLoading })
      looks.reverse().forEach(function(retro) {
        if (service.retro !== retro) {
          app.testKeyCatcher.forceActiveFocus()
          keyClick(Qt.Key_S)
          within(2000, function() { return service.retro === retro })
        }
        var look = retro ? "retro" : "smooth"
        var month = harness.strip()
        harness.check(look + ": on 1M, with its history in, the overnight line shows at rest",
          body.historyShown && !body.historyFailed && month === Format.lookSigns("OVERNIGHT 00:30 245.47 +1.10%", retro), month)
        scrubAt(0.5)
        var legend = harness.find(body, "baselineLegend")
        var scrubbedMonth = harness.strip() + " | " + (legend.visible ? legend.text : "")
        endScrub()
        harness.check(look + ": a 1M scrub rests the line, and the baseline's legend takes its place; the scrub's end brings it back",
          scrubbedMonth.indexOf(" | ┄ 1M START ") === 0 && harness.strip() === month, scrubbedMonth + " then " + harness.strip())
      })

      // A night held open across midnight, Tuesday 6 to Wednesday 7 October,
      // back on 1D: the chart stays on Tuesday until Wednesday's first print,
      // then turns to Wednesday, measured from Tuesday's close.
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_BracketLeft)
      keyClick(Qt.Key_BracketLeft)
      useSet("2026-10-06-2300")
      service.now = 1791342000
      service.refresh()
      within(8000, function() {
        return body.chartRange === "1D" && body.featuredQuote && body.featuredQuote.session.regular.start === 1791293400
          && !body.chartLoading && harness.strip().indexOf("OVERNIGHT 22:") === 0
      })
      var tuesday = body.featuredGeometry
      harness.check("Tuesday 23:00: the chart is Tuesday, midnight to midnight, its night since 20:00 at the right end",
        tuesday.start === harness.midnight.tue6 && tuesday.end === harness.midnight.wed7 && body.motion.scrubEnd >= 1791331200,
        tuesday.start + " to " + tuesday.end + ", last " + body.motion.scrubEnd + " | " + harness.strip())
      var asked = Number(harness.record("OVERNIGHT.calls"))
      useSet("2026-10-07-0005")
      service.now = 1791345900
      within(3000, function() { return Number(harness.record("OVERNIGHT.calls")) > asked && harness.strip().indexOf("OVERNIGHT 23:55") === 0 })
      var held = body.featuredGeometry
      harness.check("Wednesday 00:05, before its first print: the chart stays Tuesday's, midnight to midnight, never blank, and the line names 23:55",
        held.start === harness.midnight.tue6 && held.end === harness.midnight.wed7 && held.points.length > 0
          && harness.strip().indexOf("OVERNIGHT 23:55") === 0 && body.featured.priceText === "249.87",
        held.start + " to " + held.end + ", " + held.points.length + " points | " + harness.strip() + " | " + body.featured.priceText)
      useSet("2026-10-07-0100")
      service.now = 1791349200
      within(3000, function() { return body.featuredGeometry.start === harness.midnight.wed7 && harness.strip().indexOf("OVERNIGHT 00:") === 0 })
      var wednesday = body.featuredGeometry
      harness.check("Wednesday 01:00: the first prints after midnight turn the chart to Wednesday; the headline stays Tuesday's close and day",
        wednesday.start === harness.midnight.wed7 && wednesday.end === harness.midnight.thu8 && !body.chartLoading
          && body.featured.priceText === "249.87" && body.featured.changeText === "+7.44%",
        wednesday.start + " to " + wednesday.end + " | " + body.featured.priceText + " " + body.featured.changeText)
      // A scrub of the night reads it against Tuesday's close, as the line
      // under the price does, and names that close.
      var line = harness.strip().split(" ")
      scrubAt(1.003)
      var legend = harness.find(body, "baselineLegend")
      var nightRead = [body.headerText, body.featured.priceText, body.featured.changeText, legend.visible ? legend.text : ""].join(" | ")
      endScrub()
      harness.check("a scrub at Wednesday's last print reads its move from Tuesday's close, the line's move",
        nightRead === ["At " + line[1] + " · Overnight", line[2], line[3], "┄ PREV CLOSE 249.87"].join(" | "),
        nightRead + " vs " + line.join(" "))
      // As an amount, the line under the price says its move as one too, of
      // the same sign; since the open, it is the percent from the close it
      // was. Found in the edge-case pass of 15 October: the hero read
      // "+1.99" and the line under it still a percent.
      keyClick(Qt.Key_C)
      within(2000, function() { return service.changeMode === "abs" })
      var asAmount = harness.strip().split(" ")
      var amountSays = [asAmount.slice(0, 3).join(" ") === line.slice(0, 3).join(" "),
        /^[+\u2212]\d+\.\d\d$/.test(asAmount[3]), asAmount[3].charAt(0) === line[3].charAt(0)].join(",")
      keyClick(Qt.Key_C)
      within(2000, function() { return service.changeMode === "open" })
      harness.check("the line under the price follows c: an amount of the same sign as an amount, the percent from the close since the open",
        amountSays === "true,true,true" && harness.strip() === line.join(" "),
        line.join(" ") + " -> " + asAmount.join(" ") + " (" + amountSays + ") -> " + harness.strip())
      // Since the open, at rest, with the chart on Wednesday, the hero says
      // what its row says: Tuesday's open to its close.
      var nestRow = body.watchlist.rowItem("NEST")
      harness.check("since the open, at rest, with Wednesday's chart on show, the hero's change is Tuesday's, as its row's is",
        body.featuredGeometry.start === harness.midnight.wed7
          && body.featured.changeText === nestRow.view.changeText && body.featured.changeText !== "+7.44%",
        body.featuredGeometry.start + " | " + body.featured.changeText + " vs " + nestRow.view.changeText)
      // And from the open the info line shows, never from the first bar's
      // close: found in the 1.0.0 review, the demo AAPL read "−0.26% open"
      // beside OPEN 341.33 and a price of 342.79.
      var openShown = harness.find(body, "periodLine").line.facts[0]
      var openPrice = Number(openShown.value.replace(/,/g, ""))
      var priceShown = Number(body.featured.priceText.replace(/,/g, ""))
      var fromOpen = Format.pct((priceShown - openPrice) / openPrice * 100)
      harness.check("since the open, the hero's change is the move from the OPEN the info line shows",
        openShown.label === "OPEN" && openPrice > 0 && body.featured.changeText === fromOpen,
        "OPEN " + openShown.value + ", price " + body.featured.priceText + ": " + body.featured.changeText + " vs " + fromOpen)
      keyClick(Qt.Key_C)
      within(2000, function() { return service.changeMode === "pct" })
      // An answer without its regular price and time: the hero falls back
      // to Tuesday's last regular print, and the line under the price still
      // names the night, against that same close.
      // Robinhood can answer the clock step before the regular quote does.
      // Let that refresh land before replacing its quote with this case.
      var quoteAnswered = within(8000, function() {
        var entry = service.entries.NEST
        return entry && entry.status === "ok" && entry.answeredAt === service.now && !service.owed.NEST
      })
      var whole = service.testFeed.quotes
      var bare = Object.assign({}, whole)
      bare.NEST = Object.assign({}, whole.NEST, { price: null, marketTime: null })
      service.testFeed.quotes = bare
      within(2000, function() { return body.featured.priceText !== "249.87" })
      var fallback = body.featured.priceText + " | " + harness.find(body, "listingLine").text + " | " + harness.strip()
      var rowFallback = harness.find(nestRow, "rowDetail").text
      service.testFeed.quotes = whole
      within(2000, function() { return body.featured.priceText === "249.87" })
      harness.check("with no regular price, the hero labels its last chart trade with Tuesday's time and keeps the overnight line",
        quoteAnswered && fallback.indexOf("249.78 | LAST TRADE · TUE 15:55 · ") === 0
          && fallback.indexOf(" | OVERNIGHT 00:50 248.04 ") > 0
          && rowFallback === "Last trade · Tue 15:55", "quote answered: " + quoteAnswered + " | " + fallback + " | row: " + rowFallback)

      // Two US stocks Robinhood does not trade all day, saved with the
      // listing sweep at the same moment: KILN traded 2 shares at 23:10 on
      // Tuesday, and BOLT six times in the night, 1 to 622 shares. Neither
      // has an overnight line or a night on its chart: each draws Yahoo's own
      // day, Tuesday, 04:00 to 20:00, its prints from the left edge.
      // Robinhood is asked once whether it trades them all day, and for
      // their prints beside that, never again.
      useSet("listings-2026-10-07-0100")
      service.addSymbol("KILN")
      service.addSymbol("BOLT")
      within(8000, function() { return !!service.quotes.KILN && !!service.quotes.BOLT && service.arriving.length === 0 })
      var thin = ["KILN", "BOLT"].map(function(symbol) {
        featureShown(symbol)
        var g = body.featuredGeometry
        return { symbol: symbol, strip: harness.strip(), start: g.start, end: g.end, first: g.points.length ? g.points[0].x : -1 }
      })
      harness.check("01:00: KILN and BOLT, which Robinhood does not trade all day, have no overnight line from a stray night trade, and draw Tuesday 04:00 to 20:00 from the left edge",
        thin.every(function(t) {
          return t.strip.indexOf("OVERNIGHT") < 0 && t.start === harness.midnight.tue6 + 4 * 3600
            && t.end === harness.midnight.tue6 + 20 * 3600 && t.first === 0
        }),
        JSON.stringify(thin))
      harness.check("Robinhood is asked whether it trades KILN and BOLT all day, and their prints beside that, once",
        harness.allDayAsked("KILN") === 1 && harness.allDayAsked("BOLT") === 1 && harness.printsAsked("KILN") === 1
          && harness.printsAsked("BOLT") === 1,
        harness.allDayAsked("KILN") + ", " + harness.allDayAsked("BOLT") + " | prints " + harness.printsAsked("KILN") + ", " + harness.printsAsked("BOLT"))
      // The header's animal sleeps while its market does, by its phase and
      // calendar: at 01:00 NEST's night trades, so it's awake; KILN's
      // doesn't, so it sleeps, in both looks. A scrub wakes it, since it
      // reads a moment the market traded, and letting go puts it back to
      // sleep at once.
      var sleeps = []
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        within(2000, function() { return body.retro === (look === "retro") })
        featureShown("NEST")
        var nest = harness.sleep()
        featureShown("KILN")
        var kiln = harness.sleep()
        scrubAt(0.5)
        within(1000, function() { return body.scrubT !== 0 })
        var scrubbed = harness.sleep()
        endScrub()
        within(1000, function() { return body.scrubT === 0 })
        sleeps.push(look + ": NEST " + nest + ", KILN " + kiln + ", scrubbed " + scrubbed + ", let go " + harness.sleep())
      })
      service.persist({ style: "smooth" })
      harness.check("01:00: NEST, whose night trades, is awake; KILN sleeps, a scrub wakes it, and letting go puts it back to sleep at once, in both looks",
        sleeps.every(function(s) { return / NEST awake, KILN asleep, scrubbed awake, let go asleep$/.test(s) }), sleeps.join(" | "))
      // Its market waking while you watch, at 04:00 when KILN's pre-market
      // starts, opens the animal's eyes and takes the "z" away, in both
      // looks. They opened at once; now they open over the close's time, so
      // this reads where they end.
      var wakes = []
      featureShown("KILN")
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        within(2000, function() { return body.retro === (look === "retro") })
        service.now = harness.midnight.wed7 + 4 * 3600 - 2
        within(1000, function() { return harness.sleep() === "asleep" })
        var before = harness.sleep()
        service.now = harness.midnight.wed7 + 4 * 3600
        within(2000, function() { return harness.sleep() === "awake" })
        wakes.push(look + ": " + before + " to " + harness.sleep())
      })
      service.persist({ style: "smooth" })
      service.now = 1791349200
      harness.check("04:00: KILN's pre-market starting wakes its animal, eyes open and no \"z\", in both looks",
        wakes.every(function(w) { return / asleep to awake$/.test(w) }), wakes.join(" | "))
      // So does the header: NEST's says Overnight, as the line under its
      // price does, and KILN's Closed, with no such line. NEST's said Closed.
      featureShown("NEST")
      var nestHeader = body.headerText + " | " + harness.strip()
      featureShown("KILN")
      var kilnHeader = body.headerText + " | " + harness.strip()
      featureShown("NEST")
      harness.check("01:00: NEST's header says Overnight, as the line under its price does; KILN's says Closed",
        nestHeader.indexOf("Overnight · opens Wed 09:30 | OVERNIGHT ") === 0 && kilnHeader === "Closed · opens Wed 09:30 | ",
        nestHeader + " || " + kilnHeader)
      // An index trades only in its session: no pre-market before it, no
      // flat tail of its repeated close after it, and the header names its
      // next open from the US calendar. ^GSPC at 06:00 said "PRE-MARKET ·
      // OPENS IN 3H 30M"; at 01:00, Tuesday's line ran flat to 17:20 and
      // the header named no open.
      var indexRead = function() {
        featureShown("^GSPC")
        var quote = service.quotes["^GSPC"]
        var last = quote.points[quote.points.length - 1]
        return body.headerText + " | last print " + (last.t < quote.session.regular.end ? "in session" : "after the close")
      }
      service.refresh()
      within(8000, function() { return !!service.quotes["^GSPC"] && service.quotes["^GSPC"].session.regular.start === 1791293400 })
      var indexNight = indexRead()
      featureShown("NEST")
      // 06:00, pre-market: Yahoo's day is Wednesday's, the same close.
      useSet("2026-10-07-0600")
      service.now = 1791367200
      service.refresh()
      within(8000, function() { return body.featuredQuote.session.regular.start === 1791379800 && !body.chartLoading })
      scrubAt(0.1)
      var dawn = harness.find(body, "baselineLegend").text
      endScrub()
      harness.check("Wednesday 06:00: the chart is Wednesday, still measured from Tuesday's close",
        body.featuredGeometry.start === harness.midnight.wed7 && dawn === "┄ PREV CLOSE 249.87", body.featuredGeometry.start + " | " + dawn)
      var indexMorning = indexRead()
      featureShown("NEST")
      harness.check("an index has no pre-market and no tail after its close, and its header names the next open",
        indexNight === "Closed · opens Wed 09:30 | last print in session"
          && indexMorning === "Closed · opens Wed 09:30 | last print in session",
        indexNight + " || " + indexMorning)
      // 11:53, mid-session: midnight to midnight, the line ending at
      // now, about halfway, the rest of the day empty.
      useSet("2026-10-07-1153")
      service.now = 1791388380
      service.refresh()
      within(8000, function() { return body.featured.priceText === "236.19" && !body.chartLoading })
      var noon = body.featuredGeometry
      var lastX = noon.points[noon.points.length - 1].x
      harness.check("Wednesday 11:53: the day from midnight, its line ending about halfway, at now",
        noon.start === harness.midnight.wed7 && noon.end === harness.midnight.thu8 && lastX > 0.48 && lastX < 0.5,
        noon.start + " to " + noon.end + ", last x " + lastX)

      // 14:55, KILN, a thin stock: its line starts at the left edge and runs a
      // print a step to where the clock puts its newest print, the hours to
      // come by the clock; on the calendar day its first print stood at 40%.
      // The keys step print to print: from BOLT's first print, at 04:00,
      // three steps land on its fourth, at 05:40. Robinhood is not asked
      // again whether it trades them all day: its answer holds a day.
      useSet("listings-2026-10-07-1455")
      service.now = 1791399300
      service.refresh()
      within(8000, function() { return service.quotes.KILN.session.regular.start === 1791379800 && service.quotes.BOLT.session.regular.start === 1791379800 })
      featureShown("KILN")
      var kiln = body.featuredGeometry
      var last = kiln.points.length - 1
      var clockAt = (service.quotes.KILN.points[last].t - kiln.start) / (kiln.end - kiln.start)
      var even = kiln.points.every(function(p, k) { return Math.abs(p.x - clockAt * k / last) < 1e-9 })
      harness.check("14:55: KILN's line starts at the left edge and runs evenly, a print a step, to where the clock puts its newest print",
        kiln.start === harness.midnight.wed7 + 4 * 3600 && kiln.points[0].x === 0 && even && clockAt > 0.67 && clockAt < 0.69,
        kiln.start + ", first x " + kiln.points[0].x + ", newest at " + clockAt + ", even " + even)
      // A scrub reads the print it lands on in both looks: NEST's newest,
      // 235.32 at 14:55:42, is no five-minute mark, and retro once rounded
      // it back to 14:55:00 and read the print before, 235.31.
      featureShown("NEST")
      var edgeRead = [false, true].map(function(retro) {
        if (service.retro !== retro) {
          app.testKeyCatcher.forceActiveFocus()
          keyClick(Qt.Key_S)
          within(2000, function() { return service.retro === retro })
        }
        scrubAt(1)
        var read = body.featured.priceText + " | " + body.motion.scrubX.toFixed(4)
        endScrub()
        return read
      })
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_S)
      within(2000, function() { return !service.retro })
      harness.check("a scrub at NEST's newest print, 14:55:42, reads 235.32 there in both looks",
        edgeRead[0] === edgeRead[1] && edgeRead[0].indexOf("235.32 | ") === 0, edgeRead.join(" vs "))
      featureShown("BOLT")
      var bolt = body.featuredDay.points
      scrubAt(0)
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_Right)
      keyClick(Qt.Key_Right)
      keyClick(Qt.Key_Right)
      var stepped = body.motion.scrubT
      var steppedRead = body.headerText
      endScrub()
      harness.check("the keys step print to print: three steps from BOLT's first print land on its fourth, 05:40, an hour and forty minutes on",
        stepped === bolt[3].t && bolt[3].t - bolt[0].t > 3 * 300 && steppedRead.indexOf("At 05:40") === 0,
        steppedRead + " | " + stepped + " vs " + bolt[3].t)
      harness.check("Robinhood's answer on all-day trading holds the day: KILN and BOLT asked once, their prints never again",
        harness.allDayAsked("KILN") === 1 && harness.allDayAsked("BOLT") === 1 && harness.printsAsked("KILN") === 1
          && harness.printsAsked("BOLT") === 1,
        harness.allDayAsked("KILN") + ", " + harness.allDayAsked("BOLT") + " | prints " + harness.printsAsked("KILN") + ", " + harness.printsAsked("BOLT"))

      // Robinhood's instruments down as SPY joins: not all-day meanwhile, so
      // its 1D lands on Yahoo's day, never waiting; five minutes on it is
      // asked again, and turns to the calendar day Robinhood trades it on.
      runCommand(["touch", harness.state + "/INSTRUMENTS.down"])
      service.addSymbol("SPY")
      within(8000, function() { return !!service.quotes.SPY && service.arriving.length === 0 })
      var landed = featureShown("SPY")
      var down = body.featuredGeometry.start + " | " + harness.strip()
      runCommand(["rm", "-f", harness.state + "/INSTRUMENTS.down"])
      service.now = 1791399300 + 6 * 60
      within(4000, function() { return body.featuredGeometry.start === harness.midnight.wed7 })
      harness.check("with Robinhood's instruments down, SPY lands on Yahoo's day; asked again five minutes on, it turns to the calendar day",
        landed && down.indexOf(String(harness.midnight.wed7 + 4 * 3600)) === 0 && body.featuredGeometry.start === harness.midnight.wed7
          && harness.allDayAsked("SPY") === 2,
        down + " then " + body.featuredGeometry.start + ", asked " + harness.allDayAsked("SPY"))

      // A preview's day is its own: NEST, taken out of All and previewed
      // from search, draws Yahoo's day, never asked of Robinhood; added back,
      // with the preview's quote, it draws its calendar day again. Found in
      // review: the kept day of the preview stood in for it.
      service.removeSymbol("NEST")
      within(2000, function() { return service.library.indexOf("NEST") < 0 })
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_A)
      within(2000, function() { return body.adding })
      body.previewTo("NEST")
      within(5000, function() { return body.chartSymbol === "NEST" && !body.chartLoading && body.featuredGeometry.start !== harness.midnight.wed7 })
      var previewed = body.featuredGeometry.start
      service.addSymbol("NEST")
      within(5000, function() { return service.arriving.length === 0 && service.library.indexOf("NEST") >= 0 })
      body.cancelAdding()
      within(3000, function() { return !body.adding })
      featureShown("NEST")
      harness.check("NEST previewed outside All draws Yahoo's day from 04:00; added back, its calendar day from midnight",
        previewed === harness.midnight.wed7 + 4 * 3600 && body.featuredGeometry.start === harness.midnight.wed7,
        previewed + " then " + body.featuredGeometry.start)

      // An exchange's time says its zone only where it is not the reader's
      // clock. The harness reads from New York: Tokyo's
      // next open says JST, and Nasdaq's prints say nothing. Found in the
      // competitor review: "OPENS TUE 09:30" read as local time in Madrid.
      service.addSymbol("7203.T")
      within(8000, function() { return !!service.quotes["7203.T"] && service.arriving.length === 0 })
      featureShown("7203.T")
      var tokyoHeader = body.headerText
      // Tokyo's lunch, 11:30 to 12:30, breaks the line, as retro's columns
      // do; Yahoo sends the day as one session. Smooth drew straight across.
      var tokyoDay = service.quotes["7203.T"]
      var tokyoBreaks = body.featuredGeometry.points.map(function(p, k) { return p.brk ? Format.hhmm(tokyoDay.points[k].t, tokyoDay.gmtoffset) : "" })
        .filter(function(clock) { return clock !== "" })
      featureShown("NEST")
      scrubAt(0.5)
      var nasdaqScrub = body.headerText
      endScrub()
      harness.check("Tokyo's line starts again after its lunch break, and nowhere else",
        tokyoBreaks.join(",") === "12:30", tokyoBreaks.join(","))
      // And its row draws the gap: no ink in the line's canvas half way
      // through the lunch, but the baseline's dashes. Found in review: the
      // rows' and the pill's painter ignored the break. Its row is brought
      // into sight: a row out of sight keeps the quote it last showed.
      var tokyoAt = body.watchlist.rowItem("7203.T").y
      body.watchlist.contentY = Math.max(0, Math.min(tokyoAt, body.watchlist.contentHeight - body.watchlist.height))
      var rowLine = harness.find(body.watchlist.rowItem("7203.T"), "rowLine")
      var rowInk = rowLine.children[0]
      var rowPoints = rowLine.geometry.points
      var resumed = rowPoints.findIndex(function(p) { return p.brk })
      var lunchX = Math.round(rowLine.pad + (rowPoints[resumed - 1].x + rowPoints[resumed].x) / 2 * (rowLine.width - 2 * rowLine.pad))
      var baseY = rowLine.pad + rowLine.geometry.baselineY * (rowLine.height - 2 * rowLine.pad)
      wait(50)
      var column = rowInk.getContext("2d").getImageData(lunchX, 0, 1, Math.floor(rowInk.height)).data
      var inked = []
      for (var py = 0; py < column.length / 4; py++)
        if (column[py * 4 + 3] > 0 && Math.abs(py - baseY) > 1.5) inked.push(py)
      harness.check("Tokyo's row leaves its lunch break empty",
        resumed > 0 && inked.length === 0, "x " + lunchX + ", inked rows " + inked.join(","))
      harness.check("for a reader in New York, Tokyo's next open names JST and a Nasdaq scrub names no zone",
        tokyoHeader === "Closed · opens Thu 09:00 JST" && /^At \d\d:\d\d · /.test(nasdaqScrub) && nasdaqScrub.indexOf("EDT") < 0,
        tokyoHeader + " | " + nasdaqScrub)
      // A non-US row following a scrub reads its own close once its session
      // has closed, as it does at rest: Tokyo's last bar is 15:20 at 2,908,
      // its close 2,900.5. Found by the PM: Toyota read 2,911.50 during a
      // scrub against 2,910.50 at rest.
      var tokyoRow = body.watchlist.rowItem("7203.T")
      var tokyoRest = tokyoRow.view.priceText
      scrubAt(0.5)
      var tokyoScrubbed = tokyoRow.view.priceText + ", following " + (body.watchlistScrubShown !== 0)
      endScrub()
      harness.check("a scrub inside Nasdaq's day, after Tokyo's close, leaves Tokyo's row on its close",
        tokyoScrubbed === tokyoRest + ", following true", tokyoScrubbed + " against " + tokyoRest + " at rest")

      // A symbol that leaves All keeps Robinhood's answers only until they
      // would be asked again anyway, with no edit to prompt the pruning:
      // its prints five minutes on, while the rest go on being asked, and
      // its all-day answer a day on.
      var prints = service.testOvernightFeed
      var allDay = service.testAllDayFeed
      // Answered for `symbol` at the clock's present second.
      var answeredNow = function(feed, symbol) { return !!feed.entries[symbol] && feed.entries[symbol].at === service.now }
      service.now += 60
      prints.fetch(["NEST", "SILK"], service.now)
      allDay.fetch(["SILK"], service.now)
      var asked = within(3000, function() { return answeredNow(prints, "SILK") && answeredNow(allDay, "SILK") })
      service.removeSymbol("SILK")
      // A second removal: SILK's can no longer be undone.
      service.removeSymbol("REED")
      wait(50)
      var keptFresh = !!prints.entries.SILK && !!allDay.entries.SILK
      var leftAt = service.now
      for (var m = 1; m <= 6; m++) {
        service.now = leftAt + m * 60
        prints.fetch(["NEST"], service.now)
        asked = within(3000, function() { return answeredNow(prints, "NEST") }) && asked
      }
      var printsGone = !prints.entries.SILK && !!prints.entries.NEST
      var allDayKept = !!allDay.entries.SILK
      service.now = leftAt + 25 * 3600
      wait(50)
      var allDayGone = !allDay.entries.SILK
      harness.check("a symbol gone keeps Robinhood's prints five minutes and its all-day answer a day, then neither, with no edit",
        asked && keptFresh && printsGone && allDayKept && allDayGone,
        [asked, keptFresh, printsGone, allDayKept, allDayGone].join(","))

      // 80 US stocks Robinhood trades all day, added with the window open:
      // their prints come in requests of at most 25, a third of Robinhood's
      // limit, and every one's night is drawn. Robinhood answered 400 to all
      // 80 in one request, and no overnight price ever showed.
      useSet("2026-10-07-0100")
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
      harness.check("80 all-day listings: their prints in requests of at most 25, each asked once, and every one's night drawn",
        nights && requests.every(function(r) { return r.length <= 25 }) && each.length === 80 && drawn,
        "requests of " + requests.map(function(r) { return r.length }).join(", ") + "; " + each.length + " asked once; nights "
          + nights + "; LONG80 drawn " + drawn)

      // Thursday 23:00, a trading night, Robinhood refusing: the night's
      // refresh of the list's prints, four requests now, meets a 429 and
      // pauses Robinhood. Five minutes on, the pause's first probe lets one
      // request go alone; its answer reopens Robinhood, and the rest of the
      // list goes at once. One ask stood for the whole list, so the rest used
      // to wait another five minutes.
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
      harness.check("a trading night, Robinhood back after a refusal: its first probe lets one request go alone, and the rest goes once that reopens it",
        refused && caughtUp && afterProbe.length > 2 && afterProbe[0] === 25,
        "refused " + refused + "; requests after the pause of " + afterProbe.join(", ") + "; every night refreshed " + caughtUp)

      // A real thin US day: the three long quiet spans are known from
      // the saved answer, not from the geometry's break decisions. One key
      // step must reach the next actual print, however long the silence.
      useSet("gaps-2026-10-21-1006")
      service.now = 1792591591
      service.addSymbol("VANE")
      within(8000, function() { return !!service.quotes.VANE && service.arriving.length === 0 })
      featureShown("VANE")
      within(3000, function() { return body.chartSymbol === "VANE" && !body.chartLoading })
      var spans = [[1792555800,1792561200], [1792565400,1792569600], [1792571400,1792580700]]
      var joined = spans.map(function(span) {
        var points = body.featuredDay.points
        var a = points.map(function(p) { return p.t }).indexOf(span[0])
        var b = points.map(function(p) { return p.t }).indexOf(span[1])
        body.motion.scrubT = span[0]
        app.testKeyCatcher.forceActiveFocus()
        keyClick(Qt.Key_Right)
        return a >= 0 && b === a + 1 && body.featuredGeometry.points[b].brk === false && body.scrubT === span[1]
      })
      harness.check("a thin US day's three quiet spans keep adjacent prints joined and each is one scrub step",
        joined.every(function(ok) { return ok }), joined.join(","))
      body.endScrub()
      // Painted sparse day/3M, one-print and Tokyo lunch states are already
      // in render.qml; no model value can stand in for their rendered ink.
      harness.finish()
    }
  }

  HarnessExit { id: done }
}
