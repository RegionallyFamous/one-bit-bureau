import QtQuick

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var service: null
  readonly property var windowLedger: dock.windowLedger
  readonly property var lastActionStatus: dock.lastActionStatus

  // Shared Inspector bridge. Experience owns the Inspector surface; the dock
  // owns app/window truth and action re-resolution.
  signal inspectorRequested(var context, var invokingScreen, point invokingPosition)
  signal actionStatusReported(var status)

  function inspectorContextForApp(appId) {
    return dock.inspectorContextForApp(appId)
  }

  function performInspectorAction(actionId, context) {
    return dock.performInspectorAction(actionId, context)
  }

  // Raster keeps the mature launch, pin, preview, and persistence behavior,
  // but presents it as a compact hard-edged launch shelf.
  DockPanelBase {
    id: dock
    shell: root.shell
    pluginRegistry: root.pluginRegistry
    manifest: root.manifest
    service: root.service
    dockHeight: 72
    bottomMargin: 8
    iconSize: 48
    slotWidth: 56
    slotSpacing: 0
    sidePadding: 10
    separatorWidth: 8
    hideDuration: 110
    showDuration: 90
    onInspectorRequested: function(context, invokingScreen, invokingPosition) {
      root.inspectorRequested(context, invokingScreen, invokingPosition)
    }
    onActionStatusReported: function(status) { root.actionStatusReported(status) }
  }
}
