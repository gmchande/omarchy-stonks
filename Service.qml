import QtQuick
import Quickshell.Io
import "Asks.js" as Asks
import "Calendar.js" as Calendar
import "Chart.js" as Chart
import "Freshness.js" as Freshness
import "History.js" as History
import "Overnight.js" as Overnight
import "Quote.js" as Quote
import "Settings.js" as Settings
import "Rows.js" as Rows
// What every surface reads and acts through: what you follow and look at,
// the lists file that keeps it (~/.config/omarchy/<id>.json, which only this
// service reads and writes), the feeds and what is asked of them, the saved
// prices, the screens and the clock. Each job sits under its own banner.
Item {
  id: root

  // The plugin's id, the manifest's (`Plugin`): "" until the shell hands
  // it over, and meanwhile the lists file and the cache are left alone.
  property string pluginId: ""
  // Whether `omarchy plugin update` can update this copy (`Updates`):
  // where it can't, GitHub is never asked for main's version.
  property bool updatable: false

  // ---- What you follow and look at

  // All: every symbol, fetched once whatever lists hold it.
  property var allSymbols: Settings.fileSettings(null).symbols
  // "" is All.
  readonly property string listName: fileSettings.list
  readonly property var symbols: Settings.listSymbols(fileSettings)
  readonly property string order: Settings.listOrder(fileSettings)
  readonly property bool reversed: Settings.listReversed(fileSettings)
  readonly property string range: fileSettings.range
  // The panel's first-run hint has shown.
  readonly property bool hinted: fileSettings.hinted
  readonly property string changeMode: fileSettings.changeMode
  readonly property bool retro: fileSettings.style === "retro"
  readonly property bool soundsOn: fileSettings.sounds
  readonly property int refreshIntervalSec: fileSettings.refreshIntervalSec
  property var lastRemoval: null
  property string listsHeld: ""
  // The same arrays until what they hold changes, so a save of a range,
  // a list or the featured stock leaves the feeds and each surface's list
  // views as they are.
  property var lists: Settings.listChoices(Settings.fileSettings(null))
  onFileSettingsChanged: {
    var held = Settings.listsHeld(root.fileSettings)
    if (held === root.listsHeld) return
    root.listsHeld = held
    if (JSON.stringify(root.fileSettings.symbols) !== JSON.stringify(root.allSymbols)) root.allSymbols = root.fileSettings.symbols
    root.lists = Settings.listChoices(root.fileSettings)
    root.lastRemoval = null
  }

  // Each list's identity for the session, for what is kept by list and not
  // saved: a rename keeps it; a name a rename or delete freed is another
  // list, and so is one renamed in the file.
  property var listKeys: ({})
  property int listKeyCount: 0
  function listKey(name) { return root.listKeys[name] || "=" + name }
  function keyList(name, key) {
    var next = Object.assign({}, root.listKeys)
    next[name] = key
    root.listKeys = next
  }
  // Added symbols with no first answer yet, quote or failure: saved and
  // fetched, but no list shows them until it comes.
  property var arriving: []
  // { symbol, before }: the stock an add from search made featured before
  // its first answer, and the one featured before it.
  property var featuredTaken: null

  function answered(symbol) {
    return !!feed.quotes[symbol] || !!(feed.entries[symbol] && feed.entries[symbol].status === "failed")
  }

  // One that was made featured and failed hands the place back.
  function settleArrivals() {
    var still = root.arriving.filter(function(s) { return root.allSymbols.indexOf(s) >= 0 && !root.answered(s) })
    if (still.length !== root.arriving.length) root.arriving = still
    var taken = root.featuredTaken
    if (!taken || still.indexOf(taken.symbol) >= 0) return
    root.featuredTaken = null
    if (root.view.featured === taken.symbol && !feed.quotes[taken.symbol]) root.feature(taken.before)
  }

  // ---- What the surfaces show

  // What the surfaces show, as one value, so each change of it is whole.
  // Read from the settings and the feeds, not the bindings above, which may
  // not have caught up yet.
  readonly property var view: {
    var all = fileSettings.symbols
    var order = Settings.listOrder(fileSettings)
    var reversed = Settings.listReversed(fileSettings)
    var rows = Settings.listSymbols(fileSettings).filter(function(s) { return arriving.indexOf(s) < 0 })
    var named = String(fileSettings.featured || "").toUpperCase()
    var featured = all.indexOf(named) >= 0 ? named : (all[0] || "")
    var range = fileSettings.range
    var chart = root.chartOf(featured, range, feed)
    return {
      featured: featured,
      range: range,
      list: fileSettings.list,
      listKey: root.listKey(fileSettings.list),
      order: order,
      reversed: reversed,
      rows: rows,
      shown: Rows.shownOrder(root.heldOrder, Rows.sortedSymbols(rows, feed.quotes, order, reversed,
        fileSettings.changeMode, order === "manual" ? null : root.newestTrades)),
      allSymbols: all,
      // Null while on its way: each surface keeps the chart it has on screen.
      chart: chart
    }
  }
  readonly property var previewView: {
    var symbol = root.previewSymbol
    if (!symbol) return view
    var own = !!previewFeed.quotes[symbol] || !!previewFeed.entries[symbol]
    return Object.assign({}, view, { featured: symbol, chart: root.chartOf(symbol, view.range, own ? previewFeed : feed) })
  }
  // A symbol's chart over a range, from what a quote feed holds. It reads the
  // feed's receipts only for a symbol without a quote, and the histories only
  // off 1D, so a receipt for a quoted symbol on the day recomputes nothing.
  function chartOf(symbol, range, quoteFeed) {
    var quotes = quoteFeed.quotes
    return root.keptDay(symbol, Chart.viewChart(symbol, range, quotes, quotes[symbol] ? ({}) : quoteFeed.entries,
      range === "1D" ? ({}) : historyFeed.entries, overnightFeed.entries, allDayFeed.entries, calendars, root.viewSlideAt),
      overnightFeed.entries, allDayFeed.entries)
  }
  readonly property string featuredSymbol: view.featured
  readonly property var shown: view.shown
  // The chart to show: `chart`, with the day built for it before while that
  // was built from the same objects, its quote and an all-day listing's
  // trades and reach, and while its start hasn't slid. So an answer for
  // another symbol repaints nothing, nor does a clock that moves no start,
  // and a preview's Yahoo day never stands in once it is added. `builtDays`
  // is kept from each chart the views show (`keepDay`); it doesn't notify.
  readonly property var builtDays: ({})
  function keptDay(symbol, chart, nights, allDay) {
    if (!chart || !chart.quote || chart.day === chart.quote) return chart
    var made = root.dayMadeFrom(symbol, chart, nights, allDay)
    var built = builtDays[symbol]
    if (built && built.quote === made.quote && built.bars === made.bars && built.through === made.through && built.start === made.start)
      return Object.assign({}, chart, { day: built.day, latest: built.latest })
    return chart
  }
  function keepDay(symbol, chart) {
    if (!chart || !chart.quote || chart.day === chart.quote) return
    if (builtDays[symbol] && builtDays[symbol].day === chart.day) return
    builtDays[symbol] = Object.assign(root.dayMadeFrom(symbol, chart, overnightFeed.entries, allDayFeed.entries), { day: chart.day, latest: chart.latest })
  }
  function dayMadeFrom(symbol, chart, nights, allDay) {
    var tradability = allDay ? allDay[symbol] : null
    var night = tradability && tradability.allDay ? nights[symbol] : null
    return { quote: chart.quote, bars: night ? night.bars : null, through: night ? night.through : null,
      start: chart.day.axis ? chart.day.axis.start : null }
  }
  onPreviewViewChanged: keepDay(previewView.featured, previewView.chart)

  // The price on top on the pill, the rows, and the hero. A stock's is worked
  // out again only when what it is read from changes (`Chart.newestTradeOf`):
  // each builds the stock's whole day, and a price that lands changes one
  // stock's, not every stock's. The same object while no stock's changes, so
  // no row works out its figures again.
  property var newestTrades: ({})
  // Each stock's newest price, with what it was worked out from.
  property var newestFrom: ({})
  function workOutNewest() {
    var nights = overnightFeed.entries
    var allDay = allDayFeed.entries
    var from = {}
    var out = {}
    var count = 0
    var same = true
    root.allSymbols.forEach(function(symbol) {
      var quote = feed.quotes[symbol]
      if (!quote) return
      var night = nights[symbol]
      var bars = night ? night.bars : null
      var through = night ? night.through : null
      var trades = allDay[symbol] ? allDay[symbol].allDay : null
      var had = root.newestFrom[symbol]
      from[symbol] = had && had.quote === quote && had.bars === bars && had.through === through && had.trades === trades ? had
        : { quote: quote, bars: bars, through: through, trades: trades, newest: Chart.newestTradeOf(symbol, quote, nights, allDay, root.calendars) }
      if (!from[symbol].newest) return
      out[symbol] = from[symbol].newest
      count++
      same = same && root.newestTrades[symbol] === out[symbol]
    })
    root.newestFrom = from
    if (!same || count !== Object.keys(root.newestTrades).length) root.newestTrades = out
  }
  onNightsChanged: workOutNewest()
  onAllDayChanged: workOutNewest()

  // Held until every price the open asked for is in, or a site's pause
  // holds the rest once every run out is read, so the rows move once. A
  // gate hears a run before its feed reads it (`FetchRun`).
  property var heldOrder: null
  function releaseOrder() {
    if (!root.heldOrder) return
    var out = feed.landing.length > 0 || overnightFeed.busy || allDayFeed.busy
    var waiting = out || feed.busy || !!root.overnightWanted()
    if (out || (waiting && !yahooGate.paused && !robinhoodGate.paused)) return
    root.heldOrder = null
  }
  onOrderChanged: root.heldOrder = null
  onReversedChanged: root.heldOrder = null
  onChangeModeChanged: root.heldOrder = null
  onListNameChanged: root.heldOrder = null
  onListsHeldChanged: root.heldOrder = null

  // ---- Open surfaces and the search's preview

  // Surfaces open where a screen shows them (`StonksBody.onScreen`).
  property var openSurfaces: []

  // The clock catches up at once and moves on at the pace that now holds.
  function surfaceShown(surface, open) {
    var others = root.openSurfaces.filter(function(s) { return s !== surface })
    var next = open ? others.concat([surface]) : others
    if (next.length === root.openSurfaces.length) return
    root.openSurfaces = next
    if (!open) {
      root.sights = root.sights.filter(function(s) { return s.surface !== surface })
      root.drawingIn(surface, false)
    }
    if (open && Settings.normalizeOrder(root.order) === "pct") root.heldOrder = root.view.shown
    // The open's quote run goes a turn later, once the surface has said
    // which rows are in sight (`rowsSeen`), so it asks for those first.
    if (open) {
      root.opening = true
      root.saveWaitsFor = null
      Qt.callLater(function() {
        root.opening = false
        feed.sendWaiting()
      })
    }
    root.tick()
    root.showHistory(false)
    root.askOvernight()
    root.askDue()
    Qt.callLater(root.releaseOrder)
  }
  property bool opening: false

  // While a chart draws in, the quote and night feeds read no answer, so
  // reading never stutters it. Only an open surface counts: one taken down
  // mid-draw-in, as a rebuilt bar takes its panel, can start its draw-in
  // again as it goes.
  property var drawing: []
  function drawingIn(surface, running) {
    var others = root.drawing.filter(function(s) { return s !== surface })
    var next = running && root.openSurfaces.indexOf(surface) >= 0 ? others.concat([surface]) : others
    if (next.length !== root.drawing.length) root.drawing = next
  }
  // The search result a surface's hero shows unadded. Never saved.
  property string previewSymbol: ""
  // One search previews at a time: another that starts choosing takes it.
  property var previewSurface: null
  // Nothing is asked for a preview until the choice rests on it.
  property bool previewRests: false
  readonly property bool previewShown: previewRests && openSurfaces.indexOf(previewSurface) >= 0
  // { symbol, exchange, instrumentType } or null.
  property var previewResult: null

  // "" ends a preview, and only the search previewing can say it. Nothing
  // is asked until the choice rests, so arrowing past a result asks nothing.
  // `result` says what kind of listing it is before its quote does.
  function preview(surface, symbol, result) {
    var s = String(symbol || "").trim().toUpperCase()
    if (!s && surface !== root.previewSurface) return
    if (s === root.previewSymbol && surface === root.previewSurface) return
    var before = root.previewSurface
    // A choice that moves on has not rested on the next one.
    root.previewRests = false
    root.previewSurface = s ? surface : null
    root.previewSymbol = s
    root.previewResult = s && result && String(result.symbol || "").toUpperCase() === s ? result : null
    if (s) previewRest.restart()
    else previewRest.stop()
    root.showHistory(false)
    if (before && before !== root.previewSurface && s) root.previewTaken(before)
  }

  signal previewTaken(var surface)

  Timer {
    id: previewRest
    interval: 250
    onTriggered: {
      root.previewRests = true
      root.showHistory(false)
    }
  }
  // What a preview held back while out of sight goes once a screen shows it.
  onPreviewShownChanged: if (previewShown) {
    previewFeed.sendWaiting()
    askOvernight()
  }

  // ---- Changes to the lists

  // A stock chosen ends an add's hold on the place (`featuredTaken`).
  function feature(symbol, settles) {
    var s = String(symbol || "").toUpperCase()
    if (root.allSymbols.indexOf(s) < 0) return
    root.featuredTaken = null
    root.persist({ featured: s }, settles)
  }

  // From outside the list, its first or last row.
  function featureStep(delta) {
    var shown = root.view.shown
    if (shown.length === 0) return
    var at = shown.indexOf(root.view.featured)
    root.feature(at < 0 ? shown[delta > 0 ? 0 : shown.length - 1]
      : shown[(at + delta + shown.length) % shown.length], true)
  }

  function summon(symbol, range) {
    var values = {}
    var s = String(symbol || "").toUpperCase()
    if (s && root.allSymbols.indexOf(s) >= 0) {
      values.featured = s
      root.featuredTaken = null
    }
    if (History.historyRanges().indexOf(range) >= 0) values.range = range
    if (Object.keys(values).length) root.persist(values)
  }

  function setRange(value) {
    if (History.historyRanges().indexOf(value) >= 0) root.persist({ range: value })
  }

  function addSymbol(symbol) {
    var s = String(symbol || "").trim().toUpperCase()
    if (s && s === root.previewSymbol && previewFeed.entries[s])
      feed.restore(s, previewFeed.quotes[s] || null, previewFeed.entries[s])
    // A symbol already in All is a row at once.
    if (s && root.allSymbols.indexOf(s) < 0 && root.arriving.indexOf(s) < 0 && !root.answered(s))
      root.arriving = root.arriving.concat([s])
    var previewed = s !== "" && s === root.previewSymbol
    var coming = previewed && root.arriving.indexOf(s) >= 0
    var next = Settings.withSymbolAdded(root.fileSettings, s)
    // From an add still on its way, hand back the stock featured before it.
    var taken = root.featuredTaken
    var before = taken && taken.symbol === root.view.featured && !feed.quotes[taken.symbol] ? taken.before : root.view.featured
    if (coming) root.featuredTaken = { symbol: s, before: before }
    if (coming || (previewed && !!feed.quotes[s])) next.featured = s
    root.save(next)
  }

  // `shown`: the rows as the surface shows them, whose neighbour is featured
  // next.
  function removeSymbol(symbol, shown) {
    root.remove(symbol, Settings.withMembership(root.fileSettings, symbol, root.listName, false, shown || root.shown))
  }

  // "" is All: unticking it is a removal, which can be undone.
  function setMembership(symbol, name, member, shown) {
    var next = Settings.withMembership(root.fileSettings, symbol, name, member, shown || root.shown)
    if (name === "" && !member) root.remove(symbol, next)
    else root.save(next)
  }

  function remove(symbol, next) {
    var before = root.fileSettings
    var quote = feed.quotes[symbol] || null
    var entry = feed.entries[symbol] || null
    root.save(next)
    root.lastRemoval = { symbol: symbol, before: before, left: root.fileSettings.featured, quote: quote, entry: entry }
  }

  // Watched again first (`askDue`), so a run landing before the restore's
  // own look at the schedule can't drop the ask as unwatched.
  function undoRemoval(symbol) {
    if (!root.lastRemoval || root.lastRemoval.symbol !== symbol) return
    var removal = root.lastRemoval
    // Only once.
    root.lastRemoval = null
    if (removal.quote) feed.restore(symbol, removal.quote, removal.entry)
    root.save(Settings.withRemovalUndone(root.fileSettings, removal.before, symbol, removal.left))
    root.askDue()
    feed.ask([symbol], root.wallSecond())
  }

  // Members still arriving keep their places, so the saved order holds
  // every member.
  function setManualOrder(rows) {
    var members = root.symbols
    var next = rows.slice()
    for (var i = 0; i < members.length; i++)
      if (next.indexOf(members[i]) < 0) next.splice(Math.min(i, next.length), 0, members[i])
    root.save(Settings.withManualOrder(root.fileSettings, next))
  }

  function setOrder(order) {
    root.save(Settings.withListOrder(root.fileSettings, order))
  }

  function reverseOrder() {
    root.save(Settings.withListReversed(root.fileSettings))
  }

  function switchList(name) {
    root.persist({ list: name })
  }

  // Returns why not, or "".
  function createList(name) {
    var problem = Settings.listNameProblem(name, root.fileSettings.lists)
    if (problem === "") root.save(Settings.withListCreated(root.fileSettings, name))
    return problem
  }

  // The new name takes the list's key before the save, so no view shows the
  // list under another key; the freed old name takes a new one after.
  function renameList(name, newName) {
    var problem = Settings.renameProblem(root.fileSettings, name, newName)
    var i = Settings.listIndex(root.fileSettings.lists, name)
    if (problem !== "" || i < 0) return problem
    var old = root.fileSettings.lists[i].name
    var now = Settings.listName(newName)
    if (old !== now) root.keyList(now, root.listKey(old))
    root.save(Settings.withListRenamed(root.fileSettings, name, newName))
    if (old !== now) root.keyList(old, "#" + (++root.listKeyCount))
    return problem
  }

  function moveList(name, delta) {
    root.save(Settings.withListMoved(root.fileSettings, name, delta))
  }

  function deleteList(name) {
    var i = Settings.listIndex(root.fileSettings.lists, name)
    if (i < 0) return
    var old = root.fileSettings.lists[i].name
    root.save(Settings.withListDeleted(root.fileSettings, name))
    root.keyList(old, "#" + (++root.listKeyCount))
  }

  // ---- The lists file

  // Its reading, its writing and its read-back are `ListsFile`'s. The
  // service keeps what the file holds and the ways to change it.
  ListsFile {
    id: listsFile
    pluginId: root.pluginId
    files: ownerOnly
    onStarted: {
      feed.seed(root.parseSavedQuotes())
      // What the seed put in is what the file holds.
      root.quotesUnsaved = false
      root.askDue()
    }
    onSaveChecked: function(saved) { root.saveChecked(saved) }
  }
  // Bindings, not aliases: an alias reads nothing until the file's own
  // bindings have run, and the view is worked out before that.
  readonly property var fileSettings: listsFile.fileSettings
  readonly property string listsPath: listsFile.path
  readonly property bool ready: listsFile.ready
  readonly property bool listsUnreadable: listsFile.unreadable
  readonly property bool editsUnsaved: listsFile.editsUnsaved
  readonly property bool saveFailed: listsFile.saveFailed
  signal saveChecked(bool saved)
  function persist(values, settles) { listsFile.persist(values, settles) }
  function save(next) { listsFile.save(next) }
  function saveAgain() { listsFile.saveAgain() }

  // ---- The feeds

  FileView {
    id: calendarFile
    path: Qt.resolvedUrl("calendars.json")
    blockLoading: true
    printErrors: false
  }

  readonly property var calendars: {
    try { return JSON.parse(calendarFile.text()) } catch (e) { return null }
  }
  readonly property var centExchanges: Calendar.centExchanges(calendars)

  Gate {
    id: yahooGate
    host: "Yahoo"
    clock: root
    onPausedChanged: root.releaseOrder()
    onPausedUntilChanged: root.armClock()
    // Yahoo answering again says the network is back.
    onReopened: {
      root.showHistory(false)
      fundamentalsFeed.retry()
      releaseFeed.askAgain()
      root.yahooBack()
    }
  }
  signal yahooBack()
  readonly property alias yahooGate: yahooGate
  // Stonks asks a few times a minute: the budget only stops a runaway.
  Gate {
    id: robinhoodGate
    host: "Robinhood"
    clock: root
    capacity: 20
    perMinute: 10
    onPausedChanged: root.releaseOrder()
    onPausedUntilChanged: root.armClock()
  }
  Gate {
    id: githubGate
    host: "GitHub"
    clock: root
    onPausedUntilChanged: root.armClock()
  }

  QuoteFeed {
    id: feed
    symbols: root.ready ? root.allSymbols : []
    watched: root.watched
    featured: root.view.featured
    charted: [root.view.featured].concat(root.previewShown && root.allSymbols.indexOf(root.previewSymbol) >= 0 ? [root.previewSymbol] : [])
    reading: function() { return Asks.readingOrder(root.view.featured, root.sights, root.view.shown, root.allSymbols) }
    holding: root.drawing.length > 0
    onBusyChanged: Qt.callLater(root.releaseOrder)
    onLandingChanged: Qt.callLater(root.releaseOrder)
    now: root.now
    clock: root
    mayAsk: function() { return !root.opening && root.screensClear() }
    gate: yahooGate
    centExchanges: root.centExchanges
    calendars: root.calendars
  }
  readonly property var quotes: feed.quotes
  readonly property var entries: feed.entries
  readonly property var asked: feed.asked
  // Those waiting on Yahoo, from when: freshness's overdue counts from it.
  readonly property var owed: feed.owed
  // Asked under `Freshness.ASKED_GRACE` ago, timed to the millisecond: in the
  // clock's whole seconds the grace would end anywhere from 1 to 2 s on.
  property var asking: ({})
  property var askedMs: ({})
  function trackAsks() {
    var nowMs = Date.now()
    var since = {}
    var inGrace = {}
    var ends = 0
    for (var s in feed.asked) {
      since[s] = s in root.askedMs ? root.askedMs[s] : nowMs
      var end = since[s] + Freshness.ASKED_GRACE * 1000
      if (end > nowMs) {
        inGrace[s] = true
        if (!ends || end < ends) ends = end
      }
    }
    root.askedMs = since
    if (Object.keys(inGrace).join(",") !== Object.keys(root.asking).join(",")) root.asking = inGrace
    if (ends) {
      graceTimer.interval = Math.max(1, ends - nowMs)
      graceTimer.restart()
    } else graceTimer.stop()
  }
  Connections {
    target: feed
    function onAskedChanged() { root.trackAsks() }
  }
  Timer { id: graceTimer; onTriggered: root.trackAsks() }

  HistoryFeed {
    id: historyFeed
    gate: yahooGate
    mayAsk: function() { return root.screensClear() }
    clock: root
    centExchanges: root.centExchanges
    inUse: root.chartsInUse
    onEntriesChanged: {
      var next = Asks.nextHistory(root.historyCharts(), root.view.range, historyFeed.entries, root.historyOwed)
      if (next) historyFeed.request(next.symbol, root.view.range, next.force)
    }
    onIdle: root.fetchAhead()
    onMissed: function(key) {
      var missed = Object.assign({}, root.aheadMissed)
      missed[key] = true
      root.aheadMissed = missed
    }
  }
  readonly property var histories: historyFeed.entries
  readonly property var fundamentals: fundamentalsFeed.entries
  readonly property var rates: fundamentalsFeed.rates
  QuoteFeed {
    id: previewFeed
    symbols: root.previewRests && root.previewSymbol !== "" && root.allSymbols.indexOf(root.previewSymbol) < 0
      ? [root.previewSymbol] : []
    now: root.now
    clock: root
    mayAsk: function() { return root.previewShown && root.screensClear() }
    gate: yahooGate
    centExchanges: root.centExchanges
    calendars: root.calendars
    bulk: false
    onQuotesChanged: root.askOvernight()
  }
  readonly property var previewEntries: previewFeed.entries

  function chartedOnShow() {
    return root.openSurfaces.length > 0 ? [root.view.featured].concat(root.previewShown ? [root.previewSymbol] : []) : []
  }
  // With nothing open it reads no quote, so the pill's prices don't work it
  // out again.
  readonly property var fundamentalsWanted: {
    var charted = root.chartedOnShow()
    return charted.length > 0 ? Asks.fundamentalsWanted(charted, feed.quotes, previewFeed.quotes) : []
  }
  FundamentalsFeed {
    id: fundamentalsFeed
    wanted: root.fundamentalsWanted
    now: root.now
    clock: root
    gate: yahooGate
    mayAsk: function() { return root.screensClear() }
  }
  AllDayFeed {
    id: allDayFeed
    gate: robinhoodGate
    onEntriesChanged: Qt.callLater(root.askOvernight)
    onBusyChanged: Qt.callLater(root.releaseOrder)
  }
  OvernightFeed {
    id: overnightFeed
    gate: robinhoodGate
    holding: root.drawing.length > 0
    onEntriesChanged: Qt.callLater(root.askOvernight)
    onBusyChanged: Qt.callLater(root.releaseOrder)
  }
  readonly property var nights: overnightFeed.entries
  readonly property var allDay: allDayFeed.entries
  // Whether the night trades now, and the listings whose newest price may
  // be a trade Robinhood failed to send meanwhile: their "!".
  readonly property bool nightTrading: {
    var cal = Overnight.overnightMarket(calendars)
    var night = cal ? Overnight.nightAt(cal, now) : null
    return !!night && night.open
  }
  readonly property var nightFailed: Overnight.nightFailures(allDayFeed.entries, overnightFeed.entries, nightTrading)
  // The feeds themselves, for whoever waits until no run is out.
  readonly property var feeds: ({ quotes: feed, preview: previewFeed, overnight: overnightFeed })
  // By Yahoo's quote, never Robinhood's answer: Robinhood is asked whether
  // it trades each all day.
  readonly property var overnightSymbols: allSymbols.filter(function(s) {
    return !!feed.quotes[s] && Overnight.hasOvernight(feed.quotes[s], calendars)
  })
  // Only these draw Robinhood's trades.
  readonly property var allDaySymbols: overnightSymbols.filter(function(s) {
    return !!allDayFeed.entries[s] && allDayFeed.entries[s].allDay
  })
  // Where Robinhood's trades fill stretches Yahoo left empty, each logged
  // once. Worked out again for a stock only when its quote or trades change:
  // 150 stocks take about 28 ms of the shell's thread. Neither notifies.
  readonly property var fills: ({})
  readonly property var saidFills: ({})
  readonly property var fillsFrom: [allDaySymbols, feed.quotes, overnightFeed.entries, allDayFeed.entries, previewFeed.quotes, previewSymbol]
  onFillsFromChanged: Qt.callLater(root.sayFills)
  function sayFills() {
    var previewed = root.previewSymbol
    var tradability = previewed ? allDayFeed.entries[previewed] : null
    var preview = tradability && tradability.allDay && root.allSymbols.indexOf(previewed) < 0 ? previewFeed.quotes[previewed] : null
    var symbols = preview ? root.allDaySymbols.concat([previewed]) : root.allDaySymbols
    symbols.forEach(function(symbol) {
      var quote = symbol === previewed && preview ? preview : feed.quotes[symbol]
      var night = overnightFeed.entries[symbol]
      var had = root.fills[symbol]
      if (!quote || !night || (had && had.quote === quote && had.bars === night.bars)) return
      var stretches = Overnight.filledStretches(quote, night.bars)
      root.fills[symbol] = { quote: quote, bars: night.bars, stretches: stretches }
      stretches.forEach(function(stretch) {
        var key = symbol + " " + stretch.from + " " + stretch.to
        if (root.saidFills[key]) return
        root.saidFills[key] = true
        var sessions = []
        stretch.bars.forEach(function(b) {
          var name = b.s === "pre" ? "pre-market" : "after-hours"
          if (sessions.indexOf(name) < 0) sessions.push(name)
        })
        console.warn("stonks: " + symbol + " filled from Robinhood's " + stretch.bars.length + " " + sessions.join(" and ") + " trades between "
          + new Date(stretch.from * 1000).toISOString() + " and " + new Date(stretch.to * 1000).toISOString() + ", where Yahoo sent no bar")
      })
    })
  }

  ReleaseFeed {
    id: releaseFeed
    ready: root.ready && root.fileSettings.updateCheck && root.updatable
    now: root.now
    clock: root
    mayAsk: function() { return root.screensClear() }
    gate: githubGate
  }
  // "" until GitHub names one.
  readonly property alias mainVersion: releaseFeed.version

  // ---- What is asked, and when

  // The pills in the bars (`BarWidget`). With none, the stock you last
  // looked at is asked for only while a surface is open.
  property var pills: []
  function pillShown(pill, shown) {
    var others = root.pills.filter(function(p) { return p !== pill })
    root.pills = shown ? others.concat([pill]) : others
  }
  readonly property bool pillInBar: pills.length > 0
  onPillInBarChanged: {
    askDue()
    askOvernight()
  }

  property var watched: []

  // `askDue` reads the wall clock, which `now` trails between ticks while
  // nothing is open.
  property int dueAt: 0
  property int askedMinute: -1
  function askDue() {
    if (!root.ready) return
    var now = root.wallSecond()
    root.askedMinute = Math.floor(now / 60)
    var open = root.openSurfaces.length > 0
    var featured = root.view.featured
    var calNow = Asks.calendarsAt(root.calendars, now)
    var watched = Asks.watchedSymbols(root.allSymbols, root.pillInBar ? featured : "", open)
    if (watched.join(",") !== root.watched.join(",")) root.watched = watched
    var asks = Asks.quotesDue(watched, feed.entries, feed.asked, feed.quotes, root.chartedOnShow(), featured, now, root.refreshIntervalSec, calNow)
    root.dueAt = asks.next
    if (asks.due.length > 0) feed.ask(asks.due, now)
  }
  onPreviewRestsChanged: askDue()
  onRefreshIntervalSecChanged: askDue()
  // Robinhood's two questions go side by side, so a 1D chart waits for one
  // answer, never two in a row.
  function askOvernight() {
    if (!root.ready) return
    var open = root.openSurfaces.length > 0
    var asks = root.overnightWanted()
    if (!asks || !root.screensClear()) return
    // The pill's own ask waits for a request already out.
    if (!open && (allDayFeed.busy || overnightFeed.busy)) return
    allDayFeed.fetch(asks.tradability, root.now)
    overnightFeed.fetch(asks.trades, root.now)
  }
  function overnightWanted() {
    var previewed = root.previewSymbol
    return Asks.overnightAsks({
      open: root.openSurfaces.length > 0,
      pill: root.pillInBar,
      featured: root.view.featured,
      quoteEntries: feed.entries,
      quotes: feed.quotes,
      overnightSymbols: root.overnightSymbols,
      allSymbols: root.allSymbols,
      inSight: root.rowsInSight(),
      preview: previewed,
      previewShown: root.previewShown,
      // By search's result before its quote, so Robinhood is asked as Yahoo is.
      previewQuote: previewFeed.quotes[previewed] || feed.quotes[previewed] || root.previewResult,
      allDay: allDayFeed.entries,
      nights: overnightFeed.entries,
      now: root.now,
      calendars: root.calendars
    })
  }
  onOvernightSymbolsChanged: askOvernight()
  onAllDaySymbolsChanged: askOvernight()

  // One request per change of symbol or range, read from the view, so both
  // together never ask for a mixed pair.
  property string chartOnShow: ""
  onViewChanged: {
    keepDay(view.featured, view.chart)
    var chart = view.featured + "|" + view.range
    if (chart === chartOnShow) return
    var rangeLeft = chartOnShow !== "" && chartOnShow.split("|")[1] !== view.range
    chartOnShow = chart
    if (root.featuredTaken && view.featured !== root.featuredTaken.symbol) root.featuredTaken = null
    // Their keys name the range, so missed charts on the last are tried
    // again on a return; charts fetched ahead stay, for the cache to let go.
    if (rangeLeft) root.aheadMissed = ({})
    showHistory(false)
    askDue()
    askOvernight()
  }

  // Written once the turn is over: an undo restores the quote before All
  // takes the symbol back, and a write between them left it out.
  onQuotesChanged: {
    workOutNewest()
    settleArrivals()
    root.quotesUnsaved = true
    Qt.callLater(flushQuotes)
  }
  // Every run's answers land here, a quote changed or not. Once the run has
  // left the feed's asks, the clock catches up and the next ask falls due.
  onEntriesChanged: {
    if (!root.answeredOnce) root.answeredOnce = Object.keys(feed.entries).some(function(s) { return feed.entries[s].status === "ok" })
    settleArrivals()
    Qt.callLater(flushQuotes)
    Qt.callLater(answersLanded)
  }
  function answersLanded() {
    root.tick()
    root.askDue()
    // The pill's first live answer asks Robinhood for it at once.
    root.askOvernight()
  }
  onAllSymbolsChanged: {
    workOutNewest()
    settleArrivals()
    Qt.callLater(forgetLeft)
  }
  onPreviewSymbolChanged: Qt.callLater(forgetLeft)
  onLastRemovalChanged: Qt.callLater(forgetLeft)

  // Robinhood's answers outlive a symbol until they'd be asked again anyway,
  // so one added back meanwhile asks Robinhood nothing.
  function forgetLeft() {
    var now = root.wallSecond()
    var removed = root.lastRemoval ? root.lastRemoval.symbol : ""
    var keep = function(s) { return root.allSymbols.indexOf(s) >= 0 || s === root.previewSymbol || s === removed }
    for (var symbol in root.builtDays) if (!keep(symbol)) delete root.builtDays[symbol]
    for (var gone in root.fills) if (!keep(gone)) delete root.fills[gone]
    var prune = function(cache, fresh) {
      var next = {}
      var dropped = false
      for (var s in cache.entries) {
        if (keep(s) || fresh(cache.entries[s])) next[s] = cache.entries[s]
        else dropped = true
      }
      if (dropped) cache.entries = next
    }
    prune(fundamentalsFeed, function() { return false })
    prune(allDayFeed, function(entry) { return !Overnight.allDayDue(entry, now) })
    prune(overnightFeed, function(entry) { return !!entry.at && now - entry.at < Overnight.OVERNIGHT_INTERVAL })
  }

  // A user's refresh. A host paused for no answer is tried at once. While
  // every screen is off, the history and trades are owed until one is on.
  property bool refreshOwed: false
  function refresh() {
    if (!root.ready) return
    yahooGate.retryNow()
    robinhoodGate.retryNow()
    var now = root.wallSecond()
    feed.ask(Asks.refreshQuotes(root.watched, feed.entries, now), now, true)
    fundamentalsFeed.retry()
    if (!root.screensClear()) {
      root.refreshOwed = true
      return
    }
    root.refreshRest()
  }
  // Only the charts on show: the rows' trades come on their own five-minute
  // asks, and for 150 rows they are two answers of 4 MB each.
  function refreshRest() {
    var now = root.wallSecond()
    root.showHistory(true)
    var trades = Asks.refreshTrades(root.chartsOnShow(), root.allDaySymbols, overnightFeed.askedAt, now)
    if (trades.length > 0) overnightFeed.fetch(trades, now)
  }

  // "Refreshing" while a request a user's refresh made is out, whatever its
  // answer says. One Yahoo's pause or the screens hold is not out.
  readonly property bool refreshing: {
    var job = historyFeed.job
    return feed.userOut || (!!job && !job.ahead && historyFeed.attempts > 0 && job.charts[0].key in root.historyOwed
      && historyFeed.entries[job.charts[0].key] === root.historyOwed[job.charts[0].key])
  }

  property var historyOwed: ({})

  // The day needs no history, nor does the pill, which always shows the
  // day. With nothing named next, the last chart, the preview's, goes.
  function showHistory(force) {
    if (!root.ready) return
    var charts = root.historyCharts()
    if (charts.length === 0) {
      root.historyOwed = ({})
      historyFeed.clear()
      return
    }
    var range = root.view.range
    if (force) root.historyOwed = Asks.historyOwing(charts, range, historyFeed.entries, root.wallSecond())
    var next = Asks.nextHistory(charts, range, historyFeed.entries, root.historyOwed)
      || { symbol: charts[charts.length - 1], force: false }
    historyFeed.request(next.symbol, range, next.force)
  }

  // A range on show is asked again as its market moves it, so its line and
  // its low and high keep up: one chart's at a time, when the feed is idle.
  function refreshRange() {
    if (!root.ready || historyFeed.busy) return
    var range = root.view.range
    var stale = Asks.staleHistory(root.historyCharts(), range, historyFeed.entries, feed.quotes, previewFeed.quotes,
      root.wallSecond(), root.calendars)
    if (stale !== "" && root.screensClear()) historyFeed.request(stale, range, false)
  }

  // The featured symbol is already an add from search on its way
  // (`addSymbol`), so its preview's fetch goes on as the featured stock's.
  function chartsOnShow() {
    return Asks.chartsOnShow(root.openSurfaces, root.view.featured, root.previewSymbol, root.previewSurface, root.previewShown)
  }

  function historyCharts() {
    return Asks.historyCharts(root.chartsOnShow(), root.view.range)
  }

  // Each open surface's rows in sight, top first: an open asks for their
  // quotes first, Robinhood's trades only for them, and on a range their
  // charts are fetched ahead of a click.
  property var sights: []
  // Charts with no good answer, not asked ahead again on this range.
  property var aheadMissed: ({})
  function rowsSeen(surface, symbols) {
    var others = root.sights.filter(function(s) { return s.surface !== surface })
    var next = symbols.length ? others.concat([{ surface: surface, symbols: symbols }]) : others
    if (next.length === 0 && root.sights.length === 0) return
    root.sights = next
    root.askOvernight()
    root.fetchAhead()
  }
  function rowsInSight() {
    var rows = []
    root.sights.forEach(function(sight) { rows = rows.concat(sight.symbols) })
    return rows
  }

  function aheadRows() {
    return Asks.aheadRows(root.openSurfaces.length > 0, root.view.range, root.historyCharts(), root.sights, historyFeed.keep)
  }

  // The cache never lets these go for another.
  readonly property var chartsInUse: root.historyCharts().concat(root.aheadRows()).map(function(s) {
    return historyFeed.keyFor(s, root.view.range)
  })

  // What a run leaves goes when the feed is idle again, or on the clock.
  function fetchAhead() {
    if (!root.ready || historyFeed.busy || root.screensOff || !yahooGate.spare()) return
    var range = root.view.range
    var charts = Asks.aheadCharts(root.aheadRows(), range, historyFeed.entries, root.aheadMissed)
    if (charts.length === 0 || !root.screensClear()) return
    historyFeed.requestAhead(charts, range)
  }

  // ---- The saved prices

  readonly property string quotesPath: ownerOnly.folder ? ownerOnly.folder + "/quotes.json" : ""
  // The one keeper of the cache; the sounds write through it too.
  OwnerOnly { id: ownerOnly; pluginId: root.pluginId }
  readonly property alias files: ownerOnly

  FileView {
    id: quotesFile
    path: root.quotesPath
    blockLoading: true
    printErrors: false
  }

  // { symbol: { quote, receivedAt } }
  function parseSavedQuotes() {
    try {
      var parsed = JSON.parse(quotesFile.text())
      return parsed && parsed.version === 1 && parsed.quotes ? Quote.keptQuotes(parsed.quotes) : {}
    } catch (e) {
      return {}
    }
  }

  // At most every 10 minutes, and only once an answer has come, so quotes
  // from an earlier session are never written back as they are. It waits
  // while a surface opens or a chart draws in, and for the runs out and asks
  // due when it fell due (`saveWaitsFor`): a long list's file is a megabyte,
  // written on the shell's thread, which would stall an open's prices.
  property bool quotesUnsaved: false
  property int quotesSavedAt: 0
  property var saveWaitsFor: null
  // What came is saved, though every price may have failed since.
  property bool answeredOnce: false

  // Each of All's quotes as the cache's text, made by a save for a quote
  // changed since the last, a few milliseconds a turn: the whole cache in
  // one JSON.stringify took 40 ms of the shell's thread for 150 stocks.
  // `quoteTexts` doesn't notify.
  readonly property var quoteTexts: ({ by: {} })
  Timer {
    id: quoteTextStep
    interval: 0
    onTriggered: root.writeQuotes()
  }

  function flushQuotes() {
    if (!root.quotesUnsaved || (root.quotesSavedAt && root.now - root.quotesSavedAt < 10 * 60)) return
    if (!root.answeredOnce || root.opening || root.drawing.length > 0) return
    if (!root.saveWaitsFor) root.saveWaitsFor = { runs: feed.landing.slice(), asked: Object.assign({}, feed.asked) }
    var waits = root.saveWaitsFor
    var answering = !yahooGate.paused && !root.screensOff
    if (waits.runs.some(function(run) { return feed.landing.indexOf(run) >= 0 })
      || (answering && Object.keys(waits.asked).some(function(s) { return feed.asked[s] === waits.asked[s] }))) return
    root.saveWaitsFor = null
    root.quotesUnsaved = false
    root.quotesSavedAt = root.now
    root.writeQuotes()
  }

  // Written in a turn of its own once every text is made: the text
  // JSON.stringify makes of { version: 1, quotes: { symbol: { quote,
  // receivedAt } } }, in All's order, as the quotes stand then.
  function writeQuotes() {
    var until = Date.now() + 4
    var by = root.quoteTexts.by
    var held = root.allSymbols.filter(function(s) { return !!feed.quotes[s] })
    var stale = held.filter(function(s) { return !by[s] || by[s].quote !== feed.quotes[s] })
    if (stale.length > 0) {
      for (var i = 0; i < stale.length && Date.now() < until; i++)
        by[stale[i]] = { quote: feed.quotes[stale[i]], text: JSON.stringify(feed.quotes[stale[i]]) }
      quoteTextStep.start()
      return
    }
    var kept = {}
    var saved = held.map(function(s) {
      kept[s] = by[s]
      return JSON.stringify(s) + ':{"quote":' + by[s].text + ',"receivedAt":' + JSON.stringify((feed.entries[s] || {}).receivedAt || 0) + "}"
    })
    root.quoteTexts.by = kept
    ownerOnly.write(root.quotesPath, '{"version":1,"quotes":{' + saved.join(",") + "}}\n")
  }

  // ---- The screens

  // The window's host, which asks Hyprland whether every screen is off. A
  // scheduled request goes only on an answer under a second old; an older
  // one is asked again, and its answer lets what waits go.
  property var screens: null
  readonly property bool screensOff: !!root.screens && root.screens.screensOff
  property real screensAnsweredMs: 0
  function screensClear() {
    if (!root.screens) return true
    if (Date.now() - root.screensAnsweredMs < 1000) return !root.screensOff
    return !root.screens.askScreens()
  }
  Connections {
    target: root.screens
    function onScreensAnswered() { Qt.callLater(root.screensAnswered) }
  }
  function screensAnswered() {
    root.screensAnsweredMs = Date.now()
    if (root.screensOff) return
    feed.sendWaiting()
    previewFeed.sendWaiting()
    historyFeed.sendWaiting()
    fundamentalsFeed.sendWaiting()
    root.screensReady()
    root.askOvernight()
    if (root.refreshOwed) {
      root.refreshOwed = false
      root.refreshRest()
    }
    root.refreshRange()
    root.fetchAhead()
    releaseFeed.sendWaiting()
  }
  signal screensReady()

  // ---- The clock

  // The wall clock in seconds, read only in `wallSecond`: the desktop's,
  // unless a walk hands in its own.
  property var wallClock: null
  function wallSecond() { return wallClock ? wallClock() : Math.floor(Date.now() / 1000) }
  property int now: wallSecond()

  // Each second while a surface is open, each minute otherwise; it also
  // wakes when the next quote falls due, a pause ends, or a refresh turns
  // overdue, so the pill's "!" comes on time.
  function tick() {
    root.now = root.wallSecond()
    root.armClock()
  }
  function armClock() {
    if (!root.ready) return
    clock.interval = Asks.clockWait(root.openSurfaces.length > 0, Date.now(), root.now,
      [root.dueAt, yahooGate.pausedUntil, robinhoodGate.pausedUntil, githubGate.pausedUntil, Freshness.overdueAt(root.owed, root.now)])
    clock.restart()
  }
  onDueAtChanged: armClock()
  onOwedChanged: armClock()
  onReadyChanged: armClock()
  // Each step also tries the next chart ahead, which may have waited on
  // Yahoo's budget.
  Timer {
    id: clock
    onTriggered: {
      root.tick()
      root.fetchAhead()
    }
  }
  onNowChanged: {
    slideClock()
    askOvernight()
    if ((root.dueAt > 0 && root.now >= root.dueAt) || Math.floor(root.now / 60) !== root.askedMinute) askDue()
    if (Math.floor(root.now / 60) !== root.prunedMinute) {
      root.prunedMinute = Math.floor(root.now / 60)
      forgetLeft()
      refreshRange()
    }
    if (root.refreshOwed && root.screensClear()) {
      root.refreshOwed = false
      root.refreshRest()
    }
    flushQuotes()
  }
  property int prunedMinute: -1
  // The clock five minutes at a time, which slides 1D's start
  // (`Day.slidWindow`): the pill's line follows it while a screen is
  // on, and the panel's and window's chart and rows (`viewSlideAt`) only
  // while one is open, so nothing rebuilds for a surface no screen shows.
  property int slideAt: 0
  property int viewSlideAt: 0
  function slideClock() {
    if (root.screensOff) return
    var at = root.now - root.now % 300
    if (at !== root.slideAt) root.slideAt = at
    if (root.openSurfaces.length > 0 && root.viewSlideAt !== root.slideAt) root.viewSlideAt = root.slideAt
  }
  onScreensOffChanged: slideClock()
  onOpenSurfacesChanged: slideClock()
  Component.onCompleted: slideClock()
}
