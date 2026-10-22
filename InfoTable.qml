pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Tones.js" as Tones

// The info block's two lines as one table: each line its title, its range
// as low, a rule with the price's tick, and high, then its facts
// (`Figures.dayLine`, `Fundamentals.yearLine`). The columns are shared, so
// the two rules stand in one column. Each column is as wide as the widest
// figure its slots can hold at the listing's digits, never today's, and the
// title column as the widest of `titles`. So a refresh moves only the tick.
// The rule takes the room the columns leave, so the table spans the band's
// width at any width; a trailing column that does not fit is left out
// whole, never cut.
Item {
  id: root

  // The two lines; either may be null.
  property var lines: [null, null]
  // Every title a line can hold.
  property var titles: []
  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property string fontFamily: Style.font.family
  property int rowGap: Style.space(4)

  readonly property int gap: Style.space(14)
  readonly property int innerGap: Style.space(6)
  readonly property int minRule: Style.space(32)
  // Figures in the caption's bold; labels the same, spaced as the range
  // row's are.
  readonly property font valueFont: Qt.font({ family: fontFamily, pixelSize: Style.font.caption, bold: true })
  readonly property font labelFont: Qt.font({ family: fontFamily, pixelSize: Style.font.caption, bold: true, letterSpacing: 1 })
  // A line of text rounds its ascent and its descent up to whole pixels
  // each, and so does this.
  readonly property int lineHeight: Math.ceil(metrics.ascent) + Math.ceil(metrics.descent)

  FontMetrics { id: metrics; font: root.valueFont }

  function valueWidth(text) { return text ? Math.ceil(metrics.advanceWidth(text)) : 0 }
  function labelWidth(text) { return text ? Math.ceil(metrics.advanceWidth(text) + text.length * root.labelFont.letterSpacing) : 0 }
  function factWidth(f) {
    var value = Math.max(valueWidth(f.widest), valueWidth(f.value))
    return labelWidth(f.label) + (f.label ? innerGap : 0) + value + (f.after ? innerGap + labelWidth(f.after) : 0)
  }
  function toneColor(tone) { return tone === "up" ? upColor : tone === "down" ? downColor : foreground }

  readonly property int titleWidth: {
    var widest = 0
    for (var t = 0; t < titles.length; t++) widest = Math.max(widest, labelWidth(titles[t]))
    return widest
  }

  readonly property var layout: {
    var price = 0
    var facts = []
    var widen = function(list) {
      for (var f = 0; f < list.length; f++) facts[f] = Math.max(facts[f] || 0, factWidth(list[f]))
    }
    for (var i = 0; i < 2; i++) {
      var line = lines ? lines[i] : null
      if (!line) continue
      price = Math.max(price, valueWidth(line.range.widest), valueWidth(line.range.lowText), valueWidth(line.range.highText))
      widen(line.facts)
    }
    var fixed = function(n) {
      var t = titleWidth + gap + price * 2 + innerGap * 2
      for (var k = 0; k < n; k++) t += gap + facts[k]
      return t
    }
    var shown = facts.length
    while (shown > 0 && fixed(shown) + minRule > width) shown--
    var rule = Math.max(minRule, width - fixed(shown))
    // Whole cells on the grain, so retro's last cell ends where smooth's
    // rule does; what the grain leaves goes before the facts, which end at
    // the right edge.
    rule = Math.floor((rule + 1) / Cells.RULE_PITCH) * Cells.RULE_PITCH - 1
    var lowX = titleWidth + gap
    var ruleX = lowX + price + innerGap
    var highX = ruleX + rule + innerGap
    var factsWidth = 0
    for (var k = 0; k < shown; k++) factsWidth += gap + facts[k]
    var xs = []
    var x = Math.max(highX + price, width - factsWidth)
    for (var j = 0; j < shown; j++) {
      xs.push(x + gap)
      x += gap + facts[j]
    }
    return { price: price, rule: rule, lowX: lowX, ruleX: ruleX, highX: highX, factXs: xs }
  }

  implicitHeight: lineHeight * 2 + rowGap

  Repeater {
    model: 2

    Item {
      id: row
      required property int index
      readonly property var line: root.lines ? root.lines[index] || null : null
      objectName: index === 0 ? "dayLine" : "yearLine"
      y: index * (root.lineHeight + root.rowGap)
      width: root.width
      height: root.lineHeight

      Text {
        textFormat: Text.PlainText
        text: row.line ? row.line.title : ""
        color: root.dim
        font: root.labelFont
      }

      Text {
        x: root.layout.lowX
        width: root.layout.price
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: row.line ? row.line.range.lowText : ""
        color: root.toneColor(row.line ? row.line.range.lowTone : "")
        font: root.valueFont
      }

      InfoRule {
        objectName: row.index === 0 ? "dayRule" : "yearRule"
        visible: !!row.line
        x: root.layout.ruleX
        width: root.layout.rule
        anchors.verticalCenter: parent.verticalCenter
        low: row.line ? row.line.range.low : null
        high: row.line ? row.line.range.high : null
        price: row.line ? row.line.range.price : null
        retro: root.retro
        foreground: root.foreground
      }

      Text {
        x: root.layout.highX
        textFormat: Text.PlainText
        text: row.line ? row.line.range.highText : ""
        color: root.toneColor(row.line ? row.line.range.highTone : "")
        font: root.valueFont
      }

      // A fact's slot stays when it is not known; it draws nothing.
      Repeater {
        model: row.line ? Math.min(row.line.facts.length, root.layout.factXs.length) : 0

        Row {
          id: fact
          required property int index
          readonly property var f: row.line.facts[index]
          visible: f.value !== ""
          x: root.layout.factXs[index]
          spacing: root.innerGap

          Text {
            visible: text !== ""
            textFormat: Text.PlainText
            text: fact.f.label
            color: root.dim
            font: root.labelFont
          }
          Text {
            textFormat: Text.PlainText
            text: fact.f.value
            color: root.foreground
            font: root.valueFont
          }
          Text {
            visible: text !== ""
            textFormat: Text.PlainText
            text: fact.f.after || ""
            color: root.dim
            font: root.labelFont
          }
        }
      }
    }
  }
}
