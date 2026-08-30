import QtQuick

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var service: null

  // Raster keeps the mature launch, pin, preview, and persistence behavior,
  // but presents it as a compact hard-edged launch shelf.
  DockPanelBase {
    id: dock
    shell: root.shell
    pluginRegistry: root.pluginRegistry
    manifest: root.manifest
    dockHeight: 72
    bottomMargin: 8
    iconSize: 48
    slotWidth: 56
    slotSpacing: 0
    sidePadding: 10
    separatorWidth: 8
    hideDuration: 110
    showDuration: 90
  }
}
