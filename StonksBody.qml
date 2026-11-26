pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Chart.js" as Chart
import "ChartSound.js" as ChartSound
import "Figures.js" as Figures
import "Freshness.js" as Freshness
import "Format.js" as Format
import "Fundamentals.js" as Fundamentals
import "History.js" as History
import "KeySheet.js" as KeySheet
import "KeyText.js" as KeyText
import "Layout.js" as Layout
import "Market.js" as Market
import "Overnight.js" as Overnight
import "Release.js" as Release
import "Search.js" as Search
import "Settings.js" as Settings
// The body the window and the panel share. It reads the service and acts
// through it; the surface keeps its lifecycle, keys, and look. Each of its
// jobs stands under a banner: what it is handed and what the service says,
// then the stock on show, the rows, the header's words and what fits, then
// what opens over the rows, the keys, the chart's actions and the footer's
// notes, and last the pieces it places.
Item {
  id: root

  // ---- What the panel or the window hands it

  property var service: null
  property var updates: null
  property var sounds: null
  property var camera: null
  property bool surfaceOpen: false
  // False for the window on a workspace no screen shows, or the panel on a
  // screen that's off: it stays open, as it was left, but asks for nothing.
  property bool onScreen: true
  property string headerWhenMissing: "No data"
  // The panel's: Tab steps to the next widget's panel.
  property bool switchesPanels: false
  property int margins: 0

  property int chartHeight: Style.space(190)
  // Set (the window's 136 px), the chart takes the surface's spare height
  // and gives way first as it gets short, so three rows still show. The
  // panel's 0 never changes, so no chartHeight change finds it stale.
  property int minChartHeight: 0

  // The height the screen leaves the panel's body; 0 in the window.
  property int screenRoom: 0

  // The most height the panel's card gives the body; 0 in the window. The
  // rows' sight is measured at that height, whatever the card has shrunk to
  // for the key sheet or a view.
  property int rowsRoom: 0

  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  // The surface's colour, which a moving row carries.
  property color ground: Commons.Color.background

  // How this surface looks, for everything drawn on it.
  readonly property Look look: Look {
    retro: root.retro
    fontFamily: root.fontFamily
    foreground: root.foreground
    ground: root.ground
    upColor: root.upColor
    downColor: root.downColor
  }

  signal keysReleased()
  signal refreshRequested()

  readonly property alias watchlist: watchlist
  readonly property var search: searchLoader.item
  readonly property var manageLists: manageListsLoader.item
  readonly property var symbolLists: symbolListsLoader.item
  readonly property var helpSheet: helpSheetLoader.item
  readonly property var rowMenuView: rowMenuLoader.item
  readonly property var listMenu: listMenuLoader.item
  readonly property alias chartItem: heroBand.chartItem
  readonly property alias motion: motion

  // ---- What the service says, held still while the surface is closed

  readonly property var emptyView: ({ featured: "", range: "1D", list: "", listKey: "=", order: "manual", reversed: false,
    rows: [], shown: [], allSymbols: [], chart: null })
  // One value, so each change of the rows, hero, range, and chart is whole.
  property var view: emptyView
  property var quotes: ({})
  property var entries: ({})
  // Each listing's newest price since its close.
  property var newestTrades: ({})
  // Robinhood's answers, for the day each row's line draws, held still while
  // the surface is closed; and the day's clock, held still while no screen
  // shows the surface.
  property var nights: ({})
  property int dayClock: 0
  property var previewEntries: ({})
  // Each symbol's cap and P/E, and the currency rates P/Es need.
  property var fundamentalEntries: ({})
  // Every range the service holds, by `History.historyKey`.
  property var histories: ({})
  property var rates: ({})
  property var lists: []
  // The current list's members, those still arriving included.
  property var members: []
  property var arriving: []
  property var removal: null
  property string changeMode: "pct"
  property bool retro: false
  property bool soundsOn: false
  // Each symbol waiting on Yahoo, by the second it began.
  property var owed: ({})
  // Symbols asked for under 2 s ago: a quote opened old isn't late yet.
  property var asking: ({})
  // Listings whose Robinhood answer failed while the night trades
  // (`Service.nightFailed`).
  property var nightFailed: ({})
  // A refresh the reader asked for is out.
  property bool refreshing: false
  // A closed surface's clock holds still too.
  property int now: 0
  readonly property bool reading: surfaceOpen && !!service
  // The view, its chart rebuilt as the day's clock steps, holds still
  // for a surface no screen shows, such as a window on another workspace.
  readonly property bool showing: reading && onScreen
  readonly property bool previewing: previewSymbol !== "" && !!service && service.previewSurface === root
  Binding on view {
    when: root.showing
    value: root.previewing ? root.service?.previewView : root.service?.view
    restoreMode: Binding.RestoreNone
  }
  Binding on quotes { when: root.reading; value: root.service?.quotes; restoreMode: Binding.RestoreNone }
  Binding on entries { when: root.reading; value: root.service?.entries; restoreMode: Binding.RestoreNone }
  Binding on newestTrades { when: root.reading; value: root.service?.newestTrades; restoreMode: Binding.RestoreNone }
  Binding on nights { when: root.reading; value: root.service?.nights; restoreMode: Binding.RestoreNone }
  Binding on nightFailed { when: root.reading; value: root.service?.nightFailed; restoreMode: Binding.RestoreNone }
  Binding on dayClock { when: root.showing; value: root.service?.viewDayClock ?? 0; restoreMode: Binding.RestoreNone }
  Binding on previewEntries { when: root.reading; value: root.service?.previewEntries; restoreMode: Binding.RestoreNone }
  Binding on fundamentalEntries { when: root.reading; value: root.service?.fundamentals; restoreMode: Binding.RestoreNone }
  Binding on rates { when: root.reading; value: root.service?.rates; restoreMode: Binding.RestoreNone }
  Binding on histories { when: root.reading; value: root.service?.histories; restoreMode: Binding.RestoreNone }
  Binding on lists { when: root.reading; value: root.service?.lists; restoreMode: Binding.RestoreNone }
  // Each list's identity (`Service.listKey`), by which the rows keep their
  // place in each list.
  property var listKeys: []
  Binding on listKeys {
    when: root.reading
    value: root.service && root.service.listKey ? root.service.lists.map(function(list) { return root.service.listKey(list.name) }) : []
    restoreMode: Binding.RestoreNone
  }
  Binding on members { when: root.reading; value: root.service?.symbols; restoreMode: Binding.RestoreNone }
  Binding on arriving { when: root.reading; value: root.service?.arriving; restoreMode: Binding.RestoreNone }
  Binding on removal { when: root.reading; value: root.service?.lastRemoval; restoreMode: Binding.RestoreNone }
  Binding on changeMode { when: root.reading; value: root.service?.changeMode; restoreMode: Binding.RestoreNone }
  Binding on retro { when: root.reading; value: root.service?.retro; restoreMode: Binding.RestoreNone }
  Binding on soundsOn { when: root.reading; value: root.service?.soundsOn; restoreMode: Binding.RestoreNone }
  Binding on owed { when: root.reading; value: root.service?.owed; restoreMode: Binding.RestoreNone }
  Binding on asking { when: root.reading; value: root.service?.asking || ({}); restoreMode: Binding.RestoreNone }
  Binding on refreshing { when: root.reading; value: root.service?.refreshing; restoreMode: Binding.RestoreNone }
  // What the footer says of saving and updating (`Release.footerNotice`).
  property var footerSays: Release.footerNotice({}, "")
  Binding on footerSays {
    when: root.reading
    value: Release.footerNotice({ unreadable: root.service?.listsUnreadable, saveFailed: root.service?.saveFailed,
      editsUnsaved: root.service?.editsUnsaved, updatedTo: root.updates ? root.updates.newVersion : "",
      releasedTo: root.updates ? root.updates.releasedVersion : "" }, root.listsFile)
    restoreMode: Binding.RestoreNone
  }
  readonly property bool saveFailed: footerSays.saveFailed
  // Why Yahoo is paused, and until when (`Gate.js`).
  property var yahooPause: ({ pause: "", until: 0 })
  Binding on yahooPause {
    when: root.reading
    value: root.service?.yahooGate ? { pause: root.service.yahooGate.pause, until: root.service.yahooGate.pausedUntil } : { pause: "", until: 0 }
    restoreMode: Binding.RestoreNone
  }
  Binding on now { when: root.reading; value: root.service?.now; restoreMode: Binding.RestoreNone }
  readonly property int minuteNow: Math.floor(now / 60) * 60

  readonly property var calendars: service ? service.calendars : null
  // Kept as the same array while row membership is unchanged, so switching
  // stock or range never re-runs list-wide breadth, shared-day or scrub work.
  property var stableRows: []
  function sameRows(a, b) {
    if (!a || !b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }
  readonly property var symbols: stableRows
  readonly property string listName: view.list
  readonly property string listLabel: listName !== "" ? listName : "All"
  readonly property var shown: view.shown
  readonly property string featuredSymbol: view.featured
  readonly property string range: view.range
  readonly property string order: view.order
  readonly property bool reversed: view.reversed

  function entryOf(symbol) {
    if (entries && entries[symbol]) return entries[symbol]
    return previewEntries && previewEntries[symbol] ? previewEntries[symbol] : null
  }

  // ---- What it tells the service

  // A search held back while no screen showed it goes once one does.
  onSurfaceOpenChanged: {
    if (service) service.surfaceShown(root, surfaceOpen && onScreen)
    if (!surfaceOpen) previewTo("")
  }
  onOnScreenChanged: {
    if (service) service.surfaceShown(root, surfaceOpen && onScreen)
    if (onScreen) searchFeed.sendWaiting()
  }
  onServiceChanged: if (service && surfaceOpen && onScreen) service.surfaceShown(root, true)

  // On a screen that's on, as far as Hyprland has said: `onScreen` counts a
  // surface whose screen it hasn't named as shown.
  readonly property bool seen: surfaceOpen && onScreen && !(service && service.screensOff)

  // Asked for first on open, and fetched ahead on a range.
  readonly property var rowsInSight: surfaceOpen && onScreen && rowsShown ? watchlist.sightSymbols : []
  onRowsInSightChanged: if (service) service.rowsSeen(root, rowsInSight)
  // The service holds answers that would stutter the chart drawing in.
  readonly property bool drawingIn: surfaceOpen && onScreen && motion.drawingIn
  onDrawingInChanged: if (service) service.drawingIn(root, drawingIn)

  // A rebuilt bar or a removed screen takes the panel down mid-replay.
  Component.onDestruction: {
    if (sounds) sounds.stopReplay(root)
    if (service) {
      service.surfaceShown(root, false)
      service.preview(root, "")
    }
  }

  property bool pendingRestart: false
  function requestRestart() {
    if (!root.updates) return
    if (root.service) root.service.flushSave()
    if (root.service && root.service.saving) {
      root.pendingRestart = true
      return
    }
    if (root.footerSays.restartable) root.updates.restart()
  }
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPreviewTaken(surface) { if (surface === root) root.cancelAdding() }
    function onScreensReady() { searchFeed.sendWaiting() }
    function onYahooBack() { if (root.onScreen && root.search) root.search.yahooBack() }
    function onSavingChanged() {
      if (!root.pendingRestart || !root.service || root.service.saving) return
      root.pendingRestart = false
      if (root.updates && root.footerSays.restartable) root.updates.restart()
    }
  }

  // ---- The stock on show

  property var rangeOptions: History.historyRanges()
  readonly property var chart: motion.chart
  readonly property bool chartLoading: motion.loading
  readonly property string chartSymbol: chart ? chart.symbol : ""
  readonly property string chartRange: chart ? chart.range : "1D"
  readonly property var fundamentalsEntry: chartSymbol ? fundamentalEntries[chartSymbol] || null : null

  readonly property bool historyActive: motion.historyActive
  readonly property var history: motion.history
  // A range whose first fetch failed: the day stands in, figures and all.
  readonly property bool historyFailed: !!chart && chart.failed
  // Worked out here from the same two values the chart reads, not read from
  // the chart: its own would turn true a binding before `history` here does.
  readonly property bool historyShown: historyActive && !!history
  readonly property var historyStats: historyShown ? History.periodStats(history) : null
  readonly property var historyBar: historyShown && scrubT
    ? History.historyBarAt(history, History.historyFraction(history, scrubT)) : null
  readonly property int scrubShown: motion.scrubShown
  // The moment a scrub or a replay shows.
  readonly property int scrubT: motion.scrubT
  readonly property real scrubX: motion.scrubX
  readonly property bool dayScrubbed: !historyActive && scrubShown !== 0

  readonly property var featuredQuote: motion.quote
  // The day the 1D chart draws; its baseline is `prevClose`.
  readonly property var featuredDay: motion.day
  readonly property var featuredFreshness: Freshness.freshness(entryOf(chartSymbol || featuredSymbol), featuredQuote, now,
    owed[chartSymbol || featuredSymbol] || 0, !!asking[chartSymbol || featuredSymbol], featuredNewest, !!nightFailed[chartSymbol || featuredSymbol])
  readonly property var featuredGeometry: motion.geometry
  readonly property var featuredNewest: featuredQuote && featuredDay ? Overnight.newestTrade(featuredQuote, motion.latest, calendars, featuredDay) : null
  readonly property var dailyFeatured: featuredQuote
    ? Figures.rowModel(dayScrubbed ? featuredDay : featuredQuote, dayScrubbed ? scrubShown : 0, changeMode, featuredNewest) : null
  readonly property var featured: historyShown ? History.historyRowModel(history, featuredQuote, scrubShown) : dailyFeatured
  // A live marker is honest only when the headline and chart endpoint are the same day quote.
  readonly property bool heroLive: (!historyActive || historyFailed)
    && !scrubT && featuredFreshness.live

  // Changes only at the exchange's midnight, unlike `now`.
  readonly property int featuredToday: featuredQuote ? Figures.exchangeDay(featuredQuote, now) : 0
  // The table holds room for both first lines' facts, and their lows and
  // highs, on every range held for the stock, and for every stock in All, so
  // neither a range change nor another stock moves its rules. A range first
  // fetched with more digits than any held widens it once.
  readonly property var dayLine: chart ? Figures.dayLine(featuredQuote, featuredToday, featuredDay) : null
  // The trades Stonks shows for the stock, beyond Yahoo's bars and figures:
  // the 1D chart's, tonight's too, and the newest. The ranges and the 52W
  // line take them in, so none reads under the day.
  readonly property var shownTrades: (featuredDay ? featuredDay.trades || featuredDay.points : []).concat(featuredNewest ? [featuredNewest] : [])
  readonly property var rangeEnds: historyShown ? History.rangeEnds(history, historyStats, featuredQuote, shownTrades) : null
  readonly property var periodLine: !chart ? null : historyShown ? History.rangeLine(history, rangeEnds, featuredQuote) : dayLine
  readonly property var heldLines: chart ? History.heldLines(histories, chartSymbol, featuredQuote, shownTrades) : []
  readonly property var infoFactLists: (!dayLine ? [] : [dayLine.facts, History.rangeFacts(dayLine.range.widest)]
    .concat(yearLine ? [History.rangeFacts(yearLine.range.widest)] : [])
    .concat(heldLines.map(function(line) { return line.facts }))).concat(listInfo.factLists)
  readonly property var infoRanges: (!dayLine ? [] : [dayLine.range].concat(heldLines.map(function(line) { return line.range })))
    .concat(listInfo.ranges)
  // Every stock in All as the table holds it: its day's and its 52 weeks'
  // facts and prices, by the shape of their widest, so a refresh that keeps
  // every shape lays nothing out again. Per-symbol results are cached by quote
  // and rates reference so a batch only recomputes symbols that changed.
  readonly property var listInfoCache: ({ by: {}, rates: null })
  readonly property var listInfoNow: {
    var all = lists.length ? lists[0].symbols : []
    var cache = listInfoCache
    if (cache.rates !== rates) {
      cache.by = {}
      cache.rates = rates
    }
    var facts = {}
    var ranges = {}
    var nextBy = {}
    for (var i = 0; i < all.length; i++) {
      var sym = all[i]
      var q = quotes[sym]
      if (!q) continue
      var had = cache.by[sym]
      if (!had || had.quote !== q) {
        var day = Figures.dayLine(q, 0, null)
        var year = Fundamentals.yearLine(q, null, null, rates, [])
        var fList = [day.facts, History.rangeFacts(day.range.widest), year.facts, History.rangeFacts(year.range.widest)]
        var fKeys = fList.map(function(list) {
          return list.map(function(f) { return f.label + " " + f.widest }).join("|")
        })
        var rKeys = []
        if (day.range.widest) rKeys.push(day.range.widest)
        if (year.range.widest) rKeys.push(year.range.widest)
        had = { quote: q, fList: fList, fKeys: fKeys, rKeys: rKeys }
      }
      nextBy[sym] = had
      for (var j = 0; j < had.fKeys.length; j++) facts[had.fKeys[j]] = had.fList[j]
      for (var k = 0; k < had.rKeys.length; k++) {
        var w = had.rKeys[k]
        if (!ranges[w]) ranges[w] = { widest: w, lowText: "", highText: "" }
      }
    }
    cache.by = nextBy
    var factKeys = Object.keys(facts).sort()
    var rangeKeys = Object.keys(ranges).sort()
    return { key: factKeys.join("/") + "#" + rangeKeys.join("/"),
      factLists: factKeys.map(function(k) { return facts[k] }), ranges: rangeKeys.map(function(k) { return ranges[k] }) }
  }
  property var listInfo: ({ key: "", factLists: [], ranges: [] })
  onListInfoNowChanged: if (listInfoNow.key !== listInfo.key) listInfo = listInfoNow
  readonly property var yearLine: chart ? Fundamentals.yearLine(featuredQuote, fundamentalsEntry ? fundamentalsEntry.fundamentals : null,
    historyShown && history.range === "1Y" ? rangeEnds : null, rates, shownTrades) : null
  readonly property var rangeMarks: historyShown ? History.rangeMarks(history, rangeEnds, featuredQuote,
    function(t) { return Market.tradeClock(featuredQuote, t, calendars) }) : null
  // Said under the price: what a scrub's move counts from, the dashed line
  // under the pointer, or since the open the day's open.
  readonly property string baselineText: historyShown ? History.baselineLegend(history, featuredQuote ? featuredQuote.priceDigits : undefined)
    : (!historyActive && featuredDay ? Figures.scrubLegend(featuredDay, scrubShown, featuredToday, calendars, changeMode, featuredNewest) : "")

  // The moment shown against the baseline; the pill's reads the day.
  readonly property string animalKind: Figures.headerAnimal(featured)
  // A change of chart, list, or look is no turn: the animal changes at once.
  // A failed range's stand-in day is another chart than its history.
  readonly property string animalChart: [motion.chartKeyOf(chart), view.listKey, retro].join(" ")
  // It sleeps by phase and calendar, never by the data's age. `bell`: the
  // clock alone changed its sleep in the last `bellWindow` seconds, a late
  // or skipped tick included. One number, so sleep, bell, and scrub never
  // disagree and the animal changes only when its sleep does.
  readonly property int bellWindow: 5
  readonly property int animalSleep: {
    if (scrubT) return 3
    if (!featuredQuote) return 0
    var atNight = !!chart && chart.tradesAtNight
    var asleep = Overnight.marketAsleep(featuredQuote, atNight, now, calendars)
    var before = Overnight.marketAsleep(featuredQuote, atNight, now - bellWindow, calendars)
    return asleep ? (before ? 1 : 2) : (before ? 4 : 0)
  }
  readonly property var animal: ({ kind: animalKind, chart: animalChart, stock: chartSymbol,
    asleep: animalSleep === 1 || animalSleep === 2, bell: animalSleep === 2 || animalSleep === 4, scrubbed: animalSleep === 3 })

  // ---- The rows

  // The rows follow a scrub of the day, each reading its own line
  // (`Figures.listRow`).
  readonly property int watchlistScrubShown: historyActive ? 0 : scrubShown
  readonly property bool rowsScrubbed: watchlistScrubShown !== 0
  // Every row's line while the rows follow a scrub, so the breadth reads
  // what each row reads, never worked out at a step. Each is worked out
  // again only when what it is drawn from changes, as the newest prices are
  // (`Service.newestFrom`), and only as many a frame as fit in
  // `rowLinesBudget` ms, so a long list's first scrub stalls no frame.
  // Until every line is in, the rule is plain: it counts nothing rather
  // than a count the rows don't say.
  property var rowLines: null
  property var rowLinesFrom: ({})
  // The lines being worked out: what they are drawn from, the next row's
  // place, and those done.
  property var rowLinesWork: null
  readonly property int rowLinesBudget: 1
  readonly property var rowLinesAsk: rowsScrubbed && surfaceOpen ? [stableRows, quotes, nights, calendars, dayClock] : null
  onRowLinesAskChanged: {
    var done = rowLinesWork ? Object.assign({}, rowLinesWork.done, rowLinesWork.from) : {}
    if (!rowLinesAsk) rowLines = null
    rowLinesWork = rowLinesAsk ? { symbols: stableRows, quotes: quotes, nights: nights, calendars: calendars,
      dayClock: dayClock, next: 0, from: {}, lines: {}, done: done } : null
  }
  function workOnRowLines() {
    var work = rowLinesWork
    var until = Date.now() + rowLinesBudget
    while (work.next < work.symbols.length && Date.now() < until) {
      var symbol = work.symbols[work.next++]
      var quote = work.quotes[symbol]
      if (!quote) continue
      // Null in a harness that stubs the service (`Chart.dayDrawn`).
      var night = work.nights ? work.nights[symbol] : null
      var had = work.done[symbol] || rowLinesFrom[symbol]
      var line = had && had.quote === quote && had.night === night
        && had.calendars === work.calendars && had.dayClock === work.dayClock ? had
        : { quote: quote, night: night, calendars: work.calendars, dayClock: work.dayClock,
          line: Chart.lineDay(symbol, quote, work.nights, work.calendars, work.dayClock) }
      work.from[symbol] = line
      if (line.line) work.lines[symbol] = line.line
    }
    if (work.next < work.symbols.length) return
    rowLinesFrom = work.from
    rowLines = work.lines
    rowLinesWork = null
  }
  FrameAnimation {
    running: root.rowLinesWork !== null && root.surfaceOpen
    onTriggered: root.workOnRowLines()
  }

  // Resting breadth and shared day read each symbol's quote and newest trade
  // once together, never on a stock or range switch, and never during a scrub.
  readonly property var restingRowsSummary: {
    var rows = stableRows
    var qMap = {}
    var ntMap = {}
    for (var i = 0; i < rows.length; i++) {
      var s = rows[i]
      var q = quotes[s]
      if (q) qMap[s] = q
      var nt = newestTrades[s]
      if (nt) ntMap[s] = nt
    }
    return {
      breadth: Figures.listBreadth(rows, qMap, null, 0, changeMode, ntMap),
      shared: Figures.rowsSharedDay(rows, qMap, ntMap, calendars)
    }
  }
  readonly property var breadth: Object.assign({ list: listName },
    rowLinesWork ? { up: 0, flat: 0, down: 0, none: 0 }
    : watchlistScrubShown ? Figures.listBreadth(stableRows, quotes, rowLines, watchlistScrubShown, changeMode, newestTrades)
    : restingRowsSummary.breadth)

  // The day the rows share, worked out again only as their prices change;
  // the clock reads only its name (`Figures.rowsDayName`).
  readonly property var rowsShared: restingRowsSummary.shared

  // ---- The header's words

  // Counted again as All, its prices' answers, or what is owed changes, and
  // as one owed turns overdue: never at a tick that can't change the count.
  readonly property int overdueClock: Freshness.overdueClock(owed, now)
  readonly property int warnings: lists.length > 0
    ? Freshness.warningCount(lists[0].symbols, entries, previewEntries, owed, overdueClock) : 0
  readonly property bool yahooDown: warnings > 0 && warnings === lists[0].symbols.length

  readonly property string loadingText: "Loading" + (featuredSymbol ? " " + featuredSymbol + (range !== "1D" ? " " + range : "") : "")
  readonly property var marketFormsNow: featuredQuote ? Market.statusForms(dayScrubbed ? featuredDay : featuredQuote, now, scrubShown, calendars,
    Overnight.nightTrades(featuredQuote, !!chart && chart.tradesAtNight, now, calendars)) : []
  property var marketForms: []
  function sameStrings(a, b) {
    if (!a || !b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }
  onMarketFormsNowChanged: if (!sameStrings(marketForms, marketFormsNow)) marketForms = marketFormsNow
  Component.onCompleted: {
    if (!sameRows(stableRows, view.rows)) stableRows = view.rows
    marketForms = marketFormsNow
  }
  readonly property var headerLine: Figures.headerLine({
    hasService: !!service,
    whenMissing: headerWhenMissing,
    scrubbed: scrubShown !== 0,
    refreshing: refreshing,
    rangeFailed: historyActive && historyFailed,
    chartRange: chartRange,
    pause: Freshness.hostPause(yahooPause.pause, yahooPause.until, now),
    warnings: warnings,
    // The panel says Yahoo's pause short; the window has room for a sentence.
    compact: switchesPanels,
    yahooDown: yahooDown,
    quoted: !!featuredQuote,
    featuredFailed: featuredFreshness.state === "failed",
    symbol: chartSymbol || featuredSymbol,
    loading: chartLoading,
    hasChart: !!chart,
    loadingText: loadingText,
    scrubForms: historyShown && historyBar ? History.historyScrubForms(history, historyBar, featuredQuote ? featuredQuote.priceDigits : undefined) : null,
    marketForms: marketForms
  })
  readonly property string headerText: headerLine.forms[0] || ""

  // ---- What fits

  // The panel's card eases to a new height while the body lays out at once,
  // so rows past the edge are out of sight.
  property real edge: Math.min(height, fittedHeight(Infinity))
  // A band's gap stands between the band's blocks, a group's gap between a
  // thing and what it heads, measured from words, not a control's fill.
  readonly property int bandGap: Style.space(16)
  readonly property int groupGap: Style.space(8)
  // Every block's words stand `inset` in from the rows' fills, which leave a
  // `gutter` on the right for the scrollbar.
  readonly property int inset: Style.space(10)
  readonly property int gutter: Style.space(8)
  readonly property int textLeft: margins + inset
  readonly property int textRight: margins + gutter + inset

  readonly property int rowHeight: Style.space(30)
  readonly property int listRowHeight: Style.space(40)
  readonly property int rowGap: Style.space(2)

  // Every height, from what the pieces measure beside the chart and the
  // rows, and the band as laid out, never from the header's or the footer's
  // height, which these set (`Layout.js`). The panel's card takes its height
  // from `fit`, and the window its least height from `measured`, so neither
  // reads the body's height but the window's chart.
  readonly property var measured: Layout.measure({
    screenRoom: screenRoom,
    margins: margins,
    groupGap: groupGap,
    listMenuGap: Style.space(4),
    rowHeight: listRowHeight,
    rowGap: rowGap,
    chartHeight: chartHeight,
    minChartHeight: minChartHeight,
    headerTitledHeight: header.titledHeight,
    headerBareHeight: header.bareHeight,
    bandBesideChart: heroBand.heightBesideChart,
    footerBarHeight: footer.barHeight,
    hintRoom: footer.hintRoom,
    named: listName !== "",
    symbolCount: symbols.length
  })
  function windowHeight() { return minChartHeight > 0 ? height : 0 }
  readonly property var fit: Layout.place(measured, windowHeight(), heroBand.implicitHeight)
  // Placed afresh, not read from `fit`, which a new height reaches after it
  // reaches this: the rows never count a height against stale chrome.
  readonly property var rowsFit: Layout.rows(Layout.place(measured, windowHeight(), heroBand.implicitHeight), height, rowsRoom)
  readonly property int rowPitch: fit.rowPitch
  readonly property int chromeHeight: fit.chromeHeight
  readonly property int smallestHeight: measured.smallestHeight

  function fittedHeight(maxHeight) {
    return Layout.fittedHeight(fit, {
      help: showingHelp,
      helpHeight: helpSheet ? helpSheet.contentHeight : 0,
      lists: listViewOpen,
      listsHeight: managingLists ? (manageLists ? manageLists.contentHeight : 0) : (symbolLists ? symbolLists.contentHeight : 0),
      search: adding,
      searchHeight: search ? search.desiredHeight : 0,
      menu: listMenuOpen,
      menuHeight: listMenu ? listMenu.contentHeight : 0,
      menuLeast: listMenu ? listMenu.leastHeight : 0
    }, maxHeight)
  }

  // ---- What is open over the rows

  // One-shot lazy activation flags for the six hidden overlays: none is
  // instantiated on first panel open, and once used each stays alive through
  // its close fade.
  property bool searchLoaded: false
  property bool manageListsLoaded: false
  property bool symbolListsLoaded: false
  property bool helpSheetLoaded: false
  property bool rowMenuLoaded: false
  property bool listMenuLoaded: false

  property bool adding: false
  property string previewSymbol: ""
  property bool showingHelp: false
  onShowingHelpChanged: if (showingHelp) helpSheetLoaded = true
  property bool listMenuOpen: false
  onListMenuOpenChanged: if (listMenuOpen) listMenuLoaded = true
  property bool managingLists: false
  onManagingListsChanged: if (managingLists) manageListsLoaded = true
  property string listsSymbol: ""
  // Held through the close fade so the overlay doesn't empty before it goes.
  property string heldListsSymbol: ""
  onListsSymbolChanged: if (listsSymbol !== "") { heldListsSymbol = listsSymbol; symbolListsLoaded = true }
  property var rowMenu: null
  property var heldRowMenu: null
  onRowMenuChanged: if (rowMenu !== null) { heldRowMenu = rowMenu; rowMenuLoaded = true }
  readonly property bool listViewOpen: managingLists || listsSymbol !== ""
  readonly property bool rowsShown: !showingHelp && !adding && !listViewOpen
  readonly property bool ownsKeys: adding || listMenuOpen || listViewOpen || rowMenu !== null

  // A turn later, so a view closing as another opens hands the keys across.
  onOwnsKeysChanged: if (!ownsKeys) Qt.callLater(function() { if (!root.ownsKeys) root.keysReleased() })

  readonly property var keySheet: KeySheet.sheet()

  function closeViews() {
    cancelAdding()
    showingHelp = false
    listMenuOpen = false
    managingLists = false
    listsSymbol = ""
    rowMenu = null
  }

  function keepRename() {
    if (managingLists && manageLists && manageLists.renaming) manageLists.keepName()
    return !(managingLists && manageLists && manageLists.renaming)
  }

  function toggleHelp() {
    if (!keepRename()) return
    var shown = showingHelp
    closeViews()
    showingHelp = !shown
    if (showingHelp && helpSheet) helpSheet.contentY = 0
  }

  // ---- Search, and a stock being added

  // The added symbol the chart changes to once its answer is in, its row in
  // view, and the list at rest.
  property string landing: ""
  property bool landingJoined: false
  // A Show of a member still arriving: featured even if its first fetch fails.
  property bool landingShows: false
  // Picked by a click: its row's × waits for the pointer to move, unless it
  // moves over the rows before the row joins.
  property bool landingPointed: false
  // Each add is heard as its row joins, whatever is featured or added meanwhile.
  property var unheardAdds: []

  onFeaturedSymbolChanged: if (featuredSymbol !== landing) landing = ""

  // The list's own stocks the search names, each with the move its row
  // shows at rest, and All's while a new list is being filled, so a stock
  // Stonks already follows comes at once, without asking Yahoo. Asked only
  // while search is open.
  readonly property var ownFound: adding && search ? Search.ownMatches(search.searchText, filling ? lists[0].symbols : members, quotes).map(function(symbol) {
    var quote = quotes[symbol]
    var row = quote ? Figures.listRow(quote, changeMode, newestTrades[symbol] || null) : null
    return { symbol: symbol, name: quote ? quote.name : "", exchange: quote ? quote.exchange : "",
      move: row ? Format.lookSigns(row.changeLine, retro) : "", tone: row ? row.tone : "flat" }
  }) : []

  // Search opened by New list, to fill the list just made.
  property bool filling: false
  onAddingChanged: {
    if (adding) searchLoaded = true
    else filling = false
  }

  function startAdding() {
    if (!keepRename()) return
    closeViews()
    adding = true
  }

  // An add joins the rows once its first answer is in, and is featured once
  // it and the list rest. A result already in the list is shown, not added.
  // Filling a new list, search stays open for the next: an add is listed
  // there, and one already added is featured for when it closes.
  function acceptSymbol(symbol, pointed) {
    if (!service) return
    var s = String(symbol || "").trim().toUpperCase()
    if (view.rows.indexOf(s) >= 0) {
      if (filling) service.feature(s)
      else showSymbol(s, pointed)
      return
    }
    if (putBack && s === putBack.symbol) {
      cancelAdding()
      undoRemoval(pointed)
      return
    }
    var member = members.indexOf(s) >= 0
    if (!filling) adding = false
    if (!member) service.addSymbol(s)
    else service.feature(s)
    previewTo("")
    // After the preview has gone, whose hero was a choice, not a landing.
    landing = s
    landingShows = member
    landingPointed = !!pointed
    if (!member) unheardAdds = unheardAdds.filter(function(a) { return a !== s }).concat([s])
    landingJoined = false
    land()
    if (filling && search) search.addedOne(s)
  }

  // Show features the member before the preview ends, so the chart on show
  // never changes for it, and ends an add still landing itself: the hero may
  // already be the result, so `onFeaturedSymbolChanged` wouldn't.
  function showSymbol(symbol, pointed) {
    landing = ""
    service.feature(symbol)
    cancelAdding()
    watchlist.select(symbol, pointed)
  }

  // Called once the rows show the service's latest view.
  function land() {
    // Rows joining together are heard once.
    if (unheardAdds.length && service) {
      var joined = unheardAdds.filter(function(a) { return arriving.indexOf(a) < 0 && view.rows.indexOf(a) >= 0 })
      if (joined.length) sound("add")
      var still = unheardAdds.filter(function(a) { return joined.indexOf(a) < 0 && members.indexOf(a) >= 0 })
      if (still.length !== unheardAdds.length) unheardAdds = still
    }
    if (landing === "" || !service || arriving.indexOf(landing) >= 0) return
    var failed = !quotes[landing] && !!entries[landing] && entries[landing].status === "failed"
    // A new symbol's failed first fetch is done: the hero stays where it
    // was, its row saying it failed. A Show of a member still features it.
    if (view.rows.indexOf(landing) < 0 || (failed && !landingShows)) {
      landing = ""
      return
    }
    if (!quotes[landing] && !failed) return
    if (!landingJoined) {
      landingJoined = true
      watchlist.select(landing, landingPointed)
    }
    featureLanding()
  }

  function featureLanding() {
    if (landing === "" || !landingJoined || watchlist.settling || !watchlist.rowResting(landing)) return
    var symbol = landing
    landing = ""
    if (service) service.feature(symbol)
  }

  function cancelAdding() {
    adding = false
    previewTo("")
  }

  function previewTo(symbol, result) {
    var s = adding && surfaceOpen ? String(symbol || "") : ""
    if (s === previewSymbol) return
    // The service's first: until it is, this preview would read as taken.
    if (service) service.preview(root, s, s ? result : null)
    previewSymbol = s
  }

  // ---- The list menu and the list views

  function openListMenu() {
    if (!keepRename()) return
    closeViews()
    watchlist.forgetClicks()
    listMenuOpen = true
  }

  function closeListMenu() {
    listMenuOpen = false
  }

  function chooseList(name) {
    closeListMenu()
    if (service && name !== listName) service.switchList(name)
  }

  function createList(name) {
    if (!service) return
    var problem = service.createList(name)
    if (problem !== "") { if (listMenu) listMenu.problem = problem; return }
    startAdding()
    filling = true
  }

  function openManageLists() {
    closeViews()
    managingLists = true
  }

  function openSymbolLists(symbol) {
    if (!symbol) return
    closeViews()
    listsSymbol = symbol
  }

  function closeListViews() {
    managingLists = false
    listsSymbol = ""
  }
  // Once its symbol leaves All, however, there is nothing to tick.
  onViewChanged: {
    if (!sameRows(stableRows, view.rows)) stableRows = view.rows
    if (listsSymbol !== "" && view.allSymbols.indexOf(listsSymbol) < 0) listsSymbol = ""
  }

  function renameList(name, newName) {
    if (!service) return
    var problem = service.renameList(name, newName)
    if (problem !== "") { if (manageLists) manageLists.problem = problem }
    else if (manageLists) manageLists.stopEditing()
  }

  function setMembership(name, member) {
    if (!service) return
    if (name === "" && !member) removeFrom(listsSymbol, true)
    else service.setMembership(listsSymbol, name, member, watchlist.displayedSymbols)
  }

  // ---- A row's menu

  // It stays where it opened, so a resize, as tiling makes, closes it, as a
  // desktop's menus close.
  onWidthChanged: rowMenu = null
  onHeightChanged: rowMenu = null
  // It also closes when its list, its symbol's lists, or its row change. A
  // binding, not a handler: a handler could read the list's name before it
  // moves, and the lists can keep their array when only the list changes.
  function rowMenuGround(symbol) {
    if (view.rows.indexOf(symbol) < 0) return ""
    return JSON.stringify([view.list, lists.filter(function(list) { return list.symbols.indexOf(symbol) >= 0 }).map(function(list) { return list.name })])
  }
  readonly property string rowMenuGroundNow: rowMenu ? rowMenuGround(rowMenu.symbol) : ""
  // Closed a turn later, so the binding doesn't read itself again.
  onRowMenuGroundNowChanged: if (rowMenu && rowMenuGroundNow !== rowMenu.ground) Qt.callLater(function() {
    if (root.rowMenu && root.rowMenuGround(root.rowMenu.symbol) !== root.rowMenu.ground) root.rowMenu = null
  })

  function rowMenuLines(symbol) {
    var held = listsHolding(symbol)
    var everywhere = { label: held > 1 ? "Remove from all " + held + " lists" : "Remove from All", everywhere: true }
    return listName !== "" ? [{ label: "Remove from " + listName, everywhere: false }, everywhere] : [everywhere]
  }

  // At the pointer, on no line; from a key, under the row's symbol, on its
  // first line. Without room under, it opens upward. A right-click's menu
  // also offers the row's lists, as Ctrl-click opens them, last, so its
  // first line stays where it was.
  function openRowMenu(symbol, point) {
    var row = watchlist.rowItem(symbol)
    if (!service || !row || watchlist.displayedSymbols.indexOf(symbol) < 0) return
    closeViews()
    watchlist.cursorSymbol = symbol
    var top = row.mapToItem(root, Style.space(28), 0)
    var at = point ? root.mapFromItem(null, point.x, point.y) : top
    var lines = rowMenuLines(symbol).concat(point ? [{ label: "Choose lists…", lists: true }] : [])
    rowMenu = { symbol: symbol, lines: lines, ground: rowMenuGround(symbol), startLine: point ? -1 : 0, x: at.x,
      below: point ? at.y : top.y + row.height, above: at.y }
  }

  function takeRowMenu(index) {
    var menu = rowMenu
    var line = menu && index >= 0 && index < menu.lines.length ? menu.lines[index] : null
    if (line && line.lists) openSymbolLists(menu.symbol)
    else if (line) removeFrom(menu.symbol, line.everywhere)
    rowMenu = null
  }

  // ---- Keys, and what they change

  // The `?` sheet's keys, which both surfaces answer; each reads Esc, and
  // the panel Tab, itself. Ctrl with ↑ or ↓ moves a row, as Omarchy's
  // panels reorder.
  function pressKey(event) {
    var key = event.key
    var mods = event.modifiers & ~Qt.KeypadModifier
    // A letter's command is its key, never its text: Caps Lock sends "S"
    // for s.
    var t = KeyText.typed(event)
    if (mods === Qt.ControlModifier && key === Qt.Key_Z) undoRemoval()
    else if (mods === Qt.ControlModifier && key === Qt.Key_Up) moveSelected(-1)
    else if (mods === Qt.ControlModifier && key === Qt.Key_Down) moveSelected(1)
    else if (key === Qt.Key_Up) moveCursor(-1)
    else if (key === Qt.Key_Down) moveCursor(1)
    else if (key === Qt.Key_PageUp) moveCursor(-watchlist.pageRows())
    else if (key === Qt.Key_PageDown) moveCursor(watchlist.pageRows())
    else if (key === Qt.Key_Home) moveCursorTo(0)
    else if (key === Qt.Key_End) moveCursorTo(watchlist.displayedSymbols.length - 1)
    else if (key === Qt.Key_Left) nudgeScrub(-1)
    else if (key === Qt.Key_Right) nudgeScrub(1)
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) featureSymbol(watchlist.cursorRow)
    else if (key === Qt.Key_Delete || key === Qt.Key_Backspace) removeSelected()
    else if (t === "?") toggleHelp()
    else if (t === "a" || t === "/") startAdding()
    else if (t === "r") refreshRequested()
    else if (t === "[") stepRange(-1)
    else if (t === "]") stepRange(1)
    else if (t === "s") toggleStyle()
    else if (t === "o") cycleOrder()
    else if (t === "w") openListMenu()
    else return false
    return true
  }

  // The order and the change mode are separate settings; each click moves one.
  function cycleChangeMode() {
    showingHelp = false
    if (service) service.persist({ changeMode: Settings.nextChangeMode(changeMode) })
  }
  function setStyle(style) {
    showingHelp = false
    if (service) service.persist({ style: style })
  }
  function toggleStyle() { setStyle(retro ? "smooth" : "retro") }
  // Turned on, the add sound plays once, so you hear how loud they are.
  function toggleSounds() {
    showingHelp = false
    if (!service) return
    var on = !service.soundsOn
    service.persist({ sounds: on })
    if (on) sound("add")
  }
  function sound(name) {
    if (sounds) sounds.play(name)
  }
  function cycleOrder() {
    showingHelp = false
    if (service) service.setOrder(Settings.nextOrder(order))
  }
  // Manual has no direction: there it does nothing at all.
  function reverseOrder() {
    if (order === "manual") return
    showingHelp = false
    if (service) service.reverseOrder()
  }

  function featureSymbol(symbol) {
    showingHelp = false
    cancelAdding()
    if (service && symbol) service.feature(symbol)
  }

  function moveCursor(delta) {
    showingHelp = false
    watchlist.moveCursor(delta)
  }
  function moveCursorTo(index) {
    showingHelp = false
    watchlist.moveCursorTo(index)
  }

  // Delete, Backspace and x remove the selected row, but not one hidden
  // under the `?` sheet: there they only close it.
  function removeSelected() {
    if (showingHelp) showingHelp = false
    else removeRow(watchlist.cursorRow)
  }

  function moveSelected(delta) {
    showingHelp = false
    watchlist.moveSelected(delta)
  }

  // In All, removing a stock a named list holds too reaches that list, so
  // the row's menu asks first.
  function removeRow(symbol) {
    if (!service || !symbol) return
    if (listName === "" && listsHolding(symbol) > 1) openRowMenu(symbol, null)
    else removeFrom(symbol, listName === "")
  }

  function listsHolding(symbol) {
    return lists.filter(function(list) { return list.symbols.indexOf(symbol) >= 0 }).length
  }

  function removeFrom(symbol, everywhere) {
    if (!service) return
    showingHelp = false
    if (everywhere && !Settings.canRemove(lists[0].symbols)) {
      say("Keep at least one symbol")
      return
    }
    // The rows as shown, before what covers them closes, so the removal shows.
    var rows = watchlist.displayedSymbols
    var at = rows.indexOf(symbol)
    var successor = symbol === watchlist.cursorRow && at >= 0 ? (rows[at + 1] || rows[at - 1] || "") : ""
    if (everywhere && listName !== "") service.setMembership(symbol, "", false, rows)
    else service.removeSymbol(symbol, rows)
    closeViews()
    sound("remove")
    if (removal && removal.symbol === symbol) offerUndo()
    if (successor !== "") watchlist.handTo(successor)
  }

  readonly property var putBack: {
    if (!removal || members.indexOf(removal.symbol) >= 0) return null
    var was = Settings.listChoices(removal.before).filter(function(list) { return list.name === listName })[0]
    if (!was || was.symbols.indexOf(removal.symbol) < 0) return null
    var quote = removal.quote
    return { symbol: removal.symbol, name: quote ? quote.name : removal.symbol, exchange: quote ? quote.exchange : "" }
  }

  // `pointed`: put back by a click, as UNDO in search can be (`select`).
  function undoRemoval(pointed) {
    if (!service) return
    showingHelp = false
    if (!removal) {
      say("Nothing to undo")
      return
    }
    var symbol = removal.symbol
    service.undoRemoval(symbol)
    sound("undo")
    watchlist.select(symbol, pointed)
  }

  // Ctrl+Z works long after the offer goes, which lasts 5 s
  // (`TimedNote`).
  property var undoOffered: null
  onRemovalChanged: if (undoOffered !== null && removal !== undoOffered) endUndo()
  function offerUndo() {
    undoOffered = removal
    undoTime.hold()
  }
  function endUndo() {
    undoTime.reset()
    undoOffered = null
  }
  TimedNote {
    id: undoTime
    lasts: 5000
    says: root.undoOffered !== null
    hovered: footer.undoHovered
    surfaceOpen: root.surfaceOpen
    onEnded: root.endUndo()
  }

  // ---- The chart's range, scrub, replay and screenshot

  function selectRange(value) {
    showingHelp = false
    motion.clearScrub()
    if (service) service.setRange(value)
  }

  function stepRange(delta) {
    var index = rangeOptions.indexOf(range)
    var target = Math.max(0, Math.min(rangeOptions.length - 1, index + delta))
    if (target !== index) selectRange(rangeOptions[target])
  }

  function nudgeScrub(steps) {
    showingHelp = false
    var before = motion.scrubT
    motion.nudgeScrub(steps)
    if (motion.scrubT !== before) chime(true)
  }

  function endScrub() {
    if (!motion.replayRunning && !motion.scrubT) return false
    motion.clearScrub()
    return true
  }

  // The sounds keep the output awake a second after the scrub last moves,
  // for chimes.
  readonly property bool scrubbing: seen && motion.scrubT !== 0
  onScrubbingChanged: if (sounds) sounds.scrubMoved()
  onScrubTChanged: if (sounds && scrubbing) sounds.scrubMoved()

  property int chimed: -1
  // The pointer strikes a bar as it reaches it; each key step strikes, even
  // the same bar.
  function chime(again) {
    if (!sounds || motion.replayRunning) return
    var bar = ChartSound.barAt({ retro: retro, geometry: motion.geometry, grid: heroBand.pixelGrid,
      column: retro && motion.scrubX >= 0 ? heroBand.pixelColumnAt(motion.scrubX) : -1 }, motion.scrubX)
    if (bar !== chimed || again) sounds.chime(bar)
    chimed = bar
  }

  function replay() {
    showingHelp = false
    if (!sounds) return motion.replay()
    sounds.whenAwake(root, function() { if (root.surfaceOpen) motion.replay() })
  }

  // After a screenshot, the header's camera stays lit until the next open.
  property bool cameraLit: false
  function takeScreenshot() {
    showingHelp = false
    if (shareShot.busy) return
    // With no chart on show, the footer says why nothing was taken.
    if (!featuredQuote || !featuredDay || !featured) {
      say("No chart to take a screenshot of")
      return
    }
    shareShot.take({
      symbol: chartSymbol || featuredSymbol,
      quote: featuredQuote,
      day: featuredDay,
      history: historyShown ? history : null,
      marks: rangeMarks,
      latest: motion.latest,
      view: featured,
      scrubT: scrubShown,
      legend: scrubShown ? baselineText : "",
      changeMode: changeMode,
      range: historyShown ? chartRange : "1D",
      now: now,
      calendars: calendars,
      retro: retro,
      animalKind: animalKind,
      asleep: animal.asleep,
      foreground: foreground,
      ground: ground,
      upColor: upColor,
      downColor: downColor,
      fontFamily: fontFamily
    })
  }
  ShareShot {
    id: shareShot
    camera: root.camera
    onShutter: root.sound("shutter")
    onTold: function(words, saved) {
      if (saved) root.cameraLit = true
      root.say(words)
    }
  }

  // ---- The footer's notes, hint and notices

  // Why an action did nothing, or what a screenshot did, said in the
  // footer's place for 2.5 s (`TimedNote`). It waits while the pointer is
  // on it, so it never turns into the add under a click.
  property string note: ""
  function say(text) {
    note = text
    noteTime.hold()
  }

  function clearNote() {
    noteTime.reset()
    note = ""
  }

  // What a refusal covered fades in after it: a click meant for the note,
  // just after it went, would otherwise open search.
  TimedNote {
    id: noteTime
    objectName: "noteTime"
    lasts: 2500
    says: root.note !== ""
    hovered: footer.hovered
    surfaceOpen: root.surfaceOpen
    onEnded: {
      root.clearNote()
      footer.fadeIn()
    }
  }

  // The panel's first-run hint above the footer, cleared at the next open.
  property string hint: ""
  function showFirstRunHint() {
    hint = "Drag the pill in your bar to move it\nRight-click changes its look · middle-click opens the window"
  }

  readonly property string listsFile: "~/" + Settings.listsFile(service ? service.pluginId : "")

  readonly property string stillUnsaved: "Still not saved · your disk may be full"
  property bool savingAgain: false
  function saveAgain() {
    clearNote()
    savingAgain = true
    service.saveAgain()
  }
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onSaveChecked(saved) {
      if (!root.savingAgain) return
      root.savingAgain = false
      if (!saved) root.say(root.stillUnsaved)
    }
  }
  onSaveFailedChanged: if (!saveFailed && note === stillUnsaved) clearNote()

  // ---- Closing and opening again

  // A close drops a pending add, so nothing lands or glides during the fade
  // or after it.
  function freeze() {
    keepTyped()
    landing = ""
    unheardAdds = []
    noteTime.freeze()
    undoTime.freeze()
    footer.freeze()
    watchlist.takeOver()
    motion.freeze()
    watchlist.pauseRows()
    watchlist.releaseDragInPlace()
  }

  property var draft: null
  function keepTyped() {
    if (!service) return
    var typed, problem
    if (managingLists && manageLists && manageLists.renaming) {
      typed = manageLists.typedName
      problem = typed.trim() === "" ? "" : service.renameList(manageLists.pendingName, typed)
      if (problem !== "") draft = { list: manageLists.pendingName, key: service.listKey(manageLists.pendingName), text: typed, problem: problem }
    } else if (listMenuOpen && listMenu && listMenu.typedName.trim() !== "") {
      typed = listMenu.typedName
      problem = service.createList(typed)
      if (problem !== "") draft = { list: "", text: typed, problem: problem }
    } else if (adding && search && search.searchText.trim() !== "") {
      draft = { search: search.searchText }
    }
  }

  function resumeTyped() {
    var kept = draft
    draft = null
    if (!kept || !service) return
    if (kept.search !== undefined) {
      searchLoaded = true
      if (search) search.resumed = kept.search
      startAdding()
    } else if (kept.list !== "") {
      if (service.listKey(kept.list) !== kept.key) return
      openManageLists()
      if (manageLists) manageLists.resumeRename(kept.list, kept.text, kept.problem)
    } else {
      openListMenu()
      if (listMenu) listMenu.resumeNaming(kept.text, kept.problem)
    }
  }

  function resetInteraction() {
    closeViews()
    freeze()
    if (search) search.settle()
    if (manageLists) manageLists.settle()
    if (symbolLists) symbolLists.settle()
    if (rowMenuView) rowMenuView.settle()
    if (listMenu) listMenu.settle()
    if (helpSheet) helpSheet.settle()
    heldRowMenu = null
    heldListsSymbol = ""
    motion.reset()
    watchlist.reopen()
    watchlist.snapToRow()
    header.settle()
    heroBand.settle()
    clearNote()
    endUndo()
    cameraLit = false
    footer.settle()
    hint = ""
    resumeTyped()
  }

  // ---- The pieces

  // On the margins, not the words' edges: the longest closure status (a
  // holiday, the next open, its zone) needs the panel's whole width.
  Header {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: root.margins
    statusForms: root.headerLine.forms
    title: root.featured && root.featuredQuote ? root.featured.name : ""
    titled: root.fit.headerTitled
    offersRetry: root.headerLine.offersRetry
    look: root.look
    soundsOn: root.soundsOn
    cameraLit: root.cameraLit
    animal: root.animal
    seen: root.seen
    scrubbing: root.scrubT !== 0
    live: root.heroLive
    trouble: root.headerLine.trouble
    still: !root.surfaceOpen
    arrival: motion.arrival
    crossing: motion.crossing
    helpShown: root.showingHelp
    onStyleRequested: function(v) { root.setStyle(v) }
    onSoundsRequested: root.toggleSounds()
    onScreenshotRequested: root.takeScreenshot()
    onHelpRequested: root.toggleHelp()
    onReplayRequested: root.replay()
    onRang: function(woke) { if (woke) heroBand.opened() }
    onRetryRequested: root.refreshRequested()
  }

  HeroBand {
    id: heroBand
    calendars: root.calendars
    rowsDay: Figures.rowsDayName(root.rowsShared, root.minuteNow)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.leftMargin: root.textLeft
    anchors.rightMargin: root.textRight
    anchors.topMargin: root.groupGap
    bandGap: root.bandGap
    visible: !root.showingHelp
    freshness: root.featuredFreshness
    sourceDown: root.yahooDown
    look: root.look
    changeMode: root.changeMode
    scrubbing: root.scrubT !== 0
    live: root.heroLive
    still: !root.surfaceOpen
    seen: root.seen
    held: root.chartLoading
    dimmed: motion.dimmed
    // While the header says no prices come, the empty chart says why.
    waitingText: root.yahooDown && !root.featuredQuote ? "No price for " + root.featuredSymbol + " yet · Yahoo hasn't sent one"
      : root.yahooDown || !root.chartLoading ? "" : root.loadingText + "…"
    // Before any chart, the coming symbol, never a dash.
    symbol: root.chartSymbol || root.featuredSymbol
    nameOnLine: !root.fit.headerTitled
    view: root.featured
    quote: root.featuredQuote
    day: root.featuredDay
    latest: motion.latest
    geometry: root.featuredGeometry
    scrubX: root.scrubX
    reveal: motion.reveal
    replayX: motion.replayX
    morphFrom: motion.morphFrom
    morph: motion.morph
    beat: motion.beat
    arrival: motion.arrival
    chartHeight: Layout.chartHeight(root.measured, root.windowHeight())
    order: root.order
    reversed: root.reversed
    listLabel: root.listLabel
    breadth: root.breadth
    listMenuOpen: root.listMenuOpen
    rowsCovered: root.adding || root.listViewOpen
    replayRunning: motion.replayRunning
    rangeOptions: root.rangeOptions
    range: root.range
    periodLine: root.periodLine
    factLists: root.infoFactLists
    infoRanges: root.infoRanges
    rangeMarks: root.rangeMarks
    baselineText: root.baselineText
    yearLine: root.yearLine
    now: root.now
    changeCycles: !root.historyShown
    onChangeClicked: root.cycleChangeMode()
    onOrderClicked: root.cycleOrder()
    onOrderReverseClicked: root.reverseOrder()
    onListClicked: root.listMenuOpen ? root.closeListMenu() : root.openListMenu()
    onScrubRequested: function(fraction) {
      motion.scrubTo(fraction)
      root.chime(false)
    }
    onScrubCleared: if (root.surfaceOpen) motion.clearScrub()
    onSnapToNow: motion.clearScrub()
    onRangeRequested: function(value) { root.selectRange(value) }
  }

  Watchlist {
    id: watchlist
    calendars: root.calendars
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heroBand.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    height: root.rowsFit.listHeight
    sightHeight: root.rowsFit.sightHeight
    menuCovers: root.listMenuOpen && root.listMenu ? root.listMenu.y + root.listMenu.height - watchlist.y : 0
    held: root.rowMenu !== null
    visible: root.rowsShown
    view: root.view
    listKeys: root.listKeys
    quotes: root.quotes
    newestTrades: root.newestTrades
    nights: root.nights
    dayClock: root.dayClock
    entries: root.entries
    featuredSymbol: root.featuredSymbol
    scrubShown: root.watchlistScrubShown
    changeMode: root.changeMode
    now: root.now
    owed: root.owed
    asking: root.asking
    nightFailed: root.nightFailed
    look: root.look
    rowHeight: root.listRowHeight
    rowGap: root.rowGap
    gutter: root.gutter
    surfaceOpen: root.surfaceOpen
    seen: root.seen
    sourceDown: root.yahooDown
    // A turn later: the change that arranged the rows is still being told.
    onArranged: Qt.callLater(root.land)
    onSettlingChanged: Qt.callLater(root.featureLanding)
    onRowRested: Qt.callLater(root.featureLanding)
    onFeatureRequested: function(symbol) { root.featureSymbol(symbol) }
    onRemoveRequested: function(symbol) { root.removeRow(symbol) }
    onMenuRequested: function(symbol, x, y) { root.openRowMenu(symbol, Qt.point(x, y)) }
    onManualOrderRequested: function(symbols) {
      root.cancelAdding()
      if (root.service) root.service.setManualOrder(symbols)
    }
    onMoveRefused: root.say("Switch to manual order to move rows")
    onListsRequested: function(symbol) { root.openSymbolLists(symbol) }
    onPointerMoved: root.landingPointed = false
  }

  SearchFeed {
    id: searchFeed
    gate: root.service ? root.service.yahooGate : null
    mayAsk: root.service ? function() { return root.onScreen && root.service.screensClear() } : null
    active: !!root.search && root.search.active
    wanted: root.search ? root.search.searchText.trim() : ""
  }

  Loader {
    id: searchLoader
    active: root.searchLoaded || root.adding
    z: 5
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heroBand.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    anchors.bottomMargin: root.margins
    sourceComponent: SymbolSearch {
      objectName: "symbolSearch"
      anchors.fill: parent
      open: root.adding
      seen: root.seen
      still: !root.surfaceOpen
      feed: searchFeed
      active: root.adding && root.surfaceOpen
      look: root.look
      gutter: root.gutter
      // Short, so a list's name fits the panel's field.
      placeholder: root.listName !== "" ? "Symbol or company for " + root.listName + "…" : "Symbol or company…"
      members: root.members
      own: root.ownFound
      putBack: root.putBack
      filling: root.filling
      onPicked: function(symbol, pointed) { root.acceptSymbol(symbol, pointed) }
      onChose: function(symbol, result) { root.previewTo(symbol, result) }
      onCancelled: root.cancelAdding()
    }
  }

  Loader {
    id: manageListsLoader
    active: root.manageListsLoaded || root.managingLists
    z: 5
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heroBand.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    anchors.bottomMargin: root.margins
    sourceComponent: ManageLists {
      objectName: "manageLists"
      anchors.fill: parent
      open: root.managingLists
      seen: root.seen
      still: !root.surfaceOpen
      active: root.managingLists && root.surfaceOpen
      choices: root.lists
      look: root.look
      gutter: root.gutter
      onRenameRequested: function(name, newName) { root.renameList(name, newName) }
      onMoveRequested: function(name, delta) { if (root.service) root.service.moveList(name, delta) }
      onDeleteRequested: function(name) { if (root.service) root.service.deleteList(name) }
      onDismissed: root.closeListViews()
    }
  }

  Loader {
    id: symbolListsLoader
    active: root.symbolListsLoaded || root.listsSymbol !== ""
    z: 5
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heroBand.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    anchors.bottomMargin: root.margins
    sourceComponent: SymbolLists {
      id: symbolListsItem
      objectName: "symbolLists"
      anchors.fill: parent
      open: root.listsSymbol !== ""
      seen: root.seen
      still: !root.surfaceOpen
      active: root.listsSymbol !== "" && root.surfaceOpen
      readonly property string shownSymbol: root.listsSymbol !== "" ? root.listsSymbol : root.heldListsSymbol
      onVisibleChanged: if (!visible && root.listsSymbol === "") root.heldListsSymbol = ""
      choices: root.lists
      symbol: shownSymbol
      symbolName: shownSymbol && root.quotes[shownSymbol] ? root.quotes[shownSymbol].name : ""
      note: root.note
      look: root.look
      gutter: root.gutter
      onToggled: function(name, member) { root.setMembership(name, member) }
      onCreateRequested: function(name) {
        var problem = root.service ? root.service.createList(name, root.listsSymbol) : ""
        if (problem !== "") symbolListsItem.problem = problem
        else symbolListsItem.stopNaming()
      }
      onDismissed: root.closeListViews()
    }
  }

  // A closing surface keeps its rows, so it says nothing.
  Text {
    visible: root.members.length === 0 && watchlist.displayedSymbols.length === 0 && root.rowsShown
    x: root.margins
    y: watchlist.y
    width: root.width - root.margins * 2 - root.gutter
    height: root.listRowHeight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    text: "No symbols in " + root.listLabel + " yet"
    color: root.look.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  // It rides the panel's easing edge, carrying the surface's ground over the
  // rows and the empty list's line, so its words never cross a row.
  Footer {
    id: footer
    objectName: "footer"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    y: root.edge - root.margins - height
    visible: root.rowsShown
    look: root.look
    seen: root.seen
    still: !root.surfaceOpen
    gutter: root.gutter
    rowHeight: root.rowHeight
    note: root.note
    noteOpacity: noteTime.shown
    notice: root.footerSays.text
    noticeActions: root.footerSays.actions
    hint: root.hint
    showsHint: root.fit.hintShown
    // The same on every list: the list's name is already at its top.
    label: "+  Find or add a symbol"
    acts: !root.footerSays.unreadable
    undoLabel: root.undoOffered ? "Undo " + root.undoOffered.symbol : ""
    undoOpacity: undoTime.shown
    onUndoClicked: root.undoRemoval()
    updateLabel: root.footerSays.updateOffer !== "" ? "Update to " + root.footerSays.updateOffer : ""
    onUpdateClicked: {
      if (root.service) root.service.flushSave()
      root.updates.update(root.footerSays.restartable)
    }
    onClicked: {
      if (root.footerSays.unreadable) return
      else if (root.saveFailed) root.saveAgain()
      else if (root.note === "" && root.footerSays.updatedTo !== "") root.requestRestart()
      else root.startAdding()
    }
  }

  // Ground backing while HelpSheet fades out so the hero and rows underneath
  // emerge cleanly without overlapping words.
  Rectangle {
    anchors.fill: helpSheetLoader
    z: 5
    visible: !!root.helpSheet && root.helpSheet.visible && !root.showingHelp
    opacity: root.helpSheet ? root.helpSheet.opacity : 0
    color: root.ground
  }

  Loader {
    id: helpSheetLoader
    active: root.helpSheetLoaded || root.showingHelp
    z: 6
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    anchors.bottomMargin: root.margins
    sourceComponent: HelpSheet {
      objectName: "helpSheet"
      anchors.fill: parent
      shown: root.showingHelp
      seen: root.seen
      still: !root.surfaceOpen
      inset: root.inset
      edge: root.gutter + root.inset
      sheet: root.keySheet
      version: root.updates && root.updates.runningVersion || ""
      look: root.look
      onCloseRequested: root.showingHelp = false
    }
  }

  // Hover passes, so nothing under the pointer changes as the card fades.
  MouseArea {
    anchors.fill: parent
    z: 20
    visible: !root.surfaceOpen
    acceptedButtons: Qt.AllButtons
    onWheel: function(wheel) { wheel.accepted = true }
  }

  MouseArea {
    anchors.fill: parent
    visible: root.listMenuOpen
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    z: 9
    onClicked: root.listMenu && root.listMenu.typedName.trim() !== "" ? root.createList(root.listMenu.typedName) : root.closeListMenu()
    onWheel: function(wheel) { wheel.accepted = true }
  }

  MouseArea {
    anchors.fill: parent
    visible: root.rowMenu !== null
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    z: 9
    onClicked: function(mouse) {
      var at = mapToItem(null, mouse.x, mouse.y)
      if (watchlist.clickCounts(at.x, at.y, false)) root.rowMenu = null
    }
    onWheel: function(wheel) { wheel.accepted = true }
  }

  Loader {
    id: rowMenuLoader
    active: root.rowMenuLoaded || root.rowMenu !== null
    z: 10
    sourceComponent: RowMenu {
      objectName: "rowMenu"
      open: root.rowMenu !== null
      seen: root.seen
      still: !root.surfaceOpen
      active: root.rowMenu !== null && root.surfaceOpen
      readonly property var menu: root.rowMenu || root.heldRowMenu
      onVisibleChanged: if (!visible && root.rowMenu === null) root.heldRowMenu = null
      maxWidth: root.width - root.margins * 2
      x: menu ? Math.max(root.margins, Math.min(menu.x, root.width - root.margins - width)) : 0
      y: !menu ? 0 : menu.below + height <= root.edge - root.margins ? menu.below
        : Math.max(root.margins, menu.above - height)
      lines: menu ? menu.lines.map(function(line) { return line.label }) : []
      startLine: menu ? menu.startLine : -1
      look: root.look
      onTaken: function(index) { root.takeRowMenu(index) }
      onDismissed: root.rowMenu = null
    }
  }

  Loader {
    id: listMenuLoader
    active: root.listMenuLoaded || root.listMenuOpen
    z: 10
    sourceComponent: ListMenu {
      objectName: "listMenu"
      open: root.listMenuOpen
      seen: root.seen
      still: !root.surfaceOpen
      active: root.listMenuOpen && root.surfaceOpen
      x: root.margins
      y: root.fit.listMenuTop
      maxHeight: root.rowsFit.listMenuRoom
      choices: root.lists
      current: root.listName
      look: root.look
      onChosen: function(name) { root.chooseList(name) }
      onCreateRequested: function(name) { root.createList(name) }
      onManageRequested: root.openManageLists()
      onDismissed: root.closeListMenu()
    }
  }

  ChartMotion {
    id: motion
    view: root.view
    surfaceOpen: root.surfaceOpen
    onScreen: root.seen
    retro: root.retro
    calendars: root.calendars
    // Made from the chart as drawn in the look on screen.
    onReplayStarted: function(from, to) {
      if (root.sounds) root.sounds.playReplay(root, { geometry: motion.geometry, grid: heroBand.pixelGrid,
        from: from, to: to, seconds: motion.replayDuration / 1000 })
    }
    onReplayCut: if (root.sounds) root.sounds.stopReplay(root)
    onScrubTChanged: if (!scrubT) root.chimed = -1
  }
}
