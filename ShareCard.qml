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
// The screenshot: the chart on show laid out again for sharing, 1200 × 675
// (16:9, which X shows whole), drawn at twice that, 2400 × 1350 of the
// screen's own pixels on a screen of any scale, so its canvases paint
// sharp and no larger than the picture: every measure is in the layout's
// units, `u` window units each. What the popup shows above its ranges, at
// share size, with the facts it leaves out (`Share.words`): the symbol,
// its name and exchange; the day's animal, as the header draws it; the
// price, with its currency beside it as a unit, and its move, large; what
// the price is, its time and zone, a range's date, and what the move is
// measured from; the line under the price the popup shows; the chart, its
// axis ending at the newest price, with the scrub; and at the foot when,
// the day's date or the range's length, and Stonks' mark. Never the list.
// In the surface's look and colours. Built for a shot and gone after it
// (`StonksBody`).
Rectangle {
  id: root

  property string symbol: ""
  // Yahoo's quote, the 1D chart's day, a range's history (null on the
  // day), the newest print of all, and the price on show (`Figures.rowModel`
  // or `History.historyRowModel`), as the surface has them.
  property var quote: null
  property var day: null
  property var history: null
  property var latest: null
  property var view: null
  property int scrubT: 0
  property string changeMode: "pct"
  property string range: "1D"
  property int now: 0
  property var calendars: null
  property bool retro: false
  // The header's animal: "bull", "bear", or "" on a flat day, and asleep
  // while its market rests.
  property string animalKind: ""
  property bool asleep: false
  property color foreground: Commons.Color.foreground
  property color ground: Commons.Color.background
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property string fontFamily: Style.font.family

  // A layout unit is a pixel of the 2400 × 1350 picture: 2 to the picture's
  // 1200 × 675, so on a screen of any scale the card draws at the size it
  // is saved at, its canvases no larger. `px` is one of the picture's
  // pixels in the window's units: half a unit on a scale-2 screen.
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  readonly property real u: 2 / dpr
  readonly property real px: 1 / dpr
  readonly property real margin: 64 * u
  readonly property color dim: Tones.dim(foreground, ground)
  readonly property color dimmer: Tones.dimmer(foreground, ground)
  readonly property color ghost: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  readonly property var words: quote && day ? Share.words({ quote: quote, day: day, history: history, latest: latest,
    scrubT: scrubT, changeMode: changeMode, range: range, now: now, calendars: calendars }) : null
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

  // The symbol, its name, and exchange: the name gives way to the
  // exchange, which stays whole. The currency is the price's (below).
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
    text: root.quote ? String(root.quote.name || "").toUpperCase() : ""
    elide: Text.ElideRight
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: 18 * root.u
    font.bold: true
    font.letterSpacing: 2 * root.u
  }
  Text {
    id: metaText
    objectName: "shareListing"
    x: nameText.x + nameText.width
    anchors.baseline: symbolText.baseline
    textFormat: Text.PlainText
    text: root.quote ? " · " + root.quote.exchange : ""
    color: root.dim
    font: nameText.font
  }

  // The day's animal, as the header draws it, the same in both looks.
  PixelSprite {
    id: animal
    objectName: "shareAnimal"
    visible: root.animalKind !== ""
    x: root.width - root.margin - width
    y: 52 * root.u
    width: 80 * root.u
    height: 56 * root.u
    pixels: Cells.spriteFor(root.animalKind === "bull", root.asleep ? 2 : 0)
    color: root.animalKind === "bull" ? root.upColor : root.downColor
  }
  // Asleep, the header's dim "z" over its back.
  PixelSprite {
    visible: animal.visible && root.asleep
    columns: 3
    rows: 5
    x: animal.x - width - 4 * root.u
    y: animal.y - 4 * root.u
    width: 12 * root.u
    height: 20 * root.u
    pixels: Cells.spritePixels(Cells.SLEEP_Z)
    color: root.dim
  }

  // The price, as large as the room the move leaves it, in the look's
  // digits, and the move pinned to the right edge on the same baseline.
  readonly property string priceText: view ? view.priceText : "—"
  // The price gives up the currency's width when room is short.
  readonly property real priceRoom: width - margin * 2 - changeText.implicitWidth - 48 * u
    - currencyText.implicitWidth - currencyGap
  readonly property real currencyGap: 16 * u
  // Measured in the picture's pixels, at the size the price is drawn at on
  // a scale-1 screen, so the sizes it gives are the same on every screen.
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
  // The currency beside the price, set like a unit, on its baseline, dim
  // and at the ticker's size: a price in pence says "GBp".
  Text {
    id: currencyText
    objectName: "shareCurrency"
    x: (root.retro ? priceRetro.x + priceRetro.width : priceSmooth.x + priceSmooth.implicitWidth) + root.currencyGap
    y: root.priceBaseline - baselineOffset
    textFormat: Text.PlainText
    text: root.quote ? String(root.quote.currency || "") : ""
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

  // What the price is, its time and zone, and on a range its date (on the
  // day the foot says it); and what the move is measured from, the chart's
  // dashed line.
  component Caption: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: 18 * root.u
    font.bold: true
    font.letterSpacing: 2 * root.u
  }
  Caption {
    id: whenText
    objectName: "shareWhen"
    x: root.margin
    y: 266 * root.u - baselineOffset
    width: Math.min(implicitWidth, fromText.x - x - 32 * root.u)
    elide: Text.ElideRight
    text: root.words ? root.words.when : ""
  }
  Caption {
    id: fromText
    objectName: "shareFrom"
    x: root.width - root.margin - implicitWidth
    y: 266 * root.u - baselineOffset
    text: root.words ? root.words.from : ""
  }
  // The line under the price the popup shows, an old overnight print dim.
  Caption {
    objectName: "shareExtended"
    x: root.margin
    y: 294 * root.u - baselineOffset
    text: root.words ? Format.lookSigns(root.words.extended, root.retro) : ""
    color: root.words && root.words.extendedTone !== "old" ? root.toneColor(root.words.extendedTone) : root.dim
  }

  // The chart, at twice its strokes and cells, as the surface's look draws
  // it, still: no draw-in, ripple, or blink.
  Item {
    id: chart
    x: root.margin
    y: 314 * root.u
    width: root.width - root.margin * 2
    height: 252 * root.u

    DayChart {
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
    // A day with one print or none says so, as the popup's chart does.
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

  // The axis's two ends: the day's first and newest times, a range's dates.
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

  // When, at the foot, at the mark's size: the day's date or the range's
  // length. And Stonks' logo, the pixel bull, whatever the day's animal
  // is, and its name. The bull is in the name's ink, not the up colour: on
  // a down day a green bull would read as the day's.
  Caption {
    objectName: "shareSpan"
    x: root.margin
    y: 654 * root.u - baselineOffset
    font.pixelSize: 28 * root.u
    text: root.words ? root.words.span : ""
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
    color: root.foreground
  }
}
