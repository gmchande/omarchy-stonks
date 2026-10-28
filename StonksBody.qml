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
// Shared body for the window and the panel: header, hero band, list,
// search, footer, help, and the chart's motion (ChartMotion). It reads the
// service and acts through it; the surface keeps its lifecycle, keys, and
// look. The footer sits at the edge, one gap under the rows: a surface
// that sizes itself asks fittedHeight for whole rows; in the window, the
// edge is where the content ends, or the window's bottom.
Item {
  id: root

  // The data owner, or null while it is not ready.
  property var service: null
  // The plugin's version on disk against the one running (`Updates`).
  property var updates: null
  // The sounds for what you do here (`Sounds`), or null for none.
  property var sounds: null
  // The screenshot's hand-off (`Camera`), or null for none.
  property var camera: null
  property bool surfaceOpen: false
  // A screen shows the open surface: the window on a workspace no screen
  // shows is open, as it was left, and asks for nothing an open one would.
  property bool onScreen: true
  property string headerWhenMissing: "No data"
  // Whether the surface steps to the next widget's panel on Tab: the panel's.
  property bool switchesPanels: false
  property int margins: 0
  // Where the content ends, the footer at its bottom. The panel's card eases
  // its edge to a new height while the body lays out at it at once, so a
  // row below it is out of sight. In the window it is the content's own
  // height while that fits, so a short list has the footer one gap under
  // its rows, and the window's bottom once the list fills it.
  property real edge: Math.min(height, fittedHeight(Infinity))
  // One vertical rhythm for both looks and surfaces. A band's gap stands
  // between the band's blocks (hero, chart, range row, info lines, list
  // header); a group's gap, half of it, between a thing and what it heads
  // (header over hero, list header over rows, rows over footer). Info lines
  // are 4 apart. Each row of words in the band is its caption line, a
  // control's fill reaching past it, so the gaps are the gaps seen.
  readonly property int bandGap: Style.space(16)
  readonly property int groupGap: Style.space(8)
  // Every block's words share the rows' two edges: `inset` in from the
  // rows' fills, which stop one `gutter` short of the right for the
  // scrollbar. A block with a fill (row, search answer, view row, footer)
  // spans the rows' width, its words inset; the band's and the key sheet's
  // words stand at the edges, a control's fill reaching past. Key sheet
  // descriptions may wrap past the right edge; the header is the surface's.
  readonly property int inset: Style.space(10)
  readonly property int gutter: Style.space(8)
  readonly property int textLeft: margins + inset
  readonly property int textRight: margins + gutter + inset
  property int chartHeight: Style.space(190)
  // The least the chart may be (the window's 136 px): where set, the chart
  // is sized to the surface (`shownChartHeight`), giving way first as the
  // window gets short so three rows still show. The panel's card fits its
  // rows, so its chart follows the screen's room (`screenChartHeight`). 0,
  // the panel's, gives none: a constant, so no chartHeight change finds it
  // stale.
  property int minChartHeight: 0
  // The host's look.
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
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
  // Adds not yet heard: each is as its row joins this surface's list, its
  // answer in, whatever is featured or added meanwhile.
  property var unheardAdds: []
  // The surface's own colour, which a moving row carries.
  property color ground: Commons.Color.background
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
  // A row's menu while it is open, null while shut: { symbol, lines, each
  // { label, everywhere }, ground, what it was opened on (`rowMenuGround`),
  // startLine, the line its cursor starts on, -1 for none, and where it
  // opens in the body: its top-left at (x, below), or, where the body has
  // no room under that, its bottom-left at (x, above) } (`openRowMenu`).
  property var rowMenu: null
  // It stands where it opened, so a surface that changes size under it,
  // as a tiled window does, closes it, as a desktop's menus close.
  onWidthChanged: rowMenu = null
  onHeightChanged: rowMenu = null
  // It also closes on a change to what it was opened on (the list on show,
  // the lists its symbol is in, or its row), from anywhere, so a line never
  // acts on a list it doesn't name. Read as a binding from the view and the
  // lists: a handler of the view's change could read the list's name before
  // it moves, and the lists may keep their array when only the list on show
  // changes.
  function rowMenuGround(symbol) {
    if (view.rows.indexOf(symbol) < 0) return ""
    return JSON.stringify([view.list, lists.filter(function(list) { return list.symbols.indexOf(symbol) >= 0 }).map(function(list) { return list.name })])
  }
  readonly property string rowMenuGroundNow: rowMenu ? rowMenuGround(rowMenu.symbol) : ""
  // Closed a turn later: closing in the binding's own change would have it
  // read itself again.
  onRowMenuGroundNowChanged: if (rowMenu && rowMenuGroundNow !== rowMenu.ground) Qt.callLater(function() {
    if (root.rowMenu && root.rowMenuGround(root.rowMenu.symbol) !== root.rowMenu.ground) root.rowMenu = null
  })
  // A short word in the footer's place, for a moment, held while the pointer
  // is on it: why a key did nothing.
  property string note: ""
  // A screenshot was taken on this visit: the header's camera stays lit
  // until the surface closes, and the next open puts it out.
  property bool cameraLit: false
  // A quiet line above the footer for this visit: the panel's first-run
  // hint (`showFirstRunHint`), how the pill is moved and changed. The next
  // open clears it.
  property string hint: ""
  function showFirstRunHint() {
    hint = "Drag the pill to move it along the bar\nMiddle-click changes how the pill looks · right-click opens the window"
  }
  // The most height the screen leaves the body, whatever the card fits; 0
  // where the body's height is its own (the window).
  property int screenRoom: 0
  // Everything in the panel but its chart, its rows, and the hint: what the
  // chart and the rows share the screen's room with.
  readonly property int chromeBesideHeader: margins * 2 + heroBand.heightBesideChart + footer.barHeight + groupGap * 3
  readonly property int chromeBesideScreenChart: chromeBesideHeader + header.height
  // The header's title and rule give way after the chart, before the hint:
  // where three rows wouldn't fit beside the chart's least, the header is
  // the status words alone.
  readonly property bool headerTitled: screenRoom <= 0
    || chromeBesideHeader + header.titledHeight + leastScreenChart + threeRowsHeight <= screenRoom
  // The panel's chart: chartHeight wherever the screen holds three rows
  // beside it, else down to a fifth of itself, which still shows the day's
  // shape: rows in view matter more, and the list menu and search, in the
  // rows' room, show three lines too. Read from the screen's room, never
  // the card's, which fits the chart.
  readonly property int leastScreenChart: Math.round(chartHeight / 5)
  readonly property int screenChartHeight: screenRoom <= 0 ? chartHeight
    : Math.max(leastScreenChart, Math.min(chartHeight, screenRoom - chromeBesideScreenChart - threeRowsHeight))
  // The hint gives way, after the chart, where it would leave fewer than
  // three rows in sight: read from the screen's room, never the card's,
  // which fits what the footer takes.
  readonly property bool hintShown: hint !== "" && (screenRoom <= 0
    || chromeBesideScreenChart + screenChartHeight + footer.hintRoom + threeRowsHeight <= screenRoom)
  // A standing word in the footer's place, under a note, until fixed: the
  // data file can't be read, and once a change is made meanwhile, that it
  // isn't saved, since only memory holds it, each with what to do, which
  // names the file; a save didn't land, which a click retries, ahead of the
  // update, since a restart would lose the changes; or an update waits on a
  // shell restart, which a click does. The notice's words stay whole; what
  // to do follows it on its line, or on a line of its own where both don't
  // fit (`noticeActions`, longest first): the file by its full path, then
  // without "or remove" (the owner, 28 October).
  readonly property bool unsaved: settingsUnreadable ? editsUnsaved : saveFailed
  readonly property string notice: unsaved ? "Your changes aren't saved"
    : settingsUnreadable ? "Couldn't load your lists"
    : updatedTo !== "" ? "Updated to " + updatedTo + " · click to restart the shell" : ""
  readonly property var noticeActions: settingsUnreadable
    ? ["fix or remove ~/.config/omarchy/grvc.stonks.json", "fix ~/.config/omarchy/grvc.stonks.json"]
    : unsaved ? ["click to try again"] : []
  // A newer Stonks on main, offered at the footer's right end until on disk
  // (`updateOffer`), then the restart's notice; never in the add's place,
  // so adding by mouse never waits on it. The update restarts the shell
  // once it lands, and the notice's click or Shift+U does after an update
  // run elsewhere, each only while no unsaved change outranks it
  // (`restartable`): then the notice waits for the save. Shift+U runs what
  // the footer offers. With neither, it says so, as Ctrl+Z does with
  // nothing to undo.
  readonly property string updateOffer: releasedTo !== "" && updatedTo === "" ? releasedTo : ""
  readonly property bool restartable: !unsaved && !settingsUnreadable
  readonly property bool restartOffered: updatedTo !== "" && restartable
  function runOffered() {
    if (!updates) return
    if (restartOffered) updates.restart()
    else if (updateOffer !== "") updates.update(restartable)
    else say("Nothing to update")
  }

  // What this surface shows of the service, read only while open: from a
  // close to the next open each keeps its last value, so nothing changes
  // during the panel's close fade. The next open takes the latest at once.
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
  // Every symbol's cap and P/E, and the rates P/Es need by currency pair,
  // as the service keeps them.
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
  // The bar the scrub last struck on this pass over the chart, so moving
  // within a bar strikes nothing more; -1 between passes.
  property int chimed: -1
  // Each symbol waiting on Yahoo, with the second that began: freshness's
  // overdue (`QuoteFeed.owed`).
  property var owed: ({})
  // Each symbol whose refresh was asked under 2 s ago (`Service.asking`):
  // freshness's grace for a quote opened old.
  property var asking: ({})
  property bool settingsUnreadable: false
  property bool saveFailed: false
  property bool editsUnsaved: false
  // A refresh the reader asked for has a request out (`Service.refreshing`).
  property bool refreshing: false
  property string updatedTo: ""
  // A newer Stonks on main, "" for none (`Updates.releasedVersion`).
  property string releasedTo: ""
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
  // The chart on screen, the motion's: the view's once it can be drawn,
  // until then the one already shown, so the hero keeps its chart, figures,
  // and info lines until the new one draws in; after a quarter second they
  // dim (`motion.dimmed`). Null only before any chart.
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
  // The least rows the list keeps in sight beside a chart that gives way,
  // in the window (`shownChartHeight`) and the panel (`screenChartHeight`).
  readonly property int threeRowsHeight: 3 * rowPitch - rowGap

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
  // one reads a range or the 1D chart's hours outside Yahoo's day, except
  // into the coming day's pre-market, which each row's quote holds too
  // (`Quote.tailStart`). The quote and the day change one after the other,
  // so the day may still be null here: the scrub stands until it comes in.
  readonly property var featuredTail: featuredQuote ? Quote.tailStart(featuredQuote) : null
  readonly property int watchlistScrubShown: historyActive || !featuredQuote || scrubShown < Quote.dayStart(featuredQuote)
    || (!!featuredDay && !!featuredDay.axis && scrubShown >= Quote.dayEnd(featuredQuote)
      && !(featuredTail !== null && scrubShown >= featuredTail)) ? 0 : scrubShown
  // Yahoo's quote: the headline and the day's figures, at rest.
  readonly property var featuredQuote: motion.quote
  // The day the 1D chart draws, which a scrub of it reads: its prints, and
  // its baseline as `prevClose` (`Chart.viewChart`).
  readonly property var featuredDay: motion.day
  readonly property var featuredFreshness: Figures.freshness(entryOf(chartSymbol || featuredSymbol), featuredQuote, now,
    owed[chartSymbol || featuredSymbol] || 0, !!asking[chartSymbol || featuredSymbol])
  // How many symbols in All have a failed or overdue refresh. With every
  // one, Yahoo is sending nothing for any listing: the header says so once,
  // and the hero and rows say what they have without a warning each
  // (`Figures.quietFreshness`).
  readonly property int warnings: lists.length > 0 ? lists[0].symbols.filter(function(symbol) {
    return Figures.freshnessWarns(Figures.freshness(entryOf(symbol), quotes[symbol] || null, now, owed[symbol] || 0, !!asking[symbol]))
  }).length : 0
  readonly property bool yahooDown: warnings > 0 && warnings === lists[0].symbols.length
  // Why Yahoo stopped and when Stonks tries again, while its gate is paused
  // (`Figures.hostPause`).
  readonly property var hostPause: service && service.yahooGate
    ? Figures.hostPause(service.yahooGate.pause, service.yahooGate.pausedUntil, now) : null
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
  // against the baseline (`Figures.animalKind`), as the pill's reads the day.
  readonly property string animalKind: Figures.animalKind(featured)
  // What it reads, the chart as the motion tells charts apart (a failed
  // range's stand-in day is another chart than its history), the list, and
  // the look: a change of it is no turn, so the animal changes at once.
  readonly property string animalChart: [motion.chartKeyOf(chart), view.listKey, retro].join(" ")
  // It sleeps while its market does, by the phase and the calendar, never
  // by the data's age (`Overnight.marketAsleep`), and a scrub, which reads
  // a moment the market traded, wakes it. `bell`: the clock alone put it to
  // sleep or woke it in the last few seconds, the same quote the other way
  // `bellWindow` before, so its eyes close or open slowly, a late or skipped
  // tick of the clock included; any other change of sleep is no bell: a
  // scrub let go, ever (`scrubbed` tells the header a scrub woke it), and a
  // quote landing, past those seconds. `animalSleep` is 0 awake, 1 asleep,
  // 2 asleep at the bell, 3 awake for a scrub, 4 awake at the bell, worked
  // out in one binding, so no value of it pairs a fresh sleep with a stale
  // bell or scrub; a number, so the animal changes only when its sleep
  // does, not with every tick, quote, or scrub step that leaves it.
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
  // Today in the featured listing's exchange, which changes only at its
  // midnight, so the day line is not derived again every second.
  readonly property int featuredToday: featuredQuote ? Figures.exchangeDay(featuredQuote, now) : 0
  // The info block's first line describes the chart: the day's on 1D, a
  // range's low and high with START and VOL on a longer one, over the 52
  // weeks; before any chart, nothing. A range also marks its high and low,
  // with their dates, on its chart (`rangeMarks`). The info table holds
  // room for both first lines' facts on every range (`infoFactLists`), so a
  // range change moves nothing; a range whose prices take another digit
  // widens the price columns.
  readonly property var dayLine: chart ? Figures.dayLine(featuredQuote, featuredToday) : null
  readonly property var rangeEnds: historyShown ? History.rangeEnds(history, historyStats, featuredQuote) : null
  readonly property var periodLine: !chart ? null : historyShown ? History.rangeLine(history, rangeEnds, featuredQuote) : dayLine
  readonly property var infoFactLists: !dayLine ? [] : [dayLine.facts, History.rangeFacts(dayLine.range.widest)]
    .concat(yearLine ? [History.rangeFacts(yearLine.range.widest)] : [])
  // On 1Y the 52 weeks take in the range's own ends, so the two lines never
  // disagree (`Fundamentals.yearLine`).
  readonly property var yearLine: chart ? Fundamentals.yearLine(featuredQuote, fundamentals ? fundamentals.figures : null,
    historyShown && history.range === "1Y" ? rangeEnds : null, rates) : null
  readonly property var rangeMarks: historyShown ? History.rangeMarks(history, rangeEnds, featuredQuote) : null
  // What the dashed line is, said while a scrub reads against it, and on a
  // thin night's day the close the night's trades read from too.
  readonly property string baselineText: historyShown ? chartRange.toUpperCase() + " START " + Format.money(history.baseline, featuredQuote ? featuredQuote.priceDigits : undefined)
    : (!historyActive && featuredDay ? Figures.dayBaselineText(featuredDay, Figures.exchangeDay(featuredDay, now), scrubShown) : "")
  // A range that failed, which r, or the header's button, asks for again.
  readonly property string unavailableText: chartRange.toUpperCase() + " unavailable"
  readonly property bool offersRetry: headerText === unavailableText
  // The chart asked for, named while it is on its way.
  readonly property string loadingText: "Loading" + (featuredSymbol ? " " + featuredSymbol + (range !== "1D" ? " " + range : "") : "")
  // The market as the header says it, said in less and less.
  readonly property var marketForms: featuredQuote ? Market.statusForms(dayScrubbed ? featuredDay : featuredQuote, now, scrubShown, calendars,
    Overnight.nightTrades(featuredQuote, !!chart && chart.allDay, now, calendars)) : []
  // Trouble, said once, unless a scrub reads a moment, a refresh you asked
  // for is out, or a range failed, whose header offers its retry: while a
  // row warns and Yahoo is paused, why and when Stonks tries again; with
  // every row warning and no pause, that Stonks keeps trying; and a price
  // on show whose refresh failed, why. Null without trouble. The header
  // says it at full strength (`HeaderStatus.trouble`). Yahoo's pause is
  // said short in the panel, which switches panels on the bar, and as a
  // sentence first in the window, which has the room (`Figures.hostPause`).
  readonly property var troubleForms: {
    if (!service || scrubShown || refreshing || (historyActive && historyFailed)) return null
    if (hostPause && warnings > 0) return switchesPanels ? hostPause.forms : [hostPause.sentence].concat(hostPause.forms)
    if (yahooDown) return ["Can't get prices · Stonks keeps trying", "Can't get prices"]
    if (featuredQuote && featuredFreshness.state === "failed")
      return ["Refresh failed for " + (chartSymbol || featuredSymbol) + " · Retrying", "Refresh failed · Retrying", "Refresh failed"]
    return null
  }
  // The header's words, then the same said in less for a header with no
  // room for them (`HeaderStatus`), each form shorter than the one before:
  // trouble in fewer words, a scrubbed bar's
  // date without its price, and the market's (`Market.statusForms`).
  readonly property var headerForms: {
    if (!service) return [headerWhenMissing]
    if (troubleForms) return troubleForms
    // The chart asked for is on its way, named: what was on show stays.
    // Before any chart has been in, the empty hero's label names it alone,
    // in the one place a reader looks (`HeroBand`).
    if (chartLoading) return [chart ? loadingText : ""]
    // A refresh the reader asked for, while what it sent is out, unless a
    // scrub reads a moment: then the header names that.
    if (refreshing && !scrubShown) return ["Refreshing"]
    if (historyActive && historyFailed) return [unavailableText]
    // A refetch the service asks for itself, out or failed, with the range
    // in hand says nothing: it keeps the chart and the market.
    if (historyShown && historyBar) return History.historyScrubForms(history, historyBar, featuredQuote ? featuredQuote.priceDigits : undefined)
    if (featuredQuote) return marketForms
    return [headerWhenMissing]
  }
  // "" while the market's words, on their way in with a new quote, are not
  // yet in, as a string property not yet bound reads.
  readonly property string headerText: headerForms[0] || ""
  // Everything but the rows: margins, header, band, and footer, with the
  // band, the rows, and the footer each one group's gap under what is above.
  readonly property int chromeHeight: chartFitsSurface ? chromeBesideChart + shownChartHeight
    : margins * 2 + header.height + heroBand.implicitHeight + footer.height + groupGap * 3
  readonly property int chromeBesideChart: margins * 2 + header.height + heroBand.heightBesideChart + footer.height + groupGap * 3
  // The chart as drawn where it fits the surface (the window's): its height
  // follows the surface's alone, never the list's, so a list switch moves
  // nothing. Where three rows don't fit beside chartHeight it gives way,
  // down to minChartHeight; otherwise it takes what whole rows leave over,
  // so the rows end one gap above the footer. Read from the chrome beside
  // it, never the chart, so its size never reads itself back; elsewhere a
  // height fitted to the body, as the panel's, never passes through it.
  readonly property bool chartFitsSurface: minChartHeight > 0 && minChartHeight < chartHeight
  readonly property int roomBesideChart: height - chromeBesideChart - chartHeight
  readonly property int shownChartHeight: roomBesideChart < threeRowsHeight
    ? chartHeight - Math.min(chartHeight - minChartHeight, threeRowsHeight - roomBesideChart)
    : chartHeight + roomBesideChart - rowsHeight(Infinity, roomBesideChart)
  // The shortest the surface may be: its chrome and one row, or, where the
  // chart fits the surface, its chrome at the least chart and three rows.
  // Counted from the rows, not from the chart's give: each size rounds on
  // its own at a larger text size (275 less 170 is not two 53 px rows).
  readonly property int smallestHeight: chartFitsSurface ? chromeBesideChart + minChartHeight + threeRowsHeight
    : chromeBesideChart + chartHeight + listRowHeight
  readonly property int helpHeight: margins * 2 + header.height + groupGap + helpSheet.contentHeight
  // Search needs room for the field and a full set of results, never less
  // because the list it replaces is short. Its field takes the rows' place
  // as it opens, and its answers fill down under the field.
  readonly property int searchHeight: margins * 2 + header.height + heroBand.implicitHeight
    + groupGap * 2 + search.desiredHeight
  readonly property int wholeListHeight: wholeRowsHeight(height - chromeHeight)
  // The most height the surface gives the body, as the panel's card does
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
  readonly property bool ownsKeys: adding || listMenuOpen || listViewOpen || rowMenu !== null
  // The last removal, which search offers back first, PUT BACK, in the
  // list it left: the list on show held the stock before it, and lacks it
  // now. Null when there is none.
  readonly property var putBack: {
    if (!removal || members.indexOf(removal.symbol) >= 0) return null
    var was = Settings.listChoices(removal.before).filter(function(list) { return list.name === listName })[0]
    if (!was || was.symbols.indexOf(removal.symbol) < 0) return null
    var quote = removal.quote
    return { symbol: removal.symbol, name: quote ? quote.name : removal.symbol, exchange: quote ? quote.exchange : "" }
  }
  readonly property var keySheet: KeySheet.sheet(order, switchesPanels)
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

  // The body's height within `maxHeight`: the key sheet's own while it
  // shows, otherwise whole rows for the list shown, the footer one gap
  // under them. A view over the rows (list menu, search, Manage lists, a
  // row's ticks) keeps that height and scrolls in the rows' room: it grows
  // the surface only for a list shorter than itself, and only in whole
  // rows, never into what the rows leave over. Search takes its full height
  // as it opens, so the card's edge holds still while you type. An open
  // list menu gets at least its least (`listMenuLeastBottom`) and the
  // footer under it, where the room holds that though its whole rows don't.
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
    if (service) service.surfaceShown(root, surfaceOpen && onScreen)
    if (!surfaceOpen) previewTo("")
  }
  onOnScreenChanged: if (service) service.surfaceShown(root, surfaceOpen && onScreen)
  onServiceChanged: if (service && surfaceOpen && onScreen) service.surfaceShown(root, true)
  // The chart scrubbed, by the pointer on it or by keys, where a screen
  // shows it, and not while every screen is off, which the panel's own
  // `onScreen` doesn't follow: the sounds keep the output awake a second
  // after it last moved, started, or ended, for its chimes.
  readonly property bool scrubbing: surfaceOpen && onScreen && !(service && service.screensOff) && motion.scrubT !== 0
  onScrubbingChanged: if (sounds) sounds.scrubMoved()
  onScrubTChanged: if (sounds && scrubbing) sounds.scrubMoved()
  // A surface taken down mid-replay, as a rebuilt bar or a removed screen
  // takes its panel, stops its replay's sound with it.
  Component.onDestruction: {
    if (sounds) sounds.stopReplay(root)
    if (service) {
      service.surfaceShown(root, false)
      service.preview(root, "")
    }
  }
  // The rows in sight while they show, whose charts the service fetches
  // ahead on a range.
  readonly property var rowsInSight: surfaceOpen && onScreen && rowsShown ? watchlist.sightSymbols : []
  onRowsInSightChanged: if (service) service.rowsSeen(root, rowsInSight)
  // One search previews at a time: another surface's search that starts
  // choosing takes the preview, and this search closes, so its hero never
  // shows one result while Enter would add another.
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPreviewTaken(surface) { if (surface === root) root.cancelAdding() }
    function onScreensReady() { search.pump() }
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
  // Sounds on or off; turned on, the add sound plays once, so you hear how
  // loud they are.
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

  // A key as both surfaces take it, so the panel and the window answer the
  // same keys; false for one Stonks doesn't answer. Esc, and the panel's
  // Tab, each surface reads itself. A letter's command is its key and Shift
  // (KeyText.typed): Caps Lock sends "O" for o, which would reverse.
  function pressKey(event) {
    var key = event.key
    var mods = event.modifiers & ~Qt.KeypadModifier
    var t = KeyText.typed(event)
    if (mods === Qt.ControlModifier && key === Qt.Key_C) takeScreenshot()
    else if (mods === Qt.ControlModifier && key === Qt.Key_Z) undoRemoval()
    else if (mods === Qt.ShiftModifier && key === Qt.Key_Up) moveSelected(-1)
    else if (mods === Qt.ShiftModifier && key === Qt.Key_Down) moveSelected(1)
    // Ctrl+Enter, as Ctrl-click: the selected row's lists.
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

  // The × beside a row's symbol, and Delete or Backspace: the row goes
  // from the list on show at once. Where that would reach lists not on
  // show, in All for a stock a named list holds too, they ask first, with
  // the row's menu on its one line.
  function removeRow(symbol) {
    if (!service || !symbol) return
    if (listName === "" && listsHolding(symbol) > 1) openRowMenu(symbol, null)
    else removeFrom(symbol, listName === "")
  }

  // How many lists hold `symbol`, All among them.
  function listsHolding(symbol) {
    return lists.filter(function(list) { return list.symbols.indexOf(symbol) >= 0 }).length
  }

  // Every removal comes through here: from the list on show, or, with
  // `everywhere`, from All and so from every list. All's last symbol stays,
  // said once in the footer, or in the lists checklist that asked, which
  // stays open; otherwise what covers the rows closes, so the removal
  // shows. A named list may empty. Removing the row the keyboard cursor is
  // on hands the cursor to the row that takes its place, as Mail and Finder
  // do: the next row, or the one before when it was the last.
  function removeFrom(symbol, everywhere) {
    if (!service) return
    showingHelp = false
    if (everywhere && !Settings.canRemove(lists[0].symbols)) {
      say("Keep at least one symbol")
      return
    }
    // Read and removed as the rows are shown, held under the pointer or
    // the row's menu, and only then is what covers them closed.
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

  // A row's menu says where each way to remove it reaches. In a named
  // list, that list by its name, and every list by count: the stock is in
  // All too, so there are always two. In All, a removal reaches every list
  // that holds it, so the menu is the one line that says so.
  function rowMenuLines(symbol) {
    var held = listsHolding(symbol)
    var everywhere = { label: held > 1 ? "Remove from all " + held + " lists" : "Remove from All", everywhere: true }
    return listName !== "" ? [{ label: "Remove from " + listName, everywhere: false }, everywhere] : [everywhere]
  }

  // The row's menu for `symbol`, its row taking the cursor: at `point`, the
  // pointer's place in the scene, on no line until the pointer or a key
  // moves; with no point, as a key opens it, under the row's symbol, on its
  // first line. Where the body has no room under, it opens upward, over
  // the pointer or the row.
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

  // A line taken closes the menu, after its removal, made or refused.
  function takeRowMenu(index) {
    var menu = rowMenu
    if (menu && index >= 0 && index < menu.lines.length) removeFrom(menu.symbol, menu.lines[index].everywhere)
    rowMenu = null
  }

  function say(text) {
    note = text
    holdNote()
  }

  // The footer's try again, while a save hasn't landed. Its read-back
  // (`Service.saveChecked`) says when it still didn't, on this surface,
  // and a save that lands meanwhile, a change's, takes that back at once.
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
    service.undoRemoval(symbol)
    sound("undo")
    watchlist.select(symbol)
  }

  // The footer offers a removal made here back beside the add for a few
  // seconds, "Undo NVDA", so a mouse removal says what it took and can be
  // undone by mouse; Ctrl+Z works long after. The add stays where it is and
  // acts at once, so adding the next stock never waits on the offer. The
  // offer ends with the removal (undone, a newer one, or the lists changed),
  // a close, or its time, which waits while the pointer is on it and fades
  // its last 600 ms, as a note does.
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
    duration: 600
    onFinished: root.endUndo()
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

  // The chimes: the scrub you move, by the pointer or the keys, strikes the
  // chart's bar where it lands (`ChartSound.barAt`), as a hand run along a
  // row of bar chimes does. The pointer strikes a bar as it moves onto it;
  // each key step strikes, `again`, the same bar too. A replay has its own
  // sound, and strikes nothing.
  function chime(again) {
    if (!sounds || motion.replayRunning) return
    var bar = ChartSound.barAt({ retro: retro, geometry: motion.geometry, grid: heroBand.pixelGrid }, motion.scrubX)
    if (bar !== chimed || again) sounds.chime(bar)
    chimed = bar
  }

  // A replay plays the shown chart; the motion runs it. After a quiet
  // spell it starts once the output is awake (`Sounds.whenAwake`), so its
  // sound keeps in step with its sweep from the first bar.
  function replay() {
    showingHelp = false
    if (!sounds) return motion.replay()
    sounds.whenAwake(root, function() { if (root.surfaceOpen) motion.replay() })
  }

  // A screenshot of the chart on show, as the camera or Ctrl+C takes it: laid
  // out for sharing (`ShareCard`) where no screen shows it, as the hero and
  // the chart show it at that moment, grabbed once its canvases have
  // painted, and handed to the camera, which saves, copies, and announces
  // it. The footer says what it shows. One at a time; with no chart on
  // show, the footer says why nothing was taken.
  function takeScreenshot() {
    showingHelp = false
    if (!camera || camera.busy || String(shareLoader.source) !== "") return
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
  // The other surface's shot may have taken the camera in the frames this
  // one waited: then this card goes, and the next Ctrl+C or click is free. The
  // shutter sounds as the picture is taken, and the card goes then; the
  // footer says how the save, the copy, and the notification went after.
  function shootCard(card) {
    var shown = Share.subject(card.symbol, card.range, card.words ? card.words.said : "")
    var taken = camera.shoot(card, Share.fileSymbol(card.symbol), function() {
      shareLoader.source = ""
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

  // Closes every view over the rows and the key sheet; the surface takes
  // the keys back once none has them (keysReleased).
  function closeViews() {
    cancelAdding()
    showingHelp = false
    listMenuOpen = false
    managingLists = false
    listsSymbol = ""
    rowMenu = null
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
    var shown = showingHelp
    closeViews()
    showingHelp = !shown
    if (showingHelp) helpSheet.contentY = 0
  }

  // Opening a view closes whatever else was open, the key sheet included.
  function startAdding() {
    if (!keepRename()) return
    closeViews()
    adding = true
  }

  // A symbol you add has nothing to show until its first answer, so the
  // service keeps it out of the rows until then. Then its row joins at its
  // place, the list eases it into view once, and once both are at rest it
  // is featured as a click on the row would, unless you chose another hero
  // or switched to a list without it meanwhile. The latest add is the one;
  // closing drops it (freeze). The add is heard as its row joins.
  // Search closes first, the preview staying on the hero, and the add joins
  // the rows as any new row does. The service features the preview's
  // symbol as it adds it, so the hero is unchanged: drawn if answered, else
  // named as on its way (`loadingText`) until it lands.
  // A result already in the list on screen is shown, not added
  // (`showSymbol`); one still arriving lands as an add does, and is
  // featured even when its first fetch fails. The removal on offer
  // (`putBack`) is put back as Ctrl+Z puts it.
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
    // An add takes the hero while it arrives (`Service.addSymbol`); a Show
    // of a member still arriving chooses it, kept whatever its answer.
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
    // A row that says its first fetch failed joins too, and is heard; an add
    // that has left the list on show goes unheard. Rows joining together
    // are heard once.
    if (unheardAdds.length && service) {
      var joined = unheardAdds.filter(function(a) { return service.arriving.indexOf(a) < 0 && view.rows.indexOf(a) >= 0 })
      if (joined.length) sound("add")
      var still = unheardAdds.filter(function(a) { return joined.indexOf(a) < 0 && members.indexOf(a) >= 0 })
      if (still.length !== unheardAdds.length) unheardAdds = still
    }
    if (landing === "" || !service || service.arriving.indexOf(landing) >= 0) return
    // A first fetch that failed has nothing to show: the hero is the one
    // before the add (`Service.heroTaken`), the add is done, and its row
    // says it failed; a Show features that row all the same. One the list
    // on show lacks is done too. One already in All whose first quote is
    // still out waits for it.
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
  // open surface; "" puts the featured symbol back. `result` is search's
  // result for it, when it came from one.
  function previewTo(symbol, result) {
    var s = adding && surfaceOpen ? String(symbol || "") : ""
    if (s === previewSymbol) return
    // The service's first: until it is, this preview would read as taken.
    if (service) service.preview(root, s, s ? result : null)
    previewSymbol = s
  }

  // The menu lies over rows that stay visible: the rows forget their last
  // click, so a press that dismisses it never pairs with one before.
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

  // A new list is empty, so search opens straight away to fill it.
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
  // A symbol's lists close once it has left All, however it left: removed
  // on the other surface or in the data file, there is nothing to tick.
  onViewChanged: if (listsSymbol !== "" && view.library.indexOf(listsSymbol) < 0) listsSymbol = ""

  // The keys go back to the surface once no view has them; a turn later,
  // so one view closing as another opens hands the keys straight across.
  onOwnsKeysChanged: if (!ownsKeys) Qt.callLater(function() { if (!root.ownsKeys) root.keysReleased() })

  function renameList(name, newName) {
    if (!service) return
    var problem = service.renameList(name, newName)
    if (problem !== "") manageLists.problem = problem
    else manageLists.stopEditing()
  }

  // Unticking All is a removal from All, and so from every list: the
  // checklist closes, since the symbol it shows has no lists left.
  function setMembership(name, member) {
    if (!service) return
    if (name === "" && !member) removeFrom(listsSymbol, true)
    else service.setMembership(listsSymbol, name, member, watchlist.displayedSymbols)
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

  // A name being typed outlives a close, as it outlives a click away: only
  // Escape or CANCEL throws it away. A rename is saved and a new list made,
  // as Enter would, so the fading card shows what it showed (a new list
  // becomes current, with no search opened for it). A refused name (taken,
  // or All) is kept (`draft`) and comes back, saying why, at the next open.
  // A search being typed is kept too and reopens with its words; an empty
  // field keeps nothing.
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

  // What a close kept, open again where it was typed. A rename comes back
  // only to its own list: one deleted, or renamed, or replaced by a new
  // list under its name meanwhile has another key, and the rename has
  // nothing left to act on.
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

  // At rest before the first frame: the rows in their places and the list on
  // a row, wherever a close stopped the wheel, and the look icon and the
  // breadth rule on what the surface now reads. A name a close kept, refused,
  // is open again where it was typed, and a newer Stonks not yet said is
  // said.
  function resetInteraction() {
    closeViews()
    freeze()
    motion.reset()
    // The rows in the service's order, at rest, whatever a close held.
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

  // A refusal stays a moment. Its last 600 ms it fades, still taking a
  // click while any of it shows, and what it covered fades in after it, so
  // the change under a click is seen coming: a click meant for the note,
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
    duration: 600
    onFinished: {
      root.clearNote()
      footer.fadeIn()
    }
  }

  // The surface's own row, on the margins as the rows' fills are, not on
  // the words' edges: the longest closure's status (a holiday's name, the
  // next open, its zone) needs every pixel of the panel's width.
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
    // The chart's symbol, or before any chart is in, the one coming, which
    // the header names as it loads: never a dash in its place.
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
    clearance: root.service ? function() { return root.service.screensClear() } : null
    active: root.adding && root.surfaceOpen
    retro: root.retro
    foreground: root.foreground
    dim: root.dim
    dimmer: root.dimmer
    fontFamily: root.fontFamily
    gutter: root.gutter
    // What to type, and the list it adds to; short, so a list's name fits
    // the panel's field.
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

  // Only a list with no members at all says so: one whose add is still
  // arriving is not empty, its row is coming. It says so over the rows on
  // show, so a closing surface, which keeps its rows, says nothing.
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

  // At the body's visible bottom, the edge, one gap under the list's rows;
  // it rides the panel's easing edge. It carries the surface's ground and
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
    // The click acts on what the footer shows: the update's notice
    // restarts the shell, and the file's does nothing, nor does a refusal
    // over it; while a save hasn't landed, any click tries again; a refusal
    // otherwise, or the label, adds.
    onClicked: {
      if (root.settingsUnreadable) return
      else if (root.saveFailed) root.saveAgain()
      else if (root.note === "" && root.updatedTo !== "") root.updates.restart()
      else root.startAdding()
    }
  }

  // The screenshot, laid out where no screen shows it, for a shot alone:
  // built as one is asked for, with what the surface shows at that moment,
  // and gone once it is handed on. Clipped to nothing rather than hidden:
  // a hidden item's parts read themselves as hidden, and the retro chart's
  // lit cap falls to its top row. A canvas paints on the frame after it is
  // asked to, so the grab waits two drawn frames: grabbed at once, the
  // chart comes out empty.
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

  // A closing surface takes no press, click, or wheel: the panel's card
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

  // A click anywhere off a row's menu closes it, with any button, and
  // nothing under it acts, as off the list menu. A double-click is one
  // click, as on the rows (`Watchlist.clickCounts`): the second press of
  // the right double-click that opened the menu leaves it open.
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

  // At its place (`openRowMenu`), kept inside the body's margins, over the
  // rows and the footer.
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
    // Where the chart takes the spare height (the window's), it runs down
    // over the footer, as it lies over the rows, so a short window shows
    // more lists. Elsewhere it ends one gap above the footer, which the
    // panel's card makes room for (`listMenuBottom`).
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
    // The replay heard starts with the replay, made from the chart as drawn
    // in the look on screen, and stops when the replay is cut short.
    onReplayStarted: function(from, to) {
      if (root.sounds) root.sounds.playReplay(root, { geometry: motion.geometry, grid: heroBand.pixelGrid,
        from: from, to: to, seconds: motion.replayDuration / 1000 })
    }
    onReplayCut: if (root.sounds) root.sounds.stopReplay(root)
    // The scrub let go ends the chimes' pass: the next starts afresh.
    onScrubTChanged: if (!scrubT) root.chimed = -1
  }
}
