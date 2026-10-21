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
    Item {
      id: sectionRow
      width: parent.width
      height: 32
      Stonks.BarWidget {
        id: pill
        x: 16
        width: 150
        height: 32
        bar: api
        settings: ({id: "grvc.stonks", barStyle: "text"})
      }
    }
  }
  HarnessExit { id: done }
  TestCase {
    name: "PopupAnchor"
    when: !!pill.panel
    function test_origins() {
      var panel = pill.panel
      wait(20)
      var card = panel.testCard
      var held = panel.testHeldAnchor
      held.barWindow = barWindow
      card.anchorWindow = barWindow
      var poses = {}
      ;["left", "center", "right"].forEach(function(section) {
        sectionRow.x = 0
        pill.width = 150
        pill.x = section === "left" ? 16 : section === "center" ? 425 : 834
        var openedMiddle = pill.x + pill.width / 2
        pill.open()
        wait(20)
        var first = card.cardOrigin.x
        ;["open", "held", "next"].forEach(function(moment) {
          if (moment === "held") {
            pill.width = 220
            // A bar section can move when one of its pills widens. The
            // held card must survive that movement until its next open.
            sectionRow.x = section === "center" ? -20 : section === "right" ? -70 : 0
          }
          if (moment === "next") { pill.close(); pill.open() }
          wait(20)
          var at = card.cardOrigin
          poses[section + "-" + moment] = {x: at.x, y: at.y, pillX: sectionRow.x + pill.x, pillWidth: pill.width}
          var middle = moment === "next" ? sectionRow.x + pill.x + pill.width / 2 : openedMiddle
          harness.check("card contains the pill centre it opened from: " + section + " " + moment, at.x <= middle && middle <= at.x + card.contentWidth)
          if (section === "center") harness.check("the card centres under the pill it opened from: " + moment,
            Math.abs(at.x + card.contentWidth / 2 - middle) < 0.5)
          harness.check("card is whole under the bar", at.x >= 0 && at.x + card.contentWidth <= 1000 && at.y > 32)
          if (moment === "held") {
            harness.check("the open card stays where it opened", at.x === first)
          }
        })
        pill.close()
      })
      console.log("ANCHOR POSES " + JSON.stringify(poses))
      console.log("ANCHOR DONE")
      done.exitCode = harness.failures ? 1 : 0
      done.start()
    }
  }
}
