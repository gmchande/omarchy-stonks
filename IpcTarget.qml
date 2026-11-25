import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import "Release.js" as Release

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
  property var updates: null

  signal refreshed()

  // An update's terminal asks this once the update moved the plugin's
  // folder (`Commands.updateAndRestart`). The shell restarts only while no
  // change is unsaved, as now, not as when the update was asked for: else
  // the footer says so, and offers the restart once the change is saved.
  function restartIfSaved() {
    if (!root.service || !root.updates) return
    var says = Release.footerNotice({ unreadable: root.service.listsUnreadable, saveFailed: root.service.saveFailed,
      editsUnsaved: root.service.editsUnsaved }, "")
    if (says.restartable) root.updates.restart()
  }

  // IpcHandler offers its every property and signal over IPC, so what it
  // is wired to lives on the item around it. Where the shell answers
  // omarchy-shell over its own socket (IpcRegistry, as ShellIpc does), it
  // reaches the handler without starting a qs ipc client; Omarchy 4.0.6
  // has no such registry.
  IpcHandler {
    id: handler
    target: root.pluginId
    enabled: root.pluginId !== ""

    Component.onCompleted: if (Commons.IpcRegistry) Commons.IpcRegistry.register(handler)
    Component.onDestruction: if (Commons.IpcRegistry) Commons.IpcRegistry.unregister(handler)

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

    function restartIfSaved(): void { root.restartIfSaved() }
  }
}
