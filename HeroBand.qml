import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Figures.js" as Figures
import "Tones.js" as Tones
// The hero, the chart, the range row, the info block and the list's header.
// Each keeps its height for every symbol, range and look, so the list below
// never moves.
Item {
  id: root

  property var freshness: null
  // Yahoo is sending nothing for any listing (`Hero.sourceDown`).
  property bool sourceDown: false
  property bool retro: false
  property string changeMode: "pct"
  property bool scrubbing: false
  property bool live: false
  // Closing: what moves stops where it is.
  property bool still: false
  // The chart on show waits for the next: its live mark holds still with it.
  property bool held: false
  // Once the next chart is a while on its way, the held one dims under a line
  // naming what's coming (`ChartMotion.dimmed`): a veil of the ground over each
  // piece, to 0.6, as if each faded to 0.4 with no layer to flatten first.
  property real dimmed: 0
  property string loadingText: ""
  readonly property color veil: Qt.rgba(ground.r, ground.g, ground.b, 0.6 * dimmed)
  // A new one ripples the live dot, and blinks retro's cap.
  readonly property string newestPrice: root.day && root.day.points && root.day.points.length
    ? String(root.day.points[root.day.points.length - 1].p) : ""
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color dimmer: Tones.dimmer(foreground, Commons.Color.background)
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color ghost: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  // The surface under the chart, which the wash is seen against.
  property color ground: Commons.Color.background
  property string fontFamily: Style.font.family
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
  // the first can hold on any range; and a range's high and low on its chart.
  property var periodLine: null
  property var yearLine: null
  property var factLists: []
  property var rangeMarks: null
  property string baselineText: ""
  // The clock, by which the hero's overnight trade is old.
  property int now: 0
  // Whether the hero's change is the day's, which a click cycles.
  property bool changeCycles: true
  readonly property alias chartItem: heroChart
  // A replay's sound steps through it in retro, a note a column.
  readonly property var pixelGrid: retroChart.grid

  // The hero's change or the rows' unit, clicked: the unit steps.
  signal changeClicked()
  signal orderClicked()
  signal orderReverseClicked()
  signal listClicked()
  signal scrubRequested(real fraction)
  signal scrubCleared()
  signal snapToNow()
  signal rangeRequested(string range)

  function settle() { listHeader.settle() }

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
      retro: root.retro
      changeMode: root.changeMode
      scrubbing: root.scrubbing
      now: root.now
      foreground: root.foreground
      dim: root.dim
      upColor: root.upColor
      downColor: root.downColor
      ghost: root.ghost
      fontFamily: root.fontFamily
      baselineText: root.baselineText
      changeCycles: root.changeCycles
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

      SmoothChart {
        id: smoothChart
        visible: !root.retro
        anchors.fill: parent
        // The hidden look draws nothing and follows no scrub until it shows,
        // so a new chart paints once.
        geometry: root.retro ? null : root.geometry
        up: root.view ? root.view.dayUp : true
        upColor: root.upColor
        downColor: root.downColor
        baselineColor: root.dimmer
        hairlineColor: root.foreground
        ground: root.ground
        scrubX: root.retro ? -1 : root.scrubX
        reveal: root.retro ? 1 : root.reveal
        replayX: root.retro ? -1 : root.replayX
        live: root.live && !root.retro
        newestPrice: root.newestPrice
        surfaceOpen: !root.still
        still: root.still || root.held
      }

      RetroChart {
        id: retroChart
        visible: root.retro
        anchors.fill: parent
        geometry: root.retro ? root.geometry : null
        upColor: root.upColor
        downColor: root.downColor
        up: root.view ? root.view.dayUp : true
        baselineColor: root.dimmer
        glow: true
        live: root.live && root.retro
        newestPrice: root.newestPrice
        surfaceOpen: !root.still
        still: root.still || root.held
        hairlineColor: root.foreground
        ghostColor: root.ghost
        ground: root.ground
        scrubX: root.retro ? root.scrubX : -1
        reveal: root.retro ? root.reveal : 1
        replayX: root.retro ? root.replayX : -1
      }

      RangeMarks {
        id: rangeMarks
        parent: rangeMarks.chart.underScrub
        anchors.fill: parent
        marks: root.rangeMarks
        chart: root.retro ? retroChart : smoothChart
        foreground: root.foreground
        dim: root.dim
        fontFamily: root.fontFamily
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

      // With no name, as while Yahoo sends nothing, it says nothing.
      Text {
        objectName: "loadingLabel"
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width)
        visible: root.held && root.dimmed > 0 && root.loadingText !== ""
        opacity: root.dimmed
        textFormat: Text.PlainText
        text: root.loadingText + "…"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
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
        color: root.ground

        Text {
          id: dayNoteText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, parent.width)
          textFormat: Text.PlainText
          text: parent.text
          color: root.dim
          font.family: root.fontFamily
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
          if (!root.replayRunning) root.scrubRequested(root.retro ? retroChart.fractionAt(mouse.x) : smoothChart.fractionAt(mouse.x))
        }
        onExited: if (!root.replayRunning) root.scrubCleared()
        onClicked: root.snapToNow()
      }
    }

    // The blocks stand a band's gap apart, and the list's header a group's gap
    // over its rows (`listGap`), so it groups with them.
    RangeSelector {
      id: rangeRow
      objectName: "rangeRow"
      width: parent.width
      options: root.rangeOptions
      value: root.range
      retro: root.retro
      foreground: root.foreground
      dim: root.dim
      fontFamily: root.fontFamily
      onSelected: function(value) { root.rangeRequested(value) }
    }

    // Always two lines, so the list keeps its place.
    InfoTable {
      id: infoBlock
      objectName: "infoBlock"
      width: parent.width
      height: implicitHeight
      lines: [root.periodLine, root.yearLine]
      // Every title a line can hold (`Figures.dayTitles`,
      // `Fundamentals.yearLine`).
      titles: root.rangeOptions.map(function(r) { return String(r).toUpperCase() }).concat(Figures.dayTitles(), ["52W"])
      factLists: root.factLists
      retro: root.retro
      foreground: root.foreground
      dim: root.dim
      upColor: root.upColor
      downColor: root.downColor
      fontFamily: root.fontFamily
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
      retro: root.retro
      still: root.still
      foreground: root.foreground
      dim: root.dim
      upColor: root.upColor
      downColor: root.downColor
      fontFamily: root.fontFamily
      onListClicked: root.listClicked()
      onOrderClicked: root.orderClicked()
      onOrderReverseClicked: root.orderReverseClicked()
      onUnitClicked: root.changeClicked()
    }
  }
}
