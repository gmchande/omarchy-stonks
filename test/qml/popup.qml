import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugin/Chart.js" as Chart
import "plugin/Quote.js" as Quote
import "plugin/Settings.js" as Settings
import "plugin" as Stonks

// The real Panel and a real pill on a stub service, under the Wayland session
// without mapping: lifecycle, list views, safe input and the pill wheel;
// and on the real Service and version watch, the
// first-run hint and the footer's notices.
ShellRoot {
  id: test
  property int failures: 0
  property int opensTold: 0
  property int refreshes: 0
  property int fundamentalsCalls: 0
  // Where the list stood when the popup closed mid-wheel.
  property real wheelHeldAt: -1
  property var heldQuote: null
  property bool savedHinted: false

  FileView {
    id: watchlistFixture
    path: Quickshell.env("STONKS_WATCHLIST_FIXTURE")
    blockLoading: true
  }

  QtObject {
    id: service
    property var symbols: ["AAPL", "MSFT"]
    property var library: symbols
    property string listName: ""
    property var lists: [{ name: "", label: "All", count: symbols.length, symbols: symbols }]
    property var quotes: ({})
    property var entries: ({})
    property var histories: ({})
    property var fundamentals: ({})
    property string featuredSymbol: "AAPL"
    property string order: "manual"
    property bool reversed: false
    property string range: "1D"
    property string changeMode: "pct"
    property bool retro: false
    property int now: 1788294000
    property var calendars: null
    property var owed: ({})
    property var arriving: []
    property var lastRemoval: null
    readonly property var view: ({ featured: featuredSymbol, range: range, list: listName, listKey: "=" + listName,
      order: order, reversed: reversed, rows: symbols, shown: Settings.sortedSymbols(symbols, quotes, order, reversed, changeMode),
      library: library, chart: Chart.viewChart(featuredSymbol, range, quotes, entries, histories) })
    function featureStep(delta) {
      var shown = view.shown
      if (shown.length === 0) return
      var at = shown.indexOf(featuredSymbol)
      feature(at < 0 ? shown[delta > 0 ? 0 : shown.length - 1] : shown[(at + delta + shown.length) % shown.length])
    }
    function refresh() { test.refreshes++ }
    function fetchFundamentals(symbol) { test.fundamentalsCalls++ }
    function persist(values) { if (values.changeMode !== undefined) changeMode = values.changeMode }
    function feature(symbol) { featuredSymbol = symbol }
    function setRange(value) { range = value }
    function screensClear() { return true }
    function surfaceShown(surface, open) { if (open) test.opensTold++ }
    function rowsSeen(surface, symbols) {}
    // A search's choice shown on the hero; this stub's hero never changes.
    readonly property var previewView: view
    readonly property var previewEntries: ({})
    property var previewSurface: null
    function preview(surface, symbol) {}
    function removeSymbol(symbol) {}
    function setManualOrder(next) { symbols = next.slice(); order = "manual" }
    function setOrder(value) { order = value }
    function switchList(name) {}
    // All, a two-symbol list, and an empty one, stepped the way , and . do.
    property var allSymbols: []
    property var namedLists: [{ name: "Short", symbols: ["MZ", "AAPL"] }, { name: "Empty", symbols: [] }]
    function stepList(delta) {
      var names = [""].concat(namedLists.map(function(l) { return l.name }))
      var next = names[(names.indexOf(listName) + delta + names.length) % names.length]
      symbols = next === "" ? allSymbols : namedLists.filter(function(l) { return l.name === next })[0].symbols
      listName = next
    }
    function createList(name) { return "" }
  }

  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service } }
  }
  PluginBarApi {
    id: api
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
    _setCenterHoverRevealSuppressed: function(value) { api._centerHoverRevealSuppressed = value }
  }
  Stonks.Panel {
    id: panel
    bar: api
    settings: ({ symbols: [] })
  }
  // A real pill whose own loader loads the copied Panel, never mapped, so
  // its wheel reaches Panel.featureNext as it does on the bar.
  Stonks.BarWidget {
    id: pill
    bar: api
    settings: ({ id: "grvc.stonks", barStyle: "sparkline" })
  }
  // The real data service and a popup on it, for what must outlive a
  // restart: the first-run hint. HOME is the harness's scratch one, with no
  // data file, as on a fresh install. The popup opens at once, while the
  // service still reads its settings, and stays open until the hint steps.
  // A restart makes both again.
  Component { id: hintServiceComponent; Stonks.Service {} }
  Component { id: hintPanelComponent; Stonks.Panel { bar: hintApi; settings: ({}) } }
  property var hintService: null
  property var hintPanel: null
  property bool openedUnready: false
  Component.onCompleted: {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', test)
    view.path = test.manifestPath
    originalManifest = String(view.text())
    view.destroy()
    hintService = hintServiceComponent.createObject(test)
    hintPanel = hintPanelComponent.createObject(test)
    openedUnready = !hintService.pluginsReady
    hintPanel.open()
  }
  property string removedEarlier: ""
  property string noteSaid: ""
  QtObject {
    id: hintShell
    function serviceFor() { return { service: test.hintService, updates: hintUpdates } }
  }
  // The real version watch, on the tree's copy of the manifest.
  Stonks.Updates { id: hintUpdates }
  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  readonly property string manifestPath: String(Qt.resolvedUrl("plugin/manifest.json")).replace(/^file:\/\//, "")
  property string goodData: ""
  property int held: 0
  property string closedFooter: ""
  property int restartsBefore: 0
  property string originalManifest: ""
  property string hintBehind: ""
  // A step whose condition has not come true yet runs again on the next
  // tick, for up to ten seconds; then it checks what it has.
  function hold(ok) {
    if (ok || test.held >= 20) {
      test.held = 0
      return false
    }
    test.held++
    test.step--
    return true
  }
  // writeFile PATH BODY: through a temporary file moved over it, as an
  // editor's atomic save does.
  Process { id: writer }
  function writeFile(path, body) {
    writer.running = false
    writer.command = ["bash", "-c", "printf '%s' \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"", "--", body, path]
    writer.running = true
  }
  function footerText(panel) {
    return String(test.find(test.find(panel.testBody, "footer"), "footerText").text)
  }
  readonly property string hintStart: "Drag the pill to move it along the bar"
  // The first visit's hint as its line above the footer shows it; "" with
  // none.
  function hintLine(panel) {
    var line = test.find(test.find(panel.testBody, "footer"), "footerHint")
    return line && line.visible ? String(line.text) : ""
  }
  function restartsAsked() {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', test)
    view.path = Quickshell.env("STONKS_FAKE_STATE") + "/omarchy.calls"
    var lines = String(view.text()).split("\n").filter(function(l) { return l === "restart shell" })
    view.destroy()
    return lines.length
  }
  readonly property string fileNotice: "Can't read grvc.stonks.json · fix or remove it to save changes"
  readonly property string updateNotice: "Updated to 9.9.9 · click to restart the shell"
  PluginBarApi {
    id: hintApi
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: hintShell
  }
  // The data file as written, read fresh: a FileView that has loaded once
  // can return its old text.
  function savedSettings() {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', test)
    view.path = Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
    var text = String(view.text())
    view.destroy()
    try { return JSON.parse(text) } catch (e) { return {} }
  }
  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
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

  function sampleQuote(symbol, price) {
    return {
      symbol: symbol, name: symbol, currency: "USD", exchange: "NASDAQ",
      timezoneName: "America/New_York", gmtoffset: -14400,
      instrumentType: "EQUITY", crypto: false,
      price: price, prevClose: price - 1, marketTime: service.now,
      dayHigh: price + 1, dayLow: price - 1, dayOpen: price - 1, volume: 100,
      session: {
        pre: { start: service.now - 25200, end: service.now - 19800 },
        regular: { start: service.now - 19800, end: service.now - 300 },
        post: { start: service.now - 300, end: service.now + 14100 }
      },
      points: [
        { t: service.now - 19800, p: price - 1 },
        { t: service.now - 300, p: price }
      ]
    }
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
    service.now = fixture.now
    service.order = "manual"
    service.symbols = nextSymbols
    service.quotes = nextQuotes
    service.entries = nextEntries
    service.featuredSymbol = "MZ"
  }
  Timer {
    interval: 100
    running: true
    onTriggered: {
      service.quotes = { AAPL: test.sampleQuote("AAPL", 100), MSFT: test.sampleQuote("MSFT", 200) }
      service.entries = { AAPL: { status: "ok", receivedAt: service.now }, MSFT: { status: "ok", receivedAt: service.now } }
      // A popup never opened has built no body: it is built as the popup
      // first opens, and kept.
      test.check("a popup never opened holds no body", panel.testBody === null, String(panel.testBody))
      panel.open()
      test.check("panel opens", panel.opened)
      panel.testBody.selectRange("1Y")
      test.check("range selection sets the service's range", service.range === "1Y")
      service.histories = { "AAPL|1Y": { status: "ok", history: {
        symbol: "AAPL", range: "1Y", interval: "1d", gmtoffset: 0,
        baseline: 10, firstTradeDate: 100,
        bars: [{ t: 100, c: 10 }, { t: 200, c: 11 }]
      } } }
      panel.testBody.motion.scrubT = 100
      service.histories = { "AAPL|1Y": { status: "ok", history: {
        symbol: "AAPL", range: "1Y", interval: "1d", gmtoffset: 0,
        baseline: 11, firstTradeDate: 300,
        bars: [{ t: 300, c: 11 }, { t: 400, c: 12 }]
      } } }
      test.check("refreshed history clears an out-of-range scrub", panel.testBody.scrubT === 0)
      panel.testBody.stepRange(1)
      test.check("popup range step follows range order", panel.range === "2Y")
      panel.refresh()
      test.check("r in the popup is a user's refresh", test.refreshes === 1, test.refreshes)
      // The key sheet closes before a view opens or a row key acts, as in the
      // window: one body rule, not each host's dispatcher.
      panel.testBody.showingHelp = true
      panel.testKeyCatcher.textKey("a")
      var searchAlone = !panel.testBody.showingHelp && panel.testBody.adding
      panel.testBody.cancelAdding()
      panel.testBody.showingHelp = true
      panel.testKeyCatcher.moveRequested(0, 1)
      test.check("in the popup, a over the key sheet opens search alone, and a row key shows the rows",
        searchAlone && !panel.testBody.showingHelp, searchAlone + "|" + panel.testBody.showingHelp)
      // ↓ put the cursor off the featured row; the key sheet, shown and
      // closed by ? and ? or by Escape, and Manage lists leave it there,
      // though the popup's card shrinks to the sheet and the list with it,
      // and a key pressed over them acts on it. Manage lists keeps the
      // card's height, the list's with it. Found in the live check of #19:
      // the shrunk list let the cursor go, and it came back on the featured
      // row, so x removed that one.
      var wl = panel.testBody.watchlist
      var keyedRow = wl.cursorRow
      var kept = []
      panel.testKeyCatcher.textKey("?")
      kept.push(wl.cursorRow)
      panel.testKeyCatcher.textKey("?")
      kept.push(wl.cursorRow)
      panel.testKeyCatcher.textKey("?")
      panel.testKeyCatcher.closeRequested()
      kept.push(wl.cursorRow)
      panel.testKeyCatcher.textKey("W")
      kept.push(wl.cursorRow)
      panel.testBody.closeListViews()
      kept.push(wl.cursorRow)
      test.check("in the popup, the key sheet and Manage lists leave the cursor where ↓ put it",
        keyedRow !== service.featuredSymbol && kept.every(function(s) { return s === keyedRow }),
        keyedRow + " for featured " + service.featuredSymbol + " | " + kept.join(","))
      panel.testBody.showingHelp = true
      panel.testBody.motion.scrubT = 123
      panel.close()
      test.check("panel closes", !panel.opened)
      // A closed popup's clock holds still: every tick re-derived its rows,
      // with nothing on screen. It catches up as it opens, below.
      var closedAt = panel.testBody.now
      service.now += 7
      test.check("a closed popup's clock holds still", panel.testBody.now === closedAt,
        closedAt + " -> " + panel.testBody.now)
      // Found live: closing swapped the key sheet for the whole popup, which
      // then faded out. The card fades out as it was; it is at rest when it
      // next opens.
      test.check("closing keeps the sheet and the scrub for the fade",
        panel.testBody.showingHelp && panel.testBody.scrubT === 123, panel.testBody.showingHelp + "|" + panel.testBody.scrubT)
      var beforeReopen = test.opensTold
      // The range is the service's: one picked in the window while the popup
      // is closed is the popup's on its next open.
      service.setRange("5Y")
      panel.open()
      test.check("interaction state cleared as it opens", !panel.testBody.showingHelp && panel.testBody.scrubT === 0)
      test.check("an open popup's clock is the service's", panel.testBody.now === service.now)
      test.check("the popup opens on the shared range", panel.range === "5Y")
      test.check("reopen tells the service the popup is open", test.opensTold > beforeReopen)
      panel.toggle()
      test.check("toggle closes reopened panel", !panel.opened)
      panel.open()
      panel.closeForPopoutSwitch()
      test.check("popout switch closes panel", !panel.opened)
      test.check("popup asks for a cap and P/E", test.fundamentalsCalls > 0)
      // The icon pill's hover says its symbol and change, and nothing while
      // its popup is open: the shell puts the bubble under the pill, where
      // it would cover the card's header. The owner's rule of 15 October.
      var formBefore = pill.settings
      pill.settings = Object.assign({}, formBefore, { barStyle: "icon" })
      var closedTip = pill.testButton.tooltipText
      pill.panel.open()
      var openTip = pill.testButton.tooltipText
      pill.panel.close()
      pill.settings = formBefore
      test.check("the icon pill's hover names its symbol, and says nothing while its popup is open",
        closedTip !== "" && openTip === "", JSON.stringify(closedTip) + " -> " + JSON.stringify(openTip))
      // Closing drops a search typed but not yet made; the next step reads it
      // after its debounce would have fired.
      panel.open()
      panel.testBody.adding = true
      test.find(panel.testBody.search, "searchField").text = "SH"
      panel.close()
      flows.running = true
    }
  }

  function waiting() {
    return panel.testBody.chartLoading && panel.testBody.chart !== null
  }

  // Search words and actions stay in this harness; placement is reviewed.
  function resultCount(search) {
    var rows = []
    var walk = function(item) {
      if (item.objectName === "searchResult" && rows.indexOf(item) < 0) rows.push(item)
      for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    walk(search)
    return rows.length
  }
  function answerSearch(query, results) {
    var search = panel.testBody.search
    test.find(search, "searchField").text = query
    search.results = results
    search.resultsQuery = query
    search.answer = results.length ? "results" : "none"
    return [test.find(search, "searchField").text, test.resultCount(search), search.resultIndex, test.find(search, "searchMessage").text].join("|")
  }
  function typeSearch() {
    var body = panel.testBody
    var field = test.find(body.search, "searchField")
    if (!body.adding) body.startAdding()
    field.text = "TO"
    body.search.results = [
      { symbol: "TOPR", name: "Top Result Inc.", exchange: "NASDAQ" },
      { symbol: "SECR", name: "Second Result Inc.", exchange: "NYSE" }
    ]
    body.search.resultsQuery = "TO"
    body.search.answer = "results"
    field.text = "TOP"
    var kept = body.search.stale && body.search.results.length === 2 && !panel.testWatchlist.visible
    body.cancelAdding()
    return kept && !body.adding
  }
  property int step: 0
  function shown(label, also) {
    var body = panel.testBody
    test.check(label + " shows the selected chart's data",
      !body.chartLoading && body.chartSymbol === service.featuredSymbol && body.chartRange === service.range && also !== false,
      body.chartSymbol + " " + body.chartRange + " vs " + service.featuredSymbol + " " + service.range)
  }

  // A closing popup holds its picture through the card's fade: the card's
  // edge stops where it was easing, the look icon where it was stepping, and
  // an answer that lands, a hero chosen on another surface, and a removal
  // from All change nothing of its chart, figures, or rows, at the close
  // and through the fade (the next step); the next open takes the latest.
  // Found in the motion audit (finding 3): the fading card changed chart,
  // and a removed row left a hole; and in its design review: the edge and
  // the icon went on. The frames as rendered are window-motion.sh's; the
  // popup is never mapped.
  property string heldBefore: ""
  property string heldAtClose: ""
  property string heldHero: ""
  property var heldSymbols: []
  property var heldQuotes: null
  function shownNow() {
    var body = panel.testBody
    return [body.chartSymbol, body.chart ? body.chart.symbol : "none", body.featuredQuote ? body.featuredQuote.price : "none",
      body.watchlist.displayedSymbols.join(","), body.headerText, body.showingHelp].join("|")
  }
  function closeHolding() {
    var body = panel.testBody
    body.showingHelp = true
    test.heldBefore = test.shownNow()
    panel.close()
    test.heldHero = service.featuredSymbol
    test.heldSymbols = service.symbols
    test.heldQuotes = service.quotes
    var other = service.symbols.filter(function(symbol) { return symbol !== test.heldHero })[0]
    var next = Object.assign({}, service.quotes)
    next[test.heldHero] = test.sampleQuote(test.heldHero, (body.featuredQuote ? body.featuredQuote.price : 100) + 5)
    service.quotes = next
    service.feature(other)
    service.symbols = service.symbols.filter(function(symbol) { return symbol !== test.heldHero })
    test.heldAtClose = test.shownNow()
    service.retro = !service.retro
  }
  function heldThroughFade() {
    var body = panel.testBody
    var throughFade = test.shownNow()
    test.check("a closed popup keeps its chart, figures and rows through an answer, another choice and a removal",
      test.heldBefore !== "" && test.heldAtClose === test.heldBefore && throughFade === test.heldBefore,
      test.heldBefore + " -> " + test.heldAtClose + " -> " + throughFade)
    var other = service.featuredSymbol
    panel.open()
    test.check("the next open takes the latest symbol and rows",
      body.chartSymbol === other && body.watchlist.displayedSymbols.indexOf(test.heldHero) < 0 && !body.showingHelp,
      body.chartSymbol + "|" + body.watchlist.displayedSymbols + "|" + body.showingHelp)
    service.retro = !service.retro
    service.symbols = test.heldSymbols
    service.quotes = test.heldQuotes
    service.feature(test.heldHero)
  }

  function history(symbol, range) {
    return { status: "ok", receivedAt: service.now, history: {
      symbol: symbol, range: range, interval: "1d", gmtoffset: 0,
      baseline: 10, firstTradeDate: 100,
      bars: [{ t: 100, c: 10 }, { t: 200, c: 11 }, { t: 300, c: 12 }]
    } }
  }

  Timer {
    id: flows
    interval: 500
    repeat: true
    onTriggered: {
      test.step++
      // A step that throws would skip its own checks and let the next step
      // run on; say so instead.
      try {
        if (test.step === 1) {
          test.check("closing drops a pending search and keeps the field",
            panel.testBody.search.activeQuery === "" && panel.testBody.adding
              && test.find(panel.testBody.search, "searchField").text === "SH")
          panel.close()
          panel.testBody.selectRange("1D")
          service.histories = ({})
          panel.testBody.featureAt(0)
          panel.open()
        } else if (test.step === 2) {
          // Opening alone keeps the bar from revealing on hover, once the
          // open has settled; closing lets it go.
          test.check("hover suppressed", api.centerHoverRevealSuppressed)
          test.shown("the day on open")
          panel.close()
          test.check("hover released", !api.centerHoverRevealSuppressed)
          panel.testBody.selectRange("1W")
          service.histories = ({})
          panel.open()
        } else if (test.step === 3) {
          test.check("a range on open keeps the last chart whole while its response is out", test.waiting())
          service.histories = { "AAPL|1W": test.history("AAPL", "1W") }
        } else if (test.step === 4) {
          test.shown("a range on open, once its response lands")
          service.histories = {
            "AAPL|1W": test.history("AAPL", "1W"), "MSFT|1W": test.history("MSFT", "1W")
          }
          panel.testBody.featureAt(1)
        } else if (test.step === 5) {
          test.shown("a cached range on a symbol change", panel.featuredSymbol === "MSFT")
          service.histories = { "MSFT|1W": test.history("MSFT", "1W") }
          panel.testBody.featureAt(0)
        } else if (test.step === 6) {
          // A symbol change on a range whose history is not in keeps the last
          // chart whole until it lands (the owner's rule: never a third state).
          test.check("an uncached range on a symbol change keeps the last chart until its response",
            test.waiting() && panel.testBody.chartSymbol === "MSFT" && panel.testBody.headerText === "Loading AAPL 1W",
            panel.testBody.chartSymbol + "|" + panel.testBody.motion.reveal + "|" + panel.testBody.headerText)
          service.histories = {
            "AAPL|1W": test.history("AAPL", "1W"), "MSFT|1W": test.history("MSFT", "1W")
          }
        } else if (test.step === 7) {
          test.shown("an uncached range on a symbol change, once its response lands")
          panel.testBody.selectRange("1D")
          panel.testBody.featureAt(1)
        } else if (test.step === 8) {
          test.shown("the day on a symbol change")
          panel.testBody.featureAt(0)
          panel.testBody.selectRange("1W")
          var inHand = !panel.testBody.chartLoading && panel.testBody.chartRange === "1W"
          panel.testBody.selectRange("1D")
          panel.testBody.featureAt(1)
          panel.testBody.selectRange("1M")
          var onItsWay = panel.testBody.chartLoading && !!panel.testBody.chart && panel.testBody.chartSymbol === "MSFT" && panel.testBody.chartRange === "1D"
          test.check("a cached range selects its data, an uncached range keeps the previous data while loading", inHand && onItsWay)
          panel.testBody.selectRange("1D")
          panel.testBody.replay()
          panel.close()
          test.check("closing a replay keeps its scrub until the next open", panel.testBody.scrubT !== 0)
          panel.open()
          test.check("the next open ends the replay", !panel.testBody.motion.replayRunning && panel.testBody.scrubT === 0)
          test.closeHolding()
        } else if (test.step === 9) {
          test.heldThroughFade()
          panel.testBody.featureAt(0)
          panel.close()
        } else if (test.step === 10) {
          test.check("a close after a symbol change closes the popup", !panel.opened)
          panel.open()
          test.check("reopening shows that symbol", panel.testBody.chartSymbol === service.featuredSymbol)
          panel.testBody.featureAt(1)
          panel.open()
        } else if (test.step === 11) {
          test.setFixtureWatchlist()
        } else if (test.step === 12) {
          var beforeOpen = panel.testBody.chartSymbol
          panel.open()
          test.check("opening an already open popup keeps its selected data", panel.testBody.chartSymbol === beforeOpen)
          var list = panel.testWatchlist
          test.check("the long fixture keeps all 22 symbols scrollable", list.displayedSymbols.length === 22 && list.interactive)
          // Under the key sheet, a sort that carries the cursor's row below
          // the rows' view lets the cursor go, though the card has shrunk to
          // the sheet: the rows' view is what counts. From Grok's review of
          // #24: the hidden rows kept the cursor, so x, Enter, or m acted on
          // a row out of sight.
          list.contentY = 0
          var inView = Math.floor((list.height + list.rowGap) / list.rowPitch)
          var sortedPct = Settings.sortedSymbols(service.symbols, service.quotes, "pct", false)
          var carriedRow = list.displayedSymbols.filter(function(s, i) {
            return i < inView - 1 && sortedPct.indexOf(s) > inView + 1
          })[0]
          list.select(carriedRow)
          panel.testKeyCatcher.textKey("?")
          service.setOrder("pct")
          var afterSortUnder = [list.cursorSymbol, list.cursorRow]
          service.setOrder("manual")
          panel.testKeyCatcher.textKey("?")
          test.check("in the popup, a sort under the key sheet that carries the cursor's row below the rows' view lets it go",
            carriedRow !== undefined && afterSortUnder[0] === "" && afterSortUnder[1] !== carriedRow,
            carriedRow + " | " + afterSortUnder.join(","))
          panel.testBody.featureSymbol("MZ")
          // The popup's own key route: W and m reach the list views through the
          // real catcher, which then stands aside so j, x, and esc reach the view.
          // Each keeps the card's height: it fits the rows' room.
          panel.testKeyCatcher.textKey("W")
        } else if (test.step === 13) {
          test.check("W opens Manage lists in the popup, which takes the keys",
            panel.testBody.managingLists && panel.testKeyCatcher.blocked,
            panel.testKeyCatcher.blocked)
          panel.close()
          test.check("closing keeps Manage lists for the fade", panel.testBody.managingLists)
          panel.open()
          test.check("the next open closes Manage lists and gives the keys back",
            !panel.testBody.managingLists && !panel.testKeyCatcher.blocked)
          panel.testKeyCatcher.textKey("m")
        } else if (test.step === 14) {
          test.check("m opens the cursor row's lists in the popup, which takes the keys",
            panel.testBody.listsSymbol === "MZ" && panel.testKeyCatcher.blocked,
            panel.testBody.listsSymbol + "|" + panel.testKeyCatcher.blocked + "|" + panel.testKeyCatcher.blocked)
          panel.testBody.closeListViews()
          // A high-resolution wheel sends a notch as small ticks: the pill
          // carries three quarters without a step, and the fourth moves the
          // featured symbol one row down.
          for (var tick = 0; tick < 3; tick++) pill.testButton.wheelMoved(-30)
          test.check("three quarter-notch ticks on the pill carry without a step", service.featuredSymbol === "MZ")
          pill.testButton.wheelMoved(-30)
          test.check("the fourth completes one notch and moves one row",
            service.featuredSymbol === service.symbols[service.symbols.indexOf("MZ") + 1])
          // All is the 22-symbol library from here on, whatever list shows.
          service.allSymbols = service.symbols.slice()
          service.library = service.allSymbols
        } else if (test.step === 15) {
          test.check("editing a search keeps its stale results and cancel returns the rows", test.typeSearch())
          panel.testKeyCatcher.textKey(".")
        } else if (test.step === 16) {
          test.check(". switches to the two-symbol list", service.listName === "Short" && service.symbols.length === 2)
          panel.testKeyCatcher.textKey(".")
        } else if (test.step === 17) {
          test.check(". switches to the empty list", service.listName === "Empty" && service.symbols.length === 0)
          panel.testBody.startAdding()
        } else if (test.step === 18) {
          test.check("search on an empty list keeps its results and cancel acts", test.typeSearch())
          panel.testKeyCatcher.textKey(",")
        } else if (test.step === 19) {
          test.check(", returns to the two-symbol list with its own rows", service.listName === "Short" && panel.testWatchlist.displayedSymbols.length === 2)
          panel.testKeyCatcher.textKey(",")
        } else if (test.step === 20) {
          panel.testKeyCatcher.textKey("?")
        } else if (test.step === 21) {
          test.check("? opens the sheet", panel.testBody.showingHelp)
          panel.testKeyCatcher.textKey("?")
        } else if (test.step === 22) {
          test.check("? returns to the rows", !panel.testBody.showingHelp)
          var wheeled = panel.testWatchlist
          wheeled.contentY = 0
          wheeled.wheelBy(1)
          panel.close()
          test.wheelHeldAt = wheeled.contentY
        } else if (test.step === 23) {
          test.check("closing stops the wheel's glide and settle where they are",
            service.listName === "" && panel.testWatchlist.contentY === test.wheelHeldAt,
            test.wheelHeldAt + " -> " + panel.testWatchlist.contentY)
          // An open before the featured symbol's first quote keeps the last
          // chart whole under "Loading MZ", then draws the day in: it used to
          // draw in an empty chart.
          test.heldQuote = service.quotes.MZ
          var withoutMZ = Object.assign({}, service.quotes)
          delete withoutMZ.MZ
          service.quotes = withoutMZ
          service.featuredSymbol = "MZ"
          panel.open()
          test.check("an open before the first quote keeps the last chart whole",
            test.waiting() && panel.testBody.chartSymbol !== "MZ" && panel.testBody.headerText === "Loading MZ",
            panel.testBody.chartSymbol + "|" + panel.testBody.headerText)
          var withMZ = Object.assign({}, service.quotes)
          withMZ.MZ = test.heldQuote
          service.quotes = withMZ
          test.check("the first quote replaces Loading with its own day",
            !panel.testBody.chartLoading && panel.testBody.chartSymbol === "MZ",
            panel.testBody.headerText + "|" + panel.testBody.chartSymbol)
          panel.testBody.selectRange("1D")
        } else if (test.step === 24) {
          // All short again, two rows, so search is taller than the rows.
          service.symbols = ["AAPL", "MSFT"]
          service.allSymbols = service.symbols.slice()
          service.library = service.allSymbols
          service.quotes = { AAPL: test.sampleQuote("AAPL", 100), MSFT: test.sampleQuote("MSFT", 200) }
          service.entries = { AAPL: { status: "ok", receivedAt: service.now }, MSFT: { status: "ok", receivedAt: service.now } }
          service.featuredSymbol = "AAPL"
        } else if (test.step === 25) {
          panel.testBody.startAdding()
        } else if (test.step === 26) {
          var five = ["TOPR", "SECR", "THRD", "FRTH", "FIFT"].map(function(symbol) { return { symbol: symbol, name: symbol + " Inc.", exchange: "NYSE" } })
          var seen = [test.answerSearch("ONE", five.slice(0, 1)), test.answerSearch("FIVE", five), test.answerSearch("ZZZ", [])]
          test.check("search answers keep their query, result counts and empty-answer words",
            seen[0].indexOf("ONE|1|0|") === 0 && seen[1].indexOf("FIVE|5|0|") === 0 && seen[2] === "ZZZ|0|0|No matches for “ZZZ”", seen.join(" / "))
          panel.testBody.search.results = []
          panel.testBody.search.answer = ""
          test.find(panel.testBody.search, "searchField").text = ""
          panel.testBody.cancelAdding()
        } else if (test.step === 27) {
          test.check("cancelled search returns the footer's add action", !panel.testBody.adding)
          panel.close()
          // The first popup visit on a fresh install shows the hint, though
          // it opened before the service was ready, as a line of its own
          // above the footer, which still says "+ Add a symbol"; the next
          // open does not. It used to take the footer's place.
          var firstHint = test.hintLine(test.hintPanel)
          var firstFooter = test.footerText(test.hintPanel)
          test.hintPanel.close()
          test.hintPanel.open()
          var secondHint = test.hintLine(test.hintPanel)
          test.hintPanel.close()
          test.check("the first popup visit shows the hint beside the add action, opened before the service was ready, and the next does not",
            test.openedUnready && firstHint.indexOf(test.hintStart) === 0 && firstFooter === "+  Add a symbol"
              && secondHint === "",
            [test.openedUnready, firstHint, firstFooter, secondHint].join("|"))
        } else if (test.step === 28) {
          // A restart, of the service and the popup, reads that it has shown
          // from the data file: the first open after it shows no hint.
          test.savedHinted = test.savedSettings().hinted === true
          test.hintPanel.destroy()
          test.hintService.destroy()
          test.hintService = hintServiceComponent.createObject(test)
          test.hintPanel = hintPanelComponent.createObject(test)
        } else if (test.step === 29) {
          var restarted = test.hintService.pluginsReady
          test.hintPanel.open()
          var afterRestart = test.hintPanel.testBody.hint
          test.hintPanel.close()
          test.check("after a restart the popup shows no hint: the data file says it has shown",
            test.savedHinted && restarted && afterRestart === "", test.savedHinted + "|" + restarted + "|" + afterRestart)
          // A file that has not shown it, opened with the service ready: the
          // open itself shows it.
          test.hintService.persist({ hinted: false })
          test.hintPanel.open()
          var onReadyOpen = test.hintPanel.testBody.hint
          test.hintPanel.close()
          test.check("an open with the service ready shows the hint when the file has not",
            onReadyOpen.indexOf(test.hintStart) === 0 && test.hintService.hinted, onReadyOpen)
          test.hintPanel.close()
        } else if (test.step === 30) {
          // The data file goes bad by hand while the popup is closed.
          test.goodData = JSON.stringify(test.savedSettings(), null, 2) + "\n"
          test.closedFooter = test.footerText(test.hintPanel)
          test.writeFile(test.dataPath, "{\n  \"symbols\": [\"AAPL\",\n")
        } else if (test.step === 31) {
          if (test.hold(test.hintService.settingsUnreadable)) return
          var heldClosed = test.footerText(test.hintPanel)
          test.hintPanel.open()
          var said = test.footerText(test.hintPanel)
          var footer = test.find(test.hintPanel.testBody, "footer")
          // Said whole in the popup's width, the fix included. Found in the
          // design pass of 14 October: it named the problem and not the fix.
          footer.clicked()
          test.check("a data file that can't be read is said in the footer on the next open, with its fix, and a click on it does nothing",
            heldClosed === test.closedFooter && said === test.fileNotice && !footer.acts && !test.hintPanel.testBody.adding,
            [heldClosed, said, footer.acts, test.hintPanel.testBody.adding].join("|"))
          test.writeFile(test.dataPath, test.goodData)
        } else if (test.step === 32) {
          if (test.hold(!test.hintService.settingsUnreadable)) return
          var label = test.footerText(test.hintPanel)
          test.check("fixed, the footer is the add again", label.indexOf("+  Add a symbol") === 0, label)
          test.hintPanel.close()
          test.writeFile(test.manifestPath, JSON.stringify({ schemaVersion: 1, id: "grvc.stonks", name: "Stonks",
            version: "9.9.9", author: "Gaurav Chande", kinds: ["service", "bar-widget"],
            entryPoints: { service: "Plugin.qml", barWidget: "BarWidget.qml" } }, null, 2) + "\n")
        } else if (test.step === 33) {
          if (test.hold(!writer.running)) return
          var closedUpdate = test.footerText(test.hintPanel)
          test.hintPanel.open()
          var updateSaid = test.footerText(test.hintPanel)
          test.check("an update while the popup is closed is said in the footer on the next open",
            closedUpdate.indexOf("+  Add a symbol") === 0 && updateSaid === test.updateNotice,
            [closedUpdate, updateSaid].join("|"))
          test.writeFile(test.dataPath, "")
        } else if (test.step === 34) {
          if (test.hold(test.hintService.settingsUnreadable)) return
          var both = test.footerText(test.hintPanel)
          test.check("a file that can't be read is said over an update", both === test.fileNotice, both)
          test.writeFile(test.dataPath, test.goodData)
        } else if (test.step === 35) {
          if (test.hold(!test.hintService.settingsUnreadable)) return
          // A refusal over the update adds, as the footer does under a
          // refusal, and restarts nothing. A removal says nothing over it:
          // the update is said still, and a click restarts.
          var body = test.hintPanel.testBody
          var updateFooter = test.find(body, "footer")
          test.restartsBefore = test.restartsAsked()
          body.say("Keep at least one symbol")
          var refusal = test.footerText(test.hintPanel)
          updateFooter.clicked()
          var refusalAdds = body.adding
          body.cancelAdding()
          // The refusal's moment over.
          body.clearNote()
          var gone = test.hintService.library[0]
          body.removeRow(gone)
          var removed = test.hintService.library.indexOf(gone) < 0
          var after = test.footerText(test.hintPanel)
          updateFooter.clicked()
          test.check("a refusal over the update opens search, and a removal leaves the update said",
            refusal === "Keep at least one symbol" && refusalAdds && removed && after === test.updateNotice,
            [refusal, refusalAdds, removed, after].join("|"))
        } else if (test.step === 36) {
          var asked = test.restartsAsked() - test.restartsBefore
          if (test.hold(asked === 1)) return
          var stays = test.footerText(test.hintPanel)
          test.hintPanel.close()
          test.check("a click on the update restarts the shell, and a refused restart leaves the notice",
            asked === 1 && stays === test.updateNotice, asked + "|" + stays)
          // The first-run hint is recorded only on a visit it is the line
          // shown: one whose footer has a notice ahead of it records
          // nothing, and the next visit without one shows and records it.
          test.hintService.persist({ hinted: false })
        } else if (test.step === 37) {
          if (test.hold(test.savedSettings().hinted === false)) return
          test.hintPanel.open()
          test.hintBehind = test.footerText(test.hintPanel)
          test.hintPanel.close()
          test.writeFile(test.manifestPath, test.originalManifest)
        } else if (test.step === 38) {
          if (test.hold(!writer.running)) return
          var savedBehindUpdate = test.savedSettings().hinted
          test.hintPanel.open()
          var hintAfterUpdate = test.hintLine(test.hintPanel)
          test.hintPanel.close()
          test.check("a first open behind the update notice records no hint, and the next open shows and records it",
            test.hintBehind === test.updateNotice && savedBehindUpdate === false
              && hintAfterUpdate.indexOf(test.hintStart) === 0 && test.hintService.hinted,
            [test.hintBehind, savedBehindUpdate, hintAfterUpdate, test.hintService.hinted].join("|"))
          test.hintService.persist({ hinted: false })
        } else if (test.step === 39) {
          if (test.hold(test.savedSettings().hinted === false)) return
          test.goodData = JSON.stringify(test.savedSettings(), null, 2) + "\n"
          test.writeFile(test.dataPath, "{\n")
        } else if (test.step === 40) {
          if (test.hold(test.hintService.settingsUnreadable)) return
          test.hintPanel.open()
          test.hintBehind = test.footerText(test.hintPanel) + "|" + test.hintService.hinted
          test.hintPanel.close()
          test.writeFile(test.dataPath, test.goodData)
        } else if (test.step === 41) {
          if (test.hold(!test.hintService.settingsUnreadable)) return
          var behindFile = test.hintService.hinted
          test.hintPanel.open()
          var hintAfterFile = test.hintLine(test.hintPanel)
          test.hintPanel.close()
          test.check("a first open behind the file notice records no hint, and the next open shows and records it",
            test.hintBehind === test.fileNotice + "|false" && behindFile === false
              && hintAfterFile.indexOf(test.hintStart) === 0 && test.hintService.hinted,
            [test.hintBehind, behindFile, hintAfterFile, test.hintService.hinted].join("|"))
        } else if (test.step === 42) {
          if (test.hold(test.savedSettings().hinted === true)) return
          test.check("and the hint shown is saved", test.savedSettings().hinted === true)
        } else if (test.step === 43) {
          service.quotes = Object.assign({}, service.quotes, { MZ: test.sampleQuote("MZ", 50) })
          service.changeMode = "pct"
          service.feature("AAPL")
          panel.open()
          panel.testKeyCatcher.textKey("c")
          panel.testKeyCatcher.textKey("c")
          var mode = service.changeMode
          service.feature("MZ")
          panel.close()
          panel.open()
          test.check("c changes the mode and a reopened popup shows the newly selected symbol", mode === "open" && panel.testBody.chartSymbol === "MZ")
          panel.close()
          service.changeMode = "pct"
          // A removal leaves the footer on the add, and u takes it back
          // later, after other looking around.
          test.hintPanel.open()
          test.removedEarlier = test.hintService.library[0]
          test.hintPanel.testBody.removeRow(test.removedEarlier)
          test.noteSaid = test.footerText(test.hintPanel)
        } else if (test.step === 44) {
          var gone = test.removedEarlier
          var goneMeanwhile = test.hintService.library.indexOf(gone) < 0
          test.hintPanel.testKeyCatcher.textKey("u")
          var back = test.hintService.library.indexOf(gone) >= 0
          test.check("after a removal the footer is the add, and u later takes the removal back",
            test.noteSaid.indexOf("+  Add a symbol") === 0 && goneMeanwhile && back,
            [test.noteSaid, goneMeanwhile, back].join("|"))
          // Until the next change to the lists: a new list ends the offer,
          // and u says there is nothing to undo.
          test.hintPanel.testBody.removeRow(gone)
          test.hintService.createList("Undo ends")
          test.hintPanel.testKeyCatcher.textKey("u")
          var said = test.footerText(test.hintPanel)
          var stillGone = test.hintService.library.indexOf(gone) < 0
          test.hintService.deleteList("Undo ends")
          test.check("after the next change to the lists u puts nothing back, and the footer says why",
            stillGone && said === "Nothing to undo", stillGone + "|" + said)
          // A change in the data file is a change too, when it changes what
          // the lists hold; one that changes only the view keeps the offer.
          test.removedEarlier = test.hintService.library[0]
          test.hintPanel.testBody.removeRow(test.removedEarlier)
          test.writeFile(test.dataPath, JSON.stringify(Object.assign({}, test.hintService.dataSettings, { range: "1Y" })))
        } else if (test.step === 45) {
          if (test.hold(test.hintService.range === "1Y")) return
          test.hintPanel.testKeyCatcher.textKey("u")
          var backAfterView = test.hintService.library.indexOf(test.removedEarlier) >= 0
          test.check("a data file that changes only the view keeps the undo",
            test.hintService.range === "1Y" && backAfterView, test.hintService.range + "|" + backAfterView)
          test.hintPanel.testBody.removeRow(test.removedEarlier)
          var lists = test.hintService.dataSettings.lists.concat([{ name: "Made elsewhere", symbols: [] }])
          test.writeFile(test.dataPath, JSON.stringify(Object.assign({}, test.hintService.dataSettings, { lists: lists })))
        } else if (test.step === 46) {
          var madeElsewhere = test.hintService.lists.some(function(l) { return l.name === "Made elsewhere" })
          if (test.hold(madeElsewhere)) return
          test.hintPanel.testKeyCatcher.textKey("u")
          var saidAfterFile = test.footerText(test.hintPanel)
          var goneAfterFile = test.hintService.library.indexOf(test.removedEarlier) < 0
          test.hintPanel.close()
          test.check("a list made in the data file ends the undo, as a list made here does",
            madeElsewhere && goneAfterFile && saidAfterFile === "Nothing to undo", [madeElsewhere, goneAfterFile, saidAfterFile].join("|"))
          // A popup closed as an outside click closes it (the shell's
          // KeyboardPanel calls close()) keeps a rename being typed, and a
          // new list's name, as a click away does. Found in Codex's review
          // of #30: the close lost the typing.
          var body = test.hintPanel.testBody
          var names = function() { return test.hintService.lists.map(function(l) { return l.name }) }
          test.hintPanel.open()
          body.openManageLists()
          var manage = test.find(body, "manageLists")
          manage.startRenaming(names().indexOf("Made elsewhere"))
          test.find(manage, "renameField").text = "Made here"
          test.hintPanel.close()
          var renamedOnClose = names().indexOf("Made here") > 0 && names().indexOf("Made elsewhere") < 0
          test.hintPanel.open()
          body.openListMenu()
          var menu = test.find(body, "listMenu")
          menu.startNaming()
          test.find(menu, "listNameField").text = "Made on close"
          test.hintPanel.close()
          var madeOnClose = names().indexOf("Made on close") > 0 && test.hintService.listName === "Made on close"
          test.check("closing the popup keeps a rename being typed and makes a new list being named",
            renamedOnClose && madeOnClose, names().join(",") + "|" + test.hintService.listName)
          console.log("POPUP DONE")
          exitTimer.exitCode = test.failures ? 1 : 0
          exitTimer.start()
        }
      } catch (e) {
        test.check("flow step " + test.step + " ran to its end: " + e, false)
      }
    }
  }

  HarnessExit { id: exitTimer }
}
