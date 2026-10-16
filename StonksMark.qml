pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Cells.js" as Cells
// Stonks' mark in cells (`Cells.markLevels`): each column's cap lit and its
// stem faint, down to the floor. It climbs, or falls on a down day, so the
// shape says the direction without its colour. The pill's icon form, and the
// look icon's retro cells, which step in column by column (`shown`). At icon
// size (`solid`) each column is one bar at full ink, cap and stem joined, so
// it still reads as a chart where faint cells would scatter into dots.
Item {
  id: root
  property bool falling: false
  property bool solid: false
  property color color: Color.foreground
  property int pixel: 2
  property int gap: 1
  readonly property int rows: 4
  readonly property var levels: Cells.markLevels(rows, falling)
  property int shown: levels.length

  implicitWidth: levels.length * (pixel + gap) - gap
  implicitHeight: rows * (pixel + gap) - gap

  Repeater {
    model: root.levels.length

    Item {
      id: column
      required property int index
      readonly property int level: root.levels[index]
      visible: index < root.shown
      x: index * (root.pixel + root.gap)
      width: root.pixel
      height: root.height

      Rectangle {
        y: column.level * (root.pixel + root.gap) + root.pixel + (root.solid ? 0 : root.gap)
        width: root.pixel
        height: Math.max(0, root.height - y)
        color: root.color
        opacity: root.solid ? 1 : 0.35
      }
      Rectangle {
        objectName: "markCell"
        y: column.level * (root.pixel + root.gap)
        width: root.pixel
        height: root.pixel
        color: root.color
      }
    }
  }
}
