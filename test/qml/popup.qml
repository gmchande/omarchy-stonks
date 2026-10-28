import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugin/Chart.js" as Chart
import "plugin/Quote.js" as Quote
import "plugin/Settings.js" as Settings
import "plugin" as Stonks

// The real Panel and a real pill on a stub service, offscreen, its card in a
// plain window (CardWindow.qml) and pressed with real Qt keys: the card
// shrinking to the key sheet, its key route through the shell's catcher,
// what an open tells the service and the bar, and the pill's wheel and
// tooltip. On the real Service and version watch, the first-run hint, the
// footer's notices, the undo, and search's field keeping the keys.
Harness {
  id: harness
  marker: "POPUP DONE"

  property int opensTold: 0
  property int fundamentalsCalls: 0

  QtObject {
    id: service
    property var symbols: ["AAPL", "MSFT"]
    property var library: symbols
    property string listName: ""
    // All and two named lists, as the list menu shows them.
    property var namedLists: [{ name: "Short", symbols: ["MZ", "AAPL"] }, { name: "Empty", symbols: [] }]
    property var lists: [{ name: "", label: "All", count: library.length, symbols: library }].concat(namedLists.map(function(l) {
      return { name: l.name, label: l.name, count: l.symbols.length, symbols: l.symbols }
    }))
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
    function refresh() {}
    function fetchFundamentals(symbol) { harness.fundamentalsCalls++ }
    function persist(values) { if (values.changeMode !== undefined) changeMode = values.changeMode }
    function feature(symbol) { featuredSymbol = symbol }
    function setRange(value) { range = value }
    function screensClear() { return true }
    function surfaceShown(surface, open) { if (open) harness.opensTold++ }
    function rowsSeen(surface, symbols) {}
    // A search's choice shown on the hero; this stub's hero never changes.
    readonly property var previewView: view
    readonly property var previewEntries: ({})
    property var previewSurface: null
    function preview(surface, symbol) {}
    function removeSymbol(symbol) { symbols = symbols.filter(function(s) { return s !== symbol }) }
    function setManualOrder(next) { symbols = next.slice(); order = "manual" }
    function setOrder(value) { order = value }
    function switchList(name) { listName = name }
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

  // The real data service and a popup on it. HOME is the harness's scratch
  // one, with no data file, as on a fresh install. The popup opens at once,
  // while the service still reads its settings. A restart makes both again.
  Component { id: hintServiceComponent; Stonks.Service {} }
  Component { id: hintPanelComponent; Stonks.Panel { bar: hintApi; settings: ({}) } }
  property var hintService: null
  property var hintPanel: null
  property bool openedUnready: false
  property string originalManifest: ""
  Component.onCompleted: {
    originalManifest = readFile(manifestPath)
    hintService = hintServiceComponent.createObject(harness)
    hintPanel = hintPanelComponent.createObject(harness)
    openedUnready = !hintService.pluginsReady
    hintPanel.open()
  }
  QtObject {
    id: hintShell
    function serviceFor() { return { service: harness.hintService, updates: hintUpdates } }
  }
  // The real version watch, on the tree's copy of the manifest.
  Stonks.Updates { id: hintUpdates }
  PluginBarApi {
    id: hintApi
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: hintShell
  }
  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  readonly property string manifestPath: String(Qt.resolvedUrl("plugin/manifest.json")).replace(/^file:\/\//, "")
  readonly property string hintStart: "Drag the pill to move it along the bar"
  readonly property string fileNotice: "Couldn't load your lists"
  readonly property string updateNotice: "Updated to 9.9.9 · click to restart the shell"

  // Through a temporary file moved over it, as an editor's atomic save does.
  Process { id: writer }
  function writeFile(path, body) {
    writer.running = false
    writer.command = ["bash", "-c", "printf '%s' \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"", "--", body, path]
    writer.running = true
  }
  function savedSettings() {
    try { return JSON.parse(readFile(dataPath)) } catch (e) { return {} }
  }
  function restartsAsked() {
    return readFile(Quickshell.env("STONKS_FAKE_STATE") + "/omarchy.calls").split("\n")
      .filter(function(l) { return l === "restart shell" }).length
  }
  function footerText(popup) {
    return String(find(find(popup.testBody, "footer"), "footerText").text)
  }
  // The first visit's hint as its line above the footer shows it; "" with
  // none.
  function hintLine(popup) {
    var line = find(find(popup.testBody, "footer"), "footerHint")
    return line && line.visible ? String(line.text) : ""
  }

  // Real keys into a popup's card: the key tester sits in that card, so its
  // keys go to the card's window. It never runs as a test itself.
  TestCase {
    id: keys
    name: "PopupKeys"
    when: false
  }
  function press(popup, key, modifiers) {
    keys.parent = popup.testKeyCatcher
    keys.keyClick(key, modifiers === undefined ? Qt.NoModifier : modifiers)
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
  // The 22 saved quotes, manual order, MZ on show.
  function setFixtureWatchlist() {
    var fixture = JSON.parse(readFile(Quickshell.env("STONKS_WATCHLIST_FIXTURE")))
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

  // A symbol whose quote failed too says "No data", as a failed symbol is
  // said anywhere: its range has no chart without a quote.
  function failedRangeSaid(quoteFailed) {
    var body = panel.testBody
    var symbol = service.featuredSymbol
    var was = { quotes: service.quotes, entries: service.entries, histories: service.histories }
    var quotes = Object.assign({}, was.quotes)
    var entries = Object.assign({}, was.entries)
    if (quoteFailed) {
      delete quotes[symbol]
      entries[symbol] = { status: "failed", receivedAt: 0 }
    }
    var histories = {}
    histories[symbol + "|1W"] = { status: "failed", history: null, receivedAt: service.now }
    service.quotes = quotes
    service.entries = entries
    service.histories = histories
    body.selectRange("1W")
    var said = body.headerText + " | " + body.offersRetry
    body.selectRange("1D")
    service.quotes = was.quotes
    service.entries = was.entries
    service.histories = was.histories
    return said
  }

  Steps {
    name: "Popup"
    when: harness.hintPanel !== null

    // The popup takes its keys a turn after it opens or a view closes.
    function focusKeys(popup) {
      within(1000, function() { return popup.testBodyKeys.activeFocus })
    }

    function test_flows() {
      service.quotes = { AAPL: harness.sampleQuote("AAPL", 100), MSFT: harness.sampleQuote("MSFT", 200) }
      service.entries = { AAPL: { status: "ok", receivedAt: service.now }, MSFT: { status: "ok", receivedAt: service.now } }
      panel.open()
      var body = panel.testBody

      // The key sheet closes before a view opens or a row key acts.
      body.showingHelp = true
      focusKeys(panel)
      harness.press(panel, "a")
      var searchAlone = !body.showingHelp && body.adding
      body.cancelAdding()
      body.showingHelp = true
      focusKeys(panel)
      harness.press(panel, Qt.Key_Down)
      harness.check("in the popup, a over the key sheet opens search alone, and ↓ shows the rows",
        searchAlone && !body.showingHelp, searchAlone + "|" + body.showingHelp)

      // The card shrinks to the key sheet, the list with it; Manage lists
      // keeps the card's height. A key pressed over them acts on the cursor.
      var wl = body.watchlist
      var keyedRow = wl.cursorRow
      var kept = []
      harness.press(panel, "?")
      kept.push(wl.cursorRow)
      harness.press(panel, "?")
      kept.push(wl.cursorRow)
      harness.press(panel, "?")
      harness.press(panel, Qt.Key_Escape)
      kept.push(wl.cursorRow)
      body.openManageLists()
      kept.push(wl.cursorRow)
      body.closeListViews()
      kept.push(wl.cursorRow)
      harness.check("in the popup, the key sheet and Manage lists leave the cursor where ↓ put it",
        keyedRow !== service.featuredSymbol && kept.every(function(s) { return s === keyedRow }),
        keyedRow + " for featured " + service.featuredSymbol + " | " + kept.join(","))

      // A closed popup re-derives nothing every second; it catches up as it
      // opens.
      panel.close()
      var closedAt = body.now
      service.now += 7
      harness.check("a closed popup's clock holds still", body.now === closedAt, closedAt + " -> " + body.now)
      var opensBefore = harness.opensTold
      var asksBefore = harness.fundamentalsCalls
      panel.open()
      harness.check("an open popup's clock is the service's", body.now === service.now)
      harness.check("reopen tells the service the popup is open", harness.opensTold > opensBefore)
      harness.check("popup asks for a cap and P/E", harness.fundamentalsCalls > asksBefore)

      // The shell puts the pill's bubble under the pill, where it would
      // cover the card's header.
      var formBefore = pill.settings
      pill.settings = Object.assign({}, formBefore, { barStyle: "icon" })
      within(2000, function() { return !!pill.panel })
      var closedTip = pill.testButton.tooltipText
      pill.panel.open()
      var openTip = pill.testButton.tooltipText
      pill.panel.close()
      pill.settings = formBefore
      harness.check("the icon pill's hover names its symbol, and says nothing while its popup is open",
        closedTip !== "" && openTip === "", JSON.stringify(closedTip) + " -> " + JSON.stringify(openTip))

      panel.close()
      panel.open()
      harness.check("hover suppressed", within(1000, function() { return api.centerHoverRevealSuppressed }))
      var said = [harness.failedRangeSaid(false), harness.failedRangeSaid(true)].join(" / ")
      harness.check("a failed range says it is unavailable, with its retry, and with the quote failed too says No data, as the window does",
        said === "1W unavailable | true / No data | false", said)
      panel.close()
      harness.check("hover released", !api.centerHoverRevealSuppressed)

      panel.open()
      body.replay()
      var replaying = within(1000, function() { return body.motion.replayRunning })
      body.showingHelp = true
      panel.close()
      panel.open()
      harness.check("the next open ends the replay",
        replaying && !body.motion.replayRunning && body.scrubT === 0 && !body.showingHelp,
        [replaying, body.motion.replayRunning, body.scrubT, body.showingHelp].join("|"))

      // Under the key sheet the rows' view is what counts, though the card
      // has shrunk to the sheet: a cursor whose row leaves it, by a removal
      // of a row above it on the view's top row or by a sort that carries it
      // below, is let go, so Delete or Enter never acts out of sight.
      harness.setFixtureWatchlist()
      var list = panel.testWatchlist
      within(2000, function() { return list.displayedSymbols.length === 22 && list.interactive })
      list.contentY = 3 * list.rowPitch
      var topRow = list.displayedSymbols[3]
      list.select(topRow)
      focusKeys(panel)
      harness.press(panel, "?")
      var sheetForRemoval = body.showingHelp
      service.removeSymbol(list.displayedSymbols[1])
      var removalLetGo = within(1000, function() { return list.cursorSymbol === "" && list.cursorRow !== topRow })
      var afterRemoval = [list.cursorSymbol, list.cursorRow]
      harness.press(panel, "?")
      harness.setFixtureWatchlist()
      within(2000, function() { return list.displayedSymbols.length === 22 })
      list.contentY = 0
      var inView = Math.floor((list.height + list.rowGap) / list.rowPitch)
      var sortedPct = Settings.sortedSymbols(service.symbols, service.quotes, "pct", false)
      var carriedRow = list.displayedSymbols.filter(function(s, i) {
        return i < inView - 1 && sortedPct.indexOf(s) > inView + 1
      })[0]
      list.select(carriedRow)
      focusKeys(panel)
      harness.press(panel, "?")
      var underSheet = sheetForRemoval && body.showingHelp
      service.setOrder("pct")
      var sortLetGo = within(1000, function() { return list.cursorSymbol === "" && list.cursorRow !== carriedRow })
      var afterSort = [list.cursorSymbol, list.cursorRow]
      service.setOrder("manual")
      harness.press(panel, "?")
      harness.check("in the popup, a sort under the key sheet that carries the cursor's row below the rows' view lets it go",
        underSheet && removalLetGo && carriedRow !== undefined && sortLetGo,
        [underSheet, topRow + " -> " + afterRemoval.join(","), carriedRow + " -> " + afterSort.join(",")].join(" | "))

      // The popup's own key route: each view takes the keys, the shell's
      // catcher standing aside.
      body.featureSymbol("MZ")
      focusKeys(panel)
      harness.press(panel, "w")
      var menu = null
      harness.check("w opens the list menu in the popup, which takes the keys",
        within(1000, function() {
          menu = harness.find(body, "listMenu")
          return body.listMenuOpen && !!menu && menu.activeFocus && panel.testKeyCatcher.blocked
        }),
        body.listMenuOpen + "|" + (menu && menu.activeFocus) + "|" + panel.testKeyCatcher.blocked)
      for (var row = 0; row < menu.manageIndex; row++) harness.press(panel, Qt.Key_Down)
      harness.press(panel, Qt.Key_Return)
      harness.check("the list menu's Manage lists…, taken with ↓ and Enter, opens Manage lists, which takes the keys",
        within(1000, function() { return body.managingLists && !body.listMenuOpen && panel.testKeyCatcher.blocked }),
        body.managingLists + "|" + body.listMenuOpen + "|" + panel.testKeyCatcher.blocked)
      panel.close()
      panel.open()
      harness.check("the next open closes Manage lists and gives the keys back",
        within(1000, function() { return !body.managingLists && !panel.testKeyCatcher.blocked }))

      // A high-resolution wheel sends a notch as small ticks.
      for (var tick = 0; tick < 3; tick++) pill.testButton.wheelMoved(-30)
      harness.check("three quarter-notch ticks on the pill carry without a step", service.featuredSymbol === "MZ")
      pill.testButton.wheelMoved(-30)
      harness.check("the fourth completes one notch and moves one row",
        service.featuredSymbol === service.symbols[service.symbols.indexOf("MZ") + 1])
      panel.close()

      hintFlows()
      harness.finish()
    }

    // On the real service: the hint, the notices, the undo, search's keys.
    function hintFlows() {
      var popup = harness.hintPanel
      // The hint is a line of its own above the footer, which still offers
      // the add.
      within(10000, function() { return harness.hintLine(popup) !== "" })
      var firstHint = harness.hintLine(popup)
      var firstFooter = harness.footerText(popup)
      popup.close()
      popup.open()
      var secondHint = harness.hintLine(popup)
      popup.close()
      harness.check("the first popup visit shows the hint beside the add action, opened before the service was ready, and the next does not",
        harness.openedUnready && firstHint.indexOf(harness.hintStart) === 0 && firstFooter === "+  Add a symbol"
          && secondHint === "",
        [harness.openedUnready, firstHint, firstFooter, secondHint].join("|"))

      var savedHinted = within(3000, function() { return harness.savedSettings().hinted === true })
      popup.destroy()
      harness.hintService.destroy()
      harness.hintService = hintServiceComponent.createObject(harness)
      harness.hintPanel = popup = hintPanelComponent.createObject(harness)
      var restarted = within(10000, function() { return harness.hintService.pluginsReady })
      popup.open()
      var afterRestart = popup.testBody.hint
      popup.close()
      harness.check("after a restart the popup shows no hint: the data file says it has shown",
        savedHinted && restarted && afterRestart === "", savedHinted + "|" + restarted + "|" + afterRestart)

      harness.hintService.persist({ hinted: false })
      popup.open()
      var onReadyOpen = popup.testBody.hint
      popup.close()
      harness.check("an open with the service ready shows the hint when the file has not",
        onReadyOpen.indexOf(harness.hintStart) === 0 && harness.hintService.hinted, onReadyOpen)

      within(3000, function() { return harness.savedSettings().hinted === true })
      var goodData = JSON.stringify(harness.savedSettings(), null, 2) + "\n"
      harness.writeFile(harness.manifestPath, JSON.stringify({ schemaVersion: 1, id: "grvc.stonks", name: "Stonks",
        version: "9.9.9", author: "Gaurav Chande", kinds: ["service", "bar-widget"],
        entryPoints: { service: "Plugin.qml", barWidget: "BarWidget.qml" } }, null, 2) + "\n")
      within(3000, function() { return !writer.running })
      popup.open()
      var updateFirst = within(2000, function() { return harness.footerText(popup) === harness.updateNotice })
      harness.writeFile(harness.dataPath, "")
      within(5000, function() { return harness.hintService.settingsUnreadable })
      var both = harness.footerText(popup)
      harness.check("a file that can't be read is said over an update", updateFirst && both === harness.fileNotice,
        updateFirst + "|" + both)
      harness.writeFile(harness.dataPath, goodData)
      within(5000, function() { return !harness.hintService.settingsUnreadable })

      // A refusal over the update adds, as the footer does under a refusal,
      // and restarts nothing: the one restart asked is the update's click,
      // after a removal that leaves the update said.
      var body = popup.testBody
      var footer = harness.find(body, "footer")
      var restartsBefore = harness.restartsAsked()
      body.say("Keep at least one symbol")
      var refusal = harness.footerText(popup)
      footer.clicked()
      var refusalAdds = body.adding
      body.cancelAdding()
      body.clearNote()
      var gone = harness.hintService.library[0]
      body.removeRow(gone)
      var removed = harness.hintService.library.indexOf(gone) < 0
      var after = harness.footerText(popup)
      footer.clicked()
      within(3000, function() { return harness.restartsAsked() > restartsBefore })
      // Long enough for a second restart, the refusal's, to be written too.
      wait(200)
      var asked = harness.restartsAsked() - restartsBefore
      harness.check("a refusal over the update opens search, and a removal leaves the update said",
        refusal === "Keep at least one symbol" && refusalAdds && removed && after === harness.updateNotice && asked === 1,
        [refusal, refusalAdds, removed, after, asked].join("|"))
      popup.close()

      // A visit whose footer has a notice ahead of the hint records nothing.
      harness.hintService.persist({ hinted: false })
      within(3000, function() { return harness.savedSettings().hinted === false })
      popup.open()
      var hintBehind = harness.footerText(popup)
      var hintedBehind = harness.hintService.hinted
      popup.close()
      harness.writeFile(harness.manifestPath, harness.originalManifest)
      within(3000, function() { return !writer.running })
      var savedBehindUpdate = harness.savedSettings().hinted
      popup.open()
      var hintAfterUpdate = harness.hintLine(popup)
      popup.close()
      harness.check("a first open behind the update notice records no hint, and the next open shows and records it",
        hintBehind === harness.updateNotice && !hintedBehind && savedBehindUpdate === false
          && hintAfterUpdate.indexOf(harness.hintStart) === 0 && harness.hintService.hinted,
        [hintBehind, hintedBehind, savedBehindUpdate, hintAfterUpdate, harness.hintService.hinted].join("|"))

      // A new list ends the undo on offer, and Ctrl+Z says so.
      popup.open()
      var undone = harness.hintService.library[0]
      body.removeRow(undone)
      harness.hintService.createList("Undo ends")
      focusKeys(popup)
      harness.press(popup, Qt.Key_Z, Qt.ControlModifier)
      var nothing = harness.footerText(popup)
      var stillGone = harness.hintService.library.indexOf(undone) < 0
      harness.check("after the next change to the lists Ctrl+Z puts nothing back, and the footer says why",
        stillGone && nothing === "Nothing to undo", stillGone + "|" + nothing)
      popup.close()

      // The shell's KeyboardPanel calls close() on an outside click.
      var names = function() { return harness.hintService.lists.map(function(l) { return l.name }) }
      popup.open()
      body.openManageLists()
      var manage = harness.find(body, "manageLists")
      manage.startRenaming(names().indexOf("Undo ends"))
      harness.find(manage, "renameField").text = "Made here"
      popup.close()
      var renamedOnClose = names().indexOf("Made here") > 0 && names().indexOf("Undo ends") < 0
      popup.open()
      body.openListMenu()
      var listMenu = harness.find(body, "listMenu")
      listMenu.startNaming()
      harness.find(listMenu, "listNameField").text = "Made on close"
      popup.close()
      var madeOnClose = names().indexOf("Made on close") > 0 && harness.hintService.listName === "Made on close"
      harness.check("closing the popup keeps a rename being typed and makes a new list being named",
        renamedOnClose && madeOnClose, names().join(",") + "|" + harness.hintService.listName)

      // With search open, the keys that act on the rows elsewhere, Stonks'
      // and Omarchy's alike, edit its field, and none acts: no row goes, the
      // removal on offer stays out, no menu opens, the cursor and the chart
      // stay, and sounds, the look and the order stay as they were.
      harness.hintService.switchList("")
      popup.open()
      var offered = harness.hintService.library[0]
      body.removeRow(offered)
      body.watchlist.select(harness.hintService.library[0])
      var target = body.watchlist.cursorRow
      var settled = function() {
        return [harness.hintService.library.join(","), harness.hintService.soundsOn, harness.hintService.retro,
          harness.hintService.order, harness.hintService.reversed, body.listMenuOpen,
          body.watchlist.cursorRow, harness.hintService.featuredSymbol].join("|")
      }
      var settledBefore = settled()
      focusKeys(popup)
      harness.press(popup, "a")
      var field = harness.find(body.search, "searchField")
      within(1000, function() { return field.activeFocus })
      var typed = []
      ;["w", "m", "s", "o"].forEach(function(letter) { harness.press(popup, letter) })
      typed.push(field.text)
      harness.press(popup, Qt.Key_Backspace)
      typed.push(field.text)
      harness.press(popup, Qt.Key_Z, Qt.ControlModifier)
      typed.push(field.text)
      harness.press(popup, Qt.Key_Left)
      harness.press(popup, Qt.Key_Delete)
      typed.push(field.text)
      harness.press(popup, Qt.Key_C, Qt.ControlModifier)
      typed.push(field.text)
      ;["j", "k", "h", "l", "x", Qt.Key_Space].forEach(function(key) { harness.press(popup, key) })
      typed.push(field.text)
      harness.check("in the popup's search, w m s o, Backspace, Ctrl+Z, Delete, Ctrl+C, and Omarchy's j k h l x and Space edit the field, and none acts on the rows, the lists, sounds, the look or the order",
        target !== "" && typed.join(",") === "wmso,wms,wmso,wms,wms,wmsjkhlx " && body.adding && field.activeFocus
          && settled() === settledBefore,
        target + " | " + typed.join(",") + " | " + settledBefore + " -> " + settled())
      harness.press(popup, Qt.Key_Escape)

      focusKeys(popup)
      harness.press(popup, Qt.Key_Z, Qt.ControlModifier)
      var back = harness.hintService.library.indexOf(offered) >= 0
      popup.close()
      harness.check("once search closes, Ctrl+Z takes back the removal it left alone",
        !body.adding && back, body.adding + "|" + back)
    }
  }
}
