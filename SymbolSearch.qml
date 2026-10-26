pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
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
// are no matches, and a lookup that failed says so with RETRY beside it,
// which Enter does too (`retry`). A first query, with no
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
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color dimmer: Tones.dimmer(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.space(30)
  // What the search endpoint returns at most, so the room is the shape of a
  // full answer.
  readonly property int maxResults: 8
  readonly property int rowGap: Style.space(2)
  // The scrollbar's gutter at the right, as the list's rows keep it, so the
  // field and the answers line up with the rows they replace.
  property int gutter: 0
  readonly property int rowPitch: rowHeight + rowGap
  // From the field's rule to the first result: with it, the field and a
  // full answer are as tall as a full list's six rows and footer, so search
  // on a short list grows the popup no taller than a full one.
  readonly property int resultsGap: Style.space(4)
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
  // An Enter pressed before the field's query had its answer: kept for that
  // query, and the first answer for it decides, as Enter on it would
  // (`land`); an edit, a close, or a failed lookup drops it. Found in
  // review: "aapl" and Enter at once added nothing and said nothing.
  property string enterFor: ""
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
  // The removal on offer, { symbol, name, exchange }, or null: it is the
  // empty field's answer, its one result, chosen, and wherever it shows its
  // label says it goes back (`StonksBody.putBack`). Like any answer, it
  // stays dimmed and untaken while a query typed since is out.
  property var putBack: null
  function actionFor(symbol) {
    if (putBack && symbol === putBack.symbol) return "PUT BACK"
    return members.indexOf(symbol) >= 0 ? "SHOW" : "ADD"
  }
  function showEmpty() {
    results = putBack ? [putBack] : []
    note = ""
    answer = putBack ? "results" : ""
    resultsQuery = ""
    choose(0)
  }
  onPutBackChanged: if (searchText.trim() === "" && active) showEmpty()
  // Every label shares one slot on every row, the widest word's, so the
  // exchange codes keep their column whichever shows. In the caption's
  // spaced capitals, as every other button in the views says its word, and
  // padded as they are: 6 px each side of the widest word, 2 above and
  // below the caption line.
  readonly property font buttonFont: Qt.font({ family: fontFamily, pixelSize: Style.font.caption, bold: true, letterSpacing: 1 })
  readonly property int buttonWidth: Math.ceil(Math.max(addMetrics.advanceWidth, showMetrics.advanceWidth,
    putBack ? putBackMetrics.advanceWidth : 0)) + Style.space(12)
  TextMetrics { id: addMetrics; font: root.buttonFont; text: "ADD" }
  TextMetrics { id: showMetrics; font: root.buttonFont; text: "SHOW" }
  TextMetrics { id: putBackMetrics; font: root.buttonFont; text: "PUT BACK" }
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
  readonly property int sharedWidth: width - gutter - rowPadding * 2 - columnGap * 3 - exchangeWidth - buttonWidth
  readonly property int symbolWidth: {
    var font = symbolMetrics.font // read, so a look's new font measures again
    var widest = Style.space(80)
    for (var i = 0; i < results.length; i++)
      widest = Math.max(widest, Math.ceil(symbolMetrics.advanceWidth(results[i].symbol)))
    return Math.min(widest, Math.floor(sharedWidth / 2))
  }
  FontMetrics { id: symbolMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }

  signal picked(string symbol)
  // The choice is now this result, or none ("", null): its symbol, and the
  // result itself (`Search.parseSearch`).
  signal chose(string symbol, var result)
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

  // Words a close kept, which the next start types back in; "" for none.
  property string resumed: ""

  // A new search's start, so its first frame is empty rather than the last
  // search's field and results, unless a close kept what was being typed
  // (`resumed`): then it is typed back in and asked again.
  function reset() {
    slow = false
    resultsScroll.contentY = 0
    activeQuery = ""
    requestedQuery = ""
    enterFor = ""
    searchDebounce.stop()
    searchField.text = ""
    showEmpty()
    var kept = resumed
    resumed = ""
    if (kept !== "") searchField.text = kept
  }

  // Escape, or its button.
  function cancel() {
    searchDebounce.stop()
    requestedQuery = ""
    enterFor = ""
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
  // the query in the field is taken: an Enter before its answer is kept for
  // it (`enterFor`). On a failed lookup there is none to take: Enter asks
  // again.
  function accept(index) {
    if (stale || (answer === "" && searchText.trim() !== "")) {
      enterFor = searchText.trim()
      return
    }
    if (answer === "failed") retry()
    else if (index >= 0 && index < results.length) picked(results[index].symbol)
  }

  // The failed lookup's query asked again, through the same request and
  // gate as typing it: the failure goes, so the line says what a first
  // query's does until the answer lands (at once, while the gate pauses for
  // a refusal; a pause for no answer ends, `Gate.hurry`). It is asked once:
  // a lookup of it still waiting on the typing pause goes now instead, and
  // one already out is the retry's.
  function retry() {
    if (stale || answer !== "failed") return
    searchDebounce.stop()
    answer = ""
    if (searchProc.running && activeQuery === searchText.trim()) {
      requestedQuery = ""
      slowSearch.restart()
    } else {
      if (gate) gate.hurry()
      runSearch()
    }
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
    enterFor = ""
    if (text.trim() === "") {
      // No query is asked any more: a search still out is dropped.
      suspend()
      slow = false
      resultsScroll.contentY = 0
      showEmpty()
      return
    }
    searchDebounce.restart()
  }

  // The choice, told: a result, or none when there are no results.
  function choose(index) {
    resultIndex = index
    var result = index >= 0 && index < results.length ? results[index] : null
    chose(result ? result.symbol : "", result)
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
  property var clearance: null
  // The gate's ticket the request out was let through on (`Gate.report`).
  property int ticket: 0

  // A lookup of the field's query. One for another query still out is
  // stopped, and this one goes as its stream ends (`land`): its answer
  // would be thrown away, and waiting it out held the new query up to the
  // request's 10 s. The one out for this same query answers it.
  function runSearch() {
    var q = searchText.trim()
    if (q.length < 1) return
    if (searchProc.running) {
      if (activeQuery === q) return
      requestedQuery = q
      activeQuery = ""
      searchProc.running = false
      return
    }
    if (clearance && !clearance()) { requestedQuery = q; return }
    requestedQuery = ""
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

  function pump() {
    if (active && requestedQuery !== "" && !searchProc.running) root.runSearch()
  }

  // An answer counts only for the query still being asked: a search dropped
  // by a close or a new open has no query, and an empty field takes no
  // results. "" is no answer. The first result is chosen, so Enter takes
  // it, unless Yahoo's top answer is a kind Stonks leaves out
  // (`Search.parseSearch`): then nothing is, and the note under the
  // results says why; the arrows and a click still reach every result.
  function land(body) {
    slowSearch.stop()
    if (root.active && root.activeQuery !== "" && root.activeQuery === root.searchText.trim()) {
      var first = 0
      try {
        var parsed = Search.parseSearch(JSON.parse(body))
        root.results = parsed.results
        root.note = parsed.note
        root.answer = parsed.results.length > 0 || parsed.note !== "" ? "results" : "none"
        if (parsed.topLeftOut) first = -1
      } catch (e) {
        root.results = []
        root.note = ""
        root.answer = "failed"
      }
      root.resultsQuery = root.activeQuery
      root.slow = false
      resultsScroll.contentY = 0
      root.choose(first)
      searchField.forceActiveFocus()
      var kept = root.enterFor
      root.enterFor = ""
      if (kept === root.resultsQuery && root.answer !== "failed") root.accept(root.resultIndex)
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
    enterFor = ""
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
    // smallest, the rows' scrollbar says so, at rest too, in the gutter the
    // results stop short of.
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      // Drawn while there is more, not only while used.
      policy: resultsScroll.interactive ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
      visible: resultsScroll.interactive
      // At least 24 px long, so a long view's thumb is there to see and grab.
      minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
    }

    Column {
      id: resultsColumn
      width: resultsScroll.width - root.gutter
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
          color: rowMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
            : chosen ? Style.hoverFillFor(root.foreground, Commons.Color.accent)
            : rowMouse.containsMouse ? Style.normalFillFor(root.foreground, Commons.Color.accent) : "transparent"

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
              height: addLabel.implicitHeight + Style.space(4)
              radius: root.retro ? 0 : Style.cornerRadius
              color: Style.selectedFillFor(root.foreground, Commons.Color.accent)
              Text {
                id: addLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.actionFor(resultRow.modelData.symbol)
                color: Style.selectedStateColor(root.foreground, Commons.Color.accent)
                font: root.buttonFont
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
  // results would be; a failed lookup offers RETRY after its words.
  Text {
    id: searchMessage
    objectName: "searchMessage"
    visible: root.answer === "none" || root.answer === "failed" || (root.answer === "" && root.slow)
    opacity: root.stale ? 0.4 : 1
    anchors.left: parent.left
    anchors.top: fieldBar.bottom
    anchors.topMargin: root.resultsGap
    width: Math.min(implicitWidth, parent.width - (retrySearch.visible ? retrySearch.implicitWidth + Style.space(16) + root.rowPadding : 0))
    height: root.rowHeight
    leftPadding: root.rowPadding
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    text: root.answer === "none" ? "No matches for “" + root.resultsQuery + "”"
      : root.answer === "failed" ? "Search didn’t answer"
      : "Searching for “" + root.searchText.trim() + "”…"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  ListAction {
    id: retrySearch
    objectName: "searchRetry"
    view: root
    visible: root.answer === "failed"
    enabled: !root.stale
    opacity: searchMessage.opacity
    anchors.left: searchMessage.right
    anchors.leftMargin: Style.space(16)
    anchors.verticalCenter: searchMessage.verticalCenter
    text: "RETRY"
    onActivated: root.retry()
  }

  // The field, at the top, where the list's rows were. Its own border is
  // its edge: a rule under it would draw a second one.
  Item {
    id: fieldBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: root.gutter
    height: root.rowHeight + Style.space(6)

    Field {
      id: searchField
      objectName: "searchField"
      anchors.left: parent.left
      anchors.right: cancelButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      retro: root.retro
      foreground: root.foreground
      dim: root.dim
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
      anchors.rightMargin: root.rowPadding
      anchors.verticalCenter: parent.verticalCenter
      text: "CANCEL"
      onActivated: root.cancel()
    }
  }
}
