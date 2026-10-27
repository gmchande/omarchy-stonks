import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin/Chart.js" as Chart
import "plugin/Cells.js" as Cells
import "plugin/Format.js" as Format
import "plugin/Fundamentals.js" as Fundamentals
import "plugin/History.js" as History
import "plugin/Market.js" as Market
import "plugin/Overnight.js" as Overnight
import "plugin/Quote.js" as Quote
import "plugin/Settings.js" as Settings
import "plugin/Search.js" as Search
import "plugin/Figures.js" as Figures
import "plugin"

// Nothing jumps. The 22-symbol list with a cap symbol, an ETF, non-US
// listings in Toronto, Tokyo, and London, a four-digit price, and a price
// wide enough to force a shrink, on the day and on a range, at both surface
// sizes and in both looks: the
// listing line, the price's measured top line, baseline and left edge, the
// change's baseline and right edge, the range row, the info block, the
// header's look control and the end of its words, the list's TODAY and its
// rule, and the first row must not move with the look, and the first row
// must not move with the symbol or the range. Both looks' digits start on
// the band's left edge. The header's words keep room for its longest states
// at the popup's width. The footer sits one gap under the rows whichever
// list shows, the window's too, at its bottom once its list fills it, the
// window's chart taking what whole rows leave over, the
// rows stop short of the scrollbar's gutter, an open list menu makes room
// for itself, and the window's smallest permitted height still holds a whole
// row. The price and change text are measured as displayed, at whatever size
// they were fitted to. Every key-hint row is one line of six keys at most.
// Nothing is mapped into the running shell.
Harness {
  id: root
  marker: "LAYOUT DONE"

  readonly property string fixtures: Quickshell.env("STONKS_FIXTURES")

  FileView { id: watchlistFile; path: root.fixtures + "/list-22.json"; blockLoading: true }
  FileView { id: vfiaxFile; path: root.fixtures + "/search-vfiax.json"; blockLoading: true }
  FileView { id: eurusdFile; path: root.fixtures + "/search-eurusd.json"; blockLoading: true }
  FileView { id: searchFile; path: root.fixtures + "/search.json"; blockLoading: true }
  FileView { id: aaplFile; path: root.fixtures + "/aapl.json"; blockLoading: true }
  FileView { id: spyFile; path: root.fixtures + "/spy-2026-09-11-day-prepost.json"; blockLoading: true }
  FileView { id: shopFile; path: root.fixtures + "/shop-to.json"; blockLoading: true }
  FileView { id: aaplWeeklyFile; path: root.fixtures + "/history/aapl-5y.json"; blockLoading: true }
  FileView { id: aaplYearFile; path: root.fixtures + "/history/aapl-1y.json"; blockLoading: true }
  FileView { id: btcFile; path: root.fixtures + "/moments/listings-2026-10-07-1455/btc-usd.json"; blockLoading: true }
  FileView { id: btcYearFile; path: root.fixtures + "/history/btc-usd-1y.json"; blockLoading: true }
  FileView { id: shopYearFile; path: root.fixtures + "/history/shop-to-1y.json"; blockLoading: true }
  FileView { id: youngFile; path: root.fixtures + "/history/fab-max.json"; blockLoading: true }
  FileView { id: tokyoFile; path: root.fixtures + "/7203-t-day.json"; blockLoading: true }
  FileView { id: londonFile; path: root.fixtures + "/shel-l-day.json"; blockLoading: true }
  // A coin under a cent and a six-figure price, each in its own decimals.
  FileView { id: shibFile; path: root.fixtures + "/moments/listings-2026-10-08-1054/shib-usd.json"; blockLoading: true }
  FileView { id: berkshireFile; path: root.fixtures + "/moments/listings-2026-10-08-1054/brk-a.json"; blockLoading: true }
  // NEST on the first live night, Monday 5 October 00:36: its day, its 1M
  // history, and Robinhood's prints, so its hero carries the overnight line.
  FileView { id: liveFile; path: root.fixtures + "/moments/live-2026-10-05/nest.json"; blockLoading: true }
  FileView { id: liveMonthFile; path: root.fixtures + "/moments/live-2026-10-05/nest-1m.json"; blockLoading: true }
  FileView { id: liveNightFile; path: root.fixtures + "/moments/live-2026-10-05/robinhood-day.json"; blockLoading: true }
  // The power-user walk's thin days, Friday 16 October: CKX's one bar,
  // CVR's none; and the S&P 500 on Monday 28 September at 08:00, before its
  // bell, with no print yet.
  FileView { id: ckxFile; path: root.fixtures + "/moments/power-user-2026-10-16/ckx.json"; blockLoading: true }
  FileView { id: cvrFile; path: root.fixtures + "/moments/power-user-2026-10-16/cvr.json"; blockLoading: true }
  FileView { id: preOpenIndexFile; path: root.fixtures + "/moments/monday/gspc.json"; blockLoading: true }
  FileView { id: indexDayFile; path: root.fixtures + "/first-day-2026-10-14/n225-day.json"; blockLoading: true }
  FileView { id: calendarFile; path: Quickshell.env("STONKS_CALENDARS"); blockLoading: true }

  // The hero chart's rendered frames, for frames.js.
  FrameGrab { id: grab }

  function fundamentalsAnswer(path) {
    return JSON.parse(readFile(root.fixtures + "/fundamentals/" + path + ".json"))
  }

  // Saved fundamentals, the cap with its close, as the feed keeps them.
  function figures(name) {
    return Fundamentals.withCapClose(Fundamentals.parseFundamentals(fundamentalsAnswer(name)), fundamentalsAnswer(name + "-closes"))
  }

  // Yahoo's saved rate for a pair, as the feed keeps it.
  function rate(pair) {
    return { value: Fundamentals.parseRate(fundamentalsAnswer("fx-" + pair.toLowerCase()), pair), checkedAt: 0 }
  }

  function yIn(item, y) { return Math.round(item.mapToItem(body, 0, y).y) }
  function xIn(item, x) { return Math.round(item.mapToItem(body, x, 0).x) }
  // What's wrong with where an open tip lies, or "": all of it, its
  // background as well as its words, since a style may draw the background
  // wider (found in review), must lie under its icon, within the body's
  // width and the window's height.
  function tipFault(tip, icon) {
    var drawn = [tip.background, tip.contentItem].map(function(item) {
      var at = item.mapToItem(null, 0, 0)
      return { left: at.x, top: at.y, right: at.x + item.width, bottom: at.y + item.height }
    })
    var left = Math.round(Math.min(drawn[0].left, drawn[1].left))
    var right = Math.round(Math.max(drawn[0].right, drawn[1].right))
    var top = Math.round(Math.min(drawn[0].top, drawn[1].top))
    var bottom = Math.round(Math.max(drawn[0].bottom, drawn[1].bottom))
    var iconBottom = Math.round(icon.mapToItem(null, 0, icon.height).y)
    var bodyLeft = Math.round(body.mapToItem(null, 0, 0).x)
    if (top < iconBottom) return "its tip starts at " + top + ", not under its icon's " + iconBottom
    if (left < bodyLeft || right > bodyLeft + Math.round(body.width)) return "its tip runs from " + left + " to " + right + ", out of the body's " + bodyLeft + " to " + Math.round(bodyLeft + body.width)
    if (bottom > window.height) return "its tip runs to " + bottom + ", out of the window"
    return ""
  }
  function openTips(item, into) {
    if (!item) return into
    if (item.opened === true && item.text !== undefined) into.push(item)
    var kids = item.data || []
    for (var k = 0; k < kids.length; k++) openTips(kids[k], into)
    return into
  }

  // The ink of a Text as it is drawn now, at the size it was fitted to.
  TextMetrics { id: shownInk }

  function inkOf(item) {
    shownInk.font = item.font
    shownInk.text = item.text
    return shownInk.tightBoundingRect
  }

  // The bottom of the last row the list draws: the empty list's one row, or
  // the lowest row whose top is inside the list's box. Measured from the
  // rows, not the box, so room left in the box under them, or a row the box
  // cuts, moves the footer off its gap.
  function lastRowBottom() {
    var list = body.watchlist
    var empty = find(body, "emptyList")
    if (empty.visible) return yIn(empty, empty.height)
    var end = yIn(list, list.height)
    var bottom = yIn(list, 0)
    list.displayedSymbols.forEach(function(symbol) {
      var row = list.rowItem(symbol)
      if (row && yIn(row, 0) < end) bottom = Math.max(bottom, yIn(row, row.height))
    })
    return bottom
  }

  // Every built row in its slot, none sliding or fading in.
  function rowsAtRest() {
    var list = body.watchlist
    return !list.settling && list.displayedSymbols.every(function(symbol) {
      var row = list.rowItem(symbol)
      return !row || row.resting
    })
  }

  // Where everything sits right now, in body coordinates.
  function measure() {
    var smooth = find(body, "smoothPrice")
    var block = find(body, "blockPrice")
    var change = find(body, "changeText")
    var caption = find(body, "changeCaption")
    var info = find(body, "infoBlock")
    var firstRow = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
    var footer = find(body, "footer")
    var status = find(body, "statusText")
    var today = find(body, "todayLabel")
    var priceInk = inkOf(smooth)
    return {
      listing: yIn(find(body, "listingLine"), 0),
      baseline: stub.retro ? yIn(block, block.baselineOffset) : yIn(smooth, smooth.baselineOffset),
      top: stub.retro ? yIn(block, 0) : yIn(smooth, smooth.baselineOffset + priceInk.y),
      left: stub.retro ? xIn(block, 0) : xIn(smooth, priceInk.x),
      change: yIn(change, change.baselineOffset),
      changeRight: xIn(change, change.width),
      captionRight: xIn(caption, caption.width),
      // The line under the price, by its words' baseline, shown or not.
      strip: yIn(find(body, "extendedLine").children[0], find(body, "extendedLine").children[0].baselineOffset),
      range: yIn(find(body, "rangeRow"), 0),
      info: yIn(info, 0),
      infoHeight: Math.round(info.height),
      list: yIn(body.watchlist, 0),
      // mapToItem already carries the list's scroll, so this is where the row
      // is drawn: at the list's top only when the list is at rest there.
      row: firstRow ? yIn(firstRow, 0) : -1,
      footer: yIn(footer, footer.height),
      footerGap: yIn(footer, 0) - lastRowBottom(),
      looks: xIn(find(body, "lookIcon"), 0),
      statusRight: xIn(status, status.width),
      today: xIn(today, 0),
      todayRight: xIn(today, today.width),
      rule: xIn(find(body, "breadthRule"), 0),
      listRight: xIn(find(body, "listLabel"), find(body, "listLabel").width)
    }
  }

  function describe(m) { return JSON.stringify(m) }

  // Every text drawn inside `item`, where its ink reaches in body
  // coordinates: { what, left, right, whole }, whole when it fits its box
  // on one line.
  function drawnSpans(item) {
    var out = []
    var walk = function(it) {
      if (!it.visible) return
      if (String(it).indexOf("QQuickText(") === 0 && it.text !== "") {
        var w = Math.ceil(it.implicitWidth)
        var left = xIn(it, it.horizontalAlignment === Text.AlignRight ? it.width - w : 0)
        out.push({ what: it.text, left: left, right: left + w, color: it.color,
          whole: !it.truncated && it.lineCount === 1 && it.implicitWidth <= it.width + 0.5 })
      }
      for (var i = 0; i < it.children.length; i++) walk(it.children[i])
    }
    walk(item)
    return out
  }

  // A price and a change wide enough that the room the change leaves cannot
  // hold the digits: both renderers have to shrink.
  function wideQuote(quote) {
    return Object.assign({}, quote, {
      symbol: "WIDE", name: "Wide Price Inc.", price: 9999999.99, prevClose: 12345,
      points: quote.points.map(function(point) { return { t: point.t, p: 9999999.99 } })
    })
  }

  function load() {
    var fixture = JSON.parse(watchlistFile.text())
    var names = []
    var quotes = {}
    var entries = {}
    for (var i = 0; i < fixture.quotes.length; i++) {
      var item = fixture.quotes[i]
      var parsed = item.response ? Quote.parseChart(item.response) : null
      var name = parsed ? parsed.symbol : item.symbol
      names.push(name)
      if (parsed) quotes[name] = parsed
      entries[name] = { status: item.status, receivedAt: item.status === "ok" ? fixture.now : 0 }
    }
    quotes.AAPL = Quote.parseChart(JSON.parse(aaplFile.text()))
    quotes.SPY = Quote.parseChart(JSON.parse(spyFile.text()))
    quotes["SHOP.TO"] = Quote.parseChart(JSON.parse(shopFile.text()))
    quotes["7203.T"] = Quote.parseChart(JSON.parse(tokyoFile.text()))
    quotes["SHEL.L"] = Quote.parseChart(JSON.parse(londonFile.text()))
    quotes.NEST = Quote.parseChart(JSON.parse(liveFile.text()))
    stub.nights = { NEST: Object.assign({ status: "ok" }, Overnight.parseOvernight(JSON.parse(liveNightFile.text()), ["NEST"]).NEST) }
    stub.nightCalendars = JSON.parse(calendarFile.text())
    entries["7203.T"] = entries["SHEL.L"] = { status: "ok", receivedAt: quotes.AAPL.marketTime + 120 }
    // BRK-A's real answer in place of the list's stand-in.
    quotes["SHIB-USD"] = Quote.parseChart(JSON.parse(shibFile.text()))
    quotes["BRK-A"] = Quote.parseChart(JSON.parse(berkshireFile.text()))
    names.push("SHIB-USD")
    entries["SHIB-USD"] = entries["BRK-A"] = { status: "ok", receivedAt: quotes.AAPL.marketTime + 120 }
    quotes.WIDE = wideQuote(quotes.MZ)
    stub.now = quotes.AAPL.marketTime + 120
    names.push("WIDE")
    entries.WIDE = { status: "ok", receivedAt: stub.now }
    stub.symbols = names
    stub.quotes = quotes
    stub.entries = entries
  }

  // Before the surface takes its size, so its first height already holds rows.
  Component.onCompleted: load()

  QtObject {
    id: stub
    property var symbols: []
    property var library: symbols
    property string listName: ""
    property var lists: [{ name: "", label: "All", count: symbols.length, symbols: symbols }]
    property var quotes: ({})
    property var entries: ({})
    property var calendars: null
    property string featuredSymbol: "AAPL"
    property string order: "manual"
    property bool reversed: false
    property string changeMode: "pct"
    property int now: 0
    property var owed: ({})
    property string range: "1D"
    property var historyEntry: null
    property var figures: null
    readonly property var histories: historyEntry ? ({ [featuredSymbol + "|" + range]: historyEntry }) : ({})
    readonly property var fundamentals: figures ? ({ [featuredSymbol]: { status: "ok", figures: figures } }) : ({})
    property var rates: ({})
    property var arriving: []
    property var lastRemoval: null
    property bool settingsUnreadable: false
    readonly property var view: ({ featured: featuredSymbol, range: range, list: listName, listKey: "=" + listName,
      order: order, reversed: reversed, rows: symbols, shown: Settings.sortedSymbols(symbols, quotes, order, reversed, changeMode),
      library: library, chart: Chart.viewChart(featuredSymbol, range, quotes, entries, histories, nights,
        { NEST: { status: "ok", allDay: true, at: 0 } }, featuredSymbol === "NEST" ? nightCalendars : null) })
    // NEST's prints, and the calendars its chart's day reads; only NEST has
    // them, Robinhood trading it all day, so no other symbol waits on
    // Robinhood, and the body's own calendars stay null.
    property var nights: ({})
    property var nightCalendars: null
    property bool retro: false
    property color foreground: "#cacccc"
    property color upColor: "#7aa2f7"
    property color downColor: "#a55555"
    property string fontFamily: Style.font.family
    function persist(values) {}
    function setRange(value) {}
    function screensClear() { return true }
    function surfaceShown(surface, open) {}
    function rowsSeen(surface, symbols) {}
    // A search's choice shown on the hero; this stub's hero never changes.
    readonly property var previewView: view
    readonly property var previewEntries: ({})
    property var previewSurface: null
    function preview(surface, symbol) {}
    function feature(symbol) { featuredSymbol = symbol }
    function removeSymbol(symbol) {}
    function setManualOrder(next) {}
    function addSymbol(symbol) {}
    function setOrder(value) { order = value; reversed = false }
    function reverseOrder() { reversed = !reversed }
    function switchList(name) {}
    function createList(name) { return "" }
  }

  FloatingWindow {
    id: window
    visible: true
    color: "#101315"
    implicitWidth: 760
    implicitHeight: 900

    // The surface under test: the popup's content box (Panel's
    // Style.space(480) card less its padding and border), or the window's.
    Item {
      id: surface
      property bool wide: false
      // The window's width: the body's widest, or the window's minimum.
      property int windowWidth: 720
      property int fixedHeight: 0
      // The room the popup's card gives the body, never past its cap of six
      // rows (`Panel.bodyRoom`): its rows fill it in whole rows, the rest
      // left over (`StonksBody.fittedHeight`).
      property int budget: 730
      x: 0
      y: 0
      width: wide ? windowWidth : Style.space(448)
      height: fixedHeight > 0 ? fixedHeight : body.fittedHeight(Math.min(budget, body.chromeHeight + 6 * body.rowPitch - body.rowGap))

      StonksBody {
        id: body
        anchors.fill: parent
        service: stub
        foreground: stub.foreground
        upColor: stub.upColor
        downColor: stub.downColor
        fontFamily: stub.fontFamily
        surfaceOpen: true
        margins: surface.wide ? Style.space(16) : 0
        switchesPanels: !surface.wide
        chartHeight: surface.wide ? Style.space(220) : Style.space(190)
      }
    }

    // The pill on a side bar, stacked, reading the same stand-in service;
    // out of the surface's way.
    QtObject {
      id: pillShell
      function serviceFor() { return { service: stub } }
    }
    PluginBarApi {
      id: sideBar
      pluginId: "grvc.stonks"
      moduleName: "grvc.stonks"
      shell: pillShell
      vertical: true
      foreground: Commons.Color.bar.text
      barForeground: Commons.Color.bar.text
      fontFamily: Style.font.family
      barSize: Style.bar.sizeVertical
    }
    BarWidget {
      id: sidePill
      y: 2000
      width: Style.bar.sizeVertical
      height: implicitHeight
      bar: sideBar
      settings: ({ id: "grvc.stonks", barStyleVertical: "stacked" })
    }

    Steps {
      name: "NothingJumps"
      when: window.visible

      // Each chapter starts in a fresh process with its own fixture setup.
      function test_nothing_jumps() {
        // The rows slide into their slots on the first layout.
        within(2000, root.rowsAtRest)
        var chapter = Quickshell.env("STONKS_LAYOUT_FLOW")
        console.log("LAYOUT CHAPTER " + chapter)
        if (chapter === "surfaces") surfaceLayout()
        else if (chapter === "live") liveLayout()
        else if (chapter === "sizes") textSizes()
        else throw new Error("unknown layout chapter: " + chapter)
        root.finish()
      }

      function surfaceLayout() {
        // Under the open list menu each line of a row's words shows unless
        // it starts under the menu: the symbol, with its remove button, and
        // the name, each on its own, with one list to six, in both looks.
        // Found in the 1.0.2 visual review: a row 11 px under the menu lost
        // its symbol and its name, and showed its price and chart alone.
        var coverFaults = []
        var straddled = 0
        var coverSeen = []
        ;[1, 2, 3, 4, 5, 6].forEach(function(count) {
          stub.lists = [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }].concat(
            Array.from({ length: count - 1 }, function(_, n) { return { name: "List " + (n + 1), label: "List " + (n + 1), count: 1, symbols: ["MZ"] } }))
          ;[false, true].forEach(function(retro) {
            stub.retro = retro
            wait(50)
            body.openListMenu()
            wait(100)
            var menu = find(body, "listMenu")
            var menuEnd = menu.mapToItem(body, 0, menu.height).y
            var listEnd = yIn(body.watchlist, body.watchlist.height)
            var seen = []
            // Every built row's words, as drawn.
            var contents = []
            var walk = function(it) {
              if (it.objectName === "rowContent") contents.push(it)
              else for (var c = 0; c < it.children.length; c++) walk(it.children[c])
            }
            walk(body.watchlist)
            contents.forEach(function(content) {
              if (!content.visible || yIn(content, 0) >= listEnd || yIn(content, content.height) <= yIn(body.watchlist, 0)) return
              var symbol = find(content, "rowSymbol").text
              var lines = ["rowSymbol", "rowDetail"].map(function(name) {
                var words = find(content, name)
                var top = words.mapToItem(body, 0, 0).y
                if (words.visible !== (top >= menuEnd))
                  coverFaults.push(count + " lists " + (retro ? "retro " : "smooth ") + symbol + " " + name + " at " + top
                    + (words.visible ? " shows" : " hidden") + ", the menu ends at " + menuEnd)
                seen.push(symbol + " " + name + "@" + Math.round(top) + (words.visible ? "" : " hidden"))
                return words.visible
              })
              if (!lines[0] && lines[1]) straddled++
            })
            coverSeen.push(count + (retro ? " retro" : " smooth") + ", menu ends " + Math.round(menuEnd) + ", list " + yIn(body.watchlist, 0) + "–" + listEnd
              + " of " + body.watchlist.displayedSymbols.length + ": " + seen.join(", "))
            body.closeListMenu()
            wait(50)
          })
        })
        stub.lists = Qt.binding(function() {
          return [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }]
        })
        stub.retro = false
        wait(50)
        root.check("under the open list menu a row's symbol and its name each show unless they start under it, with one list to six in both looks, a row half under it keeping its name",
          coverFaults.length === 0 && straddled > 0, coverFaults.join(" | ") + " (" + straddled + " rows kept their name alone) || " + coverSeen.join(" | "))

        var weekly = History.parseHistory(JSON.parse(aaplWeeklyFile.text()), "5Y")
        var year = History.parseHistory(JSON.parse(shopYearFile.text()), "1Y")
        var young = History.parseHistory(JSON.parse(youngFile.text()), "All")
        var month = History.parseHistory(JSON.parse(liveMonthFile.text()), "1M")
        var aapl = root.figures("aapl")
        stub.rates = { USDCAD: root.rate("USDCAD"), USDGBP: root.rate("USDGBP") }
        var cases = [
          { symbol: "AAPL", range: "1D", history: null, figures: aapl },
          { symbol: "AAPL", range: "5Y", history: weekly, figures: aapl },
          // All whose answer starts at the first trade, as most listings'
          // does: its low and high, each with its four-digit year, no SINCE.
          { symbol: "AAPL", range: "All", history: young, figures: aapl },
          { symbol: "SPY", range: "1D", history: null, figures: null },
          { symbol: "SHOP.TO", range: "1D", history: null, figures: root.figures("shop-to") },
          { symbol: "SHOP.TO", range: "1Y", history: year, figures: root.figures("shop-to") },
          { symbol: "MZ", range: "1D", history: null, figures: null },
          { symbol: "MZ", range: "5Y", history: null, figures: null },
          { symbol: "WIDE", range: "1D", history: null, figures: null },
          // The longest real key stats line: Tokyo's, with a four-digit
          // 52-week range in yen; London's names its pounds.
          { symbol: "7203.T", range: "1D", history: null, figures: root.figures("7203-t") },
          { symbol: "SHEL.L", range: "1D", history: null, figures: root.figures("shel-l") },
          { symbol: "SHIB-USD", range: "1D", history: null, figures: null },
          { symbol: "BRK-A", range: "1D", history: null, figures: null },
          // 1M with an overnight print under the price.
          { symbol: "NEST", range: "1M", history: month, figures: null, line: "OVERNIGHT" }
        ]
        // Both info lines whole: every cell of each drawn in full, none
        // overlapping the next or the rule, none past the block's edge, and
        // the two rules in one column; in either look at either width.
        var cut = []
        // The line under the price, too: whole, short of the caption, and
        // there when the case expects it.
        var whole = function(label, expected) {
          var block = find(body, "infoBlock")
          var rules = [find(body, "periodRule"), find(body, "yearRule")]
          if (!rules[0] || !rules[1]) cut.push(label + " has no rules")
          else if (rules[0].visible && rules[1].visible
            && (xIn(rules[0], 0) !== xIn(rules[1], 0) || rules[0].width !== rules[1].width))
            cut.push(label + " rules at " + xIn(rules[0], 0) + "+" + rules[0].width + " and " + xIn(rules[1], 0) + "+" + rules[1].width)
          ;["periodLine", "yearLine"].forEach(function(name, i) {
            var line = find(body, name)
            if (!line) {
              cut.push(label + " has no " + name)
              return
            }
            var spans = root.drawnSpans(line)
            if (rules[i] && rules[i].visible) spans.push({ what: "rule", left: xIn(rules[i], 0), right: xIn(rules[i], rules[i].width), whole: true })
            spans.sort(function(a, b) { return a.left - b.left })
            spans.forEach(function(s, k) {
              var next = spans[k + 1]
              if (!s.whole || (next && s.right > next.left) || s.right > xIn(block, block.width))
                cut.push(label + " " + name + " \"" + s.what + "\" " + s.left + "–" + s.right
                  + (next ? " before \"" + next.what + "\" at " + next.left : "") + " in " + xIn(block, block.width))
            })
          })
          var strip = find(body, "extendedLine")
          var caption = find(body, "changeCaption")
          if (strip.visible && root.xIn(strip, strip.width) >= root.xIn(caption, 0))
            cut.push(label + " extendedLine ends at " + root.xIn(strip, strip.width) + ", the caption starts at " + root.xIn(caption, 0))
          var shown = strip.visible ? strip.children[0].text : ""
          if (expected && shown !== expected) cut.push(label + " shows \"" + shown + "\" under the price, not " + expected)
        }
        // Each line's title: the day's 1D, weekday, or month on the day, the
        // range's name on a range, and 52W; and the lows' column one gap past
        // 52W, as wide as any of them, on every range.
        var dayTitles = ["1D"].concat(Format.WEEKDAYS.map(function(w) { return w.toUpperCase() }), Format.MONTHS)
        var mistitled = []
        var byLeft = function(a, b) { return a.left - b.left }
        var titled = function(label, range) {
          var block = find(body, "infoBlock")
          var period = root.drawnSpans(find(body, "periodLine")).sort(byLeft)
          var year = root.drawnSpans(find(body, "yearLine")).sort(byLeft)
          var gap = xIn(block, block.layout.lowX) - year[0].right
          var titleOk = range === "1D" ? dayTitles.indexOf(period[0].what) >= 0 : period[0].what === range.toUpperCase()
          if (!titleOk || year[0].what !== "52W" || gap !== block.gap)
            mistitled.push(label + " titles " + period[0].what + " and " + year[0].what + ", lows " + gap + " px past 52W")
        }
        // A price shrinks only when it cannot fit beside the change: WIDE and
        // SHIB's nine decimals in the popup, and nothing else, nowhere else.
        var hero = find(body, "hero")
        var misfits = []
        // Each case-loop check once, naming the cases it fails in.
        var caseChecks = ["the look moves nothing outside the digits",
          "both looks' digits share a top line, and their ink starts on the band's left edge",
          "the change and its caption end at the band's right edge, the rows' figures'",
          "the change sits on the price baseline",
          "the footer follows the rows at one gap",
          "the first row sits at the top of the list",
          "TODAY is after the list's name, dim, and the rule starts after it",
          "the first row, the info block, TODAY, and the line under the price stay put across symbols and ranges"]
        var caseFaults = caseChecks.map(function() { return [] })
        var caseCheck = function(index, label, ok, detail) {
          if (!ok) caseFaults[index].push(label + ": " + detail)
        }
        for (var surfaceIndex = 0; surfaceIndex < 2; surfaceIndex++) {
          surface.wide = surfaceIndex === 1
          wait(50)
          var place = surface.wide ? "window" : "popup"
          var first = null
          for (var i = 0; i < cases.length; i++) {
            var c = cases[i]
            stub.featuredSymbol = c.symbol
            stub.range = c.range
            stub.historyEntry = c.history ? { status: "ok", history: c.history, receivedAt: stub.now } : null
            stub.figures = c.figures
            stub.retro = false
            // The list from its top: a sight that shrank as the cases
            // changed the chrome kept the featured row in it, scrolled.
            body.watchlist.contentY = 0
            wait(50)
            var smooth = root.measure()
            whole(place + " smooth " + c.symbol + " " + c.range, c.line)
            titled(place + " smooth " + c.symbol + " " + c.range, stub.historyEntry ? c.range : "1D")
            stub.retro = true
            wait(50)
            var retro = root.measure()
            whole(place + " retro " + c.symbol + " " + c.range, c.line)
            titled(place + " retro " + c.symbol + " " + c.range, stub.historyEntry ? c.range : "1D")
            var label = place + " " + c.symbol + " " + c.range
            var fixed = ["listing", "baseline", "change", "changeRight", "captionRight", "strip",
              "range", "info", "infoHeight", "list", "row", "footer", "looks", "statusRight", "today", "rule"]
            var moved = fixed.filter(function(key) { return smooth[key] !== retro[key] })
            caseCheck(0, label, moved.length === 0,
              moved.join(", ") + " smooth " + root.describe(smooth) + " retro " + root.describe(retro))
            caseCheck(1, label,
              Math.abs(smooth.top - retro.top) <= 2 && Math.abs(smooth.left - Math.round(body.textLeft)) <= 1
                && retro.left === Math.round(body.textLeft),
              "smooth " + root.describe(smooth) + " retro " + root.describe(retro) + " edge " + body.textLeft)
            caseCheck(2, label,
              smooth.changeRight === smooth.captionRight
                && smooth.changeRight === Math.round(body.width - body.textRight),
              root.describe(smooth) + " body " + body.width + " right " + body.textRight)
            caseCheck(3, label,
              smooth.change === smooth.baseline && retro.change === retro.baseline,
              "smooth " + root.describe(smooth) + " retro " + root.describe(retro))
            caseCheck(4, label,
              smooth.footerGap === body.groupGap && retro.footerGap === body.groupGap,
              smooth.footerGap + " / " + retro.footerGap)
            caseCheck(5, label,
              smooth.row === smooth.list && retro.row === retro.list,
              "smooth " + root.describe(smooth) + " retro " + root.describe(retro))
            caseCheck(6, label,
              find(body, "todayLabel").visible && find(body, "todayLabel").text === "TODAY"
                && String(find(body, "todayLabel").color) === String(body.dim)
                && smooth.today > smooth.listRight && retro.today > retro.listRight
                && smooth.rule > smooth.todayRight && retro.rule > retro.todayRight,
              find(body, "todayLabel").color + " vs " + body.dim + " " + root.describe(smooth))
            if (!first) first = smooth
            caseCheck(7, label,
              smooth.row === first.row && smooth.info === first.info && smooth.infoHeight === first.infoHeight
                && smooth.today === first.today && smooth.rule === first.rule && smooth.strip === first.strip,
              "first " + root.describe(first) + " now " + root.describe(smooth))
            if ((hero.fittedCell < hero.naturalCell) !== ((c.symbol === "WIDE" || c.symbol === "SHIB-USD") && !surface.wide))
              misfits.push(label + " " + hero.fittedCell + " of " + hero.naturalCell)
          }
        }
        caseChecks.forEach(function(label, index) {
          root.check(label, caseFaults[index].length === 0, caseFaults[index].join(" | "))
        })
        root.check("a price too wide for the popup (WIDE, SHIB-USD) shrinks there and not in the window, and no other price shrinks",
          misfits.length === 0, misfits.join(", "))
        root.check("both info lines are whole for every symbol, cell by cell, their rules in one column, and the line under the price is whole where it shows",
          cut.length === 0, cut.join(" | "))
        root.check("each info line's title is the day's or the range's, and 52W, and the lows one gap past 52W on every range",
          mistitled.length === 0, mistitled.join(" | "))
        // The 52-week line says the same words in the same places on every
        // range, and nothing moves: the columns, both rules, and every fact's
        // place stay as on the day. Both lines reach the band's right edge:
        // every column shows, the last one's slot ends at the edge, and the
        // rule leaves the facts only their gap, short of a cell of its grain.
        var infoSaid = function() {
          var at = find(body, "infoBlock").layout
          var year = root.drawnSpans(find(body, "yearLine")).sort(byLeft).map(function(s) { return s.what + "@" + s.left }).join(" ")
          var rules = ["periodRule", "yearRule"].map(function(name) {
            var rule = find(body, name)
            return xIn(rule, 0) + "+" + rule.width
          })
          return ["columns " + [at.lowX, at.ruleX, at.highX, at.rule].concat(at.factXs).join(","), year].concat(rules).join(" | ")
        }
        var shortOfEdge = function() {
          var block = find(body, "infoBlock")
          var at = block.layout
          var lists = [body.periodLine.facts, body.yearLine.facts].concat(block.factLists)
          var columns = Math.max.apply(null, lists.map(function(facts) { return facts.length }))
          var last = at.factXs.length - 1
          var slot = 0
          lists.forEach(function(facts) {
            if (facts[last]) slot = Math.max(slot, block.factWidth(facts[last]))
          })
          var end = last < 0 ? -1 : xIn(block, at.factXs[last] + slot)
          var edge = Math.round(body.width - body.textRight)
          var slack = last < 0 ? -1 : at.factXs[0] - block.gap - (at.highX + at.price)
          return at.factXs.length === columns && end === edge && slack >= 0 && slack < Cells.RULE_PITCH ? ""
            : at.factXs.length + " of " + columns + " columns, the last ending at " + end + " of " + edge + ", "
              + slack + " px spare before the facts"
        }
        // Under the change, a range's name, or SINCE the young listing's
        // first day, short of the line under the price. On a range, its high
        // and low marked whole on the chart, the high on its top edge and the
        // low on its bottom, each starting with its price and reaching over
        // where the chart draws the bar that made it, from the side away
        // from the chart's middle; none on the day.
        var chartLook = function() {
          var kids = body.chartItem.children
          for (var k = 0; k < kids.length; k++) if (kids[k].visible && typeof kids[k].xAt === "function") return kids[k]
          return null
        }
        var marksFault = function(h) {
          var marks = [find(body, "highMark"), find(body, "lowMark")]
          if (!h) return marks.some(function(m) { return m && m.visible }) ? "marks on the day" : ""
          var chart = body.chartItem
          var look = chartLook()
          var faults = []
          ;[["h", function(a, b) { return a > b }], ["l", function(a, b) { return a < b }]].forEach(function(k, i) {
            var mark = marks[i]
            var at = -1
            for (var j = 0; j < h.bars.length; j++) {
              var v = h.bars[j][k[0]]
              if (isFinite(v) && v !== null && (at < 0 || k[1](v, h.bars[at][k[0]]))) at = j
            }
            var name = i === 0 ? "high" : "low"
            if (!mark || !mark.visible) {
              faults.push("no " + name + " mark")
              return
            }
            var spans = root.drawnSpans(mark).sort(byLeft)
            var left = xIn(mark, 0)
            var right = xIn(mark, mark.width)
            var barX = xIn(chart, look.xAt(at / Math.max(1, h.bars.length - 1)))
            var reach = Style.space(4)
            // On its edge, or off it by no more than a mark lifts to clear the ink.
            var off = i === 0 ? yIn(chart, 0) - yIn(mark, 0) : yIn(mark, mark.height) - yIn(chart, chart.height)
            var onEdge = off >= 0 && off <= Style.space(4)
            var bySide = at / Math.max(1, h.bars.length - 1) < 0.5 ? Math.abs(left - barX) <= reach : Math.abs(right - barX) <= reach
            var price = Format.money(h.bars[at][k[0]], body.featuredQuote.priceDigits)
            if (spans.length !== 2 || spans[0].what !== price || !spans.every(function(s) { return s.whole }) || !onEdge || !bySide
                || left < xIn(chart, 0) || right > xIn(chart, chart.width))
              faults.push(name + " \"" + spans.map(function(s) { return s.what }).join(" ") + "\" at " + left + "–" + right + ", "
                + yIn(mark, 0) + "–" + yIn(mark, mark.height) + " on a chart at " + xIn(chart, 0) + "–" + xIn(chart, chart.width) + ", "
                + yIn(chart, 0) + "–" + yIn(chart, chart.height) + ", its bar at " + barX + ", want " + price)
          })
          return faults.join(", ")
        }
        var aaplYear = History.parseHistory(JSON.parse(aaplYearFile.text()), "1Y")
        var youngMonth = Object.assign({}, month, { firstTradeDate: month.bars[0].t, bars: month.bars.slice(0, 7) })
        var shifted = []
        var unreached = []
        var unmarked = []
        var captions = []
        var places = [["popup", false, 0], ["narrowest window", true, Style.space(560)], ["widest window", true, 1416]]
        // Each range is set once and drawn in once; the look and the surface
        // change under it, which draws nothing in again. Bitcoin, with no cap
        // to widen the first column, holds START's room: its 1Y started at
        // 108,186, a digit wider than its day.
        var quotesBeforeRanges = stub.quotes
        stub.quotes = Object.assign({}, quotesBeforeRanges, { "BTC-USD": Quote.parseChart(JSON.parse(btcFile.text())) })
        ;[{ symbol: "AAPL", figures: aapl, ranges: [["1D", null], ["1M", month], ["1Y", aaplYear], ["5Y", weekly], ["All", young]] },
          { symbol: "NEST", figures: null, ranges: [["1D", null], ["1M", youngMonth]] },
          { symbol: "BTC-USD", figures: null, ranges: [["1D", null], ["1Y", History.parseHistory(JSON.parse(btcYearFile.text()), "1Y")]] }].forEach(function(listing) {
          stub.featuredSymbol = listing.symbol
          stub.figures = listing.figures
          var onDay = {}
          // On 1Y the 52-week line is the chart's own low and high
          // (`Fundamentals.yearLine`): its words may differ from 1D's there,
          // never its places.
          var dayYear = {}
          var yearAs = function(said, where) {
            var was = dayYear[where], now = body.yearLine ? body.yearLine.range : null
            if (!was || !now) return said
            return said.replace(" " + now.lowText + "@", " " + was.lowText + "@").replace(" " + now.highText + "@", " " + was.highText + "@")
          }
          listing.ranges.forEach(function(r) {
            stub.range = r[0]
            stub.historyEntry = r[1] ? { status: "ok", history: r[1], receivedAt: stub.now } : null
            wait(50)
            // The marks draw in with the line: read them once it has.
            if (r[1]) tryVerify(function() { return body.motion.drawn === 1 }, 2000)
            places.forEach(function(place) {
              surface.wide = place[1]
              if (place[1]) surface.windowWidth = place[2]
              ;[false, true].forEach(function(retro) {
                stub.retro = retro
                wait(50)
                var where = place[0] + (retro ? " retro " : " smooth ") + listing.symbol
                var said = infoSaid()
                if (!!r[1] !== body.historyShown) shifted.push(where + " " + r[0] + " shows " + (body.historyShown ? "a range" : "the day"))
                else if (onDay[where] === undefined) {
                  onDay[where] = said
                  if (body.yearLine) dayYear[where] = { lowText: body.yearLine.range.lowText, highText: body.yearLine.range.highText }
                } else if ((r[0] === "1Y" ? yearAs(said, where) : said) !== onDay[where]) shifted.push(where + " " + r[0] + ": " + said + ", on 1D " + onDay[where])
                var short = shortOfEdge()
                if (short) unreached.push(where + " " + r[0] + ": " + short)
                var marked = marksFault(r[1])
                if (marked) unmarked.push(where + " " + r[0] + ": " + marked)
                if (r[1]) {
                  var caption = find(body, "changeCaption")
                  var strip = find(body, "extendedLine")
                  var want = r[1] === youngMonth ? /^SINCE \d{1,2} [A-Z]{3} \d{4}$/ : new RegExp("^" + r[0].toUpperCase() + "$")
                  if (!want.test(caption.text) || (strip.visible && xIn(strip, strip.width) >= xIn(caption, 0)))
                    captions.push(where + " " + r[0] + " says \"" + caption.text + "\" from " + xIn(caption, 0)
                      + (strip.visible ? ", the line under the price ending at " + xIn(strip, strip.width) : ""))
                }
              })
            })
          })
        })
        stub.quotes = quotesBeforeRanges
        surface.windowWidth = 720
        stub.featuredSymbol = "AAPL"
        stub.figures = aapl
        stub.retro = false
        stub.range = "1D"
        stub.historyEntry = null
        wait(50)
        root.check("nothing on the info lines moves from 1D to 1M, 1Y, 5Y, and All, and the 52-week line says the same, on 1Y the chart's own low and high, a young listing's too, in both looks, in the popup and the window at its narrowest and widest",
          shifted.length === 0, shifted.join(" | "))
        root.check("both info lines reach the band's right edge on every range, in both looks, in the popup and the window at its narrowest and widest",
          unreached.length === 0, unreached.join(" | "))
        root.check("a range marks its high and low whole on the chart's top and bottom edges, by the bars that made them, and the day marks none",
          unmarked.length === 0, unmarked.join(" | "))
        root.check("under the change a range says its name, and a listing younger than it SINCE its first day, clear of the line under the price",
          captions.length === 0, captions.join(" | "))
        // AAPL's figures are Tuesday 1 September's: the day line is 1D that
        // Tuesday, TUE from Wednesday's first second, and SEP a week on (the
        // titles at every moment are saved.test.js's). Only the title
        // changes: every other cell of both lines, and both rules, stay where
        // they were at the Tuesday's close. Both looks, both surfaces.
        var tuesday = stub.now
        stub.featuredSymbol = "AAPL"
        stub.range = "1D"
        stub.historyEntry = null
        stub.figures = aapl
        var moments = [["Tuesday", tuesday, "1D"], ["Wednesday 00:00", Date.UTC(2026, 8, 2, 4) / 1000, "TUE"],
          ["a week on", Date.UTC(2026, 8, 8, 16) / 1000, "SEP"]]
        // Every cell of both lines but the day's title, and both rules.
        var rest = function() {
          var cells = root.drawnSpans(find(body, "periodLine")).sort(byLeft).slice(1)
            .concat(root.drawnSpans(find(body, "yearLine")).sort(byLeft))
          return cells.map(function(s) { return s.what + "@" + s.left }).concat(["periodRule", "yearRule"].map(function(name) {
            var rule = find(body, name)
            return xIn(rule, 0) + "+" + rule.width
          })).join(" ")
        }
        var dated = []
        for (var momentSurface = 0; momentSurface < 2; momentSurface++) {
          surface.wide = momentSurface === 1
          ;[false, true].forEach(function(retro) {
            stub.retro = retro
            var where = (surface.wide ? "window " : "popup ") + (retro ? "retro" : "smooth")
            var still = null
            moments.forEach(function(moment) {
              stub.now = moment[1]
              wait(50)
              var title = root.drawnSpans(find(body, "periodLine")).sort(byLeft)[0].what
              if (title !== moment[2]) dated.push(where + " " + moment[0] + " titled " + title + ", not " + moment[2])
              if (still === null) still = rest()
              else if (rest() !== still) dated.push(where + " " + moment[0] + " moved: " + still + " became " + rest())
            })
          })
        }
        stub.now = tuesday
        wait(50)
        root.check("the day line is 1D on its figures' own day, their weekday from the next midnight, their month a week on, and nothing else moves",
          dated.length === 0, dated.join(" | "))

        // A refresh moves the tick and nothing else: AAPL's volume from
        // 52.4M to 999.9M, across its rounding into 1.0B, and to 7, with its
        // price a dollar up, leaves both rules' ends where they were; the
        // tick follows the price. At a 52-week high, with Yahoo's 52-week
        // high a dollar behind the day's, both lines' highs read the day's
        // high in the up colour, and both ticks sit at their rule's right
        // end. Both looks, both surfaces.
        var aaplQuote = stub.quotes.AAPL
        var restless = []
        var peaks = []
        var ends = function() {
          return ["periodRule", "yearRule"].map(function(name) {
            var rule = find(body, name)
            return rule ? xIn(rule, 0) + "+" + rule.width : "none"
          }).join(" ")
        }
        // The tick's right edge in its rule, -1 without one.
        var tickEnd = function(name) {
          var rule = find(body, name)
          var tick = rule ? find(rule, stub.retro ? "infoTickCells" : "infoTick") : null
          return tick && tick.visible ? tick.x + tick.width : -1
        }
        var withQuote = function(changes) {
          var next = Object.assign({}, stub.quotes)
          next.AAPL = Object.assign({}, aaplQuote, changes)
          stub.quotes = next
          wait(50)
        }
        for (var refreshSurface = 0; refreshSurface < 2; refreshSurface++) {
          surface.wide = refreshSurface === 1
          ;[false, true].forEach(function(retro) {
            stub.retro = retro
            stub.featuredSymbol = "AAPL"
            stub.range = "1D"
            stub.historyEntry = null
            stub.figures = aapl
            withQuote({})
            var where = (surface.wide ? "window " : "popup ") + (retro ? "retro" : "smooth")
            var before = ends()
            var tickBefore = tickEnd("periodRule")
            ;[999.9e6, 999.96e6, 1e9, 7].forEach(function(volume) {
              withQuote({ volume: volume, price: aaplQuote.price + 1 })
              if (ends() !== before) restless.push(where + " at VOL " + volume + ": " + before + " became " + ends())
            })
            if (tickEnd("periodRule") === tickBefore) restless.push(where + ": the tick stayed at " + tickBefore + " as the price rose")
            stub.featuredSymbol = "AAPL"
            stub.range = "1D"
            stub.historyEntry = null
            stub.figures = aapl
            withQuote({ price: aaplQuote.dayHigh, fiftyTwoWeekHigh: aaplQuote.dayHigh - 1 })
            var rules = [find(body, "periodRule"), find(body, "yearRule")]
            var highs = [body.periodLine, body.yearLine].map(function(line) { return line ? line.range.highText : "" })
            var drawn = ["periodLine", "yearLine"].map(function(name) {
              return find(body, name) ? root.drawnSpans(find(body, name)).filter(function(s) { return s.what === highs[0] }) : []
            })
            var toned = drawn.every(function(spans) { return spans.length === 1 && Qt.colorEqual(spans[0].color, stub.upColor) })
            if (!rules[0] || !rules[1] || tickEnd("periodRule") !== rules[0].width || tickEnd("yearRule") !== rules[1].width
                || highs[0] !== highs[1] || !toned)
              peaks.push(where + ": highs " + highs.join(" / ") + (toned ? "" : " not both in the up colour") + ", ticks end at "
                + tickEnd("periodRule") + " / " + tickEnd("yearRule") + " of " + (rules[0] ? rules[0].width : "-") + " / " + (rules[1] ? rules[1].width : "-"))
          })
        }
        withQuote({})
        root.check("a refresh moves neither end of either rule as VOL crosses its units; the tick follows the price",
          restless.length === 0, restless.join(" | "))
        root.check("at a 52-week high both highs read the day's high in the up colour, both ticks at the rule's right end",
          peaks.length === 0, peaks.join(" | "))

        // On 1Y the 52-week line takes in the range's own low and high, as the
        // first line and the chart's marks say them; on 1D it says Yahoo's.
        // SHOP.TO with Yahoo's 52-week marks a dollar inside its 1Y range.
        var yearStats = History.periodStats(year)
        var shopQuote = stub.quotes["SHOP.TO"]
        var narrowed = Object.assign({}, stub.quotes)
        narrowed["SHOP.TO"] = Object.assign({}, shopQuote,
          { fiftyTwoWeekLow: yearStats.low.p + 1, fiftyTwoWeekHigh: yearStats.high.p - 1 })
        stub.quotes = narrowed
        stub.featuredSymbol = "SHOP.TO"
        stub.figures = root.figures("shop-to")
        var yearSaid = function() {
          return root.drawnSpans(find(body, "yearLine")).sort(byLeft).map(function(s) { return s.what + "@" + s.left }).join(" ")
        }
        var marksSaid = function() {
          return [find(body, "lowMark"), find(body, "highMark")].map(function(mark) {
            return mark && mark.visible ? root.drawnSpans(mark).sort(byLeft)[0].what : "none"
          }).join("–")
        }
        stub.retro = false
        stub.range = "1D"
        stub.historyEntry = null
        wait(50)
        var onDay = yearSaid()
        stub.range = "1Y"
        stub.historyEntry = { status: "ok", history: year, receivedAt: stub.now }
        wait(50)
        tryVerify(function() { return body.motion.drawn === 1 }, 2000)
        var onYear = yearSaid()
        var marked = marksSaid()
        var periodRange = body.periodLine ? body.periodLine.range.lowText + "–" + body.periodLine.range.highText : "none"
        stub.range = "1D"
        stub.historyEntry = null
        stub.quotes = Object.assign({}, narrowed, { "SHOP.TO": shopQuote })
        wait(50)
        var wantMarks = Format.money(yearStats.low.p, shopQuote.priceDigits) + "–" + Format.money(yearStats.high.p, shopQuote.priceDigits)
        var wantYear = Format.money(yearStats.low.p + 1, shopQuote.priceDigits) + " " + Format.money(yearStats.high.p - 1, shopQuote.priceDigits)
        var yahoos = onDay.replace(/@\d+/g, "").indexOf(wantYear) >= 0
        var widened = onYear.replace(/@\d+/g, "").indexOf(wantMarks.replace("–", " ")) >= 0
        root.check("where Yahoo's 52 weeks leave out the 1Y range's ends, the 52-week line on 1Y says the range's, as the first line and the chart's marks do, and Yahoo's on 1D",
          widened && yahoos && marked === wantMarks && periodRange === wantMarks,
          "1Y: " + onYear + " / 1D: " + onDay + " / marks " + marked + ", first line " + periodRange + ", want " + wantMarks + " and Yahoo's " + wantYear)

        // Pence say PENCE, so a price in pence never reads as pounds beside a
        // cap in GBP. A long name is the header's title, cut there short of
        // the speaker.
        var shelQuote = stub.quotes["SHEL.L"]
        var longNamed = Object.assign({}, stub.quotes)
        longNamed["SHEL.L"] = Object.assign({}, shelQuote,
          { name: "Shell plc, with a name long enough to fill the header's whole line in the popup, and in the window at its widest too" })
        stub.quotes = longNamed
        stub.featuredSymbol = "SHEL.L"
        stub.figures = null
        var wantMeta = shelQuote.exchange + " · PENCE"
        var metaLost = []
        var wideWas = surface.wide
        ;[false, true].forEach(function(wide) {
          surface.wide = wide
          ;[false, true].forEach(function(retro) {
            stub.retro = retro
            wait(50)
            var meta = find(body, "listingMeta")
            var right = meta ? meta.x + meta.implicitWidth : 0
            var title = find(body, "headerTitle")
            var speaker = find(body, "soundIcon")
            var titleRight = xIn(title, title.width)
            if (!meta || !meta.visible || meta.text !== wantMeta || right > meta.parent.width + 0.5
              || !title.truncated || titleRight > xIn(speaker, 0))
              metaLost.push((wide ? "window " : "popup ") + (retro ? "retro " : "smooth ") + JSON.stringify(title.text.slice(0, 12)) + " ends at "
                + Math.ceil(titleRight) + ", the speaker at " + Math.floor(xIn(speaker, 0)) + " | " + JSON.stringify(meta ? meta.text : null)
                + (meta ? ", ends at " + Math.ceil(right) + " of " + meta.parent.width : ""))
          })
        })
        surface.wide = wideWas
        stub.retro = false
        stub.quotes = Object.assign({}, longNamed, { "SHEL.L": shelQuote })
        root.check("a long name is cut in the header short of the speaker; the hero's line keeps its exchange and currency whole, in the popup and the window, both looks",
          metaLost.length === 0, metaLost.join(" | "))

        // A coin under a cent to four significant digits, a six-figure price
        // to none.
        var decimals = []
        ;[["SHIB-USD", /^0\.00000\d{4}$/], ["BRK-A", /^7\d\d,\d{3}$/]].forEach(function(want) {
          stub.featuredSymbol = want[0]
          stub.range = "1D"
          stub.historyEntry = null
          stub.figures = null
          stub.retro = false
          wait(50)
          // Its row in sight: a row out of sight keeps the quote it last showed.
          var row = body.watchlist.rowItem(want[0])
          if (row) body.watchlist.contentY = Math.max(0, Math.min(row.y, body.watchlist.contentHeight - body.watchlist.height))
          var shown = { hero: find(body, "smoothPrice").text, row: row && row.view ? row.view.priceText : "" }
          body.watchlist.contentY = 0
          stub.retro = true
          wait(50)
          shown.retro = find(body, "blockPrice").text
          stub.retro = false
          var day = body.featuredDay.points
          body.motion.scrubT = day[Math.floor(day.length / 2)].t
          wait(50)
          shown.scrub = find(body, "smoothPrice").text
          body.motion.scrubT = 0
          wait(50)
          for (var where in shown) if (!want[1].test(shown[where])) decimals.push(want[0] + " " + JSON.stringify(shown))
        })
        root.check("a coin under a cent and a six-figure price each show their own decimals in the hero, both looks, the row, and a scrub",
          decimals.length === 0, decimals.join(" | "))

        // The header's words keep room for its longest real states, each
        // whole or in a shorter form that keeps its time and date, never cut,
        // and say every closure in calendars.json, as Market names it, for a
        // reader whose clock differs from the exchange's (its zone named): in
        // full wherever that fits, its letters closed up where only that
        // fits, and otherwise without the holiday's name, as a weekend's is
        // worded, then with when it opens alone. A form shows only where the
        // one before fits neither spaced nor closed up. In the popup and the
        // window at its widest and its minimum width (App.qml), beside the
        // speaker, the camera, the look icon, and the help mark, at every
        // text size Omarchy offers (9 to 20), and in the popup with the
        // shell's spacing kept at size 12's as the text grows (`[spacing]
        // scale-with-font = false`). Smooth alone: retro changes only the
        // corner radius and the look toggle's words here (HeaderStatus.qml).
        // At the everyday size 12 the popup names Constitution Memorial Day
        // in full (the owner's).
        var header = find(body, "statusText").parent
        var calendars = JSON.parse(calendarFile.text())
        var states = [["After hours · closed at 16:00 EDT", "Closed at 16:00 EDT"], ["Pre-market · opens in 3h 11m", "Opens in 3h 11m"],
          ["Overnight · opens Mon 09:30 EST", "Opens Mon 09:30 EST"], ["Weekend · opens Mon 09:30 EST", "Opens Mon 09:30 EST"],
          ["Closed · opens Thu 09:00 JST", "Opens Thu 09:00 JST"], ["Power hour · closes in 40m", "Closes in 40m"],
          ["Opening bell · closes in 6h 20m", "Closes in 6h 20m"],
          ["Lunch break · reopens 12:30 JST · in 59m", "Lunch break · reopens 12:30 JST", "Reopens 12:30 JST"],
          ["At 16:30 BST · Closing bell", "At 16:30 BST"], ["At 02:25 EDT · Overnight", "At 02:25 EDT"],
          ["WEEK OF 28 SEP 2026 · 712,345.00", "WEEK OF 28 SEP 2026"], ["21 SEP 10:00 AEST · 712,345.00", "21 SEP 10:00 AEST"],
          ["Can't get prices · Stonks keeps trying", "Can't get prices"],
          Figures.hostPause("none", 72, 0).forms, Figures.hostPause("refused", 30 * 60, 0).forms,
          ["No usable answer for SHIB-USD", "No usable answer"], ["Refreshing"], ["Loading SHIB-USD YTD"]]
        var closures = 0
        var unnamed = []
        for (var calId in calendars.calendars) {
          var cal = calendars.calendars[calId]
          var listing = stub.quotes[["AAPL", "SHOP.TO", "7203.T", "SHEL.L"].filter(function(s) {
            return Market.calendarFor(calendars, stub.quotes[s]) === cal
          })[0]]
          for (var day in cal.closures) {
            var noon = Market.epochAt(cal, day, "12:00")
            // Past the calendar's last day the header says the schedule is
            // unavailable, with no time to name a zone for.
            var next = Market.nextOpen(cal, noon)
            var zone = next ? Market.zoneName(cal, Market.localDate(next.t, cal).offset) : ""
            var forms = Market.statusForms(listing, noon, 0, calendars).map(function(form) {
              return zone !== "" && form.slice(-zone.length) !== zone ? form + " " + zone : form
            })
            var notice = forms[0].slice(forms[0].indexOf(" · "))
            if (forms[0].indexOf(cal.closures[day].split(" ")[0] + " ") !== 0 || forms[0].indexOf(" · ") < 0
              || JSON.stringify(forms.slice(1)) !== JSON.stringify(["Closed" + notice, notice.charAt(3).toUpperCase() + notice.slice(4)]))
              unnamed.push(calId + " " + day + " " + forms.join(" / "))
            states.push(forms)
            closures++
          }
        }
        var roomless = []
        var shortened = {}
        // The sweep changes the text size, the spacing, and the surface, and
        // with them the list's scroll, which keeps its cursor in sight; it
        // puts each back when it ends, however it ends, and waits for the
        // layout to come back as it was, so no later check depends on where
        // this one runs.
        var settled = function() {
          return JSON.stringify([surface.width, surface.height, body.chromeHeight, body.chartItem.height, header.height,
            body.watchlist.height, body.watchlist.contentY, body.watchlist.cursorRow, find(body, "footer").y, body.retro])
        }
        var before = { size: Style.fontBaseSize, wide: surface.wide, windowWidth: surface.windowWidth, retro: stub.retro,
          contentY: body.watchlist.contentY, cursor: body.watchlist.cursorSymbol, listName: stub.listName, layout: settled() }
        // On the same sweep, the footer's add on a named list, beside an
        // undo and once it goes: where the add doesn't fit beside it, it
        // says less, and never cuts the list's name.
        var named = "+  Add a symbol to My Watchlist"
        var addWords = find(body, "footerText")
        var addCut = []
        var addShort = []
        stub.lists = stub.lists.concat([{ name: "My Watchlist", label: "My Watchlist", count: stub.symbols.length, symbols: stub.symbols }])
        stub.listName = "My Watchlist"
        try {
          for (var hsize = 9; hsize <= 20; hsize++) {
            Style.fontBaseSize = hsize
            // The popup with its spacing kept, then the popup and the
            // window's two widths as the spacing grows with the text.
            for (var hw = -1; hw < 3; hw++) {
              Style.spacingScaleWithFont = hw >= 0
              surface.wide = hw > 0
              surface.windowWidth = hw === 1 ? Style.space(560) : 720
              stub.retro = false
              wait(20)
              var where = "size " + hsize + " " + (surface.wide ? "window " + surface.width + " " : "popup " + (hw < 0 ? "spacing kept " : ""))
              for (var s = 0; s < states.length; s++) {
                header.statusForms = states[s]
                wait(1)
                var words = find(body, "statusText")
                var shown = states[s].map(function(form) { return form.toUpperCase() }).indexOf(words.text)
                var fitted = header.measured.slice(0, Math.max(0, shown)).filter(function(form) { return form.tight <= header.wordsRoom })
                if (shown < 0 || words.truncated || words.implicitWidth > words.width)
                  roomless.push(where + words.text + " (" + Math.ceil(words.implicitWidth) + " px in " + words.width + ")")
                else if (fitted.length > 0)
                  roomless.push(where + "said in less though \"" + fitted[0].words + "\" fits closed up")
                else if (shown > 0 && hsize === 12 && !surface.wide && states[s][0].indexOf("Constitution Memorial Day ·") === 0)
                  roomless.push(where + "short at the everyday size: " + states[s][0])
                if (shown > 0) shortened[where.trim()] = (shortened[where.trim()] || 0) + 1
              }
              body.undoOffered = { symbol: "SHOP.TO" }
              wait(1)
              var beside = addWords.text + (addWords.truncated ? " (cut)" : "")
              body.undoOffered = null
              wait(1)
              var alone = addWords.text + (addWords.truncated ? " (cut)" : "")
              if (alone !== named || (beside !== named && beside !== "+  Add a symbol"))
                addCut.push(where + beside + " / " + alone)
              if (beside !== named) addShort.push(where.trim())
            }
          }
        } finally {
          header.statusForms = Qt.binding(function() { return body.headerForms })
          Style.spacingScaleWithFont = true
          stub.listName = before.listName
          stub.lists = Qt.binding(function() {
            return [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }]
          })
          Style.fontBaseSize = before.size
          surface.wide = before.wide
          surface.windowWidth = before.windowWidth
          stub.retro = before.retro
          wait(50)
          body.watchlist.takeOver()
          body.watchlist.cursorSymbol = before.cursor
          body.watchlist.contentY = before.contentY
          within(3000, function() { return settled() === before.layout })
        }
        console.log("said in less: " + Object.keys(shortened).map(function(k) { return k + " " + shortened[k] }).join(", "))
        root.check("the header's longest real states read whole or in a shorter form that keeps their time, never cut, and every closure in calendars.json is said in full where it fits, else without its holiday's name, else with when it opens alone, a zone named, in the popup and the window at its widest and narrowest, at every text size from 9 to 20, and in the popup with its spacing kept",
          closures > 50 && unnamed.length === 0 && roomless.length === 0,
          closures + " closures | " + unnamed.join(" | ") + " | " + roomless.slice(0, 12).join(" | ") + (roomless.length > 12 ? " | … " + roomless.length : ""))
        console.log("the add said less beside the undo: " + addShort.join(", "))
        root.check("on a named list the footer's add reads whole, or beside an undo it has no room beside \"+ Add a symbol\", never cut, and whole again once the undo goes, in the popup and the window at its widest and narrowest, at every text size from 9 to 20, and in the popup with its spacing kept",
          addCut.length === 0, addCut.slice(0, 12).join(" | "))

        // In a window of ordinary height, 720 × 520, the key sheet shows its
        // credit whole without a scroll, the version included: nothing says
        // the sheet scrolls. A pin of the owner's: more keys fail it.
        var sheet = find(body, "helpSheet")
        var sheetBefore = { wide: surface.wide, windowWidth: surface.windowWidth, fixedHeight: surface.fixedHeight }
        surface.wide = true
        surface.windowWidth = 720
        surface.fixedHeight = 520
        sheet.version = "1.1.0"
        body.showingHelp = true
        wait(50)
        var credits = []
        var gather = function(node) {
          if (!node || node.visible === false) return
          if (node.objectName === "helpCredit") credits.push(node)
          for (var c = 0; c < node.children.length; c++) gather(node.children[c])
        }
        gather(sheet)
        var creditEnd = credits.length === 1 ? yIn(credits[0], credits[0].height) - yIn(sheet, 0) : -1
        var creditSaid = credits.length === 1 ? credits[0].text.replace(/\n/g, " / ") : credits.length + " credits"
        var sheetHeight = sheet.height
        var creditWhole = credits.length === 1 && !credits[0].truncated && creditEnd > 0 && creditEnd <= sheetHeight && sheet.contentY === 0
        body.showingHelp = false
        sheet.version = Qt.binding(function() { return body.updates && body.updates.runningVersion || "" })
        surface.wide = sheetBefore.wide
        surface.windowWidth = sheetBefore.windowWidth
        surface.fixedHeight = sheetBefore.fixedHeight
        wait(50)
        root.check("in a 720 × 520 window the key sheet shows its credit whole without a scroll",
          creditWhole, creditSaid + " ends at " + creditEnd + " of the sheet's " + sheetHeight)

        // After the text size changes while Stonks runs (`omarchy display
        // text size 16`), every key and gesture on the key sheet still fits
        // its column.
        var keySizeBefore = Style.fontBaseSize
        body.showingHelp = true
        wait(50)
        Style.fontBaseSize = 16
        wait(50)
        var keysOver = []
        var gatherKeys = function(node) {
          if (!node || node.visible === false) return
          if ((node.objectName === "helpKey" || node.objectName === "helpGesture") && Math.ceil(node.implicitWidth) > node.width)
            keysOver.push(node.text + " " + Math.ceil(node.implicitWidth) + " px in " + node.width)
          for (var c = 0; c < node.children.length; c++) gatherKeys(node.children[c])
        }
        gatherKeys(sheet)
        Style.fontBaseSize = keySizeBefore
        body.showingHelp = false
        wait(50)
        root.check("after the text size changes, every key and gesture on the key sheet fits its column",
          keysOver.length === 0, keysOver.join(", "))

        // The band lines up with the rows and keeps one rhythm: the range
        // row, the info lines, and the list's header start at the rows' text
        // and end at their figures, the info lines' last column included;
        // the range row, the info lines, and the header stand a band's gap
        // apart, and the header a group's gap over its rows. The header ends
        // in the rows' unit, which ends there in every unit, and stepping it
        // moves neither the sign, the order word, nor the rule.
        var headerFaults = []
        for (var hw = 0; hw < 2; hw++) {
          surface.wide = hw === 1
          for (var hl = 0; hl < 2; hl++) {
            stub.retro = hl === 1
            wait(50)
            var row0 = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
            var textLeft = xIn(row0, 0) + row0.gap
            var textRight = xIn(row0, row0.width) - row0.gap
            var nameText = find(body, "listLabel")
            var orderWord = find(body, "orderLabel")
            var unitSign = find(body, "unitSign")
            var rule = find(body, "breadthRule")
            var headerLine = nameText.parent
            var rangeRow = find(body, "rangeRow")
            var infoLines = find(body, "infoBlock")
            // The info lines' last column, as wide as the widest slot either
            // line puts there.
            var lastFact = infoLines.layout.factXs.length - 1
            var lastSlot = 0
            ;[body.periodLine, body.yearLine].map(function(line) { return line ? line.facts : [] }).concat(infoLines.factLists).forEach(function(facts) {
              if (facts[lastFact]) lastSlot = Math.max(lastSlot, infoLines.factWidth(facts[lastFact]))
            })
            var units = ["pct", "abs", "open"].map(function(mode) {
              stub.changeMode = mode
              wait(20)
              return [xIn(unitSign, 0), xIn(unitSign, unitSign.width) - textRight, xIn(orderWord, orderWord.width), xIn(rule, rule.width)].join(",")
            })
            stub.changeMode = "pct"
            var placed = {
              name: xIn(nameText, 0) - textLeft,
              unit: units,
              range: [xIn(rangeRow, 0) - textLeft, xIn(rangeRow, rangeRow.width) - textRight],
              info: [xIn(infoLines, 0) - textLeft, lastFact < 0 ? "none" : xIn(infoLines, infoLines.layout.factXs[lastFact] + lastSlot) - textRight],
              rangeToInfo: yIn(infoLines, 0) - yIn(rangeRow, rangeRow.height),
              infoToHeader: yIn(headerLine, 0) - yIn(infoLines, infoLines.height),
              headerToRows: yIn(body.watchlist, 0) - yIn(headerLine, headerLine.height)
            }
            if (placed.name !== 0 || units[0].split(",")[1] !== "0" || units[1] !== units[0] || units[2] !== units[0]
                || placed.range.join() !== "0,0" || placed.info.join() !== "0,0"
                || placed.rangeToInfo !== body.bandGap || placed.infoToHeader !== body.bandGap || placed.headerToRows !== body.groupGap)
              headerFaults.push((surface.wide ? "window " : "popup ") + (stub.retro ? "retro " : "smooth ") + JSON.stringify(placed))
          }
        }
        surface.wide = false
        stub.retro = false
        wait(50)
        root.check("the range row, the info lines to their last column, and the list's header start at the rows' text and end at their figures, a band's gap apart, the header a group's gap over its rows; the unit's sign ends there in every unit and a step moves nothing beside it",
          headerFaults.length === 0, headerFaults.join(" | "))

        // The rows stop short of the scrollbar's gutter, so the thumb never
        // sits on a row.
        stub.retro = false
        var gutterFaults = []
        for (var g = 0; g < 2; g++) {
          surface.wide = g === 1
          wait(50)
          // The thumb as drawn: the bar's box carries padding that draws nothing.
          var thumb = body.watchlist.ScrollBar.vertical.contentItem
          var topRow = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
          var rowRight = xIn(topRow, topRow.width)
          var thumbLeft = xIn(thumb, 0)
          if (!(body.watchlist.interactive && thumb.visible && thumb.width > 0 && rowRight <= thumbLeft))
            gutterFaults.push((surface.wide ? "window" : "popup") + ": row ends " + rowRight + ", thumb starts " + thumbLeft + " and is " + thumb.width + " wide")
        }
        root.check("the rows stop short of the scrollbar's gutter", gutterFaults.length === 0, gutterFaults.join(" | "))

        // The window's smallest permitted height shows three whole rows: the
        // chart gives way first, down to 136 px; at the usual 760 px it keeps
        // all 220 and takes what whole rows leave over, less than a row.
        // The window's chart fits the window: set here, where the height is
        // the window's own, not fitted to the body as the popup's is.
        surface.fixedHeight = 760
        body.minChartHeight = Style.space(136)
        wait(50)
        var usualChart = body.chartItem.height
        surface.fixedHeight = body.smallestHeight !== undefined ? body.smallestHeight : body.chromeHeight + body.listRowHeight
        stub.featuredSymbol = "MZ"
        stub.range = "1D"
        stub.historyEntry = null
        wait(50)
        var minimum = root.measure()
        root.check("the window's smallest height shows three whole rows, its chart giving way to 136 px, and its usual height keeps the whole chart and less than a row more",
          body.watchlist.height === 3 * body.rowPitch - body.rowGap && body.chartItem.height === Style.space(136)
            && usualChart >= Style.space(220) && usualChart < Style.space(220) + body.rowPitch
            && minimum.footerGap === body.groupGap && minimum.footer <= surface.height,
          "list " + body.watchlist.height + " of " + surface.height + ", chart " + body.chartItem.height + ", at 760 " + usualChart)
        // At the window's smallest, every scrollbar's thumb is at least 24
        // px long, there to see and to grab.
        var listThumb = body.watchlist.ScrollBar.vertical.contentItem
        var thumbFaults = body.watchlist.interactive && listThumb.height >= Style.space(24) - 0.5 ? []
          : ["the list: " + (body.watchlist.interactive ? "thumb " + listThumb.height : "no overflow")]

        // At the window's smallest, each view over the rows shows a
        // scrollbar while more of it sits below, at rest, its entries short
        // of the bar, and dragging the bar reaches the view's end ("Manage
        // lists…" in the list menu). In both looks.
        var wideBefore = surface.wide
        surface.wide = true
        surface.windowWidth = Style.space(560)
        stub.lists = [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols },
          { name: "US", label: "US", count: 3, symbols: stub.symbols.slice(0, 3) },
          { name: "Tech", label: "Tech", count: 2, symbols: ["MZ", "AAPL"] },
          { name: "Growth", label: "Growth", count: 0, symbols: [] }].concat(["Crypto", "Wins", "Losses", "Watching"].map(function(n) {
            return { name: n, label: n, count: 1, symbols: ["MZ"] } }))
        wait(50)
        // [name, its scroll, open, close, the view whose cursor a key acts on]
        var smallViews = [
          ["list menu", "menuScroll", function() { body.openListMenu() }, function() { body.closeListMenu() }, "listMenu"],
          ["Manage lists", "manageScroll", function() { body.openManageLists() }, function() { body.closeListViews() }, "manageLists"],
          ["a symbol's lists", "symbolListsScroll", function() { body.openSymbolLists("MZ") }, function() { body.closeListViews() }, "symbolLists"],
          ["search", "searchResults", function() {
            body.startAdding()
            body.search.results = ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT"].map(function(s) { return { symbol: s, name: s, exchange: "NYSE" } })
            body.search.answer = "results"
          }, function() { body.search.results = []; body.search.answer = ""; body.cancelAdding() }, ""]
        ]
        var smallFaults = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          smallViews.forEach(function(v) {
            v[2]()
            // Past a symbol's lists' opening shield, which takes the
            // opening click's double-click; the others need a layout pass.
            wait(v[4] === "symbolLists" ? Qt.styleHints.mouseDoubleClickInterval + 100 : 50)
            var where = (retro ? "retro " : "smooth ") + v[0]
            var flick = find(body, v[1])
            var bar = flick ? flick.ScrollBar.vertical : null
            if (!flick || !bar) { smallFaults.push(where + ": no scrollbar"); v[3](); wait(50); return }
            var thumb = bar.contentItem
            if (thumb.height < Style.space(24) - 0.5) thumbFaults.push(where + ": thumb " + thumb.height)
            var entries = flick.contentItem.children[0]
            var entriesRight = xIn(entries, entries.width)
            // Drawn, not just there: a scrollbar that shows only while used
            // has its thumb at no opacity at rest.
            var shows = function() { return bar.visible && thumb.visible && thumb.opacity > 0 && thumb.height > 0 }
            if (!(flick.interactive && shows() && entriesRight <= xIn(thumb, 0)))
              smallFaults.push(where + ": overflows " + flick.interactive + ", bar " + bar.visible + ", thumb " + thumb.height
                + " at opacity " + thumb.opacity + ", entries end " + entriesRight + " thumb at " + xIn(thumb, 0))
            var grip = thumb.mapToItem(body, thumb.width / 2, thumb.height / 2)
            mousePress(body, grip.x, grip.y)
            mouseMove(body, grip.x, grip.y + flick.height / 2)
            mouseMove(body, grip.x, grip.y + flick.height)
            mouseRelease(body, grip.x, grip.y + flick.height)
            wait(800)
            if (Math.abs(flick.contentY - (flick.contentHeight - flick.height)) > 1 || !shows())
              smallFaults.push(where + ": the bar's drag ends at " + flick.contentY + " of " + (flick.contentHeight - flick.height)
                + ", the thumb then at opacity " + thumb.opacity)
            // The next key acts on an entry that shows: the drag brought the
            // cursor along. Found in review: Enter after the drag unticked a
            // list scrolled out of sight.
            var view = v[4] ? find(body, v[4]) : null
            if (view) {
              var cursorTop = view.topOf ? view.topOf(view.cursor) : view.cursor * view.itemHeight
              if (!(cursorTop < flick.contentY + flick.height && cursorTop + view.itemHeight > flick.contentY))
                smallFaults.push(where + ": the cursor stays on entry " + view.cursor + " at " + cursorTop
                  + ", out of sight at " + flick.contentY + "+" + flick.height)
            }
            v[3]()
            wait(50)
          })
        })
        root.check("at the window's smallest, every scrollbar's thumb is at least 24 px long",
          thumbFaults.length === 0, thumbFaults.join(" | "))

        // A search result's name runs up to its exchange code, one column
        // gap short of it, so a long name is cut only where the room ends.
        body.startAdding()
        body.search.results = [{ symbol: "RGTI", name: "Rigetti Computing, Incorporated Holdings", exchange: "NASDAQ" },
          { symbol: "RGTI.MX", name: "Rigetti Computing, Incorporated Holdings", exchange: "MEX" }]
        body.search.answer = "results"
        wait(100)
        var nameText = find(body.search, "searchName")
        var exchangeText = find(body.search, "searchExchange")
        var nameGap = nameText && exchangeText
          ? Math.round(xIn(exchangeText, exchangeText.width - exchangeText.contentWidth) - xIn(nameText, nameText.width)) : -1
        body.search.results = []
        body.search.answer = ""
        body.cancelAdding()
        wait(50)
        root.check("a search result's name runs up to its exchange code, one column gap short",
          nameGap >= 0 && nameGap <= body.search.columnGap + 1, "gap " + nameGap + " px")

        // What search leaves out is said on one line, whole, in the popup
        // and the window at its narrowest, in both looks: Yahoo's answers
        // for "vfiax" (a mutual fund alone) and "eurusd" (two indexes shown,
        // a currency and futures not), and the two together, three kinds.
        var vfiax = JSON.parse(vfiaxFile.text())
        var eurusd = JSON.parse(eurusdFile.text())
        var answers = [vfiax, eurusd, { quotes: vfiax.quotes.concat(eurusd.quotes) }].map(Search.parseSearch)
        var noteFaults = []
        body.startAdding()
        for (var nw = 0; nw < 2; nw++) {
          surface.wide = nw === 1
          surface.windowWidth = Style.space(560)
          for (var nlook = 0; nlook < 2; nlook++) {
            stub.retro = nlook === 1
            answers.forEach(function(answer) {
              body.search.results = answer.results
              body.search.note = answer.note
              body.search.answer = "results"
              wait(20)
              var t = find(body.search, "searchNote")
              var where = (surface.wide ? "window " + surface.width : "popup") + (stub.retro ? " retro: " : " smooth: ")
              if (!t.visible || t.lineCount !== 1 || t.truncated || t.implicitWidth > t.width + 0.5)
                noteFaults.push(where + t.text + " (" + Math.ceil(t.implicitWidth) + " px in " + t.width + ")")
            })
          }
        }
        body.search.results = []
        body.search.note = ""
        body.search.answer = ""
        body.cancelAdding()
        wait(50)
        root.check("what search leaves out is said whole on one line in the popup and the narrowest window, in both looks",
          noteFaults.length === 0, noteFaults.join(" | "))

        // Yahoo's five long symbols for "wrapped btc", each drawn whole, as
        // wide as it is, so no two coins read alike: in the popup and the
        // narrowest window.
        var coins = Search.parseSearch({ quotes: [
          { symbol: "XBTC39577-USD", longname: "OKX Wrapped BTC USD", exchange: "CCC", quoteType: "CRYPTOCURRENCY" },
          { symbol: "CBBTC32994-USD", longname: "Coinbase Wrapped BTC USD", exchange: "CCC", quoteType: "CRYPTOCURRENCY" },
          { symbol: "KBTC33513-USD", longname: "Kraken Wrapped Bitcoin USD", exchange: "CCC", quoteType: "CRYPTOCURRENCY" },
          { symbol: "WBTC-USD", longname: "Wrapped Bitcoin USD", exchange: "CCC", quoteType: "CRYPTOCURRENCY" },
          { symbol: "CIRBTC-USD", longname: "Circle Wrapped Bitcoin USD", exchange: "CCC", quoteType: "CRYPTOCURRENCY" }] })
        var resultRows = function() {
          return root.findAll(body.search, "searchResult")
        }
        var coinFaults = []
        body.startAdding()
        for (var cw = 0; cw < 2; cw++) {
          surface.wide = cw === 1
          body.search.results = coins.results
          body.search.answer = "results"
          wait(20)
          var coinRows = resultRows()
          var coinsDrawn = coinRows.map(function(row) {
            var span = root.drawnSpans(row).filter(function(s) { return s.what === row.modelData.symbol })[0]
            return span ? span.what + (span.whole ? "" : " (cut, " + (span.right - span.left) + " px)") : "none"
          })
          if (coinRows.length !== 5 || coinsDrawn.some(function(said) { return !/-USD$/.test(said) }))
            coinFaults.push((surface.wide ? "window " + surface.width : "popup") + ": " + coinsDrawn.join(", "))
        }
        body.search.results = []
        body.search.answer = ""
        body.cancelAdding()
        wait(50)
        root.check("search names all five long cryptocurrency symbols", coinFaults.length === 0, coinFaults.join(" | "))

        // At the window's smallest, five results and the note under them:
        // Down to the last brings it and the note into the view.
        surface.wide = true
        surface.windowWidth = Style.space(560)
        var mixed = JSON.parse(searchFile.text())
        mixed.quotes = mixed.quotes.concat([JSON.parse(eurusdFile.text()).quotes[0]])
        var mixedAnswer = Search.parseSearch(mixed)
        body.startAdding()
        body.search.results = mixedAnswer.results
        body.search.note = mixedAnswer.note
        body.search.answer = "results"
        wait(50)
        for (var down = 0; down < 5; down++) keyClick(Qt.Key_Down)
        wait(50)
        var view = find(body.search, "searchResults")
        var lastRow = resultRows()[4]
        var searchNote = find(body.search, "searchNote")
        var inView = function(item) { return !!item && yIn(item, 0) >= yIn(view, 0) && yIn(item, item.height) <= yIn(view, view.height) }
        var reached = body.search.resultIndex === 4 && body.search.results.length === 5 && inView(lastRow) && inView(searchNote)
          && searchNote.visible && searchNote.text === "Stonks doesn’t show currencies"
        var reachedSaid = "on " + body.search.resultIndex + " of " + body.search.results.length + ", the view " + yIn(view, 0) + "–" + yIn(view, view.height)
          + ", the last result " + (lastRow ? yIn(lastRow, 0) + "–" + yIn(lastRow, lastRow.height) : "none")
          + ", the note \"" + searchNote.text + "\" " + yIn(searchNote, 0) + "–" + yIn(searchNote, searchNote.height)
        body.search.results = []
        body.search.note = ""
        body.search.answer = ""
        body.cancelAdding()
        wait(50)
        root.check("the smallest window keeps all search results reachable by keys and names the excluded kind", reached, reachedSaid)
        stub.retro = false
        surface.wide = wideBefore
        surface.windowWidth = 720
        stub.lists = Qt.binding(function() {
          return [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }]
        })
        wait(50)
        root.check("at the window's smallest, the list menu, Manage lists, a symbol's lists, and search show a scrollbar and reach their end, the cursor coming along",
          smallFaults.length === 0, smallFaults.join(" | "))

        // The window's footer sits one gap under a short list, as the
        // popup's does, and at the window's bottom once the list fills it,
        // the rows then ending one gap above it, the chart taking what they
        // leave over; its note, hint, and notice go with it. An empty named
        // list keeps one row over it, an open list menu taller than the rows
        // pushes it down under the menu, and the views that take the rows'
        // place give it back there. The chart's height follows the window's
        // alone: every list at one height draws it the same. At the window's
        // smallest, its usual 760, 850, and tall. Smooth alone: the row pitch
        // and the footer are the look's own nowhere (the case loop's first
        // check holds them across looks).
        root.load()
        stub.library = stub.symbols.slice()
        var fullList = stub.symbols.slice()
        surface.wide = true
        body.minChartHeight = Style.space(136)
        var windowFaults = []
        var chartFaults = []
        // `rows` when the rows changed: past a row's slide or fade into its
        // place.
        var windowFooter = function(where, rows, chart) {
          wait(50)
          if (rows) within(1000, root.rowsAtRest)
          var footer = find(body, "footer")
          var gap = yIn(footer, 0) - root.lastRowBottom()
          var bottom = yIn(footer, footer.height)
          var room = surface.height - body.margins
          var ok = !footer.visible ? false : body.watchlist.interactive
            ? bottom === room && gap === body.groupGap
            : gap === body.groupGap && bottom <= room
          if (!ok) windowFaults.push(where + ": footer " + (footer.visible ? "ends " + bottom + " of " + room + ", " + gap + " under the rows"
            + (body.watchlist.interactive ? " of a list that fills it" : "") : "hidden"))
          if (chart !== null && body.chartItem.height !== chart)
            chartFaults.push(where + ": chart " + body.chartItem.height + ", " + chart + " under All")
        }
        ;[false].forEach(function(retro) {
          stub.retro = retro
          ;[body.smallestHeight, 760, 850, 1400].forEach(function(tall) {
            surface.fixedHeight = tall
            var at = tall + " px "
            stub.listName = ""
            stub.symbols = fullList.slice()
            wait(50)
            within(1000, root.rowsAtRest)
            var chart = body.chartItem.height
            windowFooter(at + "All", true, chart)
            stub.listName = "Tech"
            stub.symbols = ["MZ", "AAPL"]
            windowFooter(at + "two rows", true, chart)
            stub.symbols = ["MZ"]
            windowFooter(at + "one row", true, chart)
            body.hint = "Wheel over the pill to step symbols"
            body.note = "Keep at least one symbol"
            stub.settingsUnreadable = true
            // Only the popup shows a hint (Panel.qml), so its height here
            // judges the footer, not the chart.
            windowFooter(at + "one row, its hint, note, and notice", false, null)
            body.hint = ""
            body.note = ""
            stub.settingsUnreadable = false
            stub.listName = "Growth"
            stub.symbols = []
            windowFooter(at + "an empty named list", false, chart)
            stub.listName = "Tech"
            stub.symbols = ["MZ"]
            stub.lists = [
              { name: "", label: "All", count: fullList.length, symbols: fullList },
              { name: "Growth", label: "Growth", count: 0, symbols: [] },
              { name: "Tech", label: "Tech", count: 1, symbols: ["MZ"] },
              { name: "Semiconductors", label: "Semiconductors", count: 3, symbols: [] }
            ]
            body.openListMenu()
            wait(50)
            var menu = find(body, "listMenu")
            var menuFooter = find(body, "footer")
            // The menu runs down over the footer, inside the window's margin;
            // the footer stays at its place under the rows.
            if (!(menu.visible && yIn(menu, menu.height) <= surface.height - body.margins
                && yIn(menuFooter, menuFooter.height) <= surface.height - body.margins))
              windowFaults.push(at + "the list menu: it ends at " + yIn(menu, menu.height) + ", the footer "
                + yIn(menuFooter, 0) + "-" + yIn(menuFooter, menuFooter.height) + " in " + surface.height)
            body.closeListMenu()
            windowFooter(at + "the list menu closed", false, chart)
            ;[
              ["Manage lists", function() { body.openManageLists() }, function() { body.closeListViews() }],
              ["a symbol's lists", function() { body.openSymbolLists("MZ") }, function() { body.closeListViews() }],
              ["search", function() { body.startAdding() }, function() { body.cancelAdding() }],
              ["the key sheet", function() { body.showingHelp = true }, function() { body.showingHelp = false }]
            ].forEach(function(v) {
              v[1]()
              wait(50)
              v[2]()
              windowFooter(at + v[0] + " closed", false, chart)
            })
            stub.lists = Qt.binding(function() {
              return [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }]
            })
          })
        })
        root.check("the window's footer sits one gap under a short list, its note and notice too, and at its bottom once the list fills it, the rows one gap above it, at its smallest and taller",
          windowFaults.length === 0, windowFaults.join(" | "))
        root.check("the window's chart is as tall for every list at one window height",
          chartFaults.length === 0, chartFaults.join(" | "))
        stub.retro = false
        stub.listName = ""
        root.load()
        surface.wide = wideBefore
        wait(50)

        // Search takes its height as it opens, before any typing: the field
        // and a full set of results, or the rows' height when that is taller,
        // in the whole rows the room holds, and keeps it as the answer comes:
        // with All full, and nearly empty.
        body.minChartHeight = 0
        surface.fixedHeight = 0
        // The band's column lays the chart's new height out on its next
        // polish: the window's chart above was taller than the popup's.
        wait(50)
        var opens = function() {
          var rowsHeight = body.fittedHeight(730)
          body.adding = true
          wait(50)
          var opened = body.fittedHeight(730)
          body.search.results = [{ symbol: "ONE", name: "One", exchange: "NYSE" }]
          body.search.answer = "results"
          wait(50)
          var answered = body.fittedHeight(730)
          body.search.results = []
          body.search.answer = ""
          body.adding = false
          wait(50)
          var room = body.chromeHeight + body.rowsHeight(1000, 730 - body.chromeHeight)
          return [opened === Math.max(rowsHeight, Math.min(room, body.searchHeight)), answered === opened].join(",")
            + " " + rowsHeight + "->" + opened + "->" + answered
        }
        var fullAll = opens()
        stub.symbols = ["MZ", "AAPL"]
        wait(50)
        var shortAll = opens()
        root.check("search takes its height as it opens and keeps it as the answer comes, All full and nearly empty",
          /^true,true /.test(fullAll) && /^true,true /.test(shortAll), fullAll + " | " + shortAll)
        // Any budget takes every whole row it can hold and no more; at the
        // popup's cap, its fixed content and six whole rows, that is six. The
        // search check above left a short list behind.
        root.load()
        wait(50)
        var cap = body.chromeHeight + 6 * body.rowPitch - body.rowGap
        var budgets = [cap, cap - 1, cap - 30, 700]
        var loose = budgets.filter(function(budget) {
          var fitted = body.fittedHeight(budget)
          return fitted > budget || fitted + body.rowPitch <= budget
            || (fitted - body.chromeHeight + body.rowGap) % body.rowPitch !== 0
        })
        root.check("the popup takes every whole row its budget allows", loose.length === 0,
          budgets.map(function(b) { return b + "->" + body.fittedHeight(b) }).join(" "))

        // Another list, a long name, or an empty list moves nothing above the
        // rows, in either look; an empty list keeps one row, which says so.
        // The footer follows the list's rows. Each check runs both looks and
        // names the look it fails in.
        var listLabels = []
        var listFaults = {}
        var listCheck = function(look, label, ok, detail) {
          if (!(label in listFaults)) {
            listLabels.push(label)
            listFaults[label] = []
          }
          if (!ok) listFaults[label].push(look + ": " + detail)
        }
        for (var look = 0; look < 2; look++) {
          stub.retro = look === 1
          stub.listName = ""
          root.load()
          // All stays the library whichever list shows, as the service's does.
          stub.library = stub.symbols.slice()
          stub.featuredSymbol = "MZ"
          wait(50)
          var onAll = root.measure()
          stub.listName = "Semiconductors & AI infrastructure"
          stub.symbols = ["AAPL", "MZ"]
          wait(50)
          within(1000, root.rowsAtRest)
          var onList = root.measure()
          var lookName = stub.retro ? "retro" : "smooth"
          var keys = ["listing", "baseline", "change", "changeRight", "range", "info", "list", "row"]
          var shifted = keys.filter(function(key) { return onAll[key] !== onList[key] })
          listCheck(lookName, "a list switch with a long name moves nothing", shifted.length === 0,
            shifted.join(", ") + " all " + root.describe(onAll) + " list " + root.describe(onList))
          listCheck(lookName, "a long list name keeps TODAY after it and before the rule",
            onList.today > onList.listRight && onList.rule > onList.todayRight, root.describe(onList))
          stub.listName = "Growth"
          stub.symbols = []
          wait(50)
          var onEmpty = root.measure()
          var footerTop = function() { return yIn(find(body, "footer"), 0) }
          listCheck(lookName, "an empty list keeps one row, the footer one gap under it, and moves nothing above it",
            body.watchlist.height === body.rowPitch - body.rowGap && onEmpty.list === onAll.list
              && onEmpty.range === onAll.range && footerTop() === onEmpty.list + body.watchlist.height + body.groupGap
              && find(body, "emptyList").visible,
            root.describe(onEmpty) + " footer at " + footerTop())
          // An open list menu taller than the one row makes room for itself
          // and for the footer one gap under it: the surface grows until the
          // menu and the footer show inside it, in the whole rows the room
          // holds and never into what they leave over; the menu's lists
          // scroll in what is left.
          stub.lists = [
            { name: "", label: "All", count: 23, symbols: [] },
            { name: "Growth", label: "Growth", count: 0, symbols: [] },
            { name: "My Watchlist", label: "My Watchlist", count: 2, symbols: [] },
            { name: "Semiconductors", label: "Semiconductors", count: 3, symbols: [] }
          ]
          // With All one symbol long, the menu is taller than the rows.
          stub.library = ["AAPL"]
          wait(50)
          var shut = surface.height
          body.openListMenu()
          wait(50)
          var menu = find(body, "listMenu")
          var menuBottom = yIn(menu, menu.height)
          var footerAt = find(body, "footer")
          var menuRoom = body.chromeHeight + body.rowsHeight(1000, 730 - body.chromeHeight)
          listCheck(lookName, "an open list menu makes room for itself and the footer under it",
            menu.visible && surface.height > shut && surface.height === Math.min(menuRoom, body.listMenuBottom)
              && menuBottom + body.groupGap <= yIn(footerAt, 0) && yIn(footerAt, footerAt.height) <= surface.height,
            "menu " + menu.height + " of " + menu.contentHeight + " ends at " + menuBottom + ", footer at " + yIn(footerAt, 0)
              + " in " + surface.height + " of a room of " + menuRoom + ", shut " + shut)
          body.closeListMenu()
          stub.lists = Qt.binding(function() {
            return [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }]
          })
          wait(50)
          // Manage lists and a symbol's lists take the rows' place and move
          // nothing above it.
          stub.listName = ""
          root.load()
          wait(50)
          var above = ["listing", "baseline", "change", "changeRight", "range", "info"]
          // Over search's results and the list views the header names the
          // list only, on a line of the same height.
          var header = find(body, "listLabel").parent
          var headerHeight = header.height
          var rowsOnly = ["todayLabel", "breadthRule", "orderLabel", "orderControl", "unitSign", "unitFill", "unitTarget"]
          var namesOnly = function() {
            var shown = rowsOnly.filter(function(name) { return find(body, name).visible })
            return find(body, "listLabel").visible && shown.length === 0 && header.height === headerHeight
              ? "" : "shown " + shown.join(",") + " height " + header.height + " of " + headerHeight
          }
          var views = [
            { name: "manageLists", open: function() { body.openManageLists() }, close: function() { body.closeListViews() } },
            { name: "symbolLists", open: function() { body.openSymbolLists("MZ") }, close: function() { body.closeListViews() } },
            { name: "symbolSearch", open: function() {
              body.startAdding()
              body.search.results = [{ symbol: "ONE", name: "One", exchange: "NYSE" }]
              body.search.answer = "results"
            }, close: function() { body.search.results = []; body.search.answer = ""; body.cancelAdding() } }
          ]
          for (var v = 0; v < views.length; v++) {
            views[v].open()
            wait(50)
            var withView = root.measure()
            var viewMoved = above.filter(function(key) { return onAll[key] !== withView[key] })
            var view = find(body, views[v].name)
            listCheck(lookName, views[v].name + " takes the rows' place and moves nothing above them",
              viewMoved.length === 0 && view.visible && yIn(view, 0) === onAll.list,
              viewMoved.join(", ") + " view at " + yIn(view, 0) + " rows at " + onAll.list)
            var named = namesOnly()
            listCheck(lookName, "over " + views[v].name + " the list header names the list only", named === "", named)
            views[v].close()
            wait(50)
          }
          listCheck(lookName, "with the rows back the header says TODAY, the breadth, and the order again",
            rowsOnly.every(function(name) { return find(body, name).visible }), rowsOnly.filter(function(name) { return !find(body, name).visible }).join(","))
        }
        listLabels.forEach(function(label) { root.check(label, listFaults[label].length === 0, listFaults[label].join(" | ")) })
        // A long list menu shows whole rows only, and "New list…" and
        // "Manage lists…" in reach without scrolling, with 12 lists or 30,
        // in the popup at its cap and the window at its smallest and its
        // usual height, in both looks; a click on Manage lists opens it.
        var listsBeforeMenu = stub.lists
        var menuFaults = []
        var menuSeen = []
        ;[12, 30].forEach(function(count) {
          stub.lists = [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }].concat(
            Array.from({ length: count - 1 }, function(_, n) { return { name: "List " + (n + 1), label: "List " + (n + 1), count: 1, symbols: ["MZ"] } }))
          ;[["popup", 0], ["window smallest", -1], ["window", 760]].forEach(function(place) {
            surface.wide = place[0] !== "popup"
            body.minChartHeight = surface.wide ? Style.space(136) : 0
            surface.fixedHeight = place[1] < 0 ? body.smallestHeight : place[1]
            ;[false, true].forEach(function(retro) {
              stub.retro = retro
              wait(50)
              body.openListMenu()
              wait(100)
              var where = count + " lists, " + place[0] + " " + (retro ? "retro" : "smooth")
              var menu = find(body, "listMenu")
              var scroll = find(menu, "menuScroll")
              var inMenu = function(item) { var at = item.mapToItem(menu, 0, 0); return at.y >= -0.5 && at.y + item.height <= menu.height + 0.5 }
              var cutRows = function() {
                return Array.from(scroll.contentItem.children[0].children).filter(function(row) {
                  var at = row.mapToItem(scroll, 0, 0)
                  return row.objectName === "listChoice" && at.y < scroll.height && at.y + row.height > 0
                    && (at.y < -0.5 || at.y + row.height > scroll.height + 0.5)
                }).length
              }
              // The scroll moves from `from`, then comes to rest.
              var settled = function(from) {
                for (var t = 0; t < 2000 && (scroll.contentY === from || scroll.moving || cutRows() > 0); t += 20) wait(20)
                return scroll.contentY === from ? -1 : cutRows()
              }
              // As the menu opens; after a wheel notch over the lists and a
              // drag of the scrollbar part way, in one look, the rows being
              // alike in both; scrolled to its end. A notch must stop on a
              // row's edge.
              var atRest = cutRows()
              var pinnedShown = inMenu(find(menu, "newListRow")) && inMenu(find(menu, "manageListsRow"))
              var afterWheel = 0
              var afterDrag = 0
              var afterKey = 0
              if (!retro) {
                var over = scroll.mapToItem(body, scroll.width / 3, scroll.height / 2)
                mouseMove(body, over.x, over.y)
                var beforeWheel = scroll.contentY
                mouseWheel(body, over.x, over.y, 0, -120)
                afterWheel = settled(beforeWheel)
                var thumb = scroll.ScrollBar.vertical.contentItem
                var grip = thumb.mapToItem(body, thumb.width / 2, thumb.height / 2)
                var beforeDrag = scroll.contentY
                mousePress(body, grip.x, grip.y)
                mouseMove(body, grip.x, grip.y + 7)
                mouseMove(body, grip.x, grip.y + scroll.height / 4 + 7)
                mouseRelease(body, grip.x, grip.y + scroll.height / 4 + 7)
                afterDrag = settled(beforeDrag)
                // A key while the lists settle after a notch back up lands
                // them on a row's edge at once.
                var beforeKey = scroll.contentY
                mouseWheel(body, over.x, over.y, 0, 120)
                for (var k = 0; k < 1000 && (scroll.contentY === beforeKey || scroll.moving
                  || scroll.contentY % menu.itemHeight === 0); k += 5) wait(5)
                var cursorBefore = menu.cursor
                keyClick(Qt.Key_Down)
                wait(20)
                afterKey = menu.cursor === cursorBefore ? -2 : cutRows()
              }
              scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
              var cuts = [atRest, afterWheel, afterDrag, afterKey, cutRows()]
              // The popup's menu ends a gap above the footer; the window's
              // may run over it, to the body's margin.
              var menuFloor = surface.wide ? surface.height - body.margins : yIn(find(body, "footer"), 0) - body.groupGap
              menuSeen.push(where + ": " + scroll.height / menu.itemHeight + " rows")
              if (cuts.some(function(n) { return n !== 0 }) || !pinnedShown || yIn(menu, menu.height) > menuFloor)
                menuFaults.push(where + ": rows cut (opened/wheel/bar/key/end, -1 unmoved, -2 key unheard) " + cuts.join("/") + " in a view " + scroll.height + " px, pinned in sight " + pinnedShown
                  + ", menu ends " + yIn(menu, menu.height) + " floor at " + menuFloor)
              var manageRow = find(menu, "manageListsRow")
              var manageAt = manageRow.mapToItem(body, manageRow.width / 2, manageRow.height / 2)
              mouseClick(body, manageAt.x, manageAt.y)
              wait(50)
              if (!body.managingLists) menuFaults.push(where + ": a click on Manage lists… did not open it")
              body.closeListViews()
              body.closeListMenu()
              wait(50)
            })
          })
        })
        // The window at its usual 720 × 760 shows five lists of the demo's
        // six in the menu, which runs down over the footer, in both looks:
        // a pin of the owner's approved layout.
        stub.lists = [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }].concat(
          ["My Watchlist", "Watching", "Growth", "Wins", "Losses"].map(function(name) { return { name: name, label: name, count: 1, symbols: ["MZ"] } }))
        surface.wide = true
        surface.windowWidth = 720
        body.minChartHeight = Style.space(136)
        surface.fixedHeight = 760
        var fiveSeen = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          wait(50)
          body.openListMenu()
          wait(100)
          var menu = find(body, "listMenu")
          var scroll = find(menu, "menuScroll")
          fiveSeen.push((retro ? "retro " : "smooth ") + Math.round(scroll.height / menu.itemHeight * 10) / 10 + " lists, menu ends "
            + yIn(menu, menu.height) + " of " + surface.height)
          if (scroll.height < 5 * menu.itemHeight || yIn(menu, menu.height) > surface.height - body.margins) fiveSeen.push("FAULT")
          body.closeListMenu()
          wait(50)
        })
        stub.lists = listsBeforeMenu
        stub.retro = false
        surface.wide = false
        surface.fixedHeight = 0
        body.minChartHeight = 0
        wait(50)
        root.check("a long list menu shows whole rows, and New list and Manage lists without scrolling, in the popup and the window, in both looks",
          menuFaults.length === 0, menuFaults.join(" | ") + " || " + menuSeen.join(", "))
        root.check("the window's list menu at its usual 720 × 760 shows five of six lists, over the footer and inside the window, in both looks",
          fiveSeen.indexOf("FAULT") < 0, fiveSeen.join(", "))

        // A view opening over the rows moves nothing: the list menu, search,
        // Manage lists, and a row's ticks keep the surface's height and its
        // edge, on a list of 20 rows with 13 lists. In the popup at a room
        // 24 px and 4 px under its cap, as 760 and 780 are under a 784 px
        // cap, and at the cap; in the window at 760, 780, and that cap's
        // height. Smooth alone: the height and edge are no look's own (the
        // case loop's first check holds the rows and footer across looks).
        var listsBeforeViews = stub.lists
        var libraryBeforeViews = stub.library
        var symbolsBeforeViews = stub.symbols
        var allSymbols = stub.symbols.slice()
        stub.library = allSymbols
        stub.lists = [{ name: "", label: "All", count: allSymbols.length, symbols: allSymbols },
          { name: "Core", label: "Core", count: 20, symbols: allSymbols.slice(0, 20) }].concat(
          Array.from({ length: 11 }, function(_, n) { return { name: "List " + (n + 1), label: "List " + (n + 1), count: 3, symbols: allSymbols.slice(n, n + 3) } }))
        stub.listName = "Core"
        stub.symbols = allSymbols.slice(0, 20)
        body.minChartHeight = 0
        var cap = body.chromeHeight + 6 * body.rowPitch - body.rowGap
        var viewOpens = [
          ["the list menu", function() { body.openListMenu() }, function() { body.closeListMenu() }],
          ["search", function() { body.startAdding() }, function() { body.cancelAdding() }],
          ["Manage lists", function() { body.openManageLists() }, function() { body.closeListViews() }],
          ["a row's ticks", function() { body.openSymbolLists(stub.symbols[0]) }, function() { body.closeListViews() }]
        ]
        var heldFaults = []
        var heldSeen = []
        ;["popup", "window"].forEach(function(place) {
          surface.wide = place === "window"
          ;(surface.wide ? [760, 780, cap] : [cap - 24, cap - 4, cap]).forEach(function(room) {
            if (surface.wide) surface.fixedHeight = room
            else surface.budget = room
            ;[false].forEach(function(retro) {
              stub.retro = retro
              wait(50)
              var where = place + " " + room
              var shut = [surface.height, Math.round(body.edge)].join("/")
              heldSeen.push(where + " " + shut)
              viewOpens.forEach(function(v) {
                v[1]()
                // A row's ticks open behind a shield against the opening
                // click's double-click; the others in a layout pass.
                wait(v[0] === "a row's ticks" ? Qt.styleHints.mouseDoubleClickInterval + 50 : 50)
                var open = [surface.height, Math.round(body.edge)].join("/")
                if (open !== shut) heldFaults.push(where + ", " + v[0] + ": height/edge " + shut + " -> " + open)
                v[2]()
                wait(50)
              })
            })
          })
        })
        // The menu's least, one list row and the pinned rows with a refused
        // name's note, fits over the footer wherever the room holds it,
        // though the room's whole rows don't: one symbol in All, the first-run
        // hint, at a room from the least to 40 px over it, in both looks.
        surface.wide = false
        surface.fixedHeight = 0
        stub.lists = [{ name: "", label: "All", count: 1, symbols: ["MZ"] }]
        stub.library = ["MZ"]
        stub.listName = ""
        stub.symbols = ["MZ"]
        body.showFirstRunHint()
        var leastFaults = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          body.openListMenu()
          wait(50)
          var menu = find(body, "listMenu")
          menu.resumeNaming("All", "A list has that name already")
          wait(50)
          var least = body.listMenuTop + menu.itemHeight + menu.pinnedHeight + menu.inset * 2 + body.groupGap
            + find(body, "footer").height + body.margins
          for (var extra = 0; extra <= 40; extra += 10) {
            surface.budget = least + extra
            wait(50)
            var footer = find(body, "footer")
            var menuEnd = yIn(menu, menu.height)
            if (menuEnd + body.groupGap > yIn(footer, 0) || yIn(footer, footer.height) > surface.height)
              leastFaults.push((retro ? "retro" : "smooth") + " room " + (least + extra) + ": menu ends " + menuEnd + ", footer " + yIn(footer, 0)
                + "–" + yIn(footer, footer.height) + " in " + surface.height)
          }
          menu.stopNaming()
          body.closeListMenu()
          wait(50)
        })
        body.hint = ""
        surface.wide = false
        surface.fixedHeight = 0
        surface.budget = 730
        stub.retro = false
        stub.listName = ""
        stub.symbols = symbolsBeforeViews
        stub.library = libraryBeforeViews
        stub.lists = listsBeforeViews
        wait(50)
        root.check("a view opening over the rows keeps the surface's height and edge: the list menu, search, Manage lists, and a row's ticks, at a room of 760, 780, and the popup's cap, in the popup and the window",
          heldFaults.length === 0, heldFaults.join(" | ") + " || " + heldSeen.join(", "))
        root.check("the list menu's least, a refused name's note too, fits over the footer wherever the room holds it, under the first-run hint, in both looks",
          leastFaults.length === 0, leastFaults.join(" | "))
        // A shorter list's rows are its own, and the footer sits one gap under
        // them (an empty list's is the list switch's check above).
        stub.retro = false
        stub.listName = ""
        root.load()
        stub.library = stub.symbols.slice()
        wait(50)
        within(1000, root.rowsAtRest)
        var lists = [{ name: "Growth", symbols: ["AAPL", "MZ"] }, { name: "Losses", symbols: [] }]
        stub.listName = lists[0].name
        stub.symbols = lists[0].symbols
        wait(50)
        within(1000, root.rowsAtRest)
        var shortList = root.measure()
        root.check("a shorter list's footer sits one gap under its rows",
          body.watchlist.height === 2 * body.rowPitch - body.rowGap
            && yIn(find(body, "footer"), 0) === shortList.list + body.watchlist.height + body.groupGap,
          root.describe(shortList) + ", list " + body.watchlist.height)

        // Search's field opens where the list's rows were, under its
        // header, and stays there while you type, on any list, at either
        // surface size.
        var fieldPlaces = []
        var fieldBar = find(body.search, "searchField").parent
        for (var w = 0; w < 2; w++) {
          surface.wide = w === 1
          var cases = [{ name: "", symbols: stub.library }].concat(lists)
          for (var c2 = 0; c2 < cases.length; c2++) {
            stub.listName = cases[c2].name
            stub.symbols = cases[c2].symbols
            wait(50)
            var rowsY = yIn(body.watchlist, 0)
            body.startAdding()
            wait(50)
            var fieldY = yIn(fieldBar, 0)
            body.search.results = [{ symbol: "ONE", name: "One", exchange: "NYSE" }]
            body.search.answer = "results"
            wait(50)
            var typedY = yIn(fieldBar, 0)
            body.search.results = []
            body.search.answer = ""
            body.cancelAdding()
            wait(50)
            if (fieldY !== rowsY || typedY !== fieldY)
              fieldPlaces.push((surface.wide ? "window " : "popup ") + (cases[c2].name || "All") + " rows at "
                + rowsY + ", field " + fieldY + " -> " + typedY)
          }
        }
        surface.wide = false
        root.check("search's field opens where the rows were and stays while you type, on any list and either surface", fieldPlaces.length === 0,
          fieldPlaces.join(", "))

      }

      function liveLayout() {
        var year = History.parseHistory(JSON.parse(shopYearFile.text()), "1Y")
        // A live day and a range say the same words in the same place: nothing
        // is put in front of them while the market trades, so a range change
        // or a scrub moves nothing in the header. The chart's breathing dot
        // says live.
        stub.listName = ""
        stub.retro = false
        root.load()
        var shop = stub.quotes["SHOP.TO"]
        var liveNow = shop.marketTime + 30
        stub.now = liveNow
        stub.entries = Object.assign({}, stub.entries, { "SHOP.TO": { status: "ok", receivedAt: liveNow } })
        stub.featuredSymbol = "SHOP.TO"
        stub.range = "1D"
        stub.historyEntry = null
        wait(50)
        var status = find(body, "statusText")
        var onDay = { text: status.text, x: xIn(status, 0), live: body.heroLive }
        stub.range = "1Y"
        stub.historyEntry = { status: "ok", history: year, receivedAt: liveNow }
        wait(50)
        var onRange = { text: status.text, x: xIn(status, 0) }
        root.check("the header's words hold still from a live day to a range",
          onDay.live && onDay.text === onRange.text && onDay.x === onRange.x,
          JSON.stringify(onDay) + " " + JSON.stringify(onRange))
        stub.range = "1D"
        stub.historyEntry = null

        // A closing surface keeps its live marks as they are: the header's
        // words keep their colour, and the dot's ripple (retro's blinking cap)
        // stops where it is, then goes on as the surface opens. While the
        // chart asked for is on its way, the live day held on show holds
        // still with it: its halo and cap are the same picture on every frame
        // until the dim a quarter second on, and once it rests.
        var landPrice = function(delta) {
          var quote = stub.quotes["SHOP.TO"]
          var points = quote.points.slice()
          var last = points[points.length - 1]
          points[points.length - 1] = { t: last.t, p: last.p + delta }
          stub.quotes = Object.assign({}, stub.quotes, { "SHOP.TO": Object.assign({}, quote, { points: points }) })
        }
        var liveMarks = function(retro) {
          stub.retro = retro
          // A new price sets the mark moving: it rests otherwise.
          landPrice(0.01)
          wait(50)
          var mark = find(body, retro ? "liveCap" : "liveHalo")
          var moving = function() { return retro ? mark.opacity < 1 : mark.scale > 1.2 }
          var reached = false
          for (var t = 0; t < 3000 && !reached; t += 10) { wait(10); reached = moving() }
          var colour = String(status.color)
          var at = retro ? mark.opacity : mark.scale
          body.surfaceOpen = false
          wait(200)
          var held = [body.heroLive, String(status.color) === colour, (retro ? mark.opacity : mark.scale) === at].join(",")
          body.surfaceOpen = true
          var before = retro ? mark.opacity : mark.scale
          var goesOn = false
          for (var u = 0; u < 2000 && !goesOn; u += 10) { wait(10); goesOn = (retro ? mark.opacity : mark.scale) !== before }
          stub.range = "1Y"
          stub.historyEntry = null
          grab.source = body.chartItem
          grab.begin("loading-live-" + (retro ? "retro" : "smooth"))
          var heldLive = body.chartLoading && body.heroLive
          tryVerify(function() { return grab.frames.length >= 90 }, 5000)
          grab.end()
          tryVerify(function() { return grab.waiting === 0 }, 3000)
          grab.judge("dim")
          tryVerify(function() { return grab.verdict !== null }, 10000)
          stub.range = "1D"
          wait(50)
          return reached + "," + held + "," + goesOn + "," + (heldLive && grab.verdict.ok) + " " + grab.verdict.detail
        }
        var smoothLive = liveMarks(false)
        var retroLive = liveMarks(true)
        // A new price while the market trades ripples the dot three times,
        // or blinks retro's cap four, about 6 s, then the mark rests in its
        // still look, so the popup stops redrawing; an answer with the same
        // price starts nothing.
        var restsAfterNewPrice = function(retro) {
          stub.retro = retro
          wait(50)
          var mark = find(body, retro ? "liveCap" : "liveHalo")
          var still = function() {
            return retro ? mark.opacity === 1 : mark.scale === 1 && Math.abs(mark.opacity - 0.25) <= 0.001
          }
          var atRest = function(ms) {
            for (var r = 0; r < ms; r += 50) {
              if (!still()) return false
              wait(50)
            }
            return true
          }
          var landedAt = Date.now()
          landPrice(0.5)
          var moved = false
          for (var v = 0; v < 2000 && !moved; v += 10) { wait(10); moved = !still() }
          wait(Math.max(0, 7000 - (Date.now() - landedAt)))
          var rests = atRest(1000)
          landPrice(0)
          var samePrice = atRest(1500)
          // The key sheet over the chart and gone again shows the mark
          // again, with no new price: it stays at rest, and opened over a
          // burst, the burst ends with it: only a new price or an open starts
          // one.
          body.showingHelp = true
          wait(100)
          body.showingHelp = false
          var afterSheet = atRest(1000)
          landPrice(0.2)
          var burst = false
          for (var b = 0; b < 2000 && !burst; b += 10) { wait(10); burst = !still() }
          body.showingHelp = true
          wait(300)
          body.showingHelp = false
          afterSheet = burst && atRest(2000) && afterSheet
          // A reopen with the same price, as the window and the popup open:
          // the surface opens, then its chart draws in, hiding the mark
          // until it is whole. The mark moves once it shows: after a close
          // at rest, and after one mid-burst, which paused it: the burst the
          // first reopen set going.
          var reopenMoves = function(midBurst) {
            if (midBurst && still()) return false
            body.surfaceOpen = false
            wait(100)
            body.surfaceOpen = true
            body.motion.revealChart()
            tryVerify(function() { return body.motion.reveal === 1 }, 3000)
            var moves = false
            for (var w = 0; w < 2500 && !moves; w += 10) { wait(10); moves = !still() }
            return moves
          }
          var onOpen = reopenMoves(false)
          onOpen = reopenMoves(true) && onOpen
          return [body.heroLive, moved, rests, samePrice, afterSheet, onOpen].join(",")
        }
        var restSmooth = restsAfterNewPrice(false)
        var restRetro = restsAfterNewPrice(true)
        stub.retro = false
        root.check("a new price, or a reopen, moves the live mark, the dot's ripple and retro's cap, which rests 7 s on; the same price again, or the mark shown again, starts nothing",
          restSmooth === "true,true,true,true,true,true" && restRetro === "true,true,true,true,true,true",
          "smooth " + restSmooth + " | retro " + restRetro)
        // An aged quote is said plainly in the hero's listing line, as its row
        // says it; only overdue or failed takes the warning mark ("! AS OF"
        // would read as a warning). Smooth and retro.
        var listing = find(body, "listingLine")
        var lead = function(retro, age, unanswered) {
          stub.retro = retro
          stub.now = shop.marketTime + age
          stub.entries = Object.assign({}, stub.entries, { "SHOP.TO": { status: "ok", receivedAt: stub.now } })
          stub.owed = unanswered ? { "SHOP.TO": stub.now - unanswered } : {}
          wait(50)
          return listing.text.slice(0, 2)
        }
        var aged = [lead(false, 200, 0), lead(true, 200, 0)]
        var overdue = [lead(false, 200, 91), lead(true, 200, 91)]
        stub.retro = false
        stub.now = liveNow
        stub.entries = Object.assign({}, stub.entries, { "SHOP.TO": { status: "ok", receivedAt: liveNow } })
        stub.owed = {}
        wait(50)
        root.check("the hero says an aged quote plainly and marks only a warning, smooth and retro",
          aged.every(function(t) { return t === "AS" }) && overdue.every(function(t) { return t === "! " }),
          aged.join(",") + " | " + overdue.join(","))
        root.check("a closing surface, and a live day held while the next chart loads, hold the live marks: the words' colour and the ripple, smooth and retro",
          /^true,true,true,true,true,true /.test(smoothLive) && /^true,true,true,true,true,true /.test(retroLive),
          smoothLive + " | " + retroLive)

        // The header's words keep the animal's place in both looks, drawn or
        // not: while a featured symbol's first quote is still out (every
        // add), and across a look switch.
        var places = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          stub.featuredSymbol = "LOAD"
          wait(50)
          places.push(xIn(status, 0))
          stub.featuredSymbol = "SHOP.TO"
          wait(50)
          places.push(xIn(status, 0))
        })
        root.check("the header's words hold still across looks and while a symbol's first quote is out",
          places.every(function(x) { return x === places[0] }) && places[0] > 0, places.join(", "))
        stub.retro = false
        wait(50)

        // Each header icon on the right says on hover, past the shell's 400
        // ms delay, what a click does, in the one tip open, under its icon
        // and within the body, with room above or none; the animal says
        // nothing. Retro only for the look toggle, whose words are the
        // look's: the other tips are no look's own.
        var tipFaults = []
        var tipWords = []
        ;[["animalToggle"], ["soundToggle", "Turn sounds off"], ["cameraButton", "Take a screenshot"],
          ["lookToggle", "Switch to retro", "Switch to smooth"], ["helpToggle", "Show all keys"]].forEach(function(want) {
          var toggle = find(body, want[0])
          ;(want[2] ? [false, true] : [false]).forEach(function(retro) {
            stub.retro = retro
            ;[0, 80].forEach(function(above) {
              surface.y = above
              wait(50)
              var where = (retro ? "retro " : "smooth ") + want[0] + " with " + above + " px above"
              if (!toggle) { tipFaults.push(where + " missing"); return }
              mouseMove(toggle, toggle.width / 2, toggle.height / 2)
              var words = want[0] === "soundToggle" && !find(body, "soundIcon").on ? "Turn sounds on" : want[retro && want[2] ? 2 : 1]
              // The animal's tip must stay shut past the whole delay.
              if (words === undefined) wait(600)
              else within(1500, function() { return root.openTips(body, []).length > 0 })
              var tips = root.openTips(body, [])
              if (words === undefined ? tips.length !== 0 : tips.length !== 1 || tips[0].text !== words)
                tipFaults.push(where + ": " + JSON.stringify(tips.map(function(t) { return t.text })) + ", not " + JSON.stringify(words))
              tips.forEach(function(t) {
                var fault = root.tipFault(t, toggle)
                if (fault) tipFaults.push(where + ": " + fault)
              })
              if (!retro) tipWords.push(tips.map(function(t) { return t.text }).join(", "))
              mouseMove(body, body.width / 2, body.height - 4)
              within(1000, function() { return root.openTips(body, []).length === 0 })
            })
          })
        })
        surface.y = 0
        console.log("header tips: " + tipWords.join(" | "))
        root.check("each header icon's hover says what a click does, under its icon and within the body, with room above or none, and the animal's nothing; the look toggle's in both looks",
          tipFaults.length === 0, tipFaults.join(" | "))
        stub.retro = false
        wait(50)

        // A new order is a new arrangement: every row takes its place at once,
        // and so does the same order the other way.
        var placed = function() {
          return stub.view.shown.every(function(s, i) { return body.watchlist.rowItem(s).y === i * body.rowPitch })
        }
        var where = function() {
          return stub.view.shown.map(function(s, i) { return s + "@" + body.watchlist.rowItem(s).y + "/" + i * body.rowPitch })
            .filter(function(text, i) { return body.watchlist.rowItem(stub.view.shown[i]).y !== i * body.rowPitch }).slice(0, 4).join(" ")
        }
        // 20 ms: one frame or two, far short of a slide.
        stub.order = "pct"
        wait(20)
        var newPlaced = placed()
        var newWhere = where()
        var unreversed = stub.view.shown[0]
        stub.reversed = true
        wait(20)
        root.check("a new order places every row at once", newPlaced && placed() && stub.view.shown[0] !== unreversed,
          "new: " + newWhere + "; reversed: " + where())
        stub.reversed = false
        stub.order = "manual"
        wait(50)
        within(1000, root.rowsAtRest)

        // The order word shows its direction with an arrow, on one line, and
        // no order moves anything: a flip moves nothing beside it, the word's
        // ends and the rule's, and every order, manual included, holds the
        // word's top, bottom, and right end, and the first row's top, even
        // where an arrow's glyph comes from another font. In both looks, both
        // widths.
        var word = find(body, "orderLabel")
        var rule = find(body, "breadthRule")
        var wordFaults = []
        var wants = { manual: ["↕  MANUAL"], symbol: ["↑  SYMBOL", "↓  SYMBOL"], name: ["↑  NAME", "↓  NAME"],
          pct: ["↓  % CHANGE", "↑  % CHANGE"] }
        for (var ow = 0; ow < 2; ow++) {
          surface.wide = ow === 1
          for (var olook = 0; olook < 2; olook++) {
            stub.retro = olook === 1
            var held = []
            Object.keys(wants).forEach(function(order) {
              stub.order = order
              var at = []
              var spot = (surface.wide ? "window " : "popup ") + (stub.retro ? "retro " : "smooth ") + order
              for (var dir = 0; dir < wants[order].length; dir++) {
                stub.reversed = dir === 1
                wait(20)
                if (word.text !== wants[order][dir] || word.lineCount !== 1 || word.truncated
                    || xIn(word, 0) <= xIn(rule, rule.width) || xIn(word, word.width) > body.width)
                  wordFaults.push(spot + (dir ? " reversed" : "") + ": \"" + word.text + "\" " + word.lineCount + " lines")
                at.push([xIn(word, 0), xIn(word, word.width), yIn(word, 0), yIn(word, word.height), xIn(rule, rule.width)].join(","))
                var firstRow = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
                held.push({ order: order + (dir ? " reversed" : ""), at: [yIn(firstRow, 0), yIn(word, 0), yIn(word, word.height), xIn(word, word.width)].join(",") })
              }
              if (at.length > 1 && at[0] !== at[1]) wordFaults.push(spot + " moved: " + at.join(" -> "))
            })
            if (!held.every(function(h) { return h.at === held[0].at }))
              wordFaults.push((surface.wide ? "window " : "popup ") + (stub.retro ? "retro" : "smooth")
                + " across orders (first row's top, word's top, bottom, right): "
                + held.map(function(h) { return h.order + " " + h.at }).join(" / "))
          }
        }
        stub.reversed = false
        stub.order = "manual"
        stub.retro = false
        surface.wide = false
        wait(50)
        within(1000, root.rowsAtRest)
        root.check("the order word names its direction on one line, and no order or flip moves it or the rows, in both looks at both widths",
          wordFaults.length === 0, wordFaults.join(" | "))

        // No word on screen names a key: a button says only what it does, and
        // the keys are on the key sheet, whose table is left out here. The
        // button Enter takes, and only it, is marked as the shell marks its
        // default, and every button is one line, whole, inside the surface.
        // In every view that has buttons, in both looks, in the popup and the
        // smallest window ("esc cancel" reads as two buttons).
        var namesKey = function(text) {
          return /⏎|↵|\besc\b|\benter\b/i.test(text) || /\b[a-z0-9] to [a-z]/i.test(text) || /^[A-Z] [A-Z]{2,}/.test(text)
        }
        // Whether an item and every item it sits in are shown.
        var shown = function(item) {
          for (var it = item; it && it !== body; it = it.parent)
            if (!it.visible || it.opacity === 0) return false
          return true
        }
        // Whether a button is painted as the one Enter takes: the shell's
        // default mark, its selected fill under its word in the selected
        // colour. Read off what is drawn, not off the flag that asks for it.
        var paintedMarked = function(button, fill, foreground) {
          return Qt.colorEqual(fill.color, Style.selectedFillFor(foreground, Commons.Color.accent))
            && Qt.colorEqual(button.color, Style.selectedStateColor(foreground, Commons.Color.accent))
        }
        // The view's shown texts that name a key, its shown buttons, and the
        // ones painted as Enter's: a marked button, or search's chosen
        // label. A bare digit names a number key, unless it is a list's
        // count. A Flickable lists its rows as its children and its
        // contentItem's.
        var survey = function(scope) {
          var out = { keys: [], buttons: [], marked: [] }
          var visited = []
          var walk = function(node) {
            if (!node || !node.visible || visited.indexOf(node) >= 0) return
            visited.push(node)
            var reference = node.objectName === "helpKey" || node.objectName === "helpGesture"
            var text = String(node.text)
            var key = namesKey(text) || (/^[1-9]$/.test(text) && node.objectName !== "listCount")
            if (!reference && node.lineCount !== undefined && key && shown(node)) out.keys.push(node)
            var button = node.enterTakes !== undefined && node.activated !== undefined
            if (button && shown(node)) {
              out.buttons.push(node)
              if (paintedMarked(node, find(node, "actionFill"), node.view.foreground)) out.marked.push(node.objectName)
            }
            if (node.objectName === "searchAdd" && shown(node)) {
              out.buttons.push(node.children[0])
              if (paintedMarked(node.children[0], node, body.search.foreground)) out.marked.push(node.objectName)
            }
            for (var i = 0; i < node.children.length; i++) walk(node.children[i])
          }
          walk(scope)
          return out
        }
        var manage = find(body, "manageLists")
        var listMenu = find(body, "listMenu")
        var footerItem = find(body, "footer")
        var headerItem = find(body, "statusText").parent
        var shopResults = [
          { symbol: "SHOP", name: "Shopify Inc.", exchange: "NASDAQ" },
          { symbol: "SHOP.TO", name: "Shopify Inc.", exchange: "TSX" },
          { symbol: "SHHI.NE", name: "Ninepoint Shopify High Income", exchange: "NEO" }
        ]
        var answer = function(results) {
          body.search.results = results
          body.search.searchText = "SHOP"
          body.search.resultsQuery = "SHOP"
          body.search.answer = results.length ? "results" : "none"
        }
        var listsBefore = stub.lists
        stub.lists = [listsBefore[0], { name: "Growth", label: "Growth", count: 0, symbols: [] },
          { name: "Semiconductors & AI infrastructure", label: "Semiconductors & AI infrastructure", count: 0, symbols: [] }]
        // `enter`: the one marked as Enter's, or "" for none.
        var views = [
          { name: "search", scope: body.search, enter: "", open: function() { body.startAdding() }, close: function() { body.cancelAdding() } },
          { name: "search with results", scope: body.search, enter: "searchAdd", open: function() { body.startAdding(); answer(shopResults) }, close: function() { body.cancelAdding() } },
          { name: "search with none", scope: body.search, enter: "", open: function() { body.startAdding(); answer([]) }, close: function() { body.cancelAdding() } },
          // An earlier query's answer, dimmed: nothing in it can be taken.
          { name: "search with a stale answer", scope: body.search, enter: "",
            open: function() { body.startAdding(); answer(shopResults); body.search.searchText = "SHOPI" }, close: function() { body.cancelAdding() } },
          { name: "a symbol's lists", scope: find(body, "symbolLists"), enter: "", open: function() { body.openSymbolLists("MZ") }, close: function() { body.closeListViews() } },
          { name: "manage lists", scope: manage, enter: "renameAction", open: function() { body.openManageLists() }, close: function() { body.closeListViews() } },
          { name: "renaming a list", scope: manage, enter: "saveName", open: function() { body.openManageLists(); manage.startRenaming(2) }, close: function() { body.closeListViews() } },
          { name: "deleting a list", scope: manage, enter: "confirmDelete", open: function() { body.openManageLists(); manage.askDelete(2) }, close: function() { body.closeListViews() } },
          { name: "naming a list", scope: listMenu, enter: "makeList", open: function() { body.openListMenu(); listMenu.startNaming() }, close: function() { body.closeListMenu() } },
          { name: "the key sheet", scope: find(body, "helpSheet"), enter: "", open: function() { body.showingHelp = true }, close: function() { body.showingHelp = false } },
          { name: "a row's menu", scope: find(body, "rowMenu"), enter: "", open: function() { body.openRowMenu("MZ", null) }, close: function() { body.rowMenu = null } },
          { name: "a failed range", scope: headerItem, enter: "",
            open: function() { stub.range = "1W"; stub.historyEntry = { status: "failed", history: null, receivedAt: stub.now } },
            close: function() { stub.range = "1D"; stub.historyEntry = null } },
          { name: "a failed range under search", scope: headerItem, enter: "",
            open: function() { stub.range = "1W"; stub.historyEntry = { status: "failed", history: null, receivedAt: stub.now }; body.startAdding() },
            close: function() { body.cancelAdding(); stub.range = "1D"; stub.historyEntry = null } }
        ]
        var badKeys = []
        surface.windowWidth = Style.space(560)
        for (var hw = 0; hw < 2; hw++) {
          surface.wide = hw === 1
          for (var hl = 0; hl < 2; hl++) {
            stub.retro = hl === 1
            views.forEach(function(v) {
              v.open()
              wait(60)
              var place = (surface.wide ? "window " : "popup ") + (stub.retro ? "retro " : "smooth ") + v.name
              var seen = survey(v.scope)
              seen.keys.forEach(function(t) { badKeys.push(place + ": \"" + t.text + "\" names a key") })
              if (seen.marked.join(",") !== v.enter) badKeys.push(place + ": marked for Enter [" + seen.marked.join(",") + "], want [" + v.enter + "]")
              if (!seen.buttons.length && v.name !== "a row's menu") badKeys.push(place + ": no button")
              seen.buttons.forEach(function(t) {
                var words = "\"" + t.text + "\""
                // The whole text, not only its box: one that cannot fit fails
                // whether it is elided, wrapped, or left to spill.
                if (t.lineCount !== 1 || t.truncated || t.implicitWidth > t.width + 0.5 || xIn(t, 0) < 0 || xIn(t, t.width) > body.width)
                  badKeys.push(place + ": " + words + " " + t.lineCount + " lines" + (t.truncated ? ", elided" : "")
                    + ", " + Math.ceil(t.implicitWidth) + " px in " + xIn(t, 0) + "–" + xIn(t, t.width) + " of " + body.width)
                // Every button says its word one way: the caption, bold, in
                // spaced capitals.
                if (t.font.pixelSize !== Style.font.caption || !t.font.bold || t.font.letterSpacing !== 1 || t.text !== t.text.toUpperCase())
                  badKeys.push(place + ": " + words + " is not in the buttons' caption capitals (" + t.font.pixelSize + " px"
                    + (t.font.bold ? ", bold" : "") + ", spacing " + t.font.letterSpacing + ")")
              })
              v.close()
              wait(20)
            })
          }
        }
        surface.wide = false
        surface.windowWidth = 720
        stub.retro = false
        stub.lists = listsBefore
        wait(50)
        root.check("no word on screen names a key, Enter's button alone is marked, and every button is one whole line in the caption capitals, in both looks in the popup and the smallest window",
          badKeys.length === 0, badKeys.join(" | "))

        // A day with one bar or none says so where its chart would be, in
        // both looks on both surfaces: CKX's one bar at 14:10, CVR's none,
        // at 23:09 that Friday. A busy stock, an ETF, a coin, and listings
        // in London and Tokyo say nothing, nor does an index before its
        // bell, nor one 25 s past it: ^N225 as Yahoo answers 25 s into its
        // session, its first bar with no close yet, and the live moment.
        var quotesBeforeNotes = stub.quotes
        var opening = JSON.parse(indexDayFile.text())
        var openingDay = opening.chart.result[0]
        var bell = openingDay.meta.tradingPeriods.regular[0][0].start
        var bars = openingDay.indicators.quote[0]
        Object.keys(bars).forEach(function(key) { bars[key] = [null, bars[key][0]] })
        openingDay.timestamp = [bell, bell + 25]
        stub.quotes = Object.assign({}, quotesBeforeNotes, { CKX: Quote.parseChart(JSON.parse(ckxFile.text())),
          CVR: Quote.parseChart(JSON.parse(cvrFile.text())), "^GSPC": Quote.parseChart(JSON.parse(preOpenIndexFile.text())),
          "^N225": Quote.parseChart(opening) })
        var noteCases = [["CKX", 1792206540, "Traded only at 14:10"], ["CVR", 1792206540, "No trades charted"],
          ["AAPL", 1792206540, ""], ["SPY", 1792206540, ""], ["SHIB-USD", 1792206540, ""], ["SHEL.L", 1792206540, ""],
          ["7203.T", 1792206540, ""], ["^GSPC", 1790596800, ""], ["^N225", bell + 25, ""]]
        var noteFaults = []
        for (var nsurface = 0; nsurface < 2; nsurface++) {
          surface.wide = nsurface === 1
          for (var nl = 0; nl < 2; nl++) {
            stub.retro = nl === 1
            noteCases.forEach(function(c) {
              stub.now = c[1]
              stub.featuredSymbol = c[0]
              wait(50)
              var note = find(body, "dayNote")
              var said = note && note.visible ? note.text : ""
              var whole = !said || (xIn(note, 0) >= xIn(body.chartItem, 0) && xIn(note, note.width) <= xIn(body.chartItem, body.chartItem.width))
              if (said !== c[2] || !whole)
                noteFaults.push((surface.wide ? "window " : "popup ") + (stub.retro ? "retro " : "smooth ") + c[0] + ": \"" + said + "\""
                  + (whole ? "" : " outside the chart"))
            })
          }
        }
        // A row draws a one-bar day in both looks, as the hero does: smooth's
        // line as a dot, retro's as its column. A day with no bar leaves the
        // cell empty in both.
        var symbolsBeforeRows = stub.symbols
        var libraryBeforeRows = stub.library
        stub.symbols = symbolsBeforeRows.concat(["CKX", "CVR"])
        stub.library = stub.symbols
        stub.now = 1792206540
        surface.wide = false
        var rowInk = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          wait(50)
          ;["CKX", "CVR"].forEach(function(s) {
            var row = body.watchlist.rowItem(s)
            if (!row) { rowInk.push((retro ? "retro " : "smooth ") + s + " no row"); return }
            body.watchlist.contentY = Math.max(0, Math.min(row.y, body.watchlist.contentHeight - body.watchlist.height))
            wait(100)
            var inked = false
            if (retro) inked = find(row, "rowCells").drawable
            else {
              var canvas = find(row, "rowLine").children[0]
              var px = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data
              for (var p = 3; p < px.length && !inked; p += 4) inked = px[p] > 0
            }
            rowInk.push((retro ? "retro " : "smooth ") + s + " " + (inked ? "drawn" : "empty"))
          })
        })
        body.watchlist.contentY = 0
        stub.symbols = symbolsBeforeRows
        stub.library = libraryBeforeRows
        stub.quotes = quotesBeforeNotes
        stub.featuredSymbol = "AAPL"
        stub.now = 0
        surface.wide = false
        stub.retro = false
        wait(50)
        root.check("a day with one bar or none says so on its chart, and no fuller day or index before its bell does, in both looks on both surfaces",
          noteFaults.length === 0, noteFaults.join(" | "))
        root.check("a one-bar day's row draws its bar in both looks, and a day with none leaves the cell empty in both",
          rowInk.join(", ") === "smooth CKX drawn, smooth CVR empty, retro CKX drawn, retro CVR empty", rowInk.join(", "))
        // The popup shows a row on a short screen at a large text size: the
        // first-run hint gives way where it and a row don't both fit under
        // the rest. At text size 16, on screens from just room for the rest
        // and a row to just short of room for the hint too, in both looks.
        Style.fontBaseSize = 16
        wait(100)
        var bareChrome = body.chromeHeight
        body.showFirstRunHint()
        wait(50)
        var hintRoom = Math.ceil(find(find(body, "footer"), "footerHint").implicitHeight) + Style.space(6)
        var rowless = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          for (var room = bareChrome + body.listRowHeight; room < bareChrome + body.listRowHeight + hintRoom; room += 8) {
            body.screenRoom = room
            surface.budget = room
            wait(50)
            if (root.lastRowBottom() <= yIn(body.watchlist, 0)) rowless.push((retro ? "retro " : "smooth ") + room + " px")
          }
        })
        body.hint = ""
        body.screenRoom = 0
        surface.budget = 730
        stub.retro = false
        Style.fontBaseSize = 12
        wait(100)
        root.check("at text size 16, on a screen too short for the first-run hint and a row, the popup shows a row, in both looks",
          rowless.length === 0, rowless.join(", "))

      }

      function textSizes() {
        stub.now = 0
        // The popup shows three rows on a 768 px screen at every text size
        // Omarchy offers (`omarchy display text size`, 9 to 20), in both
        // looks: where the screen would hold fewer beside the chart, the
        // chart gives way to them, down to a fifth of itself; where it holds
        // three, the chart keeps its height. The body's room is what the
        // shell's card leaves it (Ui/PopupCard.qml): the screen less the
        // bar, the card's margins, padding, and border. The list menu and
        // search over three rows show more than one line.
        // On Bitcoin's 1Y, whose prices carry commas below the baseline, a
        // mark's words never touch the ink, the line's highest and lowest
        // close or the baseline past them, and a chart at its full height
        // shows both marks.
        var shortFaults = []
        var shortSeen = []
        var touched = []
        var coldFaults = []
        var tipFaults = []
        var tipsSeen = 0
        var coldSeen = 0
        var exact = function(item, y) { return item.mapToItem(body, 0, y).y }
        var quotesBeforeCoin = stub.quotes
        stub.quotes = Object.assign({}, quotesBeforeCoin, { "BTC-USD": Quote.parseChart(JSON.parse(btcFile.text())) })
        stub.featuredSymbol = "BTC-USD"
        stub.range = "1Y"
        var coinYear = { status: "ok", history: History.parseHistory(JSON.parse(btcYearFile.text()), "1Y"), receivedAt: stub.now }
        // The coin on its first day: one bar over a baseline below it, its
        // lone print a dot.
        var firstBar = coinYear.history.bars[coinYear.history.bars.length - 1]
        var coinDay = { status: "ok", receivedAt: stub.now, history: Object.assign({}, coinYear.history,
          { bars: [firstBar], baseline: firstBar.c * 0.9, firstTradeDate: firstBar.t }) }
        stub.historyEntry = coinYear
        // Where the ink reaches under a mark, between `x0` and `x1` on the
        // chart, as each look draws it: smooth's line through the closes
        // there and the nearest either side, a pixel either side of it, or
        // a lone close's dot of 3 px, inside its 3 px pad; retro's columns,
        // 6 px apart, each at its last close's row of 5 px; and the
        // baseline across the whole width.
        var inkReach = function(x0, x1) {
          var g = body.featuredGeometry
          var w = body.chartItem.width
          var h = body.chartItem.height
          var ys = [g.baselineY]
          if (!stub.retro) {
            var r = g.points.length === 1 ? 3 : 1
            var px = function(p) { return 3 + p.x * (w - 6) }
            var near = g.points.filter(function(p, i) {
              return px(g.points[Math.min(g.points.length - 1, i + 1)]) + r >= x0 && px(g.points[Math.max(0, i - 1)]) - r <= x1
            }).map(function(p) { return p.y })
            var at = function(y) { return 3 + y * (h - 6) }
            return [Math.min(at(g.baselineY) - 1, at(Math.min.apply(null, near.concat([1]))) - r),
              Math.max(at(g.baselineY) + 1, at(Math.max.apply(null, near.concat([0]))) + r)]
          }
          var rows = Math.floor(h / 5)
          var columns = Math.floor(w / 6)
          var last = {}
          g.points.forEach(function(p) { last[Math.min(columns - 1, Math.floor(p.x * columns))] = p.y })
          Object.keys(last).forEach(function(c) { if (c >= Math.floor(x0 / 6) && c <= Math.floor(x1 / 6)) ys.push(last[c]) })
          var levels = ys.map(function(y) { return Math.round(y * (rows - 1)) })
          return [Math.min.apply(null, levels) * 5, (Math.max.apply(null, levels) + 1) * 5]
        }
        // Each word of a mark that touches the ink under it: its ink's top
        // and bottom, and the ink's reach there.
        var touching = function(mark, high) {
          var out = []
          for (var k = 0; k < mark.children.length; k++) {
            var t = mark.children[k]
            if (String(t).indexOf("QQuickText(") !== 0) continue
            var ink = root.inkOf(t)
            var words = [exact(t, t.baselineOffset + ink.y), exact(t, t.baselineOffset + ink.y + ink.height)]
            var left = t.mapToItem(body.chartItem, 0, 0).x
            var reach = inkReach(left, left + t.width).map(function(y) { return exact(body.chartItem, y) })
            if (high ? words[1] > reach[0] : words[0] < reach[1])
              out.push("\"" + t.text + "\" at " + words.join("–") + " on ink at " + reach.join("–"))
          }
          return out.join(", ")
        }
        for (var size = 9; size <= 20; size++) {
          Style.fontBaseSize = size
          body.screenRoom = 0
          surface.budget = 4000
          wait(100)
          var room = 768 - Style.bar.sizeHorizontal - 2 * Style.gapsOut - 2 * Style.spacing.popupPadding - 2 * Math.max(1, Style.space(2))
          var fullChart = body.chartItem.height
          var rowsFitWhole = body.chromeHeight + body.threeRowsHeight <= room
          ;[false, true].forEach(function(retro) {
            stub.retro = retro
            body.screenRoom = room
            surface.budget = room
            wait(100)
            tryVerify(function() { return body.motion.drawn === 1 }, 2000)
            var where = "size " + size + (retro ? " retro" : " smooth")
            var chart = body.chartItem.height
            if (retro === false) shortSeen.push(size + ": " + chart + (chart === fullChart ? "" : " of " + fullChart) + " in " + room)
            // The card stops at the screen's room, the footer riding its
            // edge: rows are in view when they end one gap above the footer
            // there. Three, or as many as the list holds, unless the chart
            // has given all the way it may; one at the least.
            var footerTop = Math.min(surface.height, room) - find(body, "footer").height
            var inView = function(height) { return body.watchlist.height >= height && yIn(body.watchlist, height) + body.groupGap <= footerTop }
            if (!inView(body.listRowHeight))
              shortFaults.push(where + ": no row in " + room + " px, chart " + chart + ", list " + body.watchlist.height)
            else if (chart > body.leastScreenChart && !inView(body.wholeRowsHeight(body.threeRowsHeight)))
              shortFaults.push(where + ": fewer than three rows in " + room + " px, though the chart, " + chart + ", could give way")
            if (rowsFitWhole && chart !== fullChart) shortFaults.push(where + ": the chart gave way to " + chart + " though " + fullChart + " leaves three rows")
            ;[[coinYear, "1Y"], [coinDay, "first day"]].forEach(function(entry) {
              stub.historyEntry = entry[0]
              wait(50)
              ;[find(body, "highMark"), find(body, "lowMark")].forEach(function(mark, i) {
                var name = entry[1] + " " + (i === 0 ? "high" : "low")
                if (!mark || !mark.visible) {
                  if (chart === fullChart) touched.push(where + ": no " + name + " mark on a " + chart + " px chart")
                  return
                }
                var onInk = touching(mark, i === 0)
                if (onInk) touched.push(where + ": the " + name + " mark's " + onInk + ", chart " + chart)
              })
            })
            // Where the header gives its title way, the name is back on the
            // ticker's line, which is measured; with no quote yet, before a
            // first answer or after a failed one, it says nothing rather
            // than throw.
            if (!body.headerTitled) {
              var hero = find(body, "hero")
              hero.quote = null
              wait(50)
              if (hero.listingMeta !== "") coldFaults.push(where + ": \"" + hero.listingMeta + "\"")
              coldSeen++
              hero.quote = Qt.binding(function() { return body.featuredQuote })
              wait(50)
            }
            // The camera's tip once, at the largest size with the body at the
            // window's top: one tip, under its icon and within the body. A tip
            // always opens below its icon, so other sizes show nothing more.
            if (size === 20 && !retro) {
              var cameraButton = find(body, "cameraButton")
              mouseMove(cameraButton, cameraButton.width / 2, cameraButton.height / 2)
              within(1500, function() { return root.openTips(body, []).length > 0 })
              var tips = root.openTips(body, [])
              if (tips.length !== 1) tipFaults.push(where + ": " + tips.length + " tips")
              tips.forEach(function(t) {
                var fault = root.tipFault(t, cameraButton)
                if (fault) tipFaults.push(where + ": " + fault)
              })
              mouseMove(body, body.width / 2, body.height - 4)
              within(1000, function() { return root.openTips(body, []).length === 0 })
              tipsSeen++
            }
          })
        }
        // At text sizes 16 and 20 on an 850 px screen, with 12 lists, the
        // list menu and search show more than one line, the room of the
        // three rows the chart gives way to, all of it inside the popup, in
        // both looks: at 16, two lists above the menu's own two lines, and
        // four results; at 20, one list above them, and two results.
        var listsBefore = stub.lists
        stub.lists = [{ name: "", label: "All", count: stub.symbols.length, symbols: stub.symbols }].concat(
          Array.from({ length: 12 }, function(_, n) { return { name: "List " + (n + 1), label: "List " + (n + 1), count: 1, symbols: ["MZ"] } }))
        var viewFaults = []
        var viewSeen = []
        ;[[16, 2, 4], [20, 1, 2]].forEach(function(least) {
          var size = least[0]
          Style.fontBaseSize = size
          ;[false, true].forEach(function(retro) {
            stub.retro = retro
            var tall = 850 - Style.bar.sizeHorizontal - 2 * Style.gapsOut - 2 * Style.spacing.popupPadding - 2 * Math.max(1, Style.space(2))
            body.screenRoom = tall
            surface.budget = tall
            wait(100)
            var where = "size " + size + (retro ? " retro" : " smooth")
            body.openListMenu()
            wait(100)
            var menu = find(body, "listMenu")
            var menuEnd = yIn(menu, menu.height)
            var edge = Math.min(surface.height, tall)
            if (menu.rowsShown < least[1]) viewFaults.push(where + ": the list menu shows " + menu.rowsShown + " of 13 lists")
            if (menuEnd > edge) viewFaults.push(where + ": the list menu ends at " + menuEnd + ", past the popup's " + edge)
            body.closeListMenu()
            body.startAdding()
            wait(100)
            var results = Math.floor((body.search.resultsHeight + body.search.rowGap) / body.search.rowPitch)
            if (results < least[2]) viewFaults.push(where + ": search has room for " + results + " results")
            body.cancelAdding()
            wait(50)
            if (!retro) viewSeen.push(size + ": menu " + menu.rowsShown + " lists, search " + results + " results")
          })
        })
        stub.lists = listsBefore
        console.log("views on an 850 px screen: " + viewSeen.join(", "))
        root.check("at text sizes 16 and 20 on an 850 px screen, the list menu and search show more than one line, all inside the popup, in both looks",
          viewFaults.length === 0, viewFaults.join(" | "))
        body.screenRoom = 0
        surface.budget = 730
        stub.retro = false
        stub.featuredSymbol = "AAPL"
        stub.quotes = quotesBeforeCoin
        stub.range = "1D"
        stub.historyEntry = null
        Style.fontBaseSize = 12
        wait(100)
        console.log("popup charts on a 768 px screen: " + shortSeen.join(", "))
        root.check("on a 768 px screen at every text size from 9 to 20 the popup shows three rows, its chart giving way to them only where it must and as far as a fifth of itself, in both looks",
          shortFaults.length === 0, shortFaults.join(" | "))
        root.check("on a 768 px screen at every text size from 9 to 20 a range's marks never touch the ink, and a chart at full height shows both, in both looks",
          touched.length === 0, touched.join(" | "))
        root.check("on a 768 px screen where the header gives its title way, a stock with no quote yet leaves the ticker's line empty, in both looks",
          coldSeen > 0 && coldFaults.length === 0, coldSeen + " seen; " + coldFaults.join(" | "))
        root.check("at text size 20 on a 768 px screen, the camera's tip shows under its icon and within the body",
          tipsSeen > 0 && tipFaults.length === 0, tipsSeen + " seen; " + tipFaults.join(" | "))

        // After the text size changes with the list scrolled, no row is cut
        // at the list's top or bottom, the row at its top stays there unless
        // the list's end comes first, and the cursor's row stays whole in
        // sight: in the popup on an 850 px screen and the window at its
        // usual 720 × 760, two rows down at 12, to 16 and back; at the
        // list's end at 12, the cursor on its top row or its last, to 16;
        // and at its end at 16, to 12, with the surface open through the
        // change.
        var rowsList = body.watchlist
        // The popup's room on an 850 px screen at the text size of the
        // moment, as the shell's card gives it.
        var screenTall = function() {
          return 850 - Style.bar.sizeHorizontal - 2 * Style.gapsOut - 2 * Style.spacing.popupPadding - 2 * Math.max(1, Style.space(2))
        }
        // The rows any part of which shows, top to bottom, each whole or cut.
        var rowsInSight = function() {
          var top = rowsList.contentY
          var bottom = top + rowsList.height
          var out = []
          rowsList.displayedSymbols.forEach(function(symbol) {
            var row = rowsList.rowItem(symbol)
            if (row && row.y + row.height > top + 0.5 && row.y < bottom - 0.5)
              out.push({ symbol: symbol, whole: row.y >= top - 0.5 && row.y + row.height <= bottom + 0.5 })
          })
          return out
        }
        var lastSymbol = function() { return rowsList.displayedSymbols[rowsList.displayedSymbols.length - 1] }
        var rowsCut = []
        var rowsSeen = []
        ;[false, true].forEach(function(wide) {
          surface.wide = wide
          surface.windowWidth = 720
          // The window's height is its own, its chart giving way to three
          // rows (App.qml); the popup's is the card's room for the body.
          surface.fixedHeight = wide ? 760 : 0
          if (wide) {
            body.screenRoom = 0
            body.minChartHeight = Qt.binding(function() { return Style.space(136) })
          } else {
            body.screenRoom = Qt.binding(screenTall)
            surface.budget = Qt.binding(screenTall)
          }
          ;[{ from: 12, notches: 2, to: [16, 12] }, { from: 12, notches: 40, to: [16] }, { from: 12, notches: 40, last: true, to: [16] },
            { from: 16, notches: 40, to: [12] }].forEach(function(walk) {
            Style.fontBaseSize = walk.from
            rowsList.contentY = 0
            rowsList.cursorSymbol = ""
            wait(100)
            // Wheel notches down over the first row in sight, or the last,
            // which takes the cursor, then the pointer off the list.
            var pointerY = walk.last ? rowsList.height - 10 : 10
            mouseMove(rowsList, 12, pointerY)
            mouseWheel(rowsList, 12, pointerY, 0, -120 * walk.notches, Qt.NoModifier)
            tryVerify(function() { return !rowsList.settling }, 2000)
            mouseMove(body, body.width / 2, 10)
            var topRow = (rowsInSight()[0] || { symbol: "no row" }).symbol
            var cursor = rowsList.cursorSymbol
            var was = walk.from
            walk.to.forEach(function(size) {
              Style.fontBaseSize = size
              wait(100)
              var shown = rowsInSight()
              var said = (wide ? "window " : "popup ") + was + " to " + size + ": "
                + shown.map(function(r) { return r.symbol + (r.whole ? "" : " (cut)") }).join(" ")
              was = size
              rowsSeen.push(said)
              var atEnd = shown.length > 0 && shown[shown.length - 1].symbol === lastSymbol()
              if (shown.length === 0 || shown.some(function(r) { return !r.whole }) || (!atEnd && shown[0].symbol !== topRow)
                  || rowsList.cursorSymbol !== cursor || !shown.some(function(r) { return r.symbol === cursor }))
                rowsCut.push(said + ", " + topRow + " was at the top, the cursor on " + cursor + " and now on " + rowsList.cursorSymbol)
            })
          })
        })
        Style.fontBaseSize = 12
        body.screenRoom = 0
        body.minChartHeight = 0
        surface.budget = 730
        surface.wide = false
        surface.fixedHeight = 0
        rowsList.contentY = 0
        rowsList.cursorSymbol = ""
        wait(100)
        console.log("rows after a text size change: " + rowsSeen.join(" | "))
        root.check("after the text size changes with the list scrolled, no row is cut at the list's top or bottom, the row at its top stays there unless the list's end comes first, and the cursor's row stays in sight, in the popup and the window",
          rowsCut.length === 0, rowsCut.join(" | "))

        // A scrub whose line runs through a range's mark keeps the mark, all
        // of it clear of the line: over its own bar, its price, its date, and
        // either end; and the pointer leaving puts it back where it rests.
        // Both looks, both marks, on a year with a sharp high early, which
        // has no room before it, and a sharp low late, which has.
        var scrubNow = stub.quotes.AAPL.marketTime
        var sharp = []
        for (var sb = 0; sb < 40; sb++) {
          var sc = sb === 6 ? 130 : sb === 33 ? 70 : 100 + (sb % 3)
          sharp.push({ t: scrubNow - (39 - sb) * 86400, c: sc, h: sc + 0.5, l: sc - 0.5, o: sc, v: 100 })
        }
        stub.featuredSymbol = "AAPL"
        stub.figures = null
        stub.range = "1Y"
        stub.historyEntry = { status: "ok", receivedAt: scrubNow,
          history: { symbol: "AAPL", range: "1Y", baseline: 100, interval: "1d", gmtoffset: -14400, bars: sharp } }
        var crossed = []
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          wait(50)
          tryVerify(function() { return body.motion.drawn === 1 }, 2000)
          ;["highMark", "lowMark"].forEach(function(name) {
            var mark = find(body, name)
            var marks = mark.parent.parent
            var price = find(mark, "markPrice")
            var date = find(mark, "markDate")
            var place = function() { return [mark.visible, mark.x].join(",") }
            var atRest = place()
            var rest = mark.x
            var spots = { bar: marks.chart.xAt(mark.modelData.x), left: rest + 2, price: rest + price.x + price.width / 2,
              date: rest + date.x + date.width / 2, right: rest + mark.width - 2 }
            var faults = []
            for (var spot in spots) {
              var over = marks.mapToItem(body.chartItem, spots[spot], 0)
              mouseMove(body.chartItem, over.x, body.chartItem.height / 2)
              wait(50)
              var line = marks.scrubAt
              var clear = line < mark.x - 1 || line > mark.x + mark.width + 1
              if (!mark.visible || !clear || mark.x < 0 || mark.x + mark.width > marks.width)
                faults.push(spot + ": line " + Math.round(line) + ", mark " + mark.visible + " at " + Math.round(mark.x) + "–" + Math.round(mark.x + mark.width))
            }
            mouseMove(body.chartItem, 1, -Style.space(40))
            wait(50)
            var after = place()
            if (!atRest.startsWith("true") || faults.length || after !== atRest)
              crossed.push((retro ? "retro " : "smooth ") + name + ": at rest " + atRest + "; " + faults.join(", ") + "; after " + after)
          })
        })
        stub.retro = false
        stub.range = "1D"
        stub.historyEntry = null
        wait(50)
        root.check("a scrub through a range's mark, its own bar included, keeps all of it clear of the line, and the pointer leaving puts it back, both marks, both looks",
          crossed.length === 0, crossed.join(" | "))

        // On a side bar the stacked pill keeps a short line for a warning's
        // "!": a failed refresh fills it, and the pill keeps its height.
        stub.now = scrubNow + 120
        var stackSaid = function() {
          return find(sidePill, "pillStack").children.filter(function(c) { return c.objectName === "pillStackLine" })
            .map(function(line) { return line.text }).join("/") + " " + sidePill.implicitHeight + " px"
        }
        var stackFaults = []
        var entriesBeforeFail = stub.entries
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          stub.entries = entriesBeforeFail
          wait(20)
          var healthy = stackSaid()
          var healthyHeight = sidePill.implicitHeight
          stub.entries = Object.assign({}, entriesBeforeFail, { AAPL: Object.assign({}, entriesBeforeFail.AAPL, { status: "failed" }) })
          wait(20)
          var lines = find(sidePill, "pillStack").children.filter(function(c) { return c.objectName === "pillStackLine" })
          if (healthy.indexOf("!") >= 0 || !lines.some(function(line) { return line.text === "!" }) || sidePill.implicitHeight !== healthyHeight)
            stackFaults.push((retro ? "retro: " : "smooth: ") + healthy + " -> " + stackSaid())
        })
        stub.entries = entriesBeforeFail
        stub.retro = false
        stub.now = 0
        root.check("a failed refresh warns on the stacked form in both looks", stackFaults.length === 0, stackFaults.join(" | "))
      }
    }
  }
}
