pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// The manifest's service entry: the data service, the theme's up and down,
// the plugin's version watch, the sounds and the market's bell, the
// screenshot's camera, the window's host, and the IPC target, side by
// side, each on its own. The pills and the popup reach them through
// `serviceFor("grvc.stonks")`: the data as `service`, the colours as
// `trendColors`, the version watch as `updates`, the sounds as `sounds`,
// the camera as `camera`, the window as `windowHost`, and the IPC target as
// `ipc`. In a test session alone (TOPHAT_RUN set), `locator` says where a
// named control is (Locator.qml).
Item {
  id: root

  property var shell: null

  readonly property alias service: dataService
  readonly property alias updates: versionWatch
  readonly property alias trendColors: colors
  readonly property alias sounds: speaker
  readonly property alias camera: shutter
  readonly property alias windowHost: host
  readonly property alias ipc: target
  readonly property var locator: locatorLoader.item

  Service { id: dataService; screens: host }

  Updates { id: versionWatch; mainVersion: dataService.mainVersion }

  TrendColors { id: colors }

  Sounds {
    id: speaker
    turnedOn: dataService.soundsOn
    retro: dataService.retro
    files: dataService.files
  }

  Bell { service: dataService; sounds: speaker }

  Camera { id: shutter }

  WindowHost {
    id: host
    shell: root.shell
    service: dataService
    updates: versionWatch
    sounds: speaker
    camera: shutter
    trendColors: colors
  }

  IpcTarget {
    id: target
    shell: root.shell
    service: dataService
    windowHost: host
  }

  // A test session sets TOPHAT_RUN for everything it starts; a shell
  // started any other way doesn't have it.
  Loader {
    id: locatorLoader
    active: (Quickshell.env("TOPHAT_RUN") || "") !== ""
    sourceComponent: Component { Locator { windowHost: host } }
  }
}
