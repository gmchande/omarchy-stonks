import QtQuick
import qs.Commons as Commons

// A pixel sprite (named to dodge QtQuick.Sprite) drawn from Cells.spritePixels: [{x, y}, ...] on a grid.
Canvas {
  id: root

  property var pixels: []
  property int columns: 20
  property int rows: 14
  property color color: Commons.Color.foreground
  // Pixels to a window unit that the cells snap to: 1 on the surfaces, the
  // screen's ratio in the screenshot, whose units are fractions of its
  // pixels (`ShareCard`).
  property real pixelRatio: 1

  implicitWidth: width
  implicitHeight: height

  onPixelsChanged: requestPaint()
  onColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    // A hair over, so 8 pixels reached through thirds stay 8, not 7.
    var size = Math.floor(Math.min(width / columns, height / rows) * pixelRatio + 1e-6) / pixelRatio
    if (size * pixelRatio < 1) return
    var ox = Math.floor((width - size * columns) / 2 * pixelRatio + 1e-6) / pixelRatio
    var oy = Math.floor((height - size * rows) / 2 * pixelRatio + 1e-6) / pixelRatio
    ctx.fillStyle = color
    for (var i = 0; i < pixels.length; i++) {
      ctx.fillRect(ox + pixels[i].x * size, oy + pixels[i].y * size, size, size)
    }
  }
}
