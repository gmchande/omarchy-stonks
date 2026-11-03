import QtQuick
import qs.Commons as Commons
import "Cells.js" as Cells
// The retro price: every digit's slot faint and the glyph lit, as an LCD shows
// its unlit segments, each lit cell a pixel short of the next, the pixel
// chart's grain. Five rows stand on the baseline and one hangs below for the
// comma's tail, so place it by its baselineOffset, as a Text is placed.
Canvas {
  id: root

  property string text: ""
  property real cell: 8
  // A pixel of the screen it draws on, or of the picture it is grabbed into.
  property real gap: 1
  property color color: Commons.Color.foreground
  property color ghostColor: "transparent"

  readonly property var grid: Cells.blockCells(text)
  baselineOffset: 5 * cell

  width: grid.columns * cell
  height: 6 * cell

  onGridChanged: requestPaint()
  onCellChanged: requestPaint()
  onGapChanged: requestPaint()
  onColorChanged: requestPaint()
  onGhostColorChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    var cells = grid.cells
    // Unlit slots first, so a seam inside a lit cell shows the ghost, not the
    // background.
    ctx.fillStyle = ghostColor
    for (var i = 0; i < cells.length; i++) ctx.fillRect(cells[i].x * cell, cells[i].y * cell, cell, cell)
    ctx.fillStyle = color
    for (var j = 0; j < cells.length; j++) {
      if (!cells[j].lit) continue
      ctx.fillRect(cells[j].x * cell, cells[j].y * cell, Math.max(gap, cell - gap), Math.max(gap, cell - gap))
    }
  }
}
