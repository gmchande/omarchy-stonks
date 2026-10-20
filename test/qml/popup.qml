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
// without mapping: lifecycle, the draw-in, closing's hold, the height, the list
// views, and the pill wheel; and on the real Service and version watch, the
// first-run hint and the footer's notices.
ShellRoot {
  id: test
  property int failures: 0
  property int opensTold: 0
  property int refreshes: 0
  property int fundamentalsCalls: 0
  property var listHeights: []
  // Where the list stood when the popup closed mid-wheel.
  property real wheelHeldAt: -1
  property var heldQuote: null
  property real shortListRows: 0
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
      order: order, reversed: reversed, rows: symbols, shown: Settings.sortedSymbols(symbols, quotes, order, reversed),
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
  // A second real pill, on a stand-in for its bar window's content: an
  // unmapped window has no content item to place a card from. The shell's
  // placement runs whole on it, from the pill's spot there.
  Item {
    id: placedBar
    width: 1200
    height: Style.bar.sizeHorizontal
    Stonks.BarWidget {
      id: placedPill
      x: 400
      bar: api
      settings: ({ id: "grvc.stonks", barStyle: "text" })
    }
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
  // The hint's line ends above the footer's words.
  function hintAbove(panel) {
    var footer = test.find(panel.testBody, "footer")
    var line = test.find(footer, "footerHint")
    var words = test.find(footer, "footerText")
    return !!line && line.mapToItem(footer, 0, line.height).y <= words.mapToItem(footer, 0, 0).y
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
      var fullHeight = wl.height
      var shrunk = []
      var kept = []
      panel.testKeyCatcher.textKey("?")
      shrunk.push(wl.height)
      kept.push(wl.cursorRow)
      panel.testKeyCatcher.textKey("?")
      kept.push(wl.cursorRow)
      panel.testKeyCatcher.textKey("?")
      shrunk.push(wl.height)
      panel.testKeyCatcher.closeRequested()
      kept.push(wl.cursorRow)
      panel.testKeyCatcher.textKey("W")
      shrunk.push(wl.height)
      kept.push(wl.cursorRow)
      panel.testBody.closeListViews()
      kept.push(wl.cursorRow)
      test.check("in the popup, the key sheet and Manage lists leave the cursor where ↓ put it, though the card shrinks to the sheet",
        keyedRow !== service.featuredSymbol && shrunk[0] < fullHeight && shrunk[1] < fullHeight && shrunk[2] === fullHeight
          && kept.every(function(s) { return s === keyedRow }),
        keyedRow + " for featured " + service.featuredSymbol + " | heights " + fullHeight + " -> " + shrunk.join(",") + " | " + kept.join(","))
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
      // The card sits under its pill, whichever section of a top bar holds
      // it, whole and on screen. It used to sit at the bar's centre wherever
      // the pill was. The shell's own placement runs; the flow says where
      // the pill is on a bar as wide as the screen.
      var card = pill.panel.testCard
      var screenWidth = Quickshell.screens[0].width
      card.anchorWindow = { width: screenWidth, height: Style.bar.sizeHorizontal, screen: Quickshell.screens[0], contentItem: null }
      var placed = [8, (screenWidth - card.anchorW) / 2, screenWidth - card.anchorW - 8].map(function(x) {
        card.anchorScreenPos = Qt.point(x, 0)
        var origin = card.cardOrigin
        var middle = x + card.anchorW / 2
        var ok = origin.x <= middle && middle <= origin.x + card.contentWidth
          && origin.x >= 0 && origin.x + card.contentWidth <= screenWidth && origin.y > Style.bar.sizeHorizontal
        return { ok: ok, said: Math.round(middle) + " in " + origin.x + "+" + card.contentWidth + " at " + origin.y }
      })
      card.anchorWindow = null
      test.check("the popup sits under its pill in the left, centre, and right sections of the bar, whole and on screen",
        placed.every(function(p) { return p.ok }), placed.map(function(p) { return p.said }).join(" | "))
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

  // The draw-in, on the flows the owner actually uses. `reveal` has to leave 1
  // and come back to it; a trigger that never fires leaves it pinned at 1.
  // While the view's chart is on its way, the last one shows whole: `reveal`
  // holds at 1 the whole wait, and the new one draws in once it is in.
  property real lowestLoading: 1
  function waiting() {
    return panel.testBody.chartLoading && panel.testBody.motion.reveal === 1 && test.lowestLoading === 1
  }
  property real lowest: 1
  // The draw-in's length as its frames imply it: a frame part way in, at
  // `reveal` after t ms, says OutCubic's progress there, so t over that
  // progress is the length. A stalled frame shifts the reading only by how
  // late the handler runs, not by the stall. The frames as rendered are
  // window-motion.sh's (frames.js); the popup is never mapped.
  property real drawStart: 0
  property real drawLength: 0
  // Acts once part way through the next draw-in: `midDraw` is what to do,
  // on the frame where `reveal` passes 0.2.
  property var midDraw: null
  property real midAt: -1
  Connections {
    target: panel.testBody ? panel.testBody.motion : null
    function onRevealChanged() {
      var reveal = panel.testBody.motion.reveal
      if (reveal === 0) test.drawStart = Date.now()
      else if (reveal < 1 && test.drawStart > 0) test.drawLength = (Date.now() - test.drawStart) / (1 - Math.cbrt(1 - reveal))
      else if (reveal === 1) test.drawStart = 0
      if (test.midDraw && reveal > 0.2 && reveal < 0.9) {
        var act = test.midDraw
        test.midDraw = null
        test.midAt = reveal
        act()
      }
    }
  }
  // The card's heights as the Panel applies them, frame by frame.
  property var heights: []
  property bool drawKept: false
  property bool bodyAtOnce: false
  // The card's height with the rows, before a view opens; the key sheet's.
  property int rowsCard: 0
  property int sheetCard: 0

  function recordHeight() { test.heights.push(panel.testContentHeight) }
  // As the card's edge eases, frame by frame: while search is open, where
  // its field's bar stands; otherwise how far the footer ends from the
  // card's visible bottom.
  property var edgeGaps: []
  property var fieldFrames: []
  property var edgeFrames: null
  function recordEdge() {
    var body = panel.testBody
    var holder = panel.testKeyCatcher
    if (body.adding) {
      test.fieldFrames.push(Math.round(test.find(body.search, "searchField").parent.mapToItem(holder, 0, 0).y))
      return
    }
    var footer = test.find(body, "footer")
    test.edgeGaps.push(Math.round(holder.height - footer.mapToItem(holder, 0, footer.height).y))
  }
  // Where the list's first row stands in the card, shown or not.
  function rowsAt() { return Math.round(panel.testWatchlist.mapToItem(panel.testKeyCatcher, 0, 0).y) }
  // Search with the answer `results` (or "none") for `query` in its field:
  // where its field's bar stands, how far under it the answer starts, and
  // whether a result's label offers Enter.
  function answerSearch(query, results) {
    var search = panel.testBody.search
    var bar = test.find(search, "searchField").parent
    var message = test.find(search, "searchMessage")
    test.find(search, "searchField").text = query
    search.results = results
    search.resultsQuery = query
    search.answer = results.length ? "results" : "none"
    var first = results.length ? test.find(search, "searchResult") : message.visible ? message : null
    var under = first ? Math.round(first.mapToItem(bar, 0, 0).y - bar.height) : "-"
    var label = results.length ? test.find(first, "searchAdd") : null
    return [query, Math.round(bar.mapToItem(panel.testKeyCatcher, 0, 0).y), under,
      !!label && label.opacity === 1].join(" ")
  }

  // Eased to `target`: several heights on the way, every one closer.
  function eased(target) {
    var h = test.heights
    if (h.length < 5 || h[h.length - 1] !== target || h[0] === target) return false
    for (var i = 1; i < h.length; i++)
      if (Math.abs(target - h[i]) >= Math.abs(target - h[i - 1])) return false
    return true
  }

  // Types a query into search, opening it if it is shut, through an answer
  // and an edit that dims it, and closes it: whether the field stood where
  // the list's first row was throughout, and the card's height with the
  // answer in.
  function typeSearch() {
    var body = panel.testBody
    var field = test.find(body.search, "searchField")
    var barY = function() { return Math.round(field.parent.mapToItem(panel.testKeyCatcher, 0, 0).y) }
    if (!body.adding) body.startAdding()
    field.text = "TO"
    var barYs = [barY()]
    body.search.results = [
      { symbol: "TOPR", name: "Top Result Inc.", exchange: "NASDAQ" },
      { symbol: "SECR", name: "Second Result Inc.", exchange: "NYSE" }
    ]
    body.search.resultsQuery = "TO"
    body.search.answer = "results"
    var searchHeight = panel.testContentHeight
    barYs.push(barY())
    field.text = "TOP"
    barYs.push(barY())
    // A new query keeps the answer on screen, dimmed, until its own.
    var dimmed = body.search.stale && !panel.testWatchlist.visible
    var rows = test.rowsAt()
    body.cancelAdding()
    return { ok: dimmed && barYs.every(function(y) { return y === rows }),
      searchHeight: searchHeight, detail: "dimmed " + dimmed + " field " + barYs.join(",") + " first row at " + rows }
  }
  property int step: 0
  property string flow: ""

  function begin(label) {
    test.flow = label
    test.lowest = 1
    test.lowestLoading = 1
    test.drawLength = 0
  }

  // A draw-in from the left in 320 ms, as its last frame part way in
  // implies: a 160 or a 400 ms one reads outside the bounds.
  function drew(label, also) {
    test.check(label + " draws in over 320 ms",
      test.lowest < 0.5 && panel.testBody.motion.reveal === 1 && test.drawLength >= 270 && test.drawLength < 380
        && also !== false,
      test.lowest + "|" + Math.round(test.drawLength))
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
    var icon = test.find(body, "lookIcon")
    return [body.chartSymbol, body.chart ? body.chart.symbol : "none", body.featuredQuote ? body.featuredQuote.price : "none",
      body.watchlist.displayedSymbols.join(","), body.motion.reveal, body.headerText, body.showingHelp,
      panel.testContentHeight, icon.cells.toFixed(4)].join("|")
  }
  function closeHolding() {
    var body = panel.testBody
    var start = panel.testContentHeight
    var closeMid = function() {
      if (panel.testContentHeight === start) return
      panel.testContentHeightChanged.disconnect(closeMid)
      test.heldBefore = test.shownNow()
      panel.close()
      test.heldHero = service.featuredSymbol
      test.heldSymbols = service.symbols
      test.heldQuotes = service.quotes
      var other = service.symbols.filter(function(s) { return s !== test.heldHero })[0]
      var next = Object.assign({}, service.quotes)
      next[test.heldHero] = test.sampleQuote(test.heldHero, (body.featuredQuote ? body.featuredQuote.price : 100) + 5)
      service.quotes = next
      service.feature(other)
      service.symbols = service.symbols.filter(function(s) { return s !== test.heldHero })
      test.heldAtClose = test.shownNow()
    }
    panel.testContentHeightChanged.connect(closeMid)
    service.retro = !service.retro
    // The key sheet moves the card's edge; a view over the rows keeps it.
    body.showingHelp = true
  }
  function heldThroughFade() {
    var body = panel.testBody
    var throughFade = test.shownNow()
    var icon = test.find(body, "lookIcon")
    var moving = test.heldBefore.split("|")
    test.check("a closing popup holds its edge and look icon mid-motion, and its chart, figures, and rows through an answer, another surface's choice, and a removal from All, at the close and through the fade",
      test.heldBefore !== "" && Number(moving[8]) > 0 && Number(moving[8]) < 1
        && test.heldAtClose === test.heldBefore && throughFade === test.heldBefore,
      test.heldBefore + " -> " + test.heldAtClose + " -> " + throughFade)
    var other = service.featuredSymbol
    panel.open()
    test.check("the next open takes the latest, draws in, and settles the edge and the icon",
      body.chartSymbol === other && body.watchlist.displayedSymbols.indexOf(test.heldHero) < 0 && body.motion.reveal < 1
        && !body.showingHelp && panel.testContentHeight === Math.round(panel.fittedCardHeight)
        && icon.cells === (service.retro ? 0 : 1),
      body.chartSymbol + "|" + body.watchlist.displayedSymbols + "|" + body.motion.reveal + "|" + body.showingHelp
        + "|" + panel.testContentHeight + " vs " + panel.fittedCardHeight + "|" + icon.cells)
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
    id: sampler
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      var body = panel.testBody
      if (!body) return
      if (body.motion.reveal < test.lowest) test.lowest = body.motion.reveal
      if (body.chartLoading && body.motion.reveal < test.lowestLoading) test.lowestLoading = body.motion.reveal
    }
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
          test.begin("the day on open")
          panel.open()
        } else if (test.step === 2) {
          // Opening alone keeps the bar from revealing on hover, once the
          // open has settled; closing lets it go.
          test.check("hover suppressed", api.centerHoverRevealSuppressed)
          test.drew("the day on open")
          panel.close()
          test.check("hover released", !api.centerHoverRevealSuppressed)
          panel.testBody.selectRange("1W")
          service.histories = ({})
          test.begin("a range on open")
          panel.open()
        } else if (test.step === 3) {
          test.check("a range on open keeps the last chart whole while its response is out", test.waiting())
          service.histories = { "AAPL|1W": test.history("AAPL", "1W") }
        } else if (test.step === 4) {
          test.drew("a range on open, once its response lands")
          service.histories = {
            "AAPL|1W": test.history("AAPL", "1W"), "MSFT|1W": test.history("MSFT", "1W")
          }
          test.begin("a cached range on a symbol change")
          panel.testBody.featureAt(1)
        } else if (test.step === 5) {
          test.drew("a cached range on a symbol change", panel.featuredSymbol === "MSFT")
          service.histories = { "MSFT|1W": test.history("MSFT", "1W") }
          test.begin("an uncached range on a symbol change")
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
          test.drew("an uncached range on a symbol change, once its response lands")
          panel.testBody.selectRange("1D")
          test.begin("the day on a symbol change")
          panel.testBody.featureAt(1)
        } else if (test.step === 8) {
          test.drew("the day on a symbol change")
          var motion = panel.testBody.motion
          // To a range in hand the next chart draws in; to one on its way the
          // chart on show holds whole and still. Found in the design review:
          // the motion ran on under Loading.
          panel.testBody.featureAt(0)
          panel.testBody.selectRange("1W")
          var inHand = motion.reveal < 0.5
          panel.testBody.selectRange("1D")
          panel.testBody.featureAt(1)
          panel.testBody.selectRange("1M")
          var onItsWay = panel.testBody.chartLoading && motion.reveal === 1
          test.check("a range change mid draw-in: in hand it draws in, on its way it holds the chart whole and still",
            inHand && onItsWay, inHand + "|" + onItsWay)
          panel.testBody.selectRange("1D")
          // Closing mid-replay keeps the chart as far as the replay had drawn it.
          panel.testBody.replay()
          panel.close()
          test.check("closing mid-replay keeps what the replay had drawn",
            motion.replayRunning && motion.drawn < 1 && panel.testBody.scrubT !== 0,
            motion.replayRunning + "|" + motion.drawn + "|" + panel.testBody.scrubT)
          panel.open()
          test.check("the next open ends the replay", !motion.replayRunning && panel.testBody.scrubT === 0)
          // Closing mid-motion holds the picture; checked at the next step,
          // after the fade.
          test.closeHolding()
        } else if (test.step === 9) {
          test.heldThroughFade()
          // Closing mid draw-in keeps the chart as far as it had drawn for the
          // card's fade, and the next open draws in from the start.
          test.midDraw = function() { panel.close() }
          panel.testBody.featureAt(0)
        } else if (test.step === 10) {
          var motion = panel.testBody.motion
          var closedAt = test.midAt
          test.check("closing mid draw-in keeps the chart as far as it had drawn",
            !panel.opened && closedAt > 0 && motion.reveal === closedAt, closedAt + " -> " + motion.reveal)
          panel.open()
          test.check("the next open draws in from the start", motion.reveal < closedAt, motion.reveal)
          // An open while the popup is open changes nothing on screen: a
          // draw-in runs on here, and at the next step a chart at rest stays
          // whole. Found in the transition audit (lifecycle 11): the chart
          // blanked and drew in again.
          test.midDraw = function() {
            panel.open()
            test.drawKept = motion.reveal === test.midAt
          }
          panel.testBody.featureAt(1)
        } else if (test.step === 11) {
          test.setFixtureWatchlist()
        } else if (test.step === 12) {
          var restingBefore = panel.testBody.motion.reveal === 1 && !panel.testBody.chartLoading
          panel.open()
          test.check("an open while open changes nothing: a draw-in runs on, a chart at rest stays whole",
            test.drawKept && restingBefore && panel.testBody.motion.reveal === 1,
            test.drawKept + "|" + restingBefore + "|" + panel.testBody.motion.reveal)
          var list = panel.testWatchlist
          test.check("the 22-symbol fixture fills the popup with six whole rows",
            panel.testContentHeight === panel.heightCap && list.height === 6 * list.rowPitch - list.rowGap)
          test.check("the 22-symbol fixture keeps the list scrollable",
            list.interactive && list.contentHeight > list.height)
          // Wherever the list is scrolled to, the sixth row down ends inside it.
          var lastVisible = list.rowItem(list.displayedSymbols[Math.round(list.contentY / list.rowPitch) + 5])
          test.check("the capped panel's last visible row is whole",
            lastVisible && lastVisible.y + lastVisible.height <= list.contentY + list.height)
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
          var sheetSight = list.height
          service.setOrder("pct")
          var afterSortUnder = [list.cursorSymbol, list.cursorRow]
          service.setOrder("manual")
          panel.testKeyCatcher.textKey("?")
          test.check("in the popup, a sort under the key sheet that carries the cursor's row below the rows' view lets it go",
            carriedRow !== undefined && sheetSight < list.rowPitch && afterSortUnder[0] === "" && afterSortUnder[1] !== carriedRow,
            carriedRow + " | list under the sheet " + sheetSight + " | " + afterSortUnder.join(","))
          panel.testBody.featureSymbol("MZ")
          // The popup's own key route: W and m reach the list views through the
          // real catcher, which then stands aside so j, x, and esc reach the view.
          // Each keeps the card's height: it fits the rows' room.
          test.rowsCard = panel.testContentHeight
          panel.testKeyCatcher.textKey("W")
        } else if (test.step === 13) {
          test.check("W opens Manage lists in the popup, which takes the keys and keeps the card's height",
            panel.testBody.managingLists && panel.testKeyCatcher.blocked && panel.testContentHeight === test.rowsCard,
            panel.testContentHeight + " vs " + test.rowsCard)
          panel.close()
          test.check("closing keeps Manage lists for the fade", panel.testBody.managingLists)
          panel.open()
          test.check("the next open closes Manage lists and gives the keys back",
            !panel.testBody.managingLists && !panel.testKeyCatcher.blocked)
          test.rowsCard = panel.testContentHeight
          panel.testKeyCatcher.textKey("m")
        } else if (test.step === 14) {
          test.check("m opens the cursor row's lists in the popup, which takes the keys and keeps the card's height",
            panel.testBody.listsSymbol === "MZ" && panel.testKeyCatcher.blocked && panel.testContentHeight === test.rowsCard,
            panel.testBody.listsSymbol + "|" + panel.testKeyCatcher.blocked + "|" + panel.testContentHeight + " vs " + test.rowsCard)
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
          // A search on a full list keeps the popup's height, and its field
          // stays put while you type: over the rows before an answer, over
          // the results, and over the rows again when an edited query clears
          // them. Under six whole rows, the field and a full set of results
          // fit in the rows' place. Found in motion pass 3: the card's edge
          // and the field moved 2 px as results came and went, on every
          // search and query edit.
          var rowsHeight = panel.testContentHeight
          var typed = test.typeSearch()
          test.check("a search on a full list keeps the popup's height and its field where it is",
            typed.ok && typed.searchHeight === rowsHeight && panel.testContentHeight === rowsHeight,
            rowsHeight + " -> " + typed.searchHeight + " -> " + panel.testContentHeight + " " + typed.detail)
          // , and . fit each list: whole rows up to six, one for an empty
          // list, the card's edge easing there. Found in design pass 3: a
          // short list kept All's six rows, an empty one under its rows.
          test.heights = [panel.testContentHeight]
          panel.testContentHeightChanged.connect(test.recordHeight)
          panel.testKeyCatcher.textKey(".")
        } else if (test.step === 16) {
          var pitch = panel.testWatchlist.rowPitch
          test.check(". to a two-symbol list eases the card to its two rows",
            service.listName === "Short" && test.eased(panel.heightCap - 4 * pitch), test.heights.join(","))
          test.shortListRows = panel.testWatchlist.height
          test.heights = [panel.testContentHeight]
          panel.testKeyCatcher.textKey(".")
        } else if (test.step === 17) {
          test.check(". to an empty list eases the card to its one row",
            service.listName === "Empty" && test.eased(panel.heightCap - 5 * panel.testWatchlist.rowPitch),
            test.heights.join(","))
          // A search on a short list takes its height as it opens, the card
          // easing there, and then holds still while you type.
          test.heights = [panel.testContentHeight]
          panel.testBody.startAdding()
        } else if (test.step === 18) {
          var opened = test.eased(panel.testBody.searchHeight + panel.testInset)
          var typing = test.typeSearch()
          test.check("a search on a short list eases the card to its height and holds its field while you type",
            opened && typing.ok && typing.searchHeight === panel.testBody.searchHeight + panel.testInset, test.heights.join(",") + " " + typing.detail)
          test.heights = [panel.testContentHeight]
          panel.testKeyCatcher.textKey(",")
        } else if (test.step === 19) {
          test.check(", from an empty list's search to a two-symbol list eases the card to its two rows",
            service.listName === "Short" && test.eased(panel.heightCap - 4 * panel.testWatchlist.rowPitch),
            test.heights.join(","))
          panel.testContentHeightChanged.disconnect(test.recordHeight)
          test.check("the short list's rows stay its own, the footer one gap under them",
            test.shortListRows === 2 * panel.testWatchlist.rowPitch - panel.testWatchlist.rowGap
              && test.find(panel.testBody, "footer").y === panel.testWatchlist.y + test.shortListRows + panel.testBody.groupGap,
            test.shortListRows + " footer " + test.find(panel.testBody, "footer").y)
          panel.testKeyCatcher.textKey(",")
        } else if (test.step === 20) {
          // A view with its own height, here the key sheet, takes it with the
          // card's edge easing there, 160 ms OutCubic, while the body is laid
          // out at that height at once; closing it eases back. A view over the
          // rows keeps the card's height, but takes this path where a short
          // list's grows it. Found in motion pass 3: the card jumped in one
          // frame, about 365 px for the key sheet.
          test.heights = [panel.testContentHeight]
          panel.testContentHeightChanged.connect(test.recordHeight)
          panel.testKeyCatcher.textKey("?")
          test.bodyAtOnce = panel.testBody.showingHelp && panel.fittedCardHeight !== test.heights[0]
            && panel.testBody.height === panel.fittedCardHeight - panel.testInset
          test.sheetCard = panel.fittedCardHeight
        } else if (test.step === 21) {
          test.check("the key sheet eases the card to its height, with the body there at once",
            test.bodyAtOnce && test.eased(test.sheetCard), test.heights.join(","))
          test.heights = [panel.testContentHeight]
          panel.testKeyCatcher.textKey("?")
        } else if (test.step === 22) {
          test.check("closing the sheet eases the card back to the rows",
            !panel.testBody.showingHelp && test.eased(panel.heightCap), test.heights.join(","))
          panel.testContentHeightChanged.disconnect(test.recordHeight)
          // Closing stops the wheel where it is: its glide and its settle,
          // 260 ms after the last notch, would move the list after the close.
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
          test.lowestLoading = 1
          panel.open()
          test.check("an open before the first quote keeps the last chart whole",
            test.waiting() && panel.testBody.chartSymbol !== "MZ" && panel.testBody.headerText === "Loading MZ",
            panel.testBody.chartSymbol + "|" + panel.testBody.headerText)
          var withMZ = Object.assign({}, service.quotes)
          withMZ.MZ = test.heldQuote
          service.quotes = withMZ
          test.check("the first quote draws the day in",
            panel.testBody.motion.reveal === 0 && !panel.testBody.chartLoading && panel.testBody.chartSymbol === "MZ",
            panel.testBody.motion.reveal + "|" + panel.testBody.chartSymbol)
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
          // Search takes its height as it opens, the card's edge easing
          // there, while its field stands where the list's first row was on
          // every frame; it stays there through one answer, five, and none,
          // each starting the same gap under it, and the hint offers Enter
          // only with a result to take. Closing it, the footer rides the edge
          // back. Found in the transition audit (search 1, lists 14): the
          // field sat at the new bottom before the edge got there; and in the
          // first-run review: "No matches" sat about 260 px above the field,
          // the hint still offering add.
          test.heights = [panel.testContentHeight]
          test.edgeGaps = []
          test.fieldFrames = []
          panel.testContentHeightChanged.connect(test.recordHeight)
          test.edgeFrames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', test)
          test.edgeFrames.triggered.connect(test.recordEdge)
          panel.testBody.startAdding()
        } else if (test.step === 26) {
          var opened = test.heights.slice()
          var openFields = test.fieldFrames.slice()
          var rowsAt = test.rowsAt()
          var five = ["TOPR", "SECR", "THRD", "FRTH", "FIFT"].map(function(s) { return { symbol: s, name: s + " Inc.", exchange: "NYSE" } })
          var gap = panel.testBody.search.resultsGap
          var seen = [test.answerSearch("ONE", five.slice(0, 1)), test.answerSearch("FIVE", five), test.answerSearch("ZZZ", [])]
          var want = ["ONE " + rowsAt + " " + gap + " true", "FIVE " + rowsAt + " " + gap + " true", "ZZZ " + rowsAt + " " + gap + " false"]
          test.check("search takes its height as it opens, its field where the first row was on every frame and through one answer, five, and none",
            test.eased(panel.fittedCardHeight) && opened.length >= 5 && openFields.length >= 5
              && openFields.every(function(y) { return y === rowsAt }) && seen.join("|") === want.join("|"),
            opened.join(",") + " field " + openFields.join(",") + " first row at " + rowsAt + " | " + seen.join(" | ") + " — want " + want.join(" | "))
          test.heights = [panel.testContentHeight]
          test.edgeGaps = []
          panel.testBody.search.results = []
          panel.testBody.search.answer = ""
          test.find(panel.testBody.search, "searchField").text = ""
          panel.testBody.cancelAdding()
        } else if (test.step === 27) {
          var closedGaps = test.edgeGaps.slice()
          test.check("the footer rides the card's edge back as search closes",
            test.heights.length >= 5 && closedGaps.length >= 5 && closedGaps.every(function(g) { return g === closedGaps[0] }),
            test.heights.join(",") + " gaps " + closedGaps.join(","))
          panel.testContentHeightChanged.disconnect(test.recordHeight)
          test.edgeFrames.destroy()
          panel.close()
          // The first popup visit on a fresh install shows the hint, though
          // it opened before the service was ready, as a line of its own
          // above the footer, which still says "+ Add a symbol"; the next
          // open does not. It used to take the footer's place.
          var firstHint = test.hintLine(test.hintPanel)
          var firstFooter = test.footerText(test.hintPanel)
          var firstAbove = test.hintAbove(test.hintPanel)
          test.hintPanel.close()
          test.hintPanel.open()
          var secondHint = test.hintLine(test.hintPanel)
          test.hintPanel.close()
          test.check("the first popup visit shows the hint above \"+ Add a symbol\", opened before the service was ready, and the next does not",
            test.openedUnready && firstHint.indexOf(test.hintStart) === 0 && firstFooter === "+  Add a symbol" && firstAbove
              && secondHint === "",
            [test.openedUnready, firstHint, firstFooter, firstAbove, secondHint].join("|"))
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
          var whole = !test.find(footer, "footerText").truncated
          footer.clicked()
          test.check("a data file that can't be read is said whole in the footer on the next open, with its fix, and a click on it does nothing",
            heldClosed === test.closedFooter && said === test.fileNotice && whole && !footer.acts && !test.hintPanel.testBody.adding,
            [heldClosed, said, whole, footer.acts, test.hintPanel.testBody.adding].join("|"))
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
          var updateWhole = !test.find(test.find(test.hintPanel.testBody, "footer"), "footerText").truncated
          test.check("an update while the popup is closed is said whole in the footer on the next open",
            closedUpdate.indexOf("+  Add a symbol") === 0 && updateSaid === test.updateNotice && updateWhole,
            [closedUpdate, updateSaid, updateWhole].join("|"))
          test.writeFile(test.dataPath, "")
        } else if (test.step === 34) {
          if (test.hold(test.hintService.settingsUnreadable)) return
          var both = test.footerText(test.hintPanel)
          test.check("a file that can't be read is said over an update", both === test.fileNotice, both)
          test.writeFile(test.dataPath, test.goodData)
        } else if (test.step === 35) {
          if (test.hold(!test.hintService.settingsUnreadable)) return
          // A refusal over the update adds, as the footer does under a
          // refusal, and restarts nothing. A removal's offer takes the footer
          // for its moment, and its click undoes; then the update is said
          // again, and a click restarts.
          var body = test.hintPanel.testBody
          var updateFooter = test.find(body, "footer")
          test.restartsBefore = test.restartsAsked()
          body.say("Keep at least one symbol")
          var refusal = test.footerText(test.hintPanel)
          updateFooter.clicked()
          var refusalAdds = body.adding
          body.cancelAdding()
          var gone = test.hintService.library[0]
          body.removeRow(gone)
          var offer = test.footerText(test.hintPanel)
          updateFooter.clicked()
          var undone = test.hintService.library.indexOf(gone) >= 0
          var after = test.footerText(test.hintPanel)
          updateFooter.clicked()
          test.check("a refusal over the update opens search, and a removal's offer over it undoes",
            refusal === "Keep at least one symbol" && refusalAdds && offer.indexOf("Removed " + gone) === 0 && undone
              && after === test.updateNotice, [refusal, refusalAdds, offer, undone, after].join("|"))
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
          // Nothing pressed in the open popup moves it sideways: c into
          // "open", which widens the pill, and a narrower featured symbol
          // leave the card where it opened; the next open takes the pill's
          // new place. Seen live: the card moved about 15 px on c.
          var held = placedPill.panel
          var placed = held.testCard
          // The pill's own window is unmapped, so the bar window the held
          // anchor and the card read is the item the pill sits on, and its
          // row lays out on asking.
          var barWindow = { width: placedBar.width, height: Style.bar.sizeHorizontal, screen: Quickshell.screens[0], contentItem: placedBar }
          held.testHeldAnchor.barWindow = barWindow
          placed.anchorWindow = barWindow
          var pillRow = test.find(placedPill, "pillSymbol").parent
          var pillWidth = function() { pillRow.forceLayout(); return placedPill.width }
          service.quotes = Object.assign({}, service.quotes, { MZ: test.sampleQuote("MZ", 50) })
          service.changeMode = "pct"
          service.feature("AAPL")
          var before = pillWidth()
          held.open()
          var openedAt = placed.cardOrigin.x
          held.testKeyCatcher.textKey("c")
          held.testKeyCatcher.textKey("c")
          var mode = service.changeMode
          var widened = pillWidth()
          var afterOpenMode = placed.cardOrigin.x
          service.feature("MZ")
          var narrowed = pillWidth()
          var afterFeature = placed.cardOrigin.x
          held.close()
          held.open()
          var reopenedAt = placed.cardOrigin.x
          var expected = Math.round(placedPill.x + narrowed / 2 - placed.contentWidth / 2)
          held.close()
          service.changeMode = "pct"
          test.check("c into open and a narrower featured symbol leave the open card where it opened, and the next open takes the pill's new place",
            mode === "open" && widened > before && narrowed < widened
              && afterOpenMode === openedAt && afterFeature === openedAt && reopenedAt === expected && reopenedAt !== openedAt,
            [mode, "AAPL " + before + " → " + widened + ", MZ " + narrowed,
              "card x " + openedAt + " → " + afterOpenMode + " → " + afterFeature, "reopened " + reopenedAt + " (expected " + expected + ")"].join(", "))
          // A removal's undo outlives its note: u long after it, with the
          // footer back on the add, still takes it back.
          test.hintPanel.open()
          test.removedEarlier = test.hintService.library[0]
          test.hintPanel.testBody.removeRow(test.removedEarlier)
          test.noteSaid = test.footerText(test.hintPanel)
        } else if (test.step === 44) {
          var labelBack = test.footerText(test.hintPanel).indexOf("+  Add a symbol") === 0
          if (test.hold(labelBack)) return
          var gone = test.removedEarlier
          var goneMeanwhile = test.hintService.library.indexOf(gone) < 0
          test.hintPanel.testKeyCatcher.textKey("u")
          var back = test.hintService.library.indexOf(gone) >= 0
          test.check("u after the note has gone, the footer back on the add, still takes the removal back",
            test.noteSaid === "Removed " + gone && labelBack && goneMeanwhile && back,
            [test.noteSaid, labelBack, goneMeanwhile, back].join("|"))
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
