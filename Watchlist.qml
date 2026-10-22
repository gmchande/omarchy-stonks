pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Settings.js" as Settings
import "Tones.js" as Tones
// The scrolling rows. Owns identity, drag, cursor, scroll-to-row, and the
// wheel. Surfaces pass data in and persist the signals. The rows stop short
// of the right edge by one gutter, which is where the scrollbar lives, so a
// thumb never sits on a row. There is one row for every symbol in All, kept
// across lists: a list shows its members and hides the rest, so a switch
// builds nothing.
Flickable {
  id: root

  // The service's view: the list and its key, its order and direction, its
  // rows, those rows sorted, and All. It arrives whole, so one comparison
  // with the last says what changed.
  // Handlers read it, never a binding derived from it, which may not have
  // caught up when they run.
  property var view: ({ list: "", listKey: "=", order: "manual", reversed: false, rows: [], shown: [], library: [] })
  property var quotes: ({})
  property var entries: ({})
  property string featuredSymbol: ""
  property int scrubShown: 0
  property string changeMode: "pct"
  property int now: 0
  property var owed: ({})
  property bool retro: false
  // The exchanges' calendars, for the breaks in a row's day line.
  property var calendars: null
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color dimmer: Tones.dimmer(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.space(40)
  property int rowGap: Style.space(2)
  property int gutter: Style.space(8)
  // A closed or closing surface: a pointer moving over it moves no cursor.
  property bool surfaceOpen: true
  // The card's own colour, which a moving row carries under its fill.
  property color ground: "transparent"
  // The rows' own view height, as it is while they show: the list's own
  // height unless the surface says otherwise. The popup's card shrinks to
  // the key sheet or a view, and the list with it, while its rows are
  // hidden; sight is judged against the rows' view all the same.
  property real sightHeight: height
  // Down to here in the view, the list menu lies over the rows: a row that
  // starts above it leaves out its words (`WatchlistRow.wordsShown`). 0
  // while the menu is shut.
  property real menuCovers: 0

  property string cursorSymbol: ""
  // The row the wheel scrolled under a still pointer: it takes the cursor,
  // but its remove button waits for the pointer to really move or a key to
  // move the cursor, so a click there features it. The button sits after
  // the symbol, wherever its length puts it, so a notch could bring it
  // under the pointer: in the edge pass of 15 October the click meant to
  // feature 7203.T removed it.
  property string scrolledUnder: ""
  property var displayedSymbols: []
  property string dragSymbol: ""
  property real dragY: 0
  property int dragTarget: -1
  property real dragOffset: 0
  // The view the rows were last arranged for.
  property var arrangedView: null

  readonly property int rowPitch: rowHeight + rowGap
  // Where the list is headed: a glide's destination, or where it rests.
  readonly property real headedY: glide.running ? glide.to : contentY
  // The one cursor the keys and the pointer both move, as in the shell's own
  // panels. Moving the pointer puts it on the row under it, the wheel on the
  // row it brings under a still pointer, and a key one row on from wherever
  // it is; the pointer leaving the list leaves it there. Always a row in
  // sight, so a key never acts on a row you cannot see: a cursor of your own
  // stays while any of its row is in sight; without one (on open, after
  // another list) it sits on the featured row when that is in sight, else on
  // the first whole row in sight. Read where the list is headed, so a key
  // gliding the list to its row keeps it.
  readonly property string cursorRow: {
    var top = headedY
    if (ownInSight(top)) return cursorSymbol
    var hero = displayedSymbols.indexOf(featuredSymbol)
    if (hero >= 0 && wholeInSight(hero, top)) return featuredSymbol
    var first = Math.max(0, Math.ceil((top - 0.5) / rowPitch))
    return displayedSymbols[Math.min(first, displayedSymbols.length - 1)] || ""
  }
  // A cursor of your own that leaves sight, as the scrollbar moves the
  // list, the rows change under it, or a sort carries it off, is let go:
  // the cursor moves by the rule above and stays there when the row comes
  // back. Let go as the sight changes, not as cursorRow does: it reads the
  // cursor it would clear. Sight is the rows' own view (`sightHeight`), as
  // it is while they show: the popup's card shrinks to the key sheet or a
  // view, and the list with it, and that is no scroll of yours. The
  // surface made shorter is no scroll of yours either: the list scrolls to
  // keep the cursor's row whole in sight (keepCursorInSight).
  onHeadedYChanged: letGoUnseen()
  onSightHeightChanged: keepCursorInSight()
  onDisplayedSymbolsChanged: letGoUnseen()
  // A lifted row rides the pointer wherever its place has scrolled to, so
  // it keeps the cursor through the drag.
  function ownInSight(top) {
    if (cursorSymbol !== "" && cursorSymbol === dragSymbol) return true
    var own = displayedSymbols.indexOf(cursorSymbol)
    return cursorSymbol !== "" && own >= 0 && partInSight(own, top)
  }
  function letGoUnseen() {
    if (cursorSymbol !== "" && !ownInSight(headedY)) cursorSymbol = ""
  }
  // The surface made shorter keeps the cursor's row: the list scrolls at
  // once, as the edge moves, so it stays whole in sight. A cursor of your
  // own, so the keys go on from where you left them, from where a key's
  // glide was headed too: stopping the glide must not let it go on the
  // way. Without one, the featured row it rests on, when that was whole in
  // the sight before: a window settles through a size or two as it opens,
  // and the featured row an open brought into sight stays there. Found in
  // the walk of dev on 14 October (a shorter window moved a key cursor to
  // the row still showing) and the tophat of 15 October (a window opening
  // at 760, then 850, then 800 px tall lost the featured row).
  property real lastSight: 0
  function keepCursorInSight() {
    var keep = cursorSymbol !== "" ? (cursorSymbol !== dragSymbol ? cursorSymbol : "")
      : featuredSymbol
    var at = displayedSymbols.indexOf(keep)
    if (keep !== "" && cursorSymbol === "" && !(at >= 0 && wholeInSightOf(at, headedY, lastSight))) at = -1
    if (at >= 0 && sightHeight >= rowHeight && !wholeInSight(at, headedY)) {
      var own = cursorSymbol
      var to = restingTopFor(at, headedY)
      takeOver()
      contentY = to
      cursorSymbol = own
    }
    lastSight = sightHeight
    letGoUnseen()
  }
  // The rows hold their order under the pointer, a drag, or the row's
  // menu, which takes the pointer's hover from the list while it is open.
  property bool held: false
  readonly property bool sortHeld: listHover.hovered || dragSymbol !== "" || held
  readonly property bool manualOrder: view.order === "manual"

  signal featureRequested(string symbol)
  signal removeRequested(string symbol)
  // A right-click on a row, at (x, y) in the scene.
  signal menuRequested(string symbol, real x, real y)
  signal listsRequested(string symbol)
  signal manualOrderRequested(var symbols)
  // A drag, or J or K, asked to move a row while a sorted order shows,
  // where rows don't move by hand: the surface says why.
  signal moveRefused()
  // The rows show the latest view.
  signal arranged()
  // A row's slide or fade has ended.
  signal rowRested(string symbol)

  implicitHeight: Math.max(0, displayedSymbols.length * rowPitch - rowGap)
  contentWidth: width
  contentHeight: implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  interactive: contentHeight > height
  // A drag or a flick takes the list over from the wheel, and settles it
  // the way it always has.
  onMovementStarted: takeOver()
  onMovementEnded: snapToRow()
  ScrollBar.vertical: ScrollBar {
    policy: ScrollBar.AsNeeded
    visible: root.interactive
    active: root.interactive
    // At least 24 px long, so a long list's thumb is there to see and grab:
    // at the window's smallest, one row of nine drew it 9 px.
    minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
    onPressedChanged: if (!pressed) root.snapToRow()
  }

  // Touchpad scrolling reaches this handler too (its events are marked as
  // system-synthesized, which a WheelHandler ignores unless it accepts the
  // touchpad), so the finger and the wheel settle through the same glide.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
      // The wheel starts another gesture: the next click is a click of its own.
      root.endClick()
      var from = root.headedY
      // A touchpad reports the pixels the finger moved: the list follows
      // them exactly, and settles on a row once the finger stops.
      if (event.pixelDelta.y !== 0) root.followBy(-event.pixelDelta.y)
      // A notch is 120 units and one row; a high-resolution mouse sends many
      // smaller ticks, and each moves its fraction of a row.
      else if (event.angleDelta.y !== 0) root.wheelBy(-event.angleDelta.y / 120)
      else { event.accepted = false; return }
      root.pointAtPointer(root.headedY !== from)
    }
  }

  // The wheel glides the list rather than setting it, so a stream of small
  // ticks reads as motion instead of steps, and settles on a row boundary
  // once the wheel goes quiet. Snapping every tick is what made it lurch.
  NumberAnimation {
    id: glide
    target: root
    property: "contentY"
    duration: 160
    easing.type: Easing.OutCubic
  }

  // Comfortably past the glide, so a stream of ticks never snaps mid-scroll.
  Timer {
    id: wheelQuiet
    interval: 260
    onTriggered: {
      var from = root.headedY
      root.glideTo(root.snappedY(root.wheelTarget()))
      root.pointAtPointer(root.headedY !== from)
    }
  }

  RowPointer {
    id: listHover
    parent: root
    onMoved: function(x, y) {
      if (!root.surfaceOpen) return
      root.scrolledUnder = ""
      root.pointAt(x, y)
    }
  }

  // The cursor to the row at (x, y) in the scene, read where the list is
  // headed, as the cursor always is: mid-glide, that is the row that will
  // rest under the pointer. Past the rows' ends, or on the scrollbar's
  // gutter, it stays. A lifted row is the drag's, so the pointer moves no
  // cursor then. Says whether it put the cursor on a row.
  function pointAt(x, y) {
    var seen = mapFromItem(null, x, y)
    if (dragSymbol !== "" || seen.x >= rowsBox.width) return false
    var at = Math.floor((seen.y + headedY) / rowPitch)
    if (at < 0 || at >= displayedSymbols.length) return false
    cursorSymbol = displayedSymbols[at]
    return true
  }

  // The cursor to the row the wheel brings under a still pointer: the row
  // that will rest there, so the bar never stops on a row on the way. When
  // the list `scrolled`, that row is scrolledUnder.
  function pointAtPointer(scrolled) {
    if (listHover.hovered && surfaceOpen && pointAt(listHover.scenePosition.x, listHover.scenePosition.y) && scrolled)
      scrolledUnder = cursorSymbol
  }

  function entryOf(symbol) {
    return entries && entries[symbol] ? entries[symbol] : null
  }

  function freshnessOf(symbol) {
    return Figures.freshness(entryOf(symbol), quotes[symbol] || null, now, owed[symbol] || 0)
  }

  function moveCursor(delta) {
    endClick()
    if (displayedSymbols.length === 0) return
    var current = displayedSymbols.indexOf(cursorRow)
    var next = Math.max(0, Math.min(displayedSymbols.length - 1, current < 0 ? 0 : current + delta))
    select(displayedSymbols[next])
  }

  function clampY(y) {
    return Math.max(0, Math.min(Math.max(0, contentHeight - height), y))
  }

  function snappedY(y) {
    return clampY(Math.round(y / rowPitch) * rowPitch)
  }

  function snapToRow() {
    takeOver()
    contentY = snappedY(contentY)
  }

  // True while the list is still on its way to where it will rest: a glide,
  // the wheel's settle still to come, or a flick. A glide the wheel stops and
  // restarts in one turn passes through false, so a reader waits a turn.
  readonly property bool settling: glide.running || wheelQuiet.running || moving

  // Something other than the wheel now owns the list's position: a lifted
  // row, the keyboard, a flick, the scrollbar. The wheel's glide and its
  // pending settle both stop, so neither moves the list underneath it.
  function takeOver() {
    glide.stop()
    wheelQuiet.stop()
  }

  // Where the wheel has the list headed: its glide's destination, or where
  // it is resting.
  function wheelTarget() {
    return glide.running ? glide.to : contentY
  }

  function wheelBy(rows) {
    glideTo(wheelTarget() + rows * rowPitch)
    wheelQuiet.restart()
  }

  // The touchpad's pixels move the list directly; the same quiet timer then
  // glides it onto a row.
  function followBy(pixels) {
    glide.stop()
    contentY = clampY(contentY + pixels)
    wheelQuiet.restart()
  }

  function glideTo(y) {
    var target = clampY(y)
    glide.stop()
    if (target === contentY) return
    glide.from = contentY
    glide.to = target
    glide.start()
  }

  // The list glides, as the wheel glides it, to rest on a row boundary with
  // row `index` whole in view: never a jump, and never left between rows.
  // Rows moving at the same time slide with it, so none jumps on screen.
  function scrollToRow(index) {
    wheelQuiet.stop()
    var y = index * rowPitch
    var at = wheelTarget()
    if (y < at) at = y
    else if (y + rowHeight > at + height) at = y + rowHeight - height
    glideTo(snappedY(at))
  }

  // The cursor on a shown row, carried into view.
  // The list heads for the row first, so the cursor is set on a row in
  // sight. Put there by a key, or what the keys do, it shows its remove
  // button.
  function select(symbol) {
    var index = displayedSymbols.indexOf(symbol)
    if (index < 0) return
    scrollToRow(index)
    cursorSymbol = symbol
    scrolledUnder = ""
  }

  // The cursor handed to `symbol`, as a removal hands it on: where its row
  // is in sight already, the list stays where it is, stopped by the click,
  // perhaps between rows; else the row is carried into view.
  function handTo(symbol) {
    var index = displayedSymbols.indexOf(symbol)
    if (index >= 0 && partInSight(index, headedY)) cursorSymbol = symbol
    else select(symbol)
  }

  // A click on a row, at (x, y) in the scene. It stops the list where it
  // is, a glide or a touchpad's settle, as a flicking list stops under a
  // finger, and puts the cursor on the row, now in sight where the list
  // rests: the row stays under the pointer, and x or Enter act on it.
  // Gliding it whole into view or onto a row boundary instead moved it out
  // from under the pointer. And a double-click is one click, for the list
  // as for a row: a click within the double-click interval of the last,
  // at its place, does nothing, whatever button and whichever row is under
  // it by then, as the one sliding up into a removed row's place.
  // Says whether the click acts. The wheel, a key, or a move of a row
  // starts another gesture, so the next click acts (endClick), even one Qt
  // takes for a double-click's `second` press, as long as that pair's first
  // press was this list's last click. Any other second press does nothing,
  // wherever its first landed: on this row, on the one a removal took
  // away, or on a view or a search result the rows came back from under.
  // Another list, a new open, or the rows hidden behind a view forget the
  // last click (forgetClicks), so the next single click acts.
  property real lastClickTime: 0
  property point lastClickPlace: Qt.point(-1, -1)
  // This list's last click, and the last gesture that ended its window.
  property real rowClickAt: 0
  property real clickEndedAt: 0
  function clickRow(symbol, x, y, second) {
    return takeClick(symbol, x, y, clickCounts(x, y, second))
  }
  // Whether a click at (x, y) now acts, by the rule above; it changes
  // nothing, so a press can ask and keep the answer until its release.
  function clickCounts(x, y, second) {
    var now = Date.now()
    var interval = Application.styleHints.mouseDoubleClickInterval
    var near = Application.styleHints.startDragDistance
    return second ? clickEndedAt >= rowClickAt && clickEndedAt > 0 && now - rowClickAt < interval
      : !(now - lastClickTime < interval
        && Math.abs(x - lastClickPlace.x) <= near && Math.abs(y - lastClickPlace.y) <= near)
  }
  // A click on `symbol`'s row at (x, y) is this list's last; when it
  // `counts`, it stops the list and puts the cursor on its row. Says
  // whether it acts. Under a pointer still since the wheel scrolled the
  // rows, the row it stops on waits for a move to show its remove button
  // too: mid-glide, that is not the row the glide was headed for. Found in
  // review: a click 30 ms into a glide showed the stopped row's at once.
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
  // A press on a row's remove button asks at the press whether its click
  // counts, a double-click's second press too, and the release on the
  // button acts on that answer, however long it was held.
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
  // The rows shown again, behind a view or the key sheet before: the pointer
  // resting over them is no move (RowPointer.rest).
  onVisibleChanged: {
    forgetClicks()
    if (visible) listHover.rest()
  }

  // Whether row `index` is whole in the list's view with it scrolled to
  // `top`. The card's edge easing past the foot is left out: the cursor
  // follows the scroll, not a moment of the card's motion.
  function wholeInSight(index, top) {
    return wholeInSightOf(index, top, sightHeight)
  }
  function wholeInSightOf(index, top, sight) {
    var y = index * rowPitch
    return y >= top - 0.5 && y + rowHeight <= top + sight + 0.5
  }

  // Whether any of row `index` shows, with the list scrolled to `top`: the
  // pointer may rest on a row the list's foot cuts.
  function partInSight(index, top) {
    var y = index * rowPitch
    return y + rowHeight > top + 0.5 && y < top + sightHeight - 0.5
  }

  // The rows any of which shows where the list is headed, top first, for
  // the service to fetch their charts ahead on a range. Read from row
  // numbers, so it changes only as a row crosses the sight's edge.
  readonly property int sightFirst: Math.max(0, Math.floor((headedY + 0.5 - rowHeight) / rowPitch) + 1)
  readonly property int sightLast: Math.ceil((headedY + sightHeight - 0.5) / rowPitch) - 1
  readonly property var sightSymbols: displayedSymbols.slice(sightFirst, Math.max(sightFirst, sightLast + 1))

  // The nearest place to `top`, on a row boundary, where row `index` is
  // whole in sight: a row above comes in at the top, one below at the foot.
  // Bounded by the sight, not the list's own height: as a window gets
  // shorter the sight can change a moment before the height does, and a
  // bound read from the old height held the row out of sight. Found in the
  // tophat of 15 October: the key cursor on the last row was let go.
  function restingTopFor(index, top) {
    var y = index * rowPitch
    var bottom = Math.max(0, contentHeight - sightHeight)
    if (y < top) return Math.min(bottom, y)
    if (y + rowHeight > top + sightHeight) return Math.min(bottom, Math.ceil((y + rowHeight - sightHeight) / rowPitch) * rowPitch)
    return top
  }

  // Shows `next`. Rows never draw through each other: when `animate`, a
  // symbol new to the shown rows joins, fading in at its place as its day
  // line draws in, and rows already shown slide (see the delegate). A list
  // that gets shorter at its end, scrolled to it, has its scroll pulled back
  // within its new length; the rows keep their places on screen through
  // that, and the ones above the gap slide down to close it.
  function display(next, animate) {
    var before = displayedSymbols
    var scrolled = contentY
    displayedSymbols = next
    contentY = clampY(contentY)
    if (glide.running && glide.to > clampY(glide.to)) glideTo(glide.to)
    if (!animate || !visible) return
    for (var i = 0; i < next.length; i++) {
      var row = before.indexOf(next[i]) < 0 ? rowItem(next[i]) : null
      if (row) row.join()
    }
    var pulled = scrolled - contentY
    if (pulled <= 0) return
    for (var j = 0; j < next.length; j++) {
      var shownRow = rowItem(next[j])
      if (shownRow) shownRow.carry(pulled)
    }
  }

  // Closing stops each row's slide, fade, and draw-in where they are, so the
  // surface fades out as it was; settleRows puts them at rest before it
  // opens again.
  function pauseRows() {
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) row.pause()
    }
  }

  // A slide, fade, or draw-in still running when a new arrangement lands
  // ends where it was going, before anything is drawn.
  function settleRows() {
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) row.settle()
    }
  }

  function forgetGoneCursor() {
    if (cursorSymbol && view.rows.indexOf(cursorSymbol) < 0) cursorSymbol = ""
  }

  function applyShown() {
    display(view.shown.slice(), true)
    forgetGoneCursor()
  }

  // Holding freezes positions, not membership: a symbol that leaves goes at
  // once, and one whose place is new, added or brought back, takes its
  // sorted place and joins there, so it stays put when the hold ends.
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

  // Whether the row shown for `symbol` is still: not sliding, fading, or held.
  function rowResting(symbol) {
    var row = rowItem(symbol)
    return !!row && row.place >= 0 && row.resting
  }

  // Rows use the held projection while the pointer is in the list.
  function slotOf(symbol) {
    var i = displayedSymbols.indexOf(symbol)
    if (dragSymbol === "") return i
    var from = displayedSymbols.indexOf(dragSymbol)
    if (from < dragTarget && i > from && i <= dragTarget) return i - 1
    if (dragTarget < from && i >= dragTarget && i < from) return i + 1
    return i
  }

  // The pointer's height in the view while a row is lifted, so the row
  // stays under it when the wheel scrolls the list beneath.
  property real dragPointer: 0
  onContentYChanged: if (dragSymbol !== "" && !dropAnim.running) dragTo(dragPointer + contentY)

  function beginDrag(symbol, y) {
    if (!manualOrder) { moveRefused(); return }
    var from = displayedSymbols.indexOf(symbol)
    if (from < 0) return
    takeOver()
    dropAnim.stop()
    cursorSymbol = symbol
    dragOffset = y - from * rowPitch
    dragPointer = y - contentY
    dragY = from * rowPitch
    dragTarget = from
    dragSymbol = symbol
  }

  function dragTo(y) {
    if (dragSymbol === "") return
    dragPointer = y - contentY
    dragY = Math.max(0, Math.min((displayedSymbols.length - 1) * rowPitch, y - dragOffset))
    dragTarget = Math.round(dragY / rowPitch)
  }

  function endDrag() {
    var from = displayedSymbols.indexOf(dragSymbol)
    var to = dragTarget
    if (from < 0 || to < 0) { cancelDrag(); return }
    if (from !== to) root.commitManualOrder(Settings.movedSymbols(displayedSymbols, from, to))
    dropAnim.to = to * rowPitch
    dropAnim.start()
  }

  // The drag is over; the list, which the lifted row took from the wheel,
  // settles on a row.
  function cancelDrag() {
    dropAnim.stop()
    if (dragSymbol === "") return
    dragSymbol = ""
    glideTo(snappedY(contentY))
  }

  // Closing mid-drag: the drag ends and every row, the lifted one too, stays
  // where it is on screen, still, until the next open settles them.
  function releaseDragInPlace() {
    if (dragSymbol === "") return
    var rows = []
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) rows.push({ row: row, y: row.y })
    }
    dropAnim.stop()
    dragSymbol = ""
    rows.forEach(function(r) { r.row.holdAt(r.y) })
  }

  // Another list, another order, or an opening surface is a new
  // arrangement, not a resort under the pointer: thirty rows re-ranking at
  // once explain nothing, so they take their places at once. Another list
  // goes back to where it was left (`places`), the top on its first visit;
  // the same list in a new order keeps its scroll.
  function layOut() {
    display(view.shown.slice(), false)
    settleRows()
    forgetGoneCursor()
  }

  // Where each list was scrolled to when this surface last left it, by the
  // list's key (`Service.listKey`), for the session: a renamed list keeps
  // its place, and a new list under a freed name starts at the top.
  property var places: ({})

  ListModel { id: rowsModel }
  onViewChanged: {
    var before = arrangedView
    arrangedView = view
    if (!before) return
    if (before.library.join() !== view.library.join()) syncRows()
    // A rename keeps the list's key; only another list is a switch. A
    // closed surface's view does not change (StonksBody holds it), so this
    // runs only while it is open, or as it opens, before the open's reopen().
    var switched = view.listKey !== before.listKey
    if (switched) {
      places[before.listKey] = snappedY(wheelTarget())
      cancelDrag()
      cursorSymbol = ""
      forgetClicks()
      takeOver()
      layOut()
      contentY = clampY(places[view.listKey] || 0)
    } else if (view.order !== before.order || view.reversed !== before.reversed) {
      // A row held mid-drag has no manual place to drop into any more.
      cancelDrag()
      layOut()
    } else if (sortHeld) {
      applyMembership()
    } else {
      applyShown()
    }
    arranged()
  }
  onSortHeldChanged: if (!sortHeld && surfaceOpen) applyShown()

  // As the surface opens: the rows in the service's order, at rest, and no
  // cursor of the last visit's, so it rests on the featured row until you
  // point or press a key. The featured row is brought into sight at once,
  // so that cursor is the row the hero shows and Enter or x act on it.
  // Found in the walk of dev on 14 October: featured from the pill below
  // the fold, the popup opened with the cursor on its top row, and Enter
  // featured that.
  function reopen() {
    cursorSymbol = ""
    forgetClicks()
    listHover.rest()
    layOut()
    var hero = displayedSymbols.indexOf(featuredSymbol)
    if (hero >= 0 && !wholeInSight(hero, contentY)) {
      takeOver()
      contentY = restingTopFor(hero, contentY)
    }
  }
  Component.onCompleted: {
    arrangedView = view
    syncRows()
    display(view.shown.slice(), false)
  }

  function syncRows() {
    var library = view.library
    for (var i = rowsModel.count - 1; i >= 0; i--) {
      if (library.indexOf(rowsModel.get(i).symbol) < 0) rowsModel.remove(i)
    }
    for (var j = 0; j < library.length; j++) {
      var found = false
      for (var k = 0; k < rowsModel.count; k++) if (rowsModel.get(k).symbol === library[j]) found = true
      if (!found) rowsModel.append({ symbol: library[j] })
    }
  }

  NumberAnimation {
    id: dropAnim
    target: root
    property: "dragY"
    duration: 160
    easing.type: Easing.OutCubic
    onFinished: root.cancelDrag()
  }

  Item {
    id: rowsBox
    width: Math.max(0, root.width - root.gutter)
    height: root.implicitHeight

    Repeater {
      id: rowRepeater
      model: rowsModel

      WatchlistRow {
        id: rowDelegate
        calendars: root.calendars
        readonly property int place: root.slotOf(symbol)
        // A symbol outside this list keeps its row, hidden.
        visible: place >= 0
        y: lifted ? root.dragY : place * root.rowPitch + shift
        // A row slides only if it was in sight before and after the change,
        // so one that joins starts at its own place: it had no place before
        // (`lastPlace` -1), and a row in a hidden list is not in sight now.
        // It slides by easing `shift`, how far it still is from its place, to
        // zero, so a new change mid-slide carries on from where the row is. A
        // moving row carries the card's ground; the one travelling farther
        // rides on top, and the cursor's row wins a tie, so no two rows print
        // through.
        property int lastPlace: -1
        property real shift: 0
        property int travel: 0
        onPlaceChanged: {
          var from = lastPlace
          lastPlace = place
          if (lifted || !visible || from < 0 || place < 0) {
            settle()
            return
          }
          travel = Math.abs(place - from)
          shift += (from - place) * root.rowPitch
          slide.restart()
        }
        NumberAnimation { id: slide; target: rowDelegate; property: "shift"; to: 0; duration: 160; easing.type: Easing.OutCubic }
        moving: lifted || slide.running
        ground: root.ground
        z: lifted ? rowRepeater.count + 2 : (slide.running ? 1 + travel + (cursor ? 0.5 : 0) : 0)
        readonly property bool resting: !slide.running && !fadeIn.running && !lifted
        onRestingChanged: if (resting) root.rowRested(symbol)
        function settle() {
          slide.stop()
          shift = 0
          travel = 0
          fadeIn.stop()
          opacity = 1
          drawIn.stop()
          reveal = 1
          lineOwed = false
        }
        function pause() {
          if (slide.running) slide.pause()
          if (fadeIn.running) fadeIn.pause()
          if (drawIn.running) drawIn.pause()
        }
        // Stays at `atY` on screen, still: the slide it would start ends here.
        function holdAt(atY) {
          if (place < 0) return
          slide.stop()
          shift = atY - place * root.rowPitch
        }
        // Joining, the row fades in and its day line draws in from the left
        // in the hero's 320 ms, the baseline whole from the start. A row
        // that joins before its line is there owes the draw-in: a line that
        // comes while the row still fades in draws in from its start, and
        // one that comes later is there at once, the join being over.
        property bool lineOwed: false
        function join() {
          opacity = 0
          fadeIn.restart()
          lineOwed = !geometry
          if (geometry) drawLineIn()
        }
        function drawLineIn() {
          reveal = 0
          drawIn.restart()
        }
        onGeometryChanged: {
          if (!lineOwed || !geometry) return
          lineOwed = false
          if (fadeIn.running && !fadeIn.paused) drawLineIn()
        }
        // Keeps the row where it is on screen while the list's scroll moves
        // by `distance` under it, then slides it to its place.
        function carry(distance) {
          shift -= distance
          if (Math.abs(shift) < 0.5) {
            slide.stop()
            shift = 0
            travel = 0
            return
          }
          travel = Math.max(travel, Math.round(Math.abs(shift) / root.rowPitch))
          slide.restart()
        }
        NumberAnimation { id: fadeIn; target: rowDelegate; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { id: drawIn; target: rowDelegate; property: "reveal"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
        width: parent.width
        // A row outside this list rests: no figures derived, nothing drawn.
        // Shown again, it takes its quote and draws before that frame. A row
        // of the list out of sight, more than a row past the edge of the
        // view, keeps the quote it last showed, so a run's answers derive
        // and repaint only the rows in sight; it takes the latest as it
        // comes into sight, and draws it before that frame.
        readonly property bool inSight: lifted || (y + height > root.contentY - root.rowPitch
          && y < root.contentY + root.sightHeight + root.rowPitch)
        // A row of the list has its words and pointer built within a screen
        // of the view, above and below, so a wheel's glide or a page's step
        // finds them built; farther off, or outside this list, it holds its
        // place and its day line only.
        built: lifted || (place >= 0 && y + height > root.contentY - root.sightHeight
          && y < root.contentY + 2 * root.sightHeight)
        menuCovers: root.menuCovers > 0 ? root.menuCovers - (y - root.contentY) : 0
        property var sightQuote: null
        Binding on sightQuote {
          value: rowDelegate.place >= 0 ? root.quotes[rowDelegate.symbol] || null : null
          when: rowDelegate.place >= 0 && rowDelegate.inSight
          restoreMode: Binding.RestoreNone
        }
        quote: place >= 0 ? sightQuote : null
        view: quote ? Figures.rowModel(quote, root.scrubShown, root.changeMode) : null
        status: root.entryOf(symbol) ? root.entryOf(symbol).status : "loading"
        // Freshness reads the clock every second: only rows in sight do.
        freshness: place >= 0 && inSight ? root.freshnessOf(symbol) : null
        featuredRow: symbol === root.featuredSymbol
        cursor: symbol === root.cursorRow
        // A cursor of your own, not the resting one nor one the wheel
        // scrolled under a still pointer, and no row lifted.
        removable: symbol === root.cursorRow && symbol === root.cursorSymbol && symbol !== root.scrolledUnder
          && root.dragSymbol === ""
        lifted: symbol === root.dragSymbol
        retro: root.retro
        scrubX: quote && root.scrubShown ? Chart.fractionAtTime(quote, root.scrubShown) : -1
        foreground: root.foreground
        dim: root.dim
        dimmer: root.dimmer
        upColor: root.upColor
        downColor: root.downColor
        fontFamily: root.fontFamily
        // A double-click's second press does nothing (clickRow), and a
        // click stops the list where it is and puts the cursor on its row.
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
        onDragMoved: function(y) { root.dragTo(y) }
        onDragEnded: root.endDrag()
        onDragCanceled: root.cancelDrag()
      }
    }
  }
}
