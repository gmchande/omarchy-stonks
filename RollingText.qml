pragma ComponentBehavior: Bound

import QtQuick
import "Format.js" as Format

// A figure that rolls the characters a tick changed, as an odometer does: the
// new ones come up from below on a rise (`up`) and down from above on a fall,
// each in its own place, while the rest hold still. At rest, and whenever its
// text changes without a roll (`roll` stays 1), it is one plain Text.
Item {
  id: root

  property string text: ""
  property font font
  property color color
  // The roll, 0 to 1, which the surface starts as the figure ticks.
  property real roll: 1
  property bool up: true

  // The text before the last change, which a roll starts from.
  property string before: ""
  property string latest: ""
  onTextChanged: {
    before = latest
    latest = text
  }
  Component.onCompleted: latest = text

  readonly property bool rolling: roll < 1 && before !== "" && before !== text
  readonly property var glyphs: rolling ? Format.rolledGlyphs(before, text) : ({ arriving: [], leaving: [] })

  implicitWidth: label.implicitWidth
  implicitHeight: label.implicitHeight
  baselineOffset: label.baselineOffset

  FontMetrics { id: metrics; font: root.font }
  // Where the character at `at` of `text` starts, as the whole line sets it:
  // the advance counts the letter spacing.
  function place(text, at) {
    return metrics.advanceWidth(text.slice(0, at))
  }
  // A glyph rolls within the figures' own ink, from a digit's top to the
  // foot of a comma's tail, so nothing it passes shows a stray digit.
  TextMetrics { id: ink; font: root.font; text: "0123456789,.%+-" }
  readonly property real inkTop: Math.floor(label.baselineOffset + ink.tightBoundingRect.y) - 1
  readonly property real inkHeight: Math.ceil(label.baselineOffset + ink.tightBoundingRect.y + ink.tightBoundingRect.height) + 1 - inkTop

  Text {
    id: label
    visible: !root.rolling
    textFormat: Text.PlainText
    text: root.text
    color: root.color
    font: root.font
  }

  component Glyph: Item {
    id: cell
    property string glyph: ""
    property string from: ""
    property int at: 0
    // How far the glyph sits from its place, in its own heights: 0 at rest.
    property real offset: 0
    x: root.place(from, at)
    y: root.inkTop
    width: root.place(from, at + 1) - x
    height: root.inkHeight
    clip: cell.offset !== 0
    Text {
      y: cell.offset * cell.height - root.inkTop
      textFormat: Text.PlainText
      text: cell.glyph
      color: root.color
      font: root.font
    }
  }

  Repeater {
    model: root.glyphs.arriving
    Glyph {
      required property var modelData
      glyph: modelData.glyph
      from: root.text
      at: modelData.at
      offset: modelData.rolls ? (root.up ? 1 : -1) * (1 - root.roll) : 0
    }
  }

  Repeater {
    model: root.glyphs.leaving
    Glyph {
      required property var modelData
      glyph: modelData.glyph
      from: root.before
      at: modelData.at
      offset: (root.up ? -1 : 1) * root.roll
    }
  }
}
