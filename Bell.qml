import QtQuick
import "Market.js" as Market
// The market's bell, heard: as the clock passes the regular open or the
// close of the market of the stock you last looked at
// (`Market.bellBetween`), once each a day, never late. It rings only while
// sounds are on and a screen is on; the sounds keep it quiet while
// Omarchy's Do Not Disturb is on or an app records from a microphone
// (`Sounds.ring`). The clock rings it, the one
// sound you didn't cause, so it says one true thing and cheers nothing:
// the market opened, or closed.
Item {
  id: root

  property var service: null
  property var sounds: null
  // The latest second of the clock heard: where Stonks started, then each
  // step on. A clock set back is not heard until it passes this again, so
  // no bell rings twice.
  property int heardAt: 0
  Component.onCompleted: if (service) heardAt = service.now

  Connections {
    target: root.service
    function onNowChanged() {
      var before = root.heardAt
      if (root.service.now <= before) return
      root.heardAt = root.service.now
      if (!root.sounds || !root.sounds.turnedOn || root.service.screensOff) return
      var quote = root.service.quotes[root.service.featuredSymbol]
      if (Market.bellBetween(quote, before, root.service.now, root.service.calendars) !== "") root.sounds.ring()
    }
  }
}
