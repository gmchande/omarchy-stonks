import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Figures.js" as Figures
import "Format.js" as Format
import "Tones.js" as Tones
// The symbol, the listing line, the price in both looks, the change, and the
// strip under them. One fitted ink height drives both digit renderers, so they
// share a top line, a baseline and a left edge at any width. The change and
// its caption keep to the right edge, so they never move with what else shows.
Item {
  id: root

  property var view: null
  property var quote: null
  // For the time an "AS OF" names.
  property var calendars: null
  // The line under the price names the newest print of all, by the day's
  // clock, against the quote's close.
  property var day: null
  property var latest: null
  property var freshness: null
  // Yahoo is sending nothing for any listing, which the header says once, so
  // this line says only when the price is from, as the rows do.
  property bool sourceDown: false
  readonly property var shownFreshness: sourceDown ? Figures.quietFreshness(freshness) : freshness
  property bool retro: false
  // The line under the price takes its unit.
  property string changeMode: "pct"
  property bool scrubbing: false
  // By which an overnight print is old.
  property int now: 0
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color ghost: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  property string fontFamily: Style.font.family
  property string symbol: ""
  // Where the header gives its title way (`HeaderStatus.titled`).
  property bool nameOnLine: false
  // The dashed line's legend, said in the strip while a scrub reads against
  // it, where the extended-hours print steps aside.
  property string baselineText: ""
  property int priceSize: Style.font.displayLarge * 2

  readonly property string freshnessText: quote ? Figures.freshnessText(shownFreshness, quote, calendars) : ""
  // The newest price since the close, when it is on top: the line under the
  // price is the close and its move, and the caption under the change the
  // move since it. None once its quote is gone, as a failed preview's is.
  readonly property var newest: quote && view && view.newest ? view.newest : null
  readonly property bool newestOld: Figures.newestStale(newest, now)
  // A scrub's price is a past one, so the line rests and the baseline's legend
  // takes its place.
  readonly property var extended: newest ? Figures.closeLine(quote, Figures.exchangeDay(quote, now), changeMode)
    : quote && !scrubbing ? Figures.extendedStack(quote, latest, now, day, changeMode) : null
  readonly property string priceText: view ? view.priceText
    : (freshness && freshness.state === "failed" ? "—" : "…")
  readonly property string listingLead: {
    if (view && quote) {
      // Only a warning takes the mark; an aged quote is said plainly, as its
      // row says it.
      var fresh = root.scrubbing || root.freshnessText === "" ? ""
        : (Figures.freshnessWarns(root.shownFreshness) ? "! " : "") + root.freshnessText
      return !root.nameOnLine ? fresh : (fresh ? fresh + " · " : "") + view.name.toUpperCase()
    }
    // A first fetch that failed says what the row says.
    return shownFreshness && shownFreshness.state === "failed" ? "! NO DATA FOR THIS SYMBOL"
      : shownFreshness && shownFreshness.state === "overdue" ? "! NO DATA" : ""
  }
  // The exchange and currency stay whole, and the lead gives way to them. A
  // name cut short, or in the header, no longer says the currency it ends with.
  readonly property string listingMeta: {
    if (!view || !quote) return ""
    var font = listingMetrics.font // read, so a new text size measures again
    var cut = !nameOnLine || listingMetrics.advanceWidth(listingLead + " · " + Figures.listingMeta(quote, false)) > listingRoom
    return (listingLead !== "" ? " · " : "") + Figures.listingMeta(quote, cut)
  }
  readonly property real listingRoom: Math.max(0, listingRow.width - symbolText.implicitWidth - Style.space(8))
  readonly property var caption: Figures.captionLine(quote, newest, changeMode, view && view.periodLabel ? view.periodLabel : "", extended !== null)
  // Drawn only clear of the strip's left side, so the two never meet.
  readonly property real captionRoom: width - Style.space(12)
    - Math.max(extendedLine.visible ? extendedLine.implicitWidth : 0, baselineLegend.visible ? baselineLegend.implicitWidth : 0)

  readonly property int gap: Style.space(28)
  // A whole number of retro cells, so both renderers land on the same rows.
  readonly property real naturalInk: -digitInk.tightBoundingRect.y
  readonly property int naturalCell: Math.max(1, Math.floor(naturalInk / 5))
  readonly property int boxHeight: naturalCell * 5
  // From the price itself: the hidden look's digits draw nothing.
  readonly property int cells: Cells.blockCells(priceText).columns
  readonly property real priceRoom: Math.max(1, width - gap - changeText.implicitWidth)
  // The largest cell at which each renderer fits the room the change leaves.
  readonly property int fittedCell: Math.max(1, Math.min(naturalCell,
    Math.floor(priceRoom * naturalInk / (5 * Math.max(1, priceInk.advanceWidth))),
    Math.floor(priceRoom / Math.max(1, cells))))
  readonly property int digitHeight: fittedCell * 5
  readonly property int fittedSize: Math.max(1, Math.round(priceSize * digitHeight / naturalInk))
  // How far into their box the smooth digits' ink starts: pulled left by it,
  // it starts on the band's edge, as the retro cells do.
  readonly property real inkLeft: priceInk.tightBoundingRect.x * fittedSize / priceSize
  readonly property int baselineY: listingRow.height + Style.space(14) + boxHeight
  // Below the retro comma's tail, one cell under the baseline, in both looks,
  // so the look moves nothing.
  readonly property int captionDrop: naturalCell + Style.space(4) + Math.ceil(captionMetrics.capitalHeight)

  property bool changeCycles: true
  signal changeClicked()

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
      color: Figures.freshnessWarns(root.shownFreshness) ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
      elide: Text.ElideRight
    }

    FontMetrics { id: listingMetrics; font: listingText.font }
  }

  // Starts where the name's drawn text ends, not its box: a name cut short
  // draws narrower, and the gap would read as a double space before the dot.
  Text {
    id: metaText
    objectName: "listingMeta"
    x: listingText.x + listingText.leftPadding + listingText.contentWidth
    y: symbolText.baselineOffset - baselineOffset
    textFormat: Text.PlainText
    text: root.listingMeta
    color: listingText.color
    font: listingText.font
  }

  Text {
    id: smoothPrice
    objectName: "smoothPrice"
    visible: !root.retro
    x: -Math.round(root.inkLeft)
    y: root.baselineY - baselineOffset
    textFormat: Text.PlainText
    text: root.priceText
    // An old night's price dims, as its line did.
    color: root.newestOld ? root.dim : root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fittedSize
    font.bold: true
    font.letterSpacing: -1
  }

  BlockDigits {
    id: blockDigits
    objectName: "blockPrice"
    visible: root.retro
    y: root.baselineY - baselineOffset
    // Hidden, it rests, or a scrub in smooth would repaint it every step.
    text: root.retro ? root.priceText : ""
    cell: root.fittedCell
    color: root.newestOld ? root.dim : root.foreground
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
    // A range's change is always its percentage, so only the day's cycles.
    MouseArea {
      anchors.fill: parent
      enabled: root.changeCycles
      cursorShape: Qt.PointingHandCursor
      onClicked: root.changeClicked()
    }
  }

  // The extended-hours print on the left, always in the same place and shape;
  // the change's caption on the right. An old print is drawn dim, price and
  // change too, so it reads as old beside a fresh one.
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
    id: baselineLegend
    objectName: "baselineLegend"
    visible: root.scrubbing && root.baselineText !== ""
    y: root.baselineY + root.captionDrop - baselineOffset
    textFormat: Text.PlainText
    text: root.baselineText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }

  Row {
    id: captionLine
    objectName: "changeCaption"
    visible: root.caption.label !== "" && implicitWidth <= root.captionRoom
    anchors.right: parent.right
    y: root.baselineY + root.captionDrop - captionLabel.baselineOffset
    spacing: Style.space(6)

    Text {
      id: captionLabel
      textFormat: Text.PlainText
      text: root.caption.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }
    // The move since the close dims with an old night's price.
    Text {
      visible: text !== ""
      textFormat: Text.PlainText
      text: Format.lookSigns(root.caption.changeText, root.retro)
      color: root.newestOld ? root.dim : root.toneColor(root.caption.tone)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
