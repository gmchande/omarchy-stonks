import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones
// How a surface looks, for everything drawn on it: smooth or retro, its
// font, its ink on its ground, up and down for that ground, and the fainter
// inks worked out from the two.
QtObject {
  property bool retro: false
  property string fontFamily: Style.font.family
  property color foreground: Commons.Color.foreground
  property color ground: Commons.Color.background
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  readonly property color dim: Tones.dim(foreground, ground)
  readonly property color dimmer: Tones.dimmer(foreground, ground)
  readonly property color ghost: Util.alpha(foreground, 0.05)
}
