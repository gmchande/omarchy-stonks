import QtQuick
import Quickshell.Io
import "Asks.js" as Asks
import "Calendar.js" as Calendar
import "Chart.js" as Chart
import "Freshness.js" as Freshness
import "History.js" as History
import "Overnight.js" as Overnight
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
    root.forgetListKeys()
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
  // A freed name's key is kept only while a list still holds the key that
  // name would get without it, so the two can't meet.
  function forgetListKeys() {
    var names = root.fileSettings.lists.map(function(list) { return list.name })
    var used = names.map(root.listKey)
    var kept = {}
    for (var name in root.listKeys) if (names.indexOf(name) >= 0 || used.indexOf("=" + name) >= 0) kept[name] = root.listKeys[name]
    if (Object.keys(kept).length < Object.keys(root.listKeys).length) root.listKeys = kept
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
      range === "1D" ? ({}) : historyFeed.entries, root.nights, calendars, root.viewDayClock), root.nights)
  }
  readonly property string featuredSymbol: view.featured
  readonly property var shown: view.shown
  // The chart to show: `chart`, with the day built for it before while that
  // was built from the same objects, its quote and, where it trades at
  // night, its trades and reach, and while its axis hasn't moved. So an
  // answer for another symbol repaints nothing, nor does a clock that moves
  // no edge, and a preview's Yahoo day never stands in once it is added.
  // `builtDays` is kept from each chart the views show (`keepDay`); it
  // doesn't notify.
  readonly property var builtDays: ({})
  function keptDay(symbol, chart, nights) {
    if (!chart || !chart.quote || chart.day === chart.quote) return chart
    var made = root.dayMadeFrom(symbol, chart, nights)
    var built = builtDays[symbol]
    if (built && built.quote === made.quote && built.bars === made.bars && built.through === made.through && built.start === made.start
        && built.end === made.end)
      return Object.assign({}, chart, { day: built.day, latest: built.latest })
    return chart
  }
  function keepDay(symbol, chart) {
    if (!chart || !chart.quote || chart.day === chart.quote) return
    if (builtDays[symbol] && builtDays[symbol].day === chart.day) return
    var keys = Object.keys(builtDays)
    if (keys.length >= 24 && !(symbol in builtDays)) delete builtDays[keys[0]]
    builtDays[symbol] = Object.assign(root.dayMadeFrom(symbol, chart, root.nights), { day: chart.day, latest: chart.latest })
  }
  function dayMadeFrom(symbol, chart, nights) {
    var night = chart.tradesAtNight ? nights[symbol] : null
    return { quote: chart.quote, bars: night ? night.bars : null, through: night ? night.through : null,
      start: chart.day.axis ? chart.day.axis.start : null, end: chart.day.axis ? chart.day.axis.end : null }
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
    var nights = root.nights
    var lastTrades = lastTradeFeed.entries
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
      var trade = !night && lastTrades[symbol] ? lastTrades[symbol].trade : null
      var had = root.newestFrom[symbol]
      from[symbol] = had && had.quote === quote && had.bars === bars && had.through === through && had.trade === trade ? had
        : { quote: quote, bars: bars, through: through, trade: trade, newest: Chart.newestTradeOf(symbol, quote, nights, root.calendars, lastTrades) }
      if (!from[symbol].newest) return
      out[symbol] = from[symbol].newest
      count++
      same = same && root.newestTrades[symbol] === out[symbol]
    })
    root.newestFrom = from
    if (!same || count !== Object.keys(root.newestTrades).length) root.newestTrades = out
  }
  onNightsChanged: workOutNewest()

  // Held until every price the open asked for is in, or a site's pause
  // holds the rest once every run out is read, so the rows move once. A
  // gate hears a run before its feed reads it (`FetchRun`).
  property var heldOrder: null
  function releaseOrder() {
    if (!root.heldOrder) return
    var out = feed.landing.length > 0 || overnightFeed.busy || listDateFeed.busy || lastTradeFeed.busy
    var waiting = out || feed.busy || !!root.overnightWanted()
    if (out || (waiting && !yahooGate.paused && !robinhoodGate.paused)) return
    root.heldOrder = null
  }
  onOrderChanged: root.heldOrder = null
  onReversedChanged: root.heldOrder = null
  onChangeModeChanged: root.heldOrder = null
  onListNameChanged: {
    root.heldOrder = null
    Qt.callLater(root.askOvernight)
  }
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
      if (root.openSurfaces.length === 0) listsFile.flush()
    }
    if (open && Settings.normalizeOrder(root.order) === "pct") root.heldOrder = root.view.shown
    // The open's quote and overnight runs go a turn later, once the surface
    // has said which rows are in sight (`rowsSeen`), so both ask for the
    // visible rows together in one pass instead of splitting them.
    if (open && !root.opening) {
      root.opening = true
      Qt.callLater(function() {
        root.opening = false
        feed.sendWaiting()
        root.askOvernight()
      })
    }
    root.tick()
    root.showHistory(false)
    if (!open) root.askOvernight()
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

  // Returns why not, or "". With a symbol, from its lists: the list holds it.
  function createList(name, symbol) {
    var problem = Settings.listNameProblem(name, root.fileSettings.lists)
    if (problem === "") root.save(Settings.withListCreated(root.fileSettings, name, symbol))
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
    onStarted: quotesCache.seed()
    onSaveChecked: function(saved) { root.saveChecked(saved) }
  }
  // Bindings, not aliases: an alias reads nothing until the file's own
  // bindings have run, and the view is worked out before that.
  readonly property var fileSettings: listsFile.fileSettings
  readonly property bool ready: listsFile.ready
  readonly property bool listsUnreadable: listsFile.unreadable
  readonly property bool editsUnsaved: listsFile.editsUnsaved
  readonly property bool saveFailed: listsFile.saveFailed
  readonly property bool saving: listsFile.saving
  signal saveChecked(bool saved)
  function persist(values, settles) { listsFile.persist(values, settles) }
  function save(next) { listsFile.save(next) }
  function flushSave() { listsFile.flush() }
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
    onBudgetDueAtChanged: root.armClock()
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
    capacity: 40
    perMinute: 20
    onPausedChanged: root.releaseOrder()
    onPausedUntilChanged: root.armClock()
    onBudgetDueAtChanged: root.armClock()
    onReopened: Qt.callLater(root.askOvernight)
  }
  Gate {
    id: githubGate
    host: "GitHub"
    clock: root
    onPausedUntilChanged: root.armClock()
    onBudgetDueAtChanged: root.armClock()
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
    listDates: listDateFeed.entries
    needOpen: root.changeMode === "open"
  }
  readonly property var quotes: feed.quotes
  readonly property var entries: feed.entries
  readonly property var asked: feed.asked
  // Those waiting on Yahoo, from when: freshness's overdue counts from it.
  readonly property var owed: feed.owed
  // Those asked under `Freshness.ASKED_GRACE` ago (`QuoteFeed.asking`).
  readonly property var asking: feed.asking

  HistoryFeed {
    id: historyFeed
    gate: yahooGate
    mayAsk: function() { return root.screensClear() }
    clock: root
    centExchanges: root.centExchanges
    inUse: root.chartsInUse
    quoteFor: function(s) { return feed.quotes[s] || previewFeed.quotes[s] || null }
    calendars: root.calendars
    holding: root.drawing.length > 0
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
    listDates: listDateFeed.entries
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
  ListDateFeed {
    id: listDateFeed
    gate: robinhoodGate
    onEntriesChanged: Qt.callLater(root.askOvernight)
    onBusyChanged: Qt.callLater(root.releaseOrder)
  }
  OvernightFeed {
    id: overnightFeed
    gate: robinhoodGate
    holding: root.drawing.length > 0
    onEntriesChanged: {
      root.updateOvernightSets()
      root.joinNights()
      Qt.callLater(root.askOvernight)
    }
    onBusyChanged: Qt.callLater(root.releaseOrder)
  }
  LastTradeFeed {
    id: lastTradeFeed
    gate: robinhoodGate
    holding: root.drawing.length > 0
    onEntriesChanged: {
      var before = root.nights
      root.joinNights()
      if (root.nights === before) root.workOutNewest()
      Qt.callLater(root.askOvernight)
    }
    onBusyChanged: Qt.callLater(root.releaseOrder)
  }
  // Robinhood's trades with each listing's last trade from its quote
  // (`Overnight.joinedNights`), set only when one changes.
  property var nights: ({})
  property var joins: ({})
  function joinNights() {
    var joined = Overnight.joinedNights(overnightFeed.entries, lastTradeFeed.entries, Overnight.overnightMarket(root.calendars),
      { nights: root.nights, joins: root.joins })
    root.joins = joined.joins
    if (joined.nights !== root.nights) root.nights = joined.nights
  }
  onCalendarsChanged: {
    updateOvernightSets()
    joinNights()
  }
  // Whether the night trades now, and the listings whose newest price may
  // be a trade Robinhood failed to send meanwhile: their "!".
  readonly property bool nightTrading: {
    var cal = Overnight.overnightMarket(calendars)
    var night = cal ? Overnight.nightAt(cal, now) : null
    return !!night && night.open
  }
  readonly property var nightFailed: Overnight.nightFailures(overnightFeed.entries, lastTradeFeed.entries, nightTrading, Overnight.overnightMarket(calendars))
  // The feeds themselves, for whoever waits until no run is out.
  readonly property var feeds: ({ quotes: feed, preview: previewFeed, overnight: overnightFeed, lastTrade: lastTradeFeed, listDates: listDateFeed })
  // By Yahoo's quote, never Robinhood's answer: Robinhood is asked each
  // one's trades, which say whether it trades at night. Kept as the same
  // arrays while membership is unchanged so a quote batch never wakes
  // askOvernight() or sayFills() without a real change.
  property var overnightSymbols: []
  property var nightSymbols: []
  // Newest Yahoo pre-market hole across `overnightSymbols`, cached per quote
  // batch so clock ticks never scan all 152 quotes in `askOvernight`.
  property var rawYahooHole: null
  function updateOvernightSets() {
    var quotes = feed.quotes
    var cals = root.calendars
    var nextOver = []
    var newestHole = null
    for (var i = 0; i < root.allSymbols.length; i++) {
      var s = root.allSymbols[i]
      var q = quotes[s]
      if (q && Overnight.hasOvernight(q, cals)) {
        nextOver.push(s)
        var h = Overnight.yahooHole(q)
        if (h !== null && (newestHole === null || h > newestHole)) newestHole = h
      }
    }
    root.rawYahooHole = newestHole
    if (nextOver.length !== root.overnightSymbols.length
        || nextOver.some(function(s, idx) { return s !== root.overnightSymbols[idx] }))
      root.overnightSymbols = nextOver
    var cal = Overnight.overnightMarket(cals)
    var entries = overnightFeed.entries
    var nextNight = []
    for (var j = 0; j < root.overnightSymbols.length; j++) {
      var ns = root.overnightSymbols[j]
      if (Overnight.tradesAtNight(entries[ns], cal)) nextNight.push(ns)
    }
    if (nextNight.length !== root.nightSymbols.length
        || nextNight.some(function(s, idx) { return s !== root.nightSymbols[idx] }))
      root.nightSymbols = nextNight
  }
  // Where Robinhood's trades fill stretches Yahoo left empty, each logged
  // once. Worked out again for a stock only when its quote or trades change:
  // 150 stocks take about 28 ms of the shell's thread. Neither notifies.
  readonly property var fills: ({})
  readonly property var saidFills: ({})
  readonly property var fillsFrom: [nightSymbols, feed.quotes, overnightFeed.entries, previewFeed.quotes, previewSymbol]
  onFillsFromChanged: Qt.callLater(root.sayFills)
  function sayFills() {
    var previewed = root.previewSymbol
    var atNight = !!previewed && Overnight.tradesAtNight(overnightFeed.entries[previewed], Overnight.overnightMarket(root.calendars))
    var preview = atNight && root.allSymbols.indexOf(previewed) < 0 ? previewFeed.quotes[previewed] : null
    var symbols = preview ? root.nightSymbols.concat([previewed]) : root.nightSymbols
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
  // Robinhood's questions go side by side, so a 1D chart waits for one
  // answer, never two in a row.
  function askOvernight() {
    if (!root.ready || root.opening) return
    var open = root.openSurfaces.length > 0
    var asking = root.robinhoodAsking()
    var asks = Asks.overnightAsks(asking)
    var lastTrades = Asks.lastTradeAsks(asking, asks && !overnightFeed.busy ? asks.trades : [])
    root.lastTradeDueAt = Asks.lastTradeNext(asking)
    root.overnightDueAt = Asks.overnightNext(asking)
    if ((!asks && lastTrades.length === 0) || !root.screensClear()) return
    // The pill's own ask waits for a request already out.
    if (!open && (listDateFeed.busy || overnightFeed.busy || lastTradeFeed.busy)) return
    // After a pause one request goes alone. While it is out, the other asks
    // wait for its answer rather than fail unasked and wait five minutes.
    if (robinhoodGate.loneOut) return
    if (asks) {
      listDateFeed.fetch(asks.listDates, root.now)
      if (robinhoodGate.loneOut) return
      overnightFeed.fetch(asks.trades, root.now)
      if (robinhoodGate.loneOut) return
    }
    lastTradeFeed.fetch(lastTrades, root.now)
  }
  // When the next Robinhood quote or overnight refresh falls due, so the
  // clock wakes at its exact second.
  property int lastTradeDueAt: 0
  property int overnightDueAt: 0
  onLastTradeDueAtChanged: armClock()
  onOvernightDueAtChanged: armClock()
  function overnightWanted() {
    var asking = root.robinhoodAsking()
    return !!Asks.overnightAsks(asking) || Asks.lastTradeAsks(asking, []).length > 0
  }
  function robinhoodAsking() {
    var previewed = root.previewSymbol
    return {
      open: root.openSurfaces.length > 0,
      pill: root.pillInBar,
      featured: root.view.featured,
      quoteEntries: feed.entries,
      quotes: feed.quotes,
      yahooHole: root.rawYahooHole,
      rawYahooHole: root.rawYahooHole,
      overnightSymbols: root.overnightSymbols,
      listSymbols: root.view.rows,
      allSymbols: root.allSymbols,
      inSight: root.rowsInSight(),
      preview: previewed,
      previewShown: root.previewShown,
      // By search's result before its quote, so Robinhood is asked as Yahoo is.
      previewQuote: previewFeed.quotes[previewed] || feed.quotes[previewed] || root.previewResult,
      listDates: listDateFeed.entries,
      nights: overnightFeed.entries,
      lastTrades: lastTradeFeed.entries,
      interval: root.refreshIntervalSec,
      now: root.now,
      calendars: root.calendars
    }
  }
  onOvernightSymbolsChanged: askOvernight()

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
    updateOvernightSets()
    workOutNewest()
    settleArrivals()
    Qt.callLater(quotesCache.flush)
  }
  // Every run's answers land here, a quote changed or not. Once the run has
  // left the feed's asks, the clock catches up and the next ask falls due.
  onEntriesChanged: {
    settleArrivals()
    Qt.callLater(quotesCache.flush)
    Qt.callLater(answersLanded)
  }
  function answersLanded() {
    root.tick()
    root.askDue()
    // The pill's first live answer asks Robinhood for it at once.
    root.askOvernight()
  }
  onAllSymbolsChanged: {
    updateOvernightSets()
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
    var keepDay = function(s) { return s === root.view.featured || s === root.previewSymbol || s === removed || root.rowsInSight().indexOf(s) >= 0 }
    for (var symbol in root.builtDays) if (!keepDay(symbol)) delete root.builtDays[symbol]
    for (var gone in root.fills) if (!keep(gone)) delete root.fills[gone]
    // A fill is said once while it's on a chart.
    for (var said in root.saidFills) {
      var part = said.split(" ")
      var filled = root.fills[part[0]]
      if (!filled || !filled.stretches.some(function(s) { return String(s.from) === part[1] && String(s.to) === part[2] })) delete root.saidFills[said]
    }
    var missed = Object.keys(root.aheadMissed).filter(function(key) { return keep(key.split("|")[0]) })
    if (missed.length < Object.keys(root.aheadMissed).length) {
      var still = {}
      missed.forEach(function(key) { still[key] = true })
      root.aheadMissed = still
    }
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
    prune(listDateFeed, function(entry) { return !!entry.at && now - entry.at < Overnight.LIST_DATE_INTERVAL })
    prune(overnightFeed, function(entry) { return !!entry.at && now - entry.at < Overnight.OVERNIGHT_INTERVAL })
    prune(lastTradeFeed, function(entry) { return now - entry.at < root.refreshIntervalSec })
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
  // asks, and for 150 rows they are two answers of 4 MB each. While a night
  // trades, the last trades of what Robinhood's quote is asked about, the
  // same second as those trades: one asked over 10 s ago, or failed.
  function refreshRest() {
    var now = root.wallSecond()
    root.showHistory(true)
    var trades = Asks.refreshTrades(root.chartsOnShow(), root.overnightSymbols, overnightFeed.askedAt, now)
    if (trades.length > 0) overnightFeed.fetch(trades, now)
    var entries = lastTradeFeed.entries
    var lastTrades = Asks.lastTradeListings(root.robinhoodAsking()).filter(function(s) {
      return !entries[s] || entries[s].status === "failed" || now - entries[s].at > Asks.REFRESH_AGAIN
    })
    if (lastTrades.length > 0) lastTradeFeed.fetch(lastTrades, now)
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
    var first = root.sights.length === 0 && next.length > 0
    root.sights = next
    if (first) root.askOvernight()
    if (next.length > 0) aheadDebounce.restart()
    else aheadDebounce.stop()
  }
  Timer {
    id: aheadDebounce
    interval: 150
    onTriggered: {
      root.askOvernight()
      root.fetchAhead()
    }
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
    aheadDebounce.stop()
    if (!root.ready || historyFeed.busy || root.screensOff || !yahooGate.spare()) return
    var range = root.view.range
    var charts = Asks.aheadCharts(root.aheadRows(), range, historyFeed.entries, root.aheadMissed)
    if (charts.length === 0 || !root.screensClear()) return
    historyFeed.requestAhead(charts, range)
  }

  // ---- The saved prices

  // The one keeper of the cache; the sounds write through it too.
  OwnerOnly { id: ownerOnly; pluginId: root.pluginId }
  readonly property alias files: ownerOnly

  // Their reading, their handing to the feed and their writing are
  // `QuotesCache`'s. The service says when a save may be due: once a turn
  // the quotes changed in is over, and on each step of the clock, after
  // what it asks.
  QuotesCache {
    id: quotesCache
    files: ownerOnly
    quoteFeed: feed
    clock: root
    listsReady: root.ready
    opening: root.opening
    answering: !yahooGate.paused && !root.screensOff
  }
  // The feed holds the saved prices, so what of them is due is asked.
  readonly property bool seeded: quotesCache.seeded
  onSeededChanged: if (seeded) askDue()

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

  // Each minute boundary, and sooner at exact deadlines (next quote due,
  // Robinhood overnight/last-trade due, pause or budget end, overdue "!",
  // stale "As of" transition, or 5 s bell window end). Paused while every
  // screen is off.
  readonly property int clockInterval: clock.running ? clock.interval : 0
  function bellWindowEndAt(now) {
    if (root.openSurfaces.length === 0) return 0
    var sym = root.view.featured
    var q = sym ? feed.quotes[sym] : null
    if (!q || q.crypto) return 0
    var atNight = root.nightSymbols.indexOf(sym) >= 0
    return Overnight.marketAsleep(q, atNight, now, root.calendars) !== Overnight.marketAsleep(q, atNight, now - 5, root.calendars) ? now + 5 : 0
  }
  function newestStaleAt(symbols, now) {
    var trades = root.newestTrades
    var at = 0
    for (var i = 0; i < symbols.length; i++) {
      var sym = symbols[i]
      var nt = trades[sym]
      if (!nt && sym === root.previewSymbol) {
        var pq = previewFeed.quotes[sym]
        if (pq) nt = Chart.newestTradeOf(sym, pq, root.nights, root.calendars)
      }
      if (!nt || nt.phase !== "overnight" || nt.t === null || nt.t === undefined) continue
      var due = nt.t + Overnight.OVERNIGHT_STALE + 1
      if (due > now && (!at || due < at)) at = due
    }
    return at
  }
  function tick() {
    root.now = root.wallSecond()
    root.armClock()
  }
  property bool clockPending: false
  function armClockSoon() {
    if (clockPending) return
    clockPending = true
    Qt.callLater(function() {
      if (!root.clockPending) return
      root.clockPending = false
      root.armClock()
    })
  }
  function armClock() {
    clockPending = false
    if (!root.ready) return
    if (root.screensOff) {
      clock.stop()
      return
    }
    var charted = root.openSurfaces.length > 0 ? root.chartsOnShow() : root.pillInBar ? [root.view.featured] : []
    var visible = root.openSurfaces.length > 0 ? charted.concat(root.rowsInSight()) : charted
    var nowMs = root.wallClock ? root.wallSecond() * 1000 : Date.now()
    clock.interval = Asks.clockWait(root.openSurfaces.length > 0, nowMs, root.now,
      [root.dueAt, root.lastTradeDueAt, root.overnightDueAt,
        yahooGate.pausedUntil, robinhoodGate.pausedUntil, githubGate.pausedUntil,
        yahooGate.budgetDueAt, robinhoodGate.budgetDueAt, githubGate.budgetDueAt,
        Freshness.overdueAt(root.owed, root.now),
        Freshness.staleAt(feed.quotes, visible, root.now),
        root.newestStaleAt(visible, root.now),
        root.bellWindowEndAt(root.now)])
    clock.restart()
  }
  onDueAtChanged: armClockSoon()
  onOwedChanged: armClockSoon()
  onNewestTradesChanged: armClockSoon()
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
    if (yahooGate.budgetDueAt > 0 && root.now >= yahooGate.budgetDueAt) yahooGate.budgetDueAt = 0
    if (robinhoodGate.budgetDueAt > 0 && root.now >= robinhoodGate.budgetDueAt) robinhoodGate.budgetDueAt = 0
    if (githubGate.budgetDueAt > 0 && root.now >= githubGate.budgetDueAt) githubGate.budgetDueAt = 0
    stepDayClock()
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
    quotesCache.flush()
  }
  property int prunedMinute: -1
  // The clock five minutes at a time, which turns 1D's day at the open and
  // carries the hours after its close on to now (`Day.dayChart`,
  // `Day.sessionDay`): the pill's line follows it while a screen is on, and
  // the panel's and window's chart and rows (`viewDayClock`) only while one
  // is open, so nothing rebuilds for a surface no screen shows.
  property int dayClock: 0
  property int viewDayClock: 0
  function stepDayClock() {
    if (root.screensOff) return
    var at = root.now - root.now % 300
    if (at !== root.dayClock) root.dayClock = at
    if (root.openSurfaces.length > 0 && root.viewDayClock !== root.dayClock) root.viewDayClock = root.dayClock
  }
  onScreensOffChanged: {
    stepDayClock()
    if (root.screensOff) clock.stop()
    else root.tick()
  }
  onOpenSurfacesChanged: {
    stepDayClock()
    armClock()
  }
  Component.onCompleted: stepDayClock()
}
