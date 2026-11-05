import QtQuick
import qs.Commons
import qs.Commons as Commons
import "ChartSound.js" as ChartSound
import "Figures.js" as Figures
import "Format.js" as Format
import "Fundamentals.js" as Fundamentals
import "History.js" as History
import "KeySheet.js" as KeySheet
import "KeyText.js" as KeyText
import "Market.js" as Market
import "Overnight.js" as Overnight
import "Quote.js" as Quote
import "Settings.js" as Settings
import "Share.js" as Share
import "Tones.js" as Tones
// The body the window and the panel share. It reads the service and acts
// through it; the surface keeps its lifecycle, keys, and look.
Item {
  id: root

  property var service: null
  property var updates: null
  property var sounds: null
  property var camera: null
  property bool surfaceOpen: false
  // False for the window on a workspace no screen shows: it stays open, as
  // it was left, but asks for nothing.
  property bool onScreen: true
  property string headerWhenMissing: "No data"
  // The panel's: Tab steps to the next widget's panel.
  property bool switchesPanels: false
  property int margins: 0
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
  property int chartHeight: Style.space(190)
  // Set (the window's 136 px), the chart takes the surface's spare height
  // and gives way first as it gets short, so three rows still show. The
  // panel's 0 never changes, so no chartHeight change finds it stale.
  property int minChartHeight: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  // The added symbol the chart changes to once its answer is in, its row in
  // view, and the list at rest.
  property string landing: ""
  property bool landingJoined: false
  // A Show of a member still arriving: featured even if its first fetch fails.
  property bool landingShows: false
  // Each add is heard as its row joins, whatever is featured or added meanwhile.
  property var unheardAdds: []
  // The surface's colour, which a moving row carries.
  property color ground: Commons.Color.background
  property var rangeOptions: History.historyRanges()

  signal keysReleased()
  signal refreshRequested()

  // The moment a scrub or a replay shows.
  readonly property int scrubT: motion.scrubT
  property bool adding: false
  property string previewSymbol: ""
  property bool showingHelp: false
  property bool listMenuOpen: false
  property bool managingLists: false
  property string listsSymbol: ""
  property var rowMenu: null
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
  // Why an action did nothing, or what a screenshot did, said in the
  // footer's place for a moment.
  property string note: ""
  // After a screenshot, the header's camera stays lit until the next open.
  property bool cameraLit: false
  // The panel's first-run hint above the footer, cleared at the next open.
  property string hint: ""
  function showFirstRunHint() {
    hint = "Drag the pill in your bar to move it\nMiddle-click changes its look · right-click opens the window"
  }
  // The height the screen leaves the panel's body; 0 in the window.
  property int screenRoom: 0
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
  // A save that didn't land is said ahead of the update, since a restart
  // would lose the changes. Where the fix won't fit beside the notice, it
  // drops "or remove" and keeps the file's full path.
  readonly property bool unsaved: settingsUnreadable ? editsUnsaved : saveFailed
  readonly property string notice: unsaved ? "Your changes aren't saved"
    : settingsUnreadable ? "Couldn't load your lists"
    : updatedTo !== "" ? "Updated to " + updatedTo + " · click to restart the shell" : ""
  readonly property string listsFile: "~/.config/omarchy/" + (service ? service.pluginId : "") + ".json"
  readonly property var noticeActions: settingsUnreadable
    ? ["fix or remove " + listsFile, "fix " + listsFile]
    : unsaved ? ["click to try again"] : []
  readonly property string updateOffer: releasedTo !== "" && updatedTo === "" ? releasedTo : ""
  readonly property bool restartable: !unsaved && !settingsUnreadable
  readonly property bool restartOffered: updatedTo !== "" && restartable
  function runOffered() {
    if (!updates) return
    if (restartOffered) updates.restart()
    else if (updateOffer !== "") updates.update(restartable)
    else say("Nothing to update")
  }

  readonly property var emptyView: ({ featured: "", range: "1D", list: "", listKey: "=", order: "manual", reversed: false,
    rows: [], shown: [], library: [], chart: null })
  // One value, so each change of the rows, hero, range, and chart is whole.
  property var view: emptyView
  property var quotes: ({})
  property var entries: ({})
  // Each listing's newest price since its close.
  property var newestPrints: ({})
  // Robinhood's answers, for the day each row's line draws.
  property var nights: ({})
  property var allDay: ({})
  property var previewEntries: ({})
  // Each symbol's cap and P/E, and the currency rates P/Es need.
  property var fundamentalEntries: ({})
  property var rates: ({})
  property var lists: []
  // The current list's members, those still arriving included.
  property var members: []
  property var arriving: []
  property var removal: null
  property string changeMode: "pct"
  property bool retro: false
  property bool soundsOn: false
  property int chimed: -1
  // Each symbol waiting on Yahoo, by the second it began.
  property var owed: ({})
  // Symbols asked for under 2 s ago: a quote opened old isn't late yet.
  property var asking: ({})
  property bool settingsUnreadable: false
  property bool saveFailed: false
  property bool editsUnsaved: false
  // A refresh the reader asked for is out.
  property bool refreshing: false
  property string updatedTo: ""
  // A newer Stonks on main.
  property string releasedTo: ""
  // A closed surface's clock holds still too.
  property int now: 0
  readonly property bool reading: surfaceOpen && !!service
  readonly property bool previewing: previewSymbol !== "" && !!service && service.previewSurface === root
  Binding on view {
    when: root.reading
    value: root.previewing ? root.service?.previewView : root.service?.view
    restoreMode: Binding.RestoreNone
  }
  Binding on quotes { when: root.reading; value: root.service?.quotes; restoreMode: Binding.RestoreNone }
  Binding on entries { when: root.reading; value: root.service?.entries; restoreMode: Binding.RestoreNone }
  Binding on newestPrints { when: root.reading; value: root.service?.newestPrints; restoreMode: Binding.RestoreNone }
  Binding on nights { when: root.reading; value: root.service?.nights; restoreMode: Binding.RestoreNone }
  Binding on allDay { when: root.reading; value: root.service?.allDay; restoreMode: Binding.RestoreNone }
  Binding on previewEntries { when: root.reading; value: root.service?.previewEntries; restoreMode: Binding.RestoreNone }
  Binding on fundamentalEntries { when: root.reading; value: root.service?.fundamentals; restoreMode: Binding.RestoreNone }
  Binding on rates { when: root.reading; value: root.service?.rates; restoreMode: Binding.RestoreNone }
  Binding on lists { when: root.reading; value: root.service?.lists; restoreMode: Binding.RestoreNone }
  Binding on members { when: root.reading; value: root.service?.symbols; restoreMode: Binding.RestoreNone }
  Binding on arriving { when: root.reading; value: root.service?.arriving; restoreMode: Binding.RestoreNone }
  Binding on removal { when: root.reading; value: root.service?.lastRemoval; restoreMode: Binding.RestoreNone }
  Binding on changeMode { when: root.reading; value: root.service?.changeMode; restoreMode: Binding.RestoreNone }
  Binding on retro { when: root.reading; value: root.service?.retro; restoreMode: Binding.RestoreNone }
  Binding on soundsOn { when: root.reading; value: root.service?.soundsOn; restoreMode: Binding.RestoreNone }
  Binding on owed { when: root.reading; value: root.service?.owed; restoreMode: Binding.RestoreNone }
  Binding on asking { when: root.reading; value: root.service?.asking || ({}); restoreMode: Binding.RestoreNone }
  Binding on settingsUnreadable { when: root.reading; value: root.service?.settingsUnreadable; restoreMode: Binding.RestoreNone }
  Binding on saveFailed { when: root.reading; value: root.service?.saveFailed; restoreMode: Binding.RestoreNone }
  Binding on editsUnsaved { when: root.reading; value: root.service?.editsUnsaved; restoreMode: Binding.RestoreNone }
  Binding on refreshing { when: root.reading; value: root.service?.refreshing; restoreMode: Binding.RestoreNone }
  Binding on updatedTo { when: root.reading; value: root.updates ? root.updates.newVersion : ""; restoreMode: Binding.RestoreNone }
  Binding on releasedTo { when: root.reading; value: root.updates ? root.updates.releasedVersion : ""; restoreMode: Binding.RestoreNone }
  property string yahooPause: ""
  property int yahooPausedUntil: 0
  Binding on yahooPause { when: root.reading; value: root.service?.yahooGate?.pause ?? ""; restoreMode: Binding.RestoreNone }
  Binding on yahooPausedUntil { when: root.reading; value: root.service?.yahooGate?.pausedUntil ?? 0; restoreMode: Binding.RestoreNone }
  Binding on now { when: root.reading; value: root.service?.now; restoreMode: Binding.RestoreNone }

  readonly property var symbols: view.rows
  readonly property string listName: view.list
  readonly property string listLabel: listName !== "" ? listName : "All"
  readonly property var shown: view.shown
  readonly property var calendars: service ? service.calendars : null
  readonly property string featuredSymbol: view.featured
  readonly property string range: view.range
  readonly property string order: view.order
  readonly property bool reversed: view.reversed
  readonly property var chart: motion.chart
  readonly property bool chartLoading: motion.loading
  readonly property string chartSymbol: chart ? chart.symbol : ""
  readonly property string chartRange: chart ? chart.range : "1D"
  readonly property var fundamentals: chartSymbol ? fundamentalEntries[chartSymbol] || null : null
  readonly property color dim: Tones.dim(foreground, ground)
  readonly property color dimmer: Tones.dimmer(foreground, ground)
  readonly property color ghost: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  readonly property int rowHeight: Style.space(30)
  readonly property int listRowHeight: Style.space(40)
  readonly property int rowGap: Style.space(2)
  readonly property int rowPitch: listRowHeight + rowGap
  readonly property int threeRowsHeight: 3 * rowPitch - rowGap

  readonly property bool historyActive: motion.historyActive
  readonly property var history: motion.history
  // A range whose first fetch failed: the day stands in, figures and all.
  readonly property bool historyFailed: !!chart && chart.failed
  readonly property bool historyShown: historyActive && !!history
  readonly property var historyStats: historyShown ? History.periodStats(history) : null
  readonly property var historyBar: historyShown && scrubT
    ? History.historyBarAt(history, History.historyFraction(history, scrubT)) : null
  readonly property int scrubShown: motion.scrubShown
  // The rows follow a scrub of the day. They stay on now for a range and for
  // hours outside Yahoo's day, but not the coming day's pre-market, which
  // each row's quote holds too. The quote can change before the day does:
  // until the day comes, the scrub stands.
  readonly property var featuredTail: featuredQuote ? Quote.tailStart(featuredQuote) : null
  readonly property int watchlistScrubShown: historyActive || !featuredQuote || scrubShown < Quote.dayStart(featuredQuote)
    || (!!featuredDay && !!featuredDay.axis && scrubShown >= Quote.dayEnd(featuredQuote)
      && !(featuredTail !== null && scrubShown >= featuredTail)) ? 0 : scrubShown
  readonly property var featuredQuote: motion.quote
  // The day the 1D chart draws; its baseline is `prevClose`.
  readonly property var featuredDay: motion.day
  readonly property var featuredFreshness: Figures.freshness(entryOf(chartSymbol || featuredSymbol), featuredQuote, now,
    owed[chartSymbol || featuredSymbol] || 0, !!asking[chartSymbol || featuredSymbol], featuredNewest)
  readonly property int warnings: lists.length > 0 ? lists[0].symbols.filter(function(symbol) {
    return Figures.freshnessWarns(Figures.freshness(entryOf(symbol), quotes[symbol] || null, now, owed[symbol] || 0, !!asking[symbol]))
  }).length : 0
  readonly property bool yahooDown: warnings > 0 && warnings === lists[0].symbols.length
  readonly property var hostPause: Figures.hostPause(yahooPause, yahooPausedUntil, now)
  readonly property var featuredGeometry: motion.geometry
  readonly property real scrubX: motion.scrubX
  readonly property bool dayScrubbed: !historyActive && scrubShown !== 0
  readonly property var featuredNewest: featuredQuote && featuredDay ? Overnight.newestPrint(featuredQuote, motion.latest, calendars, featuredDay) : null
  readonly property var dailyFeatured: featuredQuote
    ? Figures.rowModel(dayScrubbed ? featuredDay : featuredQuote, dayScrubbed ? scrubShown : 0, changeMode, featuredNewest) : null
  readonly property var featured: historyShown ? History.historyRowModel(history, featuredQuote, scrubShown) : dailyFeatured
  // A live marker is honest only when the headline and chart endpoint are the same day quote.
  readonly property bool heroLive: (!historyActive || historyFailed)
    && !scrubT && featuredFreshness.live
  // The moment shown against the baseline; the pill's reads the day.
  readonly property string animalKind: Figures.animalKind(featured)
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
  // Changes only at the exchange's midnight, unlike `now`.
  readonly property int featuredToday: featuredQuote ? Figures.exchangeDay(featuredQuote, now) : 0
  // The table holds room for both first lines' facts on every range, so a
  // range change moves nothing.
  readonly property var dayLine: chart ? Figures.dayLine(featuredQuote, featuredToday, featuredDay) : null
  readonly property var rangeEnds: historyShown ? History.rangeEnds(history, historyStats, featuredQuote) : null
  readonly property var periodLine: !chart ? null : historyShown ? History.rangeLine(history, rangeEnds, featuredQuote) : dayLine
  readonly property var infoFactLists: !dayLine ? [] : [dayLine.facts, History.rangeFacts(dayLine.range.widest)]
    .concat(yearLine ? [History.rangeFacts(yearLine.range.widest)] : [])
  readonly property var yearLine: chart ? Fundamentals.yearLine(featuredQuote, fundamentals ? fundamentals.figures : null,
    historyShown && history.range === "1Y" ? rangeEnds : null, rates,
    (featuredDay ? featuredDay.points : []).concat(featuredNewest ? [featuredNewest] : [])) : null
  readonly property var rangeMarks: historyShown ? History.rangeMarks(history, rangeEnds, featuredQuote) : null
  // Said under the price: what a scrub's move counts from.
  readonly property string baselineText: historyShown ? "┄ " + chartRange.toUpperCase() + " START " + Format.money(history.baseline, featuredQuote ? featuredQuote.priceDigits : undefined)
    : (!historyActive && featuredDay ? "┄ " + Figures.dayBaselineText(featuredDay, Figures.exchangeDay(featuredDay, now), scrubShown) : "")
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
  // The most height the panel's card gives the body; 0 in the window. The
  // rows' sight is measured at that height, whatever the card has shrunk to
  // for the key sheet or a view.
  property int rowsRoom: 0
  readonly property int rowsSightHeight: rowsRoom > 0 ? wholeRowsHeight(rowsRoom - chromeHeight) : wholeListHeight
  readonly property int listMenuTop: margins + header.height + groupGap + heroBand.implicitHeight + Style.space(4)
  // The menu ends one gap above the footer, which stays in sight under it.
  readonly property int listMenuBottom: listMenuTop + listMenu.contentHeight + groupGap + footer.height + margins
  readonly property int listMenuLeastBottom: listMenuTop + listMenu.leastHeight + groupGap + footer.height + margins
  readonly property bool listViewOpen: managingLists || listsSymbol !== ""
  readonly property int listViewHeight: margins * 2 + header.height + heroBand.implicitHeight + groupGap * 2
    + (managingLists ? manageLists.contentHeight : symbolLists.contentHeight)
  readonly property bool rowsShown: !showingHelp && !adding && !listViewOpen
  readonly property bool ownsKeys: adding || listMenuOpen || listViewOpen || rowMenu !== null
  readonly property var putBack: {
    if (!removal || members.indexOf(removal.symbol) >= 0) return null
    var was = Settings.listChoices(removal.before).filter(function(list) { return list.name === listName })[0]
    if (!was || was.symbols.indexOf(removal.symbol) < 0) return null
    var quote = removal.quote
    return { symbol: removal.symbol, name: quote ? quote.name : removal.symbol, exchange: quote ? quote.exchange : "" }
  }
  readonly property var keySheet: KeySheet.sheet(order, switchesPanels)
  // Read from the view: `symbols` may lag a switch.
  readonly property var breadth: Object.assign({ list: view.list },
    Figures.listBreadth(view.rows, quotes, watchlistScrubShown, changeMode, newestPrints))
  readonly property alias watchlist: watchlist
  readonly property alias search: search
  readonly property alias chartItem: heroBand.chartItem
  readonly property alias motion: motion

  function entryOf(symbol) {
    if (entries && entries[symbol]) return entries[symbol]
    return previewEntries && previewEntries[symbol] ? previewEntries[symbol] : null
  }

  function rowsHeight(count, space) {
    var rows = Math.min(count, Math.floor((Math.max(0, space) + rowGap) / rowPitch))
    return rows > 0 ? rows * rowPitch - rowGap : 0
  }

  function wholeRowsHeight(space) {
    return rowsHeight(listName !== "" ? Math.max(1, symbols.length) : symbols.length, space)
  }

  function fittedHeight(maxHeight) {
    if (showingHelp) return Math.min(maxHeight, helpHeight)
    var rows = chromeHeight + wholeRowsHeight(maxHeight - chromeHeight)
    var view = listViewOpen ? listViewHeight : adding ? searchHeight : listMenuOpen ? listMenuBottom : 0
    var least = listMenuOpen ? Math.min(maxHeight, listMenuLeastBottom) : 0
    return Math.max(rows, least, Math.min(chromeHeight + rowsHeight(Infinity, maxHeight - chromeHeight), view))
  }

  onFeaturedSymbolChanged: if (featuredSymbol !== landing) landing = ""

  // A search held back while no screen showed it goes once one does.
  onSurfaceOpenChanged: {
    if (service) service.surfaceShown(root, surfaceOpen && onScreen)
    if (!surfaceOpen) previewTo("")
  }
  onOnScreenChanged: {
    if (service) service.surfaceShown(root, surfaceOpen && onScreen)
    if (onScreen) search.pump()
  }
  onServiceChanged: if (service && surfaceOpen && onScreen) service.surfaceShown(root, true)
  // The panel's `onScreen` doesn't follow screens turning off. The sounds
  // keep the output awake a second after the scrub last moves, for chimes.
  readonly property bool scrubbing: surfaceOpen && onScreen && !(service && service.screensOff) && motion.scrubT !== 0
  onScrubbingChanged: if (sounds) sounds.scrubMoved()
  onScrubTChanged: if (sounds && scrubbing) sounds.scrubMoved()
  // A rebuilt bar or a removed screen takes the panel down mid-replay.
  Component.onDestruction: {
    if (sounds) sounds.stopReplay(root)
    if (service) {
      service.surfaceShown(root, false)
      service.preview(root, "")
    }
  }
  // Asked for first on open, and fetched ahead on a range.
  readonly property var rowsInSight: surfaceOpen && onScreen && rowsShown ? watchlist.sightSymbols : []
  onRowsInSightChanged: if (service) service.rowsSeen(root, rowsInSight)
  // The service holds answers that would stutter the chart drawing in.
  readonly property bool drawingIn: surfaceOpen && onScreen && motion.drawingIn
  onDrawingInChanged: if (service) service.drawingIn(root, drawingIn)
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPreviewTaken(surface) { if (surface === root) root.cancelAdding() }
    function onScreensReady() { search.pump() }
    function onYahooBack() { if (root.onScreen) search.yahooBack() }
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

  // The keys both surfaces answer; each reads Esc, and the panel Tab, itself.
  function pressKey(event) {
    var key = event.key
    var mods = event.modifiers & ~Qt.KeypadModifier
    // A letter's command is its key and Shift, never its text: Caps Lock
    // sends "O" for o, which would reverse the order.
    var t = KeyText.typed(event)
    if (mods === Qt.ControlModifier && key === Qt.Key_C) takeScreenshot()
    else if (mods === Qt.ControlModifier && key === Qt.Key_Z) undoRemoval()
    else if (mods === Qt.ShiftModifier && key === Qt.Key_Up) moveSelected(-1)
    else if (mods === Qt.ShiftModifier && key === Qt.Key_Down) moveSelected(1)
    else if (mods === Qt.ControlModifier && (key === Qt.Key_Return || key === Qt.Key_Enter)) openSymbolLists(watchlist.cursorRow)
    else if (key === Qt.Key_Up) moveCursor(-1)
    else if (key === Qt.Key_Down) moveCursor(1)
    else if (key === Qt.Key_Left) nudgeScrub(-1)
    else if (key === Qt.Key_Right) nudgeScrub(1)
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) featureSymbol(watchlist.cursorRow)
    else if (key === Qt.Key_Delete || key === Qt.Key_Backspace) removeRow(watchlist.cursorRow)
    else if (t === "?") toggleHelp()
    else if (t === "a") startAdding()
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
    else return false
    return true
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

  function rowMenuLines(symbol) {
    var held = listsHolding(symbol)
    var everywhere = { label: held > 1 ? "Remove from all " + held + " lists" : "Remove from All", everywhere: true }
    return listName !== "" ? [{ label: "Remove from " + listName, everywhere: false }, everywhere] : [everywhere]
  }

  // At the pointer, on no line; from a key, under the row's symbol, on its
  // first line. Without room under, it opens upward.
  function openRowMenu(symbol, point) {
    var row = watchlist.rowItem(symbol)
    if (!service || !row || watchlist.displayedSymbols.indexOf(symbol) < 0) return
    closeViews()
    watchlist.cursorSymbol = symbol
    var top = row.mapToItem(root, Style.space(28), 0)
    var at = point ? root.mapFromItem(null, point.x, point.y) : top
    rowMenu = { symbol: symbol, lines: rowMenuLines(symbol), ground: rowMenuGround(symbol), startLine: point ? -1 : 0, x: at.x,
      below: point ? at.y : top.y + row.height, above: at.y }
  }

  function takeRowMenu(index) {
    var menu = rowMenu
    if (menu && index >= 0 && index < menu.lines.length) removeFrom(menu.symbol, menu.lines[index].everywhere)
    rowMenu = null
  }

  function say(text) {
    note = text
    holdNote()
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

  function undoRemoval() {
    if (!service) return
    showingHelp = false
    if (!removal) {
      say("Nothing to undo")
      return
    }
    var symbol = removal.symbol
    service.undoRemoval(symbol)
    sound("undo")
    watchlist.select(symbol)
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
    duration: Style.duration(600)
    onFinished: root.endUndo()
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

  // The pointer strikes a bar as it reaches it; each key step strikes, even
  // the same bar.
  function chime(again) {
    if (!sounds || motion.replayRunning) return
    var bar = ChartSound.barAt({ retro: retro, geometry: motion.geometry, grid: heroBand.pixelGrid }, motion.scrubX)
    if (bar !== chimed || again) sounds.chime(bar)
    chimed = bar
  }

  function replay() {
    showingHelp = false
    if (!sounds) return motion.replay()
    sounds.whenAwake(root, function() { if (root.surfaceOpen) motion.replay() })
  }

  function takeScreenshot() {
    showingHelp = false
    if (!camera || camera.busy || String(shareLoader.source) !== "") return
    // With no chart on show, the footer says why nothing was taken.
    if (!featuredQuote || !featuredDay || !featured) {
      say("No chart to take a screenshot of")
      return
    }
    shareLoader.setSource("ShareCard.qml", {
      objectName: "shareCard",
      symbol: chartSymbol || featuredSymbol,
      quote: featuredQuote,
      day: featuredDay,
      history: historyShown ? history : null,
      marks: rangeMarks,
      latest: motion.latest,
      view: featured,
      scrubT: scrubShown,
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

  function endScrub() {
    if (!motion.replayRunning && !motion.scrubT) return false
    motion.clearScrub()
    return true
  }

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

  function startAdding() {
    if (!keepRename()) return
    closeViews()
    adding = true
  }

  // An add joins the rows once its first answer is in, and is featured once
  // it and the list rest. A result already in the list is shown, not added.
  function acceptSymbol(symbol) {
    if (!service) return
    var s = String(symbol || "").trim().toUpperCase()
    if (view.rows.indexOf(s) >= 0) {
      showSymbol(s)
      return
    }
    if (putBack && s === putBack.symbol) {
      cancelAdding()
      undoRemoval()
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
    if (!member) unheardAdds = unheardAdds.filter(function(a) { return a !== s }).concat([s])
    landingJoined = false
    land()
  }

  // Show features the member before the preview ends, so the chart on show
  // never changes for it, and ends an add still landing itself: the hero may
  // already be the result, so `onFeaturedSymbolChanged` wouldn't.
  function showSymbol(symbol) {
    landing = ""
    service.feature(symbol)
    cancelAdding()
    watchlist.select(symbol)
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
      watchlist.select(landing)
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
  onViewChanged: if (listsSymbol !== "" && view.library.indexOf(listsSymbol) < 0) listsSymbol = ""

  // A turn later, so a view closing as another opens hands the keys across.
  onOwnsKeysChanged: if (!ownsKeys) Qt.callLater(function() { if (!root.ownsKeys) root.keysReleased() })

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
    duration: Style.duration(600)
    onFinished: {
      root.clearNote()
      footer.fadeIn()
    }
  }

  // On the margins, not the words' edges: the longest closure status (a
  // holiday, the next open, its zone) needs the panel's whole width.
  HeaderStatus {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: root.margins
    statusForms: root.headerForms
    title: root.featured && root.featuredQuote ? root.featured.name : ""
    titled: root.headerTitled
    offersRetry: root.offersRetry
    retro: root.retro
    soundsOn: root.soundsOn
    cameraLit: root.cameraLit
    animal: root.animal
    ground: root.ground
    scrubbing: root.scrubT !== 0
    live: root.heroLive
    trouble: !!root.troubleForms
    still: !root.surfaceOpen
    helpShown: root.showingHelp
    foreground: root.foreground
    dim: root.dim
    upColor: root.upColor
    downColor: root.downColor
    fontFamily: root.fontFamily
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
    rowsDay: Figures.rowsDay(root.view.rows, root.quotes, root.newestPrints, root.now, root.calendars)
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
    retro: root.retro
    changeMode: root.changeMode
    scrubbing: root.scrubT !== 0
    live: root.heroLive
    still: !root.surfaceOpen
    held: root.chartLoading
    dimmed: motion.dimmed
    // Nothing is said to be on its way while the header says no prices come.
    loadingText: root.yahooDown ? "" : root.loadingText
    foreground: root.foreground
    dim: root.dim
    dimmer: root.dimmer
    upColor: root.upColor
    downColor: root.downColor
    ghost: root.ghost
    ground: root.ground
    fontFamily: root.fontFamily
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
    quotes: root.quotes
    newestPrints: root.newestPrints
    nights: root.nights
    allDay: root.allDay
    entries: root.entries
    featuredSymbol: root.featuredSymbol
    scrubShown: root.watchlistScrubShown
    changeMode: root.changeMode
    now: root.now
    owed: root.owed
    asking: root.asking
    retro: root.retro
    upColor: root.upColor
    downColor: root.downColor
    foreground: root.foreground
    dim: root.dim
    dimmer: root.dimmer
    fontFamily: root.fontFamily
    rowHeight: root.listRowHeight
    rowGap: root.rowGap
    gutter: root.gutter
    surfaceOpen: root.surfaceOpen
    sourceDown: root.yahooDown
    // A turn later: the change that arranged the rows is still being told.
    onArranged: Qt.callLater(root.land)
    onSettlingChanged: Qt.callLater(root.featureLanding)
    onRowRested: Qt.callLater(root.featureLanding)
    ground: root.ground
    onFeatureRequested: function(symbol) { root.featureSymbol(symbol) }
    onRemoveRequested: function(symbol) { root.removeRow(symbol) }
    onMenuRequested: function(symbol, x, y) { root.openRowMenu(symbol, Qt.point(x, y)) }
    onManualOrderRequested: function(symbols) {
      root.cancelAdding()
      if (root.service) root.service.setManualOrder(symbols)
    }
    onMoveRefused: root.say("Switch to manual order to move rows")
    onListsRequested: function(symbol) { root.openSymbolLists(symbol) }
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
    gate: root.service ? root.service.yahooGate : null
    clearance: root.service ? function() { return root.onScreen && root.service.screensClear() } : null
    active: root.adding && root.surfaceOpen
    retro: root.retro
    foreground: root.foreground
    dim: root.dim
    dimmer: root.dimmer
    fontFamily: root.fontFamily
    gutter: root.gutter
    // Short, so a list's name fits the panel's field.
    placeholder: root.listName !== "" ? "Symbol or company for " + root.listName + "…" : "Symbol or company…"
    members: root.members
    putBack: root.putBack
    onPicked: function(symbol) { root.acceptSymbol(symbol) }
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
    retro: root.retro
    foreground: root.foreground
    dim: root.dim
    fontFamily: root.fontFamily
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
    retro: root.retro
    foreground: root.foreground
    dim: root.dim
    fontFamily: root.fontFamily
    gutter: root.gutter
    onToggled: function(name, member) { root.setMembership(name, member) }
    onDismissed: root.closeListViews()
  }

  // A closing surface keeps its rows, so it says nothing.
  Text {
    objectName: "emptyList"
    visible: root.members.length === 0 && watchlist.displayedSymbols.length === 0 && root.rowsShown
    x: root.margins
    y: watchlist.y
    width: root.width - root.margins * 2 - root.gutter
    height: root.listRowHeight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    text: "No symbols in " + root.listLabel + " yet"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  // It rides the panel's easing edge, carrying the surface's ground over the
  // rows and the empty list's line, so its words never cross a row.
  AddFooter {
    id: footer
    objectName: "footer"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    y: root.edge - root.margins - height
    visible: root.rowsShown
    retro: root.retro
    foreground: root.foreground
    dim: root.dim
    fontFamily: root.fontFamily
    gutter: root.gutter
    rowHeight: root.rowHeight
    note: root.note
    noteOpacity: root.noteShown
    notice: root.notice
    noticeActions: root.noticeActions
    hint: root.hint
    showsHint: root.hintShown
    ground: root.ground
    label: root.listName !== "" ? "+  Add a symbol to " + root.listName : "+  Add a symbol"
    labelShort: root.listName !== "" ? "+  Add a symbol" : ""
    acts: !root.settingsUnreadable
    onHoveredChanged: root.holdNote()
    undoLabel: root.undoOffered ? "Undo " + root.undoOffered.symbol : ""
    undoOpacity: root.undoShown
    onUndoHoveredChanged: root.holdUndo()
    onUndoClicked: root.undoRemoval()
    updateLabel: root.updateOffer !== "" ? "Update to " + root.updateOffer : ""
    onUpdateClicked: root.updates.update(root.restartable)
    onClicked: {
      if (root.settingsUnreadable) return
      else if (root.saveFailed) root.saveAgain()
      else if (root.note === "" && root.updatedTo !== "") root.updates.restart()
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
    foreground: root.foreground
    dim: root.dim
    fontFamily: root.fontFamily
    retro: root.retro
    onCloseRequested: root.showingHelp = false
  }

  // Hover passes, so nothing under the pointer changes as the card fades.
  MouseArea {
    objectName: "closedShield"
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
    retro: root.retro
    foreground: root.foreground
    fontFamily: root.fontFamily
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
    retro: root.retro
    foreground: root.foreground
    dim: root.dim
    fontFamily: root.fontFamily
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
