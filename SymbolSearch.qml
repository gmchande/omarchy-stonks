pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import "Fetch.js" as Fetch
import "Search.js" as Search
import "Tones.js" as Tones
// Search's field, results and Yahoo lookup. A FocusScope, so that hiding it
// takes the keys from the field: a hidden field keeps them otherwise.
FocusScope {
  id: root

  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.space(30)
  // As many as `Search.searchUrl` asks for.
  readonly property int maxResults: Search.SHOWN_RESULTS
  readonly property int rowGap: Style.space(2)
  // The rows' scrollbar gutter, so the field and results line up with them.
  property int gutter: 0
  readonly property int rowPitch: rowHeight + rowGap
  // With this gap, search is as tall as a full list's six rows and footer,
  // so on a short list it grows the panel no taller than a full one.
  readonly property int resultsGap: Style.space(4)
  readonly property int desiredHeight: fieldBar.height + resultsGap + rowPitch * maxResults - rowGap
  // Whole rows only: a row is never cut.
  readonly property int resultsHeight: {
    var rows = Math.floor((Math.max(0, height - fieldBar.height - resultsGap) + rowGap) / rowPitch)
    return rows > 0 ? rows * rowPitch - rowGap : 0
  }

  // Yahoo's answer.
  property var results: []
  // The list's own stocks the field names (`Search.ownMatches`), each with
  // its row's move and that move's tone: they lead, and Yahoo's same stock
  // shows once, as theirs.
  property var own: []
  readonly property var ownSymbols: own.map(function(r) { return r.symbol })
  readonly property var shown: own.concat(results.filter(function(r) { return ownSymbols.indexOf(r.symbol) < 0 }))
  readonly property int ownCount: own.length
  property color upColor: foreground
  property color downColor: foreground
  // Yahoo's rows dim under a newer query; the list's own follow every letter.
  function dimmed(index) { return stale && index >= ownCount }
  property string note: ""
  readonly property bool messageShown: answer === "none" || answer === "failed" || (answer === "" && slow)
  // What Yahoo said goes under the list's own; with more of them than the
  // view's rows, it takes the view's last line, so it and its RETRY stay in
  // sight and the search keeps its height.
  readonly property int viewRows: Math.floor((resultsHeight + rowGap) / rowPitch)
  readonly property bool messagePinned: messageShown && ownCount >= viewRows
  // For the answer on screen: its query, and "results", "none", "failed",
  // or "" before any.
  property string resultsQuery: ""
  property string answer: ""
  // An earlier query's answer, shown dimmed once the field no longer holds
  // its query.
  readonly property bool stale: answer !== "" && resultsQuery !== searchText.trim()
  // An Enter kept for the query before its answer; an edit drops it.
  property string enterFor: ""
  // Set once a lookup has been out a quarter second, so a quick answer shows
  // no waiting line, and kept through an edit, so the line doesn't blink.
  property bool slow: false
  property int resultIndex: 0
  // The stock chosen, kept by name, so rows arriving or leaving above and
  // below it never move the choice off it. The list's own take it, in
  // sight, from an older query's answer.
  property string chosenSymbol: ""
  onShownChanged: {
    if (chosenSymbol === "") {
      if (ownCount > 0) showResult(0)
      return
    }
    var at = shown.map(function(r) { return r.symbol }).indexOf(chosenSymbol)
    if (at >= 0 && !(ownCount > 0 && dimmed(at))) resultIndex = at
    else if (ownCount > 0) showResult(0)
    // Until Yahoo answers, the chart stays on what it shows.
    else resultIndex = -1
  }
  property string activeQuery: ""
  property string requestedQuery: ""
  property string searchText: ""
  property string placeholder: ""
  // The list on screen's members, arriving ones too.
  property var members: []
  // The removal on offer, the empty field's one result (`StonksBody.putBack`).
  property var putBack: null
  function actionFor(symbol) {
    if (putBack && symbol === putBack.symbol) return "UNDO"
    return members.indexOf(symbol) >= 0 ? "SHOW" : "ADD"
  }
  function showEmpty() {
    chosenSymbol = ""
    results = putBack ? [putBack] : []
    note = ""
    answer = putBack ? "results" : ""
    resultsQuery = ""
    choose(0)
  }
  onPutBackChanged: if (searchText.trim() === "" && active) showEmpty()
  // Every label takes the widest word's slot, so the exchange codes keep
  // their column whichever shows.
  readonly property font buttonFont: Qt.font({ family: fontFamily, pixelSize: Style.font.caption, bold: true, letterSpacing: 1 })
  readonly property int buttonWidth: Math.ceil(Math.max(addMetrics.advanceWidth, showMetrics.advanceWidth,
    putBack ? putBackMetrics.advanceWidth : 0)) + Style.space(12)
  TextMetrics { id: addMetrics; font: root.buttonFont; text: "ADD" }
  TextMetrics { id: showMetrics; font: root.buttonFont; text: "SHOW" }
  TextMetrics { id: putBackMetrics; font: root.buttonFont; text: "UNDO" }
  readonly property int rowPadding: Style.space(10)
  readonly property int columnGap: Style.space(10)
  readonly property int exchangeWidth: {
    var font = exchangeMetrics.font // read, so a look's new font measures again
    var widest = 0
    for (var i = 0; i < shown.length; i++)
      widest = Math.max(widest, Math.ceil(exchangeMetrics.advanceWidth(shown[i].move || shown[i].exchange || "")))
    return Math.min(widest, Style.space(110))
  }
  FontMetrics { id: exchangeMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
  // The name gives way to the symbol, which is what you match on, until the
  // name is down to half the room they share.
  readonly property int sharedWidth: width - gutter - rowPadding * 2 - columnGap * 3 - exchangeWidth - buttonWidth
  readonly property int symbolWidth: {
    var font = symbolMetrics.font // read, so a look's new font measures again
    var widest = Style.space(80)
    for (var i = 0; i < shown.length; i++)
      widest = Math.max(widest, Math.ceil(symbolMetrics.advanceWidth(shown[i].symbol)))
    return Math.min(widest, Math.floor(sharedWidth / 2))
  }
  FontMetrics { id: symbolMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }

  // `pointed`: picked by a click, so the pointer rests where the pick was.
  signal picked(string symbol, bool pointed)
  signal chose(string symbol, var result)
  signal cancelled()

  property bool active: false
  // Off, it still shows through the close fade but takes no pointer or key.
  enabled: active
  // Turned off, any way it closes, it drops a lookup still out and keeps
  // what it shows for the close fade.
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

  // Words a close kept, typed back in at the next open.
  property string resumed: ""

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
      root.showResult(Math.min(root.shown.length - 1, root.resultIndex + 1))
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.showResult(Math.max(0, root.resultIndex - 1))
      event.accepted = true
    }
  }

  // One of the list's own is taken at once, whatever Yahoo has said.
  function accept(index, pointed) {
    if (index >= 0 && index < ownCount) {
      picked(shown[index].symbol, !!pointed)
      return
    }
    if (stale || (answer === "" && searchText.trim() !== "")) {
      enterFor = searchText.trim()
      return
    }
    if (answer === "failed") retry()
    else if (index >= 0 && index < shown.length) picked(shown[index].symbol, !!pointed)
  }

  // Asked once: a lookup of it still waiting on the typing pause goes now.
  function retry() {
    if (stale || answer !== "failed" || failure === "missing") return
    searchDebounce.stop()
    answer = ""
    if (fetchRun.out && activeQuery === searchText.trim()) {
      requestedQuery = ""
      slowSearch.restart()
    } else {
      if (gate) gate.hurry()
      runSearch()
    }
  }

  // A click is Enter on the result: chosen first, so the hero is on it, then
  // taken.
  function take(index) {
    if (dimmed(index)) return
    showResult(index)
    accept(index, true)
  }

  // An emptied field drops a search still out.
  function setQuery(text) {
    var changed = text.trim() !== searchText.trim()
    searchText = text
    if (!changed) return
    enterFor = ""
    if (text.trim() === "") {
      suspend()
      slow = false
      resultsScroll.contentY = 0
      showEmpty()
      return
    }
    searchDebounce.restart()
  }

  function choose(index) {
    resultIndex = index
    var result = index >= 0 && index < shown.length ? shown[index] : null
    chosenSymbol = result ? result.symbol : ""
    chose(chosenSymbol, result)
  }

  function showResult(index) {
    if (index < 0 || index >= shown.length) return
    root.choose(index)
    var top = index * rowPitch
    var bottom = top + (index === shown.length - 1 && note !== "" ? rowPitch : 0) + rowHeight
    var limit = Math.max(0, resultsColumn.implicitHeight - resultsScroll.height)
    if (top < resultsScroll.contentY) resultsScroll.contentY = Math.min(limit, top)
    else if (bottom > resultsScroll.contentY + resultsScroll.height)
      resultsScroll.contentY = Math.max(0, Math.min(limit, bottom - resultsScroll.height))
  }

  // Yahoo's gate (`Gate.qml`), held by the service; null without one.
  property var gate: null
  property var clearance: null
  // "none" when nothing answered, "refused", "missing" when Yahoo called the
  // question wrong (as it does an emoji), or "other" (`Search.failure`). Set
  // by the answer that lands, so a run stopped or overtaken by typing never
  // changes what the answer on screen says.
  property string failure: ""

  // Only a lookup that failed for want of Yahoo is asked again as it answers.
  function yahooBack() {
    if (active && (failure === "none" || failure === "refused")) retry()
  }

  // A lookup already out for this same query answers it.
  function runSearch() {
    var q = searchText.trim()
    if (q.length < 1) return
    if (fetchRun.out) {
      if (activeQuery === q) return
      requestedQuery = q
      activeQuery = ""
      fetchRun.stop()
      return
    }
    if (clearance && !clearance()) { requestedQuery = q; return }
    requestedQuery = ""
    activeQuery = q
    if (gate && gate.take(1) === 0) {
      land("", gate.pause === "refused" || gate.pause === "none" ? gate.pause : "other")
      return
    }
    fetchRun.send([Search.searchUrl(q)], Fetch.SEARCH_CAP)
    if (answer === "" && !slow) slowSearch.restart()
  }

  function pump() {
    if (active && requestedQuery !== "" && !fetchRun.out) root.runSearch()
  }

  // An answer counts only for the query still in the field. A body of ""
  // fails to parse: no answer, failed for `why`.
  function land(body, why) {
    slowSearch.stop()
    if (root.active && root.activeQuery !== "" && root.activeQuery === root.searchText.trim()) {
      root.failure = why
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
      var kept = root.enterFor
      root.enterFor = ""
      // Yahoo's rows join below the list's own, so the choice stays, unless
      // an Enter waited for this answer: it takes Yahoo's first.
      var taken = kept === root.resultsQuery && root.answer !== "failed"
      if (root.ownCount === 0 || taken) {
        resultsScroll.contentY = 0
        root.choose(first < 0 ? -1 : root.ownCount + first)
      }
      searchField.forceActiveFocus()
      if (taken) root.accept(root.resultIndex)
    }
    if (root.requestedQuery !== "") {
      root.requestedQuery = ""
      root.runSearch()
    }
  }

  function suspend() {
    searchDebounce.stop()
    slowSearch.stop()
    requestedQuery = ""
    activeQuery = ""
    enterFor = ""
    // Its stream ends at once, empty, with no query left to answer.
    if (fetchRun.out) fetchRun.stop()
  }

  Timer {
    id: searchDebounce
    interval: 250
    onTriggered: root.runSearch()
  }

  Timer {
    id: slowSearch
    interval: 250
    onTriggered: if (fetchRun.out && root.answer === "") root.slow = true
  }

  FetchRun {
    id: fetchRun
    gate: root.gate
    onEnded: function(got) {
      // No answer at all, as from a curl stopped short, is nothing answered.
      var answer = got.length ? got[0] : null
      root.land(answer && answer.kind === "ok" ? answer.body : "", Search.failure(answer))
    }
  }

  Flickable {
    id: resultsScroll
    objectName: "searchResults"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: fieldBar.bottom
    anchors.topMargin: root.resultsGap
    height: root.resultsHeight - (root.messagePinned ? root.rowPitch : 0)
    visible: root.shown.length > 0 || root.note !== ""
    contentWidth: width
    contentHeight: resultsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      policy: resultsScroll.interactive ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
      visible: resultsScroll.interactive
      // A thumb big enough to see and grab in a long view.
      minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
    }

    Column {
      id: resultsColumn
      width: resultsScroll.width - root.gutter
      spacing: root.rowGap

      Repeater {
        model: root.shown
        Rectangle {
          id: resultRow
          objectName: "searchResult"
          required property var modelData
          required property int index
          readonly property bool chosen: index === root.resultIndex
          readonly property bool dimmed: root.dimmed(index)
          opacity: dimmed ? 0.4 : 1
          width: parent.width
          height: root.rowHeight
          radius: root.retro ? 0 : Style.cornerRadius
          color: rowMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
            : chosen ? Style.hoverFillFor(root.foreground, Commons.Color.accent)
            : rowMouse.containsMouse ? Style.normalFillFor(root.foreground, Commons.Color.accent) : "transparent"

          // The pointer only tints a row: one resting over the results never
          // changes what Enter adds.
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            enabled: !resultRow.dimmed
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
              text: resultRow.modelData.move || resultRow.modelData.exchange || ""
              color: resultRow.modelData.tone === "up" ? root.upColor
                : resultRow.modelData.tone === "down" ? root.downColor : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Rectangle {
              objectName: "searchAdd"
              opacity: resultRow.chosen && !resultRow.dimmed ? 1 : 0
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

      Text {
        objectName: "searchNote"
        visible: root.note !== ""
        opacity: root.stale ? 0.4 : 1
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

  // What Yahoo said, or that it is still being asked, under any of the
  // list's own, or on the view's last line (`messagePinned`).
  Item {
    visible: root.messageShown
    opacity: root.stale ? 0.4 : 1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: root.gutter
    anchors.top: fieldBar.bottom
    anchors.topMargin: root.resultsGap + (root.messagePinned ? (root.viewRows - 1) * root.rowPitch
      : root.ownCount * root.rowPitch - resultsScroll.contentY)
    height: root.rowHeight

    Text {
      id: searchMessage
      objectName: "searchMessage"
      visible: root.messageShown
      anchors.left: parent.left
      width: Math.min(implicitWidth, parent.width - (retrySearch.visible ? retrySearch.implicitWidth + Style.space(16) + root.rowPadding : 0))
      height: parent.height
      leftPadding: root.rowPadding
      verticalAlignment: Text.AlignVCenter
      textFormat: Text.PlainText
      text: root.answer === "none" ? (root.ownCount > 0 ? "No other matches for “" : "No matches for “") + root.resultsQuery + "”"
        : root.answer === "failed" ? "Couldn't search · " + (root.failure === "refused" ? "server busy"
          : root.failure === "none" ? "check your internet" : root.failure === "missing" ? "try other words" : "try again")
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
      visible: root.answer === "failed" && root.failure !== "missing"
      enabled: !root.stale
      anchors.left: searchMessage.right
      anchors.leftMargin: Style.space(16)
      anchors.verticalCenter: searchMessage.verticalCenter
      text: "RETRY"
      onActivated: root.retry()
    }
  }

  // No rule under the field: its border is its edge.
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
      Keys.onPressed: function(event) { root.handleKey(event) }
    }

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
