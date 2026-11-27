pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Cells.js" as Cells

// The info block's two lines as one table, so their rules share a column.
// Each column is as wide as the widest figure it can hold at the listing's
// digits on any range held, never today's; the rule takes what the columns
// leave, and a trailing column that doesn't fit is left out whole.
Item {
  id: root

  property var lines: [null, null]
  // Every title and list of facts a line can hold, on any range, and every
  // low and high on a range held.
  property var titles: []
  property var factLists: []
  property var ranges: []
  property var listInfo: ({ key: "", factLists: [], ranges: [] })
  property Look look
  property bool seen: true
  property bool still: false
  property int rowGap: Style.space(4)

  signal settled()
  function settle() { settled() }

  readonly property int gap: Style.space(14)
  readonly property int innerGap: Style.space(6)
  readonly property int minRule: Style.space(32)
  readonly property font valueFont: Qt.font({ family: look.fontFamily, pixelSize: Style.font.caption, bold: true })
  readonly property font labelFont: Qt.font({ family: look.fontFamily, pixelSize: Style.font.caption, bold: true, letterSpacing: 1 })
  // A label as the shell's panels set one: plain, in sentence case.
  readonly property font factFont: Qt.font({ family: look.fontFamily, pixelSize: Style.font.caption })
  function factLabel(text) { return text === "P/E" || text === "IPO" ? text : text.charAt(0) + text.slice(1).toLowerCase() }
  // Rounds ascent and descent up each, as a line of text does.
  readonly property int lineHeight: Math.ceil(metrics.ascent) + Math.ceil(metrics.descent)

  FontMetrics { id: metrics; font: root.valueFont }
  FontMetrics { id: factMetrics; font: root.factFont }

  // Cached per (font.family, font.pixelSize) and memoized list-wide totals by
  // `listInfo.key` so binding settles never re-measure every stock's shapes.
  // Bounded so long live sessions never retain arbitrary price strings.
  readonly property var widthCache: ({
    fontKey: "", values: Object.create(null), valueCount: 0,
    factLabels: Object.create(null), factLabelCount: 0,
    listKey: "", listGap: 0, listPrice: 0, listFacts: []
  })
  function ensureFontCache(font) {
    var key = font.family + "|" + font.pixelSize
    if (widthCache.fontKey === key) return
    widthCache.fontKey = key
    widthCache.values = Object.create(null)
    widthCache.valueCount = 0
    widthCache.factLabels = Object.create(null)
    widthCache.factLabelCount = 0
    widthCache.listKey = ""
    widthCache.listPrice = 0
    widthCache.listFacts = []
  }
  function valueWidth(text) {
    if (!text) return 0
    var v = widthCache.values[text]
    if (v !== undefined) return v
    if (widthCache.valueCount >= 512) {
      widthCache.values = Object.create(null)
      widthCache.valueCount = 0
    }
    v = Math.ceil(metrics.advanceWidth(text))
    widthCache.values[text] = v
    widthCache.valueCount++
    return v
  }
  function labelWidth(text) { return text ? valueWidth(text) + Math.ceil(text.length * root.labelFont.letterSpacing) : 0 }
  function factLabelWidth(label) {
    if (!label) return 0
    var v = widthCache.factLabels[label]
    if (v !== undefined) return v
    if (widthCache.factLabelCount >= 64) {
      widthCache.factLabels = Object.create(null)
      widthCache.factLabelCount = 0
    }
    v = Math.ceil(factMetrics.advanceWidth(factLabel(label)))
    widthCache.factLabels[label] = v
    widthCache.factLabelCount++
    return v
  }
  function factWidth(f) {
    var value = Math.max(valueWidth(f.widest), valueWidth(f.value))
    var label = factLabelWidth(f.label)
    return label + (f.label ? innerGap : 0) + value
  }
  function toneColor(tone) { return tone === "up" ? look.upColor : tone === "down" ? look.downColor : look.foreground }

  // Reading `metrics.font` measures again at a new text size.
  readonly property int titleWidth: {
    var font = metrics.font
    ensureFontCache(font)
    var widest = 0
    for (var t = 0; t < titles.length; t++) widest = Math.max(widest, labelWidth(titles[t]))
    return widest
  }

  readonly property var layout: {
    var font = metrics.font
    ensureFontCache(font)
    if (width <= 0) return { price: 0, rule: minRule, lowX: 0, ruleX: 0, highX: 0, factXs: [], factWidths: [] }
    var li = listInfo
    var lKey = li && li.key ? li.key : ""
    if (widthCache.listKey !== lKey || widthCache.listGap !== innerGap) {
      var lp = 0
      var lf = []
      var lFacts = li && li.factLists ? li.factLists : []
      for (var ll = 0; ll < lFacts.length; ll++) {
        var list = lFacts[ll]
        for (var lfIdx = 0; lfIdx < list.length; lfIdx++) lf[lfIdx] = Math.max(lf[lfIdx] || 0, factWidth(list[lfIdx]))
      }
      var lRanges = li && li.ranges ? li.ranges : []
      for (var lr = 0; lr < lRanges.length; lr++) {
        var rr = lRanges[lr]
        lp = Math.max(lp, valueWidth(rr.widest), valueWidth(rr.lowText), valueWidth(rr.highText))
      }
      widthCache.listKey = lKey
      widthCache.listGap = innerGap
      widthCache.listPrice = lp
      widthCache.listFacts = lf
    }
    var price = widthCache.listPrice
    var facts = widthCache.listFacts.slice()
    var widen = function(list) {
      for (var f = 0; f < list.length; f++) facts[f] = Math.max(facts[f] || 0, factWidth(list[f]))
    }
    var hold = function(range) {
      price = Math.max(price, valueWidth(range.widest), valueWidth(range.lowText), valueWidth(range.highText))
    }
    for (var i = 0; i < 2; i++) {
      var line = lines ? lines[i] : null
      if (!line) continue
      hold(line.range)
      widen(line.facts)
    }
    for (var l = 0; l < factLists.length; l++) widen(factLists[l])
    for (var r = 0; r < ranges.length; r++) hold(ranges[r])
    var fixed = function(n) {
      var t = titleWidth + gap + price * 2 + innerGap * 2
      for (var k = 0; k < n; k++) t += gap + facts[k]
      return t
    }
    var shown = facts.length
    while (shown > 0 && fixed(shown) + minRule > width) shown--
    var rule = Math.max(minRule, width - fixed(shown))
    // Whole retro cells, so both looks' rules end alike.
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
    return { price: price, rule: rule, lowX: lowX, ruleX: ruleX, highX: highX, factXs: xs, factWidths: facts.slice(0, shown) }
  }

  implicitHeight: lineHeight * 2 + rowGap

  Repeater {
    id: rows
    model: 2

    Item {
      id: row
      required property int index
      readonly property var line: root.lines ? root.lines[index] || null : null
      objectName: index === 0 ? "periodLine" : "yearLine"
      y: index * (root.lineHeight + root.rowGap)
      width: root.width
      height: root.lineHeight

      Text {
        textFormat: Text.PlainText
        text: row.line ? row.line.title : ""
        color: root.look.dim
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
        id: ruleItem
        objectName: row.index === 0 ? "periodRule" : "yearRule"
        visible: !!row.line
        x: root.layout.ruleX
        width: root.layout.rule
        anchors.verticalCenter: parent.verticalCenter
        low: row.line ? row.line.range.low : null
        high: row.line ? row.line.range.high : null
        price: row.line ? row.line.range.price : null
        look: root.look
        seen: root.seen
        still: root.still
        Connections {
          target: root
          function onSettled() { ruleItem.settle() }
        }
      }

      Text {
        x: root.layout.highX
        textFormat: Text.PlainText
        text: row.line ? row.line.range.highText : ""
        color: root.toneColor(row.line ? row.line.range.highTone : "")
        font: root.valueFont
      }

      Repeater {
        model: row.line ? Math.min(row.line.facts.length, root.layout.factXs.length) : 0

        Item {
          id: fact
          required property int index
          readonly property var f: row.line.facts[index]
          visible: f.value !== ""
          x: root.layout.factXs[index]
          width: root.layout.factWidths[index]
          height: row.height

          Text {
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.factLabel(fact.f.label)
            color: root.look.dim
            font: root.factFont
          }
          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: fact.f.value
            color: root.look.foreground
            font: root.valueFont
          }
        }
      }
    }
  }
}
