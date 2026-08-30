import QtQuick
import Quickshell
import "components/dock" as OneBitBureauDock
import "components/inspector" as OneBitBureauInspector
import "components/overview" as OneBitBureauOverview

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var service: null

  readonly property bool opened: overview.opened || inspector.opened

  function screenForName(screenName) {
    var requested = String(screenName || "")
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name || "") === requested)
        return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  function openInspector(payload, screenOrName, position) {
    var invokingScreen = screenOrName && typeof screenOrName === "object"
      ? screenOrName
      : root.screenForName(screenOrName)
    inspector.openContext(payload, invokingScreen, position || Qt.point(-1, -1))
  }

  function performInspectorAction(actionId, context) {
    var kind = String((context && context.kind) || "")
    if (kind === "desktop" && root.service
        && typeof root.service.performInspectorAction === "function")
      return root.service.performInspectorAction(actionId, context)
    if (kind === "app")
      return dock.performInspectorAction(actionId, context)
    if (kind === "window")
      return overview.performInspectorAction(actionId, context)
    return false
  }

  function open(payloadJson) {
    overview.open(payloadJson || "{}")
  }

  function close() {
    inspector.close()
    overview.close()
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true

    function onInspectRequested(payload, screenName) {
      root.openInspector(payload, screenName, Qt.point(-1, -1))
    }

    function onInspectorCloseRequested() {
      inspector.close()
    }
  }

  OneBitBureauDock.DockPanel {
    id: dock
    shell: root.shell
    pluginRegistry: root.pluginRegistry
    manifest: root.manifest
    barWidgetRegistry: root.barWidgetRegistry
    service: root.service
    onInspectorRequested: function(context, invokingScreen, invokingPosition) {
      root.openInspector(context, invokingScreen, invokingPosition)
    }
  }

  OneBitBureauOverview.Overview {
    id: overview
    shell: root.shell
    manifest: root.manifest
    service: root.service
    onInspectRequested: function(payload, screenName) {
      root.openInspector(payload, screenName, Qt.point(-1, -1))
    }
  }

  OneBitBureauInspector.InspectorPanel {
    id: inspector
    reducedMotion: root.service && root.service.reducedMotion === true

    onActionRequested: function(actionId, context) {
      if (root.performInspectorAction(actionId, context))
        inspector.close()
    }

    onClosed: {
      if (root.service && root.service.inspectorOpen
          && typeof root.service.closeInspector === "function")
        root.service.closeInspector()
    }
  }
}
