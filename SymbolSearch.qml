pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Fetch.js" as Fetch
import "Search.js" as Search
import "Tones.js" as Tones
// Search field, results, and the Yahoo lookup. The body turns it on and off
// (`active`) and handles picked / chose / cancelled, and gives it the room
// of desiredHeight as it opens. The field sits at the top and the results
// fill down under it, whole rows only, so nothing above them moves as
// answers come and go. The last answer stays on screen while a new query is
// out, dimmed and not takeable, so nothing can add a symbol found for an
// earlier query; only an empty field clears it. An empty answer says there
// are no matches, and a lookup that failed says so. A first query, with no
// answer on screen, whose lookup has been out a quarter of a second says
// it is being searched for, so a slow network never leaves the space under
// the field blank. What an answer held that Stonks doesn't follow, a mutual
// fund or a currency, is named under the results it does show (`note`), so
// a fund Yahoo has never reads as no
// match. The keyboard owns the choice: it starts on the top result, the
// arrows move it and keep it in view, Enter takes it, and every change of
// it is told (`chose`), so the
// hero can show it before it is added. The pointer tints the row under it,
// and a click takes that row as Enter does: chosen, then added, or shown
// when it is already in the list. So a pointer resting over the list never
// changes what Enter adds. A
// FocusScope so that hiding it takes the keyboard away from the field;
// otherwise the hidden field keeps every later key the surface's own key
// handler should see.
FocusScope {
  id: root

  property bool retro: false
  property color foreground: Color.foreground
  property color dim: Tones.dim(foreground, Color.background)
  property color dimmer: Tones.dimmer(foreground, Color.background)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.space(30)
  // What the search endpoint returns at most, so the room is the shape of a
  // full answer.
  readonly property int maxResults: 8
  readonly property int rowGap: Style.space(2)
  readonly property int rowPitch: rowHeight + rowGap
  // From the field's rule to the first result.
  readonly property int resultsGap: Style.space(6)
  readonly property int desiredHeight: fieldBar.height + resultsGap + rowPitch * maxResults - rowGap
  // The results' room under the field, in whole rows: a row is never cut.
  readonly property int resultsHeight: {
    var rows = Math.floor((Math.max(0, height - fieldBar.height - resultsGap) + rowGap) / rowPitch)
    return rows > 0 ? rows * rowPitch - rowGap : 0
  }

  property var results: []
  // What else Yahoo's answer held, in words, or "" (`Search.parseSearch`).
  property string note: ""
  // The query the answer on screen is for, and what it was: "results" (some
  // shown, or a note), "none", or "failed"; "" before any answer.
  property string resultsQuery: ""
  property string answer: ""
  // The answer on screen is for an earlier query than the field's.
  readonly property bool stale: answer !== "" && resultsQuery !== searchText.trim()
  // A lookup has been out a quarter of a second with no answer on screen,
  // counted from the latest one to go out, so one answering sooner shows
  // nothing. It stays until an answer, an empty field, or a new open:
  // through an edit too, so the line doesn't blink while you type.
  property bool slow: false
  property int resultIndex: 0
  property string activeQuery: ""
  property string requestedQuery: ""
  property string searchText: ""
  property string placeholder: ""
  // The list on screen's members, arriving ones too: a result already in
  // it is shown, not added, and its label says so.
  property var members: []
  function actionFor(symbol) { return members.indexOf(symbol) >= 0 ? "Show" : "Add" }
  // Add and Show share one slot on every row, the wider label's, so the
  // exchange codes keep their column whichever shows.
  readonly property int buttonWidth: Math.ceil(Math.max(addMetrics.advanceWidth, showMetrics.advanceWidth)) + Style.space(20)
  TextMetrics { id: addMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; text: "Add" }
  TextMetrics { id: showMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; text: "Show" }
  // A row's columns: the symbol, the name, the exchange, and the label.
  readonly property int rowPadding: Style.space(10)
  readonly property int columnGap: Style.space(10)
  // As wide as the answer's widest exchange code, so the name runs up to
  // it: a fixed 110 px left NASDAQ 70 px of nothing while names were cut.
  readonly property int exchangeWidth: {
    var font = exchangeMetrics.font // read, so a look's new font measures again
    var widest = 0
    for (var i = 0; i < results.length; i++)
      widest = Math.max(widest, Math.ceil(exchangeMetrics.advanceWidth(results[i].exchange || "")))
    return Math.min(widest, Style.space(110))
  }
  FontMetrics { id: exchangeMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
  // The symbol is what you match on, so the name gives way to it: one
  // column for every row, as wide as the answer's widest symbol, until the
  // name is down to half the room the two share; past that a symbol ends
  // in an ellipsis. The exchange and the label keep theirs.
  readonly property int sharedWidth: width - rowPadding * 2 - columnGap * 3 - exchangeWidth - buttonWidth
  readonly property int symbolWidth: {
    var font = symbolMetrics.font // read, so a look's new font measures again
    var widest = Style.space(80)
    for (var i = 0; i < results.length; i++)
      widest = Math.max(widest, Math.ceil(symbolMetrics.advanceWidth(results[i].symbol)))
    return Math.min(widest, Math.floor(sharedWidth / 2))
  }
  FontMetrics { id: symbolMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }

  signal picked(string symbol)
  // The choice is now this result, or none ("").
  signal chose(string symbol)
  signal cancelled()

  // True while search is open on an open surface. Turned on, it starts
  // fresh before its first frame and takes the keys a turn later if it is
  // still on; turned off, by any way it closes or by the surface closing, it
  // gives the keys up and drops a search still out, and keeps what it shows
  // for the close fade.
  property bool active: false
  // Off, it still shows, through the close fade, but takes no pointer or
  // key: nothing acts or takes focus from a view that is closing.
  enabled: active
  onActiveChanged: {
    if (active) {
      reset()
      Qt.callLater(function() { if (root.active) searchField.forceActiveFocus() })
    } else {
      suspend()
      searchField.focus = false
      root.focus = false
    }
  }
  Keys.onPressed: function(event) { root.handleKey(event) }

  // A new search's start, so its first frame is empty rather than the last
  // search's field and results.
  function reset() {
    results = []
    note = ""
    answer = ""
    resultsQuery = ""
    slow = false
    resultsScroll.contentY = 0
    activeQuery = ""
    requestedQuery = ""
    searchText = ""
    searchDebounce.stop()
    searchField.text = ""
    choose(0)
  }

  // Escape, or its button.
  function cancel() {
    searchDebounce.stop()
    requestedQuery = ""
    cancelled()
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.cancel()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.accept(root.resultIndex)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.showResult(Math.min(root.results.length - 1, root.resultIndex + 1))
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.showResult(Math.max(0, root.resultIndex - 1))
      event.accepted = true
    }
  }

  // Every way of taking a result comes through here, and only a result for
  // the query in the field is taken.
  function accept(index) {
    if (!stale && index >= 0 && index < results.length) picked(results[index].symbol)
  }

  // A click on a result is Enter on it: chosen, so the hero is on it as an
  // add or a show expects, then taken.
  function take(index) {
    if (stale) return
    showResult(index)
    accept(index)
  }

  function setQuery(text) {
    var changed = text.trim() !== searchText.trim()
    searchText = text
    if (!changed) return
    if (text.trim() === "") {
      // No query is asked any more: a search still out is dropped.
      suspend()
      results = []
      note = ""
      answer = ""
      resultsQuery = ""
      slow = false
      resultsScroll.contentY = 0
      choose(0)
      return
    }
    searchDebounce.restart()
  }

  // The choice, told: a result, or none when there are no results.
  function choose(index) {
    resultIndex = index
    chose(index >= 0 && index < results.length ? results[index].symbol : "")
  }

  // Choose a result and bring it into view: the last brings the note under
  // it too, so the keys reach what the answer left out. Found in review: in
  // the window at its smallest, the note stayed clipped under a fifth result.
  function showResult(index) {
    if (index < 0 || index >= results.length) return
    root.choose(index)
    var top = index * rowPitch
    var bottom = top + (index === results.length - 1 && note !== "" ? rowPitch : 0) + rowHeight
    var limit = Math.max(0, resultsColumn.implicitHeight - resultsScroll.height)
    if (top < resultsScroll.contentY) resultsScroll.contentY = Math.min(limit, top)
    else if (bottom > resultsScroll.contentY + resultsScroll.height)
      resultsScroll.contentY = Math.max(0, Math.min(limit, bottom - resultsScroll.height))
  }

  // Yahoo's gate (`Gate.qml`), which the service holds: while it pauses the
  // host, a lookup fails at once rather than waiting. A body with no
  // service has none.
  property var gate: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0

  function runSearch() {
    var q = searchText.trim()
    if (q.length < 1) return
    if (searchProc.running) { requestedQuery = q; return }
    activeQuery = q
    if (gate && gate.take(1) === 0) {
      land("")
      return
    }
    if (gate) root.ticket = gate.ticket
    searchProc.command = Fetch.curlCommand([Search.searchUrl(q)], Fetch.SEARCH_CAP)
    searchProc.running = true
    if (answer === "" && !slow) slowSearch.restart()
  }

  // An answer counts only for the query still being asked: a search dropped
  // by a close or a new open has no query, and an empty field takes no
  // results. "" is no answer.
  function land(body) {
    slowSearch.stop()
    if (root.active && root.activeQuery !== "" && root.activeQuery === root.searchText.trim()) {
      try {
        var parsed = Search.parseSearch(JSON.parse(body))
        root.results = parsed.results
        root.note = parsed.note
        root.answer = parsed.results.length > 0 || parsed.note !== "" ? "results" : "none"
      } catch (e) {
        root.results = []
        root.note = ""
        root.answer = "failed"
      }
      root.resultsQuery = root.activeQuery
      root.slow = false
      resultsScroll.contentY = 0
      root.choose(0)
      searchField.forceActiveFocus()
    }
    if (root.requestedQuery !== "") {
      root.requestedQuery = ""
      root.runSearch()
    }
  }

  // Drops a search not yet made and ignores an answer still out; what shows
  // stays.
  function suspend() {
    searchDebounce.stop()
    slowSearch.stop()
    requestedQuery = ""
    activeQuery = ""
    // Its stream ends at once, empty, and is ignored: no query is asked.
    if (searchProc.running) searchProc.running = false
  }

  Timer {
    id: searchDebounce
    interval: 250
    onTriggered: root.runSearch()
  }

  Timer {
    id: slowSearch
    interval: 250
    onTriggered: if (searchProc.running && root.answer === "") root.slow = true
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var got = Fetch.answers(String(text || ""))
        if (root.gate) root.gate.report(got.map(function(a) { return a.kind }), got.length ? got[0].retryAfter : 0, root.ticket)
        root.land(got.length && got[0].kind === "ok" ? got[0].body : "")
      }
    }
  }

  Flickable {
    id: resultsScroll
    objectName: "searchResults"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: fieldBar.bottom
    anchors.topMargin: root.resultsGap
    height: root.resultsHeight
    visible: root.results.length > 0 || root.note !== ""
    opacity: root.stale ? 0.4 : 1
    contentWidth: width
    contentHeight: resultsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    // While more results sit out of sight, as in the window at its
    // smallest, the rows' scrollbar says so, at rest too, and the results
    // stop short of its gutter.
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      // Drawn while there is more, not only while used.
      policy: resultsScroll.interactive ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
      visible: resultsScroll.interactive
      // At least 24 px long, so a long view's thumb is there to see and grab.
      minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
    }

    Column {
      id: resultsColumn
      width: resultsScroll.width - (resultsScroll.interactive ? Style.space(8) : 0)
      spacing: root.rowGap

      Repeater {
        model: root.results
        Rectangle {
          id: resultRow
          objectName: "searchResult"
          required property var modelData
          required property int index
          readonly property bool chosen: index === root.resultIndex
          width: parent.width
          height: root.rowHeight
          radius: root.retro ? 0 : Style.cornerRadius
          color: rowMouse.pressed ? Style.pressedFillFor(root.foreground, Color.accent)
            : chosen ? Style.hoverFillFor(root.foreground, Color.accent)
            : rowMouse.containsMouse ? Style.normalFillFor(root.foreground, Color.accent) : "transparent"

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            enabled: !root.stale
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.take(resultRow.index)
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: root.rowPadding
            anchors.rightMargin: root.rowPadding
            spacing: root.columnGap
            Text {
              width: root.symbolWidth
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: resultRow.modelData.symbol
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            // Every row keeps the label's slot, so the exchange codes stay in
            // one column as the choice moves.
            Text {
              objectName: "searchName"
              width: root.sharedWidth - root.symbolWidth
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: resultRow.modelData.name
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              objectName: "searchExchange"
              width: root.exchangeWidth
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: resultRow.modelData.exchange || ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            // What Enter, or a click, does to the chosen result, marked as the
            // shell marks the button Enter takes (the selected fill, in the
            // selected colour): on the chosen result only, the one the hero
            // shows, and only while it can be taken. Other rows keep its
            // slot, unseen.
            Rectangle {
              id: addButton
              objectName: "searchAdd"
              opacity: resultRow.chosen && !root.stale ? 1 : 0
              anchors.verticalCenter: parent.verticalCenter
              width: root.buttonWidth
              height: Style.space(20)
              radius: root.retro ? 0 : Style.cornerRadius
              color: Style.selectedFillFor(root.foreground, Color.accent)
              Text {
                id: addLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.actionFor(resultRow.modelData.symbol)
                color: Style.selectedStateColor(root.foreground, Color.accent)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }
        }
      }

      // What else the answer held, under what it shows: at the top when it
      // shows nothing. One line; nothing acts on it.
      Text {
        objectName: "searchNote"
        visible: root.note !== ""
        width: parent.width
        height: root.rowHeight
        leftPadding: root.rowPadding
        rightPadding: root.rowPadding
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: root.note
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }

  // No matches, no answer at all, or a slow first lookup, said where the
  // results would be.
  Text {
    objectName: "searchMessage"
    visible: root.answer === "none" || root.answer === "failed" || (root.answer === "" && root.slow)
    opacity: root.stale ? 0.4 : 1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: fieldBar.bottom
    anchors.topMargin: root.resultsGap
    height: root.rowHeight
    leftPadding: root.rowPadding
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    text: root.answer === "none" ? "No matches for “" + root.resultsQuery + "”"
      : root.answer === "failed" ? "Search didn’t answer · try again"
      : "Searching for “" + root.searchText.trim() + "”…"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  // The field, at the top, where the list's rows were. Its own border is
  // its edge: a rule under it would draw a second one.
  Item {
    id: fieldBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.rowHeight + Style.space(6)

    TextField {
      id: searchField
      objectName: "searchField"
      anchors.left: parent.left
      anchors.right: cancelButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.foreground
      placeholderText: root.placeholder
      onTextChanged: root.setQuery(text)
      onAccepted: root.accept(root.resultIndex)
      Keys.onPressed: function(event) { root.handleKey(event) }
    }

    // Escape, as a button: with the field's caption size, so the field
    // keeps its width.
    ListAction {
      id: cancelButton
      objectName: "searchCancel"
      view: root
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: "CANCEL"
      onActivated: root.cancel()
    }
  }
}
