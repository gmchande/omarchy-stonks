import QtQuick
import qs.Commons
import "Cells.js" as Cells
// The retro price: Cells.blockCells drawn as square cells, every digit's slot
// faintly and the glyph lit, the way an LCD shows its unlit segments. Each
// lit cell stops a pixel short of the next, so the price carries the same
// grain as the pixel chart under it. The hero sizes the cell so the digits
// stand as tall as the smooth ones. Five rows stand on the baseline and one
// hangs below it for the comma's tail, so place it by its baselineOffset,
// the way a Text is placed.
Canvas {
  id: root

  property string text: ""
  property int cell: 8
  property color color: Color.foreground
  property color ghostColor: "transparent"

  readonly property var grid: Cells.blockCells(text)
  baselineOffset: 5 * cell

  width: grid.columns * cell
  height: 6 * cell

  onGridChanged: requestPaint()
  onCellChanged: requestPaint()
  onColorChanged: requestPaint()
  onGhostColorChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    var cells = grid.cells
    // Every cell's unlit slot first, so a seam inside a lit cell shows the
    // same ghost the dark segments are drawn in, not the background.
    ctx.fillStyle = ghostColor
    for (var i = 0; i < cells.length; i++) ctx.fillRect(cells[i].x * cell, cells[i].y * cell, cell, cell)
    ctx.fillStyle = color
    for (var j = 0; j < cells.length; j++) {
      if (!cells[j].lit) continue
      ctx.fillRect(cells[j].x * cell, cells[j].y * cell, Math.max(1, cell - 1), Math.max(1, cell - 1))
    }
  }
}
