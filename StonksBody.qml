import QtQuick
import qs.Commons
import qs.Commons as Commons
import "ChartSound.js" as ChartSound
import "Figures.js" as Figures
import "Freshness.js" as Freshness
import "Format.js" as Format
import "Fundamentals.js" as Fundamentals
import "History.js" as History
import "KeySheet.js" as KeySheet
import "KeyText.js" as KeyText
import "Market.js" as Market
import "Overnight.js" as Overnight
import "Quote.js" as Quote
import "Release.js" as Release
import "Search.js" as Search
import "Settings.js" as Settings
import "Share.js" as Share
import "Motion.js" as Motion
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
  // The panel's: the pill it opened from, whose form `b` changes.
  property var pill: null
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

  // False holds the animal's fidget still.
  property bool screenOn: true

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
  readonly property alias search: search
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
  // the surface is closed; and the clock that slides its start, held still
  // while no screen shows the surface.
  property var nights: ({})
  property var allDay: ({})
  property int slideAt: 0
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
  // The view, its chart rebuilt as the clock slides 1D's start, holds still
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
  Binding on allDay { when: root.reading; value: root.service?.allDay; restoreMode: Binding.RestoreNone }
  Binding on nightFailed { when: root.reading; value: root.service?.nightFailed; restoreMode: Binding.RestoreNone }
  Binding on slideAt { when: root.showing; value: root.service?.viewSlideAt ?? 0; restoreMode: Binding.RestoreNone }
  Binding on previewEntries { when: root.reading; value: root.service?.previewEntries; restoreMode: Binding.RestoreNone }
  Binding on fundamentalEntries { when: root.reading; value: root.service?.fundamentals; restoreMode: Binding.RestoreNone }
  Binding on rates { when: root.reading; value: root.service?.rates; restoreMode: Binding.RestoreNone }
  Binding on histories { when: root.reading; value: root.service?.histories; restoreMode: Binding.RestoreNone }
  Binding on lists { when: root.reading; value: root.service?.lists; restoreMode: Binding.RestoreNone }
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

  readonly property var calendars: service ? service.calendars : null
  readonly property var symbols: view.rows
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

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPreviewTaken(surface) { if (surface === root) root.cancelAdding() }
    function onScreensReady() { searchFeed.sendWaiting() }
    function onYahooBack() { if (root.onScreen) search.yahooBack() }
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
  // highs, on every range held for the stock, so a range change moves
  // nothing. A range first fetched with more digits than any held widens it
  // once.
  readonly property var dayLine: chart ? Figures.dayLine(featuredQuote, featuredToday, featuredDay) : null
  // The trades Stonks shows for the stock, beyond Yahoo's bars and figures:
  // the 1D chart's, tonight's too, and the newest. The ranges and the 52W
  // line take them in, so none reads under the day.
  readonly property var shownTrades: (featuredDay ? featuredDay.trades || featuredDay.points : []).concat(featuredNewest ? [featuredNewest] : [])
  readonly property var rangeEnds: historyShown ? History.rangeEnds(history, historyStats, featuredQuote, shownTrades) : null
  readonly property var periodLine: !chart ? null : historyShown ? History.rangeLine(history, rangeEnds, featuredQuote) : dayLine
  readonly property var heldLines: chart ? History.heldLines(histories, chartSymbol, featuredQuote, shownTrades) : []
  readonly property var infoFactLists: !dayLine ? [] : [dayLine.facts, History.rangeFacts(dayLine.range.widest)]
    .concat(yearLine ? [History.rangeFacts(yearLine.range.widest)] : [])
    .concat(heldLines.map(function(line) { return line.facts }))
  readonly property var infoRanges: !dayLine ? [] : [dayLine.range].concat(heldLines.map(function(line) { return line.range }))
  readonly property var yearLine: chart ? Fundamentals.yearLine(featuredQuote, fundamentalsEntry ? fundamentalsEntry.fundamentals : null,
    historyShown && history.range === "1Y" ? rangeEnds : null, rates, shownTrades) : null
  readonly property var rangeMarks: historyShown ? History.rangeMarks(history, rangeEnds, featuredQuote,
    function(t) { return Market.tradeClock(featuredQuote, t, calendars) }) : null
  // Said under the price: what a scrub's move counts from, the dashed line
  // under the pointer, or since the open the day's open.
  readonly property string baselineText: historyShown ? "┄ " + chartRange.toUpperCase() + " START " + Format.money(history.baseline, featuredQuote ? featuredQuote.priceDigits : undefined)
    : (!historyActive && featuredDay ? Figures.scrubLegend(featuredDay, scrubShown, Figures.exchangeDay(featuredDay, now), calendars, changeMode, featuredNewest) : "")

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
    var allDay = !!chart && chart.allDay
    var asleep = Overnight.marketAsleep(featuredQuote, allDay, now, calendars)
    var before = Overnight.marketAsleep(featuredQuote, allDay, now - bellWindow, calendars)
    return asleep ? (before ? 1 : 2) : (before ? 4 : 0)
  }
  readonly property var animal: ({ kind: animalKind, chart: animalChart,
    asleep: animalSleep === 1 || animalSleep === 2, bell: animalSleep === 2 || animalSleep === 4, scrubbed: animalSleep === 3 })

  // ---- The rows

  // The rows follow a scrub of the day. They stay on now for a range and for
  // hours outside Yahoo's day, but not the coming day's pre-market, which
  // each row's quote holds too. The quote can change before the day does:
  // until the day comes, the scrub stands.
  readonly property var featuredTail: featuredQuote ? Quote.tailStart(featuredQuote) : null
  readonly property int watchlistScrubShown: historyActive || !featuredQuote || scrubShown < Quote.dayStart(featuredQuote)
    || (!!featuredDay && !!featuredDay.axis && scrubShown >= Quote.dayEnd(featuredQuote)
      && !(featuredTail !== null && scrubShown >= featuredTail)) ? 0 : scrubShown

  // Read from the view: `symbols` may lag a switch.
  readonly property var breadth: Object.assign({ list: view.list },
    Figures.listBreadth(view.rows, quotes, watchlistScrubShown, changeMode, newestTrades))

  // ---- The header's words

  readonly property int warnings: lists.length > 0 ? lists[0].symbols.filter(function(symbol) {
    return Freshness.freshnessWarns(Freshness.freshness(entryOf(symbol), quotes[symbol] || null, now, owed[symbol] || 0, !!asking[symbol]))
  }).length : 0
  readonly property bool yahooDown: warnings > 0 && warnings === lists[0].symbols.length
  readonly property var hostPause: Freshness.hostPause(yahooPause.pause, yahooPause.until, now)

  readonly property string unavailableText: chartRange.toUpperCase() + " unavailable"
  readonly property bool offersRetry: headerText === unavailableText
  readonly property string loadingText: "Loading" + (featuredSymbol ? " " + featuredSymbol + (range !== "1D" ? " " + range : "") : "")
  readonly property var marketForms: featuredQuote ? Market.statusForms(dayScrubbed ? featuredDay : featuredQuote, now, scrubShown, calendars,
    Overnight.nightTrades(featuredQuote, !!chart && chart.allDay, now, calendars)) : []
  // The panel says Yahoo's pause short; the window has room for a sentence.
  readonly property var troubleForms: {
    if (!service || scrubShown || refreshing || (historyActive && historyFailed)) return null
    if (hostPause && warnings > 0) return switchesPanels ? hostPause.forms.slice(1) : hostPause.forms
    if (yahooDown) return ["Can't get prices · Stonks keeps trying", "Can't get prices"]
    if (featuredQuote && featuredFreshness.state === "failed")
      return ["Refresh failed for " + (chartSymbol || featuredSymbol) + " · Retrying", "Refresh failed · Retrying", "Refresh failed"]
    return null
  }
  readonly property var headerForms: {
    if (!service) return [headerWhenMissing]
    if (troubleForms) return troubleForms
    // Before any chart, only the empty hero names what's loading.
    if (chartLoading) return [chart ? loadingText : ""]
    // A refresh you asked for is said while out, unless a scrub reads a moment.
    if (refreshing && !scrubShown) return ["Refreshing"]
    if (historyActive && historyFailed) return [unavailableText]
    // A refetch the service makes itself says nothing, out or failed.
    if (historyShown && historyBar) return History.historyScrubForms(history, historyBar, featuredQuote ? featuredQuote.priceDigits : undefined)
    if (featuredQuote) return marketForms
    return [headerWhenMissing]
  }
  readonly property string headerText: headerForms[0] || ""

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
  readonly property int rowPitch: listRowHeight + rowGap
  readonly property int threeRowsHeight: 3 * rowPitch - rowGap

  readonly property int chromeBesideHeader: margins * 2 + heroBand.heightBesideChart + footer.barHeight + groupGap * 3
  readonly property int chromeBesideScreenChart: chromeBesideHeader + header.height
  // The title gives way after the chart: where three rows won't fit beside
  // the least chart, the header is the status words alone.
  readonly property bool headerTitled: screenRoom <= 0
    || chromeBesideHeader + header.titledHeight + leastScreenChart + threeRowsHeight <= screenRoom
  // From the screen's room, never the card's, which fits the chart.
  readonly property int leastScreenChart: Math.round(chartHeight / 5)
  readonly property int screenChartHeight: screenRoom <= 0 ? chartHeight
    : Math.max(leastScreenChart, Math.min(chartHeight, screenRoom - chromeBesideScreenChart - threeRowsHeight))
  // The hint gives way, after the chart, where it would leave fewer than
  // three rows: read from the screen's room, never the card's, which fits
  // the footer.
  readonly property bool hintShown: hint !== "" && (screenRoom <= 0
    || chromeBesideScreenChart + screenChartHeight + footer.hintRoom + threeRowsHeight <= screenRoom)

  readonly property int chromeHeight: chartFitsSurface ? chromeBesideChart + shownChartHeight
    : margins * 2 + header.height + heroBand.implicitHeight + footer.height + groupGap * 3
  readonly property int chromeBesideChart: margins * 2 + header.height + heroBand.heightBesideChart + footer.height + groupGap * 3
  // The window's chart is sized from the surface and the chrome beside it,
  // never the list or itself, so a list switch moves nothing.
  readonly property bool chartFitsSurface: minChartHeight > 0 && minChartHeight < chartHeight
  readonly property int roomBesideChart: height - chromeBesideChart - chartHeight
  readonly property int shownChartHeight: roomBesideChart < threeRowsHeight
    ? chartHeight - Math.min(chartHeight - minChartHeight, threeRowsHeight - roomBesideChart)
    : chartHeight + roomBesideChart - rowsHeight(Infinity, roomBesideChart)
  // Counted from the rows, not the chart's give: at a larger text size each
  // rounds on its own (275 less 170 is not two 53 px rows).
  readonly property int smallestHeight: chartFitsSurface ? chromeBesideChart + minChartHeight + threeRowsHeight
    : chromeBesideChart + chartHeight + listRowHeight
  readonly property int helpHeight: margins * 2 + header.height + groupGap + helpSheet.contentHeight
  readonly property int searchHeight: margins * 2 + header.height + heroBand.implicitHeight
    + groupGap * 2 + search.desiredHeight
  readonly property int wholeListHeight: wholeRowsHeight(height - chromeHeight)

  readonly property int rowsSightHeight: rowsRoom > 0 ? wholeRowsHeight(rowsRoom - chromeHeight) : wholeListHeight
  readonly property int listMenuTop: margins + header.height + groupGap + heroBand.implicitHeight + Style.space(4)
  // The menu ends one gap above the footer, which stays in sight under it.
  readonly property int listMenuBottom: listMenuTop + listMenu.contentHeight + groupGap + footer.height + margins
  readonly property int listMenuLeastBottom: listMenuTop + listMenu.leastHeight + groupGap + footer.height + margins
  readonly property int listViewHeight: margins * 2 + header.height + heroBand.implicitHeight + groupGap * 2
    + (managingLists ? manageLists.contentHeight : symbolLists.contentHeight)

  function rowsHeight(count, space) {
    var rows = Math.min(count, Math.floor((Math.max(0, space) + rowGap) / rowPitch))
    return rows > 0 ? rows * rowPitch - rowGap : 0
  }

  function wholeRowsHeight(space) {
    return rowsHeight(listName !== "" ? Math.max(1, symbols.length) : symbols.length, space)
  }

  function fittedHeight(maxHeight) {
    var rows = chromeHeight + wholeRowsHeight(maxHeight - chromeHeight)
    // The sheet keeps the rows' height, so opening it moves nothing, and
    // grows the panel only past rows shorter than itself.
    if (showingHelp) return Math.max(rows, Math.min(maxHeight, helpHeight))
    var view = listViewOpen ? listViewHeight : adding ? searchHeight : listMenuOpen ? listMenuBottom : 0
    var least = listMenuOpen ? Math.min(maxHeight, listMenuLeastBottom) : 0
    return Math.max(rows, least, Math.min(chromeHeight + rowsHeight(Infinity, maxHeight - chromeHeight), view))
  }

  // ---- What is open over the rows

  property bool adding: false
  property string previewSymbol: ""
  property bool showingHelp: false
  property bool listMenuOpen: false
  property bool managingLists: false
  property string listsSymbol: ""
  property var rowMenu: null
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
    if (managingLists && manageLists.renaming) manageLists.keepName()
    return !(managingLists && manageLists.renaming)
  }

  function toggleHelp() {
    if (!keepRename()) return
    var shown = showingHelp
    closeViews()
    showingHelp = !shown
    if (showingHelp) helpSheet.contentY = 0
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
  // shows at rest. Asked only while search is open.
  readonly property var ownFound: adding ? Search.ownMatches(search.searchText, members, quotes).map(function(symbol) {
    var quote = quotes[symbol]
    var row = quote ? Figures.listRow(quote, 0, changeMode, newestTrades[symbol] || null) : null
    return { symbol: symbol, name: quote ? quote.name : "", exchange: quote ? quote.exchange : "",
      move: row ? Format.lookSigns(row.changeLine, retro) : "", tone: row ? row.tone : "flat" }
  }) : []

  function startAdding() {
    if (!keepRename()) return
    closeViews()
    adding = true
  }

  // An add joins the rows once its first answer is in, and is featured once
  // it and the list rest. A result already in the list is shown, not added.
  function acceptSymbol(symbol, pointed) {
    if (!service) return
    var s = String(symbol || "").trim().toUpperCase()
    if (view.rows.indexOf(s) >= 0) {
      showSymbol(s, pointed)
      return
    }
    if (putBack && s === putBack.symbol) {
      cancelAdding()
      undoRemoval(pointed)
      return
    }
    var member = members.indexOf(s) >= 0
    adding = false
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
      var joined = unheardAdds.filter(function(a) { return service.arriving.indexOf(a) < 0 && view.rows.indexOf(a) >= 0 })
      if (joined.length) sound("add")
      var still = unheardAdds.filter(function(a) { return joined.indexOf(a) < 0 && members.indexOf(a) >= 0 })
      if (still.length !== unheardAdds.length) unheardAdds = still
    }
    if (landing === "" || !service || service.arriving.indexOf(landing) >= 0) return
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
    if (problem !== "") { listMenu.problem = problem; return }
    startAdding()
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
  onViewChanged: if (listsSymbol !== "" && view.allSymbols.indexOf(listsSymbol) < 0) listsSymbol = ""

  function renameList(name, newName) {
    if (!service) return
    var problem = service.renameList(name, newName)
    if (problem !== "") manageLists.problem = problem
    else manageLists.stopEditing()
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

  // The keys both surfaces answer; each reads Esc, and the panel Tab, itself.
  function pressKey(event) {
    var key = event.key
    var mods = event.modifiers & ~Qt.KeypadModifier
    // A letter's command is its key and Shift, never its text: Caps Lock
    // sends "O" for o, which would reverse the order.
    var t = KeyText.typed(event)
    if (mods === Qt.ControlModifier && key === Qt.Key_C) takeScreenshot()
    else if (mods === Qt.ControlModifier && key === Qt.Key_Z) undoRemoval()
    else if (mods === Qt.ControlModifier && key === Qt.Key_Up) moveSelected(-1)
    else if (mods === Qt.ControlModifier && key === Qt.Key_Down) moveSelected(1)
    else if (mods === Qt.ControlModifier && (key === Qt.Key_Return || key === Qt.Key_Enter)) openSymbolLists(watchlist.cursorRow)
    else if (key === Qt.Key_Up) moveCursor(-1)
    else if (key === Qt.Key_Down) moveCursor(1)
    else if (key === Qt.Key_Left) nudgeScrub(-1)
    else if (key === Qt.Key_Right) nudgeScrub(1)
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) featureSymbol(watchlist.cursorRow)
    else if (key === Qt.Key_Delete || key === Qt.Key_Backspace) removeRow(watchlist.cursorRow)
    else if (t === "?") toggleHelp()
    else if (t === "a" || t === "/") startAdding()
    else if (t === "c") cycleChangeMode()
    else if (t === "r") refreshRequested()
    else if (t === "[") stepRange(-1)
    else if (t === "]") stepRange(1)
    else if (t === "p") replay()
    else if (t === "s") toggleStyle()
    else if (t === "m") toggleSounds()
    else if (t === "o") cycleOrder()
    else if (t === "O") reverseOrder()
    else if (t === "U") runOffered()
    else if (t === "w") openListMenu()
    else if (t === "b" && pill) pill.cycleBarStyle()
    else return false
    return true
  }

  // The order and the change mode are separate settings; each key moves one.
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

  // Ctrl+Z works long after the offer goes. Its time waits while the
  // pointer is on it.
  property var undoOffered: null
  property real undoShown: 1
  onRemovalChanged: if (undoOffered !== null && removal !== undoOffered) endUndo()
  function offerUndo() {
    undoOffered = removal
    holdUndo()
  }
  function holdUndo() {
    undoFade.stop()
    undoShown = 1
    if (undoOffered !== null && surfaceOpen && !footer.undoHovered) undoTimer.restart()
    else undoTimer.stop()
  }
  function endUndo() {
    undoTimer.stop()
    undoFade.stop()
    undoShown = 1
    undoOffered = null
  }
  Timer {
    id: undoTimer
    interval: 5000 - undoFade.duration
    onTriggered: undoFade.start()
  }
  NumberAnimation {
    id: undoFade
    target: root
    property: "undoShown"
    from: 1
    to: 0
    duration: Motion.duration(Style, 600)
    onFinished: root.endUndo()
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
    if (!camera || camera.busy || String(shareLoader.source) !== "") return
    // With no chart on show, the footer says why nothing was taken.
    if (!featuredQuote || !featuredDay || !featured) {
      say("No chart to take a screenshot of")
      return
    }
    shareLoader.setSource("ShareCard.qml", {
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
  // The other surface may take the camera while this card waits: then this
  // card goes.
  function shootCard(card) {
    var shown = Share.subject(card.symbol, card.range, card.words ? card.words.said : "")
    var taken = camera.shoot(card, Share.fileSymbol(card.symbol), function() {
      shareLoader.source = ""
      // As the picture is taken; the footer says after how the save went.
      sound("shutter")
    }, function(code) {
      shareLoader.source = ""
      if (code === 1) return say("Screenshot not saved · the screenshots folder can't be written")
      cameraLit = true
      say(code === 0 ? "Copied a screenshot of " + shown : "Saved a screenshot of " + shown + " · copying it failed")
    })
    if (!taken) shareLoader.source = ""
  }

  // ---- The footer's notes, hint and notices

  // Why an action did nothing, or what a screenshot did, said in the
  // footer's place for a moment.
  property string note: ""
  function say(text) {
    note = text
    holdNote()
  }

  // The note waits while the pointer is on it, so it never turns into the
  // add under a click. A closed surface's note stays as the close left it.
  function holdNote() {
    if (!surfaceOpen) {
      noteTimer.stop()
      return
    }
    noteFade.stop()
    noteShown = 1
    if (note !== "" && surfaceOpen && !footer.hovered) noteTimer.restart()
    else noteTimer.stop()
  }

  function clearNote() {
    noteTimer.stop()
    noteFade.stop()
    noteShown = 1
    note = ""
  }

  // What a refusal covered fades in after it: a click meant for the note,
  // just after it went, would otherwise open search.
  property real noteShown: 1
  Timer {
    id: noteTimer
    interval: 2500 - noteFade.duration
    onTriggered: noteFade.start()
  }
  NumberAnimation {
    id: noteFade
    target: root
    property: "noteShown"
    from: 1
    to: 0
    duration: Motion.duration(Style, 600)
    onFinished: {
      root.clearNote()
      footer.fadeIn()
    }
  }

  // The panel's first-run hint above the footer, cleared at the next open.
  property string hint: ""
  function showFirstRunHint() {
    hint = "Drag the pill in your bar to move it\nMiddle-click changes its look · right-click opens the window"
  }

  readonly property string listsFile: "~/" + Settings.listsFile(service ? service.pluginId : "")
  function runOffered() {
    if (!updates) return
    if (footerSays.restartOffered) updates.restart()
    else if (footerSays.updateOffer !== "") updates.update(footerSays.restartable)
    else say("Nothing to update")
  }

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
    noteTimer.stop()
    noteFade.stop()
    undoTimer.stop()
    undoFade.stop()
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
    if (managingLists && manageLists.renaming) {
      typed = manageLists.typedName
      problem = typed.trim() === "" ? "" : service.renameList(manageLists.pendingName, typed)
      if (problem !== "") draft = { list: manageLists.pendingName, key: service.listKey(manageLists.pendingName), text: typed, problem: problem }
    } else if (listMenuOpen && listMenu.typedName.trim() !== "") {
      typed = listMenu.typedName
      problem = service.createList(typed)
      if (problem !== "") draft = { list: "", text: typed, problem: problem }
    } else if (adding && search.searchText.trim() !== "") {
      draft = { search: search.searchText }
    }
  }

  function resumeTyped() {
    var kept = draft
    draft = null
    if (!kept || !service) return
    if (kept.search !== undefined) {
      search.resumed = kept.search
      startAdding()
    } else if (kept.list !== "") {
      if (service.listKey(kept.list) !== kept.key) return
      openManageLists()
      manageLists.resumeRename(kept.list, kept.text, kept.problem)
    } else {
      openListMenu()
      listMenu.resumeNaming(kept.text, kept.problem)
    }
  }

  function resetInteraction() {
    closeViews()
    freeze()
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
    statusForms: root.headerForms
    title: root.featured && root.featuredQuote ? root.featured.name : ""
    titled: root.headerTitled
    offersRetry: root.offersRetry
    look: root.look
    soundsOn: root.soundsOn
    cameraLit: root.cameraLit
    animal: root.animal
    seen: root.seen && root.screenOn
    scrubbing: root.scrubT !== 0
    live: root.heroLive
    trouble: !!root.troubleForms
    still: !root.surfaceOpen
    helpShown: root.showingHelp
    onStyleRequested: function(v) { root.setStyle(v) }
    onSoundsRequested: root.toggleSounds()
    onScreenshotRequested: root.takeScreenshot()
    onHelpRequested: root.toggleHelp()
    onReplayRequested: root.replay()
    onRetryRequested: root.refreshRequested()
  }

  HeroBand {
    id: heroBand
    calendars: root.calendars
    rowsDay: Figures.rowsDay(root.view.rows, root.quotes, root.newestTrades, root.now, root.calendars)
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
    held: root.chartLoading
    dimmed: motion.dimmed
    // While the header says no prices come, the empty chart says why.
    waitingText: root.yahooDown && !root.featuredQuote ? "No price for " + root.featuredSymbol + " yet · Yahoo hasn't sent one"
      : root.yahooDown || !root.chartLoading ? "" : root.loadingText + "…"
    // Before any chart, the coming symbol, never a dash.
    symbol: root.chartSymbol || root.featuredSymbol
    nameOnLine: !root.headerTitled
    view: root.featured
    quote: root.featuredQuote
    day: root.featuredDay
    latest: motion.latest
    geometry: root.featuredGeometry
    scrubX: root.scrubX
    reveal: motion.reveal
    replayX: motion.replayX
    chartHeight: root.chartFitsSurface ? root.shownChartHeight : root.screenChartHeight
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
    height: root.wholeListHeight
    sightHeight: root.rowsSightHeight
    menuCovers: root.listMenuOpen ? listMenu.y + listMenu.height - watchlist.y : 0
    held: root.rowMenu !== null
    visible: root.rowsShown
    view: root.view
    listKeys: root.service && root.service.listKey ? root.service.lists.map(function(list) { return root.service.listKey(list.name) }) : []
    quotes: root.quotes
    newestTrades: root.newestTrades
    nights: root.nights
    allDay: root.allDay
    slideAt: root.slideAt
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
    active: search.active
    wanted: search.searchText.trim()
  }

  SymbolSearch {
    id: search
    objectName: "symbolSearch"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heroBand.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    anchors.bottomMargin: root.margins
    visible: root.adding
    feed: searchFeed
    active: root.adding && root.surfaceOpen
    look: root.look
    gutter: root.gutter
    // Short, so a list's name fits the panel's field.
    placeholder: root.listName !== "" ? "Symbol or company for " + root.listName + "…" : "Symbol or company…"
    members: root.members
    own: root.ownFound
    putBack: root.putBack
    onPicked: function(symbol, pointed) { root.acceptSymbol(symbol, pointed) }
    onChose: function(symbol, result) { root.previewTo(symbol, result) }
    onCancelled: root.cancelAdding()
  }

  ManageLists {
    id: manageLists
    objectName: "manageLists"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heroBand.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    anchors.bottomMargin: root.margins
    visible: root.managingLists
    active: root.managingLists && root.surfaceOpen
    choices: root.lists
    look: root.look
    gutter: root.gutter
    onRenameRequested: function(name, newName) { root.renameList(name, newName) }
    onMoveRequested: function(name, delta) { if (root.service) root.service.moveList(name, delta) }
    onDeleteRequested: function(name) { if (root.service) root.service.deleteList(name) }
    onDismissed: root.closeListViews()
  }

  SymbolLists {
    id: symbolLists
    objectName: "symbolLists"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heroBand.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    anchors.bottomMargin: root.margins
    visible: root.listsSymbol !== ""
    active: root.listsSymbol !== "" && root.surfaceOpen
    choices: root.lists
    symbol: root.listsSymbol
    symbolName: root.quotes[root.listsSymbol] ? root.quotes[root.listsSymbol].name : ""
    note: root.note
    look: root.look
    gutter: root.gutter
    onToggled: function(name, member) { root.setMembership(name, member) }
    onDismissed: root.closeListViews()
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
    gutter: root.gutter
    rowHeight: root.rowHeight
    note: root.note
    noteOpacity: root.noteShown
    notice: root.footerSays.text
    noticeActions: root.footerSays.actions
    hint: root.hint
    showsHint: root.hintShown
    // The same on every list: the list's name is already at its top.
    label: "+  Find or add a symbol"
    acts: !root.footerSays.unreadable
    onHoveredChanged: root.holdNote()
    undoLabel: root.undoOffered ? "Undo " + root.undoOffered.symbol : ""
    undoOpacity: root.undoShown
    onUndoHoveredChanged: root.holdUndo()
    onUndoClicked: root.undoRemoval()
    updateLabel: root.footerSays.updateOffer !== "" ? "Update to " + root.footerSays.updateOffer : ""
    onUpdateClicked: root.updates.update(root.footerSays.restartable)
    onClicked: {
      if (root.footerSays.unreadable) return
      else if (root.saveFailed) root.saveAgain()
      else if (root.note === "" && root.footerSays.updatedTo !== "") root.updates.restart()
      else root.startAdding()
    }
  }

  // Clipped to nothing, not hidden: a hidden item's parts read themselves
  // hidden, and the retro chart's lit cap falls to its top row. A canvas
  // paints a frame after it is asked, so the grab waits two frames.
  Item {
    width: 0
    height: 0
    clip: true
    Loader {
      id: shareLoader
      objectName: "shareLoader"
    }
    FrameAnimation {
      property int frames: 0
      running: shareLoader.status === Loader.Ready
      onRunningChanged: frames = 0
      onTriggered: if (++frames === 2) root.shootCard(shareLoader.item)
    }
  }

  HelpSheet {
    id: helpSheet
    objectName: "helpSheet"
    visible: root.showingHelp
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    anchors.topMargin: root.groupGap
    anchors.bottomMargin: root.margins
    inset: root.inset
    edge: root.gutter + root.inset
    sheet: root.keySheet
    version: root.updates && root.updates.runningVersion || ""
    look: root.look
    onCloseRequested: root.showingHelp = false
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
    z: 9
    onClicked: listMenu.typedName.trim() !== "" ? root.createList(listMenu.typedName) : root.closeListMenu()
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

  RowMenu {
    objectName: "rowMenu"
    visible: root.rowMenu !== null
    active: root.rowMenu !== null && root.surfaceOpen
    z: 10
    maxWidth: root.width - root.margins * 2
    x: root.rowMenu ? Math.max(root.margins, Math.min(root.rowMenu.x, root.width - root.margins - width)) : 0
    y: !root.rowMenu ? 0 : root.rowMenu.below + height <= root.edge - root.margins ? root.rowMenu.below
      : Math.max(root.margins, root.rowMenu.above - height)
    lines: root.rowMenu ? root.rowMenu.lines.map(function(line) { return line.label }) : []
    startLine: root.rowMenu ? root.rowMenu.startLine : -1
    look: root.look
    onTaken: function(index) { root.takeRowMenu(index) }
    onDismissed: root.rowMenu = null
  }

  ListMenu {
    id: listMenu
    objectName: "listMenu"
    visible: root.listMenuOpen
    active: root.listMenuOpen && root.surfaceOpen
    z: 10
    x: root.margins
    y: root.listMenuTop
    maxHeight: root.height - root.listMenuTop - root.margins - (root.chartFitsSurface ? 0 : root.groupGap + footer.height)
    choices: root.lists
    current: root.listName
    look: root.look
    onChosen: function(name) { root.chooseList(name) }
    onCreateRequested: function(name) { root.createList(name) }
    onManageRequested: root.openManageLists()
    onDismissed: root.closeListMenu()
  }

  ChartMotion {
    id: motion
    view: root.view
    surfaceOpen: root.surfaceOpen
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
