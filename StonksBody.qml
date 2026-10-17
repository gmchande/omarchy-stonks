import QtQuick
import qs.Commons
import "Figures.js" as Figures
import "Format.js" as Format
import "Fundamentals.js" as Fundamentals
import "History.js" as History
import "KeySheet.js" as KeySheet
import "Market.js" as Market
import "Overnight.js" as Overnight
import "Quote.js" as Quote
import "Settings.js" as Settings
import "Tones.js" as Tones
// Shared body for the window and the popup: header, hero band, list,
// search, footer, help, and the chart's motion (ChartMotion). It reads the
// service and acts through it; the surface around it keeps its lifecycle,
// keys, and look.
// The footer sits at the edge, one gap under the rows: a surface that sizes
// itself asks fittedHeight for a height of whole rows for the list shown;
// in the window, the edge is where the content ends, or its own bottom.
Item {
  id: root

  // The data owner, or null while it is not ready.
  property var service: null
  // The plugin's version on disk against the one running (`Updates`).
  property var updates: null
  property bool surfaceOpen: false
  property string headerWhenMissing: "No data"
  property bool failClosedHeader: false
  property int margins: 0
  // Where the body's content ends, the footer at its bottom: the popup's
  // card eases its edge to a new height while the body lays out at it at
  // once, the footer riding it, and a row below it is out of sight. The
  // window's is the content's own height while that fits, so a short list
  // has the footer one gap under its rows, as in the popup, and its own
  // bottom once the list fills it. Found in the edge pass of 15 October: a
  // list of one row in the window left a tall gap above the footer.
  property real edge: Math.min(height, fittedHeight(Infinity))
  // One vertical rhythm for both looks and both surfaces. A band's gap
  // stands between the band's blocks: the hero, the chart, the range row,
  // the info lines, and the list's header. A group's gap, half of it,
  // stands between a thing and what it heads: the header over the hero, the
  // list's header over its rows or a view in their place, and the rows over
  // the footer that adds to them. The info lines' own lines are 4 apart.
  // Every row of words in the band is its caption line, a control's fill
  // reaching past it, so the gaps are the gaps seen.
  readonly property int bandGap: Style.space(16)
  readonly property int groupGap: Style.space(8)
  // Every block's words share two edges, the rows' own: `inset` in from
  // the rows' fills, which stop one `gutter` short of the right, where the
  // scrollbar lives. A block with a fill (a row, a search answer, a view's
  // row, the footer) spans the rows' width, its words inset; the band and
  // the key sheet's words stand at the words' edges, a control's fill
  // reaching past its word. The key sheet's descriptions may run on past
  // the right one, as wrapped words do; the header is the surface's own row.
  readonly property int inset: Style.space(10)
  readonly property int gutter: Style.space(8)
  readonly property int textLeft: margins + inset
  readonly property int textRight: margins + gutter + inset
  property int chartHeight: Style.space(190)
  // The least the chart may be (the window's 136 px): as the window gets
  // short, the chart gives way first, so three rows still show; at its
  // usual sizes it keeps chartHeight. The popup's card fits its rows, so
  // its chart never gives way. Found in the design pass of 14 October: the
  // smallest window showed one row of the list. 0, the popup's, gives none:
  // a constant, so no change of chartHeight can find it stale.
  property int minChartHeight: 0
  // The host's look.
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color upColor: Color.foreground
  property color downColor: Color.urgent
  // The added symbol the chart will change to once its answer is in, its row
  // in view, and the list at rest; "" when none is. The latest add is the
  // one, and a hero chosen meanwhile drops it.
  property string landing: ""
  // The landing row has joined and been eased into view; what is left is to
  // feature it once it and the list are at rest.
  property bool landingJoined: false
  // The landing is a Show of a member still arriving, not an add: it is
  // featured once its first answer is in, a failed one too.
  property bool landingShows: false
  // The surface's own colour, which a moving row carries.
  property color ground: Color.background
  property var rangeOptions: History.historyRanges()

  // A view that had the keys has let them go: the surface takes them back.
  signal keysReleased()
  // The header's R RETRY, which does what the surface's r does.
  signal refreshRequested()

  // The moment the chart shows, the motion's: a scrub or a replay.
  readonly property int scrubT: motion.scrubT
  property bool adding: false
  // The search result the hero shows unadded while search is open: the
  // keyboard's choice (`previewTo`); "" when none is.
  property string previewSymbol: ""
  property bool showingHelp: false
  property bool listMenuOpen: false
  property bool managingLists: false
  // The symbol whose lists the checklist shows; "" while it is closed.
  property string listsSymbol: ""
  // A short word in the footer's place, for a moment, held while the pointer
  // is on it: why a key did nothing, or what a removal took, which a click
  // on it puts back (`offered`).
  property string note: ""
  // A quiet line above the footer for this visit: the popup's first-run
  // hint (`showFirstRunHint`), how the pill is moved and changed. The next
  // open clears it.
  property string hint: ""
  function showFirstRunHint() {
    hint = "Drag the pill to move it along the bar\nMiddle-click changes its form · right-click opens the window"
  }
  // A standing word in the footer's place, under a note, until what it says
  // is fixed: the data file can't be read, or an update waits on a shell
  // restart, which a click on it does.
  readonly property string notice: settingsUnreadable ? "Can't read grvc.stonks.json · fix or remove it to save changes"
    : updatedTo !== "" ? "Updated to " + updatedTo + " · restart the shell" : ""
  // The removal the footer's note offers back, the service's one removal on
  // offer as the note was said: when another surface makes a newer removal,
  // the lists change, or it is undone, the offer goes, and the note with it.
  property var offered: null
  onRemovalChanged: if (offered !== null && removal !== offered) clearNote()

  // What this surface shows of the service, held in one place: the surface
  // reads the service only while it is open. From a close until the next
  // open each of these keeps what it last read, so nothing on a closing
  // surface changes during the popup's close fade, whatever the service does
  // meanwhile: a chart that lands, a hero chosen on another surface, a
  // removal from All. The next open takes the latest at once.
  readonly property var emptyView: ({ featured: "", range: "1D", list: "", listKey: "=", order: "manual", reversed: false,
    rows: [], shown: [], library: [], chart: null })
  // What the rows show, the hero and the range asked for, and the chart
  // ready for them, as one value: each change of it is whole. While search
  // previews a result, the hero is that result.
  property var view: emptyView
  property var quotes: ({})
  property var entries: ({})
  // The preview's receipt, which says whether its quote failed.
  property var previewEntries: ({})
  // Every symbol's cap and P/E, as the service keeps them.
  property var fundamentalEntries: ({})
  property var lists: []
  // The current list's members, those still arriving included.
  property var members: []
  property var arriving: []
  property var removal: null
  property string changeMode: "pct"
  property bool retro: false
  // Each symbol waiting on Yahoo, with the second that began: freshness's
  // overdue (`QuoteFeed.owed`).
  property var owed: ({})
  property bool settingsUnreadable: false
  property string updatedTo: ""
  // The clock: a closed surface's holds still too, so nothing it would show
  // is derived again every second.
  property int now: 0
  readonly property bool reading: surfaceOpen && !!service
  // This surface's preview, while the service's preview is its own.
  readonly property bool previewing: previewSymbol !== "" && !!service && service.previewSurface === root
  Binding on view {
    when: root.reading
    value: root.previewing ? root.service?.previewView : root.service?.view
    restoreMode: Binding.RestoreNone
  }
  Binding on quotes { when: root.reading; value: root.service?.quotes; restoreMode: Binding.RestoreNone }
  Binding on entries { when: root.reading; value: root.service?.entries; restoreMode: Binding.RestoreNone }
  Binding on previewEntries { when: root.reading; value: root.service?.previewEntries; restoreMode: Binding.RestoreNone }
  Binding on fundamentalEntries { when: root.reading; value: root.service?.fundamentals; restoreMode: Binding.RestoreNone }
  Binding on lists { when: root.reading; value: root.service?.lists; restoreMode: Binding.RestoreNone }
  Binding on members { when: root.reading; value: root.service?.symbols; restoreMode: Binding.RestoreNone }
  Binding on arriving { when: root.reading; value: root.service?.arriving; restoreMode: Binding.RestoreNone }
  Binding on removal { when: root.reading; value: root.service?.lastRemoval; restoreMode: Binding.RestoreNone }
  Binding on changeMode { when: root.reading; value: root.service?.changeMode; restoreMode: Binding.RestoreNone }
  Binding on retro { when: root.reading; value: root.service?.retro; restoreMode: Binding.RestoreNone }
  Binding on owed { when: root.reading; value: root.service?.owed; restoreMode: Binding.RestoreNone }
  Binding on settingsUnreadable { when: root.reading; value: root.service?.settingsUnreadable; restoreMode: Binding.RestoreNone }
  Binding on updatedTo { when: root.reading; value: root.updates ? root.updates.newVersion : ""; restoreMode: Binding.RestoreNone }
  Binding on now { when: root.reading; value: root.service?.now; restoreMode: Binding.RestoreNone }

  readonly property var symbols: view.rows
  // The current list, "" for All.
  readonly property string listName: view.list
  readonly property string listLabel: listName !== "" ? listName : "All"
  readonly property var shown: view.shown
  readonly property var calendars: service ? service.calendars : null
  readonly property string featuredSymbol: view.featured
  readonly property string range: view.range
  readonly property string order: view.order
  readonly property bool reversed: view.reversed
  // The chart on screen, the motion's: the view's once it can be drawn, and
  // until then the one already on screen, as it was, so the hero keeps what
  // it showed, chart, figures, and info lines alike, until the new one is in
  // and draws in; a quarter of a second on, they dim (`motion.dimmed`). Null
  // only before any chart has been in.
  readonly property var chart: motion.chart
  // The chart asked for is still on its way: what is on screen is another.
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

  // The chart on screen as the motion measures it, and the moment it shows.
  readonly property bool historyActive: motion.historyActive
  readonly property var history: motion.history
  // A range whose first fetch failed: the day stands in, figures and all.
  readonly property bool historyFailed: !!chart && chart.failed
  // From this body's own `history`, not the motion's `historyShown`: what
  // reads both here then sees them change together, never a shown history
  // that is not there yet.
  readonly property bool historyShown: historyActive && !!history
  readonly property var historyStats: historyShown ? History.periodStats(history) : null
  readonly property var historyBar: historyShown && scrubT
    ? History.historyBarAt(history, History.historyFraction(history, scrubT)) : null
  readonly property int scrubShown: motion.scrubShown
  // The rows show the day: they follow a scrub of it, and stay on now while
  // one reads a range, or the 1D chart's hours outside Yahoo's day, before
  // it or the night after it.
  readonly property int watchlistScrubShown: historyActive || !featuredQuote || scrubShown < Quote.dayStart(featuredQuote)
    || (!!featuredDay.axis && scrubShown >= Quote.dayEnd(featuredQuote)) ? 0 : scrubShown
  // Yahoo's quote: the headline and the day's figures, at rest.
  readonly property var featuredQuote: motion.quote
  // The day the 1D chart draws, which a scrub of it reads: its prints, and
  // its baseline as `prevClose` (`Chart.viewChart`).
  readonly property var featuredDay: motion.day
  readonly property var featuredFreshness: Figures.freshness(entryOf(chartSymbol || featuredSymbol), featuredQuote, now,
    owed[chartSymbol || featuredSymbol] || 0)
  readonly property var featuredGeometry: motion.geometry
  readonly property real scrubX: motion.scrubX
  readonly property bool dayScrubbed: !historyActive && scrubShown !== 0
  readonly property var dailyFeatured: featuredQuote
    ? Figures.rowModel(dayScrubbed ? featuredDay : featuredQuote, dayScrubbed ? scrubShown : 0, changeMode) : null
  readonly property var featured: historyShown ? History.historyRowModel(history, featuredQuote, scrubShown) : dailyFeatured
  // A live marker is honest only when the headline and chart endpoint are the same day quote.
  readonly property bool heroLive: (!historyActive || historyFailed)
    && !scrubT && featuredFreshness.live
  // The header's animal, in both looks: the direction of the moment shown
  // against the baseline, a bull up and a bear down, and none on a flat day
  // (`dayTone`) or before a direction is known.
  readonly property string animalKind: !featured || featured.dayTone === "flat" ? ""
    : featured.dayTone === "up" ? "bull" : "bear"
  // What it reads, the chart as the motion tells charts apart (a failed
  // range's stand-in day is another chart than its history), the list, and
  // the look: a change of it is no turn, so the animal changes at once.
  readonly property string animalChart: [motion.chartKeyOf(chart), view.listKey, retro].join(" ")
  // It sleeps while its market does, by the phase and the calendar, never
  // by the data's age (`Overnight.marketAsleep`), and a scrub, which reads
  // a moment the market traded, wakes it. `bell`: the clock put it to sleep
  // in the last few seconds, the same quote awake `bellWindow` before, so
  // its eyes close slowly, a late or skipped tick of the clock included;
  // any other way into sleep is no bell: a scrub let go, ever (`scrubbed`
  // tells the header a scrub woke it), and a quote landing, past those
  // seconds. `animalSleep` is 0 awake, 1 asleep, 2 asleep at the bell, 3
  // awake for a scrub, worked out in one binding, so no value of it pairs a
  // fresh sleep with a stale bell or scrub; a number, so the animal changes
  // only when its sleep does, not with every tick, quote, or scrub step
  // that leaves it.
  readonly property int bellWindow: 5
  readonly property int animalSleep: {
    if (scrubT) return 3
    var allDay = !!chart && chart.allDay
    if (!featuredQuote || !Overnight.marketAsleep(featuredQuote, allDay, now, calendars)) return 0
    return Overnight.marketAsleep(featuredQuote, allDay, now - bellWindow, calendars) ? 1 : 2
  }
  readonly property var animal: ({ kind: animalKind, chart: animalChart,
    asleep: animalSleep === 1 || animalSleep === 2, bell: animalSleep === 2, scrubbed: animalSleep === 3 })
  // Today in the featured listing's exchange, which changes only at its
  // midnight, so the day line is not derived again every second.
  readonly property int featuredToday: featuredQuote ? Figures.exchangeDay(featuredQuote, now) : 0
  // The info block describes what the chart shows: the range's line, or the
  // day's when the chart is the day, over the 52 weeks. Before any chart,
  // nothing.
  readonly property var periodLine: !chart ? null : historyShown
    ? History.rangeLine(history, historyStats, featuredQuote ? featuredQuote.priceDigits : undefined,
      featuredQuote ? Quote.regularClose(featuredQuote) : null)
    : Figures.dayLine(featuredQuote, featuredToday)
  readonly property var yearLine: chart ? Fundamentals.yearLine(featuredQuote, fundamentals ? fundamentals.figures : null,
    historyShown ? history.range : "", historyStats) : null
  // What the dashed line is, said while a scrub reads against it.
  readonly property string baselineText: historyShown ? chartRange.toUpperCase() + " START " + Format.money(history.baseline, featuredQuote ? featuredQuote.priceDigits : undefined)
    : (!historyActive && featuredDay ? "PREV CLOSE " + Format.money(featuredDay.prevClose, featuredDay.priceDigits) : "")
  // A range that failed, which r, or the header's button, asks for again.
  readonly property string unavailableText: chartRange.toUpperCase() + " unavailable"
  readonly property bool offersRetry: headerText === unavailableText
  // The chart asked for, named while it is on its way.
  readonly property string loadingText: "Loading " + featuredSymbol + (range !== "1D" ? " " + range : "")
  readonly property string headerText: {
    if (!service) return headerWhenMissing
    // The chart asked for is on its way, named: what was on show stays.
    if (chartLoading) return loadingText
    if (failClosedHeader && !featuredQuote && featuredFreshness && featuredFreshness.state === "failed")
      return "No data"
    if (historyActive && historyFailed) return unavailableText
    // A refetch, out or failed, with the range in hand says nothing: it
    // keeps the chart and the market.
    if (historyShown && historyBar) return History.historyScrubText(history, historyBar, featuredQuote ? featuredQuote.priceDigits : undefined,
      featuredQuote ? Market.calendarFor(calendars, featuredQuote) : null)
    if (featuredQuote) return Market.marketStatus(dayScrubbed ? featuredDay : featuredQuote, now, scrubShown, calendars)
    return headerWhenMissing
  }
  // Everything but the rows: margins, header, band, and footer, with the
  // band, the rows, and the footer each one group's gap under what is above.
  readonly property int chromeHeight: chartGivesWay ? chromeBesideChart + shownChartHeight
    : margins * 2 + header.height + heroBand.implicitHeight + footer.height + groupGap * 3
  readonly property int chromeBesideChart: margins * 2 + header.height + heroBand.heightBesideChart + footer.height + groupGap * 3
  // The chart as drawn: chartHeight, less what three rows need of it, down
  // to minChartHeight. Read from the chrome beside it, never from the chart,
  // so its size never reads itself back. Only where the chart gives way:
  // elsewhere the chart and the chrome are read as they always were, so a
  // height fitted to the body, as the popup's is, never passes through it.
  readonly property bool chartGivesWay: minChartHeight > 0 && minChartHeight < chartHeight
  readonly property int shownChartHeight: chartHeight - Math.max(0, Math.min(chartHeight - minChartHeight,
    3 * rowPitch - rowGap - (height - chromeBesideChart - chartHeight)))
  // The shortest the surface may be: its chrome and one row, or, where the
  // chart gives way, its chrome at the least chart and three rows. Counted
  // from the rows, not from the chart's give: each size rounds on its own
  // at a larger text size (275 less 170 is not two 53 px rows).
  readonly property int smallestHeight: chartGivesWay ? chromeBesideChart + minChartHeight + 3 * rowPitch - rowGap
    : chromeBesideChart + chartHeight + listRowHeight
  readonly property int helpHeight: margins * 2 + header.height + groupGap + helpSheet.contentHeight
  // Search needs room for the field and a full set of results, never less
  // because the list it replaces is short. Its field takes the rows' place
  // as it opens, and its answers fill down under the field.
  readonly property int searchHeight: margins * 2 + header.height + heroBand.implicitHeight
    + groupGap * 2 + search.desiredHeight
  readonly property int wholeListHeight: wholeRowsHeight(height - chromeHeight)
  // The most height the surface gives the body, as the popup's card does
  // when it fits the rows; 0 where the body's height is its own (the
  // window). The list's sight is its rows' view at that height, whatever
  // the card has shrunk to for the key sheet or a view.
  property int rowsRoom: 0
  readonly property int rowsSightHeight: rowsRoom > 0 ? wholeRowsHeight(rowsRoom - chromeHeight) : wholeListHeight
  readonly property int listMenuTop: margins + header.height + groupGap + heroBand.implicitHeight + Style.space(4)
  // The menu ends one gap above the footer, which stays in sight under it.
  readonly property int listMenuBottom: listMenuTop + listMenu.contentHeight + groupGap + footer.height + margins
  // Where the menu's least ends, the footer one gap under it: its floor.
  readonly property int listMenuLeastBottom: listMenuTop + listMenu.leastHeight + groupGap + footer.height + margins
  // Manage lists and a symbol's lists take the rows' and the footer's place,
  // in the surface's height; their own is what they would need
  // (`fittedHeight`).
  readonly property bool listViewOpen: managingLists || listsSymbol !== ""
  readonly property int listViewHeight: margins * 2 + header.height + heroBand.implicitHeight + groupGap * 2
    + (managingLists ? manageLists.contentHeight : symbolLists.contentHeight)
  // The rows are what the body shows under the band, not the key sheet,
  // search, or a list view.
  readonly property bool rowsShown: !showingHelp && !adding && !listViewOpen
  // While any of these is open it has the keys, not the surface.
  readonly property bool ownsKeys: adding || listMenuOpen || listViewOpen
  readonly property var keySheet: KeySheet.sheet(order)
  // The rows' mood, for the rule under the list name; it follows the scrub
  // as the rows do, and names its list, so the rule tells a switch from a
  // change. Read from the view, list and rows at once: `symbols` may not
  // have caught up with a switch when this is evaluated.
  readonly property var breadth: Object.assign({ list: view.list },
    Figures.listBreadth(view.rows, quotes, watchlistScrubShown, changeMode))
  readonly property alias watchlist: watchlist
  readonly property alias search: search
  readonly property alias chartItem: heroBand.chartItem
  readonly property alias motion: motion

  function entryOf(symbol) {
    if (entries && entries[symbol]) return entries[symbol]
    return previewEntries && previewEntries[symbol] ? previewEntries[symbol] : null
  }

  // The height of `count` rows, as many whole ones as fit in `space`.
  function rowsHeight(count, space) {
    var rows = Math.min(count, Math.floor((Math.max(0, space) + rowGap) / rowPitch))
    return rows > 0 ? rows * rowPitch - rowGap : 0
  }

  // The list's height in whole rows. An empty named list keeps one row,
  // which says so; All is never empty.
  function wholeRowsHeight(space) {
    return rowsHeight(listName !== "" ? Math.max(1, symbols.length) : symbols.length, space)
  }

  // The body's height within `maxHeight`: the key sheet's own height while it
  // shows, otherwise whole rows for the list shown, the footer one gap under
  // them. A view over the rows (the list menu, search, Manage lists, a row's
  // ticks) keeps that height and fits the rows' room, scrolling what it
  // holds: it grows the surface only for a list shorter than itself, and
  // only in whole rows the room holds, never into what the rows leave over.
  // Found in the walk of #1: at a room of 780 px the menu took the 38 px
  // under the rows' 742 and pushed the footer down. Search takes its height
  // as it opens, before any typing: the field and a full set of results, so
  // the card's edge holds still while you type. An open list menu taller
  // than a short list makes room for itself and for the footer under it,
  // and at least for its least (`listMenuLeastBottom`) where the room holds
  // that though its whole rows don't: a refused name on a one-symbol list
  // under the first-run hint sat 27 px over the footer (found in review).
  function fittedHeight(maxHeight) {
    if (showingHelp) return Math.min(maxHeight, helpHeight)
    var rows = chromeHeight + wholeRowsHeight(maxHeight - chromeHeight)
    var view = listViewOpen ? listViewHeight : adding ? searchHeight : listMenuOpen ? listMenuBottom : 0
    var least = listMenuOpen ? Math.min(maxHeight, listMenuLeastBottom) : 0
    return Math.max(rows, least, Math.min(chromeHeight + rowsHeight(Infinity, maxHeight - chromeHeight), view))
  }

  // A hero chosen while an add is still coming wins over the add.
  onFeaturedSymbolChanged: if (featuredSymbol !== landing) landing = ""

  // The service wants the chart's history only while a surface shows it,
  // and a preview only while its search is open on an open surface.
  onSurfaceOpenChanged: {
    if (service) service.surfaceShown(root, surfaceOpen)
    if (!surfaceOpen) previewTo("")
  }
  onServiceChanged: if (service && surfaceOpen) service.surfaceShown(root, true)
  Component.onDestruction: if (service) {
    service.surfaceShown(root, false)
    service.preview(root, "")
  }
  // The rows in sight while they show, whose charts the service fetches
  // ahead on a range.
  readonly property var rowsInSight: surfaceOpen && rowsShown ? watchlist.sightSymbols : []
  onRowsInSightChanged: if (service) service.rowsSeen(root, rowsInSight)
  // One search previews at a time: another surface's search that starts
  // choosing takes the preview, and this search closes, so its hero never
  // shows one result while Enter would add another.
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPreviewTaken(surface) { if (surface === root) root.cancelAdding() }
  }

  // Every action on the rows and the chart shows what it acts on: the key
  // sheet closes first, from either surface.
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

  // A row by its place in the list as it is on screen, as 1 to 9 feature
  // them: while the pointer holds the rows, that is not the service's order.
  // The cursor goes with it, gliding the row into view as the arrows do, so
  // its highlight shows and x and Enter act on it. Found in the edge-case
  // pass of 15 October: a row scrolled out of sight was featured unseen.
  function featureAt(index) {
    showingHelp = false
    var rows = watchlist.displayedSymbols
    if (!service || index < 0 || index >= rows.length) return
    service.feature(rows[index])
    watchlist.select(rows[index])
  }

  // Acting on the rows closes what covers them first, the key sheet or
  // search, so what the act does shows.
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

  function stepList(delta) {
    showingHelp = false
    if (service) service.stepList(delta)
  }

  // Every removal comes through here, from a key or a right-click, so All's
  // last row's refusal is said once, in the footer. A named list may empty.
  // Removing the row the keyboard cursor is on hands the cursor to the row
  // that takes its place, as Mail and Finder do: the next row, or the one
  // before when it was the last.
  function removeRow(symbol) {
    showingHelp = false
    cancelAdding()
    if (!service || !symbol) return
    if (listName === "" && !Settings.canRemove(symbols)) {
      say("Keep at least one symbol")
      return
    }
    var rows = watchlist.displayedSymbols
    var at = rows.indexOf(symbol)
    var successor = symbol === watchlist.cursorRow && at >= 0 ? (rows[at + 1] || rows[at - 1] || "") : ""
    service.removeSymbol(symbol, rows)
    if (successor !== "") watchlist.handTo(successor)
    offerUndo(symbol, listName)
  }

  function say(text) {
    offered = null
    note = text
    holdNote()
  }

  // A removal is instant and needs no confirm, and the row may be off screen,
  // so the footer names what went and offers it back. `u` takes it back
  // until the next change to the lists, long after the note has gone.
  function offerUndo(symbol, from) {
    offered = removal
    note = "Removed " + symbol + (from !== "" ? " from " + from : "")
    holdNote()
  }

  // Puts the service's last removal back, whichever surface made it, or
  // says there is none: the next change to the lists ended the offer. The
  // row returns at its place, and the list eases it into view.
  function undoRemoval() {
    if (!service) return
    showingHelp = false
    if (!removal) {
      say("Nothing to undo")
      return
    }
    var symbol = removal.symbol
    clearNote()
    service.undoRemoval(symbol)
    watchlist.select(symbol)
  }

  // The note's moment starts again, and waits while the pointer is on it,
  // so it never turns into the add under a click on its way. A pointer that
  // comes during its fade brings it back whole. A closed surface's note
  // stays as the close left it, a pointer passing over the fading card too.
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
    offered = null
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
    motion.nudgeScrub(steps)
  }

  // A replay plays the shown chart; the motion runs it.
  function replay() {
    showingHelp = false
    motion.replay()
  }

  // Back from a scrub or a replay to now; false when there was none.
  function endScrub() {
    if (!motion.replayRunning && !motion.scrubT) return false
    motion.clearScrub()
    return true
  }

  // Every view that takes the keys, closed. Each gives up its own keys; the
  // surface takes them back once none has them (keysReleased).
  function closeViews() {
    cancelAdding()
    listMenuOpen = false
    managingLists = false
    listsSymbol = ""
  }

  // A rename being typed in Manage lists is kept, as Enter keeps it, before
  // a click opens anything else (the `?`, the list name); a refused one
  // keeps the view, saying why. Keys can't get here: the field has them.
  function keepRename() {
    if (managingLists && manageLists.renaming) manageLists.keepName()
    return !(managingLists && manageLists.renaming)
  }

  function toggleHelp() {
    if (!keepRename()) return
    closeViews()
    showingHelp = !showingHelp
    if (showingHelp) helpSheet.contentY = 0
  }

  // Opening a view closes whatever else was open, the key sheet included.
  function startAdding() {
    if (!keepRename()) return
    closeViews()
    showingHelp = false
    adding = true
  }

  // A symbol you add has nothing to show until its first answer, so the
  // service keeps it out of the rows until then and the view stays on what
  // you were looking at. Then its row joins at its place, the list eases it
  // into view once, and when the list and the row are at rest it is featured
  // the way a click on that row features it, unless you chose another hero
  // meanwhile or switched to a list without it. The latest add is the one;
  // closing drops it (freeze). A result the hero already shows as a preview
  // has its answer: it joins at once and stays the hero.
  // Search closes first, the preview staying on the hero: the rows show
  // again as they were, and the add then joins them the way any new row
  // does, faded in at its place with the rows below it sliding. The preview
  // ends once the add has made it the featured symbol, so the chart on
  // show never changes for it.
  // A result already in the list on screen is shown, not added
  // (`showSymbol`); one still arriving lands as an add does, and, shown,
  // is featured even when its first fetch fails.
  function acceptSymbol(symbol) {
    if (!service) return
    var s = String(symbol || "").trim().toUpperCase()
    if (view.rows.indexOf(s) >= 0) {
      showSymbol(s)
      return
    }
    var member = members.indexOf(s) >= 0
    adding = false
    if (!member) service.addSymbol(s)
    previewTo("")
    // After the preview has gone, whose hero was a choice, not a landing.
    landing = s
    landingShows = member
    landingJoined = false
    land()
  }

  // Show features the member's row the way a click on it does, a first
  // fetch that failed too, and carries the row into view. The hero already
  // shows it as the preview: it is featured before the preview ends, so the
  // chart on show never changes for it. Show is a choice of hero, so it
  // ends an add still landing, which the featured symbol may not change to
  // tell (`onFeaturedSymbolChanged`) when the hero was already the result.
  function showSymbol(symbol) {
    landing = ""
    service.feature(symbol)
    cancelAdding()
    watchlist.select(symbol)
  }

  // Called once the rows show the service's latest view.
  function land() {
    if (landing === "" || !service || service.arriving.indexOf(landing) >= 0) return
    // A first fetch that failed has nothing to show: the view stays, the add
    // is done, and its row says it failed; a Show features that row all the
    // same. One the list on show lacks is done too. One already in All
    // whose first quote is still out waits for it.
    var failed = !quotes[landing] && !!entries[landing] && entries[landing].status === "failed"
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

  // The chart changes to the landing row once it has joined and the list is
  // at rest: where the selection's glide took it, or wherever a wheel or a
  // key left it instead.
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

  // The hero shows search's choice, unadded, while search is open on an
  // open surface; "" puts the featured symbol back.
  function previewTo(symbol) {
    var s = adding && surfaceOpen ? String(symbol || "") : ""
    if (s === previewSymbol) return
    // The service's first: until it is, this preview would read as taken.
    if (service) service.preview(root, s)
    previewSymbol = s
  }

  // The menu lies over rows that stay visible: the rows forget their last
  // click, so a press that dismisses it never pairs with one before.
  function openListMenu() {
    if (!keepRename()) return
    closeViews()
    showingHelp = false
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

  // A new list is empty, so search opens straight away to fill it.
  function createList(name) {
    if (!service) return
    var problem = service.createList(name)
    if (problem !== "") { listMenu.problem = problem; return }
    startAdding()
  }

  function openManageLists() {
    closeViews()
    showingHelp = false
    managingLists = true
  }

  function openSymbolLists(symbol) {
    if (!symbol) return
    closeViews()
    showingHelp = false
    listsSymbol = symbol
  }

  function closeListViews() {
    managingLists = false
    listsSymbol = ""
  }

  // The keys go back to the surface once no view has them; a turn later,
  // so one view closing as another opens hands the keys straight across.
  onOwnsKeysChanged: if (!ownsKeys) Qt.callLater(function() { if (!root.ownsKeys) root.keysReleased() })

  function renameList(name, newName) {
    if (!service) return
    var problem = service.renameList(name, newName)
    if (problem !== "") manageLists.problem = problem
    else manageLists.stopEditing()
  }

  // Unticking All is a removal from All: its last symbol stays, and the
  // symbol it takes away has no lists left to show.
  function setMembership(name, member) {
    if (!service) return
    if (name === "" && !member && !Settings.canRemove(lists[0].symbols)) {
      say("Keep at least one symbol")
      return
    }
    var symbol = listsSymbol
    service.setMembership(symbol, name, member, watchlist.displayedSymbols)
    if (name === "" && !member) {
      closeListViews()
      offerUndo(symbol, "")
    }
  }

  // Closing stops what moves and keeps what is shown, so the surface fades
  // out as it was; resetInteraction puts it at rest when it next opens. A
  // pending search and a pending add are dropped, the wheel stops where it
  // is, a drag ends with every row where it is on screen, and the footer's
  // note stays, so nothing lands, glides, drops, or goes during the fade or
  // after it. What the header and band move stops with `still`.
  function freeze() {
    keepTyped()
    landing = ""
    noteTimer.stop()
    noteFade.stop()
    footer.freeze()
    watchlist.takeOver()
    motion.freeze()
    watchlist.pauseRows()
    watchlist.releaseDragInPlace()
  }

  // A name being typed outlives a close, as it outlives a click away: only
  // Escape or CANCEL throws it away. A rename is saved and a new list is
  // made, as Enter would, through the service, so the fading card shows
  // what it showed (a new list becomes the current one, with no search
  // opened for it). A name refused, a taken one or All, is kept as it was
  // left (`draft`) and comes back, saying why, as this surface next opens.
  // An empty field keeps nothing.
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
    }
  }

  // The name a close kept, refused, open again where it was typed. A rename
  // comes back only to its own list: one deleted, or renamed, or replaced
  // by a new list under its name meanwhile has another key, and the rename
  // has nothing left to act on.
  function resumeTyped() {
    var kept = draft
    draft = null
    if (!kept || !service) return
    if (kept.list !== "") {
      if (service.listKey(kept.list) !== kept.key) return
      openManageLists()
      manageLists.resumeRename(kept.list, kept.text, kept.problem)
    } else {
      openListMenu()
      listMenu.resumeNaming(kept.text, kept.problem)
    }
  }

  // At rest before the first frame: the rows in their places and the list on
  // a row, wherever a close stopped the wheel, and the look icon and the
  // breadth rule on what the surface now reads. A name a close kept, refused,
  // is open again where it was typed.
  function resetInteraction() {
    closeViews()
    showingHelp = false
    freeze()
    motion.reset()
    // The rows in the service's order, at rest, whatever a close held.
    watchlist.reopen()
    watchlist.snapToRow()
    header.settle()
    heroBand.settle()
    clearNote()
    footer.settle()
    hint = ""
    resumeTyped()
  }

  // A refusal stays a moment; an offer to undo long enough to act on it.
  // Its last 600 ms it fades, still taking a click while any of it shows,
  // and what it covered fades in after it, so the change under a click is
  // seen coming. Found in the walk of dev on 14 October: a click meant as
  // an undo, just after the note went, opened search.
  property real noteShown: 1
  Timer {
    id: noteTimer
    interval: (root.offered !== null ? 5000 : 2500) - noteFade.duration
    onTriggered: noteFade.start()
  }
  NumberAnimation {
    id: noteFade
    target: root
    property: "noteShown"
    from: 1
    to: 0
    duration: 600
    onFinished: {
      root.clearNote()
      footer.fadeIn()
    }
  }

  // The surface's own row, on the margins as the rows' fills are, not on
  // the words' edges: the longest closure's status (a holiday's name, the
  // next open, its zone) needs every pixel of the popup's width.
  HeaderStatus {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: root.margins
    statusText: root.headerText
    offersRetry: root.offersRetry
    retro: root.retro
    animal: root.animal
    ground: root.ground
    scrubbing: root.scrubT !== 0
    live: root.heroLive
    still: !root.surfaceOpen
    helpShown: root.showingHelp
    foreground: root.foreground
    dim: root.dim
    upColor: root.upColor
    downColor: root.downColor
    fontFamily: root.fontFamily
    onStyleRequested: function(v) { root.setStyle(v) }
    onHelpRequested: root.toggleHelp()
    onReplayRequested: root.replay()
    onRetryRequested: root.refreshRequested()
  }

  HeroBand {
    id: heroBand
    calendars: root.calendars
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.leftMargin: root.textLeft
    anchors.rightMargin: root.textRight
    anchors.topMargin: root.groupGap
    bandGap: root.bandGap
    visible: !root.showingHelp
    freshness: root.featuredFreshness
    retro: root.retro
    changeMode: root.changeMode
    scrubbing: root.scrubT !== 0
    live: root.heroLive
    still: !root.surfaceOpen
    held: root.chartLoading
    dimmed: motion.dimmed
    loadingText: root.loadingText
    foreground: root.foreground
    dim: root.dim
    dimmer: root.dimmer
    upColor: root.upColor
    downColor: root.downColor
    ghost: root.ghost
    ground: root.ground
    fontFamily: root.fontFamily
    // The chart's symbol, or before any chart is in, the one coming, which
    // the header names as it loads: never a dash in its place.
    symbol: root.chartSymbol || root.featuredSymbol
    view: root.featured
    quote: root.featuredQuote
    day: root.featuredDay
    latest: motion.latest
    geometry: root.featuredGeometry
    scrubX: root.scrubX
    reveal: motion.reveal
    replayX: motion.replayX
    chartHeight: root.chartGivesWay ? root.shownChartHeight : root.chartHeight
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
    baselineText: root.baselineText
    yearLine: root.yearLine
    now: root.now
    changeCycles: !root.historyShown
    onChangeClicked: root.cycleChangeMode()
    onOrderClicked: root.cycleOrder()
    onOrderReverseClicked: root.reverseOrder()
    onListClicked: root.listMenuOpen ? root.closeListMenu() : root.openListMenu()
    onScrubRequested: function(fraction) { motion.scrubTo(fraction) }
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
    visible: root.rowsShown
    view: root.view
    quotes: root.quotes
    entries: root.entries
    featuredSymbol: root.featuredSymbol
    scrubShown: root.watchlistScrubShown
    changeMode: root.changeMode
    now: root.now
    owed: root.owed
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
    // A turn later: the change that arranged the rows is still being told.
    onArranged: Qt.callLater(root.land)
    onSettlingChanged: Qt.callLater(root.featureLanding)
    onRowRested: Qt.callLater(root.featureLanding)
    ground: root.ground
    onFeatureRequested: function(symbol) { root.featureSymbol(symbol) }
    onRemoveRequested: function(symbol) { root.removeRow(symbol) }
    onManualOrderRequested: function(symbols) {
      root.cancelAdding()
      if (root.service) root.service.setManualOrder(symbols)
    }
    onMoveRefused: root.say("Switch to manual order to move rows")
    onListsRequested: function(symbol) { root.openSymbolLists(symbol) }
  }

  // In the rows' place as it opens: its field where the first row was, its
  // answers under it, laid out at the body's height while the card's edge
  // eases there.
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
    active: root.adding && root.surfaceOpen
    retro: root.retro
    foreground: root.foreground
    dim: root.dim
    dimmer: root.dimmer
    fontFamily: root.fontFamily
    gutter: root.gutter
    // What to type, and the list it adds to; short, so a list's name fits
    // the popup's field.
    placeholder: root.listName !== "" ? "Symbol or company for " + root.listName + "…" : "Search a symbol or company…"
    members: root.members
    onPicked: function(symbol) { root.acceptSymbol(symbol) }
    onChose: function(symbol) { root.previewTo(symbol) }
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

  // Only a list with no members at all says so: one whose add is still
  // arriving is not empty, its row is coming. It says so over the rows on
  // show, so a closing surface, which keeps its rows, says nothing.
  Text {
    objectName: "emptyList"
    visible: root.members.length === 0 && watchlist.displayedSymbols.length === 0
      && !root.showingHelp && !root.adding && !root.listViewOpen
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

  // At the body's visible bottom, the edge, one gap under the list's rows;
  // it rides the popup's easing edge. It carries the surface's ground and
  // stacks over the rows and the empty list's line, so a growing edge
  // carries it across them without drawing its words through a row.
  AddFooter {
    id: footer
    objectName: "footer"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.margins
    anchors.rightMargin: root.margins
    y: root.edge - root.margins - height
    visible: !root.showingHelp && !root.adding && !root.listViewOpen
    retro: root.retro
    foreground: root.foreground
    dim: root.dim
    fontFamily: root.fontFamily
    gutter: root.gutter
    rowHeight: root.rowHeight
    note: root.note
    noteAction: root.offered !== null ? " · click to undo" : ""
    noteOpacity: root.noteShown
    notice: root.notice
    hint: root.hint
    ground: root.ground
    label: root.listName !== "" ? "+  Add a symbol to " + root.listName : "+  Add a symbol"
    acts: root.offered !== null || !root.settingsUnreadable
    onHoveredChanged: root.holdNote()
    // The click acts on what the footer shows: an undo offer undoes, the
    // update's notice restarts the shell, and the file's does nothing,
    // nor does a refusal over it; a refusal otherwise, or the label, adds.
    onClicked: {
      if (root.offered !== null) root.undoRemoval()
      else if (root.settingsUnreadable) return
      else if (root.note === "" && root.updatedTo !== "") root.updates.restart()
      else root.startAdding()
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
    foreground: root.foreground
    dim: root.dim
    fontFamily: root.fontFamily
    retro: root.retro
    onCloseRequested: root.showingHelp = false
  }

  // A closing surface takes no press, click, or wheel: the popup's card
  // still shows while it fades, and nothing on it acts. Hover passes, so
  // nothing under the pointer changes as the card goes.
  MouseArea {
    objectName: "closedShield"
    anchors.fill: parent
    z: 20
    visible: !root.surfaceOpen
    acceptedButtons: Qt.AllButtons
    onWheel: function(wheel) { wheel.accepted = true }
  }

  // A click anywhere off the open menu closes it, and nothing under it acts,
  // not even to a resting pointer: the chart would scrub. While a new list's
  // name is typed, it keeps the name as Enter does: the list is made, or
  // the menu stays open saying why not; an empty field just closes.
  MouseArea {
    anchors.fill: parent
    visible: root.listMenuOpen
    hoverEnabled: true
    z: 9
    onClicked: listMenu.typedName.trim() !== "" ? root.createList(listMenu.typedName) : root.closeListMenu()
    onWheel: function(wheel) { wheel.accepted = true }
  }

  ListMenu {
    id: listMenu
    objectName: "listMenu"
    visible: root.listMenuOpen
    active: root.listMenuOpen && root.surfaceOpen
    z: 10
    x: root.margins
    y: root.listMenuTop
    maxHeight: root.height - root.listMenuTop - root.groupGap - footer.height - root.margins
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
  }
}
