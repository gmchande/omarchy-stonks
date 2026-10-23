import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "plugin/Chart.js" as Chart
import "plugin/Quote.js" as Quote
import "plugin/Settings.js" as Settings
import "plugin"

// StonksBody under a real offscreen pointer and wheel, on a stub surface:
// the cases real data cannot set up. Nothing is mapped into the running shell.
ShellRoot {
  id: root

  property int failures: 0

  FileView {
    id: watchlistFixture
    path: Quickshell.env("STONKS_WATCHLIST_FIXTURE")
    blockLoading: true
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

  function findAll(item, name, into) {
    var out = into || []
    if (!item) return out
    if (item.objectName === name) out.push(item)
    for (var i = 0; i < item.children.length; i++) findAll(item.children[i], name, out)
    return out
  }

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  // The sign the header names. Its ink and transitions are review states.
  function animalShows(kind) { return body.animal.kind === kind }

  function quote(symbol, price, previous) {
    return {
      symbol: symbol,
      name: "Sample " + symbol,
      currency: "USD",
      exchange: "NASDAQ",
      timezoneName: "America/New_York",
      gmtoffset: -14400,
      instrumentType: "EQUITY",
      crypto: false,
      price: price,
      prevClose: previous,
      marketTime: stub.now,
      dayHigh: Math.max(price, previous) + 1,
      dayLow: Math.min(price, previous) - 1,
      volume: 100,
      session: {
        pre: { start: stub.now - 25200, end: stub.now - 19800 },
        regular: { start: stub.now - 19800, end: stub.now + 3600 },
        post: { start: stub.now + 3600, end: stub.now + 18000 }
      },
      points: [
        { t: stub.now - 19800, p: previous },
        { t: stub.now - 300, p: price }
      ]
    }
  }

  function symbols(count) {
    var result = []
    for (var i = 0; i < count; i++) result.push("S" + String(i).padStart(2, "0"))
    return result
  }

  function setQuotes(symbols, values) {
    var nextQuotes = {}
    var nextEntries = {}
    for (var i = 0; i < symbols.length; i++) {
      nextQuotes[symbols[i]] = root.quote(symbols[i], values[i], 100)
      nextEntries[symbols[i]] = { status: "ok", receivedAt: stub.now }
    }
    stub.symbols = symbols.slice()
    stub.quotes = nextQuotes
    stub.entries = nextEntries
    stub.shown = Settings.sortedSymbols(stub.symbols, stub.quotes, stub.order, stub.reversed)
    stub.featuredSymbol = symbols[0]
  }

  function setFixtureWatchlist() {
    var fixture = JSON.parse(watchlistFixture.text())
    var nextSymbols = []
    var nextQuotes = {}
    var nextEntries = {}
    for (var i = 0; i < fixture.quotes.length; i++) {
      var item = fixture.quotes[i]
      var parsed = item.response ? Quote.parseChart(item.response) : null
      var symbol = parsed ? parsed.symbol : item.symbol
      nextSymbols.push(symbol)
      if (parsed) nextQuotes[symbol] = parsed
      nextEntries[symbol] = { status: item.status, receivedAt: item.status === "ok" ? fixture.now : 0 }
    }
    stub.now = fixture.now
    stub.order = "manual"
    stub.reversed = false
    stub.symbols = nextSymbols
    stub.quotes = nextQuotes
    stub.entries = nextEntries
    stub.shown = nextSymbols.slice()
    stub.featuredSymbol = "MZ"
  }

  QtObject {
    id: stub
    property var symbols: []
    property var shown: []
    property var library: symbols
    property string listName: ""
    property var lists: [{ name: "", label: "All", count: symbols.length, symbols: symbols }]
    property var quotes: ({})
    property var entries: ({})
    property var calendars: null
    property string featuredSymbol: ""
    property string order: "pct"
    property bool reversed: false
    property string changeMode: "pct"
    property int now: 1789669200
    property var owed: ({})
    property string range: "1D"
    property var histories: ({})
    property var fundamentals: ({})
    property var arriving: []
    property var lastRemoval: null
    readonly property var view: ({ featured: featuredSymbol, range: range, list: listName, listKey: "=" + listName,
      order: order, reversed: reversed, rows: symbols.filter(function(s) { return arriving.indexOf(s) < 0 }),
      shown: shown.filter(function(s) { return arriving.indexOf(s) < 0 }), library: library,
      chart: Chart.viewChart(featuredSymbol, range, quotes, entries, histories) })
    property bool retro: false
    property color foreground: "#cacccc"
    property color upColor: "#7aa2f7"
    property color downColor: "#a55555"
    property string fontFamily: Style.font.family
    property var lastSettings: null
    function persist(values) { lastSettings = values }
    function setRange(value) { range = value }
    function screensClear() { return true }
    function surfaceShown(surface, open) {}
    function rowsSeen(surface, symbols) {}
    // A search's choice shown on the hero; this stub's hero never changes.
    readonly property var previewView: view
    readonly property var previewEntries: ({})
    property var previewSurface: null
    function preview(surface, symbol) {}
    function feature(symbol) { featuredSymbol = symbol }
    function removeSymbol(symbol) {
      var before = { symbols: symbols, lists: [] }
      var next = symbols.filter(function(value) { return value !== symbol })
      symbols = next
      shown = Settings.sortedSymbols(next, quotes, order, reversed)
      if (featuredSymbol === symbol) featuredSymbol = next[0] || ""
      lastRemoval = { symbol: symbol, before: before }
    }
    function setManualOrder(next) { symbols = next.slice(); shown = next.slice(); order = "manual" }
    function addSymbol(symbol) {
      var upper = String(symbol || "").toUpperCase()
      var next = symbols.slice()
      if (next.indexOf(upper) < 0) {
        next.push(upper)
        arriving = arriving.concat([upper])
      }
      symbols = next
      shown = Settings.sortedSymbols(next, quotes, order, reversed)
    }
    function setOrder(value) {
      order = value
      shown = Settings.sortedSymbols(symbols, quotes, order, reversed)
      lastSettings = { order: value }
    }
    function reverseOrder() {
      reversed = !reversed
      shown = Settings.sortedSymbols(symbols, quotes, order, reversed)
      lastSettings = { reversed: reversed }
    }
    property var memberships: []
    function setMembership(symbol, name, member) { memberships = memberships.concat([symbol + "|" + name + "|" + member]) }
    function switchList(name) {}
    function stepList(delta) {}
    function createList(name) { return "" }
  }

  FloatingWindow {
    id: window
    visible: true
    color: "#101315"
    implicitWidth: 480
    implicitHeight: 760

    StonksBody {
      id: body
      anchors.fill: parent
      anchors.margins: Style.space(16)
      service: stub
      foreground: stub.foreground
      upColor: stub.upColor
      downColor: stub.downColor
      fontFamily: stub.fontFamily
      surfaceOpen: true
      chartHeight: Style.space(190)
      rangeOptions: ["1D", "1Y"]
    }

    TestCase {
      name: "Pointer"
      when: window.visible

      // Waits up to ms for fn to hold and returns whether it does.
      function within(ms, fn) {
        for (var t = 0; t < ms && !fn(); t += 20) wait(20)
        return fn()
      }

      // A click on the open row menu's line `index`, where its words are.
      function takeMenuLine(index) {
        var line = root.findAll(body, "rowMenuLine")[index]
        if (line) mouseClick(line, Style.space(20), line.height / 2)
      }

      function firstWhole(watchlist) {
        for (var i = 0; i < watchlist.displayedSymbols.length; i++)
          if (watchlist.wholeInSight(i, watchlist.contentY)) return i
        return -1
      }

      function test_owner_flows() {
        root.setQuotes(["UNKNOWN"], [100])
        stub.quotes = { UNKNOWN: Object.assign({}, stub.quotes.UNKNOWN, { prevClose: null }) }
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          root.check("an unknown chart direction stays unset in " + (retro ? "retro" : "smooth"),
            body.featured.dayUp === null && body.animal.kind === "")
        })
        // The featured symbol is up while the list is net down.
        root.setQuotes(["UP", "DOWN", "DEEP"], [110, 95, 90])

        // The arrow changes the rows the reader sees, and an arriving quote
        // keeps that direction. Three unequal gains make the order explicit.
        var reversedRows = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          stub.reversed = false
          stub.setOrder("pct")
          root.setQuotes(["UP", "DOWN", "DEEP"], [110, 95, 90])
          mouseMove(body, 1, 1)
          tryVerify(function() { return body.watchlist.displayedSymbols.join() === "UP,DOWN,DEEP" }, 2000)
          var arrow = root.find(body, "orderArrow")
          var at = arrow.mapToItem(body, arrow.width / 2, arrow.height / 2)
          mouseClick(body, at.x, at.y)
          mouseMove(body, 1, 1)
          var reversed = within(2000, function() { return body.watchlist.displayedSymbols.join() === "DEEP,DOWN,UP" })
          root.setQuotes(["UP", "DOWN", "DEEP"], [80, 95, 90])
          var refreshed = within(2000, function() { return body.watchlist.displayedSymbols.join() === "UP,DEEP,DOWN" })
          reversedRows.push(retro + ":" + reversed + "," + refreshed)
        })
        root.check("the order arrow reverses the visible rows and a quote refresh keeps that direction in both looks",
          reversedRows.join("|") === "false:true,true|true:true,true", reversedRows.join("|"))
        stub.reversed = false
        stub.setOrder("pct")
        root.setQuotes(["UP", "DOWN", "DEEP"], [110, 95, 90])

        // The header's animal, in both looks: the featured day's, whatever
        // the click. A Shift-click replays the chart as a click does, and
        // never forces a bull or a bear over the day's direction.
        ;[true, false].forEach(function(retro) {
          stub.retro = retro
          var look = retro ? "retro" : "smooth"
          wait(50)
          root.check("featured direction beats a down watchlist in " + look + "'s animal",
            body.animal.kind === "bull" && within(500, function() { return root.animalShows("bull") }))
          var clicks = []
          for (var shiftClick = 0; shiftClick < 3; shiftClick++) {
            mouseClick(body, 20, 14, Qt.LeftButton, Qt.ShiftModifier)
            var replayed = body.motion.replayRunning
            // The replay reads the day from its start; at rest it is the day's.
            body.motion.stopReplay()
            body.motion.scrubT = 0
            wait(50)
            clicks.push(body.animal.kind + " " + replayed)
          }
          root.check(look + "'s animal: a Shift-click replays the chart and leaves the day's bull",
            clicks.join(",") === "bull true,bull true,bull true" && within(500, function() { return root.animalShows("bull") }),
            clicks.join(","))
        })

        var rangeRow = root.find(body, "rangeRow")
        var tokens = root.findAll(rangeRow, "rangeToken")
        var second = tokens[1].mapToItem(body, tokens[1].width / 2, tokens[1].height / 2)
        mouseMove(body, second.x, second.y)
        // The wheel over a token walks the ranges, the way it does between
        // them: a notch down is the next, longer range. The pointer rests on
        // the token first, the way a hand reaches for it, so the token's
        // hover area is live when the wheel arrives.
        var first = tokens[0].mapToItem(body, tokens[0].width / 2, tokens[0].height / 2)
        mouseMove(body, first.x, first.y)
        wait(200)
        mouseWheel(body, first.x, first.y, 0, -120, Qt.NoModifier)
        wait(50)
        root.check("a wheel notch down over a hovered range token steps to the next range", body.range === "1Y")
        mouseWheel(body, first.x, first.y, 0, 120, Qt.NoModifier)
        wait(50)
        root.check("a wheel notch up over a hovered range token steps back", body.range === "1D")
        mouseMove(body, body.width / 2, body.height - 4)
        wait(50)

        // The header's marks are as easy to hit as the row they sit in.
        var helpMark = root.find(body, "helpMark")
        var beside = helpMark.mapToItem(body, helpMark.width + 8, helpMark.height / 2)
        mouseClick(body, beside.x, beside.y)
        wait(50)
        root.check("a click beside the help mark opens the sheet", body.showingHelp)
        mouseClick(body, beside.x, beside.y)
        wait(50)
        root.check("and closes it again", !body.showingHelp)
        var icon = root.find(body, "lookIcon")
        var toggle = root.find(body, "lookToggle")
        var onIcon = icon.mapToItem(body, icon.width / 2, icon.height / 2)
        var underIcon = toggle.mapToItem(body, toggle.width / 2, toggle.height - 2)
        stub.lastSettings = null
        mouseClick(body, underIcon.x, underIcon.y)
        var picked = stub.lastSettings ? stub.lastSettings.style : ""
        stub.retro = true
        stub.lastSettings = null
        mouseClick(body, onIcon.x, onIcon.y)
        var back = stub.lastSettings ? stub.lastSettings.style : ""
        stub.retro = false
        root.check("a click on or under the look icon changes the look", picked === "retro" && back === "smooth")
        mouseMove(body, body.width / 2, body.height - 4)

        // The axis runs to the bell, an hour off; the fixture's last print is
        // five minutes old.
        var lastPrint = stub.now - 300
        root.check("the day's axis runs past its last print", body.motion.dayGeometry.end > lastPrint)
        body.motion.scrubTo(1)
        root.check("hover scrubbing stops at the last print", body.scrubT === lastPrint)
        body.nudgeScrub(50)
        root.check("key scrubbing stops at the last print", body.scrubT === lastPrint)
        // Watch the whole sweep: its furthest moment is the last print, and
        // it reaches it rather than stopping short.
        body.motion.scrubT = 0
        body.replay()
        var furthest = 0
        var sampled = 0
        while (body.motion.replayRunning && sampled < 80) {
          furthest = Math.max(furthest, body.scrubT)
          wait(40)
          sampled++
        }
        root.check("replay sweeps as far as the last print and no further",
          sampled > 0 && !body.motion.replayRunning && furthest <= lastPrint && furthest > lastPrint - 600)
        body.motion.stopReplay()
        body.motion.scrubT = 0

        // The bull and bear agree with the moment shown: a day that traded
        // above its close in the morning and closed below it is a bull while
        // the scrub reads the morning, and a bear at rest.
        var restFeatured = stub.featuredSymbol
        var open = stub.now - 19800
        var swing = root.quote("SWING", 95, 100)
        swing.points = [{ t: open, p: 104 }, { t: open + 10800, p: 96 }, { t: stub.now - 300, p: 95 }]
        stub.quotes = Object.assign({}, stub.quotes, { SWING: swing })
        stub.entries = Object.assign({}, stub.entries, { SWING: { status: "ok", receivedAt: stub.now } })
        stub.featuredSymbol = "SWING"
        // Scrub the way the owner does, with the pointer over the chart.
        var span = Chart.chartGeometry(swing).end - Chart.chartGeometry(swing).start
        var legend = root.find(body, "baselineLegend")
        ;[true, false].forEach(function(retro) {
          stub.retro = retro
          var look = retro ? "retro" : "smooth"
          wait(50)
          var chart = body.chartItem
          var xAt = function(t) { return chart.width * (t - Chart.chartGeometry(swing).start) / span }
          root.check(look + ": at rest a day that closed down draws the bear",
            within(500, function() { return root.animalShows("bear") }))
          mouseMove(chart, xAt(open + 600), chart.height / 2)
          root.check(look + ": the pointer on a morning above the close draws the bull",
            within(500, function() { return root.animalShows("bull") }))
          // While a scrub reads the price against the dashed line, the strip
          // under the price names it.
          root.check(look + ": a scrub names the dashed line under the price",
            !!legend && legend.visible && legend.text === "┄ PREV CLOSE 100.00")
          mouseMove(chart, xAt(open + 10800 + 600), chart.height / 2)
          root.check(look + ": the pointer on an afternoon below the close draws the bear again",
            within(500, function() { return root.animalShows("bear") }))
          mouseMove(body, body.width / 2, 20)
          wait(50)
          root.check(look + ": the name leaves with the scrub", !!legend && !legend.visible && body.scrubT === 0)
        })

        // A flat day, a change that rounds to nothing, has no sign, neither
        // colour, and no animal, in either look. Found on BOLT at 0.00%:
        // retro drew a green bull.
        var flat = root.quote("FLAT", 100.001, 100)
        flat.points = [{ t: open, p: 100.4 }, { t: stub.now - 300, p: 100.001 }]
        stub.quotes = Object.assign({}, stub.quotes, { FLAT: flat })
        stub.entries = Object.assign({}, stub.entries, { FLAT: { status: "ok", receivedAt: stub.now } })
        stub.featuredSymbol = "FLAT"
        ;[true, false].forEach(function(retro) {
          stub.retro = retro
          wait(50)
          root.check((retro ? "retro" : "smooth") + ": a flat day draws no animal",
            body.featured.tone === "flat" && body.animal.kind === "", body.featured.changeText)
        })
        stub.retro = false

        // A range whose first fetch failed shows the day in its place; the
        // retry that lands is another chart, so the animal changes at once.
        // Found in review: the up day's bull crossfaded into the range's bear.
        stub.featuredSymbol = "UP"
        stub.range = "1Y"
        stub.histories = { "UP|1Y": { history: null } }
        root.check("a failed range's stand-in day draws its bull",
          body.chart.failed && within(500, function() { return root.animalShows("bull") }))
        stub.histories = { "UP|1Y": { history: { symbol: "UP", range: "1Y", baseline: 120, interval: "1d", gmtoffset: -14400, bars: [
          { t: stub.now - 86400, c: 120, h: 121, l: 119, o: 120, v: 100 },
          { t: stub.now, c: 110, h: 111, l: 109, o: 110, v: 100 }
        ] } } }
        root.check("a failed range's retry that lands down names the bear",
          !body.chart.failed && root.animalShows("bear"), body.animal.kind)
        // A scrub whose line crosses a mark's date keeps the mark: the date
        // stands clear of the line, and the price where it was, and both are
        // back at rest once the pointer leaves. Both looks, both marks, on a
        // year with a sharp high early, whose date has no room before its
        // price, and a sharp low late, whose date has. Found in the
        // overnight QA of 23 October: AAPL's 1Y scrub ran through "20│JAN
        // 2026"; and in the check of that night's fixes, the whole mark went
        // instead, the year's high with it.
        var sharp = []
        for (var sb = 0; sb < 40; sb++) {
          var sc = sb === 6 ? 130 : sb === 33 ? 70 : 100 + (sb % 3)
          sharp.push({ t: stub.now - (39 - sb) * 86400, c: sc, h: sc + 0.5, l: sc - 0.5, o: sc, v: 100 })
        }
        stub.histories = { "UP|1Y": { history: { symbol: "UP", range: "1Y", baseline: 100, interval: "1d", gmtoffset: -14400, bars: sharp } } }
        var crossed = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          wait(50)
          tryVerify(function() { return body.motion.drawn === 1 }, 2000)
          ;["highMark", "lowMark"].forEach(function(name) {
            var mark = root.find(body, name)
            var marks = mark.parent.parent
            var price = root.find(mark, "markPrice")
            var date = root.find(mark, "markDate")
            var place = function() { return [mark.visible, mark.x + price.x, mark.x + date.x].join(",") }
            var atRest = place()
            var restDate = [mark.x + date.x, mark.x + date.x + date.width]
            var over = date.mapToItem(body.chartItem, date.width / 2, 0)
            mouseMove(body.chartItem, over.x, body.chartItem.height / 2)
            wait(50)
            var line = marks.scrubAt
            var onRest = line >= restDate[0] && line <= restDate[1]
            var dateNow = [mark.x + date.x, mark.x + date.x + date.width]
            var clear = line < dateNow[0] - 1 || line > dateNow[1] + 1
            var scrubbed = [mark.visible, mark.x + price.x === Number(atRest.split(",")[1]), clear, dateNow[0] >= 0 && dateNow[1] <= marks.width].join(",")
            mouseMove(body.chartItem, over.x, -Style.space(40))
            wait(50)
            var after = place()
            if (!atRest.startsWith("true") || !onRest || scrubbed !== "true,true,true,true" || after !== atRest)
              crossed.push((retro ? "retro " : "smooth ") + name + ": at rest " + atRest + ", line " + line + " on the date " + onRest
                + ", scrubbed (shown, price kept, date clear, on the chart) " + scrubbed + ", after " + after)
          })
          mouseMove(body.chartItem, 1, -Style.space(40))
          wait(50)
        })
        stub.retro = false
        root.check("a scrub over a range's mark's date keeps the mark, its price in place and its date clear of the line, and the pointer leaving puts it back, both marks, both looks",
          crossed.length === 0, crossed.join(" | "))
        stub.range = "1D"
        stub.histories = {}
        stub.featuredSymbol = restFeatured
        wait(50)

        var held = body.watchlist.displayedSymbols.join(",")
        mouseMove(body.watchlist, 12, 12)
        wait(50)
        root.setQuotes(["UP", "DOWN", "DEEP"], [90, 95, 120])
        wait(50)
        root.check("quote arrival records the newest sort while rows stay put",
          stub.shown.join(",") === "DEEP,DOWN,UP"
            && body.watchlist.displayedSymbols.join(",") === held)
        mouseMove(body, body.width / 2, 20)
        wait(200)
        root.check("leaving applies the newest sort once",
          !body.watchlist.sortHeld && body.watchlist.displayedSymbols.join(",") === "DEEP,DOWN,UP")

        // A closing surface holds the order on screen too: the pointer leaving
        // as the card fades re-sorts nothing, and the next open lays the rows
        // out in the newest order at once, in smooth and in retro. Found in
        // the review of the transitions branch: the rows moved during the
        // close fade once the pointer left them.
        var closingHolds = function(values, retro) {
          stub.retro = retro
          mouseMove(body.watchlist, 12, 12)
          wait(50)
          var onScreen = body.watchlist.displayedSymbols.join(",")
          root.setQuotes(["UP", "DOWN", "DEEP"], values)
          wait(50)
          body.surfaceOpen = false
          mouseMove(body, body.width / 2, 20)
          wait(200)
          var kept = body.watchlist.displayedSymbols.join(",") === onScreen && onScreen !== stub.shown.join(",")
          body.resetInteraction()
          body.surfaceOpen = true
          var laidOut = body.watchlist.displayedSymbols.join(",") === stub.shown.join(",")
          return kept + "," + laidOut + " " + onScreen + " -> " + body.watchlist.displayedSymbols.join(",")
        }
        var smoothClose = closingHolds([120, 95, 90], false)
        var retroClose = closingHolds([90, 95, 120], true)
        stub.retro = false
        wait(50)
        root.check("a closing surface holds the rows' order as the pointer leaves, and the next open lays them out at once",
          /^true,true /.test(smoothClose) && /^true,true /.test(retroClose), smoothClose + " | " + retroClose)
        // So does a list chosen on another surface as this one closes: the
        // rows stay as they were, and the next open shows the new list from
        // its top. Found in cubic's review of #26.
        var allRows = stub.symbols.slice()
        var shownRows = body.watchlist.displayedSymbols.join(",")
        body.surfaceOpen = false
        stub.listName = "Other"
        stub.symbols = ["DEEP"]
        stub.shown = ["DEEP"]
        wait(100)
        var keptRows = body.watchlist.displayedSymbols.join(",") === shownRows
        body.resetInteraction()
        body.surfaceOpen = true
        var otherList = body.watchlist.displayedSymbols.join(",") === "DEEP" && body.watchlist.contentY === 0
        // An empty list chosen so says nothing over the rows it keeps.
        var emptyList = root.find(body, "emptyList")
        body.surfaceOpen = false
        stub.listName = "Empty"
        stub.symbols = []
        stub.shown = []
        wait(100)
        var quiet = !emptyList.visible && body.watchlist.displayedSymbols.join(",") === "DEEP"
        body.resetInteraction()
        body.surfaceOpen = true
        var saysEmpty = emptyList.visible && body.watchlist.displayedSymbols.length === 0
        stub.listName = ""
        stub.symbols = allRows
        stub.shown = Settings.sortedSymbols(allRows, stub.quotes, stub.order, stub.reversed)
        wait(100)
        root.check("a list chosen elsewhere as the surface closes changes no row until the next open, which starts it from the top; an empty one says so only then",
          keptRows && otherList && quiet && saysEmpty,
          [keptRows, otherList, quiet, saysEmpty].join("|") + " " + shownRows + " -> " + body.watchlist.displayedSymbols.join(","))

        var fifteen = root.symbols(15)
        var values = []
        for (var i = 0; i < fifteen.length; i++) values.push(100 + i)
        stub.order = "pct"
        root.setQuotes(fifteen, values)
        wait(100)

        body.watchlist.contentY = 0
        // The pointer comes in as a hand's does, over more than one place:
        // the first place it is seen at in a list is where it starts.
        mouseMove(body.watchlist, 12, body.watchlist.rowPitch + 6)
        mouseMove(body.watchlist, 12, body.watchlist.rowPitch + 12)
        wait(50)
        var removed = body.watchlist.displayedSymbols[1]
        // A middle-click removes nothing; a right-click opens the row's menu,
        // removing nothing, and its line removes the row.
        mouseClick(body.watchlist, 12, body.watchlist.rowPitch + 12, Qt.MiddleButton)
        wait(50)
        var middleKept = body.watchlist.displayedSymbols.indexOf(removed) >= 0 && body.rowMenu === null
        mouseClick(body.watchlist, 12, body.watchlist.rowPitch + 12, Qt.RightButton)
        wait(50)
        var menuKept = body.rowMenu !== null && body.rowMenu.symbol === removed && body.watchlist.displayedSymbols.indexOf(removed) >= 0
        takeMenuLine(0)
        wait(200)
        root.check("a middle-click removes nothing, a right-click opens the row's menu, and its line removes the row under a held sort",
          middleKept && menuKept && body.rowMenu === null && body.watchlist.sortHeld && body.watchlist.displayedSymbols.indexOf(removed) < 0
            && body.watchlist.rowItem(removed) === null
            && body.watchlist.displayedSymbols.length === 14,
          [middleKept, menuKept, body.rowMenu === null, body.watchlist.sortHeld, body.watchlist.displayedSymbols.length].join("|"))

        // Before its first answer the new symbol is not in the list at all:
        // not drawn, not counted in the scroll, and not a key's target.
        // Found in the code-quality review: it showed as "Loading…" at the
        // end, then vanished and faded in again at its sorted place.
        var newAt = []
        var watchNew = function() { newAt.push(body.watchlist.displayedSymbols.indexOf("NEW")) }
        body.watchlist.displayedSymbolsChanged.connect(watchNew)
        // This stub isolates a pending service answer; accept its supplied
        // result through the same pointer path as a real search.
        body.startAdding()
        body.search.results = [{ symbol: "NEW", name: "New result", exchange: "NASDAQ" }]
        body.search.answer = "results"
        wait(20)
        var newResult = root.findAll(body.search, "searchResult")[0]
        mouseClick(newResult, newResult.width / 2, newResult.height / 2)
        mouseMove(body.watchlist, 12, body.watchlist.rowPitch + 6)
        mouseMove(body.watchlist, 12, body.watchlist.rowPitch + 12)
        wait(20)
        body.watchlist.displayedSymbolsChanged.disconnect(watchNew)
        root.check("a pointer-held add stays out of the list until its first answer",
          body.watchlist.sortHeld && body.watchlist.displayedSymbols.length === 14
            && body.shown.indexOf("NEW") < 0
            && newAt.every(function(at) { return at < 0 }),
          body.watchlist.displayedSymbols.length + "|" + newAt.join(","))
        // Its first answer lands, as the service's fetch would bring it, up
        // 100%, which sorts it first. With the pointer still over the rows it
        // joins there, is selected there, and stays when the pointer leaves.
        // Found in motion pass 3 review: it was selected at the bottom, then
        // slid up once the pointer left.
        tryVerify(function() { return body.watchlist.rowItem("NEW") !== null }, 1000)
        var addedRow = body.watchlist.rowItem("NEW")
        stub.quotes = Object.assign({}, stub.quotes, { NEW: root.quote("NEW", 200, 100) })
        stub.entries = Object.assign({}, stub.entries, { NEW: { status: "ok", receivedAt: stub.now } })
        stub.shown = Settings.sortedSymbols(stub.symbols, stub.quotes, stub.order, stub.reversed)
        stub.arriving = []
        wait(100)
        var landedAt = body.watchlist.displayedSymbols.indexOf("NEW")
        root.check("pointer-held sorted add joins at its sorted place, selected and in view",
          body.watchlist.sortHeld && landedAt === stub.shown.indexOf("NEW") && landedAt < 14
            && body.watchlist.cursorSymbol === "NEW"
            && addedRow.y >= body.watchlist.contentY
            && addedRow.y + addedRow.height <= body.watchlist.contentY + body.watchlist.height)

        // Scrolled by hand with NEW still whole in sight, so it keeps the
        // cursor of its own.
        body.watchlist.contentY = addedRow.y
        var userScroll = body.watchlist.contentY
        stub.quotes = Object.assign({}, stub.quotes)
        stub.shown = Settings.sortedSymbols(stub.symbols, stub.quotes, stub.order, stub.reversed)
        wait(100)
        root.check("a quote refresh does not repeat add selection or scrolling",
          body.watchlist.cursorSymbol === "NEW"
            && Math.abs(body.watchlist.contentY - userScroll) < 0.5)
        mouseMove(body.watchlist, 24, body.watchlist.rowPitch + 12)
        wait(50)
        var pointedRow = body.watchlist.displayedSymbols[Math.floor((body.watchlist.rowPitch + 12 + body.watchlist.contentY) / body.watchlist.rowPitch)]
        root.check("real pointer movement takes the cursor from the added row to the row under the pointer",
          pointedRow !== "NEW" && body.watchlist.cursorSymbol === pointedRow, pointedRow + "|" + body.watchlist.cursorSymbol)
        mouseMove(body, body.width / 2, 20)
        wait(200)
        root.check("and the added row stays there once the pointer leaves",
          !body.watchlist.sortHeld && body.watchlist.displayedSymbols.indexOf("NEW") === landedAt)

        root.setFixtureWatchlist()
        wait(100)
        var fixtureOrder = body.watchlist.displayedSymbols.join(",")
        body.watchlist.contentY = 0
        var wheelRow = body.watchlist.rowItem(body.watchlist.displayedSymbols[2])
        mouseWheel(wheelRow, wheelRow.width / 2, wheelRow.height / 2,
          0, -120, Qt.NoModifier)
        wait(500)
        var afterOne = firstWhole(body.watchlist)
        mouseWheel(wheelRow, wheelRow.width / 2, wheelRow.height / 2,
          0, -120, Qt.NoModifier)
        wait(500)
        root.check("each wheel notch over a row moves one whole row",
          afterOne === 1 && firstWhole(body.watchlist) === 2)

        // A high-resolution wheel sends many small ticks per notch. Each
        // moves its fraction of a row, and the list settles on a boundary
        // once they stop, not on every tick.
        var pitch = body.watchlist.rowPitch
        body.watchlist.contentY = 0
        wait(50)
        mouseWheel(wheelRow, wheelRow.width / 2, wheelRow.height / 2,
          0, -30, Qt.NoModifier)
        within(2000, function() { return !body.watchlist.settling })
        root.check("a high-resolution tick leaves the first row in reach", firstWhole(body.watchlist) === 0)
        body.watchlist.contentY = 0
        wait(50)
        for (var tick = 0; tick < 4; tick++) {
          mouseWheel(wheelRow, wheelRow.width / 2, wheelRow.height / 2,
            0, -30, Qt.NoModifier)
          wait(30)
        }
        wait(600)
        root.check("four high-resolution ticks add up to one row",
          firstWhole(body.watchlist) === 1)
        root.check("wheel scrolling does not reorder rows", body.watchlist.displayedSymbols.join(",") === fixtureOrder)

        // A row lifted mid-glide takes the list over: neither the glide nor
        // the wheel's pending settle moves the list under it.
        body.watchlist.wheelBy(0.3)
        wait(40)
        var lifted = body.watchlist.displayedSymbols[2]
        body.watchlist.beginDrag(lifted, 2 * pitch + 10)
        var heldAt = firstWhole(body.watchlist)
        wait(500)
        root.check("lifting a row stops the wheel's glide and its settle",
          body.watchlist.dragSymbol === lifted && firstWhole(body.watchlist) === heldAt)
        body.watchlist.cancelDrag()
        body.watchlist.snapToRow()

        // A held row keeps the cursor while the wheel scrolls the list under
        // it, and once it drops: it rides the pointer wherever its old place
        // went. From the rows review: the cursor left it as soon as its old
        // place scrolled out of sight, and the next key acted on another row.
        body.watchlist.contentY = 0
        wait(50)
        var held = body.watchlist.displayedSymbols[1]
        body.watchlist.beginDrag(held, pitch + 10)
        mouseWheel(body.watchlist, 12, pitch + 10, 0, -600, Qt.NoModifier)
        wait(700)
        var heldScrolled = [body.watchlist.cursorRow === held, body.watchlist.contentY >= 4 * pitch].join(",")
        body.watchlist.endDrag()
        wait(400)
        root.check("a held row keeps the cursor while the wheel scrolls the list under it, and once it drops",
          heldScrolled === "true,true" && body.watchlist.dragSymbol === "" && body.watchlist.cursorRow === held,
          heldScrolled + " | " + body.watchlist.cursorRow + " for " + held)
        root.setFixtureWatchlist()
        wait(100)

        // A right-click mid-glide opens the menu of the row under the
        // pointer, and its removal hands the cursor to the row that takes its
        // place, as x does. From the rows review: the cursor read the glide's
        // destination, skipped that row, and the next removal key acted on
        // the one after it.
        body.watchlist.contentY = 0
        wait(50)
        var clicked = body.watchlist.displayedSymbols[0]
        var takesPlace = body.watchlist.displayedSymbols[1]
        mouseMove(body.watchlist, 12, 10)
        mouseMove(body.watchlist, 12, 12)
        mouseWheel(body.watchlist, 12, 12, 0, -120, Qt.NoModifier)
        mouseClick(body.watchlist, 12, 12, Qt.RightButton)
        var menuFor = body.rowMenu ? body.rowMenu.symbol : ""
        takeMenuLine(0)
        wait(600)
        root.check("a right-click mid-glide opens the menu of the row under the pointer, and its removal hands the cursor to the row that takes its place",
          menuFor === clicked && body.watchlist.displayedSymbols.indexOf(clicked) < 0 && body.watchlist.cursorRow === takesPlace,
          menuFor + " menu; " + clicked + " -> " + body.watchlist.cursorRow + " for " + takesPlace)
        root.setFixtureWatchlist()
        wait(100)

        // A click or a Ctrl-click mid-glide puts the cursor on the row it
        // acts on, so x then removes that row. From Grok's review of #9: the
        // click featured the row, or showed its lists, but the bar stayed on
        // the row the glide was heading for, and x removed that one.
        var clickedThenX = function(modifiers) {
          body.watchlist.contentY = 0
          wait(50)
          var target = body.watchlist.displayedSymbols[0]
          mouseMove(body.watchlist, 12, 10)
          mouseMove(body.watchlist, 12, 12)
          mouseWheel(body.watchlist, 12, 12, 0, -120, Qt.NoModifier)
          mouseClick(body.watchlist, 12, 12, Qt.LeftButton, modifiers)
          var acted = modifiers ? body.listsSymbol === target : stub.featuredSymbol === target
          body.closeListViews()
          wait(600)
          var cursor = body.watchlist.cursorRow
          body.removeRow(cursor)
          wait(100)
          var removedIt = body.watchlist.displayedSymbols.indexOf(target) < 0
          root.setFixtureWatchlist()
          wait(100)
          return (acted && cursor === target && removedIt) + " " + target + " cursor " + cursor
        }
        var byClick = clickedThenX(Qt.NoModifier)
        var byCtrlClick = clickedThenX(Qt.ControlModifier)
        root.check("a click or a Ctrl-click mid-glide puts the cursor on its row, and x then removes that row",
          /^true /.test(byClick) && /^true /.test(byCtrlClick), byClick + " | " + byCtrlClick)

        // A double-click is one click for the list, not only for a row: its
        // second press, at the first one's place, does nothing, whichever
        // row is under it by then. And a click stops the list where it is,
        // so its row stays under the pointer. From Grok's review of #9: a
        // click glided its row away (onto a row boundary after a touchpad
        // scroll), and the second press featured the next row; after a
        // right-click's removal, the row that slid up was removed too.
        root.setFixtureWatchlist()
        wait(100)
        body.watchlist.contentY = 0
        wait(50)
        var featuredSeen = []
        var noteFeatured = function() { featuredSeen.push(stub.featuredSymbol) }
        stub.featuredSymbolChanged.connect(noteFeatured)
        body.watchlist.followBy(17)
        var partRow = body.watchlist.displayedSymbols[1]
        var partY = pitch + 2 - 17
        mouseMove(body.watchlist, 12, partY - 6)
        mouseMove(body.watchlist, 12, partY)
        mouseClick(body.watchlist, 12, partY)
        wait(200)
        mouseClick(body.watchlist, 12, partY)
        wait(400)
        stub.featuredSymbolChanged.disconnect(noteFeatured)
        var featuredOnce = featuredSeen.length > 0 && featuredSeen.every(function(s) { return s === partRow })
          && stub.featuredSymbol === partRow && body.watchlist.cursorRow === partRow
        var stayedFeatured = body.watchlist.contentY === 17
        root.setFixtureWatchlist()
        wait(100)
        body.watchlist.contentY = 0
        wait(50)
        // Off a row boundary too: a right double-click opens the row's menu
        // once, its second press no click off it, and the removal it takes
        // hands the cursor on, the list staying where the click stopped it.
        body.watchlist.followBy(17)
        var shownBefore = body.watchlist.displayedSymbols.slice()
        var thirdY = 2 * pitch + 20 - 17
        mouseMove(body.watchlist, 12, thirdY - 6)
        mouseMove(body.watchlist, 12, thirdY)
        mouseClick(body.watchlist, 12, thirdY, Qt.RightButton)
        wait(200)
        mouseClick(body.watchlist, 12, thirdY, Qt.RightButton)
        wait(100)
        var menuStayed = body.rowMenu !== null && body.rowMenu.symbol === shownBefore[2]
        takeMenuLine(0)
        wait(400)
        var shownAfter = body.watchlist.displayedSymbols
        var removedOnce = shownAfter.length === shownBefore.length - 1
          && shownAfter.indexOf(shownBefore[2]) < 0 && shownAfter.indexOf(shownBefore[3]) >= 0
          && body.watchlist.cursorRow === shownBefore[3]
        var stayedRemoved = body.watchlist.contentY === 17
        root.check("a double-click on a part-scrolled row features only that row, and a right double-click opens its menu once, which removes one row, the list staying where the click stopped it",
          featuredOnce && menuStayed && removedOnce && stayedFeatured && stayedRemoved,
          featuredSeen.join(",") + " for " + partRow + " | menu " + menuStayed + " | " + shownBefore.length + " -> " + shownAfter.length
            + " cursor " + body.watchlist.cursorRow + " | stayed " + stayedFeatured + "," + stayedRemoved)
        root.setFixtureWatchlist()
        wait(100)

        // The wheel or a key between two clicks at one place makes them two
        // clicks, even when Qt takes the second for a double-click's: the
        // second stops the list and acts, and x then removes its row. So does
        // a row's move by Shift+J. From rows-review: the second was dropped,
        // and x removed the row the glide was heading for, or the moved one.
        var between = function(interrupt) {
          body.watchlist.contentY = 0
          wait(50)
          stub.featuredSymbol = body.watchlist.displayedSymbols[5]
          var target = body.watchlist.displayedSymbols[2]
          var y = 2 * pitch + 20
          mouseMove(body.watchlist, 12, y - 6)
          mouseMove(body.watchlist, 12, y)
          var once = function() {
            stub.featuredSymbolChanged.disconnect(once)
            interrupt(y)
          }
          stub.featuredSymbolChanged.connect(once)
          mouseDoubleClickSequence(body.watchlist, 12, y)
          wait(400)
          var cursor = body.watchlist.cursorRow
          body.removeRow(cursor)
          wait(100)
          var removedIt = body.watchlist.displayedSymbols.indexOf(target) < 0
          root.setFixtureWatchlist()
          wait(100)
          return (cursor === target && removedIt) + " " + cursor + " for " + target
        }
        var afterWheel = between(function(y) { mouseWheel(body.watchlist, 12, y, 0, -120, Qt.NoModifier) })
        var afterKey = between(function() { body.moveCursor(1) })
        body.watchlist.contentY = 0
        wait(50)
        stub.featuredSymbol = body.watchlist.displayedSymbols[5]
        var takenPlace = body.watchlist.displayedSymbols[3]
        var moveY = 2 * pitch + 20
        mouseMove(body.watchlist, 12, moveY - 6)
        mouseMove(body.watchlist, 12, moveY)
        mouseClick(body.watchlist, 12, moveY)
        body.moveSelected(1)
        wait(180)
        mouseClick(body.watchlist, 12, moveY)
        wait(100)
        var afterMove = (body.watchlist.displayedSymbols[2] === takenPlace && stub.featuredSymbol === takenPlace
          && body.watchlist.cursorRow === takenPlace) + " " + stub.featuredSymbol + "/" + body.watchlist.cursorRow + " for " + takenPlace
        root.setFixtureWatchlist()
        wait(100)
        root.check("the wheel, a key, or Shift+J between two clicks at one place makes the second act, a double-click's too",
          [afterWheel, afterKey, afterMove].every(function(r) { return /^true /.test(r) }),
          [afterWheel, afterKey, afterMove].join(" | "))

        // A double-click whose first press is a view's, its second landing on
        // a row, does nothing there, even soon after a row click and the
        // wheel, or with the wheel between its presses: on Manage lists' DONE
        // as the rows come back, and outside the list menu, which dismisses
        // it over rows that stay. From rows-review: the second press featured
        // the row under it.
        //
        // Each wait is on what the next move reads. A press aimed from a row
        // still sliding into place, after the last case's rows changed, landed
        // on the order word above the list, sorted it, and left the next case
        // aiming at rows that weren't where it thought (2 failed runs in 20).
        var rowsAtRest = function() {
          var list = body.watchlist
          return !list.settling && list.dragSymbol === ""
            && list.displayedSymbols.every(function(s) { return list.rowResting(s) })
        }
        var throughView = function(open, pressAt, closedSignal, wheelBetween) {
          body.watchlist.contentY = 0
          within(3000, rowsAtRest)
          stub.featuredSymbol = body.watchlist.displayedSymbols[5]
          var row = body.watchlist.displayedSymbols[4]
          var rowY = 4 * pitch + 20
          mouseMove(body.watchlist, 12, rowY - 6)
          mouseMove(body.watchlist, 12, rowY)
          mouseClick(body.watchlist, 12, rowY)
          if (!wheelBetween) mouseWheel(body.watchlist, 12, rowY, 0, -120, Qt.NoModifier)
          open()
          // The view is open over rows that have stopped moving, so the
          // press lands where pressAt reads it.
          within(1000, function() {
            return (body.managingLists || body.listMenuOpen)
              && body.watchlist.displayedSymbols.every(function(s) { return body.watchlist.rowResting(s) })
          })
          var at = pressAt()
          var once = function() {
            closedSignal.disconnect(once)
            mouseWheel(body, at.x, at.y, 0, -120, Qt.NoModifier)
          }
          if (wheelBetween) closedSignal.connect(once)
          mouseDoubleClickSequence(body, at.x, at.y)
          within(1000, function() { return !body.managingLists && !body.listMenuOpen })
          // Nothing under the second press acted: no row featured, and the
          // order word above the rows kept its order.
          var result = (stub.featuredSymbol === row && !body.managingLists && !body.listMenuOpen && stub.order === "manual")
            + " " + stub.featuredSymbol + " for " + row + ", " + stub.order
          root.setFixtureWatchlist()
          within(3000, rowsAtRest)
          return result
        }
        var onDone = function() {
          var done = root.find(body, "manageDone")
          return done.mapToItem(body, done.width / 2, done.height / 2)
        }
        var offMenu = function() {
          var first = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
          return first.mapToItem(body, first.width - 30, first.height / 2)
        }
        var views = [
          throughView(function() { body.openManageLists() }, onDone, body.managingListsChanged, false),
          throughView(function() { body.openManageLists() }, onDone, body.managingListsChanged, true),
          throughView(function() { body.openListMenu() }, offMenu, body.listMenuOpenChanged, false),
          throughView(function() { body.openListMenu() }, offMenu, body.listMenuOpenChanged, true)
        ]
        root.check("a double-click that begins on a view, Manage lists' DONE or off the list menu, features no row under its second press",
          views.every(function(v) { return /^true /.test(v) }), views.join(" | "))

        // The key sheet closing over a resting pointer leaves the cursor
        // where the keys put it, on the body the popup and the window share,
        // though the pointer is reported again, a pixel off, as the rows come
        // back; a hand that then moves to another row still takes it. Found
        // in the live check of #9: the cursor came back on the row under the
        // still pointer.
        body.watchlist.contentY = 0
        wait(50)
        var sheetFirst = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + pitch)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2)
        wait(50)
        body.moveCursor(1)
        wait(50)
        var sheetKeyed = body.watchlist.cursorRow
        body.toggleHelp()
        wait(100)
        body.toggleHelp()
        wait(200)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + 1)
        wait(50)
        var sheetKept = body.watchlist.cursorRow
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + 2 * pitch)
        wait(50)
        root.check("the key sheet closing over a resting pointer leaves the cursor the keys put, and a hand's move takes it after",
          sheetKeyed === body.watchlist.displayedSymbols[1] && sheetKept === sheetKeyed
            && body.watchlist.cursorRow === body.watchlist.displayedSymbols[2],
          sheetKeyed + " -> " + sheetKept + " -> " + body.watchlist.cursorRow)

        // The rows coming back from behind a view, under a pointer that
        // moved while the view was open: the first report is where it rests,
        // and one a pixel off is no move. From Grok's review of #19: only a
        // pointer near where the rows last saw it rested, so that report
        // moved the cursor.
        body.watchlist.contentY = 0
        wait(50)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + pitch)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2)
        wait(50)
        body.moveCursor(1)
        wait(50)
        var viewKeyed = body.watchlist.cursorRow
        body.openManageLists()
        wait(100)
        mouseMove(sheetFirst, sheetFirst.width / 2 - 20, sheetFirst.height / 2 + 3 * pitch)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + 3 * pitch)
        wait(50)
        body.closeListViews()
        wait(200)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + 3 * pitch + 1)
        wait(50)
        var viewKept = body.watchlist.cursorRow
        // And a small real move after the rows come back counts: from the
        // last few pixels of a row, a few pixels onto the next one take the
        // cursor. Grok found the drag distance's 8 px left it behind.
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height + 20)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height - 3)
        wait(50)
        body.moveCursor(1)
        body.moveCursor(1)
        wait(50)
        var smallKeyed = body.watchlist.cursorRow
        body.toggleHelp()
        wait(100)
        body.toggleHelp()
        wait(200)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height + 3)
        wait(50)
        root.check("rows back from behind a view keep the cursor under a pointer moved meanwhile, and a few pixels onto the next row take it",
          viewKept === viewKeyed && viewKeyed === body.watchlist.displayedSymbols[1]
            && smallKeyed === body.watchlist.displayedSymbols[2] && body.watchlist.cursorRow === body.watchlist.displayedSymbols[1],
          viewKeyed + " -> " + viewKept + " | " + smallKeyed + " -> " + body.watchlist.cursorRow)

        // The surface made shorter (the window resized) until the cursor's
        // row would be below the fold keeps a cursor of your own: the list
        // scrolls to keep its row whole in sight, the rows showing and under
        // the key sheet. Found in the walk of dev on 14 October: the cursor
        // keys left on SHEL.L went to the one row still showing. And mid a
        // key's glide toward a row below the fold: found in review, stopping
        // the glide let the cursor go on the way.
        mouseMove(body, body.width / 2, 20)
        wait(50)
        var rowsInView = Math.floor((body.watchlist.height + body.watchlist.rowGap) / pitch)
        var shrinkKeeps = function(row, underSheet, midGlide) {
          body.watchlist.contentY = 0
          wait(50)
          body.watchlist.select(row)
          var gliding = body.watchlist.settling
          if (underSheet) body.toggleHelp()
          if (!midGlide) wait(50)
          body.anchors.fill = undefined
          body.height = body.chromeHeight + pitch - body.watchlist.rowGap
          wait(100)
          var w = body.watchlist
          var said = w.cursorSymbol + "," + w.cursorRow + "," + w.wholeInSight(w.displayedSymbols.indexOf(row), w.headedY)
            + (midGlide && !gliding ? ",no glide" : "")
          body.anchors.fill = body.parent
          wait(300)
          if (underSheet) body.toggleHelp()
          wait(50)
          return said
        }
        var lowRow = body.watchlist.displayedSymbols[rowsInView - 1]
        var pastRow = body.watchlist.displayedSymbols[rowsInView]
        var shrunk = [shrinkKeeps(lowRow, false, false), shrinkKeeps(lowRow, true, false), shrinkKeeps(pastRow, false, true)]
        root.check("the surface made shorter keeps a cursor of your own whole in sight, the rows showing, under the key sheet, and mid a key's glide",
          rowsInView > 1 && shrunk[0] === lowRow + "," + lowRow + ",true" && shrunk[1] === shrunk[0]
            && shrunk[2] === pastRow + "," + pastRow + ",true",
          shrunk.join(" | "))
        // And when the sight shrinks a moment before the list's own height
        // does, as the real window did: the scroll is bounded by the sight.
        // Found in the tophat of 15 October: bounded by the old height, the
        // list stayed short of the row, and the key cursor was let go.
        var w2 = body.watchlist
        var lastRow = w2.displayedSymbols[w2.displayedSymbols.length - 1]
        w2.select(lastRow)
        tryVerify(function() { return !w2.settling }, 2000)
        w2.sightHeight = pitch - w2.rowGap
        var sightFirst = w2.cursorSymbol + "," + w2.wholeInSight(w2.displayedSymbols.indexOf(lastRow), w2.headedY)
        w2.sightHeight = Qt.binding(function() { return body.rowsSightHeight })
        w2.contentY = 0
        wait(100)
        root.check("a sight that shrinks before the list's height still keeps a cursor of your own on the last row whole in sight",
          sightFirst === lastRow + ",true", lastRow + " -> " + sightFirst)

        // Under the key sheet, a cursor whose row really leaves the rows'
        // view is let go, as with the rows in sight, so x, Enter, or m act
        // on a row you can see: a removal of a row above a cursor on the
        // view's top row, and a sort that carries it below the fold. From
        // Grok's review of #24: the hidden rows kept the cursor in each.
        body.watchlist.contentY = 3 * pitch
        wait(50)
        var topRow = body.watchlist.displayedSymbols[3]
        body.watchlist.select(topRow)
        body.toggleHelp()
        wait(50)
        stub.removeSymbol(body.watchlist.displayedSymbols[1])
        wait(100)
        var afterRemoval = [body.watchlist.cursorSymbol, body.watchlist.cursorRow]
        body.toggleHelp()
        wait(50)
        root.setFixtureWatchlist()
        wait(100)
        body.watchlist.contentY = 0
        wait(50)
        var sorted = Settings.sortedSymbols(stub.symbols, stub.quotes, "pct")
        var carried = body.watchlist.displayedSymbols.filter(function(s, i) {
          return i < rowsInView - 1 && sorted.indexOf(s) > rowsInView + 1
        })[0]
        body.watchlist.select(carried)
        body.toggleHelp()
        wait(50)
        stub.order = "pct"
        stub.shown = sorted
        wait(100)
        var afterSort = [body.watchlist.cursorSymbol, body.watchlist.cursorRow]
        body.toggleHelp()
        wait(50)
        root.setFixtureWatchlist()
        wait(100)
        root.check("under the key sheet, a removal above the cursor's top row, or a sort carrying it below the fold, lets the cursor go",
          afterRemoval[0] === "" && afterRemoval[1] !== topRow && carried !== undefined
            && afterSort[0] === "" && afterSort[1] !== carried,
          topRow + " -> " + afterRemoval.join(",") + " | " + carried + " -> " + afterSort.join(","))

        // The keyboard cursor always has a row: with none of its own it sits
        // on the featured row, in sight at the top, and it is drawn as a bar,
        // not as a fill.
        body.watchlist.contentY = 0
        body.watchlist.cursorSymbol = ""
        mouseMove(body, body.width / 2, 20)
        wait(200)
        var featuredRow = body.watchlist.rowItem("MZ")
        var cursorBar = root.find(featuredRow, "cursorBar")
        root.check("with no cursor of its own the list's cursor rests on the featured row",
          body.watchlist.cursorRow === "MZ")
        body.watchlist.moveCursor(1)
        wait(50)
        root.check("the first Down moves the cursor off the featured row",
          body.watchlist.cursorRow === body.watchlist.displayedSymbols[1]
)

        // One cursor, as the shell's own panels have it: the pointer puts it
        // on the row under it; a wheel notch with the pointer still leaves
        // it, once the glide rests, on the row then under the pointer, never
        // the first row in sight; ↓ moves it on from there; the pointer
        // leaving the list leaves it. Only the cursor's row takes the hover
        // fill and the bar, and the featured row keeps its selected fill.
        // From the owner's trial: the pointer cleared the cursor, so the bar
        // went to the featured row, and after the wheel to the first row in
        // sight, wherever the pointer was; a hovered row only tinted, at 4%.
        var wl = body.watchlist
        wl.contentY = 0
        wait(50)
        var third = wl.rowItem(wl.displayedSymbols[2])
        mouseMove(third, third.width / 2, third.height / 2 - 6)
        mouseMove(third, third.width / 2, third.height / 2)
        wait(100)
        var onThird = [wl.cursorRow === wl.displayedSymbols[2]]
        mouseWheel(third, third.width / 2, third.height / 2, 0, -120, Qt.NoModifier)
        // At once, before the glide: the row that will rest under the pointer.
        var atOnce = wl.cursorRow === wl.displayedSymbols[3]
        wait(700)
        var afterWheel = [atOnce, firstWhole(wl) === 1, wl.cursorRow === wl.displayedSymbols[3], wl.cursorRow !== wl.displayedSymbols[1]]
        body.moveCursor(1)
        wait(100)
        var afterDown = [wl.cursorRow === wl.displayedSymbols[4]]
        mouseMove(body, body.width / 2, 20)
        wait(100)
        var afterLeaving = [wl.cursorRow === wl.displayedSymbols[4]]
        var steps = [onThird, afterWheel, afterDown, afterLeaving]
        root.check("one cursor: the pointer puts it on row 3, the wheel on the row under the still pointer once it rests, ↓ one row on, and leaving keeps it",
          steps.every(function(step) { return step.every(function(part) { return part === true }) }),
          steps.map(function(step) { return step.join(",") }).join(" | "))

        // A short touchpad stroke keeps the first row accessible once input ends.
        body.watchlist.contentY = 0
        body.watchlist.followBy(15)
        within(2000, function() { return !body.watchlist.settling })
        root.check("a short touchpad stroke leaves the first row accessible", firstWhole(body.watchlist) === 0)

        // Search: it takes the rows' place as it opens, then the keyboard's
        // choice (the top result) is what Enter adds, wherever the pointer
        // rests.
        body.startAdding()
        wait(100)
        root.check("opening search takes the rows' place at once", body.adding && !body.watchlist.visible)
        body.search.results = [
          { symbol: "TOPR", name: "Top Result Inc.", exchange: "NASDAQ" },
          { symbol: "SECR", name: "Second Result Inc.", exchange: "NYSE" },
          { symbol: "THRD", name: "Third Result Inc.", exchange: "NYSE" }
        ]
        body.search.answer = "results"
        wait(50)
        var third = root.findAll(body.search, "searchResult")[2]
        var overThird = third.mapToItem(body, third.width / 2, third.height / 2)
        mouseMove(body, overThird.x, overThird.y)
        wait(200)
        root.check("the pointer only tints a result", body.search.resultIndex === 0)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Return)
        wait(100)
        root.check("Enter adds the keyboard's choice, not the result under the pointer",
          stub.symbols.indexOf("TOPR") >= 0 && stub.symbols.indexOf("THRD") < 0 && !body.adding)
        // A click on a result the keyboard did not choose takes it, as Enter
        // would on it, wherever on the row it lands: the unseen label's slot
        // too. Found by the owner on 14 October: a click only chose the row.
        body.startAdding()
        wait(100)
        body.search.results = [
          { symbol: "TOPR", name: "Top Result Inc.", exchange: "NASDAQ" },
          { symbol: "SECR", name: "Second Result Inc.", exchange: "NYSE" },
          { symbol: "THRD", name: "Third Result Inc.", exchange: "NYSE" }
        ]
        body.search.answer = "results"
        wait(50)
        var thirdAgain = root.findAll(body.search, "searchResult")[2]
        var hiddenLabel = root.find(thirdAgain, "searchAdd")
        var overHiddenLabel = hiddenLabel.mapToItem(body, hiddenLabel.width / 2, hiddenLabel.height / 2)
        mouseClick(body, overHiddenLabel.x, overHiddenLabel.y)
        wait(100)
        root.check("a click on a result the keyboard did not choose adds it",
          stub.symbols.indexOf("THRD") >= 0 && !body.adding, stub.symbols.join(",") + "|" + body.adding)
        mouseMove(body, body.width / 2, 20)
        wait(200)

        // More results than the viewport holds: Down past its bottom and back
        // Up keeps the choice in view, and the scroll never leaves its bounds.
        body.startAdding()
        wait(100)
        var many = []
        for (var r = 0; r < 14; r++) many.push({ symbol: "R" + r, name: "Result " + r, exchange: "NYSE" })
        body.search.results = many
        body.search.answer = "results"
        wait(50)
        var viewport = root.find(body.search, "searchResults")
        var limit = viewport.contentHeight - viewport.height
        var inView = function() {
          var chosen = root.findAll(body.search, "searchResult")[body.search.resultIndex]
          var top = chosen.y - viewport.contentY
          return top >= 0 && top + chosen.height <= viewport.height
        }
        var arrowsHold = limit > 0
        for (var down = 0; down < 16; down++) {
          keyClick(Qt.Key_Down)
          arrowsHold = arrowsHold && inView() && viewport.contentY >= 0 && viewport.contentY <= limit
        }
        root.check("Down past the viewport keeps the choice in view and stops at the last result",
          arrowsHold && body.search.resultIndex === 13 && viewport.contentY === limit)
        arrowsHold = true
        for (var up = 0; up < 16; up++) {
          keyClick(Qt.Key_Up)
          arrowsHold = arrowsHold && inView() && viewport.contentY >= 0 && viewport.contentY <= limit
        }
        root.check("Up back past the top keeps the choice in view and rests at the top",
          arrowsHold && body.search.resultIndex === 0 && viewport.contentY === 0)
        keyClick(Qt.Key_Escape)
        wait(50)

        // A view still showing as its surface closes takes nothing: a click
        // on a result or a checklist box acts on nothing and takes no focus.
        // Found in the review of the untangle: during the popup's close fade
        // a click on a result added it. The surface's closing is surfaceOpen
        // going false, as the popup's fade begins.
        body.startAdding()
        wait(100)
        body.search.results = [{ symbol: "LATE", name: "Late Inc.", exchange: "NYSE" }]
        body.search.answer = "results"
        wait(50)
        body.surfaceOpen = false
        var lateRow = root.findAll(body.search, "searchResult")[0]
        var overLate = lateRow.mapToItem(body, lateRow.width / 2, lateRow.height / 2)
        mouseClick(body, overLate.x, overLate.y)
        wait(50)
        var searchInert = stub.symbols.indexOf("LATE") < 0 && body.adding && !body.search.activeFocus
        body.surfaceOpen = true
        wait(50)
        body.cancelAdding()
        body.openSymbolLists(stub.symbols[0])
        wait(100)
        body.surfaceOpen = false
        var box = root.find(body, "symbolLists")
        var overBox = box.mapToItem(body, box.width / 2, Style.space(45))
        mouseClick(body, overBox.x, overBox.y)
        wait(50)
        var listsInert = stub.memberships.length === 0 && !box.activeFocus
        body.surfaceOpen = true
        body.closeListViews()
        wait(50)
        root.check("a view showing through its surface's close takes no click and no focus",
          searchInert && listsInert, searchInert + "|" + listsInert + "|" + stub.memberships)

        // Nothing else on a closing surface acts either: a click, a right-click,
        // or the wheel on a row, a click on the footer or the header's look,
        // and the pointer over the chart, in smooth and in retro. Found in
        // cubic's review of #25: the card took clicks through its close fade.
        var inert = function() {
          mouseMove(body, 1, 1)
          wait(50)
          var rows = body.watchlist.displayedSymbols.slice()
          var target = rows[1]
          var hero = stub.featuredSymbol
          var settings = stub.lastSettings
          var scrolled = body.watchlist.contentY
          var cursor = body.watchlist.cursorRow
          body.surfaceOpen = false
          var row = body.watchlist.rowItem(target)
          var overRow = row.mapToItem(body, row.width / 2, row.height / 2)
          mouseClick(body, overRow.x, overRow.y)
          mouseClick(body, overRow.x, overRow.y, Qt.RightButton)
          mouseWheel(body, overRow.x, overRow.y, 0, -120)
          var footer = root.find(body, "footer")
          var overFooter = footer.mapToItem(body, footer.width / 2, footer.height / 2)
          mouseClick(body, overFooter.x, overFooter.y)
          var look = root.find(body, "lookIcon")
          var overLook = look.mapToItem(body, look.width / 2, look.height / 2)
          mouseClick(body, overLook.x, overLook.y)
          var chart = body.chartItem
          var overChart = chart.mapToItem(body, chart.width / 3, chart.height / 2)
          mouseMove(body, overChart.x, overChart.y)
          mouseMove(body, overChart.x + 20, overChart.y)
          wait(300)
          var still = [stub.featuredSymbol === hero, body.watchlist.displayedSymbols.join() === rows.join(),
            body.watchlist.contentY === scrolled, !body.adding, stub.lastSettings === settings,
            body.scrubT === 0, body.watchlist.cursorRow === cursor, body.rowMenu === null].join(",")
          body.surfaceOpen = true
          mouseMove(body, 1, 1)
          wait(50)
          return still
        }
        var smoothInert = inert()
        stub.retro = true
        wait(50)
        var retroInert = inert()
        stub.retro = false
        wait(50)
        root.check("a closing surface takes no click, right-click, wheel, or scrub, smooth and retro",
          smoothInert === "true,true,true,true,true,true,true,true" && retroInert === smoothInert, smoothInert + " | " + retroInert)

        var orderWord = root.find(body, "orderLabel")
        var orderWas = stub.order
        var edgeFaults = []
        var arrowGlyph = Qt.createQmlObject('import QtQuick; TextMetrics {}', root)
        arrowGlyph.font = orderWord.font
        arrowGlyph.text = orderWord.text.charAt(0)
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          stub.order = "pct"
          wait(20)
          ;[arrowGlyph.boundingRect.x + 1, arrowGlyph.boundingRect.x + arrowGlyph.boundingRect.width - 1].forEach(function(x) {
            stub.lastSettings = null
            var at = orderWord.mapToItem(body, x, orderWord.height / 2)
            mouseClick(body, at.x, at.y)
            if (!stub.lastSettings || stub.lastSettings.reversed === undefined) edgeFaults.push(retro + " at " + x)
          })
        })
        arrowGlyph.destroy()
        var breadth = root.find(body, "breadthRule")
        var breadthEnd = breadth.mapToItem(body, breadth.width - 2, breadth.height / 2)
        mouseMove(body, breadthEnd.x, breadthEnd.y)
        within(2000, function() { return breadth.revealed })
        var breadthWords = root.find(body, "breadthCounts")
        root.check("the order arrow leaves the breadth rule's end available for its counts", breadth.revealed && breadthWords.visible && breadthWords.text !== "")
        stub.retro = false
        stub.order = orderWas
        root.check("both visible edges of a sorted order's arrow act in both looks", edgeFaults.length === 0, edgeFaults.join(" | "))

        // Since the open, the hero's caption names it, in the slot AT CLOSE
        // would take, and the figure is bare; a row says "open" inline.
        stub.featuredSymbol = "MZ"
        stub.changeMode = "open"
        wait(50)
        var heroCaption = root.find(body, "changeCaption")
        var heroChange = root.find(body, "changeText")
        var firstShown = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
        root.check("a change since the open is captioned SINCE OPEN, never AT CLOSE",
          heroCaption.text === "SINCE OPEN" && heroChange.text.indexOf("open") < 0
            && firstShown.view.changeLine.indexOf(" open") > 0)
        stub.changeMode = "pct"
        wait(50)

        root.setQuotes(["FIT1", "FIT2"], [101, 102])
        wait(200)
        // The row's menu removes a row from All; the last one stays, and the
        // footer says why for a moment.
        var fit2 = body.watchlist.rowItem("FIT2")
        mouseClick(fit2, fit2.width / 2, fit2.height / 2, Qt.RightButton)
        takeMenuLine(0)
        wait(200)
        var fit1 = body.watchlist.rowItem("FIT1")
        mouseClick(fit1, fit1.width / 2, fit1.height / 2, Qt.RightButton)
        takeMenuLine(0)
        wait(50)
        root.check("the last row stays and the footer says why",
          stub.symbols.join(",") === "FIT1" && body.note === "Keep at least one symbol", stub.symbols + "|" + body.note)
        wait(2700)
        root.check("the note clears on its own", body.note === "")

        // In a sorted order a row can't move by hand: a drag and J leave the
        // order as it was and say why in the footer, the way a refused
        // removal does. Found in the mouse audit: a drag in symbol order did
        // nothing, and nothing said why.
        root.setQuotes(["FIT1", "FIT2", "FIT3"], [101, 102, 103])
        stub.order = "pct"
        wait(200)
        var sortedMoves = []
        var refusedNote = "Switch to manual order to move rows"
        var lift = body.watchlist.rowItem("FIT1")
        mousePress(lift, lift.width / 2, lift.height / 2)
        mouseMove(lift, lift.width / 2, lift.height / 2 + 20)
        mouseMove(lift, lift.width / 2, lift.height * 2)
        mouseRelease(lift, lift.width / 2, lift.height * 2)
        wait(100)
        sortedMoves.push("drag " + stub.symbols.join(",") + " " + JSON.stringify(body.note))
        body.note = ""
        body.watchlist.cursorSymbol = "FIT2"
        body.moveSelected(1)
        wait(50)
        sortedMoves.push("J " + stub.symbols.join(",") + " " + JSON.stringify(body.note))
        root.check("a drag and J in a sorted order move nothing and say why",
          sortedMoves.every(function(m) { return m.indexOf(" FIT1,FIT2,FIT3 " + JSON.stringify(refusedNote)) > 0 }),
          sortedMoves.join(" | "))
        body.note = ""
        stub.order = "manual"
        wait(50)

        // A cursor you put on a row, by pointer or key, shows its remove
        // button, as the shell's Bluetooth panel shows Forget; the cursor
        // resting on the featured row shows none. A click on it removes that
        // row, a double-click one row only, and nothing else on the row
        // moves. The ? sheet says a right-click offers to remove a row.
        // Found in the mouse audit: nothing on screen said a row could be
        // removed.
        root.setQuotes(["FIT1", "FIT2", "FIT3", "FIT4"], [101, 102, 103, 104])
        mouseMove(body, body.width / 2, body.height - 4)
        body.watchlist.cursorSymbol = ""
        wait(200)
        var removeOf = function(symbol) {
          var r = body.watchlist.rowItem(symbol)
          return r ? root.find(r, "rowRemove") : null
        }
        var removesShown = function() {
          return stub.symbols.filter(function(s) { var b = removeOf(s); return b && b.visible }).join(",") || "none"
        }
        var removeSteps = ["rest " + removesShown()]
        var fit2 = body.watchlist.rowItem("FIT2")
        // The first place a pointer is seen at is no move (RowPointer).
        mouseMove(fit2, fit2.width / 2, fit2.height / 2 - 6)
        mouseMove(fit2, fit2.width / 2, fit2.height / 2)
        wait(100)
        removeSteps.push("pointer " + removesShown())
        var fit2Remove = removeOf("FIT2")
        // An explicit remove control needs no tooltip over the next row.
        var removeLooks = "missing"
        if (fit2Remove && fit2Remove.visible) {
          var onRemove = fit2Remove.mapToItem(body, fit2Remove.width / 2, fit2Remove.height / 2)
          mouseMove(body, onRemove.x, onRemove.y)
          wait(600)
          removeLooks = fit2Remove.data.filter(function(d) { return d.opened === true }).length === 0 ? "no tip" : "open tip"
          mouseMove(fit2, fit2.width / 2, fit2.height / 2)
        }
        root.check("the remove button opens no tooltip over the next row", removeLooks === "no tip", removeLooks)
        // A slip removes nothing: a press beside the button released on it,
        // or a press on it released beside it. Found in review: the first
        // removed the row.
        // Both slips' places, read before either: a slip that removed the
        // row would take its button with it.
        var slips = fit2Remove && fit2Remove.visible ? [[-1, 2], [1, -2]].map(function(s) {
          return [fit2Remove.mapToItem(body, s[0], fit2Remove.height / 2), fit2Remove.mapToItem(body, s[1], fit2Remove.height / 2)]
        }) : []
        slips.forEach(function(s) {
          mousePress(body, s[0].x, s[0].y)
          mouseMove(body, s[1].x, s[1].y)
          mouseRelease(body, s[1].x, s[1].y)
          wait(Application.styleHints.mouseDoubleClickInterval + 50)
        })
        removeSteps.push("slips " + stub.symbols.join(","))
        fit2Remove = removeOf("FIT2")
        var slidAt = fit2Remove ? fit2Remove.mapToItem(body, fit2Remove.width / 2, fit2Remove.height / 2) : Qt.point(-1, -1)
        if (fit2Remove && fit2Remove.visible) mouseClick(fit2Remove, fit2Remove.width / 2, fit2Remove.height / 2)
        wait(200)
        removeSteps.push("click " + stub.symbols.join(","))
        // The row that slid into its place, under the still pointer, shows
        // no remove button, so another click there features it; a move of
        // the pointer shows it. Found by the design panel of 23 October: a
        // click on Toyota's × put Tesla's under the still pointer, and one
        // more click removed Tesla.
        removeSteps.push("slid " + body.watchlist.cursorRow + " " + removesShown())
        wait(Application.styleHints.mouseDoubleClickInterval + 50)
        mouseClick(body, slidAt.x, slidAt.y)
        wait(200)
        removeSteps.push("again " + stub.symbols.join(",") + " " + stub.featuredSymbol)
        wait(Application.styleHints.mouseDoubleClickInterval + 50)
        mouseMove(body, slidAt.x + 3, slidAt.y)
        wait(100)
        removeSteps.push("moved " + removesShown())
        var nextRemove = removeOf("FIT3")
        if (nextRemove && nextRemove.visible) mouseDoubleClickSequence(nextRemove, nextRemove.width / 2, nextRemove.height / 2)
        wait(300)
        removeSteps.push("double " + stub.symbols.join(","))
        mouseMove(body, body.width / 2, body.height - 4)
        body.watchlist.cursorSymbol = ""
        wait(100)
        body.moveCursor(1)
        wait(100)
        var keyed = body.watchlist.cursorRow
        removeSteps.push("key " + removesShown())
        // A press on the button and a move still lift the row: the button
        // takes only a click.
        var keyedRemove = removeOf(keyed)
        if (keyedRemove && keyedRemove.visible) {
          var grip = keyedRemove.mapToItem(body, keyedRemove.width / 2, keyedRemove.height / 2)
          var toward = (keyed === "FIT1" ? 1 : -1) * body.watchlist.rowPitch
          mousePress(body, grip.x, grip.y)
          mouseMove(body, grip.x, grip.y + toward / 4)
          mouseMove(body, grip.x, grip.y + toward)
          mouseRelease(body, grip.x, grip.y + toward)
          wait(400)
        }
        removeSteps.push("lift " + stub.symbols.join(","))
        root.check("a cursor you put on a row shows its remove button, the resting one none; a click on it removes that row, a slip nothing, and the row sliding under the still pointer shows none until it moves; a double-click removes one, a press and move lifts the row",
          keyed !== "" && removeSteps.join(" | ") === "rest none | pointer FIT2 | slips FIT1,FIT2,FIT3,FIT4 | click FIT1,FIT3,FIT4 | slid FIT3 none"
            + " | again FIT1,FIT3,FIT4 FIT3 | moved FIT3 | double FIT1,FIT4 | key " + keyed + " | lift FIT4,FIT1",
          removeSteps.join(" | "))

        // A removal by the button is decided at its press and done at a
        // release on it, even a double-click's second press, which Qt acts
        // on at mouse-down: a click on one row's button, a wheel notch, a
        // pixel's move, which shows the button of the row now under the
        // pointer, then a quick press on it. Slid off and let go, it removes
        // nothing more; held past the double-click interval and let go on
        // the button, it removes that row. Found in the reviews of #32: the
        // second went at mouse-down, so a slip couldn't cancel it; then,
        // decided at release, a held one did nothing. The events one by one,
        // as Qt sends a double-click: press, release, press, double-click,
        // release.
        var secondPress = function(release) {
          root.setQuotes(["FIT1", "FIT2", "FIT3"], [101, 102, 103])
          wait(200)
          var firstRow = body.watchlist.rowItem("FIT1")
          mouseMove(firstRow, firstRow.width / 2, firstRow.height / 2 - 6)
          mouseMove(firstRow, firstRow.width / 2, firstRow.height / 2)
          wait(100)
          var firstRemove = removeOf("FIT1")
          var onButton = firstRemove && firstRemove.visible ? firstRemove.mapToItem(body, firstRemove.width / 2, firstRemove.height / 2) : null
          // Each removal, in order.
          var removals = []
          var symbolsBefore = stub.symbols.slice()
          var watchRemovals = function() {
            symbolsBefore.forEach(function(s) { if (stub.symbols.indexOf(s) < 0) removals.push(s) })
            symbolsBefore = stub.symbols.slice()
          }
          stub.symbolsChanged.connect(watchRemovals)
          if (onButton) {
            mousePress(body, onButton.x, onButton.y)
            mouseRelease(body, onButton.x, onButton.y)
            wait(120)
            mouseWheel(body, onButton.x, onButton.y, 0, -120, Qt.NoButton, Qt.NoModifier)
            var moved = Qt.point(onButton.x + 1, onButton.y)
            mouseMove(body, moved.x, moved.y)
            mousePress(body, moved.x, moved.y)
            // TestCase has no lone double-click event in Qt 6; its sender does.
            qtest_events.mouseDoubleClick(body, moved.x, moved.y, Qt.LeftButton, Qt.NoModifier, -1)
            release(moved)
          }
          wait(300)
          stub.symbolsChanged.disconnect(watchRemovals)
          return removals.join(",") + " -> " + stub.symbols.join(",")
        }
        var slidOff = secondPress(function(at) {
          mouseMove(body, at.x - Style.space(30), at.y)
          mouseRelease(body, at.x - Style.space(30), at.y)
        })
        var heldLong = secondPress(function(at) {
          wait(Application.styleHints.mouseDoubleClickInterval + 100)
          mouseRelease(body, at.x, at.y)
        })
        root.check("a double-click's second press on a remove button, after the wheel, removes nothing let go off it, and its row let go on it however late",
          slidOff === "FIT1 -> FIT2,FIT3" && heldLong === "FIT1,FIT2 -> FIT3", slidOff + " | " + heldLong)

        // A row the wheel scrolls under a still pointer takes the cursor but
        // shows no remove button, so a click there features it; the button
        // shows once the pointer really moves, or a key moves the cursor. A
        // tick that moves the list less than a row, leaving the row under
        // the pointer, hides it too. Every symbol here is as long as the
        // next, so each row's button sits where the one above it sat. Found
        // in the edge pass of 15 October: a notch put 7203.T's button under
        // the pointer, and the click meant to feature it removed it.
        var even = root.symbols(20)
        root.setQuotes(even, even.map(function(s, i) { return 100 + i }))
        body.watchlist.contentY = 0
        wait(200)
        var secondRow = body.watchlist.rowItem(even[1])
        mouseMove(secondRow, secondRow.width / 2, secondRow.height / 2 - 6)
        mouseMove(secondRow, secondRow.width / 2, secondRow.height / 2)
        wait(100)
        var secondRemove = removeOf(even[1])
        var waits = ["pointer " + removesShown()]
        if (secondRemove && secondRemove.visible) {
          var onSecond = secondRemove.mapToItem(body, secondRemove.width / 2, secondRemove.height / 2)
          mouseMove(body, onSecond.x, onSecond.y)
          wait(100)
          mouseWheel(body, onSecond.x, onSecond.y, 0, -120, Qt.NoButton, Qt.NoModifier)
          wait(600)
          waits.push("wheel " + body.watchlist.cursorRow + " " + removesShown())
          mouseClick(body, onSecond.x, onSecond.y)
          wait(200)
          waits.push("click " + stub.featuredSymbol + " " + stub.symbols.length + " " + removesShown())
          wait(Application.styleHints.mouseDoubleClickInterval + 50)
          mouseMove(body, onSecond.x + 3, onSecond.y)
          wait(100)
          waits.push("move " + removesShown())
          mouseWheel(body, onSecond.x + 3, onSecond.y, 0, -120, Qt.NoButton, Qt.NoModifier)
          wait(600)
          body.moveCursor(1)
          wait(300)
          waits.push("key " + body.watchlist.cursorRow + " " + removesShown())
          mouseMove(body, onSecond.x, onSecond.y)
          wait(100)
          var before = body.watchlist.cursorRow + " " + removesShown()
          mouseWheel(body, onSecond.x, onSecond.y, 0, -30, Qt.NoButton, Qt.NoModifier)
          wait(600)
          waits.push("tick " + before + " " + body.watchlist.cursorRow + " " + removesShown())
          // A click during a glide stops the list on a row on the way, which
          // waits too. Found in review: 30 ms into four notches, the row the
          // click stopped on showed its button at once.
          mouseMove(body, onSecond.x + 3, onSecond.y)
          wait(100)
          for (var notch = 0; notch < 4; notch++) mouseWheel(body, onSecond.x + 3, onSecond.y, 0, -120, Qt.NoButton, Qt.NoModifier)
          wait(30)
          mouseClick(body, onSecond.x + 3, onSecond.y)
          wait(200)
          waits.push("glide " + (stub.featuredSymbol === body.watchlist.cursorRow) + " " + stub.symbols.length + " " + removesShown())
        }
        root.check("a row the wheel scrolls under a still pointer shows no remove button, a click there features it, mid-glide too, and a move or a key shows it",
          waits.join(" | ") === ["pointer " + even[1], "wheel " + even[2] + " none", "click " + even[2] + " 20 none",
            "move " + even[2], "key " + even[4] + " " + even[4], "tick " + even[3] + " " + even[3] + " " + even[3] + " none",
            "glide true 20 none"].join(" | "),
          waits.join(" | "))
        body.showingHelp = true
        wait(100)
        var gestures = root.findAll(body, "helpGesture").map(function(k) { return k.text + ": " + k.parent.children[1].text })
        body.showingHelp = false
        wait(100)
        root.check("the ? sheet says a right-click on a row offers to remove it",
          gestures.some(function(g) { return /^row: .*right-click offers to remove it/.test(g) }), gestures.join(" | "))


        // Sliding off cancels a press. Only the pressed ink moved to review.
        body.closeListViews()
        body.showingHelp = false
        stub.range = "1D"
        stub.order = "pct"
        stub.lists = [{name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols.slice()},
          {name: "Watching", label: "Watching", count: 0, symbols: []}]
        var status = root.find(body, "statusText")
        var away = status.mapToItem(body, status.width / 2, status.height / 2)
        var settings = function() {
          return [stub.range, stub.order, body.showingHelp, body.listMenuOpen, JSON.stringify(stub.lastSettings), body.adding, body.managingLists,
            JSON.stringify(stub.memberships), stub.symbols.join("|")].join(",")
        }
        var pressedIn = function(item) {
          if (item.pressed === true) return true
          return item.children.some(function(child) { return pressedIn(child) })
        }
        var pressOn = function(name, fill, target) {
          var at = target.mapToItem(body, target.width / 2, target.height / 2)
          mouseMove(body, away.x, away.y)
          var before = settings()
          mousePress(body, at.x, at.y)
          var reached = pressedIn(fill.parent)
          mouseMove(body, away.x, away.y)
          mouseRelease(body, away.x, away.y)
          var after = settings()
          return reached && after === before ? "" : name + ": pressed=" + reached + " " + before + " -> " + after
        }
        var pressFaults = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          stub.lastSettings = null
          waitForRendering(body)
          var look = retro ? "retro " : "smooth "
          var token = root.findAll(root.find(body, "rangeRow"), "rangeToken")[1]
          var controls = [
            ["range token", token, token],
            ["list name", root.find(body, "listControl"), root.find(body, "listLabel")],
            ["order word", root.find(body, "orderControl"), root.find(body, "orderLabel")],
            ["order arrow", root.find(body, "orderArrowFill"), root.find(body, "orderArrow")],
            ["unit sign", root.find(body, "unitFill"), root.find(body, "unitTarget")],
            ["look icon", root.find(body, "lookFill"), root.find(body, "lookIcon")],
            ["help mark", root.find(body, "helpFill"), root.find(body, "helpMark")],
            ["footer", root.find(body, "footerFill"), root.find(body, "footerText")]
          ]
          controls.forEach(function(c) {
            var fault = pressOn((look + c[0]).replace(/ /g, "-"), c[1], c[2])
            if (fault !== "") pressFaults.push(fault)
          })
          body.openManageLists()
          wait(100)
          var doneAction = root.find(body, "manageDone")
          var actionFault = pressOn((look + "list view action").replace(/ /g, "-"), root.find(doneAction, "actionFill"), doneAction)
          if (actionFault !== "") pressFaults.push(actionFault)
          body.closeListViews()
          wait(100)
          // The rows that name a key are buttons too: a symbol's list, past
          // the opening's double-click moment, and a search result.
          body.openSymbolLists(stub.symbols[0])
          wait(Application.styleHints.mouseDoubleClickInterval + 100)
          var listRow = root.findAll(body, "symbolListRow")[1]
          var listFault = pressOn((look + "symbol list row").replace(/ /g, "-"), root.find(listRow, "rowFill"), listRow)
          if (listFault !== "") pressFaults.push(listFault)
          body.closeListViews()
          wait(100)
          body.startAdding()
          body.search.results = [
            { symbol: "TOPR", name: "Top Result Inc.", exchange: "NASDAQ" },
            { symbol: "SECR", name: "Second Result Inc.", exchange: "NYSE" }
          ]
          body.search.answer = "results"
          wait(100)
          var resultRow = root.findAll(body.search, "searchResult")[1]
          var resultFault = pressOn((look + "search result").replace(/ /g, "-"), resultRow, resultRow)
          if (resultFault !== "") pressFaults.push(resultFault)
          body.cancelAdding()
          wait(100)
        })
        stub.retro = false
        root.check("releasing a press off a control cancels it, for every control in both looks",
          pressFaults.length === 0, pressFaults.join(" | "))

        // The list views follow the wheel as the rows do: scrolled under a
        // still pointer, the cursor goes to the row then under it, so Enter
        // never acts on a row scrolled out of sight. From the rows review:
        // the cursor stayed on the row the pointer had left.
        var many = [{ name: "", label: "All", count: 1, symbols: ["FIT1"] }]
        for (var n = 1; n < 15; n++) many.push({ name: "L" + n, label: "List " + n, count: 0, symbols: [] })
        stub.lists = many
        wait(50)
        // Opens a view at its top with the pointer on its second row and
        // wheels two notches under it; `interrupt`, if any, acts 30 ms in,
        // while the wheel's motion runs. Says the cursor then and at rest.
        var wheeled = function(open, close, viewName, rowName, interrupt) {
          open()
          wait(100)
          var view = root.find(body, viewName)
          var rows = root.findAll(view, rowName)
          var at = rows[1].mapToItem(body, rows[1].width / 2, rows[1].height / 2)
          mouseMove(body, at.x, at.y - 6)
          mouseMove(body, at.x, at.y)
          wait(50)
          var pointed = view.cursor
          mouseWheel(body, at.x, at.y, 0, -240, Qt.NoModifier)
          var stopped = -1
          if (interrupt) {
            wait(30)
            interrupt()
            stopped = view.cursor
          }
          wait(400)
          var under = -1
          rows.forEach(function(row, i) { if (row.contains(row.mapFromItem(body, at.x, at.y))) under = i })
          var rested = view.cursor
          close()
          wait(100)
          return { pointed: pointed, under: under, stopped: stopped, rested: rested }
        }
        // A key, or the surface closing with the view showing through its
        // fade, while the wheel's motion runs stops it: the cursor moves no
        // further. From the rows re-review: the motion carried it on past the
        // key's row, and on through the close.
        var wheels = [
          [function() { body.openListMenu() }, function() { body.closeListMenu() }, "listMenu", "listChoice"],
          [function() { body.openSymbolLists("FIT1") }, function() { body.closeListViews() }, "symbolLists", "symbolListRow"],
          [function() { body.openManageLists() }, function() { body.closeListViews() }, "manageLists", "manageRow"]
        ].map(function(v) {
          var free = wheeled(v[0], v[1], v[2], v[3], null)
          var keyed = wheeled(v[0], v[1], v[2], v[3], function() { keyClick(Qt.Key_Down) })
          var closed = wheeled(v[0], v[1], v[2], v[3], function() { body.surfaceOpen = false })
          body.surfaceOpen = true
          wait(50)
          return [free.pointed === 1 && free.under > 1 && free.rested === free.under,
            keyed.rested === keyed.stopped, closed.rested === closed.stopped].join(",")
            + " " + v[2] + " " + JSON.stringify([free, keyed, closed])
        })
        root.check("in the list menu, a symbol's lists, and Manage lists, the wheel under a still pointer moves the cursor to the row then under it, until a key or a close stops it",
          wheels.every(function(w) { return w.indexOf("true,true,true ") === 0 }), wheels.join(" | "))

        // A view showing through its surface's close moves no cursor as the
        // pointer moves over it. From the rows review of the stale pointer
        // fix: the pointer onto All moved all three views' cursors.
        var closing = [
          [function() { body.openListMenu() }, function() { body.closeListMenu() }, "listMenu", "listChoice"],
          [function() { body.openSymbolLists("FIT1") }, function() { body.closeListViews() }, "symbolLists", "symbolListRow"],
          [function() { body.openManageLists() }, function() { body.closeListViews() }, "manageLists", "manageRow"]
        ].map(function(v) {
          v[0]()
          wait(100)
          var view = root.find(body, v[2])
          var rows = root.findAll(view, v[3])
          var onTwo = rows[2].mapToItem(body, rows[2].width / 2, rows[2].height / 2)
          var onAll = rows[0].mapToItem(body, rows[0].width / 2, rows[0].height / 2)
          mouseMove(body, onTwo.x, onTwo.y - 6)
          mouseMove(body, onTwo.x, onTwo.y)
          wait(50)
          var before = view.cursor
          body.surfaceOpen = false
          mouseMove(body, onAll.x, onAll.y - 6)
          mouseMove(body, onAll.x, onAll.y)
          wait(50)
          var after = view.cursor
          body.surfaceOpen = true
          v[1]()
          wait(50)
          return (before === 2 && after === 2) + " " + v[2] + " " + before + "->" + after
        })
        root.check("a list view showing through its surface's close moves no cursor as the pointer passes",
          closing.every(function(c) { return c.indexOf("true ") === 0 }), closing.join(" | "))

        console.log("POINTER DONE")
        done.exitCode = root.failures ? 1 : 0
        done.start()
      }
    }
  }

  HarnessExit { id: done }
}
