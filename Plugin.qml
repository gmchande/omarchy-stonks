pragma ComponentBehavior: Bound

import QtQuick

// The manifest's service entry. The pills and the panel reach its parts
// through `serviceFor("grvc.stonks")`.
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
}
