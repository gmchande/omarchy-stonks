pragma ComponentBehavior: Bound

import QtQuick

// The manifest's service entry: its parts side by side, each on its own,
// with the market's bell playing through the sounds. The pills and the
// popup reach them through `serviceFor("grvc.stonks")`: the data service as
// `service`, the theme's up and down as `trendColors`, the plugin's version
// watch as `updates`, the sounds as `sounds`, the screenshot's camera as
// `camera`, the window's host as `windowHost`, and the IPC target as `ipc`.
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

  // A restart loses a change the data file doesn't hold, as the footer's
  // notices say (`StonksBody.unsaved`).
  Updates {
    id: versionWatch
    mainVersion: dataService.mainVersion
    changesUnsaved: dataService.settingsUnreadable ? dataService.editsUnsaved : dataService.saveFailed
  }

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
    updates: versionWatch
  }
}
