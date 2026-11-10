import QtQuick
import Quickshell
import Quickshell.Io
import "Asks.js" as Asks
import "Chart.js" as Chart
import "Figures.js" as Figures
import "History.js" as History
import "Market.js" as Market
import "Overnight.js" as Overnight
import "Quote.js" as Quote
import "Settings.js" as Settings
// The one owner of the lists file, ~/.config/omarchy/<id>.json: the lists
// and what you look at, the stock on show and the range the panel and the
// window share.
Item {
  id: root

  // The plugin's id, the manifest's (`Plugin`): "" until the shell hands
  // it over, and meanwhile the lists file and the cache are left alone.
  property string pluginId: ""
  // Whether `omarchy plugin update` can update this copy (`Updates`):
  // where it can't, GitHub is never asked for main's version.
  property bool updatable: false
  property var dataSettings: Settings.fileSettings(null)
  property bool pluginsReady: false
  property bool settingsUnreadable: false
  // A change made while the file can't be read: only memory holds it.
  property bool editsUnsaved: false
  onSettingsUnreadableChanged: if (!settingsUnreadable) editsUnsaved = false
  // A save didn't land: Quickshell said so, or the read-back still held the
  // text before it (`takesRead`). The next save writes everything in memory.
  property bool saveFailed: false
  signal saveChecked(bool saved)
  property int now: Math.floor(Date.now() / 1000)
  // The clock five minutes at a time, which slides 1D's start
  // (`Overnight.slidWindow`): the pill's line follows it while a screen is
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
  property var lastRemoval: null
  property string listsHeld: ""
  // The same array until what the lists hold changes, so a save of a range
  // or a hero leaves each surface's list views as they are.
  property var lists: Settings.listChoices(Settings.fileSettings(null))
  onDataSettingsChanged: {
    var held = Settings.listsHeld(root.dataSettings)
    if (held === root.listsHeld) return
    root.listsHeld = held
    root.lists = Settings.listChoices(root.dataSettings)
    root.lastRemoval = null
  }
  // Added symbols with no first answer yet, quote or failure: saved and
  // fetched, but no list shows them until it comes.
  property var arriving: []
  // { symbol, before }: the hero an add from search took before its first
  // answer, and the one it left.
  property var heroTaken: null
  // Surfaces open where a screen shows them (`StonksBody.onScreen`).
  property var openSurfaces: []
  // The search result a surface's hero shows unadded. Never saved.
  property string previewSymbol: ""
  // One search previews at a time: another that starts choosing takes it.
  property var previewSurface: null
  // Nothing is asked for a preview until the choice rests on it.
  property bool previewRests: false
  readonly property bool previewShown: previewRests && openSurfaces.indexOf(previewSurface) >= 0
  property var watched: []

  readonly property string dataPath: pluginId ? Quickshell.env("HOME") + "/.config/omarchy/" + pluginId + ".json" : ""
  readonly property string quotesPath: ownerOnly.folder ? ownerOnly.folder + "/quotes.json" : ""

  // All: every symbol, fetched once whatever lists hold it.
  readonly property var library: dataSettings.symbols
  // "" is All.
  readonly property string listName: dataSettings.list
  readonly property var symbols: Settings.listSymbols(dataSettings)
  readonly property string order: Settings.listOrder(dataSettings)
  readonly property bool reversed: Settings.listReversed(dataSettings)
  readonly property string range: dataSettings.range
  // The panel's first-run hint has shown.
  readonly property bool hinted: dataSettings.hinted
  // What the surfaces show, as one value, so each change of it is whole.
  // Read from the settings and the feeds, not the bindings above, which may
  // not have caught up yet.
  readonly property var view: {
    var all = dataSettings.symbols
    var order = Settings.listOrder(dataSettings)
    var reversed = Settings.listReversed(dataSettings)
    var rows = Settings.listSymbols(dataSettings).filter(function(s) { return arriving.indexOf(s) < 0 })
    var named = String(dataSettings.featured || "").toUpperCase()
    var featured = all.indexOf(named) >= 0 ? named : (all[0] || "")
    var range = dataSettings.range
    // Receipts and histories only when the chart needs them, so a receipt
    // for a quoted symbol on the day recomputes nothing.
    var chart = Chart.viewChart(featured, range, feed.quotes,
      feed.quotes[featured] ? ({}) : feed.entries, range === "1D" ? ({}) : historyFeed.entries,
      overnightFeed.entries, allDayFeed.entries, calendars, root.viewSlideAt)
    root.keepDay(featured, chart, overnightFeed.entries, allDayFeed.entries)
    return {
      featured: featured,
      range: range,
      list: dataSettings.list,
      listKey: root.listKey(dataSettings.list),
      order: order,
      reversed: reversed,
      rows: rows,
      shown: Settings.shownOrder(root.heldOrder, Settings.sortedSymbols(rows, feed.quotes, order, reversed,
        dataSettings.changeMode, order === "manual" ? null : root.newestPrints)),
      library: all,
      // Null while on its way: each surface keeps the chart it has on screen.
      chart: chart
    }
  }
  readonly property var previewView: {
    var symbol = root.previewSymbol
    if (!symbol) return view
    var own = !!previewFeed.quotes[symbol] || !!previewFeed.entries[symbol]
    var quotes = own ? previewFeed.quotes : feed.quotes
    var entries = own ? previewFeed.entries : feed.entries
    var range = view.range
    var chart = Chart.viewChart(symbol, range, quotes, quotes[symbol] ? ({}) : entries,
      range === "1D" ? ({}) : historyFeed.entries, overnightFeed.entries, allDayFeed.entries, calendars, root.viewSlideAt)
    root.keepDay(symbol, chart, overnightFeed.entries, allDayFeed.entries)
    return Object.assign({}, view, { featured: symbol, chart: chart })
  }
  readonly property var previewEntries: previewFeed.entries
  readonly property string featuredSymbol: view.featured
  readonly property string changeMode: dataSettings.changeMode === "abs" || dataSettings.changeMode === "open"
    ? dataSettings.changeMode : "pct"
  readonly property bool retro: dataSettings.style === "retro"
  readonly property bool soundsOn: dataSettings.sounds
  readonly property int refreshIntervalSec: dataSettings.refreshIntervalSec
  readonly property var quotes: feed.quotes
  readonly property var entries: feed.entries
  readonly property var asked: feed.asked
  // Those waiting on Yahoo, from when: freshness's overdue counts from it.
  readonly property var owed: feed.owed
  // Asked under `Figures.ASKED_GRACE` ago, timed to the millisecond: in the
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
      var end = since[s] + Figures.ASKED_GRACE * 1000
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
  readonly property var histories: historyFeed.entries
  readonly property var fundamentals: fundamentalsFeed.entries
  readonly property var rates: fundamentalsFeed.rates
  readonly property var shown: view.shown
  // By Yahoo's quote, never Robinhood's answer: Robinhood is asked whether
  // it trades each all day.
  readonly property var overnightSymbols: library.filter(function(s) {
    return !!feed.quotes[s] && Overnight.hasOvernight(feed.quotes[s], calendars)
  })
  // Only these draw Robinhood's prints.
  readonly property var allDaySymbols: overnightSymbols.filter(function(s) {
    return !!allDayFeed.entries[s] && allDayFeed.entries[s].allDay
  })
  // The price on top on the pill, the rows, and the hero.
  readonly property var newestPrints: Chart.newestPrints(library, feed.quotes, overnightFeed.entries, allDayFeed.entries, calendars)
  readonly property var nights: overnightFeed.entries
  readonly property var allDay: allDayFeed.entries
  // Where Robinhood's trades fill stretches Yahoo left empty, each logged
  // once. Worked out again for a stock only when its quote or prints change:
  // 150 stocks take about 28 ms of the shell's thread. Neither notifies.
  readonly property var fills: ({})
  readonly property var saidFills: ({})
  readonly property var fillsFrom: [allDaySymbols, feed.quotes, overnightFeed.entries, allDayFeed.entries, previewFeed.quotes, previewSymbol]
  onFillsFromChanged: Qt.callLater(root.sayFills)
  function sayFills() {
    var previewed = root.previewSymbol
    var tradability = previewed ? allDayFeed.entries[previewed] : null
    var preview = tradability && tradability.allDay && root.library.indexOf(previewed) < 0 ? previewFeed.quotes[previewed] : null
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
  // Robinhood's two questions go side by side, so a 1D chart waits for one
  // answer, never two in a row.
  function askOvernight() {
    if (!root.pluginsReady) return
    var open = root.openSurfaces.length > 0
    var asks = root.overnightWanted()
    if (!asks || !root.screensClear()) return
    // The pill's own ask waits for a request already out.
    if (!open && (allDayFeed.busy || overnightFeed.busy)) return
    allDayFeed.fetch(asks.tradability, root.now)
    overnightFeed.fetch(asks.prints, root.now)
  }
  function overnightWanted() {
    var previewed = root.previewSymbol
    return Asks.overnightAsks({
      open: root.openSurfaces.length > 0,
      pill: root.view.featured,
      quoteEntries: feed.entries,
      quotes: feed.quotes,
      overnightSymbols: root.overnightSymbols,
      library: root.library,
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
  onOvernightSymbolsChanged: askOvernight()
  onAllDaySymbolsChanged: askOvernight()

  // `askDue` reads the wall clock, which `now` trails between ticks while
  // nothing is open.
  property int dueAt: 0
  property int askedMinute: -1
  function askDue() {
    if (!root.pluginsReady) return
    var now = root.wallSecond()
    root.askedMinute = Math.floor(now / 60)
    var open = root.openSurfaces.length > 0
    var featured = root.view.featured
    var calNow = Asks.calendarsAt(root.calendars, now)
    var watched = Asks.watchedSymbols(root.library, featured, open)
    if (watched.join(",") !== root.watched.join(",")) root.watched = watched
    var asks = Asks.quotesDue(watched, feed.entries, feed.asked, feed.quotes, root.heroesOnShow(), featured, now, root.refreshIntervalSec, calNow)
    root.dueAt = asks.next
    if (asks.due.length > 0) feed.ask(asks.due, now)
  }
  onPreviewRestsChanged: askDue()
  onRefreshIntervalSecChanged: askDue()

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
    feed.pump()
    previewFeed.pump()
    historyFeed.pump()
    fundamentalsFeed.pump()
    root.screensReady()
    root.askOvernight()
    if (root.refreshOwed) {
      root.refreshOwed = false
      root.refreshRest()
    }
    root.refreshRange()
    root.fetchAhead()
    releaseFeed.pump()
  }
  signal screensReady()
  // Reused while built from the same objects, its quote and an all-day
  // listing's prints and reach, and while its start hasn't slid: an answer
  // for another symbol repaints nothing, nor does a clock that moves no
  // start, and a preview's Yahoo day never stands in once it is added.
  readonly property var builtDays: ({})
  function keepDay(symbol, chart, nights, allDay) {
    if (!chart || !chart.quote || chart.day === chart.quote) return
    var tradability = allDay ? allDay[symbol] : null
    var night = tradability && tradability.allDay ? nights[symbol] : null
    var bars = night ? night.bars : null
    var through = night ? night.through : null
    var start = chart.day.axis ? chart.day.axis.start : null
    var built = builtDays[symbol]
    if (built && built.quote === chart.quote && built.bars === bars && built.through === through && built.start === start) {
      chart.day = built.day
      chart.latest = built.latest
    } else {
      builtDays[symbol] = { quote: chart.quote, bars: bars, through: through, start: start, day: chart.day, latest: chart.latest }
    }
  }

  FileView {
    id: calendarFile
    path: Qt.resolvedUrl("calendars.json")
    blockLoading: true
    printErrors: false
  }

  readonly property var calendars: {
    try { return JSON.parse(calendarFile.text()) } catch (e) { return null }
  }

  FileView {
    id: shellFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: dataFile
    path: root.dataPath
    watchChanges: true
    atomicWrites: true
    // Quickshell 0.3.1's async write, cancelled by the next, compares a
    // third against the cancelled text: a change back to it is never
    // written, and the watch reads the second back over it.
    blockWrites: true
    printErrors: false
    onFileChanged: root.readDataFile()
    onLoaded: {
      root.dataMissing = false
      root.dataReadEnded(root.takesRead(dataFile.text()) ? root.takeLoadedSettings : null)
    }
    // Only a file not there is missing: one that can't be read is never
    // written over.
    onLoadFailed: function(error) {
      root.dataMissing = error === FileViewError.FileNotFound
      if (!root.takesRead(null)) root.dataReadEnded(null)
      else root.dataReadEnded(root.dataMissing ? root.takeMissingFile : root.takeUnreadableFile)
    }
    // A write drops a read in flight unheard.
    onSaved: {
      ownerOnly.keep([root.dataPath])
      root.dataReadEnded(null)
    }
    onSaveFailed: function(error) {
      console.warn("stonks: failed to write " + root.dataPath + ": " + error)
      root.dataReadEnded(null)
    }
  }
  // Quickshell 0.3.1 ignores reload() while a read is in flight, so a
  // change meanwhile is held and read once that read ends.
  property bool dataReading: true
  property bool dataChangedMeanwhile: false
  function readDataFile() {
    if (root.dataReading) {
      root.dataChangedMeanwhile = true
      return
    }
    root.startDataRead()
  }
  function startDataRead() {
    root.dataReading = true
    dataFile.reload()
  }
  // Quickshell lets go of a read only after its handlers have run, so a
  // held read starts a turn later.
  function dataReadEnded(take) {
    var again = root.dataChangedMeanwhile
    root.dataReading = again
    root.dataChangedMeanwhile = false
    if (take) take()
    if (again) Qt.callLater(root.startDataRead)
  }

  // While a save awaits its read-back: each text the file may still hold
  // if Stonks' last write was lost, as keys. Quickshell 0.3.2 reports a
  // write done when a full disk fails its commit (fileview.cpp,
  // FileViewWriter::write), so only a read tells.
  property var staleTexts: null
  property string dataWritten: ""
  // A read of an earlier text, or none, says the last save was lost, and
  // isn't taken. Any other text ends the wait: a save from elsewhere wins.
  function takesRead(text) {
    if (root.dataMaking) return false
    if (root.staleTexts === null) return true
    var lost = text === null || (text !== root.dataWritten && root.staleTexts[text] === true)
    if (lost && !root.saveFailed)
      console.warn("stonks: " + root.dataPath + " didn't take the save; keeping the changes until one lands")
    root.saveFailed = lost
    if (!lost) root.staleTexts = null
    root.saveChecked(!lost)
    return !lost
  }

  Gate {
    id: yahooGate
    host: "Yahoo"
    clock: root
    // Yahoo answering again says the network is back.
    onReopened: {
      root.showHistory(false)
      fundamentalsFeed.retry()
      releaseFeed.askAgain()
      root.yahooBack()
    }
  }
  signal yahooBack()
  // Stonks asks a few times a minute: the budget only stops a runaway.
  Gate {
    id: robinhoodGate
    host: "Robinhood"
    clock: root
    capacity: 20
    perMinute: 10
  }
  Gate {
    id: githubGate
    host: "GitHub"
    clock: root
  }
  readonly property alias yahooGate: yahooGate
  readonly property var centExchanges: Market.centExchanges(calendars)

  QuoteFeed {
    id: feed
    symbols: root.pluginsReady ? root.library : []
    watched: root.watched
    lead: root.view.featured
    heroes: [root.view.featured].concat(root.previewShown && root.library.indexOf(root.previewSymbol) >= 0 ? [root.previewSymbol] : [])
    reading: function() { return Asks.readingOrder(root.view.featured, root.sights, root.view.shown, root.library) }
    holding: root.drawing.length > 0
    onBusyChanged: Qt.callLater(root.releaseOrder)
    onLandingChanged: Qt.callLater(root.releaseOrder)
    now: root.now
    clock: root
    clearance: function() { return !root.opening && root.screensClear() }
    gate: yahooGate
    centExchanges: root.centExchanges
    calendars: root.calendars
  }

  HistoryFeed {
    id: historyFeed
    gate: yahooGate
    clearance: function() { return root.screensClear() }
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
  QuoteFeed {
    id: previewFeed
    symbols: root.previewRests && root.previewSymbol !== "" && root.library.indexOf(root.previewSymbol) < 0
      ? [root.previewSymbol] : []
    now: root.now
    clock: root
    clearance: function() { return root.previewShown && root.screensClear() }
    gate: yahooGate
    centExchanges: root.centExchanges
    calendars: root.calendars
    bulk: false
    onQuotesChanged: root.askOvernight()
  }

  function heroesOnShow() {
    return root.openSurfaces.length > 0 ? [root.view.featured].concat(root.previewShown ? [root.previewSymbol] : []) : []
  }
  // With nothing open it reads no quote, so the pill's prices don't work it
  // out again.
  readonly property var figuresWanted: {
    var heroes = root.heroesOnShow()
    return heroes.length > 0 ? Asks.figuresWanted(heroes, feed.quotes, previewFeed.quotes) : []
  }
  FundamentalsFeed {
    id: fundamentalsFeed
    wanted: root.figuresWanted
    now: root.now
    clock: root
    gate: yahooGate
    clearance: function() { return root.screensClear() }
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

  ReleaseFeed {
    id: releaseFeed
    ready: root.pluginsReady && root.dataSettings.updateCheck && root.updatable
    now: root.now
    clock: root
    clearance: function() { return root.screensClear() }
    gate: githubGate
  }
  // "" until GitHub names one.
  readonly property alias mainVersion: releaseFeed.version

  // A user's refresh. A host paused for no answer is tried at once. While
  // every screen is off, the history and prints are owed until one is on.
  property bool refreshOwed: false
  function refresh() {
    if (!root.pluginsReady) return
    yahooGate.hurry()
    robinhoodGate.hurry()
    var now = root.wallSecond()
    feed.ask(Asks.refreshQuotes(root.watched, feed.entries, now), now, true)
    fundamentalsFeed.retry()
    if (!root.screensClear()) {
      root.refreshOwed = true
      return
    }
    root.refreshRest()
  }
  // Rows never draw Robinhood's prints: for 150 rows they come to two
  // answers of 4 MB each.
  function refreshRest() {
    var now = root.wallSecond()
    root.showHistory(true)
    var prints = Asks.refreshPrints(root.chartsOnShow(), root.allDaySymbols, overnightFeed.askedAt, now)
    if (prints.length > 0) overnightFeed.fetch(prints, now)
  }

  // "Refreshing" while a request a user's refresh made is out, whatever its
  // answer says. One Yahoo's pause or the screens hold is not out.
  readonly property bool refreshing: {
    var job = historyFeed.job
    return feed.userOut || (!!job && !job.ahead && historyFeed.attempts > 0 && job.charts[0].key in root.historyOwed
      && historyFeed.entries[job.charts[0].key] === root.historyOwed[job.charts[0].key])
  }

  // The day needs no history, nor does the pill, which always shows the
  // day. With nothing named next, the last chart, the preview's, goes.
  function showHistory(force) {
    if (!root.pluginsReady) return
    var charts = root.historyCharts()
    if (charts.length === 0) {
      root.historyOwed = ({})
      historyFeed.clear()
      return
    }
    var range = root.view.range
    if (force) root.historyOwed = Asks.historyOwing(charts, range, historyFeed.entries)
    var next = Asks.nextHistory(charts, range, historyFeed.entries, root.historyOwed)
      || { symbol: charts[charts.length - 1], force: false }
    historyFeed.request(next.symbol, range, next.force)
  }

  // A range on show is asked again as its market moves it, so its line and
  // its low and high keep up: one hero's at a time, when the feed is idle.
  function refreshRange() {
    if (!root.pluginsReady || historyFeed.busy) return
    var range = root.view.range
    var stale = Asks.staleHistory(root.historyCharts(), range, historyFeed.entries, feed.quotes, previewFeed.quotes,
      root.wallSecond(), root.calendars)
    if (stale !== "" && root.screensClear()) historyFeed.request(stale, range, false)
  }

  property var historyOwed: ({})

  // The featured symbol is already an add from search on its way
  // (`addSymbol`), so its preview's fetch goes on as the hero's.
  function chartsOnShow() {
    return Asks.chartsOnShow(root.openSurfaces, root.view.featured, root.previewSymbol, root.previewSurface, root.previewShown)
  }

  function historyCharts() {
    return Asks.historyCharts(root.chartsOnShow(), root.view.range)
  }

  // Each open surface's rows in sight, top first: an open asks for their
  // quotes first, and on a range their charts are fetched ahead of a click.
  property var sights: []
  // Charts fetched ahead on this range and not shown since, which a new
  // range drops; and those with no good answer, not asked ahead again.
  property var aheadAsked: ({})
  property var aheadMissed: ({})
  function rowsSeen(surface, symbols) {
    var others = root.sights.filter(function(s) { return s.surface !== surface })
    var next = symbols.length ? others.concat([{ surface: surface, symbols: symbols }]) : others
    if (next.length === 0 && root.sights.length === 0) return
    root.sights = next
    root.fetchAhead()
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
    if (!root.pluginsReady || historyFeed.busy || root.screensOff || !yahooGate.spare()) return
    var range = root.view.range
    var charts = Asks.aheadCharts(root.aheadRows(), range, historyFeed.entries, root.aheadMissed)
    if (charts.length === 0 || !root.screensClear()) return
    var asked = Object.assign({}, root.aheadAsked)
    charts.forEach(function(s) { asked[historyFeed.keyFor(s, range)] = true })
    root.aheadAsked = asked
    historyFeed.requestAhead(charts, range)
  }

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
    if (s) {
      root.shownAsHero(s)
      previewRest.restart()
    } else previewRest.stop()
    root.showHistory(false)
    if (before && before !== root.previewSurface && s) root.previewTaken(before)
  }
  // { symbol, exchange, instrumentType } or null.
  property var previewResult: null

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
    previewFeed.pump()
    askOvernight()
  }

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
        feed.pump()
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
  Connections {
    target: yahooGate
    function onPausedChanged() { root.releaseOrder() }
  }
  Connections {
    target: robinhoodGate
    function onPausedChanged() { root.releaseOrder() }
  }

  // One request per change of symbol or range, read from the view, so both
  // together never ask for a mixed pair.
  property string chartOnShow: ""
  onViewChanged: {
    var chart = view.featured + "|" + view.range
    if (chart === chartOnShow) return
    var rangeLeft = chartOnShow !== "" && chartOnShow.split("|")[1] !== view.range
    chartOnShow = chart
    if (root.heroTaken && view.featured !== root.heroTaken.symbol) root.heroTaken = null
    if (rangeLeft) {
      // A turn later: the view's change is still being told.
      var left = Object.keys(root.aheadAsked)
      root.aheadAsked = ({})
      root.aheadMissed = ({})
      if (left.length) Qt.callLater(function() { historyFeed.drop(left) })
    } else root.shownAsHero(view.featured)
    showHistory(false)
    askDue()
    askOvernight()
  }

  // A chart fetched ahead and now on a hero is the hero's: a new range keeps it.
  function shownAsHero(symbol) {
    var key = historyFeed.keyFor(symbol, root.view.range)
    if (!(key in root.aheadAsked)) return
    var asked = Object.assign({}, root.aheadAsked)
    delete asked[key]
    root.aheadAsked = asked
  }

  function setRange(value) {
    if (History.historyRanges().indexOf(value) >= 0) root.persist({ range: value })
  }

  // Written once the turn is over: an undo restores the quote before All
  // takes the symbol back, and a write between them left it out.
  onQuotesChanged: {
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
  onLibraryChanged: {
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
    var keep = function(s) { return root.library.indexOf(s) >= 0 || s === root.previewSymbol || s === removed }
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

  function answered(symbol) {
    return !!feed.quotes[symbol] || !!(feed.entries[symbol] && feed.entries[symbol].status === "failed")
  }

  // One that took the hero and failed hands it back.
  function settleArrivals() {
    var still = root.arriving.filter(function(s) { return root.library.indexOf(s) >= 0 && !root.answered(s) })
    if (still.length !== root.arriving.length) root.arriving = still
    var taken = root.heroTaken
    if (!taken || still.indexOf(taken.symbol) >= 0) return
    root.heroTaken = null
    if (root.view.featured === taken.symbol && !feed.quotes[taken.symbol]) root.feature(taken.before)
  }

  function parseShell() {
    try { return JSON.parse(shellFile.text()) } catch (e) { return null }
  }

  function parseDataText(text) {
    try {
      var parsed = JSON.parse(String(text || "").trim())
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
      return Settings.fileSettings(parsed)
    } catch (e) {
      return null
    }
  }

  function adopt(settings) {
    root.dataSettings = Settings.fileSettings(settings)
    if (!root.pluginsReady) {
      root.pluginsReady = true
      feed.seed(root.parseSavedQuotes())
      // What the seed put in is what the file holds.
      root.quotesUnsaved = false
      root.askDue()
    }
  }

  FileView {
    id: quotesFile
    path: root.quotesPath
    blockLoading: true
    printErrors: false
  }
  // The one keeper of the cache; the sounds write through it too.
  OwnerOnly { id: ownerOnly; pluginId: root.pluginId }
  readonly property alias files: ownerOnly

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
  // due when it fell due (`saveWaitsFor`): a long list takes 20 ms of the
  // shell's thread, which would stall an open's prices.
  property bool quotesUnsaved: false
  property int quotesSavedAt: 0
  property var saveWaitsFor: null
  // What came is saved, though every price may have failed since.
  property bool answeredOnce: false

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
    var saved = {}
    root.library.forEach(function(s) {
      if (feed.quotes[s]) saved[s] = { quote: feed.quotes[s], receivedAt: (feed.entries[s] || {}).receivedAt || 0 }
    })
    ownerOnly.write(root.quotesPath, JSON.stringify({ version: 1, quotes: saved }) + "\n")
  }

  function takeLoadedSettings() {
    var parsed = root.parseDataText(dataFile.text())
    if (!parsed) {
      root.takeUnreadableFile()
      return
    }
    root.settingsUnreadable = false
    if (settleWrite.running) parsed = Settings.fileSettings(Object.assign({}, parsed, { featured: root.dataSettings.featured }))
    if (root.pluginsReady && Settings.settingsEqual(parsed, root.dataSettings)) return
    root.adopt(parsed)
  }

  function takeUnreadableFile() {
    if (!root.settingsUnreadable)
      console.warn("stonks: " + root.dataPath + " can't be read; saving nothing until it can")
    root.settingsUnreadable = true
    if (!root.pluginsReady) root.adopt(root.dataSettings)
  }

  function takeMissingFile() {
    root.settingsUnreadable = false
    if (!root.pluginsReady) {
      var fromBar = Settings.settingsFromBar(root.parseShell(), root.pluginId)
      if (fromBar) {
        root.adopt(fromBar)
        root.writeDataFile(fromBar)
        return
      }
    }
    console.warn("stonks: settings file missing; using defaults")
    root.adopt(Settings.fileSettings(null))
  }

  // Read back once written (`takesRead`). The read also hands Quickshell
  // the text it compares a write with: after a lost save it would skip the
  // same text. It starts a turn later: Quickshell 0.3.2 forgets a read
  // started inside a read's handlers (fileview.cpp, operationFinished).
  function writeDataFile(settings) {
    var body = JSON.stringify(settings, null, 2) + "\n"
    var before = dataFile.text()
    if (body === before && root.staleTexts === null) return
    if (root.staleTexts === null) root.staleTexts = {}
    else root.staleTexts[root.dataWritten] = true
    root.staleTexts[before] = true
    root.dataWritten = body
    if (root.dataMissing) return root.makeDataFile()
    dataFile.setText(body)
    Qt.callLater(root.readDataFile)
  }

  // A missing data file is made, not written: Quickshell writes a new file
  // 0644 under the shell's umask, readable by other accounts until a chmod.
  // A write asked for meanwhile goes into it once made, or makes it again.
  property bool dataMissing: false
  property bool dataMaking: false
  property bool dataMakeOwed: false
  function makeDataFile() {
    if (root.dataMaking) {
      root.dataMakeOwed = true
      return
    }
    root.dataMaking = true
    ownerOnly.create(root.dataPath, root.dataWritten, function(made) {
      root.dataMaking = false
      if (made) root.dataMissing = false
      var owed = root.dataMakeOwed
      root.dataMakeOwed = false
      if (owed && !made) return root.makeDataFile()
      if (owed) dataFile.setText(root.dataWritten)
      Qt.callLater(root.readDataFile)
    })
  }

  function persist(values, settles) {
    root.store(Settings.fileSettings(Object.assign({}, root.dataSettings, values)), settles)
  }

  function store(next, settles) {
    var changed = !Settings.settingsEqual(next, root.dataSettings)
    root.dataSettings = next
    if (!root.pluginsReady) return
    if (root.settingsUnreadable) {
      if (changed) root.editsUnsaved = true
      return
    }
    if (settles) {
      settleWrite.restart()
      return
    }
    settleWrite.stop()
    root.writeDataFile(next)
  }

  // The pill's wheel writes the file once it rests. A read of the file
  // meanwhile keeps the symbol the wheel left.
  Timer {
    id: settleWrite
    interval: 400
    onTriggered: root.writeSettled()
  }
  function writeSettled() {
    if (root.pluginsReady && !root.settingsUnreadable) root.writeDataFile(root.dataSettings)
  }
  // The footer's try again.
  function saveAgain() {
    settleWrite.stop()
    root.writeSettled()
  }
  Component.onDestruction: if (settleWrite.running) root.writeSettled()

  // A hero chosen ends an add's hold on it (`heroTaken`).
  function feature(symbol, settles) {
    var s = String(symbol || "").toUpperCase()
    if (root.library.indexOf(s) < 0) return
    root.heroTaken = null
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
    if (s && root.library.indexOf(s) >= 0) {
      values.featured = s
      root.heroTaken = null
    }
    if (History.historyRanges().indexOf(range) >= 0) values.range = range
    if (Object.keys(values).length) root.persist(values)
  }

  function save(next) {
    if (!Settings.settingsEqual(next, root.dataSettings)) root.store(next)
  }

  function addSymbol(symbol) {
    var s = String(symbol || "").trim().toUpperCase()
    if (s && s === root.previewSymbol && previewFeed.entries[s])
      feed.restore(s, previewFeed.quotes[s] || null, previewFeed.entries[s])
    // A symbol already in All is a row at once.
    if (s && root.library.indexOf(s) < 0 && root.arriving.indexOf(s) < 0 && !root.answered(s))
      root.arriving = root.arriving.concat([s])
    var previewed = s !== "" && s === root.previewSymbol
    var coming = previewed && root.arriving.indexOf(s) >= 0
    var next = Settings.withSymbolAdded(root.dataSettings, s)
    // From an add still on its way, hand back the hero before that add.
    var taken = root.heroTaken
    var before = taken && taken.symbol === root.view.featured && !feed.quotes[taken.symbol] ? taken.before : root.view.featured
    if (coming) root.heroTaken = { symbol: s, before: before }
    if (coming || (previewed && !!feed.quotes[s])) next.featured = s
    root.save(next)
  }

  // `shown`: the rows as the surface shows them, whose neighbour takes the
  // hero.
  function removeSymbol(symbol, shown) {
    root.remove(symbol, Settings.withMembership(root.dataSettings, symbol, root.listName, false, shown || root.shown))
  }

  // "" is All: unticking it is a removal, which can be undone.
  function setMembership(symbol, name, member, shown) {
    var next = Settings.withMembership(root.dataSettings, symbol, name, member, shown || root.shown)
    if (name === "" && !member) root.remove(symbol, next)
    else root.save(next)
  }

  function remove(symbol, next) {
    var before = root.dataSettings
    var quote = feed.quotes[symbol] || null
    var entry = feed.entries[symbol] || null
    root.save(next)
    root.lastRemoval = { symbol: symbol, before: before, left: root.dataSettings.featured, quote: quote, entry: entry }
  }

  // Watched again first (`askDue`), so a run landing before the restore's
  // own look at the schedule can't drop the ask as unwatched.
  function undoRemoval(symbol) {
    if (!root.lastRemoval || root.lastRemoval.symbol !== symbol) return
    var removal = root.lastRemoval
    // Only once.
    root.lastRemoval = null
    if (removal.quote) feed.restore(symbol, removal.quote, removal.entry)
    root.save(Settings.withRemovalUndone(root.dataSettings, removal.before, symbol, removal.left))
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
    root.save(Settings.withManualOrder(root.dataSettings, next))
  }

  function setOrder(order) {
    root.save(Settings.withListOrder(root.dataSettings, order))
  }

  function reverseOrder() {
    root.save(Settings.withListReversed(root.dataSettings))
  }

  function switchList(name) {
    root.persist({ list: name })
  }

  // Returns why not, or "".
  function createList(name) {
    var problem = Settings.listNameProblem(name, root.dataSettings.lists)
    if (problem === "") root.save(Settings.withListCreated(root.dataSettings, name))
    return problem
  }

  // The new name takes the list's key before the save, so no view shows the
  // list under another key; the freed old name takes a new one after.
  function renameList(name, newName) {
    var problem = Settings.renameProblem(root.dataSettings, name, newName)
    var i = Settings.listIndex(root.dataSettings.lists, name)
    if (problem !== "" || i < 0) return problem
    var old = root.dataSettings.lists[i].name
    var now = Settings.listName(newName)
    if (old !== now) root.keyList(now, root.listKey(old))
    root.save(Settings.withListRenamed(root.dataSettings, name, newName))
    if (old !== now) root.keyList(old, "#" + (++root.listKeyCount))
    return problem
  }

  function moveList(name, delta) {
    root.save(Settings.withListMoved(root.dataSettings, name, delta))
  }

  function deleteList(name) {
    var i = Settings.listIndex(root.dataSettings.lists, name)
    if (i < 0) return
    var old = root.dataSettings.lists[i].name
    root.save(Settings.withListDeleted(root.dataSettings, name))
    root.keyList(old, "#" + (++root.listKeyCount))
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

  // Each second while a surface is open, each minute otherwise; it also
  // wakes when the next quote falls due, a pause ends, or a refresh turns
  // overdue, so the pill's "!" comes on time. The wall clock is read only
  // in `wallSecond`.
  function wallSecond() { return Math.floor(Date.now() / 1000) }
  function tick() {
    root.now = root.wallSecond()
    root.armClock()
  }
  function armClock() {
    if (!root.pluginsReady) return
    clock.interval = Asks.clockWait(root.openSurfaces.length > 0, Date.now(), root.now,
      [root.dueAt, yahooGate.pausedUntil, robinhoodGate.pausedUntil, githubGate.pausedUntil, Figures.overdueAt(root.owed, root.now)])
    clock.restart()
  }
  onDueAtChanged: armClock()
  onOwedChanged: armClock()
  onPluginsReadyChanged: armClock()
  Connections {
    target: yahooGate
    function onPausedUntilChanged() { root.armClock() }
  }
  Connections {
    target: robinhoodGate
    function onPausedUntilChanged() { root.armClock() }
  }
  Connections {
    target: githubGate
    function onPausedUntilChanged() { root.armClock() }
  }
  // Each step also tries the next chart ahead, which may have waited on
  // Yahoo's budget.
  Timer {
    id: clock
    onTriggered: {
      root.tick()
      root.fetchAhead()
    }
  }
}
