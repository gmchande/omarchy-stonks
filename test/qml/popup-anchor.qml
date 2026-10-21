import QtQuick
import QtTest
import Quickshell
import qs.Ui
import "plugin" as Stonks

// Run on Wayland with every window unmapped. Keep the real Panel,
// HeldAnchor and installed KeyboardPanel placement. An unmapped Wayland
// window has no attached QsWindow, so supply that platform boundary here;
// render.qml checks the default window lookup on its real offscreen pill.
// The renderer consumes these origins, never a copied placement formula.
ShellRoot {
  id: harness
  property int failures: 0
  function check(label, ok) {
    console.log((ok ? "PASS " : "FAIL ") + label)
    if (!ok) failures++
  }
  QtObject { id: shellApi; function serviceFor() { return null } }
  PluginBarApi { id: api; pluginId: "grvc.stonks"; moduleName: "grvc.stonks"; shell: shellApi }
  FloatingWindow {
    id: barWindow
    visible: false
    implicitWidth: 1000
    implicitHeight: 32
    Item { id: pill; x: 16; width: 150; height: 32 }
  }
  Stonks.Panel { id: panel; bar: api; anchorItem: pill }
  HarnessExit { id: done }
  TestCase {
    name: "PopupAnchor"
    when: true
    function test_origins() {
      var card = panel.testCard
      var held = panel.testHeldAnchor
      held.barWindow = barWindow
      card.anchorWindow = barWindow
      var poses = {}
      ;["left", "center", "right"].forEach(function(section) {
        pill.width = 150
        pill.x = section === "left" ? 16 : section === "center" ? 425 : 834
        panel.open()
        wait(20)
        harness.check("the card uses HeldAnchor on the bar's content", held.parent === barWindow.contentItem && card.anchorItem === held)
        var original = held.x + "+" + held.width
        var first = card.cardOrigin.x
        ;["open", "held", "next"].forEach(function(moment) {
          if (moment === "held") {
            pill.width = 220
            if (section === "right") pill.x = 1000 - pill.width - 16
          }
          if (moment === "next") { panel.close(); panel.open() }
          wait(20)
          var at = card.cardOrigin
          poses[section + "-" + moment] = {x: at.x, y: at.y, pillX: pill.x, pillWidth: pill.width}
          var middle = held.x + held.width / 2
          harness.check("card contains its held pill's centre: " + section + " " + moment, at.x <= middle && middle <= at.x + card.contentWidth)
          harness.check("card is whole under the bar", at.x >= 0 && at.x + card.contentWidth <= 1000 && at.y > 32)
          if (moment === "held") {
            harness.check("widening leaves the held anchor alone", held.x + "+" + held.width === original)
            harness.check("the open card stays where it opened", at.x === first)
          }
          if (moment === "next") harness.check("next open takes the new width", held.width === 220)
        })
        panel.close()
      })
      console.log("ANCHOR POSES " + JSON.stringify(poses))
      console.log("ANCHOR DONE")
      done.exitCode = harness.failures ? 1 : 0
      done.start()
    }
  }
}
