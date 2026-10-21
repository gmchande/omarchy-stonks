import QtQuick
import "Market.js" as Market
// The market's bell, heard: as the clock passes the regular open or the
// close of the market of the stock you last looked at
// (`Market.bellBetween`), once each a day, never late. It rings only while
// sounds are on and a screen is on; the sounds keep it quiet while an app
// records from a microphone (`Sounds.ring`). The clock rings it, the one
// sound you didn't cause, so it says one true thing and cheers nothing:
// the market opened, or closed.
Item {
  id: root

  property var service: null
  property var sounds: null
  // The clock's second last heard, 0 before the first.
  property int heardAt: 0

  Connections {
    target: root.service
    function onNowChanged() {
      var before = root.heardAt
      root.heardAt = root.service.now
      if (!before || !root.sounds || !root.sounds.turnedOn || root.service.screensOff) return
      var quote = root.service.quotes[root.service.featuredSymbol]
      if (Market.bellBetween(quote, before, root.service.now, root.service.calendars) !== "") root.sounds.ring()
    }
  }
}
