pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Freshness.js" as Freshness
import "Settings.js" as Settings
import "Rows.js" as Rows
import "Motion.js" as Motion
// The scrolling rows: cursor, drag, scroll and wheel. Surfaces pass data in
// and save what the signals ask. One row for each symbol in All: a list
// hides the rows it lacks, so a switch builds nothing.
Flickable {
  id: root

  // Arrives whole, so comparing it with the last says what changed.
  // Handlers read it, not a binding derived from it, which may lag behind.
  property var view: ({ list: "", listKey: "=", order: "manual", reversed: false, rows: [], shown: [], allSymbols: [] })
  property var quotes: ({})
  property var newestTrades: ({})
  // Robinhood's answers, by symbol, and the clock a row's 1D runs on to
  // before the open, five minutes at a time (`Service.viewDayClock`).
  property var nights: ({})
  property int dayClock: 0
  property var entries: ({})
  property string featuredSymbol: ""
  property int scrubShown: 0
  property string changeMode: "pct"
  property int now: 0
  property int minuteNow: 0
  property bool overnightList: false
  property var owed: ({})
  // Symbols asked to refresh under 2 s ago: freshness gives them grace.
  property var asking: ({})
  property var nightFailed: ({})
  property Look look
  property var calendars: null
  property int rowHeight: Style.space(40)
  property int rowGap: Style.space(2)
  property int gutter: Style.space(8)
  // Closed or closing: a pointer moving over it moves no cursor.
  property bool surfaceOpen: true
  // A screen shows the rows: out of sight, a removed row goes and the
  // selected fill moves at once. Hidden while open, or as the shell's
  // animations turn off, what moves lands; a closing surface holds it
  // through its fade (`pauseRows`).
  property bool seen: true
  function landMoves() {
    settleRows()
  }
  // Judged a turn later, once a close has said so too.
  onSeenChanged: if (!seen) Qt.callLater(function() { if (!root.seen && root.surfaceOpen) root.landMoves() })
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() { if (Style.reduceMotion) root.landMoves() }
  }
  // The rows' view height while they show. The panel's card shrinks to the
  // key sheet or a view, hiding the rows, but sight is still judged by this.
  property real sightHeight: height
  // How far down the view the list menu covers the rows; 0 while it's shut.
  property real menuCovers: 0
  // Yahoo sends nothing at all: the surface says so once, and no row warns.
  property bool sourceDown: false

  property string cursorSymbol: ""
  // The row the wheel or a removal (`handTo`) brought under a still pointer:
  // its remove button waits for the pointer to move or a key.
  property string scrolledUnder: ""
  property var displayedSymbols: []
  property var arrangedView: null

  readonly property int rowPitch: rowHeight + rowGap
  // Read at each use: a handler of rowPitch's change runs before a binding
  // on it would catch up.
  function rowSize() { return { pitch: rowPitch, height: rowHeight } }
  property int lastPitch: 0
  onRowPitchChanged: {
    if (lastPitch > 0) {
      var top = Math.round(headedY / lastPitch)
      var own = cursorSymbol
      takeOver()
      contentY = clampY(top * rowPitch)
      cursorSymbol = own
      // And keeps the cursor's row whole in sight, as a shorter surface does.
      keepCursorInSight()
    }
    lastPitch = rowPitch
  }
  readonly property real headedY: glide.running ? glide.to : contentY
  // Read where the list is headed, so a key gliding the list to its row
  // keeps it.
  readonly property string cursorRow: Rows.cursorRow(displayedSymbols, cursorSymbol, cursorSymbol === reorder.lifted, featuredSymbol,
    rowSize(), headedY, sightHeight)
  // A cursor of your own that leaves sight is let go, on these changes
  // rather than on cursorRow's, which reads the cursor it would clear.
  onHeadedYChanged: letGoUnseen()
  onSightHeightChanged: keepCursorInSight()
  onDisplayedSymbolsChanged: letGoUnseen()
  function letGoUnseen() {
    if (cursorSymbol !== "" && !Rows.chosenSeen(displayedSymbols, cursorSymbol, cursorSymbol === reorder.lifted, rowSize(), headedY, sightHeight))
      cursorSymbol = ""
  }
  property real lastSight: 0
  function keepCursorInSight() {
    var keep = cursorSymbol !== "" ? (cursorSymbol !== reorder.lifted ? cursorSymbol : "")
      : featuredSymbol
    var at = displayedSymbols.indexOf(keep)
    // The featured row only if it was whole in sight before, so a resize
    // never pulls the list back to it.
    if (keep !== "" && cursorSymbol === "" && !(at >= 0 && Rows.rowWhole(at, rowSize(), headedY, lastSight))) at = -1
    if (at >= 0 && sightHeight >= rowHeight && !wholeInSight(at, headedY)) {
      var own = cursorSymbol
      // Judged from where a key's glide was headed, so stopping the glide
      // never lets the cursor go on the way.
      var to = restingTopFor(at, headedY)
      takeOver()
      contentY = to
      cursorSymbol = own
    }
    lastSight = sightHeight
    letGoUnseen()
  }
  // Set while a row's menu is open: it takes the pointer's hover from the list.
  property bool held: false
  readonly property bool sortHeld: listHover.hovered || reorder.lifted !== "" || held
  readonly property bool manualOrder: view.order === "manual"

  signal featureRequested(string symbol)
  signal removeRequested(string symbol)
  // x, y in the scene.
  signal menuRequested(string symbol, real x, real y)
  signal listsRequested(string symbol)
  signal manualOrderRequested(var symbols)
  // A drag, J or K on a sorted order; the surface says why.
  signal moveRefused()
  signal arranged()
  signal rowRested(string symbol)
  // The pointer moved over the rows.
  signal pointerMoved()

  implicitHeight: rowsLength()
  contentWidth: width
  contentHeight: implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  interactive: contentHeight > height
  // A drag or a flick takes the list over from a glide.
  onMovementStarted: takeOver()
  // Shown as needed, as Omarchy's own lists show theirs.
  ScrollBar.vertical: ViewScrollBar {
    scrolls: root.interactive
    policy: ScrollBar.AsNeeded
    active: root.interactive
  }

  // A WheelHandler ignores the touchpad's events unless it accepts TouchPad.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
      event.accepted = root.wheelEvent(event.phase, event.pixelDelta.y, event.angleDelta.y)
    }
  }

  // A touchpad's pixels reach the shell at Hyprland's 0.4 of the fingers'
  // travel, so Omarchy's menu scales them by its own factor, which Stonks
  // follows, and by the 3 it chose until its shell has one.
  readonly property real touchpadFactor: Style.touchpadScrollFactor || 3

  // The wheel and the touchpad move the list at once and leave it where they
  // stop, as Omarchy's own lists do. Says whether the list took the event.
  function wheelEvent(phase, pixels, angle) {
    // A wheel's notches come with no scroll phase: 120 units, and three rows,
    // a notch, or parts of one from a high-resolution wheel. On Wayland a
    // notch carries 15 pixels too, so only the touchpad moves by pixels.
    var by = phase === Qt.NoScrollPhase ? -angle / 120 * 3 * rowPitch : -pixels * touchpadFactor
    if (by === 0) return false
    endClick()
    var from = headedY
    takeOver()
    contentY = clampY(from + by)
    pointAtPointer(headedY !== from)
    return true
  }

  // A key or a drop glides the list to its row.
  NumberAnimation {
    id: glide
    target: root
    property: "contentY"
    duration: Motion.duration(Style, 160)
    easing.type: Easing.OutCubic
  }

  RowPointer {
    id: listHover
    parent: root
    onMoved: function(x, y) {
      if (!root.surfaceOpen) return
      root.scrolledUnder = ""
      root.pointAt(x, y)
      root.pointerMoved()
    }
  }

  // Read where the list is headed: mid-glide, the row that will rest under
  // the pointer.
  function pointAt(x, y) {
    var seen = mapFromItem(null, x, y)
    // A lifted row is the drag's, and the gutter the scrollbar's: neither
    // moves the cursor.
    if (reorder.lifted !== "" || seen.x >= rowsBox.width) return false
    var at = Math.floor((seen.y + headedY) / rowPitch)
    if (at < 0 || at >= displayedSymbols.length) return false
    cursorSymbol = displayedSymbols[at]
    return true
  }

  function pointAtPointer(scrolled) {
    if (listHover.hovered && surfaceOpen && pointAt(listHover.scenePosition.x, listHover.scenePosition.y) && scrolled)
      scrolledUnder = cursorSymbol
  }

  function entryOf(symbol) {
    return entries && entries[symbol] ? entries[symbol] : null
  }

  // Its time is the price's the row shows at rest (`Figures.listRow`).
  function freshnessOf(symbol, quote, newestTrade) {
    var q = quote !== undefined ? quote : (quotes[symbol] || null)
    var nt = newestTrade !== undefined ? newestTrade : (newestTrades[symbol] || null)
    return Freshness.freshness(entryOf(symbol), q, now, owed[symbol] || 0, !!asking[symbol],
      nt, !!nightFailed[symbol], calendars)
  }

  function moveCursor(delta) {
    endClick()
    if (displayedSymbols.length === 0) return
    var current = displayedSymbols.indexOf(cursorRow)
    var next = Math.max(0, Math.min(displayedSymbols.length - 1, current < 0 ? 0 : current + delta))
    select(displayedSymbols[next])
  }

  // Home and End.
  function moveCursorTo(index) {
    endClick()
    if (displayedSymbols.length === 0) return
    select(displayedSymbols[Math.max(0, Math.min(displayedSymbols.length - 1, index))])
  }

  // A page key's step: the rows wholly in sight, less one, so the row it
  // leaves stays in sight.
  function pageRows() {
    return Math.max(1, Math.floor((sightHeight + rowGap) / rowPitch) - 1)
  }

  // Not contentHeight, which lags a pitch behind while onRowPitchChanged runs.
  function rowsLength() {
    return Math.max(0, displayedSymbols.length * rowPitch - rowGap)
  }

  function clampY(y) {
    return Math.max(0, Math.min(rowsLength() - height, y))
  }

  function snappedY(y) {
    return clampY(Math.round(y / rowPitch) * rowPitch)
  }

  function snapToRow() {
    takeOver()
    contentY = snappedY(contentY)
  }

  // A glide stopped and restarted in one turn passes through false, so a
  // reader waits a turn.
  readonly property bool settling: glide.running || moving

  // Another hand moves the list: a glide stops.
  function takeOver() {
    glide.stop()
  }

  function glideTo(y) {
    var target = clampY(y)
    glide.stop()
    if (target === contentY) return
    glide.from = contentY
    glide.to = target
    glide.start()
  }

  // Glides to bring the row whole into view, resting on a row boundary. A
  // row already whole leaves the list where it is, between rows too.
  function scrollToRow(index) {
    var at = Rows.topShowing(index, rowSize(), headedY, height)
    if (at !== headedY) glideTo(snappedY(at))
  }

  // Heads for the row first, so the cursor is set on a row in sight. A row
  // picked by a click (`pointed`) may come to rest under the pointer that
  // picked it, so its remove button waits as one scrolled under it does.
  function select(symbol, pointed) {
    var index = displayedSymbols.indexOf(symbol)
    if (index < 0) return
    scrollToRow(index)
    cursorSymbol = symbol
    scrolledUnder = pointed ? symbol : ""
  }

  // A removal hands the cursor on: a row in sight keeps the list where the
  // click stopped it, even between rows.
  function handTo(symbol) {
    var index = displayedSymbols.indexOf(symbol)
    if (index >= 0 && Rows.rowSeen(index, rowSize(), headedY, sightHeight)) cursorSymbol = symbol
    else select(symbol)
    scrolledUnder = symbol
  }

  // A click stops the list and puts the cursor on its row, under the
  // pointer. A double-click is one click: a press near the last click within
  // the double-click interval does nothing, and so does a press Qt calls a
  // double-click's `second`, unless its first was this list's last click and
  // the wheel, a key or a row's move came between (endClick).
  property real lastClickTime: 0
  property point lastClickPlace: Qt.point(-1, -1)
  property real rowClickAt: 0
  property real clickEndedAt: 0
  function clickRow(symbol, x, y, second) {
    return takeClick(symbol, x, y, clickCounts(x, y, second))
  }
  // Changes nothing, so a press can ask and act on the answer at release.
  function clickCounts(x, y, second) {
    var now = Date.now()
    var interval = Application.styleHints.mouseDoubleClickInterval
    var near = Application.styleHints.startDragDistance
    return second ? clickEndedAt >= rowClickAt && clickEndedAt > 0 && now - rowClickAt < interval
      : !(now - lastClickTime < interval
        && Math.abs(x - lastClickPlace.x) <= near && Math.abs(y - lastClickPlace.y) <= near)
  }
  function takeClick(symbol, x, y, counts) {
    var now = Date.now()
    lastClickTime = now
    lastClickPlace = Qt.point(x, y)
    rowClickAt = now
    if (!counts || displayedSymbols.indexOf(symbol) < 0) return false
    takeOver()
    cancelFlick()
    cursorSymbol = symbol
    if (scrolledUnder !== "") scrolledUnder = symbol
    return true
  }
  property string removeArmed: ""
  function endClick() {
    lastClickTime = 0
    clickEndedAt = Date.now()
  }
  function forgetClicks() {
    lastClickTime = 0
    rowClickAt = 0
    clickEndedAt = 0
  }
  // Rows hidden behind a view forget the last click, so the next one acts.
  onVisibleChanged: {
    forgetClicks()
    if (visible) listHover.rest()
  }

  // Against sightHeight, so the card's edge easing past moves no cursor.
  function wholeInSight(index, top) {
    return Rows.rowWhole(index, rowSize(), top, sightHeight)
  }

  // The rows drawn where the list is headed, a row past each edge as a row
  // in sight is (`inSight`), which the service fetches ahead. From row
  // numbers, so it changes only as a row crosses the edge.
  readonly property int sightFirst: Rows.rowsSeen(rowSize(), headedY - rowPitch, sightHeight + 2 * rowPitch).first
  readonly property int sightLast: Rows.rowsSeen(rowSize(), headedY - rowPitch, sightHeight + 2 * rowPitch).last
  readonly property var sightSymbols: displayedSymbols.slice(sightFirst, Math.max(sightFirst, sightLast + 1))

  function restingTopFor(index, top) {
    return Rows.restingTop(index, rowSize(), top, sightHeight, rowsLength())
  }

  function sameList(a, b) {
    if (!a || !b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }

  // With `animate`, a new row fades in at its place and the rest slide. A
  // list that shortens under its scroll is pulled back, its rows held on
  // screen, then sliding down to close the gap.
  function display(next, animate) {
    var before = displayedSymbols
    if (sameList(before, next)) return
    var scrolled = contentY
    var rows = animate && visible ? rowItems() : null
    var nextSet = {}
    for (var n = 0; n < next.length; n++) nextSet[next[n]] = true
    var beforeSet = {}
    for (var b = 0; b < before.length; b++) beforeSet[before[b]] = true
    // A row that leaves folds away where it stood.
    for (var f = 0; rows && seen && f < before.length; f++) {
      if (!nextSet[before[f]] && rows[before[f]]) rows[before[f]].fold()
    }
    displayedSymbols = next
    contentY = clampY(contentY)
    if (glide.running && glide.to > clampY(glide.to)) glideTo(glide.to)
    if (!rows) return
    for (var i = 0; i < next.length; i++) {
      if (!beforeSet[next[i]] && rows[next[i]]) rows[next[i]].join()
    }
    var pulled = scrolled - contentY
    if (pulled <= 0) return
    for (var j = 0; j < next.length; j++) {
      if (rows[next[j]]) rows[next[j]].carry(pulled)
    }
    for (var k = 0; k < before.length; k++) {
      var gone = rows[before[k]]
      if (gone && gone.folding) gone.foldY -= pulled
    }
  }

  function pauseRows() {
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) row.pause()
    }
    if (highlightSlide.running) highlightSlide.pause()
  }

  function settleRows() {
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) row.settle()
    }
    highlightSlide.stop()
    highlightShift = 0
  }

  function forgetGoneCursor() {
    if (cursorSymbol && view.rows.indexOf(cursorSymbol) < 0) cursorSymbol = ""
  }

  function applyShown() {
    display(view.shown.slice(), true)
    forgetGoneCursor()
  }

  function applyMembership() {
    var next = displayedSymbols.filter(function(s) { return view.rows.indexOf(s) >= 0 })
    var joining = view.shown.filter(function(s) { return next.indexOf(s) < 0 })
    for (var i = 0; i < joining.length; i++)
      next.splice(Math.min(view.shown.indexOf(joining[i]), next.length), 0, joining[i])
    display(next, true)
    forgetGoneCursor()
  }

  function commitManualOrder(next) {
    if (!manualOrder) return
    displayedSymbols = next.slice()
    manualOrderRequested(next)
  }

  function moveSymbol(symbol, delta) {
    endClick()
    if (!manualOrder) { moveRefused(); return }
    var from = displayedSymbols.indexOf(symbol)
    var to = from + delta
    if (from < 0 || to < 0 || to >= displayedSymbols.length) return
    commitManualOrder(Settings.movedSymbols(displayedSymbols, from, to))
    scrollToRow(to)
    cursorSymbol = symbol
  }

  function moveSelected(delta) {
    if (cursorRow) moveSymbol(cursorRow, delta)
  }

  function rowItem(symbol) {
    for (var i = 0; i < rowRepeater.count; i++) {
      var item = rowRepeater.itemAt(i) as WatchlistRow
      if (item && item.symbol === symbol) return item
    }
    return null
  }

  // One pass: a lookup per row is 22,500 looks at 150 symbols.
  function rowItems() {
    var rows = {}
    for (var i = 0; i < rowRepeater.count; i++) {
      var item = rowRepeater.itemAt(i) as WatchlistRow
      if (item) rows[item.symbol] = item
    }
    return rows
  }

  function rowResting(symbol) {
    var row = rowItem(symbol)
    return !!row && row.place >= 0 && row.resting
  }

  // A row dragged in your own order: lifted under the pointer, the others
  // making room, and dropped in the place it is over.
  readonly property ReorderDrag reorder: ReorderDrag {
    keys: root.displayedSymbols
    pitch: root.rowPitch
    contentY: root.contentY
    sight: root.sightHeight
    reach: Math.max(0, root.rowsLength() - root.height)
    onScrollTo: function(y) {
      root.takeOver()
      root.contentY = y
    }
    onDropped: function(from, to) {
      if (from !== to) root.commitManualOrder(Settings.movedSymbols(root.displayedSymbols, from, to))
    }
    // The dropped row comes whole into view, as a key's row does.
    onLanded: function(at) { if (at >= 0) root.scrollToRow(at) }
  }

  function beginDrag(symbol, y) {
    if (!manualOrder) { moveRefused(); return }
    if (displayedSymbols.indexOf(symbol) < 0) return
    takeOver()
    reorder.begin(symbol, y)
    cursorSymbol = symbol
  }

  // Closing mid-drag, every row, the lifted one too, stays where it is on
  // screen until the next open.
  function releaseDragInPlace() {
    if (reorder.lifted === "") return
    var rows = []
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) rows.push({ row: row, y: row.y })
    }
    reorder.cancel()
    rows.forEach(function(r) { r.row.holdAt(r.y) })
  }

  // Another list or an opening surface is a new arrangement: the rows take
  // their places at once.
  function layOut() {
    display(view.shown.slice(), false)
    settleRows()
    forgetGoneCursor()
  }

  // Sorting or reversing glides rows staying in sight, eases arriving rows
  // into place without leaving a gap, and settles off-screen rows at once.
  property bool sorting: false
  function reorderRows() {
    var next = view.shown.slice()
    var same = next.length === displayedSymbols.length && next.every(function(s, i) { return s === displayedSymbols[i] })
    if (same || !seen || !visible || Motion.duration(Style, 220) <= 0) {
      layOut()
      return
    }
    var rows = rowItems()
    var top = contentY
    var bottom = top + sightHeight
    var wasY = {}
    var wasSeen = {}
    for (var i = 0; i < displayedSymbols.length; i++) {
      var s = displayedSymbols[i]
      var r = rows[s]
      var at = r ? r.y : i * rowPitch
      wasY[s] = at
      wasSeen[s] = at + rowHeight > top && at < bottom
    }
    highlightSlide.stop()
    highlightShift = 0
    sorting = true
    display(next, false)
    sorting = false
    forgetGoneCursor()
    var newTop = contentY
    var newBottom = newTop + sightHeight
    var seenNext = {}
    for (var j = 0; j < next.length; j++) {
      var sym = next[j]
      seenNext[sym] = true
      var row = rows[sym]
      if (!row) continue
      var targetY = j * rowPitch
      var fromY = wasY[sym] !== undefined ? wasY[sym] : targetY
      var fromSeen = !!wasSeen[sym]
      var toSeen = targetY + rowHeight > newTop && targetY < newBottom
      if (fromSeen && toSeen) {
        row.sortGlide(fromY - targetY)
      } else if (!fromSeen && toSeen) {
        row.sortArrive(fromY < targetY ? -0.4 * rowPitch : 0.4 * rowPitch)
      } else {
        row.settle()
      }
    }
    for (var k in rows) if (!seenNext[k]) rows[k].settle()
  }

  // Each list's scroll, by its key, for the session: only lists that are
  // there keep one.
  property var places: ({})
  property var listKeys: []
  onListKeysChanged: {
    for (var key in places) if (listKeys.indexOf(key) < 0) delete places[key]
  }

  ListModel { id: rowsModel }
  // Rows that left All, kept until they have folded away.
  property var foldKept: []
  function syncRows() {
    Rows.syncModel(rowsModel, "symbol", arrangedView.allSymbols.concat(foldKept))
  }
  // A turn later, so no row goes inside its own handler.
  function releaseFolded() {
    var rows = rowItems()
    var kept = foldKept.filter(function(s) { return !!rows[s] && rows[s].folding })
    if (kept.length === foldKept.length) return
    foldKept = kept
    syncRows()
  }
  onViewChanged: {
    var before = arrangedView
    arrangedView = view
    if (!before) return
    // A rename keeps the key. StonksBody holds a closed surface's view, so
    // this runs only while open or opening, before reopen().
    var switched = view.listKey !== before.listKey
    var reordered = view.order !== before.order || view.reversed !== before.reversed
    if (!sameList(before.allSymbols, view.allSymbols)) {
      var allSet = {}
      for (var a = 0; a < view.allSymbols.length; a++) allSet[view.allSymbols[a]] = true
      var foldSet = {}
      for (var fk = 0; fk < foldKept.length; fk++) foldSet[foldKept[fk]] = true
      // A lifted row goes at once: the drag it was in ends with it.
      var leaving = !switched && !reordered && visible && seen
        ? displayedSymbols.filter(function(s) { return !allSet[s] && !foldSet[s] && s !== reorder.lifted }) : []
      foldKept = foldKept.filter(function(s) { return !allSet[s] }).concat(leaving)
      syncRows()
    }
    if (switched) {
      places[before.listKey] = headedY
      reorder.cancel()
      cursorSymbol = ""
      forgetClicks()
      takeOver()
      layOut()
      contentY = clampY(places[view.listKey] || 0)
    } else if (reordered) {
      reorder.cancel()
      reorderRows()
    } else if (sameList(before.shown, view.shown) && sameList(before.rows, view.rows)) {
      // Only featured or range changed: row order and membership are untouched.
    } else if (sortHeld) {
      applyMembership()
    } else {
      applyShown()
    }
    arranged()
    if (foldKept.length) Qt.callLater(releaseFolded)
  }
  onSortHeldChanged: if (!sortHeld && surfaceOpen) applyShown()

  function reopen() {
    cursorSymbol = ""
    forgetClicks()
    listHover.rest()
    layOut()
    var featuredAt = displayedSymbols.indexOf(featuredSymbol)
    if (featuredAt >= 0 && !wholeInSight(featuredAt, contentY)) {
      takeOver()
      contentY = restingTopFor(featuredAt, contentY)
    }
  }
  Component.onCompleted: {
    lastPitch = rowPitch
    arrangedView = view
    lineLook = look.retro
    Rows.syncModel(rowsModel, "symbol", view.allSymbols)
    display(view.shown.slice(), false)
  }

  // A look switch swaps each row's day line, a canvas, which a long All
  // builds for every row. Rows near sight swap at once, the rest a few a
  // frame after (`lineSweep`, the rows by index it has reached), and a row
  // that comes near sight first swaps as it does: none shows the old look.
  property bool lineLook: false
  readonly property int everyRow: 1 << 30
  property int lineSweep: everyRow
  Connections {
    target: root.look
    function onRetroChanged() {
      root.lineSweep = 0
      root.lineLook = root.look.retro
      if (root.surfaceOpen) lineSweeper.restart()
    }
  }
  onSurfaceOpenChanged: {
    if (!surfaceOpen) lineSweeper.stop()
    else if (lineSweep < rowRepeater.count) lineSweeper.restart()
  }
  readonly property bool hasNightsMap: nights !== null
  Timer {
    id: lineSweeper
    interval: 16
    repeat: true
    onTriggered: {
      root.lineSweep += 8
      if (root.lineSweep < rowRepeater.count) return
      root.lineSweep = root.everyRow
      stop()
    }
  }

  // The selected row's fill and outline, drawn here rather than by the row,
  // so it slides from the row it was on to the row clicked, on the switch's
  // beat, and then follows its row wherever the row goes: a scroll, a
  // neighbour's slide, an add or a removal. A lifted row draws its own. With
  // the row moving it lays the card's ground under it, as the row would,
  // just under that row.
  readonly property WatchlistRow featuredItem: rowRepeater.count >= 0 ? rowItem(featuredSymbol) : null
  property string highlightedSymbol: ""
  property real highlightShift: 0
  onFeaturedSymbolChanged: {
    var from = rowItem(highlightedSymbol)
    var to = rowItem(featuredSymbol)
    var was = from ? from.y + highlightShift : 0
    highlightedSymbol = featuredSymbol
    highlightSlide.stop()
    highlightShift = 0
    if (!seen || !from || !to || from === to || !from.visible || !to.visible || !from.inSight || !to.inSight || to.moving) return
    highlightShift = was - to.y
    highlightSlide.start()
  }
  NumberAnimation {
    id: highlightSlide
    target: root
    property: "highlightShift"
    to: 0
    duration: Motion.duration(Style, Motion.SWITCH_MS)
    easing.type: Easing.OutCubic
  }

  Item {
    id: rowsBox
    width: Math.max(0, root.width - root.gutter)
    height: root.implicitHeight

    Rectangle {
      id: highlight
      objectName: "rowHighlight"
      readonly property WatchlistRow row: root.featuredItem
      readonly property bool moving: !!row && row.moving
      visible: !!row && row.visible && row.highlighted
      // Under the rows at rest; under its own row alone while that moves.
      z: moving ? row.z - 0.25 : -1
      width: row ? row.width : 0
      height: row ? row.height : 0
      y: row ? row.y + (moving ? 0 : root.highlightShift) : 0
      opacity: row ? row.opacity : 1
      radius: root.look.retro ? 0 : Style.cornerRadius
      color: Style.selectedFillFor(root.look.foreground, Commons.Color.accent)
      border.width: row && row.cursor ? Style.hoverBorderWidth : 0
      border.color: Style.hoverBorderFor(root.look.foreground, Commons.Color.accent)
      Behavior on color { ColorAnimation { duration: Motion.duration(Style, 60) } }

      Rectangle {
        z: -1
        anchors.fill: parent
        radius: parent.radius
        visible: highlight.moving
        color: root.look.ground
      }
    }

    Repeater {
      id: rowRepeater
      model: rowsModel

      WatchlistRow {
        id: rowDelegate
        calendars: root.calendars
        sorting: root.sorting
        place: root.reorder.slotOf(symbol)
        visible: place >= 0 || folding
        onFoldEnded: Qt.callLater(root.releaseFolded)
        pitch: root.rowPitch
        liftedY: root.reorder.liftedY
        rowCount: rowRepeater.count
        onRested: root.rowRested(symbol)
        look: root.look
        width: parent.width
        required property int index
        Binding on lineRetro {
          value: root.lineLook
          when: rowDelegate.built || rowDelegate.index < root.lineSweep
          restoreMode: Binding.RestoreNone
        }
        // Whether the row lies within `above` and `below` of the view at
        // `top`. From its place, not `y`, which a new place may not have
        // reached yet; a folding row's is where it folds.
        function near(top, above, below) {
          var at = folding ? foldY : place * pitch + shift
          return (place >= 0 || folding) && at + height > top - above && at < top + root.sightHeight + below
        }
        readonly property bool inSight: lifted || near(root.contentY, root.rowPitch, root.rowPitch)
        // Words and pointer built within a screen of where the list rests or
        // is headed, so a page's step finds them built, and for the rows a
        // glide shows on its way, not those it passes over.
        built: inSight || near(root.headedY, root.sightHeight, root.sightHeight)
        inView: inSight && root.surfaceOpen && root.seen
        menuCovers: root.menuCovers > 0 ? root.menuCovers - (y - root.contentY) : 0
        // A row out of sight, or hidden by a list, keeps the quote, night and
        // day it showed, so answers repaint and work out only rows in sight
        // whose own inputs changed; it takes the latest before the frame it
        // comes into sight. Ternaries short-circuit before reading the whole
        // maps when `when` is false, since Qt 6 still evaluates `value`.
        property var sightQuote: null
        Binding on sightQuote {
          value: rowDelegate.inSight ? (root.quotes[rowDelegate.symbol] || null) : null
          when: rowDelegate.inSight && !rowDelegate.folding
          restoreMode: Binding.RestoreNone
        }
        quote: sightQuote
        property var sightNight: null
        Binding on sightNight {
          value: rowDelegate.inSight && root.nights ? (root.nights[rowDelegate.symbol] || null) : null
          when: rowDelegate.inSight && !rowDelegate.folding
          restoreMode: Binding.RestoreNone
        }
        // Out of sight, the day it has, so leaving sight changes nothing.
        // Bound to per-row `quote` and `sightNight` rather than `root.quotes`
        // and `root.nights`, so off-screen updates never rebuild visible rows.
        property var sightDay: null
        Binding on sightDay {
          value: !rowDelegate.inSight ? null
            : rowDelegate.quote ? Chart.lineDay(rowDelegate.symbol, rowDelegate.quote,
                root.hasNightsMap ? (rowDelegate.sightNight ? ({ [rowDelegate.symbol]: rowDelegate.sightNight }) : ({})) : null,
                root.calendars, root.dayClock)
            : null
          when: rowDelegate.inSight && !rowDelegate.folding
          restoreMode: Binding.RestoreNone
        }
        day: sightDay
        // Read once for both, and only while in sight: off-screen rows skip
        // map reads on every live trade.
        property var sightNewestTrade: null
        Binding on sightNewestTrade {
          value: rowDelegate.inSight ? (root.newestTrades[rowDelegate.symbol] || null) : null
          when: rowDelegate.inSight && !rowDelegate.folding
          restoreMode: Binding.RestoreNone
        }
        readonly property var newestTrade: sightNewestTrade
        // Only rows in sight follow the scrub, or each step repaints every
        // row; each reads its own line, where its dot sits. At rest a new
        // line, as a refresh brings, leaves the figures be.
        readonly property int sightScrub: inSight ? root.scrubShown : 0
        // A folding row keeps what it showed: its stock has left the list.
        Binding on view {
          value: rowDelegate.inSight && rowDelegate.quote ? Figures.listRow(rowDelegate.quote, root.changeMode, rowDelegate.newestTrade,
            rowDelegate.sightScrub ? rowDelegate.day : null, rowDelegate.sightScrub) : null
          when: rowDelegate.inSight && !rowDelegate.folding
          restoreMode: Binding.RestoreNone
        }
        Binding on status {
          value: rowDelegate.inSight ? (root.entryOf(rowDelegate.symbol) ? root.entryOf(rowDelegate.symbol).status : "loading") : "loading"
          when: rowDelegate.inSight && !rowDelegate.folding
          restoreMode: Binding.RestoreNone
        }
        // Freshness reads the clock every second: only rows in sight do, using
        // the row's own quote and newest trade rather than re-indexing the maps.
        Binding on freshness {
          value: rowDelegate.inSight ? root.freshnessOf(rowDelegate.symbol, rowDelegate.quote, rowDelegate.newestTrade) : null
          when: rowDelegate.inSight && !rowDelegate.folding
          restoreMode: Binding.RestoreNone
        }
        Binding on newestOld {
          value: rowDelegate.inSight ? Figures.newestStale(rowDelegate.view ? rowDelegate.view.newest : null, root.now) : false
          when: rowDelegate.inSight && !rowDelegate.folding
          restoreMode: Binding.RestoreNone
        }
        overnightList: root.overnightList
        minuteNow: rowDelegate.inSight && root.overnightList ? root.minuteNow : 0
        sourceDown: root.sourceDown
        featuredRow: symbol === root.featuredSymbol
        cursor: symbol === root.cursorRow
        // Only a cursor of your own shows the remove button, not the resting one.
        removable: symbol === root.cursorRow && symbol === root.cursorSymbol && symbol !== root.scrolledUnder
          && root.reorder.lifted === ""
        lifted: symbol === root.reorder.lifted
        scrubX: day && sightScrub ? Chart.tradeFraction(day, sightScrub) : -1
        onFeatureRequested: function(x, y, second) { if (root.clickRow(symbol, x, y, second)) root.featureRequested(symbol) }
        onMenuRequested: function(x, y, second) { if (root.clickRow(symbol, x, y, second)) root.menuRequested(symbol, x, y) }
        onRemovePressed: function(x, y, second) { root.removeArmed = root.clickCounts(x, y, second) ? symbol : "" }
        onRemoveReleased: function(x, y) {
          var armed = root.removeArmed === symbol
          root.removeArmed = ""
          if (root.takeClick(symbol, x, y, armed)) root.removeRequested(symbol)
        }
        onListsRequested: function(x, y, second) { if (root.clickRow(symbol, x, y, second)) root.listsRequested(symbol) }
        onDragStarted: function(y) { root.beginDrag(symbol, y) }
        onDragMoved: function(y) { root.reorder.moveTo(y) }
        onDragEnded: root.reorder.end()
        onDragCanceled: root.reorder.cancel()
      }
    }
  }
}
