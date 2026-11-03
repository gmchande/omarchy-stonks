import QtQuick
import Quickshell.Io

// `omarchy-shell ID <function>`, ID being the plugin's id, with or without
// a pill on the bar. The panel's verbs go through the shell, which opens the
// panel on the focused screen's pill.
Item {
  id: root

  property var shell: null
  // The plugin's id, the manifest's (`Plugin`); no target until it's known.
  property string pluginId: ""
  property var service: null
  property var windowHost: null

  signal refreshed()

  // IpcHandler offers its every property and signal over IPC, so what it
  // is wired to lives on the item around it.
  IpcHandler {
    id: handler
    target: root.pluginId
    enabled: root.pluginId !== ""

    function refresh(): void {
      if (root.service) root.service.refresh()
      root.refreshed()
    }
    function next(): void { if (root.service) root.service.featureStep(1) }
    function prev(): void { if (root.service) root.service.featureStep(-1) }

    function open(): void { if (root.shell) root.shell.summon(root.pluginId, "{}") }
    function close(): void { if (root.shell) root.shell.hide(root.pluginId) }
    function show(): void { handler.open() }
    function hide(): void { handler.close() }
    function toggle(): void { if (root.shell) root.shell.toggle(root.pluginId, "{}") }

    function toggleWindow(): void { if (root.windowHost) root.windowHost.toggle() }
    function openWindow(payloadJson: string): void { if (root.windowHost) root.windowHost.open(payloadJson) }
  }
}
