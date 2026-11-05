pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Settings.js" as Settings
import "Tones.js" as Tones
// The scrolling rows: cursor, drag, scroll and wheel. Surfaces pass data in
// and save what the signals ask. One row for each symbol in All: a list
// hides the rows it lacks, so a switch builds nothing.
Flickable {
  id: root

  // Arrives whole, so comparing it with the last says what changed.
  // Handlers read it, not a binding derived from it, which may lag behind.
  property var view: ({ list: "", listKey: "=", order: "manual", reversed: false, rows: [], shown: [], library: [] })
  property var quotes: ({})
  property var newestPrints: ({})
  // Robinhood's answers, by symbol.
  property var nights: ({})
  property var allDay: ({})
  property var entries: ({})
  property string featuredSymbol: ""
  property int scrubShown: 0
  property string changeMode: "pct"
  property int now: 0
  property var owed: ({})
  // Symbols asked to refresh under 2 s ago: freshness gives them grace.
  property var asking: ({})
  property bool retro: false
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
  // Closed or closing: a pointer moving over it moves no cursor.
  property bool surfaceOpen: true
  // The card's colour, under a moving row's fill.
  property color ground: "transparent"
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
  property string dragSymbol: ""
  property real dragY: 0
  property int dragTarget: -1
  property real dragOffset: 0
  property var arrangedView: null

  readonly property int rowPitch: rowHeight + rowGap
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
  readonly property string cursorRow: {
    var top = headedY
    if (ownInSight(top)) return cursorSymbol
    var hero = displayedSymbols.indexOf(featuredSymbol)
    if (hero >= 0 && wholeInSight(hero, top)) return featuredSymbol
    // Else the first whole row in sight: a key never acts on a row unseen.
    var first = Math.max(0, Math.ceil((top - 0.5) / rowPitch))
    return displayedSymbols[Math.min(first, displayedSymbols.length - 1)] || ""
  }
  // A cursor of your own that leaves sight is let go, on these changes
  // rather than on cursorRow's, which reads the cursor it would clear.
  onHeadedYChanged: letGoUnseen()
  onSightHeightChanged: keepCursorInSight()
  onDisplayedSymbolsChanged: letGoUnseen()
  function ownInSight(top) {
    if (cursorSymbol !== "" && cursorSymbol === dragSymbol) return true
    var own = displayedSymbols.indexOf(cursorSymbol)
    return cursorSymbol !== "" && own >= 0 && partInSight(own, top)
  }
  function letGoUnseen() {
    if (cursorSymbol !== "" && !ownInSight(headedY)) cursorSymbol = ""
  }
  property real lastSight: 0
  function keepCursorInSight() {
    var keep = cursorSymbol !== "" ? (cursorSymbol !== dragSymbol ? cursorSymbol : "")
      : featuredSymbol
    var at = displayedSymbols.indexOf(keep)
    // The featured row only if it was whole in sight before, so a resize
    // never pulls the list back to it.
    if (keep !== "" && cursorSymbol === "" && !(at >= 0 && wholeInSightOf(at, headedY, lastSight))) at = -1
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
  readonly property bool sortHeld: listHover.hovered || dragSymbol !== "" || held
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

  implicitHeight: rowsLength()
  contentWidth: width
  contentHeight: implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  interactive: contentHeight > height
  // A drag or a flick takes the list over from the wheel.
  onMovementStarted: takeOver()
  onMovementEnded: snapToRow()
  ScrollBar.vertical: ScrollBar {
    policy: ScrollBar.AsNeeded
    visible: root.interactive
    active: root.interactive
    minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
    onPressedChanged: if (!pressed) root.snapToRow()
  }

  // A WheelHandler ignores the touchpad's events unless it accepts TouchPad.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
      root.endClick()
      var from = root.headedY
      // A touchpad sends pixels, which the list follows exactly.
      if (event.pixelDelta.y !== 0) root.followBy(-event.pixelDelta.y)
      // A notch is 120 units and one row; a high-resolution mouse sends parts.
      else if (event.angleDelta.y !== 0) root.wheelBy(-event.angleDelta.y / 120)
      else { event.accepted = false; return }
      root.pointAtPointer(root.headedY !== from)
    }
  }

  // The wheel glides the list rather than stepping it: snapping every tick
  // lurches.
  NumberAnimation {
    id: glide
    target: root
    property: "contentY"
    duration: Style.duration(160)
    easing.type: Easing.Bezier
    easing.bezierCurve: Style.easeOut
  }

  // Longer than the glide, so a stream of ticks never snaps mid-scroll.
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

  // Read where the list is headed: mid-glide, the row that will rest under
  // the pointer.
  function pointAt(x, y) {
    var seen = mapFromItem(null, x, y)
    // A lifted row is the drag's, and the gutter the scrollbar's: neither
    // moves the cursor.
    if (dragSymbol !== "" || seen.x >= rowsBox.width) return false
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

  function freshnessOf(symbol) {
    return Figures.freshness(entryOf(symbol), quotes[symbol] || null, now, owed[symbol] || 0, !!asking[symbol], newestPrints[symbol] || null)
  }

  function moveCursor(delta) {
    endClick()
    if (displayedSymbols.length === 0) return
    var current = displayedSymbols.indexOf(cursorRow)
    var next = Math.max(0, Math.min(displayedSymbols.length - 1, current < 0 ? 0 : current + delta))
    select(displayedSymbols[next])
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

  // A glide the wheel stops and restarts in one turn passes through false,
  // so a reader waits a turn.
  readonly property bool settling: glide.running || wheelQuiet.running || moving

  // Another hand moves the list: the wheel's glide and pending settle stop.
  function takeOver() {
    glide.stop()
    wheelQuiet.stop()
  }

  function wheelTarget() {
    return glide.running ? glide.to : contentY
  }

  function wheelBy(rows) {
    glideTo(wheelTarget() + rows * rowPitch)
    wheelQuiet.restart()
  }

  // The touchpad moves the list directly; it settles on a row once the
  // finger stops.
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

  // Glides, as the wheel does, to rest on a row boundary: never a jump, and
  // never between rows.
  function scrollToRow(index) {
    wheelQuiet.stop()
    var y = index * rowPitch
    var at = wheelTarget()
    if (y < at) at = y
    else if (y + rowHeight > at + height) at = y + rowHeight - height
    glideTo(snappedY(at))
  }

  // Heads for the row first, so the cursor is set on a row in sight.
  function select(symbol) {
    var index = displayedSymbols.indexOf(symbol)
    if (index < 0) return
    scrollToRow(index)
    cursorSymbol = symbol
    scrolledUnder = ""
  }

  // A removal hands the cursor on: a row in sight keeps the list where the
  // click stopped it, even between rows.
  function handTo(symbol) {
    var index = displayedSymbols.indexOf(symbol)
    if (index >= 0 && partInSight(index, headedY)) cursorSymbol = symbol
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
    return wholeInSightOf(index, top, sightHeight)
  }
  function wholeInSightOf(index, top, sight) {
    var y = index * rowPitch
    return y >= top - 0.5 && y + rowHeight <= top + sight + 0.5
  }

  // Any part: the pointer may rest on a row the list's foot cuts.
  function partInSight(index, top) {
    var y = index * rowPitch
    return y + rowHeight > top + 0.5 && y < top + sightHeight - 0.5
  }

  // The rows in sight where the list is headed, which the service fetches
  // ahead. From row numbers, so it changes only as a row crosses the edge.
  readonly property int sightFirst: Math.max(0, Math.floor((headedY + 0.5 - rowHeight) / rowPitch) + 1)
  readonly property int sightLast: Math.ceil((headedY + sightHeight - 0.5) / rowPitch) - 1
  readonly property var sightSymbols: displayedSymbols.slice(sightFirst, Math.max(sightFirst, sightLast + 1))

  function restingTopFor(index, top) {
    var y = index * rowPitch
    var bottom = Math.max(0, rowsLength() - sightHeight)
    if (y < top) return Math.min(bottom, y)
    if (y + rowHeight > top + sightHeight) return Math.min(bottom, Math.ceil((y + rowHeight - sightHeight) / rowPitch) * rowPitch)
    return top
  }

  // With `animate`, a new row fades in at its place and the rest slide. A
  // list that shortens under its scroll is pulled back, its rows held on
  // screen, then sliding down to close the gap.
  function display(next, animate) {
    var before = displayedSymbols
    var scrolled = contentY
    displayedSymbols = next
    contentY = clampY(contentY)
    if (glide.running && glide.to > clampY(glide.to)) glideTo(glide.to)
    if (!animate || !visible) return
    var rows = rowItems()
    for (var i = 0; i < next.length; i++) {
      if (before.indexOf(next[i]) < 0 && rows[next[i]]) rows[next[i]].join()
    }
    var pulled = scrolled - contentY
    if (pulled <= 0) return
    for (var j = 0; j < next.length; j++) {
      if (rows[next[j]]) rows[next[j]].carry(pulled)
    }
  }

  function pauseRows() {
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) row.pause()
    }
  }

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

  function slotOf(symbol) {
    var i = displayedSymbols.indexOf(symbol)
    if (dragSymbol === "") return i
    var from = displayedSymbols.indexOf(dragSymbol)
    if (from < dragTarget && i > from && i <= dragTarget) return i - 1
    if (dragTarget < from && i >= dragTarget && i < from) return i + 1
    return i
  }

  // So a lifted row stays under the pointer as the wheel scrolls.
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
    dragTarget = Settings.dragSlot(dragY / rowPitch, dragTarget, displayedSymbols.length)
  }

  function endDrag() {
    var from = displayedSymbols.indexOf(dragSymbol)
    var to = dragTarget
    if (from < 0 || to < 0) { cancelDrag(); return }
    if (from !== to) root.commitManualOrder(Settings.movedSymbols(displayedSymbols, from, to))
    dropAnim.to = to * rowPitch
    dropAnim.start()
  }

  // The drag over, the list it took from the wheel settles on a row.
  function cancelDrag() {
    dropAnim.stop()
    if (dragSymbol === "") return
    dragSymbol = ""
    glideTo(snappedY(contentY))
  }

  // Closing mid-drag, every row, the lifted one too, stays where it is on
  // screen until the next open.
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

  // Another list, another order, or an opening surface is a new arrangement:
  // the rows take their places at once.
  function layOut() {
    display(view.shown.slice(), false)
    settleRows()
    forgetGoneCursor()
  }

  // Each list's scroll, by its key, for the session.
  property var places: ({})

  ListModel { id: rowsModel }
  onViewChanged: {
    var before = arrangedView
    arrangedView = view
    if (!before) return
    if (before.library.join() !== view.library.join()) syncRows()
    // A rename keeps the key. StonksBody holds a closed surface's view, so
    // this runs only while open or opening, before reopen().
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
    lastPitch = rowPitch
    arrangedView = view
    syncRows()
    display(view.shown.slice(), false)
  }

  function syncRows() {
    var library = view.library
    var wanted = {}
    for (var j = 0; j < library.length; j++) wanted[library[j]] = true
    var have = {}
    for (var i = rowsModel.count - 1; i >= 0; i--) {
      var symbol = rowsModel.get(i).symbol
      if (wanted[symbol] === true) have[symbol] = true
      else rowsModel.remove(i)
    }
    for (j = 0; j < library.length; j++) {
      if (have[library[j]] !== true) rowsModel.append({ symbol: library[j] })
    }
  }

  NumberAnimation {
    id: dropAnim
    target: root
    property: "dragY"
    duration: Style.duration(160)
    easing.type: Easing.Bezier
    easing.bezierCurve: Style.easeOut
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
        visible: place >= 0
        y: lifted ? root.dragY : place * root.rowPitch + shift
        // A row slides only from one place in the list to another, so one
        // that joins starts at its own place. It eases `shift`, its distance
        // from its place, to zero, so a change mid-slide goes on from where
        // it is. The row travelling farther rides on top, the cursor's on a
        // tie, so none print through.
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
        NumberAnimation { id: slide; target: rowDelegate; property: "shift"; to: 0; duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
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
        function holdAt(atY) {
          if (place < 0) return
          slide.stop()
          shift = atY - place * root.rowPitch
        }
        // A day line that arrives while the row fades in draws in; one that
        // arrives later shows at once.
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
        // Holds the row on screen while the scroll moves `distance`, then
        // slides it home.
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
        NumberAnimation { id: fadeIn; target: rowDelegate; property: "opacity"; to: 1; duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        NumberAnimation { id: drawIn; target: rowDelegate; property: "reveal"; from: 0; to: 1; duration: Style.duration(320); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        width: parent.width
        // A row more than a row out of sight keeps the quote it showed, so
        // answers repaint only rows in sight; it takes the latest before the
        // frame it comes into sight.
        readonly property bool inSight: lifted || (y + height > root.contentY - root.rowPitch
          && y < root.contentY + root.sightHeight + root.rowPitch)
        // Words and pointer built within a screen of the view, so a glide or a
        // page's step finds them built.
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
        // Taken in sight, as the quote is.
        property var sightDay: null
        Binding on sightDay {
          value: rowDelegate.quote ? Chart.lineDay(rowDelegate.symbol, rowDelegate.quote, root.nights, root.allDay, root.calendars) : null
          when: rowDelegate.place >= 0 && rowDelegate.inSight
          restoreMode: Binding.RestoreNone
        }
        day: quote ? sightDay : null
        // Only rows in sight follow the scrub, or each step repaints every row.
        readonly property int sightScrub: inSight ? root.scrubShown : 0
        view: quote ? Figures.rowModel(quote, sightScrub, root.changeMode, root.newestPrints[symbol] || null) : null
        newestTime: view && view.newest && inSight ? Figures.newestTime(quote, view.newest, root.now, root.calendars) : ""
        status: root.entryOf(symbol) ? root.entryOf(symbol).status : "loading"
        // Freshness reads the clock every second: only rows in sight do.
        freshness: place >= 0 && inSight ? root.freshnessOf(symbol) : null
        sourceDown: root.sourceDown
        featuredRow: symbol === root.featuredSymbol
        cursor: symbol === root.cursorRow
        // Only a cursor of your own shows the remove button, not the resting one.
        removable: symbol === root.cursorRow && symbol === root.cursorSymbol && symbol !== root.scrolledUnder
          && root.dragSymbol === ""
        lifted: symbol === root.dragSymbol
        retro: root.retro
        scrubX: day && sightScrub ? Chart.fractionAtTime(day, sightScrub) : -1
        foreground: root.foreground
        dim: root.dim
        dimmer: root.dimmer
        upColor: root.upColor
        downColor: root.downColor
        fontFamily: root.fontFamily
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
