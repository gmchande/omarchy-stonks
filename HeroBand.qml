pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Motion.js" as Motion
// The hero, the chart, the range row, the info block and the list's header.
// Each keeps its height for every symbol, range and look, so the list below
// never moves.
Item {
  id: root

  property var freshness: null
  // Yahoo is sending nothing for any listing (`Hero.sourceDown`).
  property bool sourceDown: false
  property Look look
  property string changeMode: "pct"
  property bool scrubbing: false
  property bool live: false
  // Closing: what moves stops where it is.
  property bool still: false
  // A screen shows the surface: out of sight, a tick, a range or the bell
  // changes what they change at once.
  property bool seen: true
  // The chart on show waits for the next: its live mark holds still with it.
  property bool held: false
  // Once the next chart is a while on its way, the held one dims under a line
  // naming what's coming (`ChartMotion.dimmed`): a veil of the ground over each
  // piece, to 0.6, as if each faded to 0.4 with no layer to flatten first.
  property real dimmed: 0
  // On the chart: while the next one is on its way, over the dimmed one,
  // what's coming; with no price at all, why none comes.
  property string waitingText: ""
  readonly property color veil: Util.alpha(look.ground, 0.6 * dimmed)
  // A new one ripples the live dot, and blinks retro's cap.
  readonly property string newestPrice: root.day && root.day.points && root.day.points.length
    ? String(root.day.points[root.day.points.length - 1].p) : ""
  property string symbol: ""
  property bool nameOnLine: false
  property var view: null
  property var quote: null
  property var calendars: null
  property var day: null
  property var latest: null
  property var geometry: null
  property real scrubX: -1
  // The draw-in's share of the ink, and a replay's place (-1 without one).
  property real reveal: 1
  property real replayX: -1
  // The chart the one on show bends out of, how far on OutCubic, and how
  // far in time, which retro's wave takes (`ChartMotion`).
  property var morphFrom: null
  property real morph: 1
  property real beat: 1
  // While another stock arrives (`ChartMotion.arrival`), its figures roll
  // no digits (`Hero`).
  property real arrival: 1
  property int chartHeight: Style.space(190)
  property string order: "manual"
  property bool reversed: false
  property string listLabel: "All"
  property string rowsDay: "TODAY"
  property var breadth: ({ list: "", up: 0, flat: 0, down: 0, none: 0 })
  property bool listMenuOpen: false
  property bool replayRunning: false
  property bool rowsCovered: false
  property var rangeOptions: []
  property string range: "1D"
  // The info block's day or range line over the 52 weeks'; every set of facts
  // the first can hold on any range, and every low and high on a range held;
  // and a range's high and low on its chart.
  property var periodLine: null
  property var yearLine: null
  property var factLists: []
  property var infoRanges: []
  property var rangeMarks: null
  property string baselineText: ""
  // The clock, by which the hero's overnight trade is old.
  property int now: 0
  // Whether the hero's change is the day's, which a click cycles.
  property bool changeCycles: true
  readonly property alias chartItem: heroChart
  readonly property var smoothChart: smoothLoader.item
  readonly property var retroChart: retroLoader.item
  // A replay's sound steps through it in retro, a note a column.
  readonly property var pixelGrid: retroChart ? retroChart.grid : Chart.retroGrid(root.geometry, heroChart.width, heroChart.height, 5, 1)
  // The retro column a place on the chart stands in, which a scrub's chime
  // strikes.
  function pixelColumnAt(fraction) {
    return retroChart ? retroChart.columnAt(fraction) : Chart.retroColumn(pixelGrid, fraction)
  }

  // The hero's change or the rows' unit, clicked: the unit steps.
  signal changeClicked()
  signal orderClicked()
  signal orderReverseClicked()
  signal listClicked()
  signal scrubRequested(real fraction)
  signal scrubCleared()
  signal snapToNow()
  signal rangeRequested(string range)

  function settle() {
    listHeader.settle()
    heroItem.settle()
    rangeRow.settle()
    infoBlock.settle()
    settleLook()
    if (smoothChart) smoothChart.settle()
  }

  // Remember the last price each look's live mark played for across lazy
  // look switches, so switching smooth <-> retro doesn't replay the burst.
  property string smoothPlayedFor: ""
  property string retroPlayedFor: ""

  // Left-to-right column-pitch wipe on smooth ↔ retro, synced with LookIcon.
  property real lookWipe: 1
  readonly property bool lookWiping: lookWipe < 1
  readonly property real wipeX: Math.min(heroChart.width, Math.round(lookWipe * pixelGrid.columns) * pixelGrid.pitch)
  function settleLook() {
    lookWipeAnim.stop()
    lookWipe = 1
  }
  Connections {
    target: root.look
    function onRetroChanged() {
      if (root.still) return
      if (!root.seen || !root.visible || Motion.duration(Style, 240) <= 0) {
        root.settleLook()
        return
      }
      lookWipeAnim.stop()
      root.lookWipe = 0
      lookWipeAnim.start()
    }
  }
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() { if (Style.reduceMotion) root.settleLook() }
  }
  onStillChanged: if (still && lookWipeAnim.running) lookWipeAnim.pause()
  onSeenChanged: if (!seen) Qt.callLater(function() { if (!root.seen && !root.still) root.settleLook() })
  NumberAnimation {
    id: lookWipeAnim
    target: root
    property: "lookWipe"
    to: 1
    duration: Motion.duration(Style, 240)
    easing.type: Easing.Linear
  }
  // The market opened: the live dot blooms on the bell's beat.
  function opened() {
    if (!root.seen) return
    if (root.look.retro) { if (retroChart) retroChart.bloom() }
    else if (smoothChart) smoothChart.bloom()
  }

  // Between the band's blocks, the body's rhythm (`StonksBody.bandGap`).
  property int bandGap: Style.space(16)

  implicitHeight: band.implicitHeight
  // Summed from its parts, so the body can size the chart without reading it.
  readonly property int heightBesideChart: heroItem.height + rangeRow.height + infoBlock.height + listHeader.height
    + band.spacing * 4
  implicitWidth: parent ? parent.width : 0
  height: implicitHeight
  width: parent ? parent.width : implicitWidth

  Column {
    id: band
    width: parent.width
    spacing: root.bandGap

    Hero {
      id: heroItem
      objectName: "hero"
      width: parent.width
      calendars: root.calendars
      symbol: root.symbol
      nameOnLine: root.nameOnLine
      view: root.view
      quote: root.quote
      day: root.day
      latest: root.latest
      freshness: root.freshness
      sourceDown: root.sourceDown
      look: root.look
      changeMode: root.changeMode
      scrubbing: root.scrubbing
      now: root.now
      baselineText: root.baselineText
      changeCycles: root.changeCycles
      still: root.still
      seen: root.seen
      arrival: root.arrival
      onChangeClicked: root.changeClicked()

      Rectangle {
        anchors.fill: parent
        visible: root.dimmed > 0
        color: root.veil
      }
    }

    Item {
      id: heroChart
      objectName: "heroChart"
      width: parent.width
      height: root.chartHeight

      Item {
        id: smoothWrap
        visible: !root.look.retro || root.lookWiping
        x: root.lookWiping && root.look.retro ? root.wipeX : 0
        y: -rangeMarks.lift
        width: root.lookWiping ? (root.look.retro ? Math.max(0, parent.width - root.wipeX) : root.wipeX) : parent.width
        height: parent.height + rangeMarks.lift * 2
        clip: root.lookWiping

        Loader {
          id: smoothLoader
          active: !root.look.retro || root.lookWiping
          x: -parent.x
          y: rangeMarks.lift
          width: heroChart.width
          height: heroChart.height
          sourceComponent: SmoothChart {
            objectName: "smoothChart"
            geometry: root.geometry
            stock: root.symbol
            up: root.view ? root.view.dayUp : true
            upColor: root.look.upColor
            downColor: root.look.downColor
            baselineColor: root.look.dimmer
            hairlineColor: root.look.foreground
            ground: root.look.ground
            scrubX: root.scrubX
            reveal: root.reveal
            replayX: root.replayX
            morphFrom: root.morphFrom
            morph: root.morph
            live: root.live && !root.look.retro
            newestPrice: root.newestPrice
            initialPlayedFor: root.smoothPlayedFor
            onPlayed: function(price) { root.smoothPlayedFor = price }
            surfaceOpen: !root.still
            seen: root.seen
            still: root.still || root.held
          }
        }
      }

      Item {
        id: retroWrap
        visible: root.look.retro || root.lookWiping
        x: root.lookWiping && !root.look.retro ? root.wipeX : 0
        y: -rangeMarks.lift
        width: root.lookWiping ? (!root.look.retro ? Math.max(0, parent.width - root.wipeX) : root.wipeX) : parent.width
        height: parent.height + rangeMarks.lift * 2
        clip: root.lookWiping

        Loader {
          id: retroLoader
          active: root.look.retro || root.lookWiping
          x: -parent.x
          y: rangeMarks.lift
          width: heroChart.width
          height: heroChart.height
          sourceComponent: RetroChart {
            objectName: "retroChart"
            geometry: root.geometry
            upColor: root.look.upColor
            downColor: root.look.downColor
            up: root.view ? root.view.dayUp : true
            baselineColor: root.look.dimmer
            glow: true
            fullSession: true
            live: root.live && root.look.retro
            newestPrice: root.newestPrice
            initialPlayedFor: root.retroPlayedFor
            onPlayed: function(price) { root.retroPlayedFor = price }
            surfaceOpen: !root.still
            seen: root.seen
            still: root.still || root.held
            hairlineColor: root.look.foreground
            ghostColor: root.look.ghost
            ground: root.look.ground
            scrubX: root.scrubX
            reveal: root.reveal
            replayX: root.replayX
            morphFrom: root.morphFrom
            morph: root.beat
          }
        }
      }

      RangeMarks {
        id: rangeMarks
        parent: rangeMarks.chart ? rangeMarks.chart.underScrub : heroChart
        anchors.fill: parent
        marks: root.rangeMarks
        chart: root.look.retro ? root.retroChart : root.smoothChart
        look: root.look
      }

      // The chart that lands draws in at full ink. The veil reaches as far past
      // the chart as a mark can lift off it.
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: -rangeMarks.lift
        anchors.bottomMargin: -rangeMarks.lift
        visible: root.held && root.dimmed > 0
        color: root.veil
      }

      Text {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width)
        visible: root.waitingText !== "" && (!root.held || root.dimmed > 0)
        opacity: root.held ? root.dimmed : 1
        textFormat: Text.PlainText
        text: root.waitingText
        color: root.look.foreground
        font.family: root.look.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }

      // A day with one bar or none says so on a patch of the ground, which
      // stops the dashed baseline short of it: a lone dot or an empty chart
      // reads as broken. Beside a lone trade it stands in the other half.
      Rectangle {
        objectName: "dayNote"
        readonly property string text: root.geometry && root.geometry.day ? Figures.dayNote(root.day, root.now, root.calendars) : ""
        readonly property real tradeX: root.geometry && root.geometry.points.length === 1 ? root.geometry.points[0].x : -1
        x: (tradeX < 0 ? parent.width / 2 : tradeX > 0.5 ? parent.width / 4 : parent.width * 3 / 4) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(parent.width / (tradeX < 0 ? 1 : 2), dayNoteText.implicitWidth + Style.space(16))
        height: dayNoteText.implicitHeight
        visible: text !== "" && !(root.held && root.dimmed > 0)
        color: root.look.ground

        Text {
          id: dayNoteText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, parent.width)
          textFormat: Text.PlainText
          text: parent.text
          color: root.look.dim
          font.family: root.look.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        // Read where the chart is drawn, so the right edge reaches the last
        // trade.
        onPositionChanged: function(mouse) {
          if (!root.replayRunning) {
            var activeChart = root.look.retro ? root.retroChart : root.smoothChart
            if (activeChart) root.scrubRequested(activeChart.fractionAt(mouse.x))
          }
        }
        onExited: if (!root.replayRunning) root.scrubCleared()
        onClicked: root.snapToNow()
      }
    }

    // The blocks stand a band's gap apart, and the list's header a group's gap
    // over its rows (`StonksBody.groupGap`), so it groups with them.
    RangeSelector {
      id: rangeRow
      objectName: "rangeRow"
      width: parent.width
      options: root.rangeOptions
      value: root.range
      still: root.still
      seen: root.seen
      look: root.look
      onSelected: function(value) { root.rangeRequested(value) }
    }

    // Always two lines, so the list keeps its place.
    InfoTable {
      id: infoBlock
      width: parent.width
      height: implicitHeight
      lines: [root.periodLine, root.yearLine]
      // Every title a line can hold (`Figures.dayTitles`,
      // `Fundamentals.yearLine`).
      titles: root.rangeOptions.map(function(r) { return String(r).toUpperCase() }).concat(Figures.dayTitles(), ["52W"])
      factLists: root.factLists
      ranges: root.infoRanges
      look: root.look
      seen: root.seen
      still: root.still
      rowGap: Style.space(4)

      Rectangle {
        anchors.fill: parent
        visible: root.dimmed > 0
        color: root.veil
      }
    }

    ListHeader {
      id: listHeader
      width: parent.width
      listLabel: root.listLabel
      listMenuOpen: root.listMenuOpen
      rowsDay: root.rowsDay
      breadth: root.breadth
      rowsCovered: root.rowsCovered
      order: root.order
      reversed: root.reversed
      changeMode: root.changeMode
      look: root.look
      seen: root.seen
      still: root.still
      onListClicked: root.listClicked()
      onOrderClicked: root.orderClicked()
      onOrderReverseClicked: root.orderReverseClicked()
      onUnitClicked: root.changeClicked()
    }
  }
}
