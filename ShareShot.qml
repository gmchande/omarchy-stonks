import QtQuick
import "Share.js" as Share

// A screenshot of the stock on show: the share card built off screen, two
// frames for its canvases to paint, then the camera's shot. Clipped to
// nothing, not hidden: a hidden item's parts read themselves hidden, and
// the retro chart's lit cap falls to its top row.
Item {
  id: root
  width: 0
  height: 0
  clip: true

  property var camera: null
  // A shot is out, here or from the other surface.
  readonly property bool busy: !camera || camera.busy || String(loader.source) !== ""

  // As the picture is taken; `told` says after how the save went, `saved`
  // whether the picture was kept.
  signal shutter()
  signal told(string words, bool saved)

  // `card`: `ShareCard`'s properties.
  function take(card) {
    loader.setSource("ShareCard.qml", card)
  }

  // The other surface may take the camera while this card waits: then this
  // card goes.
  function shoot(card) {
    var shown = Share.subject(card.symbol, card.range, card.words ? card.words.said : "")
    var taken = camera.shoot(card, Share.fileSymbol(card.symbol), function() {
      loader.source = ""
      root.shutter()
    }, function(code) {
      loader.source = ""
      if (code === 1) root.told("Screenshot not saved · the screenshots folder can't be written", false)
      else root.told(code === 0 ? "Copied a screenshot of " + shown : "Saved a screenshot of " + shown + " · copying it failed", true)
    })
    if (!taken) loader.source = ""
  }

  Loader {
    id: loader
    objectName: "shareLoader"
  }

  FrameAnimation {
    property int frames: 0
    running: loader.status === Loader.Ready
    onRunningChanged: frames = 0
    onTriggered: if (++frames === 2) root.shoot(loader.item)
  }
}
