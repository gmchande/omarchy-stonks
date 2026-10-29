import QtQuick
import Quickshell
import Quickshell.Io
import "Asks.js" as Asks
import "Chart.js" as Chart
import "Figures.js" as Figures
import "History.js" as History
import "Market.js" as Market
import "Overnight.js" as Overnight
import "Settings.js" as Settings
// The one data owner. Data settings live in grvc.stonks.json and are
// written only here, including what you are looking at: the list, the
// featured symbol, and the chart range the panel and the window share.
// List membership follows Settings.js's rules; this file persists their result.
Item {
  id: root

  property var dataSettings: Settings.fileSettings(null)
  property bool pluginsReady: false
  // The data file is there but can't be read: empty, not JSON, or not an
  // object. The settings in memory stay, the defaults if it never could be
  // read, and changes still apply to them, but nothing is written until the
  // file reads again, so a typo in it never costs the user's lists.
  property bool settingsUnreadable: false
  // A change made while the file can't be read: it shows, but only memory
  // holds it, and the file read again or a restart loses it. The footer
  // says so, as it does a save that didn't land.
  property bool editsUnsaved: false
  onSettingsUnreadableChanged: if (!settingsUnreadable) editsUnsaved = false
  // A save of the data file didn't land: Quickshell said so, or the file,
  // read back, still held what it did before (`takesRead`). The settings in
  // memory stay ahead of the file, and the next save, a change's or the
  // footer's try again (`saveAgain`), writes them all.
  property bool saveFailed: false
  // Each read-back that judged a save, saved or not: the footer that asked
  // to try again says when it still didn't.
  signal saveChecked(bool saved)
  property int now: Math.floor(Date.now() / 1000)
  // The symbols whose fundamentals were asked for before their first
  // quote, one for each asker: the stock on show ("stock") and search's
  // preview ("preview"), so neither's ask takes the other's. Found in
  // review: the stock's ask each minute emptied one slot the preview's
  // waited in, and the preview showed no cap or P/E.
  property var pendingFundamentals: ({ stock: "", preview: "" })
  // What the last removal took and the settings from just before it, on
  // offer until the next change to what the lists hold, however it comes: a
  // change here, on either surface, or in the data file.
  property var lastRemoval: null
  property string listsHeld: ""
  // All first, then the named lists (`Settings.listChoices`): the same array
  // until what the lists hold changes, so a save that changes no list, such
  // as a range or a hero, leaves each surface's list views as they are.
  property var lists: Settings.listChoices(Settings.fileSettings(null))
  onDataSettingsChanged: {
    var held = Settings.listsHeld(root.dataSettings)
    if (held === root.listsHeld) return
    root.listsHeld = held
    root.lists = Settings.listChoices(root.dataSettings)
    root.lastRemoval = null
  }
  // Symbols just added whose first answer is not in: neither a quote nor a
  // first fetch that failed for good. They are members, saved and fetched,
  // but no list shows them until then.
  property var arriving: []
  // The hero an add from search took while its symbol was still on its way,
  // and the one it left: { symbol, before }. A first fetch that fails for
  // good hands the hero back, as an add whose preview had already failed
  // leaves it; another hero chosen meanwhile ends it.
  property var heroTaken: null
  // The surfaces open now where a screen shows them: the panel on any bar,
  // the window on a workspace on view (`StonksBody.onScreen`). The chart's
  // history is wanted only while one is (`surfaceShown`).
  property var openSurfaces: []
  // The search result a surface's hero shows unadded, the keyboard's choice
  // while its search is open (`preview`); "" when none is. Never saved.
  property string previewSymbol: ""
  // The surface whose search it is: one search previews at a time, and
  // another surface's search that starts choosing takes it.
  property var previewSurface: null
  // The choice has rested on it: only then are its quote, its range's
  // history, and its cap and P/E asked for.
  property bool previewRests: false
  // It rests on a surface a screen shows: only then is it a hero, its quote
  // on the chart and on the interval, its range's history kept fresh.
  readonly property bool previewShown: previewRests && openSurfaces.indexOf(previewSurface) >= 0
  // The symbols whose quotes are kept fresh now (`Asks.watchedSymbols`),
  // each asked for on its own market's clock (`askDue`).
  property var watched: []

  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  // The last good quotes, shown at start until each one's first answer, in
  // the cache (`files`).
  readonly property string quotesPath: ownerOnly.folder + "/quotes.json"

  // All, the library: every symbol, fetched once each whatever lists hold it.
  readonly property var library: dataSettings.symbols
  // The current list: "" for All. Its symbols in manual order are the rows.
  readonly property string listName: dataSettings.list
  // Every member of the current list, in manual order, arriving ones too.
  readonly property var symbols: Settings.listSymbols(dataSettings)
  readonly property string order: Settings.listOrder(dataSettings)
  readonly property bool reversed: Settings.listReversed(dataSettings)
  readonly property string range: dataSettings.range
  // The panel's first-run hint has shown.
  readonly property bool hinted: dataSettings.hinted
  // What the surfaces show of the settings, as one value, so a change of it
  // is whole whatever changed: the hero, the range, the list and its key
  // (`listKey`), which tells a rename from a switch, its order and
  // direction, its rows (members that have answered), those rows as sorted
  // (by the unit they show), All, and the chart asked for once it is ready.
  // Read straight from the settings and the feeds, not from the bindings
  // above, which may not have caught up when this one is evaluated.
  readonly property var view: {
    var all = dataSettings.symbols
    var order = Settings.listOrder(dataSettings)
    var reversed = Settings.listReversed(dataSettings)
    var rows = Settings.listSymbols(dataSettings).filter(function(s) { return arriving.indexOf(s) < 0 })
    var named = String(dataSettings.featured || "").toUpperCase()
    var featured = all.indexOf(named) >= 0 ? named : (all[0] || "")
    var range = dataSettings.range
    // Receipts and histories are read only when the chart needs them, so a
    // receipt for a quoted symbol on the day recomputes nothing here.
    var chart = Chart.viewChart(featured, range, feed.quotes,
      feed.quotes[featured] ? ({}) : feed.entries, range === "1D" ? ({}) : historyFeed.entries,
      overnightFeed.entries, allDayFeed.entries, calendars)
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
      // The chart asked for once it can be drawn (`Chart.viewChart`), null
      // while it is on its way: each surface keeps the one it has on screen.
      chart: chart
    }
  }
  // The view with the preview as its hero, unadded: the rows and the range
  // as they are, and its chart once it can be drawn. The view itself while
  // there is none. A US stock or ETF outside All waits on Robinhood's
  // answers as one in All does (`askOvernight`), so the preview says what
  // the stock added would. Found in the overnight QA of 23 October: NVDA's
  // preview said CLOSED and drew Thursday, then OVERNIGHT with tonight's
  // chart a second after ADD.
  readonly property var previewView: {
    var symbol = root.previewSymbol
    if (!symbol) return view
    var own = !!previewFeed.quotes[symbol] || !!previewFeed.entries[symbol]
    var quotes = own ? previewFeed.quotes : feed.quotes
    var entries = own ? previewFeed.entries : feed.entries
    var range = view.range
    var chart = Chart.viewChart(symbol, range, quotes, quotes[symbol] ? ({}) : entries,
      range === "1D" ? ({}) : historyFeed.entries, overnightFeed.entries, allDayFeed.entries, calendars)
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
  // Each symbol asked for and not yet answered, with the second it was asked.
  readonly property var asked: feed.asked
  // Of those, each one waiting on Yahoo, with the second that began: what
  // freshness's overdue counts from (`QuoteFeed.owed`).
  readonly property var owed: feed.owed
  // Of those asked, each asked under `Figures.ASKED_GRACE` ago by the wall
  // clock, to the millisecond, as true: freshness's grace for a quote
  // opened old. `askedMs` holds when each was asked; a timer ends each
  // grace as it runs out. Counted in the clock's whole seconds, the grace
  // ended anywhere from 1 to 2 s on (the check of #69, 23 October).
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
  // The rates P/Es need, by currency pair (`FundamentalsFeed.rates`).
  readonly property var rates: fundamentalsFeed.rates
  readonly property var shown: view.shown
  // Every US stock and ETF, by its quote (`Overnight.hasOvernight`), never by
  // what Robinhood answers: Robinhood is asked whether it trades each all day.
  readonly property var overnightSymbols: library.filter(function(s) {
    return !!feed.quotes[s] && Overnight.hasOvernight(feed.quotes[s], calendars)
  })
  // Those Robinhood trades all day, the only ones whose prints are drawn.
  readonly property var allDaySymbols: overnightSymbols.filter(function(s) {
    return !!allDayFeed.entries[s] && allDayFeed.entries[s].allDay
  })
  // Each listing's newest price since its regular close, by symbol: the
  // price on top on the pill, the rows, and the panel and the window
  // (`Chart.newestPrints`).
  readonly property var newestPrints: Chart.newestPrints(library, feed.quotes, overnightFeed.entries, allDayFeed.entries, calendars)
  // Robinhood's answers, by symbol: its prints (`nights`) and whether it
  // trades each all day (`allDay`), so a row's line and the pill's draw the
  // day the 1D chart does (`Chart.lineDay`).
  readonly property var nights: overnightFeed.entries
  readonly property var allDay: allDayFeed.entries
  // Robinhood's two questions, whether it trades a listing all day and its
  // prints, go side by side, so a 1D chart waits for one answer, never two
  // in a row: what is asked is `Asks.overnightAsks`'s. A feed with a
  // request out sends nothing more; each answer asks again for what is
  // still wanted, and one the gate held back goes as soon as it lets it.
  // Looked at as the clock ticks, answers land, the listings change, a
  // surface opens, a preview rests, and the screens answer; never while
  // every screen is off (`screensClear`).
  property bool pillAsked: false
  function askOvernight() {
    if (!root.pluginsReady) return
    var open = root.openSurfaces.length > 0
    var asks = root.overnightWanted()
    if (!asks || !root.screensClear()) return
    // The pill's own ask waits for a request already out, then goes.
    if (!open && (allDayFeed.busy || overnightFeed.busy)) return
    if (!open) root.pillAsked = true
    allDayFeed.fetch(asks.tradability, root.now)
    overnightFeed.fetch(asks.prints, root.now)
  }
  // What Robinhood is still to be asked now, null for nothing.
  function overnightWanted() {
    var previewed = root.previewSymbol
    return Asks.overnightAsks({
      open: root.openSurfaces.length > 0,
      pill: root.view.featured,
      pillAsked: root.pillAsked,
      quoteEntries: feed.entries,
      overnightSymbols: root.overnightSymbols,
      library: root.library,
      preview: previewed,
      previewShown: root.previewShown,
      // The preview's kind by its quote, or before that by search's result,
      // so Robinhood is asked as Yahoo is.
      previewQuote: previewFeed.quotes[previewed] || feed.quotes[previewed] || root.previewResult,
      allDay: allDayFeed.entries,
      nights: overnightFeed.entries,
      now: root.now,
      calendars: root.calendars
    })
  }
  // The clock's work, as it moves: the asks fall due at their own second
  // (`dueAt`), and the rest by the minute, when a market's session may have
  // begun or ended, or a range on show grown old.
  onNowChanged: {
    askOvernight()
    if ((root.dueAt > 0 && root.now >= root.dueAt) || Math.floor(root.now / 60) !== root.askedMinute) askDue()
    // What a symbol gone keeps ages out by the minute, with no edit to
    // prompt it (`forgetLeft`).
    if (Math.floor(root.now / 60) !== root.prunedMinute) {
      root.prunedMinute = Math.floor(root.now / 60)
      forgetLeft()
      refreshRange()
      // The hero's cap and P/E, and its rate, are good for a day: a surface
      // left open on it asks again once they are older (`FundamentalsFeed.fetch`
      // asks nothing while both are fresh). A failed one waits to be wanted.
      if (root.openSurfaces.length > 0 && (root.fundamentals[root.view.featured] || {}).status === "ok")
        fetchFundamentals(root.view.featured)
    }
    // A refresh owed while every screen was off asks again as the clock
    // moves, so it goes once one is on, quotes due or not.
    if (root.refreshOwed && root.screensClear()) {
      root.refreshOwed = false
      root.refreshRest()
    }
    flushQuotes()
  }
  property int prunedMinute: -1
  onOvernightSymbolsChanged: askOvernight()
  onAllDaySymbolsChanged: askOvernight()

  // What is watched (`watched`), and of it what is due, each on its own
  // market's clock (`Asks.quotesDue`). Looked at as the clock reaches the
  // next one due (`dueAt`) and each minute, as answers land, as a surface
  // opens, as the featured symbol or a resting preview changes, and as the
  // interval does: on the wall clock, which `now` trails between ticks
  // while nothing is open. Whatever is asked goes only while a screen is on
  // (`screensClear`).
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
    var heroes = open ? [featured].concat(root.previewShown ? [root.previewSymbol] : []) : []
    var asks = Asks.quotesDue(watched, feed.entries, feed.asked, feed.quotes, heroes, featured, now, root.refreshIntervalSec, calNow)
    root.dueAt = asks.next
    if (asks.due.length > 0) feed.ask(asks.due, now)
  }
  onPreviewRestsChanged: askDue()
  onRefreshIntervalSecChanged: askDue()

  // The window's host, which asks Hyprland whether every screen is off.
  // Every request a feed starts on the schedule, a quote run (queued,
  // retried, or after a pause), Robinhood's, a refresh's history or a
  // range's grown old, and the day's look for a newer Stonks, asks first
  // (`screensClear`): only an answer under a second old says go. An older
  // one is asked again, and the answer lets what waits go
  // (`screensAnswered`), or holds it while every screen is off.
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
  // The day last built for each symbol's chart, kept while what built it is
  // the same: its quote, and for a listing Robinhood trades all day its
  // prints and how far its answer reached, read from the answers the chart
  // was built from (`nights`, `allDay`, as `Chart.viewChart` took them), so
  // an own preview's Yahoo day is never handed to the same symbol's
  // calendar day once it is added. An answer for another symbol hands the
  // chart the objects it has and nothing that draws it repaints. Written in
  // place by the views, and pruned with the other caches by symbol
  // (`forgetLeft`); it notifies nothing.
  readonly property var builtDays: ({})
  function keepDay(symbol, chart, nights, allDay) {
    if (!chart || !chart.quote || chart.day === chart.quote) return
    var tradability = allDay ? allDay[symbol] : null
    var night = tradability && tradability.allDay ? nights[symbol] : null
    var bars = night ? night.bars : null
    var through = night ? night.through : null
    var built = builtDays[symbol]
    if (built && built.quote === chart.quote && built.bars === bars && built.through === through) {
      chart.day = built.day
      chart.latest = built.latest
    } else {
      builtDays[symbol] = { quote: chart.quote, bars: bars, through: through, day: chart.day, latest: chart.latest }
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
    // Written before setText returns. Quickshell 0.3.1's async write, cancelled
    // by the next, leaves the cancelled text as what it compares a third
    // against, so a change back to it while the second is in flight is never
    // written, and the watch reads the second back over it.
    blockWrites: true
    printErrors: false
    onFileChanged: root.readDataFile()
    onLoaded: {
      root.dataMissing = false
      root.dataReadEnded(root.takesRead(dataFile.text()) ? root.takeLoadedSettings : null)
    }
    // Only a file that isn't there is missing: one there that can't be
    // read, for its permissions or as a folder, is never written over.
    onLoadFailed: function(error) {
      root.dataMissing = error === FileViewError.FileNotFound
      if (!root.takesRead(null)) root.dataReadEnded(null)
      else root.dataReadEnded(root.dataMissing ? root.takeMissingFile : root.takeUnreadableFile)
    }
    // A write drops a read in flight unheard: neither loaded nor failed.
    // Written, the file is its owner's alone (`files`).
    onSaved: {
      ownerOnly.keep([root.dataPath])
      root.dataReadEnded(null)
    }
    onSaveFailed: function(error) {
      console.warn("stonks: failed to write " + root.dataPath + ": " + error)
      root.dataReadEnded(null)
    }
  }
  // A read of the data file is in flight, or owed; the first starts as its
  // path is set. Quickshell 0.3.1 ignores a reload() asked for while one is,
  // so a change saved meanwhile would never be read: it is held instead,
  // and read once that read ends, however it ends.
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
  // TAKE, when the read found something, takes it first. A change held
  // during the read is read once the handler has returned: Quickshell lets
  // go of a read only after its loaded or loadFailed handlers have run.
  function dataReadEnded(take) {
    var again = root.dataChangedMeanwhile
    root.dataReading = again
    root.dataChangedMeanwhile = false
    if (take) take()
    if (again) Qt.callLater(root.startDataRead)
  }

  // A save awaiting its read-back: each text the file may still hold if
  // Stonks' last write was lost, what it held before the first write not
  // yet read back and every write since, as keys; null when none awaits.
  // And what Stonks wrote last. Quickshell 0.3.2 reports a write done when
  // a full disk fails its commit (fileview.cpp, FileViewWriter::write), so
  // only a read tells.
  property var staleTexts: null
  property string dataWritten: ""
  // Whether a read of the data file is taken. While a save awaits its
  // read-back, a file holding an earlier text, or none that reads, says
  // the last save was lost: the read is not taken, so the changes in memory
  // stay. What Stonks wrote last ends the wait, and so does any other
  // text, a save from elsewhere, which wins as ever. A read while the file
  // is being made (`makeDataFile`) is not taken and judges nothing: the
  // read after it does.
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
      releaseFeed.askAgain()
    }
  }
  // Robinhood is asked for its prints and its instruments once a session
  // for the pill's symbol, as a surface opens, as US listings are added,
  // every 5 minutes through a night, and on r: a few a minute, more while
  // adding, so the budget only stops a runaway.
  Gate {
    id: robinhoodGate
    host: "Robinhood"
    clock: root
    capacity: 20
    perMinute: 10
  }
  // GitHub is asked once a day, for the newest version (`ReleaseFeed`).
  Gate {
    id: githubGate
    host: "GitHub"
    clock: root
  }
  readonly property alias yahooGate: yahooGate
  // The exchanges whose listings trade in whole cents from $1, which every
  // Yahoo answer is read with (`Quote.parseChart`).
  readonly property var centExchanges: Market.centExchanges(calendars)

  QuoteFeed {
    id: feed
    symbols: root.pluginsReady ? root.library : []
    watched: root.watched
    lead: root.view.featured
    // A member previewed shows on the hero too, from this feed.
    heroes: [root.view.featured].concat(root.previewShown && root.library.indexOf(root.previewSymbol) >= 0 ? [root.previewSymbol] : [])
    reading: function() { return Asks.readingOrder(root.view.featured, root.sights, root.view.shown, root.library) }
    holding: root.drawing.length > 0
    waited: root.chartWaited
    onBusyChanged: Qt.callLater(root.releaseOrder)
    now: root.now
    clock: root
    clearance: function() { return !root.opening && root.screensClear() }
    gate: yahooGate
    centExchanges: root.centExchanges
    calendars: root.calendars
  }

  // One request at a time: a chart's history, or a run of the rows in sight;
  // an answer may leave another chart a refresh still owes, or one with no
  // answer yet, which is asked for next; with none, the rows in sight are
  // fetched ahead (`fetchAhead`).
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
  // The preview's quote, fetched once when the choice rests on a symbol
  // outside All, and never refreshed: not on the timer, not by `r`; held
  // while its surface is out of sight (`previewShown`).
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
    onQuotesChanged: {
      root.askPendingFundamentals()
      root.askOvernight()
    }
  }

  FundamentalsFeed {
    id: fundamentalsFeed
    gate: yahooGate
    clearance: function() { return root.screensClear() }
  }
  // Robinhood's feeds send one request at a time; each answer asks again
  // for what is still wanted, while it still is (`askOvernight`).
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
    waited: root.chartWaited
    onEntriesChanged: Qt.callLater(root.askOvernight)
    onBusyChanged: Qt.callLater(root.releaseOrder)
  }
  // Off by the data file's `updateCheck`, it asks GitHub nothing.
  ReleaseFeed {
    id: releaseFeed
    ready: root.pluginsReady && root.dataSettings.updateCheck
    now: root.now
    clock: root
    clearance: function() { return root.screensClear() }
    gate: githubGate
  }
  // The version on main, "" until GitHub has named one (`Updates`).
  readonly property alias mainVersion: releaseFeed.version

  // A user's refresh, from a key, the pill, or IPC: every watched quote
  // whose last answer is more than 10 s old, and the overnight prints of
  // the charts on show, unless asked for in the last 10 s, so a second
  // press adds nothing; and the chart's history fresh whatever the cache
  // holds. A host paused for no answer is tried at once (`Gate.hurry`).
  // While every screen is off the quotes wait their turn, and the rest is
  // owed (`refreshOwed`) until a screen is on.
  property bool refreshOwed: false
  function refresh() {
    if (!root.pluginsReady) return
    yahooGate.hurry()
    robinhoodGate.hurry()
    var now = root.wallSecond()
    feed.ask(Asks.refreshQuotes(root.watched, feed.entries, now), now, true)
    if (!root.screensClear()) {
      root.refreshOwed = true
      return
    }
    root.refreshRest()
  }
  // Rows never draw Robinhood's prints, only a chart does: asked for every
  // row Robinhood trades all day, `r` sent 150 listings, two answers of
  // 4 MB each, at any hour.
  function refreshRest() {
    var now = root.wallSecond()
    root.showHistory(true)
    var prints = Asks.refreshPrints(root.chartsOnShow(), root.allDaySymbols, overnightFeed.askedAt, now)
    if (prints.length > 0) overnightFeed.fetch(prints, now)
  }

  // A user's refresh has a request to Yahoo out, and the header says
  // "Refreshing": a quote it asked for (`QuoteFeed.userOut`), or the chart
  // it owes (`historyOwed`), each until its answer comes back, whatever it
  // says. One Yahoo's pause holds, or every screen off, is not out.
  // Automatic refreshes say nothing.
  readonly property bool refreshing: {
    var job = historyFeed.job
    return feed.userOut || (!!job && !job.ahead && historyFeed.attempts > 0 && job.charts[0].key in root.historyOwed
      && historyFeed.entries[job.charts[0].key] === root.historyOwed[job.charts[0].key])
  }

  // The history the open surfaces' heroes show on the shared range: the
  // featured symbol's, on every open surface but the one previewing, and
  // the preview's once the choice rests on it. The day needs none, and
  // neither does the pill, which always shows the day. One request at a
  // time: the chart `Asks.nextHistory` names, a user's refresh (`force`)
  // owing it fresh, else the last, the preview.
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

  // A range left on show with its history in hand is asked again as its
  // market moves it (`Asks.staleHistory`), so its line and its low and high
  // keep up with the price over it: a hero's at a time, when the feed has
  // nothing on its way, and only while a screen is on. Looked at each
  // minute.
  function refreshRange() {
    if (!root.pluginsReady || historyFeed.busy) return
    var range = root.view.range
    var stale = Asks.staleHistory(root.historyCharts(), range, historyFeed.entries, feed.quotes, previewFeed.quotes,
      root.wallSecond(), root.calendars)
    if (stale !== "" && root.screensClear()) historyFeed.request(stale, range, false)
  }

  // The charts a user's refresh asked for fresh, each with the answer it had
  // then (`Asks.historyOwing`).
  property var historyOwed: ({})

  // The symbols the open surfaces' heroes chart (`Asks.chartsOnShow`): the
  // featured symbol, which an add from search still on its way already is
  // (`addSymbol`), so the fetch its preview has out goes on as the hero's;
  // and a resting preview.
  function chartsOnShow() {
    return Asks.chartsOnShow(root.openSurfaces, root.view.featured, root.previewSymbol, root.previewSurface, root.previewShown)
  }

  // Those whose history they show: none on the day.
  function historyCharts() {
    return Asks.historyCharts(root.chartsOnShow(), root.view.range)
  }

  // The rows each open surface shows, top first, as { surface, symbols }
  // (`rowsSeen`): an open asks for their quotes first
  // (`Asks.readingOrder`), and on a range their charts are fetched ahead of
  // a click.
  property var sights: []
  // The charts asked for ahead on this range and not shown since, which a
  // change of range drops; and those that got no good answer, which are
  // not asked for ahead again on it.
  property var aheadAsked: ({})
  property var aheadMissed: ({})
  function rowsSeen(surface, symbols) {
    var others = root.sights.filter(function(s) { return s.surface !== surface })
    var next = symbols.length ? others.concat([{ surface: surface, symbols: symbols }]) : others
    if (next.length === 0 && root.sights.length === 0) return
    root.sights = next
    root.fetchAhead()
  }

  // The rows in sight on the open surfaces whose charts are fetched ahead
  // (`Asks.aheadRows`).
  function aheadRows() {
    return Asks.aheadRows(root.openSurfaces.length > 0, root.view.range, root.historyCharts(), root.sights, historyFeed.keep)
  }

  // The charts the heroes show and those of the rows in sight, which the
  // cache never lets go for another.
  readonly property var chartsInUse: root.historyCharts().concat(root.aheadRows()).map(function(s) {
    return historyFeed.keyFor(s, root.view.range)
  })

  // The charts in sight with no answer yet fetched ahead in one run, once
  // the heroes' charts want nothing, while Yahoo has budget to spare
  // (`Gate.spare`) and a screen is on; what the run leaves goes as the feed
  // is idle again, or on the clock.
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

  // A surface's search shows its choice on the hero (`previewView`), or
  // nothing with "", which only the search previewing can say. What it
  // needs is asked for only once the choice has rested there, so arrowing
  // past a result asks for nothing. `result`, search's result for it, says
  // what kind of listing it is before its quote does (`previewResult`).
  function preview(surface, symbol, result) {
    var s = String(symbol || "").trim().toUpperCase()
    if (!s && surface !== root.previewSurface) return
    if (s === root.previewSymbol && surface === root.previewSurface) return
    var before = root.previewSurface
    // The rest first: a choice that moves on has not rested on the next one.
    root.previewRests = false
    root.previewSurface = s ? surface : null
    root.previewSymbol = s
    root.previewResult = s && result && String(result.symbol || "").toUpperCase() === s ? result : null
    if (s) {
      root.shownAsHero(s)
      previewRest.restart()
    } else {
      previewRest.stop()
      // A preview gone asks for nothing it waited on.
      root.keepPending("preview", "")
    }
    root.showHistory(false)
    if (before && before !== root.previewSurface && s) root.previewTaken(before)
  }
  // Search's result for the preview, { symbol, exchange, instrumentType },
  // or null: a US stock or ETF by it is asked of Robinhood as its quote is
  // asked of Yahoo, side by side (`askOvernight`). Found in the night's
  // check of 23 October: waiting for the quote first made NVDA's preview
  // 3 s later on a slow network.
  property var previewResult: null

  // Another surface's search took the preview `surface` had.
  signal previewTaken(var surface)

  Timer {
    id: previewRest
    interval: 250
    onTriggered: {
      root.previewRests = true
      root.showHistory(false)
    }
  }
  // A resting preview on a surface a screen shows asks for what it holds
  // back while it is not: its quote, its cap and P/E, and Robinhood's two
  // answers for a US stock or ETF. Out of sight, it takes back the cap and
  // P/E it still waits for.
  onPreviewShownChanged: if (previewShown) {
    previewFeed.pump()
    fetchFundamentals(previewSymbol, "preview")
    askOvernight()
  } else withdrawFundamentals("preview")

  // A surface says when it opens and closes, and as it goes. The clock
  // catches up at once, and moves on at the pace that now holds.
  function surfaceShown(surface, open) {
    var others = root.openSurfaces.filter(function(s) { return s !== surface })
    var next = open ? others.concat([surface]) : others
    if (next.length === root.openSurfaces.length) return
    root.openSurfaces = next
    // With no surface in sight, the stock on show is on none: what it waits
    // for is asked again when one comes back (`requestFundamentals` in App
    // and Panel).
    if (!next.length) root.withdrawFundamentals("stock")
    if (!open) {
      root.sights = root.sights.filter(function(s) { return s.surface !== surface })
      root.drawingIn(surface, false)
    }
    // A list in order of change keeps its places while the prices the open
    // asks for come in (`releaseOrder`).
    if (open && Settings.normalizeOrder(root.order) === "pct") root.heldOrder = root.view.shown
    // The surface lays out its rows as it opens, and says which are in
    // sight (`rowsSeen`): the open's quote run goes a turn later, so it
    // asks for those first (`Asks.readingOrder`).
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

  // The surfaces whose chart is drawing itself in (`StonksBody.drawingIn`):
  // while one is, the feeds read only the chart waited on (`chartWaited`),
  // and the rest once the motion ends, so reading never stutters it. Only
  // an open surface counts: one taken down mid-draw-in, as a rebuilt bar
  // takes its panel, can start its chart again as it goes.
  property var drawing: []
  function drawingIn(surface, running) {
    var others = root.drawing.filter(function(s) { return s !== surface })
    var next = running && root.openSurfaces.indexOf(surface) >= 0 ? others.concat([surface]) : others
    if (next.length !== root.drawing.length) root.drawing = next
  }
  // The chart a surface waits on to draw: the stock on show's, or a resting
  // preview's on view, while it can't be drawn yet; "" for none.
  readonly property string chartWaited: !root.view.chart ? root.view.featured
    : root.previewShown && !root.previewView.chart ? root.previewSymbol : ""

  // The order a list in order of change showed as a surface opened, held
  // while the prices the open asked for come in, so the rows move once,
  // when they're in (`Settings.shownOrder`): until no feed has anything
  // asked or out, a turn after the last says so, once what it answered is
  // applied, and Robinhood has nothing left to be asked (one request out
  // holds the next, the rows' behind the pill's); or until a site's pause
  // holds what is left. Changing the order, the list, or its rows lets it
  // go at once.
  property var heldOrder: null
  function releaseOrder() {
    if (!root.heldOrder) return
    var waiting = feed.busy || overnightFeed.busy || allDayFeed.busy || !!root.overnightWanted()
    if (waiting && !yahooGate.paused && !robinhoodGate.paused) return
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

  // Asked for once per change of the chart asked for, read from the view, so
  // a change of symbol and range together is one request, never a mixed pair.
  // A new range drops what was fetched ahead for the last one.
  property string chartOnShow: ""
  onViewChanged: {
    var chart = view.featured + "|" + view.range
    if (chart === chartOnShow) return
    var rangeLeft = chartOnShow !== "" && chartOnShow.split("|")[1] !== view.range
    chartOnShow = chart
    if (root.heroTaken && view.featured !== root.heroTaken.symbol) root.heroTaken = null
    if (rangeLeft) {
      // A turn later: the change of the view is still being told.
      var left = Object.keys(root.aheadAsked)
      root.aheadAsked = ({})
      root.aheadMissed = ({})
      if (left.length) Qt.callLater(function() { historyFeed.drop(left) })
    } else root.shownAsHero(view.featured)
    showHistory(false)
    askDue()
  }

  // A chart fetched ahead and now on a hero, featured or previewed, is a
  // hero's: a new range keeps it.
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

  // An open surface asks for the hero's cap and P/E: the featured symbol's
  // (`asker` "stock", or none), or a preview's ("preview"). One asked for
  // before its quote waits in its asker's place (`pendingFundamentals`) and
  // goes when the quote lands (`Asks.fundamentalsAsk`).
  function fetchFundamentals(symbol, asker) {
    var normalized = String(symbol || "").toUpperCase()
    var quote = root.quotes[normalized] || previewFeed.quotes[normalized]
    var by = asker || "stock"
    var ask = Asks.fundamentalsAsk(root.pendingFundamentals, by, normalized, quote)
    if (ask.pending !== root.pendingFundamentals) root.pendingFundamentals = ask.pending
    if (ask.fetch) fundamentalsFeed.fetch(normalized, quote.currency, by)
  }

  function keepPending(asker, symbol) {
    var next = Asks.pendingWith(root.pendingFundamentals, asker, symbol)
    if (next !== root.pendingFundamentals) root.pendingFundamentals = next
  }

  // An asker no screen shows takes back its cap and P/E, waiting on a quote
  // or behind another fetch.
  function withdrawFundamentals(asker) {
    root.keepPending(asker, "")
    fundamentalsFeed.withdraw(asker)
  }

  // Each ask that waited on its quote, now that quotes have changed.
  function askPendingFundamentals() {
    var pending = root.pendingFundamentals
    for (var asker in pending) if (pending[asker]) fetchFundamentals(pending[asker], asker)
  }

  // A quote that changed, by an answer, a restore, or a symbol leaving,
  // leaves the saved quotes behind (`flushQuotes`), written once the turn
  // is over: an undo restores the quote before All takes the symbol back,
  // and a write between the two left it out of the file.
  onQuotesChanged: {
    askPendingFundamentals()
    settleArrivals()
    root.quotesUnsaved = true
    Qt.callLater(flushQuotes)
  }
  // Every run's answers land in the entries, after their quotes, whether or
  // not a quote changed. Then, once the run has left the feed's asks, the
  // clock catches up to the answers' own second and the next ask falls due
  // from them; and the pill's first live answer asks Robinhood for it
  // (`askOvernight`).
  onEntriesChanged: {
    if (!root.answeredOnce) root.answeredOnce = Object.keys(feed.entries).some(function(s) { return feed.entries[s].status === "ok" })
    settleArrivals()
    Qt.callLater(flushQuotes)
    Qt.callLater(answersLanded)
  }
  function answersLanded() {
    root.tick()
    root.askDue()
    root.askOvernight()
  }
  onLibraryChanged: {
    settleArrivals()
    Qt.callLater(forgetLeft)
  }
  onPreviewSymbolChanged: Qt.callLater(forgetLeft)
  onLastRemovalChanged: Qt.callLater(forgetLeft)

  // What is kept by symbol is kept for All, the preview, and a removal
  // still on offer to undo: a symbol that leaves, or a preview passed by,
  // takes its built day and its cap and P/E with it, and Robinhood's
  // answers once they would be asked again anyway (a day for whether it
  // trades all day, a night's five minutes for its prints, each by when
  // that symbol was last asked), so a symbol added back meanwhile asks
  // Robinhood nothing. Pruned as those change and each minute. The quotes
  // go with the feeds' symbols, and histories by their own cap
  // (`HistoryFeed.keep`).
  function forgetLeft() {
    var now = root.wallSecond()
    var removed = root.lastRemoval ? root.lastRemoval.symbol : ""
    var keep = function(s) { return root.library.indexOf(s) >= 0 || s === root.previewSymbol || s === removed }
    for (var symbol in root.builtDays) if (!keep(symbol)) delete root.builtDays[symbol]
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

  // An add leaves arriving once it has answered, or has left All. One that
  // took the hero and failed hands it back (`heroTaken`).
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

  // Read once, as Stonks starts; written through `files`.
  FileView {
    id: quotesFile
    path: root.quotesPath
    blockLoading: true
    printErrors: false
  }
  // Stonks' files, its owner's alone (`OwnerOnly`): the one keeper of the
  // cache, which the sounds write through too.
  OwnerOnly { id: ownerOnly }
  readonly property alias files: ownerOnly

  // The saved quotes, { symbol: { quote, receivedAt } }; none when the file
  // is missing or unreadable.
  function parseSavedQuotes() {
    try {
      var parsed = JSON.parse(quotesFile.text())
      return parsed && parsed.version === 1 && parsed.quotes ? parsed.quotes : {}
    } catch (e) {
      return {}
    }
  }

  // Written once a quote has changed, at most every 10 minutes on the
  // service's clock: at once, then, if more changed meanwhile, as the wait
  // ends; and only once an answer has come, so quotes kept from an earlier
  // session are never written back as they are. Marked by every answer, it
  // was rewritten whole every 10 minutes around the clock, a weekend's
  // unmoving prices too. It waits while a surface opens or a chart draws in,
  // and for the quote runs out and the asks for quotes as it falls due,
  // then goes on a later tick: on a long list it takes 20 ms of the shell's
  // thread, which among an open's prices would stall them. Only those
  // (`saveWaitsFor`), not a later ask of the same quote, so runs back to
  // back on a slow link can't hold it for good; an open starts the wait
  // again, for its own. An ask Yahoo's pause holds, or one waiting while
  // every screen is off, can wait long, and the save doesn't.
  property bool quotesUnsaved: false
  property int quotesSavedAt: 0
  property var saveWaitsFor: null
  // An answer has come this session, though every price may have failed
  // since: what did come is still saved.
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

  // The settings in memory stay, the defaults if none were read, and
  // nothing is written until the file reads again.
  function takeUnreadableFile() {
    if (!root.settingsUnreadable)
      console.warn("stonks: " + root.dataPath + " can't be read; saving nothing until it can")
    root.settingsUnreadable = true
    if (!root.pluginsReady) root.adopt(root.dataSettings)
  }

  function takeMissingFile() {
    root.settingsUnreadable = false
    if (!root.pluginsReady) {
      var fromBar = Settings.settingsFromBar(root.parseShell())
      if (fromBar) {
        root.adopt(fromBar)
        root.writeDataFile(fromBar)
        return
      }
    }
    console.warn("stonks: settings file missing; using defaults")
    root.adopt(Settings.fileSettings(null))
  }

  // `settings` as `Settings.fileSettings` returns them, read back once
  // written (`takesRead`). The read also hands Quickshell the file's text,
  // which it compares a write with: after a lost save it would skip the
  // same text unheard. It starts once the handler that wrote has returned,
  // as a read's own (`takeMissingFile`) may: Quickshell 0.3.2 forgets a
  // read started inside a read's handlers (fileview.cpp, operationFinished).
  function writeDataFile(settings) {
    var body = JSON.stringify(settings, null, 2) + "\n"
    if (typeof dataFile.setText !== "function") {
      console.warn("stonks: cannot write " + root.dataPath)
      return
    }
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

  // The data file, last read as not there, is made rather than written:
  // Quickshell writes a new file as the shell's umask has it, 0644, and the
  // lists in it would show to another account until the chmod after it.
  // `OwnerOnly.create` makes it its owner's alone before it holds a byte,
  // with what Stonks wrote last. A write asked for meanwhile is written
  // once the file is there, into it, now 0600, or made again where it isn't
  // there. The read after judges it as it does any save (`takesRead`): one
  // that didn't land is said, and the next change or the footer's try
  // again makes it again, never writing it 0644 instead. Reads while it is
  // being made judge nothing.
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

  // Saved at once, or with `settles`, once the change has rested
  // (`settleWrite`); a change saved at once takes a waiting one with it.
  function persist(values, settles) {
    root.store(Settings.fileSettings(Object.assign({}, root.dataSettings, values)), settles)
  }

  // `next`, as `Settings.fileSettings` returns it, in memory and the file.
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

  // The pill's wheel steps through symbols faster than the file needs to
  // hear of each: the pill follows every notch, and the file is written
  // once the wheel has rested. A read of the file meanwhile, of its last
  // write or of an edit, keeps the symbol the wheel left.
  Timer {
    id: settleWrite
    interval: 400
    onTriggered: root.writeSettled()
  }
  function writeSettled() {
    if (root.pluginsReady && !root.settingsUnreadable) root.writeDataFile(root.dataSettings)
  }
  // The footer's try again: the settings in memory, written whole.
  function saveAgain() {
    settleWrite.stop()
    root.writeSettled()
  }
  Component.onDestruction: if (settleWrite.running) root.writeSettled()

  // A hero chosen, by a click, a Show, a key, or the wheel, is kept: an
  // add's hold on the hero ends (`heroTaken`).
  function feature(symbol, settles) {
    var s = String(symbol || "").toUpperCase()
    if (root.library.indexOf(s) < 0) return
    root.heroTaken = null
    root.persist({ featured: s }, settles)
  }

  // The pill's wheel and IPC's next and prev: the next row of the current
  // list, or from outside it its first or last, saved once the steps rest.
  function featureStep(delta) {
    var shown = root.view.shown
    if (shown.length === 0) return
    var at = shown.indexOf(root.view.featured)
    root.feature(at < 0 ? shown[delta > 0 ? 0 : shown.length - 1]
      : shown[(at + delta + shown.length) % shown.length], true)
  }

  // A summon's symbol and range, in one change.
  function summon(symbol, range) {
    var values = {}
    var s = String(symbol || "").toUpperCase()
    if (s && root.library.indexOf(s) >= 0) {
      values.featured = s
      // Asked for by name, it is a hero chosen (`feature`).
      root.heroTaken = null
    }
    if (History.historyRanges().indexOf(range) >= 0) values.range = range
    if (Object.keys(values).length) root.persist(values)
  }

  // Every membership change is a Settings.js rule: settings in, settings out.
  function save(next) {
    if (!Settings.settingsEqual(next, root.dataSettings)) root.store(next)
  }

  // A symbol new to All arrives: fetched ahead of any refresh, and shown
  // once it has answered. One already in All is a row at once. The result
  // the hero shows as a preview stays the hero: with a quote, it joins with
  // it, so nothing is fetched again and the chart does not change; with
  // none yet, it is the chart asked for, which each surface names while it
  // is on its way (`ChartMotion.loading`), as the preview did, until its
  // answer lands and its row joins. Found in the slow walk of 1.0.2: the
  // hero went back to the stock before the add, as if the add were done.
  // A first fetch the preview saw fail joins with that, the add done there,
  // its row saying so; one that fails later hands the hero back
  // (`heroTaken`).
  function addSymbol(symbol) {
    var s = String(symbol || "").trim().toUpperCase()
    if (s && s === root.previewSymbol && previewFeed.entries[s])
      feed.restore(s, previewFeed.quotes[s] || null, previewFeed.entries[s])
    if (s && root.library.indexOf(s) < 0 && root.arriving.indexOf(s) < 0 && !root.answered(s))
      root.arriving = root.arriving.concat([s])
    var previewed = s !== "" && s === root.previewSymbol
    var coming = previewed && root.arriving.indexOf(s) >= 0
    var next = Settings.withSymbolAdded(root.dataSettings, s)
    // Taken from an add still on its way, the hero to hand back is the one
    // before that add.
    var taken = root.heroTaken
    var before = taken && taken.symbol === root.view.featured && !feed.quotes[taken.symbol] ? taken.before : root.view.featured
    if (coming) root.heroTaken = { symbol: s, before: before }
    if (coming || (previewed && !!feed.quotes[s])) next.featured = s
    root.save(next)
  }

  // A featured symbol that leaves hands the hero to its neighbour in `shown`,
  // the rows as the surface shows them; the service's own order otherwise.
  function removeSymbol(symbol, shown) {
    root.remove(symbol, Settings.withMembership(root.dataSettings, symbol, root.listName, false, shown || root.shown))
  }

  // A tick or untick in a symbol's checklist; "" is All. Unticking All is a
  // removal, and can be taken back like one.
  function setMembership(symbol, name, member, shown) {
    var next = Settings.withMembership(root.dataSettings, symbol, name, member, shown || root.shown)
    if (name === "" && !member) root.remove(symbol, next)
    else root.save(next)
  }

  // A removal remembers the settings before it, the hero it left, and the
  // symbol's quote, so it can be taken back as it was without undoing
  // anything chosen since. It is the one removal on offer, whichever surface
  // made it, until the next change to the lists.
  function remove(symbol, next) {
    var before = root.dataSettings
    var quote = feed.quotes[symbol] || null
    var entry = feed.entries[symbol] || null
    root.save(next)
    root.lastRemoval = { symbol: symbol, before: before, left: root.dataSettings.featured, quote: quote, entry: entry }
  }

  // The last removal, put back where it was. Only once. Its quote is asked
  // for at once, as an add's is, not at its next refresh on the schedule:
  // the quote it had shows until the new one lands. The owner, 22 October.
  // It is watched again first (`askDue`), so a run landing before the
  // restore's own look at the schedule can't drop the ask as unwatched.
  function undoRemoval(symbol) {
    if (!root.lastRemoval || root.lastRemoval.symbol !== symbol) return
    var removal = root.lastRemoval
    root.lastRemoval = null
    if (removal.quote) feed.restore(symbol, removal.quote, removal.entry)
    root.save(Settings.withRemovalUndone(root.dataSettings, removal.before, symbol, removal.left))
    root.askDue()
    feed.ask([symbol], root.wallSecond())
  }

  // A hand-arranged order of the rows. Members still arriving keep their
  // places, so the order saved holds every member.
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

  // The current sorted order the other way; manual stays as it is.
  function reverseOrder() {
    root.save(Settings.withListReversed(root.dataSettings))
  }

  function switchList(name) {
    root.persist({ list: name })
  }

  // Makes and opens an empty list. Returns why not, or "" once it exists.
  function createList(name) {
    var problem = Settings.listNameProblem(name, root.dataSettings.lists)
    if (problem === "") root.save(Settings.withListCreated(root.dataSettings, name))
    return problem
  }

  // Returns why not, or "" once renamed. The new name takes the list's key
  // before the save, so no view shows the list under another key; the old
  // name, now free, takes a new one after.
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

  // A list made later under the deleted one's name is another list.
  function deleteList(name) {
    var i = Settings.listIndex(root.dataSettings.lists, name)
    if (i < 0) return
    var old = root.dataSettings.lists[i].name
    root.save(Settings.withListDeleted(root.dataSettings, name))
    root.keyList(old, "#" + (++root.listKeyCount))
  }

  // Each list's identity for the session, by name, for what is kept by list
  // and not saved (each surface's place in it): a rename keeps it, and a name
  // a rename or a delete freed names another list. A name with no entry is
  // its own key. A list renamed by editing the file is another list.
  property var listKeys: ({})
  property int listKeyCount: 0
  function listKey(name) { return root.listKeys[name] || "=" + name }
  function keyList(name, key) {
    var next = Object.assign({}, root.listKeys)
    next[name] = key
    root.listKeys = next
  }

  // The clock moves each second while a surface is open, for what it shows,
  // and each minute while none is; it also wakes at the second the next
  // quote falls due (`dueAt`) and a host's pause ends, at once for one the
  // wall clock has passed already. The wall clock is read in one place
  // (`wallSecond`).
  function wallSecond() { return Math.floor(Date.now() / 1000) }
  function tick() {
    root.now = root.wallSecond()
    root.armClock()
  }
  function armClock() {
    if (!root.pluginsReady) return
    clock.interval = Asks.clockWait(root.openSurfaces.length > 0, Date.now(), root.now,
      [root.dueAt, yahooGate.pausedUntil, robinhoodGate.pausedUntil, githubGate.pausedUntil])
    clock.restart()
  }
  onDueAtChanged: armClock()
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
  // Each step of the clock also tries the next chart ahead, which may have
  // waited on Yahoo's budget.
  Timer {
    id: clock
    onTriggered: {
      root.tick()
      root.fetchAhead()
    }
  }
}
