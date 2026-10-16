import QtQuick
import qs.Commons

// A pixel sprite (named to dodge QtQuick.Sprite) drawn from Cells.spritePixels: [{x, y}, ...] on a grid.
Canvas {
  id: root

  property var pixels: []
  property int columns: 20
  property int rows: 14
  property color color: Color.foreground

  implicitWidth: width
  implicitHeight: height

  onPixelsChanged: requestPaint()
  onColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    var size = Math.floor(Math.min(width / columns, height / rows))
    if (size < 1) return
    var ox = Math.floor((width - size * columns) / 2)
    var oy = Math.floor((height - size * rows) / 2)
    ctx.fillStyle = color
    for (var i = 0; i < pixels.length; i++) {
      ctx.fillRect(ox + pixels[i].x * size, oy + pixels[i].y * size, size, size)
    }
  }
}
