import QtQuick
import "components/dock" as OneBitBureauDock
import "components/overview" as OneBitBureauOverview

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var service: null

  readonly property bool opened: overview.opened

  function open(payloadJson) {
    overview.open(payloadJson || "{}")
  }

  function close() {
    overview.close()
  }

  OneBitBureauDock.DockPanel {
    shell: root.shell
    pluginRegistry: root.pluginRegistry
    manifest: root.manifest
    barWidgetRegistry: root.barWidgetRegistry
    service: root.service
  }

  OneBitBureauOverview.Overview {
    id: overview
    shell: root.shell
    manifest: root.manifest
  }
}
