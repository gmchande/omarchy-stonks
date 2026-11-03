pragma ComponentBehavior: Bound

import QtQuick
import "Cells.js" as Cells
// The pill's icon form: the day's bull or bear in the header's cells, in the up
// or the down colour. A day that turns (`turnTo`) steps it to the other animal
// left to right in 200 ms, column by column.
Item {
  id: root
  property string kind: ""
  property color upColor
  property color downColor
  property int cell: 1
  readonly property int columns: Cells.BULL_SPRITE[0].length
  readonly property int rows: Cells.BULL_SPRITE.length

  // Mid-turn, the columns left of `turnedColumns` show `turnKind`, the rest
  // `fromKind`.
  property real turn: 1
  readonly property bool turning: step.running
  readonly property int turnedColumns: turning ? Math.round(turn * columns) : columns
  property string turnKind: ""
  property string fromKind: ""

  NumberAnimation { id: step; target: root; property: "turn"; duration: 200; easing.type: Easing.OutCubic }

  // Only the bull and the bear turn into each other: to or from no animal, or
  // out of sight, it changes at once. A turn reversed mid-step heads back from
  // where it is, never queued.
  function turnTo(now, was) {
    var to
    if (now === "" || !visible) return settle()
    if (!step.running) {
      if (was === "" || now === was) return
      fromKind = was
      turnKind = now
      turn = 0
      to = 1
    } else if (now === fromKind) to = 0
    else {
      turnKind = now
      to = 1
    }
    if (step.running && step.to === to) return
    step.stop()
    step.to = to
    step.start()
  }

  function settle() {
    step.stop()
    turn = 1
  }
  onVisibleChanged: if (!visible) settle()

  function inkOf(k) { return k === "bull" ? upColor : downColor }

  implicitWidth: columns * cell
  implicitHeight: rows * cell

  Item {
    readonly property string shows: root.turning ? root.turnKind : root.kind
    visible: shows !== ""
    width: root.turnedColumns * root.cell
    height: root.height
    clip: root.turning

    PixelSprite {
      objectName: "animalCells"
      width: root.width
      height: root.height
      columns: root.columns
      rows: root.rows
      pixels: Cells.spriteFor(parent.shows === "bull", 0)
      color: root.inkOf(parent.shows)
    }
  }

  Item {
    visible: root.turning
    x: root.turnedColumns * root.cell
    width: root.width - x
    height: root.height
    clip: true

    PixelSprite {
      objectName: "animalCells"
      x: -parent.x
      width: root.width
      height: root.height
      columns: root.columns
      rows: root.rows
      pixels: Cells.spriteFor(root.fromKind === "bull", 0)
      color: root.inkOf(root.fromKind)
    }
  }
}
