import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin/Cells.js" as Cells
import "plugin/Chart.js" as Chart
import "plugin/Fundamentals.js" as Fundamentals
import "plugin/History.js" as History
import "plugin/Market.js" as Market
import "plugin/Overnight.js" as Overnight
import "plugin/Quote.js" as Quote
import "plugin/Search.js" as Search
import "plugin/Settings.js" as Settings
import "plugin"

// Offscreen window body. A stub surface feeds StonksBody from fixtures.
// Grab the opaque window-sized layer so margins stay in the PNG. The
// w22-<surface>-<look>-<symbol>-<range> states render the 22-symbol list with
// a real day featured, at identical state in both looks; a popup is as tall
// as its whole rows, the way Panel sizes it. sprite-candidates draws the
// bull and bear candidates at 1x and 4x. pill-sheet draws the real bar pill
// for NEST in every bar style and look, on a horizontal and a vertical bar.
Harness {
  id: root
  marker: "RENDER DONE"

  // window-of-<state>: a popup-<state> in the window instead (the ranges,
  // the 52-week high, an overnight moment), the same data. The sweep has
  // its own window-sweep-*. min-window-of-<state>: the same in the smallest
  // window.
  // share-of-<state>: the screenshot the camera takes of popup-<state>, at
  // its full size, in place of the surface; share-scrub-of-<state>: the
  // same scrubbed to the day's middle print. lit-<state>: the surface after
  // a screenshot, its camera lit; quiet-<state>: with sounds off; both may
  // lead, quiet- first. <state>-size-N: the state at text size N
  // (render.sh) in the frame the shell gives it there, the popup and the
  // smallest window grown with the text, as a reader sees it; the state as
  // named without the suffix. The pill sheet keeps its name and draws its
  // own frame.
  readonly property string asked: Quickshell.env("STONKS_VISUAL_STATE") || "retro"
  readonly property bool quiet: /^quiet-/.test(asked)
  readonly property bool lit: /^(quiet-)?lit-/.test(asked)
  readonly property bool shareScrub: asked.indexOf("share-scrub-of-") === 0
  readonly property bool shareOf: shareScrub || asked.indexOf("share-of-") === 0
  readonly property string requested: {
    var state = asked.replace(/^(quiet-)?(lit-)?/, "")
    if (shareOf) state = "popup-" + state.slice(state.indexOf("-of-") + 4)
    return state.indexOf("pill-sheet") === 0 ? state : state.replace(/-size-\d+$/, "")
  }
  // A -size-N state's text scale, as Style.fontScale has it; 1 for the rest.
  readonly property real sizeScale: {
    var m = /-size-(\d+)$/.exec(asked)
    return m ? Math.max(1 / 12, Number(m[1]) / 12) : 1
  }
  readonly property bool minWindowOf: requested.indexOf("min-window-of-") === 0
  readonly property bool windowOf: minWindowOf || requested.indexOf("window-of-") === 0
  readonly property string stateName: windowOf ? "popup-" + requested.slice((minWindowOf ? "min-window-of-" : "window-of-").length) : requested
  // A control under real pointer input: its hover, or its press filmed and
  // judged (frames.js press), then drawn held.
  readonly property var controlState: /^(popup|window)-controls-([a-z]+)-(hover|press)-(smooth|retro)$/.exec(stateName)
  readonly property var anchorState: /^popup-anchor-(left|center|right)-(open|held|next)-(smooth|retro)$/.exec(stateName)
  FileView { id: anchorPoses; path: Quickshell.env("STONKS_ANCHOR_POSES"); blockLoading: true }
  readonly property var anchorPose: anchorState ? JSON.parse(anchorPoses.text())[anchorState[1] + "-" + anchorState[2]] : null
  readonly property var motionPose: /^popup-motion-(join|crossing|dragwheel|scroll|endremove|notefade|breadth|look|neutral)-(smooth|retro)$/.exec(stateName)
  readonly property var refusedList: /^min-window-lists-refused-(menu|manage)-(smooth|retro)$/.exec(stateName)
  readonly property bool interactivePicture: !!controlState || !!anchorState || !!motionPose || !!refusedList
  readonly property string outPath: Quickshell.env("STONKS_VISUAL_OUT")
  readonly property string fixtureDir: Quickshell.env("STONKS_FIXTURES")
  readonly property string calendarPath: Quickshell.env("STONKS_VISUAL_CALENDARS")
  // What a state does as its picture is taken, after everything has
  // landed; null for none.
  property var beforeGrab: null
  readonly property var w22: {
    var match = /^w22-(popup|window|min-window)-(smooth|retro)-([a-z]+)-(1d|1y|5y)$/.exec(stateName)
    return match ? { popup: match[1] === "popup", min: match[1] === "min-window", symbol: match[3], range: match[4] } : null
  }
  // The smallest window App.qml allows.
  readonly property bool smallest: minWindow || minWindowOf || (!!w22 && w22.min)
  // loading and failed: a cold start, the first quotes out or failed, in
  // retro, or in smooth with -smooth; in the popup with popup- before.
  readonly property string coldState: (/^(?:popup-)?(loading|failed)(?:-smooth)?$/.exec(stateName) || ["", ""])[1]
  // The popup while adding, and the window at the size App.qml permits.
  readonly property bool searchState: stateName.indexOf("-search") >= 0
  readonly property bool minWindow: stateName.indexOf("min-window-") === 0
  // <popup|window>-room-<list>-<moment>-<look>: search on a list of one,
  // four, or five rows, or the empty named list Growth, as it opens, with
  // one result, five, none, no answer, or an answer of long symbols.
  readonly property var room: {
    var match = /^(popup|window)-room-(one|four|five|growth)-(open|one|five|none|failed|long)-(smooth|retro)$/.exec(stateName)
    return match ? { list: match[2], moment: match[3] } : null
  }
  // window-1416-<look>: the tiled window at the full 1416 by 850 the live run
  // measured, the 22-symbol list.
  readonly property int windowWidth: {
    var match = /^window-(\d+)-(smooth|retro)$/.exec(stateName)
    return match ? Number(match[1]) : 0
  }
  // <popup|window>-order-<falls|rises>-<look>: the order word both ways.
  readonly property bool orderState: /^(popup|window)-order-(falls|rises)-/.test(stateName)
  readonly property bool bigList: !!controlState || !!motionPose || !!w22 || !!room || minWindow || windowWidth > 0 || stateName.indexOf("popup-search-") === 0
    || stateName.indexOf("popup-price") === 0 || /^(popup|window)-rowstates-/.test(stateName)
    || stateName.indexOf("popup-note-") === 0 || stateName.indexOf("window-note-") === 0 || stateName.indexOf("popup-lists-") === 0
    || stateName.indexOf("popup-rowlines-") === 0 || stateName.indexOf("popup-52w-") === 0
    || stateName.indexOf("popup-breadth-even-") === 0
    || stateName.indexOf("window-lists-") === 0 || orderState
    || /^(popup|window|min-window)-update-offer-/.test(stateName)
  readonly property bool sheet: stateName === "sprite-candidates"
  // pill-sheet-large: the same at a larger text size (render.sh);
  // pill-sheet-<theme>: in another theme.
  readonly property bool pillSheet: stateName.indexOf("pill-sheet") === 0
  property var pillQuote: null
  // The same day closed up, and closed where it opened: the icon form's
  // bull, and its flat day.
  readonly property var pillUpQuote: pillQuote ? Object.assign({}, pillQuote, { prevClose: pillQuote.price * 0.97 }) : null
  readonly property var pillFlatQuote: pillQuote ? Object.assign({}, pillQuote, { prevClose: pillQuote.price }) : null
  function pillQuoteFor(day) { return day === "up" ? pillUpQuote : day === "flat" ? pillFlatQuote : day === "down" ? pillQuote : null }
  readonly property bool popup: windowOf ? false : w22 ? w22.popup : stateName.indexOf("popup") === 0 || themeState
  // <popup-help|popup-help-sorted|window-help>-<look>: the key sheet.
  readonly property var help: {
    var match = /^(popup-help|popup-help-sorted|window-help)-(smooth|retro)$/.exec(stateName)
    return match ? { sorted: match[1] === "popup-help-sorted", window: match[1] === "window-help" } : null
  }
  readonly property bool historyState: stateName.indexOf("history-") === 0
    || stateName.indexOf("popup-history-") === 0
  readonly property bool nestState: stateName.indexOf("popup-history-1w-") === 0
    || stateName.indexOf("popup-history-1m-") === 0
  readonly property bool nestDayState: stateName.indexOf("popup-nest-1d-") === 0
  readonly property bool holidayState: /^popup-holiday-(smooth|retro)$/.test(stateName)
  // <popup|min-window>-holiday-<tokyo|london>-<look>: the calendars' longest
  // closures, at the exchange's noon, the listing's own saved day featured:
  // Tokyo's Constitution Memorial Day observed (6 May 2026) and London's
  // Christmas Day (substitute) (27 December 2027).
  readonly property var closure: {
    var match = /^(?:popup|min-window)-holiday-(tokyo|london)-(smooth|retro)$/.exec(stateName)
    return !match ? null : match[1] === "tokyo" ? { symbol: "7203.T", file: "7203-t-day", date: "2026-05-06" }
      : { symbol: "SHEL.L", file: "shel-l-day", date: "2027-12-27" }
  }
  // <popup|window-of>-first-day-<1d|1y>-<look>: answers saved on 14 October
  // 2026, when the 1Y range's first day held RGTI's 1Y high above Yahoo's
  // 52 weeks, on a day at its 52-week low, beside GOOG, TD.TO, ^N225, and
  // ETH-USD, whose first day held theirs, and SPY, whose did not.
  readonly property var firstDay: {
    var match = /^popup-first-day-(1d|1y)-(smooth|retro)$/.exec(stateName)
    return match ? { range: match[1].toUpperCase() } : null
  }
  // popup-overnight-<moment>-<symbol>-<look>: a saved moment from
  // test/fixtures/moments, NEST, SILK, and REED with Robinhood's prints;
  // at the live moment (Monday 5 October, 00:36), NEST, EZ, and TOY, on 1D
  // or on 1M (-1m), at rest or scrubbed (-1m-scrub); at a dated moment
  // (<date>-<hhmm>, New York), NEST alone, on 1D at rest or scrubbed to its
  // last print (-scrub). Robinhood trades every one of them all day there.
  // <popup|window>-sweep-<moment>-<symbol>-<look>: the listing sweep's
  // moments (listings-<date>-<hhmm>), every kind of listing on 1D at rest:
  // NEST, KILN, SPY, BOLT, the S&P 500 (gspc), BTC-USD, SHEL.L, and 7203.T,
  // with Robinhood's saved answers on which it trades all day.
  // <popup|window>-sweep-<folder>-<symbol>-<look>: any saved moment whose
  // folder is named for its minute, <word>-<date>-<hhmm> (the weekend
  // watch's watch-2026-10-24-2238), every listing its folder saved on 1D at
  // rest, <symbol> named as its answer's file (aapl, shel.l, gspc) and
  // featured, at the folder's clock, with Robinhood's saved answers on which
  // it trades all day. render.sh hands over the folder's answers
  // (STONKS_VISUAL_SAVED), since QML can't list a folder.
  // <popup|window>-sweep-own-<shel.l|7203.t>-<look>: the 7 October 14:55
  // sweep with London before its session, or Tokyo at lunch, from that
  // listing's own saved day, at a clock inside that moment.
  // <popup|window>-power-<symbol>-<look>: the power-user walk's odd days,
  // Friday 16 October at 23:09, with Yahoo's own day (no Robinhood answer
  // was saved): JPM's stray pair, PLUG's and AITX's one-tick bounces, CKX's
  // one bar, CVR's none, and LUMN's four-decimal hint.
  // <popup|window>-gaps-<1d|3m>-<look>: VANE, a thin NYSE stock, on
  // Wednesday 21 October at 10:06, with Robinhood's prints: 26 since
  // midnight, its night quiet for over an hour twice, and nine pre-market
  // prints hours apart; or its 3M, 66 days.
  readonly property var overnight: {
    // A constructed metadata omission: the saved answer itself had a quote.
    if (/^popup-last-trade-(smooth|retro)$/.test(stateName)) return {
      moment: "2026-10-07-0100", folder: "listings-2026-10-07-0100", symbol: "NEST", listed: ["NEST"],
      month: false, scrub: false, dated: true, sweep: false, lastTrade: true }
    var match = /^popup-overnight-(day|night|sunday|live|\d{4}-\d\d-\d\d-\d{4})-(nest|silk|reed|ez|toy)(-1m|-1m-scrub|-scrub)?-(smooth|retro)$/.exec(stateName)
    if (match) return { moment: match[1], symbol: match[2].toUpperCase(), month: match[3] === "-1m" || match[3] === "-1m-scrub",
      scrub: !!match[3] && match[3] !== "-1m", dated: /^\d/.test(match[1]), sweep: false }
    match = /^(?:popup|window)-sweep-own-(shel\.l|7203\.t)-(smooth|retro)$/.exec(stateName)
    if (match) return { moment: "2026-10-07-1455", symbol: match[1].toUpperCase(), month: false, scrub: false, dated: true, sweep: true,
      own: match[1] === "shel.l" ? { file: "shel-l-day", at: Date.UTC(2026, 9, 2, 5, 30) / 1000 }
        : { file: "7203-t-day", at: Date.UTC(2026, 9, 2, 2, 45) / 1000 } }
    match = /^(?:popup|window)-power-(jpm|plug|aitx|ckx|cvr|lumn)-(smooth|retro)$/.exec(stateName)
    if (match) return { moment: "2026-10-16-2309", folder: "power-user-2026-10-16", symbol: match[1].toUpperCase(), month: false,
      scrub: false, dated: true, sweep: false, power: true }
    match = /^(?:popup|window)-sweep-(\d{4}-\d\d-\d\d-\d{4})-(nest|kiln|spy|bolt|gspc|btc-usd|shel\.l|7203\.t|shib-usd|ry\.to|brk-a|brk-b)-(smooth|retro)$/.exec(stateName)
    if (match) return { moment: match[1], symbol: match[2] === "gspc" ? "^GSPC" : match[2].toUpperCase(), month: false, scrub: false,
      dated: true, sweep: true }
    match = /^(?:popup|window)-sweep-([a-z]+-(\d{4}-\d\d-\d\d-\d{4}))-([a-z0-9.^-]+)-(smooth|retro)$/.exec(stateName)
    if (match) return { moment: match[2], folder: match[1], file: match[3], month: false, scrub: false, dated: true, sweep: true,
      saved: String(Quickshell.env("STONKS_VISUAL_SAVED") || "").split(" ").filter(function(f) { return f !== "" }) }
    match = /^(?:popup|window)-gaps-(1d|3m)-(smooth|retro)$/.exec(stateName)
    return match ? { moment: "2026-10-21-1006", folder: "gaps-2026-10-21-1006", symbol: "VANE", listed: ["VANE"], month: false,
      quarter: match[1] === "3m", scrub: false, dated: true, sweep: false } : null
  }
  // popup-fill-<day>-<look>[-<theme>]: the 1D wash on an up day (SPY 11
  // Sep), a down day (AAPL 4 Sep), and a day across its baseline (NEST 11
  // Sep). theme-<look>-<theme>: the gallery, the day across its baseline
  // with every pill form beside it. Every render is in an installed Omarchy
  // theme, the one its name ends with or Tokyo Night, which render.sh puts
  // where the shell reads the current theme.
  readonly property bool themeState: /^theme-(smooth|retro)-[a-z0-9-]+$/.test(stateName)
  readonly property var fill: {
    if (themeState) return { day: "cross" }
    var match = /^popup-fill-(up|down|cross)-(smooth|retro)(?:-[a-z0-9-]+)?$/.exec(stateName)
    return match ? { day: match[1] } : null
  }
  // The theme's up and down, as the plugin reads them.
  property TrendColors trendColors: TrendColors {}
  // The surface's ground: the popup's card, opaque, or the window's.
  readonly property color groundColor: popup
    ? Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 1) : Commons.Color.background
  // The bar's own ground and ink, opaque, for the pills.
  readonly property color barGround: Qt.rgba(Commons.Color.bar.background.r, Commons.Color.bar.background.g, Commons.Color.bar.background.b, 1)
  property int now: holidayState ? 1813334400 : (nestState || nestDayState ? 1789156800 : 1788294000)
  property string shownRange: historyState ? "1Y" : "1D"
  property var shownHistoryEntry: null
  // popup-loading-<kind>-<look>: the symbol that kind's chart is held for,
  // its own 1Y on show, dimmed, until it comes.
  readonly property var loadingKind: /^popup-loading-(aapl|shel-l|btc-usd)-/.exec(stateName)
  property string loadingNext: ""
  // The saved cap and EPS by symbol, the cap with its close, as the feed
  // keeps them: AAPL, NEST, SHOP.TO, 7203.T, and SHEL.L have them; any
  // other symbol shows what its quote alone gives. And Yahoo's saved rates
  // by pair, which SHOP.TO's and SHEL.L's P/Es need.
  property var savedFigures: ({})
  property var savedRates: ({})

  function fundamentalsAnswer(path) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', root)
    view.path = fixtureDir + "/fundamentals/" + path + ".json"
    var json = JSON.parse(view.text())
    view.destroy()
    return json
  }

  function figures(name) {
    return Fundamentals.withCapClose(Fundamentals.parseFundamentals(fundamentalsAnswer(name)), fundamentalsAnswer(name + "-closes"))
  }

  function rate(pair) {
    return { value: Fundamentals.parseRate(fundamentalsAnswer("fx-" + pair.toLowerCase()), pair), checkedAt: 0 }
  }

  readonly property var bullCandidates: [
    [".##..............##.", "##................##", "##................##", ".###............###.",
     "..#####......#####..", "....############....", "###.############.###", ".##.#.########.#.##.",
     "....############....", "....############....", "...##############...", "...###.######.###...",
     "...##############...", "....############...."],
    Cells.BULL_SPRITE.slice(),
    [".##..............##.", "##................##", "##................##", ".###............###.",
     "..#####......#####..", "....############....", "###.############.###", ".##.#.########.#.##.",
     "....############....", "...##############...", "...###.######.###...", "...##############...",
     "....#####..#####....", "........####........"]
  ]
  // The bear candidates for a face to match the bull's: one read as a pig,
  // the teddy with inner ears and a mouth, the grizzly (the default), and the
  // bull's twin with a short muzzle.
  readonly property var bearCandidates: [
    ["....................", ".........#####......", ".......##########...", "..###.############..",
     ".#.###.############.", "####.##############.", "###################.", ".##################.",
     "...################.", "....####.....#####..", "....####......####..", "....####......####..",
     "...#####.....#####..", "...................."],
    ["....................", "..###..........###..", ".#####........#####.", ".##.############.##.",
     ".##################.", "..################..", "..####.######.####..", ".##################.",
     ".#######....#######.", ".########..########.", ".#######.##.#######.", "..#######..#######..",
     "....############....", "......########......"],
    Cells.BEAR_SPRITE.slice(),
    ["....................", "..###..........###..", ".#####........#####.", ".##################.",
     ".##################.", "..####.######.####..", "..################..", "..################..",
     "...##############...", "....############....", "....############....", "....####....####....",
     ".....####..####.....", "......########......"]
  ]

  function isDefaultSprite(rows, standard) {
    return rows.join("|") === standard.join("|")
  }

  FileView { id: aaplFile; path: fixtureDir + "/aapl.json"; blockLoading: true }
  FileView { id: nestDayFile; path: fixtureDir + "/nest-2026-09-11-day-prepost.json"; blockLoading: true }
  FileView { id: spyDayFile; path: fixtureDir + "/spy-2026-09-11-day-prepost.json"; blockLoading: true }
  FileView { id: aaplDownFile; path: fixtureDir + "/aapl-2026-09-04-day-prepost.json"; blockLoading: true }
  FileView { id: shopFile; path: fixtureDir + "/shop-to.json"; blockLoading: true }
  FileView { id: searchFile; path: fixtureDir + "/search.json"; blockLoading: true }
  FileView { id: vfiaxFile; path: fixtureDir + "/search-vfiax.json"; blockLoading: true }
  FileView { id: eurusdFile; path: fixtureDir + "/search-eurusd.json"; blockLoading: true }
  FileView { id: historyFile; path: fixtureDir + "/history/aapl-1y.json"; blockLoading: true }
  FileView { id: nestWeekFile; path: fixtureDir + "/history/nest-5d.json"; blockLoading: true }
  FileView { id: nestMonthFile; path: fixtureDir + "/history/nest-1mo.json"; blockLoading: true }
  FileView { id: shortFile; path: fixtureDir + "/history/fab-max.json"; blockLoading: true }
  FileView { id: weeklyFile; path: fixtureDir + "/history/aapl-5y.json"; blockLoading: true }
  FileView { id: calendarFile; path: calendarPath; blockLoading: true }
  FileView { id: watchlistFile; path: fixtureDir + "/list-22.json"; blockLoading: true }
  FileView { id: shopYearFile; path: fixtureDir + "/history/shop-to-1y.json"; blockLoading: true }

  QtObject {
    id: stub
    property var symbols: ["AAPL", "SHOP.TO"]
    property bool settingsUnreadable: false
    // A save that didn't land (popup-notice-save-*), said again after a
    // click that still didn't (popup-notice-save-again-*).
    readonly property bool saveFailed: root.stateName.indexOf("popup-notice-save-") === 0
    // A change made while the file can't be read (popup-notice-file-edited-*).
    readonly property bool editsUnsaved: root.stateName.indexOf("popup-notice-file-edited-") === 0
    // A refresh the reader asked for, out (popup-refreshing-*).
    readonly property bool refreshing: root.stateName.indexOf("popup-refreshing-") === 0
    // Sounds on, their default, so the header's speaker shows its waves;
    // off for quiet-.
    property bool soundsOn: !root.quiet
    property var shown: ["AAPL", "SHOP.TO"]
    property var library: symbols
    property string listName: ""
    property var lists: [{ name: "", label: "All", count: symbols.length, symbols: symbols }]
    property var quotes: ({})
    property var entries: ({})
    property var calendars: null
    property string featuredSymbol: "AAPL"
    property string order: "pct"
    property bool reversed: false
    property string changeMode: "pct"
    property int now: root.now
    property var owed: ({})
    property string range: root.shownRange
    // The history on show, keyed to its symbol: a held chart's stays its own
    // while the next symbol's is on its way.
    property string historySymbol: ""
    readonly property var histories: root.shownHistoryEntry ? ({ [(historySymbol || featuredSymbol) + "|" + range]: root.shownHistoryEntry }) : ({})
    readonly property string hero: previewSymbol || featuredSymbol
    readonly property var fundamentals: root.savedFigures[hero]
      ? ({ [hero]: { status: "ok", figures: root.savedFigures[hero] } }) : ({})
    readonly property var rates: root.savedRates
    property var arriving: []
    property var lastRemoval: null
    // Robinhood's prints, and its word on which listings it trades all day,
    // answered, on the overnight states only.
    property var nights: ({})
    property var allDay: ({})
    readonly property var view: ({ featured: featuredSymbol, range: range, list: listName, listKey: "=" + listName,
      order: order, reversed: reversed, rows: symbols, shown: shown, library: library,
      chart: Chart.viewChart(featuredSymbol, range, quotes, entries, histories, nights, allDay, root.overnight ? calendars : null) })
    // The search's choice on the hero, unadded (popup-search-preview-*).
    property string previewSymbol: ""
    readonly property var previewView: previewSymbol ? Object.assign({}, view, { featured: previewSymbol,
      chart: Chart.viewChart(previewSymbol, range, quotes, entries, histories) }) : view
    readonly property var previewEntries: ({})
    property var previewSurface: null
    function preview(surface, symbol) {
      previewSurface = symbol ? surface : null
      previewSymbol = symbol
    }
    property bool retro: root.stateName !== "smooth" && root.stateName.indexOf("-smooth") < 0
      && root.stateName !== "popup-history-failed" && root.stateName !== "popup-history-loading"
    property color foreground: Commons.Color.popups.text
    property color upColor: root.trendColors.upOn(root.groundColor)
    property color downColor: root.trendColors.downOn(root.groundColor)
    // The shell's own family, so renders measure what the owner sees.
    property string fontFamily: Style.font.family
    function persist(values) {}
    function setRange(value) { root.shownRange = value }
    function screensClear() { return true }
    function surfaceShown(surface, open) {}
    function rowsSeen(surface, symbols) {}
    function feature(symbol) { featuredSymbol = symbol }
    function removeSymbol(symbol) {}
    function setManualOrder(symbols) {}
    function addSymbol(symbol) {}
    function setOrder(value) { order = value }
    function switchList(name) {}
    function createList(name) { return "" }
  }
  // The version watch, as a render sets it.
  QtObject {
    id: updates
    property string newVersion: ""
    property string releasedVersion: ""
    property string runningVersion: "1.0.0"
  }

  function load() {
    var aapl = Quote.parseChart(JSON.parse(aaplFile.text()))
    var nestDay = Quote.parseChart(JSON.parse(nestDayFile.text()))
    var spyDay = Quote.parseChart(JSON.parse(spyDayFile.text()))
    var shop = Quote.parseChart(JSON.parse(shopFile.text()))
    var history = History.parseHistory(JSON.parse(historyFile.text()), "1Y")
    var nestJson = JSON.parse(nestWeekFile.text())
    // A day cut from the week's answer, saved that Friday evening: its
    // current period is that day, its trading periods the week's.
    var nestCut = JSON.parse(nestWeekFile.text())
    delete nestCut.chart.result[0].meta.tradingPeriods
    var nest = Quote.parseChart(nestCut)
    nest.prevClose = nestJson.chart.result[0].meta.previousClose
    nest.points = nest.points.filter(function(point) { return point.t >= nest.session.pre.start })
    var nestWeek = History.parseHistory(nestJson, "1W")
    var nestMonth = History.parseHistory(JSON.parse(nestMonthFile.text()), "1M")
    var weekly = History.parseHistory(JSON.parse(weeklyFile.text()), "5Y")
    var shortHistory = History.parseHistory(JSON.parse(shortFile.text()), "All")
    root.savedFigures = { AAPL: root.figures("aapl"), NEST: root.figures("nest"), "SHOP.TO": root.figures("shop-to"),
      "7203.T": root.figures("7203-t"), "SHEL.L": root.figures("shel-l") }
    root.savedRates = { USDCAD: root.rate("USDCAD"), USDGBP: root.rate("USDGBP") }
    try { stub.calendars = JSON.parse(calendarFile.text()) } catch (e) { stub.calendars = null }
    if (root.pillSheet) {
      root.pillQuote = nestDay
      root.now = nestDay.marketTime + 120
      return
    }
    if (root.loadingKind) {
      var held = { aapl: "AAPL", "shel-l": "SHEL.L", "btc-usd": "BTC-USD" }[root.loadingKind[1]]
      var dayOf = function(name) {
        var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', root)
        view.path = fixtureDir + "/" + name + ".json"
        var json = JSON.parse(view.text())
        view.destroy()
        return json
      }
      stub.symbols = ["AAPL", "SHEL.L", "BTC-USD"]
      stub.shown = stub.symbols.slice()
      stub.quotes = { AAPL: aapl, "SHEL.L": Quote.parseChart(dayOf("shel-l-day")), "BTC-USD": Quote.parseChart(dayOf("btc-usd-day")) }
      root.now = stub.quotes[held].marketTime + 120
      stub.entries = { AAPL: { status: "ok", receivedAt: root.now }, "SHEL.L": { status: "ok", receivedAt: root.now }, "BTC-USD": { status: "ok", receivedAt: root.now } }
      stub.featuredSymbol = held
      root.shownRange = "1Y"
      root.shownHistoryEntry = { status: "ok", history: History.parseHistory(dayOf("history/" + root.loadingKind[1] + "-1y"), "1Y"), receivedAt: root.now }
      root.loadingNext = stub.symbols[(stub.symbols.indexOf(held) + 1) % stub.symbols.length]
      return
    }
    if (root.coldState === "loading") {
      stub.quotes = {}
      stub.entries = {}
    } else if (root.coldState === "failed") {
      stub.quotes = {}
      stub.entries = { AAPL: { status: "failed" }, "SHOP.TO": { status: "failed" } }
    } else if (root.stateName === "aged") {
      stub.quotes = { AAPL: aapl, "SHOP.TO": shop }
      stub.entries = { AAPL: { status: "ok", receivedAt: root.now - 1000 }, "SHOP.TO": { status: "ok", receivedAt: root.now - 1000 } }
    } else if (root.stateName.indexOf("fetch-saved-") === 0) {
      // Quotes kept from an earlier session, two days on: each says its day.
      root.now = root.now + 2 * 86400
      stub.quotes = { AAPL: aapl, "SHOP.TO": shop }
      stub.entries = { AAPL: { status: "saved", receivedAt: aapl.marketTime }, "SHOP.TO": { status: "saved", receivedAt: shop.marketTime } }
    } else if (root.stateName.indexOf("fetch-overdue-") === 0) {
      // A refresh asked for 91 s ago with no answer: a refusal, or no network.
      stub.quotes = { AAPL: aapl, "SHOP.TO": shop }
      stub.entries = { AAPL: { status: "ok", receivedAt: root.now - 300 }, "SHOP.TO": { status: "ok", receivedAt: root.now - 300 } }
      stub.owed = { AAPL: root.now - 91, "SHOP.TO": root.now - 91 }
    } else {
      stub.quotes = { AAPL: aapl, "SHOP.TO": shop }
      stub.entries = { AAPL: { status: "ok", receivedAt: root.now }, "SHOP.TO": { status: "ok", receivedAt: root.now } }
    }

    if (root.nestDayState) {
      stub.symbols = ["NEST", "AAPL"]
      stub.shown = ["NEST", "AAPL"]
      stub.quotes = { NEST: nestDay, AAPL: aapl }
      stub.entries = { NEST: { status: "ok", receivedAt: root.now }, AAPL: { status: "ok", receivedAt: root.now } }
      stub.featuredSymbol = "NEST"
    }

    if (root.fill) {
      var days = { up: ["SPY", spyDay], down: ["AAPL", Quote.parseChart(JSON.parse(aaplDownFile.text()))], cross: ["NEST", nestDay] }
      var fillQuotes = {}, fillEntries = {}
      ;["up", "down", "cross"].forEach(function(day) {
        fillQuotes[days[day][0]] = days[day][1]
      })
      var featuredDay = days[root.fill.day][1]
      root.now = featuredDay.marketTime + 120
      Object.keys(fillQuotes).forEach(function(s) { fillEntries[s] = { status: "ok", receivedAt: root.now } })
      stub.symbols = ["SPY", "AAPL", "NEST"]
      stub.shown = stub.symbols.slice()
      stub.quotes = fillQuotes
      stub.entries = fillEntries
      stub.order = "manual"
      stub.featuredSymbol = days[root.fill.day][0]
      if (root.themeState) root.pillQuote = nestDay
    }

    if (root.overnight) {
      var live = root.overnight.moment === "live"
      var folder = root.overnight.folder || (live ? "live-2026-10-05" : (root.overnight.sweep ? "listings-" : "") + root.overnight.moment)
      var saved = function(name) {
        var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', root)
        view.path = fixtureDir + "/moments/" + folder + "/" + name + ".json"
        var text = String(view.text())
        view.destroy()
        return text
      }
      var read = function(name) { return JSON.parse(saved(name)) }
      // The look sweep adds a coin under a cent, Toronto, a six-figure
      // price, and a long symbol at the moments that saved them (8 October,
      // and Saturday 3 October), listing the featured one first so its row
      // shows.
      var file = function(s) { return s.toLowerCase().replace(/^\^/, "") }
      var looked = root.overnight.sweep && saved(file("SHIB-USD")) !== ""
      // A saved moment's folder names its own listings: each answer's symbol.
      var named = root.overnight.saved
        ? root.overnight.saved.map(function(f) { return read(f).chart.result[0].meta.symbol }) : null
      var featured = named ? named[root.overnight.saved.indexOf(root.overnight.file)] : root.overnight.symbol
      if (named && !featured) console.log("FAIL no saved answer " + root.overnight.file + ".json in moments/" + folder)
      var listed = named ? named : root.overnight.listed ? root.overnight.listed
        : looked ? ["NEST", "KILN", "SPY", "BOLT", "^GSPC", "BTC-USD", "SHIB-USD", "SHEL.L", "7203.T", "RY.TO", "BRK-A", "BRK-B"]
        : root.overnight.sweep ? ["NEST", "KILN", "SPY", "BOLT", "^GSPC", "BTC-USD", "SHEL.L", "7203.T"]
        : live ? ["NEST", "EZ", "TOY"] : root.overnight.power ? ["JPM", "PLUG", "AITX", "CKX", "CVR", "LUMN"]
        : root.overnight.dated ? ["NEST"] : ["NEST", "SILK", "REED"]
      if (looked || root.overnight.power || named) listed = [featured].concat(listed.filter(function(s) { return s !== featured }))
      var quotes = {}, entries = {}, nights = {}, allDay = {}
      // Read as the feeds read them: the US listings in cents from $1.
      listed.forEach(function(s) {
        quotes[s] = Quote.parseChart(read(file(s)), Market.centExchanges(stub.calendars))
        if (root.overnight.lastTrade) quotes[s] = Object.assign({}, quotes[s], { price: null, marketTime: null })
      })
      // The US listings: Robinhood's word on which it trades all day, saved
      // with the sweep's moments, and every one at the moments before them;
      // at a saved moment's folder, those Stonks asks Robinhood about, in
      // the order its saved answer was asked in, since an answer's results
      // pair with the symbols asked by place (Overnight.parseOvernight).
      var day = named ? saved("robinhood-day") : null
      var instruments = named ? saved("robinhood-instruments") : null
      var asked = day ? JSON.parse(day).results.map(function(r) { return r.symbol }) : []
      var place = function(s) { var i = asked.indexOf(Overnight.robinhoodSymbol(s)); return i < 0 ? asked.length : i }
      var us = named ? listed.filter(function(s) { return Overnight.hasOvernight(quotes[s], stub.calendars) })
          .sort(function(a, b) { return place(a) - place(b) })
        : looked ? ["NEST", "KILN", "SPY", "BOLT", "BRK-A", "BRK-B"]
        : root.overnight.sweep ? ["NEST", "KILN", "SPY", "BOLT"] : listed
      // A saved moment missing either of Robinhood's answers, a fetch that
      // failed, replays as Stonks stands without it: no word on all-day
      // trading, or no night's prints.
      var tradable = named ? (instruments ? Overnight.parseAllDay(JSON.parse(instruments), us) : null)
        : root.overnight.sweep ? Overnight.parseAllDay(read("robinhood-instruments"), us) : root.overnight.power ? {} : null
      // What a surface opening at the moment holds: Robinhood's span=day
      // answer.
      var answer = named ? (day ? Overnight.parseOvernight(JSON.parse(day), us) : null)
        : root.overnight.power ? {} : Overnight.parseOvernight(read("robinhood-day"), us)
      us.forEach(function(s) {
        if (named && !tradable) return
        allDay[s] = { status: "ok", allDay: tradable ? tradable[s] : true, at: 0 }
        if (allDay[s].allDay && (answer || !named)) nights[s] = Object.assign({ status: "ok" }, answer[s])
      })
      // The moment each was saved at: Friday 2 October 13:42, Thursday
      // 1 October 23:00, Sunday 27 September 22:30, Monday 5 October 00:36;
      // a dated one at its name, New York time.
      var dated = root.overnight.dated ? /^(.{10})-(\d\d)(\d\d)$/.exec(root.overnight.moment) : null
      root.now = dated ? Market.epochAt(Overnight.overnightMarket(stub.calendars), dated[1], dated[2] + ":" + dated[3])
        : { day: 1790962920, night: 1790910000, sunday: 1790562600, live: 1791175013 }[root.overnight.moment]
      if (root.overnight.own) {
        var own = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', root)
        own.path = fixtureDir + "/" + root.overnight.own.file + ".json"
        quotes[root.overnight.symbol] = Quote.parseChart(JSON.parse(own.text()))
        own.destroy()
        root.now = root.overnight.own.at
      }
      listed.forEach(function(s) { entries[s] = { status: "ok", receivedAt: root.now } })
      if (root.overnight.month || root.overnight.quarter) {
        var range = root.overnight.month ? "1M" : "3M"
        root.shownRange = range
        root.shownHistoryEntry = { status: "ok", history: History.parseHistory(read(root.overnight.symbol.toLowerCase() + "-" + range.toLowerCase()), range), receivedAt: root.now }
      }
      stub.symbols = listed
      stub.shown = listed.slice()
      stub.quotes = quotes
      stub.entries = entries
      stub.nights = nights
      stub.allDay = allDay
      stub.order = "manual"
      stub.featuredSymbol = featured
      return
    }

    if (root.closure) {
      var closed = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', root)
      closed.path = fixtureDir + "/" + root.closure.file + ".json"
      var closedQuote = Quote.parseChart(JSON.parse(closed.text()))
      closed.destroy()
      root.now = Market.epochAt(Market.calendarFor(stub.calendars, closedQuote), root.closure.date, "12:00")
      stub.symbols = [root.closure.symbol, "AAPL"]
      stub.shown = stub.symbols.slice()
      stub.quotes = { [root.closure.symbol]: closedQuote, AAPL: aapl }
      stub.entries = { [root.closure.symbol]: { status: "ok", receivedAt: root.now }, AAPL: { status: "ok", receivedAt: root.now } }
      stub.featuredSymbol = root.closure.symbol
      return
    }

    if (root.firstDay) {
      var saved = function(name) {
        var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', root)
        view.path = fixtureDir + "/first-day-2026-10-14/" + name + ".json"
        var json = JSON.parse(view.text())
        view.destroy()
        return json
      }
      var listed = { RGTI: "rgti", GOOG: "goog", "TD.TO": "td-to", "^N225": "n225", "ETH-USD": "eth-usd", SPY: "spy" }
      stub.symbols = Object.keys(listed)
      stub.shown = stub.symbols.slice()
      var dayQuotes = {}
      stub.symbols.forEach(function(symbol) { dayQuotes[symbol] = Quote.parseChart(saved(listed[symbol] + "-day")) })
      root.now = dayQuotes.RGTI.marketTime + 120
      var answered = {}
      stub.symbols.forEach(function(symbol) { answered[symbol] = { status: "ok", receivedAt: root.now } })
      stub.quotes = dayQuotes
      stub.entries = answered
      stub.featuredSymbol = "RGTI"
      if (root.firstDay.range === "1Y") {
        root.shownRange = "1Y"
        root.shownHistoryEntry = { status: "ok", history: History.parseHistory(saved("rgti-1y"), "1Y"), receivedAt: root.now }
      }
      return
    }

    if (root.bigList) {
      var fixture = JSON.parse(watchlistFile.text())
      // popup-52w-<look>: MZ's day reaches its 52-week high.
      if (root.stateName.indexOf("popup-52w-") === 0) {
        fixture.quotes.forEach(function(q) {
          var meta = q.response ? q.response.chart.result[0].meta : null
          if (meta && meta.symbol === "MZ") meta.fiftyTwoWeekHigh = meta.regularMarketDayHigh
        })
      }
      var names = []
      var loaded = {}
      var states = {}
      for (var n = 0; n < fixture.quotes.length; n++) {
        var entry = fixture.quotes[n]
        var chart = entry.response ? Quote.parseChart(entry.response) : null
        var name = chart ? chart.symbol : entry.symbol
        names.push(name)
        states[name] = entry.status
        if (chart) loaded[name] = chart
      }
      // The featured symbols carry a real day, pre- and post-market included.
      loaded.AAPL = aapl
      loaded.SPY = spyDay
      loaded["SHOP.TO"] = shop
      var featuredName = root.w22 ? { aapl: "AAPL", spy: "SPY", shop: "SHOP.TO", mz: "MZ" }[root.w22.symbol]
        : (root.stateName.indexOf("popup-price5-") === 0 ? "BRK-A" : "MZ")
      // popup-price4-solo-<look>: the day without its post-market prints, so
      // the strip under the price is empty.
      if (root.stateName.indexOf("-solo-") >= 0) {
        var day = loaded[featuredName]
        loaded[featuredName] = Object.assign({}, day, {
          points: day.points.filter(function(point) { return point.t < day.session.regular.end })
        })
      }
      root.now = loaded[featuredName].marketTime + 120
      var fresh = {}
      for (var e = 0; e < names.length; e++)
        fresh[names[e]] = { status: states[names[e]], receivedAt: states[names[e]] === "ok" ? root.now : 0 }
      stub.symbols = names
      stub.shown = names.slice()
      stub.quotes = loaded
      stub.entries = fresh
      stub.order = "manual"
      stub.featuredSymbol = featuredName
      // popup-rowlines-<look>: rows whose day crosses its previous close
      // (AAPL's pre-market under it, SHOP.TO over then under), for the row
      // line's two colours.
      if (root.stateName.indexOf("popup-rowlines-") === 0) {
        stub.symbols = ["AAPL", "SHOP.TO", "BRK-A", "TSLA", "SPY", "MZ"]
        stub.shown = stub.symbols.slice()
      }
      // popup-breadth-even-<look>: a list three up and three down, whose two
      // ends of the rule must be the same length and never meet.
      if (root.stateName.indexOf("popup-breadth-even-") === 0) {
        stub.library = stub.symbols.slice()
        stub.listName = "Even"
        stub.symbols = ["MZ", "BRK-A", "LONG", "MSFT", "TSLA", "AMZN"]
        stub.shown = stub.symbols.slice()
      }
      // <surface>-room-*: All of one, four, or five rows, or the empty
      // named list Growth beside All.
      if (root.room) {
        var lists = { one: ["AAPL"], four: ["AAPL", "NVDA", "MSFT", "SPY"], five: ["NVDA", "AAPL", "MSFT", "SPY", "TSLA"], growth: [] }
        if (root.room.list === "growth") {
          stub.library = stub.symbols.slice()
          stub.listName = "Growth"
        }
        stub.symbols = lists[root.room.list]
        stub.shown = stub.symbols.slice()
      }
      // The order word both ways: All by % change, the biggest gain first
      // and, reversed, the biggest loss first.
      if (root.orderState) {
        stub.order = "pct"
        stub.reversed = root.stateName.indexOf("-rises-") > 0
        stub.shown = Settings.sortedSymbols(stub.symbols, stub.quotes, stub.order, stub.reversed, stub.changeMode)
      }
      if (root.w22 && root.w22.range === "5y") {
        root.shownRange = "5Y"
        root.shownHistoryEntry = { status: "ok", history: weekly, receivedAt: root.now }
      } else if (root.w22 && root.w22.range === "1y") {
        root.shownRange = "1Y"
        root.shownHistoryEntry = { status: "ok", history: History.parseHistory(JSON.parse(shopYearFile.text()), "1Y"), receivedAt: root.now }
      }
      return
    }

    if (root.historyState) {
      // popup-history-1w-* and -1m-*: NEST on 15-minute and hourly bars, the
      // only ranges drawn from intraday history.
      if (root.nestState) {
        root.shownRange = root.stateName.indexOf("popup-history-1w-") === 0 ? "1W" : "1M"
        root.shownHistoryEntry = { status: "ok", history: root.shownRange === "1W" ? nestWeek : nestMonth, receivedAt: root.now }
        stub.symbols = ["NEST", "AAPL"]
        stub.shown = ["NEST", "AAPL"]
        stub.quotes = { NEST: nest, AAPL: aapl }
        stub.entries = { NEST: { status: "ok", receivedAt: root.now }, AAPL: { status: "ok", receivedAt: root.now } }
        stub.featuredSymbol = "NEST"
      } else if (root.stateName.indexOf("popup-history-all-") === 0) {
        root.shownRange = "All"
        root.shownHistoryEntry = { status: "ok", history: shortHistory, receivedAt: root.now }
        var fab = Object.assign({}, aapl, { symbol: "FAB", name: "Fable", price: 23.20, prevClose: 23.20 })
        stub.symbols = ["FAB", "AAPL"]
        stub.shown = ["FAB", "AAPL"]
        stub.quotes = { FAB: fab, AAPL: aapl }
        stub.entries = { FAB: { status: "ok", receivedAt: root.now }, AAPL: { status: "ok", receivedAt: root.now } }
        stub.featuredSymbol = "FAB"
      } else if (root.stateName === "history-sparse") {
        root.shownRange = "All"
        root.shownHistoryEntry = { status: "ok", receivedAt: root.now, history: {
          symbol: "AAPL", range: "All", interval: "1mo", currency: "USD", gmtoffset: -14400,
          baseline: 95, firstTradeDate: history.bars[0].t, bars: history.bars.slice(0, 5)
        } }
      } else if (root.stateName === "popup-history-loading") {
        // 1Y asked from the day on show (Component.onCompleted), its answer
        // not in yet.
        root.shownRange = "1D"
      } else if (root.stateName === "history-empty-loading") {
        // No answer yet.
        root.shownHistoryEntry = null
      } else if (root.stateName === "popup-history-failed") {
        // 1Y asked with the network gone: the range fails as every
        // listing's refresh has, the day stands in, and the header offers
        // the range's retry rather than saying Yahoo sends nothing.
        root.shownHistoryEntry = { status: "failed", history: null, receivedAt: root.now }
        stub.entries = { AAPL: { status: "failed", answeredAt: root.now, receivedAt: root.now - 300 },
          "SHOP.TO": { status: "failed", answeredAt: root.now, receivedAt: root.now - 300 } }
      } else if (root.stateName.indexOf("popup-history-unavailable-") === 0) {
        // A first fetch that failed: the day stands in, and the header
        // offers the retry.
        root.shownHistoryEntry = { status: "failed", history: null, receivedAt: root.now }
      } else {
        root.shownHistoryEntry = { status: "ok", history: history, receivedAt: root.now }
      }
    }
  }

  function searchField(item) {
    if (item.objectName === "searchField") return item
    for (var i = 0; i < item.children.length; i++) {
      var found = searchField(item.children[i])
      if (found) return found
    }
    return null
  }

  Component.onCompleted: {
    load()
    if (root.stateName === "popup-history-loading") root.shownRange = "1Y"
    // The next symbol asked for, past its quarter second: what is on show
    // for the held one dims as it rests (`ChartMotion.dimmed`).
    if (root.loadingNext) {
      stub.historySymbol = stub.featuredSymbol
      stub.featuredSymbol = root.loadingNext
      body.motion.dimmed = 1
    } else if (body.motion.loading) {
      // A chart still on its way dims a quarter second in, over 160 ms, and
      // the grab at 300 ms caught it partway, further in one run than the
      // next: it shows at rest, dimmed, so two renders of one tree match
      // (test/render-diff.sh).
      body.motion.dimmed = 1
    }
    if (root.searchState) {
      body.adding = true
      body.search.results = Search.parseSearch(JSON.parse(searchFile.text())).results
      body.search.searchText = "SHOP"
      body.search.resultsQuery = "SHOP"
      body.search.answer = "results"
      // popup-search-stale-*: SHOP's results under a newer query, dimmed;
      // -none-: an empty answer; -failed-: no answer at all.
      if (root.stateName.indexOf("-stale-") > 0) body.search.searchText = "SHOPI"
      // popup-search-preview-*: SHOP.TO, not in the list, chosen with the
      // arrows, so the hero shows it unadded beside the Add on its row.
      if (root.stateName.indexOf("-preview-") > 0) {
        stub.symbols = stub.symbols.filter(function(s) { return s !== "SHOP.TO" })
        stub.shown = stub.symbols.slice()
        root.now = stub.quotes["SHOP.TO"].marketTime + 120
        stub.entries = Object.assign({}, stub.entries, { "SHOP.TO": { status: "ok", receivedAt: root.now } })
        body.search.showResult(1)
      }
      // popup-search-show-*: SHOP.TO, already in the list, chosen: its
      // button and the field's hint say Show, in Add's slot.
      if (root.stateName.indexOf("-show-") > 0) {
        root.now = stub.quotes["SHOP.TO"].marketTime + 120
        stub.entries = Object.assign({}, stub.entries, { "SHOP.TO": { status: "ok", receivedAt: root.now } })
        body.search.showResult(1)
      }
      // popup-search-putback-*: SHOP.TO just removed, and search opened on
      // an empty field: its one result is the removal, chosen, PUT BACK, the
      // hero showing it.
      if (root.stateName.indexOf("-putback-") > 0) {
        stub.lastRemoval = { symbol: "SHOP.TO", before: { symbols: stub.symbols, lists: [] }, quote: stub.quotes["SHOP.TO"] }
        stub.symbols = stub.symbols.filter(function(s) { return s !== "SHOP.TO" })
        stub.shown = stub.symbols.slice()
        root.now = stub.quotes["SHOP.TO"].marketTime + 120
        stub.entries = Object.assign({}, stub.entries, { "SHOP.TO": { status: "ok", receivedAt: root.now } })
        body.search.searchText = ""
        body.search.showEmpty()
      }
      if (root.stateName.indexOf("-none-") > 0 || root.stateName.indexOf("-failed-") > 0) {
        body.search.results = []
        body.search.resultsQuery = "ZZZ"
        body.search.searchText = "ZZZ"
        body.search.answer = root.stateName.indexOf("-none-") > 0 ? "none" : "failed"
      }
      // popup-search-vfiax-*: Yahoo's answer holds a mutual fund alone;
      // -eurusd-: two indexes shown, a currency and futures left out. The
      // note has to fit the popup's width on one line. The currency is
      // Yahoo's top answer, so no result is chosen, as search's own landing
      // chooses (`SymbolSearch.land`).
      var leftOut = root.stateName.indexOf("-vfiax-") > 0 ? ["vfiax", vfiaxFile]
        : root.stateName.indexOf("-eurusd-") > 0 ? ["eurusd", eurusdFile] : null
      if (leftOut) {
        var answer = Search.parseSearch(JSON.parse(leftOut[1].text()))
        body.search.results = answer.results
        body.search.note = answer.note
        body.search.resultIndex = answer.topLeftOut ? -1 : 0
        body.search.resultsQuery = leftOut[0]
        body.search.searchText = leftOut[0]
        root.searchField(body.search).text = leftOut[0]
      }
    } else if (root.help) {
      // Manual order, so the sheet shows every entry it can; popup-help-sorted
      // shows a sorted order's instead, without J K and the drag.
      stub.order = root.help.sorted ? "pct" : "manual"
      body.showingHelp = true
    } else if (root.room) {
      // Search open: as it opens, or with an answer for what the field says.
      body.adding = true
      var moment = root.room.moment
      var saved = Search.parseSearch(JSON.parse(searchFile.text())).results
      // Yahoo's answer for "wrapped btc", 9 October 2026: long symbols.
      var coins = [["XBTC39577-USD", "OKX Wrapped BTC USD"], ["CBBTC32994-USD", "Coinbase Wrapped BTC USD"],
        ["KBTC33513-USD", "Kraken Wrapped Bitcoin USD"], ["WBTC-USD", "Wrapped Bitcoin USD"],
        ["CIRBTC-USD", "Circle Wrapped Bitcoin USD"]].map(function(c) { return { symbol: c[0], name: c[1], exchange: "CCC" } })
      var query = moment === "long" ? "wrapped btc" : moment === "none" ? "ZZZ" : moment === "failed" ? "OOPS" : "SHOP"
      if (moment !== "open") {
        body.search.results = moment === "long" ? coins : moment === "one" ? saved.slice(0, 1) : moment === "five" ? saved.slice(0, 5) : []
        body.search.searchText = query
        body.search.resultsQuery = query
        body.search.answer = moment === "none" ? "none" : moment === "failed" ? "failed" : "results"
        // The field says the query; the same text asks for nothing.
        root.searchField(body.search).text = query
      }
    } else if (/^(popup|window)-rowstates-/.test(root.stateName)) {
      // Featured, cursor, and a row that has not moved, side by side; the
      // cursor, put there as by the pointer, shows its remove button.
      // -featured- puts it on the featured row. The cursor a turn later,
      // once the rows show: set on no rows, it is let go.
      var onFeatured = root.stateName.indexOf("-featured-") > 0
      Qt.callLater(function() { body.watchlist.cursorSymbol = onFeatured ? stub.featuredSymbol : stub.shown[2] })
      var still = stub.quotes["SHOP.TO"]
      var quotes = Object.assign({}, stub.quotes)
      quotes["SHOP.TO"] = Object.assign({}, still, { prevClose: Quote.regularClose(still) })
      stub.quotes = quotes
    } else if (/^(popup|window)-note-/.test(root.stateName)) {
      // popup-note-<look>: a refusal. <popup|window>-note-sorted-<look>: J
      // refused in a sorted order.
      if (root.stateName.indexOf("-sorted-") > 0) {
        stub.order = "pct"
        Qt.callLater(function() {
          body.watchlist.cursorSymbol = stub.shown[2]
          body.moveSelected(1)
        })
      }
      else body.note = "Keep at least one symbol"
    } else if (/^(popup|window)-undo-/.test(root.stateName)) {
      // <popup|window>-undo-<look>: a removal offered back beside the add;
      // -named-: in a named list, the add's words the longer.
      if (root.stateName.indexOf("-named-") > 0) stub.listName = "My Watchlist"
      body.undoOffered = { symbol: "SHOP.TO" }
    } else if (root.stateName.indexOf("popup-hint-") === 0) {
      // The first open's footer: the hint's lines have to fit the popup's
      // width, above "+ Add a symbol".
      body.showFirstRunHint()
    } else if (root.stateName.indexOf("popup-notice-file-") === 0) {
      // The footer's notices have to fit the popup's width.
      stub.settingsUnreadable = true
    } else if (root.stateName.indexOf("popup-notice-update-") === 0) {
      updates.newVersion = "1.0.0"
    } else if (root.stateName.indexOf("popup-notice-save-again-") === 0) {
      body.note = "Still not saved · your disk may be full"
    } else if (/^(popup|window|min-window)-update-offer-/.test(root.stateName)) {
      // <surface>-update-offer-<look>: a newer Stonks offered at the bar's
      // right end; -named-: beside a named list's longer add, -long-: beside
      // one too long to say whole; -undo-: an undo in its place for the
      // undo's seconds.
      updates.releasedVersion = "1.1.0"
      if (root.stateName.indexOf("-named-") > 0) stub.listName = "My Watchlist"
      if (root.stateName.indexOf("-long-") > 0) stub.listName = "Semiconductors & AI infrastructure"
      if (root.stateName.indexOf("-undo-") > 0) body.undoOffered = { symbol: "SHOP.TO" }
    } else if (/^(popup|window|min-window)-lists-/.test(root.stateName)) {
      // popup-lists-<menu|naming|named|empty|long|manage|rename|confirm|symbol>-<look>,
      // window-lists-<manage|symbol>-<look>, and min-window-lists-<menu|manage|symbol>-<look>,
      // the window at its smallest: named watchlists over the 22-symbol
      // library, the featured symbol staying put on a switch. -menu12- and
      // -menu30-: the menu over 12 or 30 lists, the power-user walk's.
      var all = stub.symbols.slice()
      var named = /-(named|rowmenu)-/.test(root.stateName) ? { name: "My Watchlist", symbols: all.slice(0, 8) }
        : root.stateName.indexOf("-empty-") > 0 ? { name: "Growth", symbols: [] }
        : root.stateName.indexOf("-long-") > 0 ? { name: "Semiconductors & AI infrastructure", symbols: all.slice(3, 8) }
        : null
      var choice = function(name, symbols) { return { name: name, label: name || "All", count: symbols.length, symbols: symbols } }
      stub.lists = [choice("", all), choice("My Watchlist", all.slice(0, 8)), choice("Watching", all.slice(3, 8)),
        choice("Growth", []), choice("Wins", all.slice(10, 14)), choice("Losses", all.slice(14, 17))]
      if (named) {
        // All stays the library, so the popup keeps All's height on a list.
        stub.library = all
        stub.listName = named.name
        stub.order = "manual"
        stub.symbols = named.symbols
        stub.shown = named.symbols.slice()
      }
      var many = /-menu(\d+)-/.exec(root.stateName)
      for (var n = stub.lists.length; many && n < Number(many[1]); n++) stub.lists = stub.lists.concat([choice("List " + n, all.slice(n % 9, n % 9 + 3))])
      var child = function(name) { return body.children.filter(function(c) { return c.objectName === name })[0] }
      var find = function(item, name) {
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; i++) {
          var found = find(item.children[i], name)
          if (found) return found
        }
        return null
      }
      if (root.stateName.indexOf("-menu-") > 0 || many) {
        // The cursor's row under the menu's left edge, which must not show
        // its bar through: a turn later, once the rows show.
        Qt.callLater(function() { body.watchlist.cursorSymbol = stub.shown[2] })
        body.openListMenu()
      } else if (root.stateName.indexOf("-naming-") > 0) {
        // A new list's name typed into the menu's field.
        body.openListMenu()
        Qt.callLater(function() {
          var menu = child("listMenu")
          menu.startNaming()
          Qt.callLater(function() { find(menu, "listNameField").text = "Crypto" })
        })
      } else if (root.stateName.indexOf("-symbol-") > 0) {
        body.openSymbolLists(body.watchlist.cursorRow)
      } else if (/-rowmenu(all)?-/.test(root.stateName)) {
        // <popup|window>-lists-rowmenu-<look>: My Watchlist's second row,
        // in sight at every text size, right-clicked, which Wins holds too:
        // this list by its name, or all 3. popup-lists-rowmenuall-<look>:
        // that symbol's menu in All by Shift+X, its one line chosen. Opened
        // as the picture is taken, once the rows and a -size-N text size
        // have landed: the menu stands where it opens, and a later size
        // closes it.
        var held = all[1]
        stub.lists = stub.lists.map(function(list) { return list.name === "Wins" ? choice("Wins", list.symbols.concat([held])) : list })
        if (!named) {
          stub.order = "manual"
          stub.shown = all.slice()
        }
        root.beforeGrab = function() {
          var row = body.watchlist.rowItem(held)
          body.openRowMenu(held, named ? row.mapToItem(null, Style.space(60), row.height / 2) : null)
        }
      } else if (/-(manage|rename|confirm)-/.test(root.stateName)) {
        body.openManageLists()
        // After the view opens on its first named list.
        Qt.callLater(function() {
          var manage = child("manageLists")
          if (root.stateName.indexOf("-confirm-") > 0) manage.askDelete(4)
          if (root.stateName.indexOf("-rename-") > 0) {
            manage.startRenaming(2)
            Qt.callLater(function() {
              find(manage, "renameField").text = "wins"
              manage.problem = "wins already exists"
            })
          }
        })
      }
    } else if (root.stateName === "history-scrub") {
      body.motion.scrubT = root.shownHistoryEntry.history.bars[125].t
    } else if (/^popup-history-1y-crossed(low)?-/.test(root.stateName)) {
      // A scrub whose line runs through where the high's date rests, or
      // the low's (-crossedlow-): the whole mark stands clear of it.
      var low = root.stateName.indexOf("-crossedlow-") > 0
      var marked = root.shownHistoryEntry.history.bars
      body.motion.scrubT = marked[Math.round(body.rangeMarks[low ? "low" : "high"].x * (marked.length - 1)) + (low ? 55 : -4)].t
    } else if (root.overnight && root.overnight.scrub && root.overnight.month) {
      var bars = root.shownHistoryEntry.history.bars
      body.motion.scrubT = bars[Math.floor(bars.length / 2)].t
    } else if (root.overnight && root.overnight.scrub) {
      var day = body.featuredDay.points
      body.motion.scrubT = day[day.length - 1].t
    }
    if (root.shareScrub) {
      var shown = body.historyShown ? body.history.bars : body.featuredDay.points
      body.motion.scrubT = shown[Math.floor(shown.length / 2)].t
    }
    body.cameraLit = root.lit
  }

  // The camera, for share-of-*: the screenshot saved as the render, its
  // words in the log, nothing handed on.
  QtObject {
    id: shareCamera
    property bool busy: false
    function shoot(item, symbol, taken, done) {
      console.log("SHARE " + symbol)
      return item.grabToImage(function(result) {
        taken()
        result.saveToFile(root.outPath)
        done(0)
        console.log("SHARE footer | " + body.note)
        root.finish()
      }, Qt.size(item.width, item.height))
    }
  }

  FloatingWindow {
    id: renderWindow
    visible: true
    color: root.groundColor
    // The larger text size lands after the window has taken its size, so
    // the large sheet is given room for its seven rows, and a -size-N state
    // is given the widths Style.space gives the surfaces at size N: the
    // popup's 480 and the smallest window's 560 grow with the text, and the
    // window is 720 or its smallest, whichever is wider.
    implicitWidth: root.anchorState ? 1000 : root.pillSheet ? Math.max(520, pillColumn.implicitWidth + 48) : root.themeState ? 480 + 410 : root.sheet ? 1000
      : (root.windowWidth ? root.windowWidth : (root.smallest ? Math.round(560 * root.sizeScale)
        : (root.popup ? Math.round(480 * root.sizeScale) : Math.max(720, Math.round(560 * root.sizeScale)))))
    implicitHeight: root.anchorState ? body.fittedHeight(body.chromeHeight + 6 * body.rowPitch - body.rowGap) + content.inset * 2 + 56
      : root.stateName === "pill-sheet-large" ? 720 : root.pillSheet ? pillColumn.implicitHeight + 40 : root.sheet ? 460
      : root.themeState ? Math.max(body.fittedHeight(body.chromeHeight + 3 * body.rowPitch - body.rowGap) + content.inset * 2, pillColumn.implicitHeight + 40)
      : (root.windowWidth ? 850
        : (root.smallest ? body.smallestHeight
          : (root.popup ? body.fittedHeight(body.chromeHeight + 6 * body.rowPitch - body.rowGap) + content.inset * 2
            : (root.help && root.help.window ? 520 : 760))))

    Rectangle {
      id: frame
      anchors.fill: parent
      color: root.groundColor

      // The origins came from the real Panel/HeldAnchor/KeyboardPanel in
      // popup-anchor.qml, unmapped on Wayland. This scene paints them.
      Rectangle {
        visible: !!root.anchorState
        width: parent.width
        height: 32
        color: root.barGround
        QtObject {
          id: anchorShell
          function serviceFor() { return {service: stub, trendColors: root.trendColors} }
        }
        PluginBarApi { id: anchorApi; pluginId: "grvc.stonks"; moduleName: "grvc.stonks"; shell: anchorShell }
        BarWidget {
          id: anchorPill
          visible: !!root.anchorState
          x: root.anchorPose ? root.anchorPose.pillX : 0
          width: root.anchorPose ? root.anchorPose.pillWidth : 150
          height: parent.height
          bar: anchorApi
          settings: ({id: "grvc.stonks", barStyle: "text"})
        }
      }
      HeldAnchor { id: anchorProbe; pill: anchorPill }
      BorderSurface {
        visible: !!root.anchorState
        x: content.x - content.inset
        y: content.y - content.inset
        width: content.width + 2 * content.inset
        height: content.height + 2 * content.inset
        color: root.groundColor
        borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius
      }

      // The popup's body as the card holds it: inset by the card's border and
      // padding (`KeyboardPanel`'s), its own margins none, in a box that
      // clips it at its edges (`Panel.qml`'s key catcher), so what draws past
      // the body is cut here as on screen. The window's body has its own
      // margins.
      Item {
        id: content
        readonly property int inset: root.popup ? Style.spacing.popupPadding
          + Border.left(Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))) : 0
        clip: root.popup
        visible: !root.sheet && !root.pillSheet
        x: root.anchorPose ? root.anchorPose.x + inset : inset
        y: root.anchorPose ? root.anchorPose.y + inset : inset
        width: (root.anchorState || root.themeState ? 480 : parent.width) - inset * 2
        height: root.anchorState ? parent.height - y - inset : root.themeState ? body.fittedHeight(body.chromeHeight + 3 * body.rowPitch - body.rowGap) : parent.height - inset * 2

        StonksBody {
          id: body
          // As App.qml draws it: past 720 the body keeps that width, centred.
          // The gallery's popup is at the left, the pills beside it.
          width: root.themeState ? parent.width : Math.min(parent.width, Style.space(720))
          height: parent.height
          x: (parent.width - width) / 2
          service: stub
          updates: updates
          foreground: stub.foreground
          upColor: stub.upColor
          downColor: stub.downColor
          fontFamily: stub.fontFamily
          surfaceOpen: true
          headerWhenMissing: root.coldState === "loading" ? "Loading" : "No data"
          switchesPanels: root.popup
          margins: root.popup ? 0 : Style.space(16)
          chartHeight: root.popup ? Style.space(190) : Style.space(220)
          minChartHeight: root.popup ? 0 : Style.space(136)
          ground: root.groundColor
        }
      }

      Column {
        id: pillColumn
        visible: root.pillSheet || root.themeState
        x: root.themeState ? 480 + 8 : 24
        y: 20
        spacing: 8

        Repeater {
          // Every form in each look, the icon on a down day, an up one, a
          // flat one, before the first quote, and after a first fetch that
          // failed, then the pill in the right section with no form picked
          // there, where it is its icon, down and up.
          model: {
            if (root.themeState) {
              var retroLook = root.stateName.indexOf("theme-retro-") === 0
              return ["sparkline", "arrow", "text", "icon"].map(function(style) { return { style: style, retro: retroLook, compact: true, day: "down" } })
                .concat([{ style: "text", retro: retroLook, day: "up", compact: true }, { style: "icon", retro: retroLook, day: "up", compact: true }])
            }
            if (!root.pillSheet) return []
            var rows = []
            for (var look = 0; look < 2; look++) {
              var retro = look === 1
              ;["sparkline", "arrow", "text", "icon"].forEach(function(style) { rows.push({ style: style, retro: retro, day: "down" }) })
              ;["up", "flat", "waiting", "failed", "refresh failed"].forEach(function(day) { rows.push({ style: "icon", retro: retro, day: day }) })
              // The text form's row puts the stacked form on the side bar:
              // after a failed refresh, as tall as the fresh one above.
              rows.push({ style: "text", retro: retro, day: "refresh failed" })
            }
            var right = [{ style: "sparkline", retro: false, right: true, day: "down" }, { style: "sparkline", retro: true, right: true, day: "down" },
              { style: "sparkline", retro: false, right: true, day: "up" }, { style: "sparkline", retro: true, right: true, day: "up" }]
            // At the larger size, the smooth look's rows fill the screen, the
            // failed refresh's stacked row left out.
            return root.stateName === "pill-sheet-large" ? rows.filter(function(r) { return !r.retro && !(r.style === "text" && r.day !== "down") })
              .concat(right.filter(function(r) { return !r.retro })) : rows.concat(right)
          }

          Row {
            id: pillRow
            required property var modelData
            spacing: 16

            Text {
              width: pillRow.modelData.compact ? 80 : 170
              anchors.verticalCenter: parent.verticalCenter
              text: (pillRow.modelData.compact ? "" : (pillRow.modelData.retro ? "RETRO" : "SMOOTH") + " · ") + (pillRow.modelData.right ? "RIGHT SECTION" : pillRow.modelData.style.toUpperCase())
                + (pillRow.modelData.style === "icon" || pillRow.modelData.right || pillRow.modelData.day !== "down" ? " · " + pillRow.modelData.day.toUpperCase() : "")
              color: Commons.Color.muted
              font.family: Style.font.family
              font.pixelSize: 10
              font.bold: true
            }

            // A strip of bar at the bar's height, the real pill on it, fed
            // by a service stub of its own.
            Rectangle {
              id: pillCell
              width: 230
              height: Style.bar.sizeHorizontal
              anchors.verticalCenter: parent.verticalCenter
              color: root.barGround

              QtObject {
                id: pillService
                property string featuredSymbol: "NEST"
                property var quotes: ({ NEST: root.pillQuoteFor(pillRow.modelData.day === "refresh failed" ? "down" : pillRow.modelData.day) })
                property var entries: ({ NEST: { status: pillRow.modelData.day === "failed" || pillRow.modelData.day === "refresh failed" ? "failed"
                  : pillRow.modelData.day === "waiting" ? "pending" : "ok", receivedAt: root.now } })
                property string changeMode: "pct"
                property bool retro: pillRow.modelData.retro
                property int now: root.now
                property var owed: ({})
              }
              QtObject {
                id: pillShell
                function serviceFor() { return { service: pillService, trendColors: root.trendColors } }
              }
              PluginBarApi {
                id: pillApi
                pluginId: "grvc.stonks"
                moduleName: "grvc.stonks"
                shell: pillShell
                // The bar mirrors these onto the facade; the render sets them.
                foreground: Commons.Color.bar.text
                barForeground: Commons.Color.bar.text
                fontFamily: Style.font.family
                barSize: Style.bar.sizeHorizontal
                layoutConfig: pillRow.modelData.right ? { left: [], center: [], right: [{ id: "grvc.stonks" }] } : ({})
              }
              BarWidget {
                anchors.verticalCenter: parent.verticalCenter
                x: pillRow.modelData.right ? parent.width - width - 8 : 0
                width: implicitWidth
                height: parent.height
                bar: pillApi
                settings: ({ id: "grvc.stonks", barStyle: pillRow.modelData.style })
              }
              // An Omarchy bar icon beside it, Bluetooth's, as the right
              // section draws its icons: what the animal is sized against.
              BarIconButton {
                visible: pillRow.modelData.right === true
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - 8 - 2 * Style.bar.iconSlot
                height: parent.height
                bar: pillApi
                text: "\uDB80\uDCAF"
              }
            }

            // The same pill on a strip of vertical bar: the animal beside the
            // icon form, the symbol over its change beside the others. The
            // strip clips to the bar's width, as the shell's bar surface does.
            Rectangle {
              width: Style.bar.sizeVertical
              height: verticalPill.implicitHeight
              anchors.verticalCenter: parent.verticalCenter
              color: root.barGround
              clip: true

              PluginBarApi {
                id: verticalApi
                pluginId: "grvc.stonks"
                moduleName: "grvc.stonks"
                shell: pillShell
                vertical: true
                foreground: Commons.Color.bar.text
                barForeground: Commons.Color.bar.text
                fontFamily: Style.font.family
                barSize: Style.bar.sizeVertical
                layoutConfig: pillApi.layoutConfig
              }
              BarWidget {
                id: verticalPill
                anchors.centerIn: parent
                width: parent.width
                height: implicitHeight
                bar: verticalApi
                settings: ({ id: "grvc.stonks", barStyleVertical: pillRow.modelData.style === "icon" ? "icon" : "stacked" })
              }
            }
          }
        }
      }

      Column {
        visible: root.sheet
        x: 24
        y: 20
        spacing: 16

        Repeater {
          model: [
            { title: "BULL", color: "#8fc08a", sprites: root.bullCandidates, standard: Cells.BULL_SPRITE },
            { title: "BEAR", color: "#e05a7a", sprites: root.bearCandidates, standard: Cells.BEAR_SPRITE }
          ]

          Column {
            id: family
            required property var modelData
            spacing: 8

            Row {
              spacing: 32
              Repeater {
                model: family.modelData.sprites
                Column {
                  id: candidate
                  required property var modelData
                  required property int index
                  spacing: 6
                  Text {
                    text: family.modelData.title + " " + (candidate.index + 1)
                      + (root.isDefaultSprite(candidate.modelData, family.modelData.standard) ? "  DEFAULT" : "")
                    color: "#8a8d8d"
                    font.family: Style.font.family
                    font.pixelSize: 10
                    font.bold: true
                  }
                  Row {
                    spacing: 16
                    PixelSprite { width: 40; height: 28; pixels: Cells.spritePixels(candidate.modelData); color: family.modelData.color }
                    PixelSprite { width: 80; height: 56; pixels: Cells.spritePixels(candidate.modelData); color: family.modelData.color }
                  }
                }
              }
            }

            Row {
              spacing: 32
              Repeater {
                model: family.modelData.sprites
                PixelSprite {
                  required property var modelData
                  width: 160
                  height: 112
                  pixels: Cells.spritePixels(modelData)
                  color: family.modelData.color
                }
              }
            }
          }
        }
      }
    }

    // A still state's picture, 300 ms in, once its window has laid out and
    // drawn: nothing in the shell says when that is done.
    Timer {
      interval: 300
      running: !root.interactivePicture
      onTriggered: {
        if (root.shareOf) {
          body.camera = shareCamera
          body.takeScreenshot()
          return
        }
        if (root.beforeGrab) root.beforeGrab()
        frame.grabToImage(function(result) {
          result.saveToFile(root.outPath)
          root.finish()
        })
      }
    }
  }

  Steps {
    name: "ReviewPictures"
    when: root.interactivePicture && renderWindow.visible
    // Failed QtTest assertions still leave through the quiescent exit.
    function cleanupTestCase() { root.finish() }

    function one(name) { return root.findAll(body, name)[0] }

    function test_picture() {
      if (root.motionPose) {
        waitForRendering(body)
        var pose = root.motionPose[1]
        var rows = body.watchlist
        var member = rows.displayedSymbols[2]
        var row = rows.rowItem(member)
        // Fixed, paused poses make the render diff repeatable. The existing
        // motion harness judges the transitions; these show their ink.
        if (pose === "join") { row.join(); row.pause(); row.opacity = 0.5; row.reveal = 0.5 }
        else if (pose === "crossing") { row.carry(rows.rowPitch * 1.5); row.pause(); row.shift = -rows.rowPitch * 1.5 }
        else if (pose === "dragwheel") {
          stub.order = "manual"
          rows.beginDrag(member, 2 * rows.rowPitch + 10)
          rows.contentY = rows.rowPitch
        } else if (pose === "scroll") {
          rows.takeOver()
          rows.contentY = rows.rowPitch / 2
        } else if (pose === "endremove") {
          rows.contentY = rows.contentHeight - rows.height
          var removed = stub.shown[stub.shown.length - 2]
          stub.symbols = stub.symbols.filter(function(symbol) { return symbol !== removed })
          stub.shown = stub.shown.filter(function(symbol) { return symbol !== removed })
          within(2000, function() { return !rows.rowItem(removed) && stub.shown.every(function(symbol) { return rows.rowResting(symbol) }) })
        } else if (pose === "notefade") {
          // A refusal's note, half faded.
          stub.order = "pct"
          rows.cursorSymbol = member
          body.moveSelected(1)
          if (body.note !== "Switch to manual order to move rows") {
            console.error("FAIL fading refusal state contains the move refusal")
            root.failures++
          }
          body.noteShown = 0.5
        } else if (pose === "breadth") {
          one("breadthRule").still = true
          one("breadthRule").upShare = 0.5
          one("breadthRule").downShare = 0.25
        } else if (pose === "look") {
          one("lookIcon").still = true
          one("lookIcon").cells = 0.5
        } else if (pose === "neutral") {
          var unknown = Object.assign({}, stub.quotes[stub.featuredSymbol], {prevClose: null})
          stub.quotes = Object.assign({}, stub.quotes, {[stub.featuredSymbol]: unknown})
        }
        savePicture()
        return
      }
      if (root.refusedList) {
        var choices = [{name: "", label: "All", symbols: stub.symbols, count: stub.symbols.length}]
        for (var n = 1; n <= 30; n++) choices.push({name: "List " + n, label: "List " + n, symbols: stub.symbols, count: stub.symbols.length})
        stub.lists = choices
        if (root.refusedList[1] === "menu") {
          body.openListMenu()
          waitForRendering(body)
          one("listMenu").startNaming()
          one("listNameField").text = "List 1"
          one("listMenu").problem = "List 1 already exists"
        } else {
          body.openManageLists()
          waitForRendering(body)
          var manage = one("manageLists")
          manage.startRenaming(30)
          one("renameField").text = "List 1"
          manage.problem = "List 1 already exists"
        }
        savePicture()
        return
      }
      if (root.anchorState) {
        verify(!!root.anchorPose, "the real placement produced this review pose")
        anchorProbe.hold()
        if (!anchorProbe.QsWindow || anchorProbe.QsWindow.window !== renderWindow || !anchorProbe.parent) {
          console.error("FAIL the default held anchor finds its real pill's window")
          root.failures++
          return
        }
        var heldAt = anchorProbe.mapToItem(renderWindow.contentItem, 0, 0)
        var pillAt = anchorPill.mapToItem(renderWindow.contentItem, 0, 0)
        compare(heldAt.x, pillAt.x, "the real pill's held position")
        savePicture()
        return
      }
      var control = root.controlState[2]
      var mode = root.controlState[3]
      var all = stub.symbols.slice()
      stub.lists = [{name: "", label: "All", count: all.length, symbols: all},
        {name: "Watching", label: "Watching", count: 2, symbols: all.slice(0, 2)},
        {name: "Growth", label: "Growth", count: 1, symbols: all.slice(2, 3)}]
      stub.order = "pct"
      waitForRendering(body)
      var target = null
      if (control === "range") target = root.findAll(one("rangeRow"), "rangeToken")[1]
      else if (control === "list") target = one("listLabel")
      else if (control === "orderword") target = one("orderLabel")
      else if (control === "orderarrow") target = one("orderArrow")
      else if (control === "unit") target = one("unitTarget")
      else if (control === "manualorder") { stub.order = "manual"; target = one("orderLabel") }
      else if (control === "look") target = one("lookIcon")
      else if (control === "help") target = one("helpMark")
      else if (control === "footer") target = one("footerText")
      else if (control === "breadth") target = one("breadthRule")
      else if (control === "remove") {
        body.watchlist.cursorSymbol = stub.shown[1]
        waitForRendering(body)
        target = root.findAll(body.watchlist.rowItem(stub.shown[1]), "rowRemove")[0]
      } else if (control === "done" || control === "deadmove" || control === "livemove") {
        body.openManageLists()
        waitForRendering(body)
        target = control === "done" ? one("manageDone")
          : root.findAll(root.findAll(body, "manageRow")[1], control === "deadmove" ? "moveUp" : "moveDown")[0]
      } else if (control === "symbol") {
        body.openSymbolLists(stub.shown[0])
        waitForRendering(body)
        // The click that opened this view is shielded for a double-click.
        // Begin the row's film only once that row can receive the press.
        var shield = root.findAll(one("symbolLists"), "openingShield")[0]
        tryVerify(function() { return !shield.visible }, 2000)
        target = root.findAll(body, "symbolListRow")[0]
      } else if (control === "search") {
        body.adding = true
        body.search.results = Search.parseSearch(JSON.parse(searchFile.text())).results
        body.search.searchText = "SHOP"
        body.search.resultsQuery = "SHOP"
        body.search.answer = "results"
        root.searchField(body.search).text = "SHOP"
        body.search.suspend()
        waitForRendering(body)
        target = root.findAll(body.search, "searchResult")[1]
      }
      verify(!!target, "review control exists: " + control)
      waitForRendering(body)
      var point = target.mapToItem(body, target.width / 2, target.height / 2)
      // The word's right end is its own control; its left is the arrow.
      if (control === "orderword") point = target.mapToItem(body, target.width - 2, target.height / 2)
      if (mode === "press") {
        var fill = control === "list" ? one("listControl")
          : control === "orderword" || control === "manualorder" ? one("orderControl")
          : control === "orderarrow" ? one("orderArrowFill")
          : control === "unit" ? one("unitFill")
          : control === "look" ? one("lookFill")
          : control === "help" ? one("helpFill")
          : control === "footer" ? one("footerFill")
          : control === "done" ? root.findAll(target, "actionFill")[0]
          : control === "symbol" ? root.findAll(target, "rowFill")[0]
          : control === "remove" ? root.findAll(target, "rowRemoveFill")[0] : target
        var corner = fill.mapToItem(body, 0, 0)
        var box = [Math.ceil(corner.x) + 1, Math.ceil(corner.y) + 1, Math.floor(fill.width) - 3, Math.floor(fill.height) - 3]
        // Off the control, so the film opens on it at rest; the time lets
        // any hover fill the move left fade (160 ms).
        mouseMove(body, body.width / 2, 10)
        wait(200)
        pressFilm.source = body
        pressFilm.begin(root.stateName)
        tryVerify(function() { return pressFilm.frames.length >= 4 }, 2000)
        pressFilm.markStart()
        mousePress(body, point.x, point.y)
        tryVerify(function() { var frames = pressFilm.frames; return frames.length > 0 && frames[frames.length - 1].at - pressFilm.start >= 320 }, 3000)
        pressFilm.end()
        tryVerify(function() { return pressFilm.waiting === 0 }, 3000)
        var ink = Style.pressedFillFor(stub.foreground, Commons.Color.accent)
        pressFilm.judge("press", null, [[ink.r, ink.g, ink.b, ink.a].join(","), box.join(",")])
        tryVerify(function() { return pressFilm.verdict !== null }, 10000)
        if (!pressFilm.verdict.ok) {
          console.error("FAIL pressed feedback " + control + " — " + pressFilm.verdict.detail)
          root.failures++
        }
      } else {
        // RowPointer treats its first sighting as a resting pointer.
        // Enter the row, then move within it as a hand would.
        if (control === "symbol" || control === "search")
          mouseMove(body, point.x - target.width / 4, point.y)
        mouseMove(body, point.x, point.y)
      }
      savePicture()
    }

    function savePicture() {
      // The hover and press fills, the scroll and the poses' rows, settle
      // within two 160 ms fades; nothing says when all of them have.
      wait(320)
      var saved = false
      frame.grabToImage(function(result) { saved = result.saveToFile(root.outPath) })
      tryVerify(function() { return saved }, 3000)
      root.finish()
    }
  }

  FrameGrab { id: pressFilm }
}
