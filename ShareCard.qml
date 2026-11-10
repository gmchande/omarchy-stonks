pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Format.js" as Format
import "History.js" as History
import "Share.js" as Share
import "Tones.js" as Tones
// The screenshot: what the panel shows above its ranges, never the list, laid
// out again at 1200 × 675 (16:9, which X shows whole), with the panel's two
// lines under the price and the move (`Figures.heroLines`) and the facts the
// panel leaves out (`Share.words`), in the surface's look and colours. Drawn
// at twice that in the screen's own pixels on a screen of any scale, so its
// canvases paint sharp and no larger than the picture: every measure is in
// `u`, the layout's unit in window units. Built for a shot and gone after it.
Rectangle {
  id: root

  property string symbol: ""
  // As the surface has them; `marks` is a range's high and low.
  property var quote: null
  property var day: null
  property var history: null
  property var marks: null
  property var latest: null
  property var view: null
  property int scrubT: 0
  property string changeMode: "pct"
  property string range: "1D"
  property int now: 0
  property var calendars: null
  property bool retro: false
  // "bull", "bear", or "" on a flat day.
  property string animalKind: ""
  property bool asleep: false
  property color foreground: Commons.Color.foreground
  property color ground: Commons.Color.background
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property string fontFamily: Style.font.family

  // `px` is one of the picture's pixels in window units: half a unit on a
  // scale-2 screen.
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  readonly property real u: 2 / dpr
  readonly property real px: 1 / dpr
  readonly property real margin: 64 * u
  readonly property color dim: Tones.dim(foreground, ground)
  readonly property color dimmer: Tones.dimmer(foreground, ground)
  readonly property color ghost: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  readonly property var words: quote && day ? Share.words({ quote: quote, day: day, history: history, latest: latest,
    newest: view ? view.newest : null, scrubT: scrubT, changeMode: changeMode, calendars: calendars }) : null
  readonly property var lines: Figures.heroLines(quote, view, latest, now, day, calendars, changeMode, scrubT !== 0)
  // Since the open, the open the move counts from takes the line under the
  // price, at rest and scrubbed (`Share.words`).
  readonly property var open: words && words.open ? words.open : null
  // A scrub's move counts from the line under the pointer, named as the
  // panel names it.
  readonly property string legend: !scrubT || !quote || open ? ""
    : history ? "┄ " + String(range).toUpperCase() + " START " + Format.money(history.baseline, quote.priceDigits)
    : day ? "┄ " + Figures.scrubBaselineText(day, scrubT, Figures.exchangeDay(day, now), calendars) : ""
  readonly property var shownDay: Share.pictureDay(day)
  readonly property var geometry: history ? History.historyGeometry(history) : shownDay ? Chart.chartGeometry(shownDay, calendars) : null
  readonly property real scrubX: !scrubT ? -1 : history ? History.historyFraction(history, scrubT)
    : shownDay ? Chart.fractionAtTime(shownDay, scrubT) : -1

  function toneColor(tone) {
    return tone === "up" ? upColor : tone === "down" ? downColor : dim
  }

  width: 1200 * u
  height: 675 * u
  color: ground

  // The name gives way to the exchange, which stays whole.
  Text {
    id: symbolText
    objectName: "shareSymbol"
    x: root.margin
    y: 96 * root.u - baselineOffset
    textFormat: Text.PlainText
    text: root.symbol
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: 40 * root.u
    font.bold: true
  }
  Text {
    id: nameText
    objectName: "shareName"
    readonly property real room: animal.x - 32 * root.u - x - metaText.implicitWidth
    x: symbolText.x + symbolText.implicitWidth + 20 * root.u
    width: Math.max(0, Math.min(implicitWidth, room))
    anchors.baseline: symbolText.baseline
    textFormat: Text.PlainText
    text: root.quote ? String(root.quote.name || "") : ""
    elide: Text.ElideRight
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: 24 * root.u
    font.bold: true
  }
  Text {
    id: metaText
    objectName: "shareListing"
    x: nameText.x + nameText.width
    anchors.baseline: symbolText.baseline
    textFormat: Text.PlainText
    text: root.quote ? " · " + root.quote.exchange : ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: 18 * root.u
    font.bold: true
    font.letterSpacing: 2 * root.u
  }

  // As the header draws it, the same in both looks.
  PixelSprite {
    id: animal
    objectName: "shareAnimal"
    visible: root.animalKind !== ""
    x: root.width - root.margin - width
    y: 52 * root.u
    width: 80 * root.u
    height: 56 * root.u
    pixels: Cells.spriteFor(root.animalKind === "bull", root.asleep ? 2 : 0)
    pixelRatio: root.dpr
    color: root.animalKind === "bull" ? root.upColor : root.downColor
  }
  PixelSprite {
    visible: animal.visible && root.asleep
    columns: 3
    rows: 5
    x: animal.x - width - 4 * root.u
    y: animal.y - 4 * root.u
    width: 12 * root.u
    height: 20 * root.u
    pixels: Cells.spritePixels(Cells.SLEEP_Z)
    pixelRatio: root.dpr
    color: root.dim
  }

  // As large as the room the move leaves it.
  readonly property string priceText: view ? view.priceText : "—"
  readonly property real priceRoom: width - margin * 2 - changeText.implicitWidth - 48 * u
    - currencyText.implicitWidth - currencyGap
  readonly property real currencyGap: currencyText.text ? 16 * u : 0
  // At the size the price is drawn at on a scale-1 screen, so the sizes it gives
  // are the same on every screen.
  TextMetrics {
    id: priceInk
    font.family: root.fontFamily
    font.pixelSize: 240
    font.bold: true
    font.letterSpacing: -2
    text: root.priceText
  }
  TextMetrics {
    id: digitInk
    font: priceInk.font
    text: "0123456789"
  }
  readonly property real priceScale: Math.min(1, priceRoom * dpr / Math.max(1, priceInk.advanceWidth))
  readonly property real cell: Math.max(1, Math.floor(Math.min(-digitInk.tightBoundingRect.y * priceScale / 5,
    priceRoom * dpr / Math.max(1, Cells.blockCells(priceText).columns)))) * px
  readonly property real priceBaseline: 222 * u
  Text {
    id: priceSmooth
    objectName: "sharePrice"
    visible: !root.retro
    x: root.margin - Math.round(priceInk.tightBoundingRect.x * root.priceScale) * root.px
    y: root.priceBaseline - baselineOffset
    textFormat: Text.PlainText
    text: root.priceText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Math.round(240 * root.priceScale) * root.px
    font.bold: true
    font.letterSpacing: -1 * root.u
  }
  BlockDigits {
    id: priceRetro
    visible: root.retro
    x: root.margin
    y: root.priceBaseline - baselineOffset
    text: root.retro ? root.priceText : ""
    cell: root.cell
    gap: root.px
    color: root.foreground
    ghostColor: root.ghost
  }
  // Set like a unit, dim at the ticker's size: a price in pence says "PENCE".
  Text {
    id: currencyText
    objectName: "shareCurrency"
    x: (root.retro ? priceRetro.x + priceRetro.width : priceSmooth.x + priceSmooth.implicitWidth) + root.currencyGap
    y: root.priceBaseline - baselineOffset
    textFormat: Text.PlainText
    text: root.words ? root.words.currency : ""
    color: root.dim
    font: symbolText.font
  }
  Text {
    id: changeText
    objectName: "shareChange"
    anchors.right: parent.right
    anchors.rightMargin: root.margin
    y: root.priceBaseline - baselineOffset
    textFormat: Text.PlainText
    text: root.view ? Format.lookSigns(root.view.changeText, root.retro) : ""
    color: root.toneColor(root.view ? root.view.tone : "flat")
    font.family: root.fontFamily
    font.pixelSize: 64 * root.u
    font.bold: true
  }

  // The panel's two lines, as the panel says them: under the price the close
  // before it, under the move its name and the same move in the other unit.
  component Caption: Text {
    textFormat: Text.PlainText
    visible: text !== ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: 18 * root.u
    font.bold: true
    font.letterSpacing: 2 * root.u
  }
  component Figure: Text {
    textFormat: Text.PlainText
    visible: text !== ""
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: 18 * root.u
    font.bold: true
  }
  readonly property var close: open ? { label: open.label, time: "", price: open.price, changeText: "", tone: "flat", stale: false } : lines.close
  Row {
    objectName: "shareClose"
    x: root.margin
    y: 266 * root.u - closeLabel.baselineOffset
    spacing: 10 * root.u
    Caption {
      id: closeLabel
      text: root.legend !== "" ? root.legend : root.close ? root.close.label : ""
    }
    Caption { text: root.close ? root.close.time : "" }
    Figure {
      text: root.close ? root.close.price : ""
      color: root.close && root.close.stale ? root.dim : root.foreground
    }
    Figure {
      text: root.close ? Format.lookSigns(root.close.changeText, root.retro) : ""
      color: root.close && root.close.stale ? root.dim : root.toneColor(root.close ? root.close.tone : "flat")
    }
    Caption { text: root.close && root.close.since ? "· " + root.close.since.label : "" }
    Figure {
      text: root.close && root.close.since ? Format.lookSigns(root.close.since.changeText, root.retro) : ""
      color: root.toneColor(root.close && root.close.since ? root.close.since.tone : "flat")
    }
  }
  Row {
    objectName: "shareCaption"
    x: root.width - root.margin - width
    y: 266 * root.u - captionLabel.baselineOffset
    spacing: 10 * root.u
    Caption { id: captionLabel; text: root.lines.caption.label }
    Figure {
      text: Format.lookSigns(root.lines.caption.changeText, root.retro)
      color: root.toneColor(root.lines.caption.tone)
    }
  }

  // At twice its strokes and cells, still: no draw-in, ripple or blink. A range
  // says its dates once at the foot, so its chart takes the axis row's height.
  Item {
    id: chart
    x: root.margin
    y: 296 * root.u
    width: root.width - root.margin * 2
    height: (root.history ? 294 : 270) * root.u

    DayChart {
      id: dayChart
      objectName: "shareDayChart"
      visible: !root.retro
      anchors.fill: parent
      weight: root.u
      dashUnit: 2
      geometry: root.retro ? null : root.geometry
      up: root.view ? root.view.dayUp : true
      upColor: root.upColor
      downColor: root.downColor
      baselineColor: root.dimmer
      hairlineColor: root.foreground
      ground: root.ground
      scrubX: root.scrubX
      surfaceOpen: false
      still: true
    }
    PixelChart {
      id: pixelChart
      visible: root.retro
      anchors.fill: parent
      pixel: 8 * root.u
      gap: 2 * root.u
      geometry: root.retro ? root.geometry : null
      up: root.view ? root.view.dayUp : true
      upColor: root.upColor
      downColor: root.downColor
      baselineColor: root.dimmer
      hairlineColor: root.foreground
      ghostColor: root.ghost
      ground: root.ground
      glow: true
      scrubX: root.scrubX
      surfaceOpen: false
      still: true
    }
    RangeMarks {
      id: rangeMarks
      parent: rangeMarks.chart.underScrub
      anchors.fill: parent
      marks: root.marks
      chart: root.retro ? pixelChart : dayChart
      foreground: root.foreground
      dim: root.dim
      fontFamily: root.fontFamily
      fontSize: 18 * root.u
      letterSpacing: root.u
      spacing: 1.8 * root.u
    }
    Rectangle {
      readonly property string text: root.geometry && root.geometry.day ? Figures.dayNote(root.day, root.now, root.calendars) : ""
      visible: text !== ""
      anchors.centerIn: parent
      width: noteText.implicitWidth + 32 * root.u
      height: noteText.implicitHeight
      color: root.ground
      Text {
        id: noteText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: parent.text
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 20 * root.u
      }
    }
  }

  Caption {
    objectName: "shareStart"
    x: root.margin
    y: 596 * root.u - baselineOffset
    font.letterSpacing: 1 * root.u
    text: root.words ? root.words.start : ""
  }
  Caption {
    objectName: "shareEnd"
    x: root.width - root.margin - implicitWidth
    y: 596 * root.u - baselineOffset
    font.letterSpacing: 1 * root.u
    text: root.words ? root.words.end : ""
  }

  Rectangle {
    x: root.margin
    y: 616 * root.u
    width: root.width - root.margin * 2
    height: root.u
    color: root.ghost
  }

  // When the price on top is from. Spaced as the day's axis is, so it stays
  // clear of the logo. The logo's bull is in the name's ink, whatever the
  // day's animal: on a down day a green bull would read as the day's.
  Caption {
    objectName: "shareFoot"
    x: root.margin
    y: 654 * root.u - baselineOffset
    font.pixelSize: 28 * root.u
    text: root.words ? root.words.foot : ""
  }
  Text {
    id: forOmarchy
    x: root.width - root.margin - implicitWidth
    y: 654 * root.u - baselineOffset
    textFormat: Text.PlainText
    text: "for Omarchy"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: 28 * root.u
  }
  Text {
    id: stonksText
    x: forOmarchy.x - implicitWidth - 12 * root.u
    y: 654 * root.u - baselineOffset
    textFormat: Text.PlainText
    text: "Stonks"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: 28 * root.u
    font.bold: true
  }
  PixelSprite {
    objectName: "shareLogo"
    readonly property real cell: 2 * root.u
    x: stonksText.x - width - 14 * root.u
    y: 654 * root.u - height
    width: columns * cell
    height: rows * cell
    pixels: Cells.spriteFor(true, 0)
    pixelRatio: root.dpr
    color: root.foreground
  }
}
