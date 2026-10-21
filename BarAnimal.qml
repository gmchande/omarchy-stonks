pragma ComponentBehavior: Bound

import QtQuick
import "Cells.js" as Cells
// The pill's icon form: the day's bull or bear in the header's cells
// (`Cells.spriteFor`), the bull in up's colour and the bear in down's.
// A day that turns (`turnTo`) steps it to the other animal left to right in
// 200 ms, each column taking the new animal's cells and colour as it turns;
// a turn reversed mid-step turns back from where it is. At rest, and after
// `settle`, it is simply `kind`, and nothing at all for "".
Item {
  id: root
  property string kind: ""
  property color upColor
  property color downColor
  property int cell: 1
  readonly property int columns: Cells.BULL_SPRITE[0].length
  readonly property int rows: Cells.BULL_SPRITE.length

  // While a turn steps: the columns left of `turnedColumns` show
  // `turnKind`, the rest `fromKind`.
  property real turn: 1
  readonly property bool turning: step.running
  readonly property int turnedColumns: turning ? Math.round(turn * columns) : columns
  property string turnKind: ""
  property string fromKind: ""

  NumberAnimation { id: step; target: root; property: "turn"; duration: 200; easing.type: Easing.OutCubic }

  // The day now reads `now`, after `was`. Only the bull and the bear turn
  // into each other: to or from no animal, or out of sight, it changes at
  // once. Mid-step, the turn heads for the new animal: back toward where it
  // came from, or on, never queued.
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

  // At once to `kind`: another symbol, or the animal hidden.
  function settle() {
    step.stop()
    turn = 1
  }
  onVisibleChanged: if (!visible) settle()

  function inkOf(k) { return k === "bull" ? upColor : downColor }

  implicitWidth: columns * cell
  implicitHeight: rows * cell

  // The animal at rest, or the columns a turn has reached.
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

  // The columns a turn has yet to reach.
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
