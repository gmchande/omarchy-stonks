import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Figures.js" as Figures
import "Format.js" as Format
import "Tones.js" as Tones
// Featured symbol, listing line, the price in both looks, the change, and the
// caption strip under them. One box serves both looks: one fitted ink height
// drives both digit renderers, so they share a top line, a baseline, and a
// left edge however narrow it gets. The change and its caption are pinned to
// the hero's right edge, so they never move with what else is on show. The
// strip under the price carries the extended-hours print on the left (an
// overnight print with its own time, dimmed once it is old) and the change's
// caption on the right, and keeps its height when there is neither.
// Surfaces own scrub and persist.
Item {
  id: root

  property var view: null
  property var quote: null
  // The exchanges' calendars, for the time an "AS OF" names.
  property var calendars: null
  // The chart's day and the newest print of all (`Chart.viewChart`): the
  // line under the price names the newest print, by the day's clock,
  // against the quote's close.
  property var day: null
  property var latest: null
  property var freshness: null
  property bool retro: false
  // The change's unit and base, "pct", "abs", or "open": the line under the
  // price takes its unit (`Figures.extendedStack`).
  property string changeMode: "pct"
  property bool scrubbing: false
  // The clock, by which an overnight print is old.
  property int now: 0
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color ghost: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  property string fontFamily: Style.font.family
  property string symbol: ""
  // What the chart's dashed line is: said in the strip while a scrub reads
  // against it, where the extended-hours print steps aside.
  property string baselineText: ""
  property int priceSize: Style.font.displayLarge * 2

  readonly property string freshnessText: quote ? Figures.freshnessText(freshness, quote, calendars) : ""
  // The extended-hours print, on every range. A scrub's price is a past one,
  // so the print rests and the baseline's legend takes its place.
  readonly property var extended: quote && !scrubbing ? Figures.extendedStack(quote, latest, now, day, changeMode) : null
  readonly property string priceText: view ? view.priceText
    : (freshness && freshness.state === "failed" ? "—" : "…")
  readonly property string listingLead: {
    if (view && quote) {
      // Only a warning takes the mark; an aged quote is said plainly, as its
      // row says it.
      return (root.scrubbing || root.freshnessText === "" ? ""
        : (Figures.freshnessWarns(root.freshness) ? "! " : "") + root.freshnessText + " · ")
        + view.name.toUpperCase()
    }
    // A first fetch that failed: nothing was ever there to refresh, so it
    // says what the row says.
    return freshness && freshness.state === "failed" ? "! NO DATA FOR THIS SYMBOL"
      : freshness && freshness.state === "overdue" ? "! NO DATA" : ""
  }
  // The exchange and currency stay whole; the lead, the name last, gives
  // way to them. A name cut short no longer says the currency it ends with.
  readonly property string listingMeta: view && quote
    ? " · " + Figures.listingMeta(quote, listingMetrics.advanceWidth(listingLead + " · " + Figures.listingMeta(quote, false)) > listingRoom)
    : ""
  readonly property real listingRoom: Math.max(0, listingRow.width - symbolText.implicitWidth - Style.space(8))
  readonly property string changeCaption: view && view.periodLabel ? view.periodLabel
    : (extended !== null ? "AT CLOSE" : "")

  readonly property int gap: Style.space(28)
  // The digits' ink at the surface's price size, and the box kept for it: a
  // whole number of retro cells, so both renderers land on the same rows.
  readonly property real naturalInk: -digitInk.tightBoundingRect.y
  readonly property int naturalCell: Math.max(1, Math.floor(naturalInk / 5))
  readonly property int boxHeight: naturalCell * 5
  // The retro digits' width, from the price itself: the hidden look's
  // digits draw nothing, and the smooth size must not follow them.
  readonly property int cells: Cells.blockCells(priceText).columns
  readonly property real priceRoom: Math.max(1, width - gap - changeText.implicitWidth)
  // One fitted ink height for both looks: the largest cell at which each
  // renderer still fits the room the change leaves.
  readonly property int fittedCell: Math.max(1, Math.min(naturalCell,
    Math.floor(priceRoom * naturalInk / (5 * Math.max(1, priceInk.advanceWidth))),
    Math.floor(priceRoom / Math.max(1, cells))))
  readonly property int digitHeight: fittedCell * 5
  readonly property int fittedSize: Math.max(1, Math.round(priceSize * digitHeight / naturalInk))
  // Where the smooth digits' ink starts; the retro cells start there too.
  readonly property real inkLeft: priceInk.tightBoundingRect.x * fittedSize / priceSize
  readonly property int baselineY: listingRow.height + Style.space(14) + boxHeight
  // The strip under the price starts below the retro comma's tail, one cell
  // under the baseline, in both looks, so the look moves nothing.
  readonly property int captionDrop: naturalCell + Style.space(4) + Math.ceil(captionMetrics.capitalHeight)

  // Whether the change shown is the day's, which the change mode sets.
  property bool changeCycles: true
  signal changeClicked()

  // An unmoved figure is neither colour.
  function toneColor(tone) {
    return tone === "up" ? upColor : tone === "down" ? downColor : dim
  }

  implicitHeight: baselineY + captionDrop + Math.ceil(captionMetrics.descent)
  implicitWidth: parent ? parent.width : 0
  height: implicitHeight
  width: parent ? parent.width : implicitWidth

  TextMetrics {
    id: digitInk
    font.family: root.fontFamily
    font.pixelSize: root.priceSize
    font.bold: true
    text: "0123456789"
  }

  TextMetrics {
    id: priceInk
    font.family: root.fontFamily
    font.pixelSize: root.priceSize
    font.bold: true
    font.letterSpacing: -1
    text: root.priceText
  }

  FontMetrics {
    id: captionMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Row {
    id: listingRow
    width: parent.width
    Text {
      id: symbolText
      objectName: "heroSymbol"
      textFormat: Text.PlainText
      text: root.symbol || "—"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      id: listingText
      objectName: "listingLine"
      leftPadding: Style.space(8)
      width: Math.min(implicitWidth, leftPadding + Math.max(0, root.listingRoom - metaText.implicitWidth))
      anchors.baseline: symbolText.baseline
      textFormat: Text.PlainText
      text: root.listingLead
      color: Figures.freshnessWarns(root.freshness) ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
      elide: Text.ElideRight
    }
    Text {
      id: metaText
      objectName: "listingMeta"
      anchors.baseline: symbolText.baseline
      textFormat: Text.PlainText
      text: root.listingMeta
      color: listingText.color
      font: listingText.font
    }

    FontMetrics { id: listingMetrics; font: listingText.font }
  }

  Text {
    id: smoothPrice
    objectName: "smoothPrice"
    visible: !root.retro
    y: root.baselineY - baselineOffset
    textFormat: Text.PlainText
    text: root.priceText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fittedSize
    font.bold: true
    font.letterSpacing: -1
  }

  BlockDigits {
    id: blockDigits
    objectName: "blockPrice"
    visible: root.retro
    x: Math.max(0, Math.round(root.inkLeft))
    y: root.baselineY - baselineOffset
    // Hidden, it rests: a scrub in smooth repainted it every step.
    text: root.retro ? root.priceText : ""
    cell: root.fittedCell
    color: root.foreground
    ghostColor: root.ghost
  }

  Text {
    id: changeText
    objectName: "changeText"
    anchors.right: parent.right
    y: root.baselineY - baselineOffset
    textFormat: Text.PlainText
    text: root.view ? Format.lookSigns(root.view.changeText, root.retro) : ""
    color: root.toneColor(root.view ? root.view.tone : "flat")
    font.family: root.fontFamily
    font.pixelSize: Style.font.display
    font.bold: true
    // A click cycles the change mode only where the figure follows it: the
    // day's change. A range's change is always its percentage.
    MouseArea {
      anchors.fill: parent
      enabled: root.changeCycles
      cursorShape: Qt.PointingHandCursor
      onClicked: root.changeClicked()
    }
  }

  // The strip under the price: the extended-hours print on the left, always
  // in the same place and shape, and the change's caption on the right. An
  // old print is drawn in the dim colour, price and change too, so it reads
  // as old beside a fresh one and stays as legible as any dim text.
  Row {
    id: extendedLine
    objectName: "extendedLine"
    readonly property bool old: !!root.extended && root.extended.stale
    visible: root.extended !== null
    y: root.baselineY + root.captionDrop - extendedLabel.baselineOffset
    spacing: Style.space(6)

    Text {
      id: extendedLabel
      textFormat: Text.PlainText
      text: root.extended ? root.extended.label : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }
    Text {
      visible: text !== ""
      textFormat: Text.PlainText
      text: root.extended ? root.extended.time : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }
    Text {
      textFormat: Text.PlainText
      text: root.extended ? root.extended.price : ""
      color: extendedLine.old ? root.dim : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      text: root.extended ? Format.lookSigns(root.extended.changeText, root.retro) : ""
      color: extendedLine.old ? root.dim : root.toneColor(root.extended ? root.extended.tone : "flat")
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Text {
    objectName: "baselineLegend"
    visible: root.scrubbing && root.baselineText !== ""
    y: root.baselineY + root.captionDrop - baselineOffset
    textFormat: Text.PlainText
    text: "┄ " + root.baselineText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }

  Text {
    id: captionText
    objectName: "changeCaption"
    anchors.right: parent.right
    y: root.baselineY + root.captionDrop - baselineOffset
    textFormat: Text.PlainText
    text: root.changeCaption
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }
}
