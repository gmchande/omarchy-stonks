import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Figures.js" as Figures
import "Format.js" as Format
import "Tones.js" as Tones
// Featured symbol, listing line, the price in both looks, the change, and the
// caption strip under them. One fitted ink height drives both digit
// renderers, so they share a top line, a baseline, and a left edge at any
// width. The change and its caption are pinned to the right edge, so they
// never move with what else is on show. Surfaces own scrub and persist.
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
  // Yahoo is sending nothing for any listing, which the header says once:
  // the listing line says only when the price is from, as the rows do
  // (`Figures.quietFreshness`). A failed first answer still shows "—".
  property bool sourceDown: false
  readonly property var shownFreshness: sourceDown ? Figures.quietFreshness(freshness) : freshness
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
  // The name on this line, where the header gives its title way
  // (`HeaderStatus.titled`).
  property bool nameOnLine: false
  // What the chart's dashed line is: said in the strip while a scrub reads
  // against it, where the extended-hours print steps aside.
  property string baselineText: ""
  property int priceSize: Style.font.displayLarge * 2

  readonly property string freshnessText: quote ? Figures.freshnessText(shownFreshness, quote, calendars) : ""
  // The newest price since the close, when it is the one on top
  // (`Figures.rowModel`): its session and time are said under the change,
  // and the line under the price is the close and its day's move. None
  // while the quote it is from is gone, as a failed preview's is.
  readonly property var newest: quote && view && view.newest ? view.newest : null
  readonly property bool newestOld: Figures.newestStale(newest, now)
  // The line under the price: with the newest price on top, the close and
  // the move since it (`Figures.closeLine`); else the extended-hours print,
  // on every range. A scrub's price is a past one, so the line rests and
  // the baseline's legend takes its place.
  readonly property var extended: newest ? Figures.closeLine(quote, Figures.exchangeDay(quote, now), changeMode, newest)
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
    // A first fetch that failed: nothing was ever there to refresh, so it
    // says what the row says.
    return shownFreshness && shownFreshness.state === "failed" ? "! NO DATA FOR THIS SYMBOL"
      : shownFreshness && shownFreshness.state === "overdue" ? "! NO DATA" : ""
  }
  // The exchange and currency stay whole; the lead, a name last, gives way
  // to them. A name cut short, or in the header, no longer says the
  // currency it ends with.
  readonly property string listingMeta: {
    if (!view || !quote) return ""
    var font = listingMetrics.font // read, so a new text size measures again
    var cut = !nameOnLine || listingMetrics.advanceWidth(listingLead + " · " + Figures.listingMeta(quote, false)) > listingRoom
    return (listingLead !== "" ? " · " : "") + Figures.listingMeta(quote, cut)
  }
  readonly property real listingRoom: Math.max(0, listingRow.width - symbolText.implicitWidth - Style.space(8))
  // Under the change: with the newest price on top, its session and time,
  // after the range's name on a longer range or SINCE OPEN
  // (`Figures.newestCaptions`); else what the change is measured from. The
  // longest form that fits beside what the strip shows on the left, the
  // line under the price or a scrub's baseline, so the two never meet; none
  // where even the shortest doesn't fit.
  readonly property var newestCaptions: newest
    ? Figures.newestCaptions(quote, newest, now, calendars, view && view.periodLabel ? view.periodLabel : "") : null
  readonly property real captionRoom: width - Style.space(12)
    - Math.max(extendedLine.visible ? extendedLine.implicitWidth : 0, baselineLegend.visible ? baselineLegend.implicitWidth : 0)
  readonly property string changeCaption: {
    var forms = newestCaptions || [view && view.periodLabel ? view.periodLabel : (extended !== null ? "AT CLOSE" : "")]
    var font = captionMetrics.font // read, so a new text size measures again
    for (var i = 0; i < forms.length; i++) {
      // The caption's letter spacing is a pixel a letter.
      if (forms[i] === "" || captionMetrics.advanceWidth(forms[i]) + forms[i].length <= captionRoom) return forms[i]
    }
    return ""
  }

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
  // Where the smooth digits' ink starts in their box: they are pulled left
  // by it, so their ink, like the retro cells, starts on the band's edge.
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
      color: Figures.freshnessWarns(root.shownFreshness) ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
      elide: Text.ElideRight
    }

    FontMetrics { id: listingMetrics; font: listingText.font }
  }

  // The exchange and currency start where the name's drawn text ends, not
  // where its box does: a name cut short draws narrower than its box, and
  // the gap would read as a double space before the dot.
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
    // An old night's price dims, as its line under the price did.
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
    // Hidden, it rests: otherwise a scrub in smooth repaints it every step.
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
  // in the same place and shape, and the change's caption on the right; it
  // keeps its height when there is neither. An old print is drawn dim, price
  // and change too, so it reads as old beside a fresh one.
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
    // After the close, on its own day, the move since it (`Figures.closeLine`).
    Text {
      visible: !!root.extended && !!root.extended.since
      textFormat: Text.PlainText
      text: "·"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Text {
      visible: !!root.extended && !!root.extended.since
      textFormat: Text.PlainText
      text: root.extended && root.extended.since ? Format.lookSigns(root.extended.since, root.retro) : ""
      color: root.toneColor(root.extended && root.extended.since ? root.extended.sinceTone : "flat")
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Text {
      visible: !!root.extended && !!root.extended.since
      textFormat: Text.PlainText
      text: "SINCE"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
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
