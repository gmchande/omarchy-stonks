pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "Cells.js" as Cells
// Stonks' mark in cells (`Cells.markLevels`): each column's cap lit and its
// stem faint, down to the floor, climbing. The look icon's smooth cells,
// which step in column by column (`shown`).
Item {
  id: root
  property color color: Commons.Color.foreground
  property int pixel: 2
  property int gap: 1
  readonly property int rows: 4
  readonly property var levels: Cells.markLevels(rows)
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
        y: column.level * (root.pixel + root.gap) + root.pixel + root.gap
        width: root.pixel
        height: Math.max(0, root.height - y)
        color: root.color
        opacity: 0.35
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
