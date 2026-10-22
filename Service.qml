import QtQuick
import Quickshell
import Quickshell.Io
import "Chart.js" as Chart
import "Fundamentals.js" as Fundamentals
import "History.js" as History
import "Market.js" as Market
import "Overnight.js" as Overnight
import "Settings.js" as Settings
// The one data owner. Data settings live in grvc.stonks.json and are
// written only here, including what you are looking at: the list, the
// featured symbol, and the chart range the popup and the window share.
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
  property int now: Math.floor(Date.now() / 1000)
  // A symbol whose fundamentals were asked for before its first quote.
  property string pendingFundamentals: ""
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
  // The surfaces open now where a screen shows them: the popup on any bar,
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
  // The symbols whose quotes are kept fresh now: the featured symbol, which
  // the pill shows; every stock, ETF, and index in All through its own
  // regular session, so an open finds the rows fresh (`Market.staysWarm`);
  // and all of All while a surface is open. Each is asked for on its own
  // market's clock (`askDue`).
  property var watched: []

  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  readonly property string cacheFolder: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/grvc.stonks"
  // The last good quotes, shown at start until each one's first answer.
  readonly property string quotesPath: cacheFolder + "/quotes.json"

  // All, the library: every symbol, fetched once each whatever lists hold it.
  readonly property var library: dataSettings.symbols
  // The current list: "" for All. Its symbols in manual order are the rows.
  readonly property string listName: dataSettings.list
  // Every member of the current list, in manual order, arriving ones too.
  readonly property var symbols: Settings.listSymbols(dataSettings)
  readonly property string order: Settings.listOrder(dataSettings)
  readonly property bool reversed: Settings.listReversed(dataSettings)
  readonly property string range: dataSettings.range
  // The popup's first-run hint has shown.
  readonly property bool hinted: dataSettings.hinted
  // What the surfaces show of the settings, as one value, so a change of it
  // is whole whatever changed: the hero, the range, the list and its key
  // (`listKey`), which tells a rename from a switch, its order and
  // direction, its rows (members that have answered), those rows as sorted,
  // All, and the chart asked for once it is ready.
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
      shown: Settings.sortedSymbols(rows, feed.quotes, order, reversed),
      library: all,
      // The chart asked for once it can be drawn (`Chart.viewChart`), null
      // while it is on its way: each surface keeps the one it has on screen.
      chart: chart
    }
  }
  // The view with the preview as its hero, unadded: the rows and the range
  // as they are, and its chart once it can be drawn. The view itself while
  // there is none. A symbol in All has its chart as it does featured; a US
  // listing outside it has Yahoo's own day: Robinhood is asked only for All.
  readonly property var previewView: {
    var symbol = root.previewSymbol
    if (!symbol) return view
    var own = !!previewFeed.quotes[symbol] || !!previewFeed.entries[symbol]
    var quotes = own ? previewFeed.quotes : feed.quotes
    var entries = own ? previewFeed.entries : feed.entries
    var range = view.range
    var nights = own ? ({}) : overnightFeed.entries
    var allDay = own ? null : allDayFeed.entries
    var chart = Chart.viewChart(symbol, range, quotes, quotes[symbol] ? ({}) : entries,
      range === "1D" ? ({}) : historyFeed.entries, nights, allDay, calendars)
    root.keepDay(symbol, chart, nights, allDay)
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
  readonly property var histories: historyFeed.entries
  readonly property var fundamentals: fundamentalsFeed.entries
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
  // Robinhood's two questions, whether it trades a listing all day and its
  // prints, go side by side, so a 1D chart waits for one answer, never two
  // in a row. While a surface is open, for every US stock and ETF: whether
  // it trades all day, once a day each (`Overnight.allDayDue`); and the
  // prints of each not known to trade only by day, each by its own last ask
  // (`Overnight.overnightDue`): never asked, every 5 minutes as a night
  // goes, once after it ends. Whatever is asked takes with it each one due
  // within half that, so the list stays one request a night's 5 minutes,
  // and one the gate held back goes as soon as it lets it. With nothing
  // open, once a session, for the pill's symbol alone, what Robinhood has
  // not answered for it, as soon as Yahoo has answered it live, so the
  // first click finds its chart in hand. Looked at as the clock ticks,
  // answers land, the listings change, a surface opens, and the screens
  // answer; never while every screen is off (`screensClear`).
  property bool pillAsked: false
  function askOvernight() {
    if (!root.pluginsReady) return
    var open = root.openSurfaces.length > 0
    var pill = root.view.featured
    var live = !!feed.entries[pill] && feed.entries[pill].status === "ok" && root.overnightSymbols.indexOf(pill) >= 0
    if (!open && (root.pillAsked || !live)) return
    var listings = open ? root.overnightSymbols : [pill]
    var tradability = listings.filter(function(s) {
      return open ? Overnight.allDayDue(allDayFeed.entries[s], root.now) : !allDayFeed.entries[s]
    })
    var drawn = listings.filter(function(s) { return !allDayFeed.entries[s] || allDayFeed.entries[s].allDay })
    // The listings of one ask share its second (`entry.at`), so each ask is
    // judged once, not once a listing.
    var judged = {}
    var printsDue = function(s, at) {
      var entry = overnightFeed.entries[s]
      if (!entry) return true
      if (!open) return false
      var key = at + " " + entry.at + " " + entry.status
      if (!(key in judged)) judged[key] = Overnight.overnightDue(entry.at, at, root.calendars, entry.status === "failed")
      return judged[key]
    }
    var prints = drawn.filter(function(s) { return printsDue(s, root.now) })
    if (prints.length > 0)
      prints = drawn.filter(function(s) { return printsDue(s, root.now + Overnight.OVERNIGHT_INTERVAL / 2) })
    if ((tradability.length === 0 && prints.length === 0) || !root.screensClear()) return
    // The pill's own ask waits for a request already out, then goes.
    if (!open && (allDayFeed.busy || overnightFeed.busy)) return
    if (!open) root.pillAsked = true
    // The pill's symbol with no answer yet goes alone, ahead of the rest:
    // its chart is the one a click waits on. A feed with a request out
    // sends nothing more; each answer asks again for what is still wanted.
    var ask = function(robinhood, symbols) {
      var alone = symbols.length > 1 && symbols.indexOf(pill) >= 0 && !robinhood.entries[pill]
      robinhood.fetch(alone ? [pill] : symbols, root.now)
    }
    ask(allDayFeed, tradability)
    ask(overnightFeed, prints)
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

  // What is watched (`watched`), and of it what is due: a symbol whose last
  // answer, ok or failed, is as old as its own market's cadence
  // (`Market.quoteCadence`), the hero of an open surface on the interval.
  // Whatever is asked takes with it each one due within `dueSoon`, so a
  // symbol answered at a second of its own (featured, added, or retried)
  // joins the run at the next one, and the list stays one run: two seconds
  // of a minute are never more than half a minute apart one way.
  // First answers are the feed's own. Looked at as the clock reaches the
  // next one due (`dueAt`) and each minute, as answers land, as a surface
  // opens, as the featured symbol or a resting preview changes, and as the
  // interval does: on the wall clock, which `now` trails between ticks
  // while nothing is open. Whatever is asked goes only while a screen is on
  // (`screensClear`).
  property int dueAt: 0
  property int askedMinute: -1
  readonly property int dueSoon: 30
  function askDue() {
    if (!root.pluginsReady) return
    var now = root.wallSecond()
    root.askedMinute = Math.floor(now / 60)
    var open = root.openSurfaces.length > 0
    var featured = root.view.featured
    // Each market's calendar is read once a walk, not once a listing.
    var calendars = root.calendars
    var calendarsNow = new Map()
    var calNow = function(quote) {
      var cal = Market.calendarFor(calendars, quote)
      if (!calendarsNow.has(cal)) calendarsNow.set(cal, Market.calendarNow(cal, now))
      return calendarsNow.get(cal)
    }
    var watched = root.library.filter(function(s) {
      return open || s === featured || Market.staysWarm(feed.quotes[s], now, calNow(feed.quotes[s]))
    })
    if (watched.join(",") !== root.watched.join(",")) root.watched = watched
    var at = {}
    watched.forEach(function(s) {
      var entry = feed.entries[s]
      if (!entry || entry.status === "saved" || s in feed.asked) return
      var hero = open && (s === featured || (root.previewShown && s === root.previewSymbol))
      at[s] = entry.answeredAt + Market.quoteCadence(feed.quotes[s], now, root.refreshIntervalSec, hero, calNow(feed.quotes[s]))
    })
    var symbols = Object.keys(at)
    var asking = symbols.some(function(s) { return at[s] <= now })
    var due = symbols.filter(function(s) { return at[s] <= (asking ? now + root.dueSoon : now) })
    var next = 0
    symbols.forEach(function(s) { if (due.indexOf(s) < 0 && (next === 0 || at[s] < next)) next = at[s] })
    root.dueAt = next
    if (due.length > 0) feed.ask(due, now)
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
    // No screens to ask, as in a harness: nothing holds.
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
    root.askOvernight()
    if (root.refreshOwed) {
      root.refreshOwed = false
      root.refreshRest()
    }
    root.refreshRange()
    root.fetchAhead()
    releaseFeed.pump()
  }
  // The day last built for each symbol's chart, kept while what built it is
  // the same: its quote, and for a listing Robinhood trades all day its
  // prints, read from the answers the chart was built from (`nights`,
  // `allDay`, as `Chart.viewChart` took them), so an own preview's Yahoo day
  // is never handed to the same symbol's calendar day once it is added. An
  // answer for another symbol hands the chart the objects it has and nothing
  // that draws it repaints. Written in place by the views, and pruned with
  // the other caches by symbol (`forgetLeft`); it notifies nothing.
  readonly property var builtDays: ({})
  function keepDay(symbol, chart, nights, allDay) {
    if (!chart || !chart.quote || chart.day === chart.quote) return
    var tradability = allDay ? allDay[symbol] : null
    var night = tradability && tradability.allDay ? nights[symbol] : null
    var bars = night ? night.bars : null
    var built = builtDays[symbol]
    if (built && built.quote === chart.quote && built.bars === bars) {
      chart.day = built.day
      chart.latest = built.latest
    } else {
      builtDays[symbol] = { quote: chart.quote, bars: bars, day: chart.day, latest: chart.latest }
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
    onLoaded: root.dataReadEnded(root.takeLoadedSettings)
    // Only a file that isn't there is missing: one there that can't be
    // read, for its permissions or as a folder, is never written over.
    onLoadFailed: function(error) {
      root.dataReadEnded(error === FileViewError.FileNotFound ? root.takeMissingFile : root.takeUnreadableFile)
    }
    // A write drops a read in flight unheard: neither loaded nor failed.
    // Written, the file is its owner's alone (`OwnerOnly`).
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
    now: root.now
    clock: root
    clearance: function() { return root.screensClear() }
    gate: yahooGate
    centExchanges: root.centExchanges
  }

  // One chart's history at a time; an answer may leave another chart a
  // refresh still owes, or one with no answer yet, which is asked for next;
  // with none, a chart in sight is fetched ahead (`fetchAhead`).
  HistoryFeed {
    id: historyFeed
    gate: yahooGate
    clock: root
    centExchanges: root.centExchanges
    inUse: root.chartsInUse
    onEntriesChanged: {
      var owed = root.owedHistory()
      if (owed.length > 0) historyFeed.request(owed[0], root.view.range, true)
      else {
        var unanswered = root.unansweredHistory()
        if (unanswered.length > 0) historyFeed.request(unanswered[0], root.view.range, false)
      }
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
    bulk: false
    onQuotesChanged: if (root.pendingFundamentals) root.fetchFundamentals(root.pendingFundamentals)
  }

  FundamentalsFeed { id: fundamentalsFeed; gate: yahooGate }
  // Robinhood's feeds send one request at a time; each answer asks again
  // for what is still wanted, while it still is (`askOvernight`).
  AllDayFeed { id: allDayFeed; gate: robinhoodGate; onEntriesChanged: Qt.callLater(root.askOvernight) }
  OvernightFeed { id: overnightFeed; gate: robinhoodGate; onEntriesChanged: Qt.callLater(root.askOvernight) }
  // Off by the data file's `updateCheck`, it asks GitHub nothing.
  ReleaseFeed {
    id: releaseFeed
    ready: root.pluginsReady && root.dataSettings.updateCheck
    now: root.now
    clock: root
    clearance: function() { return root.screensClear() }
    gate: githubGate
  }
  // The version on main, "" until GitHub has named one, and when it last
  // did (`Updates`).
  readonly property alias mainVersion: releaseFeed.version
  readonly property alias mainNamedAt: releaseFeed.namedAt

  // A user's refresh, from a key, the pill, or IPC: every watched quote
  // whose last answer is more than 10 s old, and the overnight prints of
  // the charts on show, unless asked for in the last 10 s, so a second
  // press adds nothing; and the chart's history fresh whatever the cache
  // holds. While every screen is off the quotes wait their turn, and the
  // rest is owed (`refreshOwed`) until a screen is on.
  property bool refreshOwed: false
  function refresh() {
    if (!root.pluginsReady) return
    var now = root.wallSecond()
    feed.ask(root.watched.filter(function(s) {
      var entry = feed.entries[s]
      return !!entry && entry.status !== "saved" && now - entry.answeredAt > 10
    }), now)
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
    var charts = root.chartsOnShow().filter(function(s) { return root.allDaySymbols.indexOf(s) >= 0 })
    if (charts.length > 0 && now - overnightFeed.askedAt > 10) overnightFeed.fetch(charts, now)
  }

  // The history the open surfaces' heroes show on the shared range: the
  // featured symbol's, on every open surface but the one previewing, and
  // the preview's once the choice rests on it. The day needs none, and
  // neither does the pill, which always shows the day. One request at a
  // time: a chart a user's refresh (`force`) still owes first, fetched
  // fresh, then one with no answer yet, else the last, the preview.
  function showHistory(force) {
    if (!root.pluginsReady) return
    var charts = root.historyCharts()
    if (charts.length === 0) {
      root.historyOwed = ({})
      historyFeed.clear()
      return
    }
    var range = root.view.range
    if (force) {
      var owing = {}
      charts.forEach(function(s) {
        var key = historyFeed.keyFor(s, range)
        owing[key] = historyFeed.entries[key] || null
      })
      root.historyOwed = owing
    }
    var owed = root.owedHistory()
    if (owed.length > 0) {
      historyFeed.request(owed[0], range, true)
      return
    }
    var unanswered = root.unansweredHistory()
    historyFeed.request(unanswered.length > 0 ? unanswered[0] : charts[charts.length - 1], range, false)
  }

  // A range left on show with its history in hand is asked again as its
  // market moves it (`History.historyDue`), a failed refresh too, so its
  // line and its low and high keep up with the price over it: a hero's at a
  // time, when the feed has nothing on its way, and only while a screen is
  // on. Looked at each minute.
  function refreshRange() {
    if (!root.pluginsReady || historyFeed.busy) return
    var range = root.view.range
    var now = root.wallSecond()
    var stale = root.historyCharts().filter(function(s) {
      var entry = historyFeed.entries[historyFeed.keyFor(s, range)]
      var quote = feed.quotes[s] || previewFeed.quotes[s]
      var trading = !!quote && (quote.crypto || Market.inRegularSession(quote, now, root.calendars))
      return !!entry && !!entry.history && History.historyDue(range, entry, quote, now, trading)
    })
    if (stale.length > 0 && root.screensClear()) historyFeed.request(stale[0], range, false)
  }

  // The charts a user's refresh asked for fresh, each with the answer it had
  // then: one is owed until a new answer, ok or failed, replaces that.
  property var historyOwed: ({})
  function owedHistory() {
    var range = root.view.range
    return root.historyCharts().filter(function(s) {
      var key = historyFeed.keyFor(s, range)
      return key in root.historyOwed && historyFeed.entries[key] === root.historyOwed[key]
    })
  }

  // The symbols the open surfaces' heroes chart: the featured symbol, which
  // an add from search still on its way already is (`addSymbol`), so the
  // fetch its preview has out goes on as the hero's; and a resting
  // preview.
  function chartsOnShow() {
    if (root.openSurfaces.length === 0) return []
    var charts = []
    if (root.previewSymbol === "" || root.openSurfaces.some(function(s) { return s !== root.previewSurface }))
      charts.push(root.view.featured)
    if (root.previewSymbol !== "" && root.previewShown && charts.indexOf(root.previewSymbol) < 0)
      charts.push(root.previewSymbol)
    return charts.filter(function(s) { return s !== "" })
  }

  // Those whose history they show: none on the day.
  function historyCharts() {
    return root.view.range === "1D" ? [] : root.chartsOnShow()
  }

  // Those of them with no answer yet, ok or failed.
  function unansweredHistory() {
    var range = root.view.range
    return root.historyCharts().filter(function(s) { return !historyFeed.entries[historyFeed.keyFor(s, range)] })
  }

  // The rows each open surface shows, top first, as { surface, symbols }
  // (`rowsSeen`): on a range, their charts are fetched ahead of a click.
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

  // The rows in sight on the open surfaces, top first, each surface's in
  // the order they opened, but the heroes': only as many as the history
  // cache keeps beside the heroes' charts.
  function aheadRows() {
    if (root.openSurfaces.length === 0 || root.view.range === "1D") return []
    var heroes = root.historyCharts()
    var rows = []
    root.sights.forEach(function(sight) {
      sight.symbols.forEach(function(s) { if (rows.indexOf(s) < 0 && heroes.indexOf(s) < 0) rows.push(s) })
    })
    return rows.slice(0, historyFeed.keep - heroes.length)
  }

  // Those of them whose chart on this range has no answer yet, nor has
  // missed one ahead.
  function aheadCharts() {
    var range = root.view.range
    return root.aheadRows().filter(function(s) {
      var key = historyFeed.keyFor(s, range)
      return !historyFeed.entries[key] && !root.aheadMissed[key]
    })
  }

  // The charts the heroes show and those of the rows in sight, which the
  // cache never lets go for another.
  readonly property var chartsInUse: root.historyCharts().concat(root.aheadRows()).map(function(s) {
    return historyFeed.keyFor(s, root.view.range)
  })

  // One chart in sight fetched ahead, once the heroes' charts want nothing,
  // while Yahoo has budget to spare (`Gate.spare`) and a screen is on; the
  // next goes as the feed is idle again, or on the clock.
  function fetchAhead() {
    if (!root.pluginsReady || historyFeed.busy || root.screensOff || !yahooGate.spare()) return
    var next = root.aheadCharts()[0]
    if (!next || !root.screensClear()) return
    var key = historyFeed.keyFor(next, root.view.range)
    var asked = Object.assign({}, root.aheadAsked)
    asked[key] = true
    root.aheadAsked = asked
    historyFeed.request(next, root.view.range, false, true)
  }

  // A surface's search shows its choice on the hero (`previewView`), or
  // nothing with "", which only the search previewing can say. What it
  // needs is asked for only once the choice has rested there, so arrowing
  // past a result asks for nothing.
  function preview(surface, symbol) {
    var s = String(symbol || "").trim().toUpperCase()
    if (!s && surface !== root.previewSurface) return
    if (s === root.previewSymbol && surface === root.previewSurface) return
    var before = root.previewSurface
    // The rest first: a choice that moves on has not rested on the next one.
    root.previewRests = false
    root.previewSurface = s ? surface : null
    root.previewSymbol = s
    if (s) {
      root.shownAsHero(s)
      previewRest.restart()
    } else previewRest.stop()
    root.showHistory(false)
    if (before && before !== root.previewSurface && s) root.previewTaken(before)
  }

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
  // back while it is not: its quote, and its cap and P/E.
  onPreviewShownChanged: if (previewShown) {
    previewFeed.pump()
    fetchFundamentals(previewSymbol)
  }

  // A surface says when it opens and closes, and as it goes. The clock
  // catches up at once, and moves on at the pace that now holds.
  function surfaceShown(surface, open) {
    var others = root.openSurfaces.filter(function(s) { return s !== surface })
    var next = open ? others.concat([surface]) : others
    if (next.length === root.openSurfaces.length) return
    root.openSurfaces = next
    if (!open) root.sights = root.sights.filter(function(s) { return s.surface !== surface })
    root.tick()
    root.showHistory(false)
    root.askOvernight()
    root.askDue()
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

  // An open surface asks for the hero's cap and P/E: the featured symbol's,
  // or a preview's. One asked for before its quote goes when the quote
  // lands, and only an equity's.
  function fetchFundamentals(symbol) {
    var normalized = String(symbol || "").toUpperCase()
    var quote = root.quotes[normalized] || previewFeed.quotes[normalized]
    if (!quote) {
      root.pendingFundamentals = normalized
      return
    }
    root.pendingFundamentals = ""
    if (Fundamentals.hasFundamentals(quote)) fundamentalsFeed.fetch(normalized)
  }

  // A quote that changed, by an answer, a restore, or a symbol leaving,
  // leaves the saved quotes behind (`flushQuotes`), written once the turn
  // is over: an undo restores the quote before All takes the symbol back,
  // and a write between the two left it out of the file.
  onQuotesChanged: {
    if (pendingFundamentals) fetchFundamentals(pendingFundamentals)
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

  FileView {
    id: quotesFile
    path: root.quotesPath
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onSaved: ownerOnly.keep([root.quotesPath])
  }
  OwnerOnly { id: ownerOnly; folder: root.cacheFolder }

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
  // unmoving prices too.
  property bool quotesUnsaved: false
  property int quotesSavedAt: 0

  function flushQuotes() {
    if (!root.quotesUnsaved || (root.quotesSavedAt && root.now - root.quotesSavedAt < 10 * 60)) return
    if (!Object.keys(feed.entries).some(function(s) { return feed.entries[s].status === "ok" })) return
    root.quotesUnsaved = false
    root.quotesSavedAt = root.now
    var saved = {}
    root.library.forEach(function(s) {
      if (feed.quotes[s]) saved[s] = { quote: feed.quotes[s], receivedAt: (feed.entries[s] || {}).receivedAt || 0 }
    })
    if (typeof quotesFile.setText === "function") quotesFile.setText(JSON.stringify({ version: 1, quotes: saved }) + "\n")
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

  // `settings` as `Settings.fileSettings` returns them.
  function writeDataFile(settings) {
    var body = JSON.stringify(settings, null, 2) + "\n"
    if (typeof dataFile.setText !== "function") {
      console.warn("stonks: cannot write " + root.dataPath)
      return
    }
    dataFile.setText(body)
  }

  // Saved at once, or with `settles`, once the change has rested
  // (`settleWrite`); a change saved at once takes a waiting one with it.
  function persist(values, settles) {
    root.store(Settings.fileSettings(Object.assign({}, root.dataSettings, values)), settles)
  }

  // `next`, as `Settings.fileSettings` returns it, in memory and the file.
  function store(next, settles) {
    root.dataSettings = next
    if (!root.pluginsReady || root.settingsUnreadable) return
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

  // The last removal, put back where it was. Only once.
  function undoRemoval(symbol) {
    if (!root.lastRemoval || root.lastRemoval.symbol !== symbol) return
    var removal = root.lastRemoval
    root.lastRemoval = null
    if (removal.quote) feed.restore(symbol, removal.quote, removal.entry)
    root.save(Settings.withRemovalUndone(root.dataSettings, removal.before, symbol, removal.left))
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

  function stepList(delta) {
    root.switchList(Settings.steppedList(root.dataSettings, delta))
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
    var wall = root.wallSecond()
    var next = root.openSurfaces.length > 0 ? wall + 1 : (Math.floor(wall / 60) + 1) * 60
    ;[root.dueAt, yahooGate.pausedUntil, robinhoodGate.pausedUntil, githubGate.pausedUntil].forEach(function(at) {
      if (at > root.now && at < next) next = at
    })
    // To just past that second's start.
    clock.interval = Math.max(0, (next - wall - 1) * 1000 + 1000 - Date.now() % 1000) + 5
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
