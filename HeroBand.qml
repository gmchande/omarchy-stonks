import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Figures.js" as Figures
import "Settings.js" as Settings
import "Tones.js" as Tones
// Hero, chart, range row, info block, and the list and order rule. Every
// piece keeps its height for every symbol, range, and look, so the list
// below never moves. Surfaces own scrub and persist.
Item {
  id: root

  property var freshness: null
  // Yahoo is sending nothing for any listing (`Hero.sourceDown`).
  property bool sourceDown: false
  property bool retro: false
  property string changeMode: "pct"
  property bool scrubbing: false
  property bool live: false
  // The surface is closing: what moves stops where it is.
  property bool still: false
  // The chart on show is held while the next one loads: its live mark holds
  // still with it.
  property bool held: false
  // Once the next chart has been on its way a while, what is on show for the
  // held one dims, 0..1 (`ChartMotion.dimmed`), under a line naming what is
  // coming; the header's controls, the range row, and the list stay. The
  // dim is a veil of the ground laid over each, to 0.6: as if each faded to
  // 0.4 over it, with no layer to flatten first.
  property real dimmed: 0
  property string loadingText: ""
  readonly property color veil: Qt.rgba(ground.r, ground.g, ground.b, 0.6 * dimmed)
  // The newest print's price: a new one ripples the live dot, and blinks
  // retro's cap.
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
  // The draw-in's share of the ink, and a replay's place along the plot
  // (-1 without one), which each painter draws in behind.
  property real reveal: 1
  property real replayX: -1
  property int chartHeight: Style.space(190)
  property string order: "manual"
  property bool reversed: false
  property string listLabel: "All"
  // The day the rows measure (`Figures.rowsDay`): "TODAY", or "FRI".
  property string rowsDay: "TODAY"
  property var breadth: ({ list: "", up: 0, flat: 0, down: 0, none: 0 })
  property bool listMenuOpen: false
  property bool replayRunning: false
  // Search or a list view covers the rows: the header names the
  // list they act on and says nothing about rows out of sight.
  property bool rowsCovered: false
  property var rangeOptions: []
  property string range: "1D"
  // The info block's two lines, the day's or the range's over the 52 weeks;
  // every list of facts the first can hold on any range; and a range's own
  // high and low, marked on its chart (`History.rangeMarks`).
  property var periodLine: null
  property var yearLine: null
  property var factLists: []
  property var rangeMarks: null
  property string baselineText: ""
  // The clock, by which the hero's overnight print is old.
  property int now: 0
  // Whether the hero's change is the day's, which a click cycles.
  property bool changeCycles: true
  readonly property alias chartItem: heroChart
  // The retro chart's grid as drawn (`PixelChart.grid`), which a replay's
  // sound steps through in retro, a note a column.
  readonly property var pixelGrid: pixelChart.grid

  // The hero's change or the rows' unit sign, clicked: the unit steps.
  signal changeClicked()
  signal orderClicked()
  signal orderReverseClicked()
  signal listClicked()
  signal scrubRequested(real fraction)
  signal scrubCleared()
  signal snapToNow()
  signal rangeRequested(string range)

  // At rest as a surface opens: the rule on the list's breadth.
  function settle() { breadthRule.settle() }

  // Between the band's blocks, the body's rhythm (`StonksBody.bandGap`).
  property int bandGap: Style.space(16)

  implicitHeight: band.implicitHeight
  // The band's height but the chart's, summed from its other parts, so the
  // body can size the chart from it without reading the chart back.
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

      DayChart {
        id: dayChart
        visible: !root.retro
        anchors.fill: parent
        // The hidden look rests: it draws nothing, draws in nothing and
        // follows no scrub until it shows, so a new chart paints once.
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

      PixelChart {
        id: pixelChart
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
        anchors.fill: parent
        marks: root.rangeMarks
        chart: root.retro ? pixelChart : dayChart
        scrubX: root.scrubX
        foreground: root.foreground
        dim: root.dim
        fontFamily: root.fontFamily
      }

      // The held chart's veil; the chart that lands draws in at full ink.
      // It reaches as far past the chart as a mark can lift off it.
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: -rangeMarks.lift
        anchors.bottomMargin: -rangeMarks.lift
        visible: root.held && root.dimmed > 0
        color: root.veil
      }

      // What is coming, named over the dimmed chart; gone as it lands. With
      // no name, as while Yahoo sends nothing, it says nothing.
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

      // A day with one bar or none says so where its line would be, on a
      // patch of the ground so the dashed baseline stops short of it: a lone
      // dot or an empty chart read as broken (`Figures.dayNote`). Beside a
      // lone print it stands in the other half, clear of its dot or column.
      Rectangle {
        objectName: "dayNote"
        readonly property string text: root.geometry && root.geometry.day ? Figures.dayNote(root.day, root.now, root.calendars) : ""
        readonly property real printX: root.geometry && root.geometry.points.length === 1 ? root.geometry.points[0].x : -1
        x: (printX < 0 ? parent.width / 2 : printX > 0.5 ? parent.width / 4 : parent.width * 3 / 4) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(parent.width / (printX < 0 ? 1 : 2), dayNoteText.implicitWidth + Style.space(16))
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
        // The pointer reads the chart where it is drawn, so its right edge
        // reaches the last print, alone as a dot too.
        onPositionChanged: function(mouse) {
          if (!root.replayRunning) root.scrubRequested(root.retro ? mouse.x / width : dayChart.fractionAt(mouse.x))
        }
        onExited: if (!root.replayRunning) root.scrubCleared()
        onClicked: root.snapToNow()
      }
    }

    // The range row, then the info lines it chooses, then the list's header,
    // a band's gap apart, as every block in the band is; the header stands a
    // group's gap over its rows (the body's `listGap`), so it groups with
    // the rows it titles.
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

    // The day's or the range's, and the 52 weeks: two lines that are always
    // there, so the list keeps its place for every symbol and range.
    InfoTable {
      id: infoBlock
      objectName: "infoBlock"
      width: parent.width
      height: implicitHeight
      lines: [root.periodLine, root.yearLine]
      // Every title a line can hold: each range's, the day's 1D, weekday, or
      // month (`Figures.dayTitles`), and the 52 weeks'
      // (`Fundamentals.yearLine`).
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

    // The list's name, a menu, at the left of the rule, as Apple puts it at
    // the top of the list; the order control at the right, then the rows'
    // unit. The name starts at the rows' words, and the unit ends at the
    // figures it names, the band's own edges. Its height is the caption
    // line's, never a word's: a glyph drawn from another font is taller, and
    // would move the rows. A line of text rounds its ascent and its descent
    // up to whole pixels each, and so does this.
    Item {
      id: listHeader
      width: parent.width
      height: Math.ceil(captionLine.ascent) + Math.ceil(captionLine.descent)

      FontMetrics {
        id: captionLine
        font: orderText.font
      }

      Rectangle {
        objectName: "listControl"
        anchors.left: listText.left
        anchors.leftMargin: -Style.space(6)
        anchors.right: listChevron.right
        anchors.rightMargin: -Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height + Style.space(4)
        radius: root.retro ? 0 : Style.cornerRadius
        color: listMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
          : root.listMenuOpen ? Style.selectedFillFor(root.foreground, Commons.Color.accent)
          : listMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      Text {
        id: listText
        objectName: "listLabel"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - orderText.implicitWidth - todayText.implicitWidth
          - unitSign.width - orderText.anchors.rightMargin - Style.space(80))
        textFormat: Text.PlainText
        text: root.listLabel.toUpperCase()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
        elide: Text.ElideRight
      }

      Text {
        id: listChevron
        anchors.left: listText.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅀"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      MouseArea {
        id: listMouse
        anchors.left: listText.left
        anchors.right: listChevron.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: -Style.space(6)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.listClicked()
      }

      // The rows and the rule are the day's on every range, and say which
      // while the rows show.
      Text {
        id: todayText
        objectName: "todayLabel"
        visible: !root.rowsCovered
        anchors.left: listChevron.right
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.rowsDay
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
      }

      // The rule between the name and the order is the list's breadth. It
      // rests while the rows are covered and settles as they show again.
      BreadthRule {
        id: breadthRule
        objectName: "breadthRule"
        visible: !root.rowsCovered
        anchors.left: todayText.right
        anchors.leftMargin: Style.space(10)
        anchors.right: orderText.left
        anchors.rightMargin: Style.space(10)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        breadth: root.breadth
        retro: root.retro
        still: root.still || root.rowsCovered
        foreground: root.foreground
        dim: root.dim
        upColor: root.upColor
        downColor: root.downColor
        fontFamily: root.fontFamily
      }

      // The order control hovers the way a range token does: the fill and
      // the brighter word, so it reads as a control and not a label. In a
      // sorted order the arrow and the word are two controls, each with its
      // own fill: the arrow reverses the order, the word steps to the next.
      // Manual has no direction, so there they are one control that steps.
      Rectangle {
        objectName: "orderControl"
        visible: !root.rowsCovered
        anchors.right: orderText.right
        anchors.rightMargin: -Style.space(6)
        anchors.verticalCenter: orderText.verticalCenter
        width: orderText.sorted ? orderText.implicitWidth - orderText.wordStart + Style.space(12)
          : orderText.implicitWidth + Style.space(12)
        height: parent.height + Style.space(4)
        radius: root.retro ? 0 : Style.cornerRadius
        readonly property bool hovered: wordMouse.containsMouse || !orderText.sorted && arrowMouse.containsMouse
        readonly property bool pressed: wordMouse.pressed || !orderText.sorted && arrowMouse.pressed
        color: pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
          : hovered ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      // The arrow's fill pads it as the word's fill pads the word, so the two
      // read as two buttons; its target is wider, through the gap.
      Rectangle {
        objectName: "orderArrowFill"
        visible: !root.rowsCovered && orderText.sorted
        x: orderText.x - Style.space(6)
        width: Math.round(arrowMetrics.advanceWidth) + Style.space(12)
        anchors.verticalCenter: orderText.verticalCenter
        height: parent.height + Style.space(4)
        radius: root.retro ? 0 : Style.cornerRadius
        color: arrowMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
          : arrowMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      // The arrow alone, and the arrow with the two spaces after it, as the
      // label draws them.
      TextMetrics {
        id: arrowMetrics
        font: orderText.font
        text: orderText.text.slice(0, 1)
      }
      TextMetrics {
        id: gapMetrics
        font: orderText.font
        text: orderText.text.slice(0, 3)
      }

      Text {
        id: orderText
        objectName: "orderLabel"
        visible: !root.rowsCovered
        anchors.right: unitSign.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Settings.orderLabel(root.order, root.reversed)
        readonly property bool sorted: root.order !== "manual"
        // Where the word's first letter starts: the arrow's target runs up
        // to it, through the gap, and reaches left far enough to make the
        // shell's 22 px, though never past the gap before the breadth rule,
        // whose hover says the counts.
        readonly property real wordStart: Math.round(gapMetrics.advanceWidth)
        readonly property real arrowReach: Math.min(breadthRule.anchors.rightMargin,
          Math.max(Style.space(6), Style.space(22) - wordStart))
        // Only the hover's brightening eases.
        property real lift: arrowMouse.containsMouse || wordMouse.containsMouse ? 1 : 0
        Behavior on lift { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        // The list's name is the header's one word in full ink; the order
        // brightens only under the pointer.
        color: Qt.tint(root.dim, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, lift))
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1

        MouseArea {
          id: arrowMouse
          objectName: "orderArrow"
          x: -orderText.arrowReach
          y: -Style.space(6)
          width: orderText.arrowReach + orderText.wordStart
          height: parent.height + Style.space(12)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: orderText.sorted ? root.orderReverseClicked() : root.orderClicked()
        }

        // Its target reaches halfway into the gap before the unit, whose
        // target takes the other half.
        MouseArea {
          id: wordMouse
          x: orderText.wordStart
          y: -Style.space(6)
          width: parent.width - orderText.wordStart + orderText.anchors.rightMargin / 2
          height: parent.height + Style.space(12)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (mouse.modifiers & Qt.ShiftModifier) root.orderReverseClicked()
            else root.orderClicked()
          }
        }
      }

      // The rows' unit at the figures' edge, where a table puts a column's
      // unit: % for a percent, ± for an amount, and the market's bell for
      // since the open (`Cells.UNIT_SIGNS`), in the header icons' pen,
      // bright as a sorted order word. The signs are one width, so a step
      // moves nothing. A click steps the unit for every row, as c does; it
      // hovers and presses as the order word does.
      Rectangle {
        objectName: "unitFill"
        visible: !root.rowsCovered
        anchors.horizontalCenter: unitSign.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: unitSign.width + Style.space(12)
        height: parent.height + Style.space(4)
        radius: root.retro ? 0 : Style.cornerRadius
        color: unitMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
          : unitMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      GridIcon {
        id: unitSign
        objectName: "unitSign"
        visible: !root.rowsCovered
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        cell: Cells.iconCell(Style.fontScale)
        shape: Cells.UNIT_SIGNS[root.changeMode]
        color: unitMouse.containsMouse ? root.foreground : root.dim
      }

      MouseArea {
        id: unitMouse
        objectName: "unitTarget"
        visible: !root.rowsCovered
        anchors.left: unitSign.left
        anchors.leftMargin: -orderText.anchors.rightMargin / 2
        anchors.right: unitSign.right
        anchors.rightMargin: -Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height + Style.space(12)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.changeClicked()
      }
    }
  }
}
