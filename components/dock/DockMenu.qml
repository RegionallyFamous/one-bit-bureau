import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
  id: root

  property var itemData: null
  property bool opened: false
  property point requestedPosition: Qt.point(0, 0)
  property bool autoHideEnabled: true

  signal actionTriggered(string action, var itemData)

  visible: opened && itemData !== null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "paper-jam-84-dock-menu"
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: dismissSurface }

  Rectangle {
    id: menu
    x: Math.max(12, Math.min(root.requestedPosition.x, root.width - width - 12))
    y: Math.max(12, Math.min(root.requestedPosition.y, root.height - height - 12))
    width: 180
    height: menuColumn.implicitHeight + 16
    radius: 0
    color: Color.menu.background
    border.color: Color.menu.border
    border.width: 2

    Column {
      id: menuColumn
      anchors.fill: parent
      anchors.margins: 8
      spacing: 2

      Repeater {
        model: [
          { action: "setIcon", label: "Get Info", separator: false, enabled: true },
          { action: "", label: "", separator: true, enabled: false },
          { action: "togglePin", label: root.itemData && root.itemData.pinned ? "Unpin" : "Pin", separator: false, enabled: true },
          { action: "newWindow", label: "New Window", separator: false, enabled: true },
          { action: "close", label: "Close", separator: false, enabled: !!(root.itemData && root.itemData.running) },
          { action: "", label: "", separator: true, enabled: false },
          { action: "manageIcons", label: "Manage Icons", separator: false, enabled: true },
          { action: "", label: "", separator: true, enabled: false },
          { action: "toggleAutoHide", label: root.autoHideEnabled ? "Turn Hiding Off" : "Turn Hiding On", separator: false, enabled: true }
        ]
        delegate: Rectangle {
          required property var modelData
          readonly property bool rowEnabled: !modelData.separator && modelData.enabled !== false
          width: parent.width
          height: modelData.separator ? 10 : 36
          radius: 0
          color: rowEnabled && buttonMouse.containsMouse ? Color.menu.selectedBackground : "transparent"

          Text {
            visible: !modelData.separator
            anchors.fill: parent
            anchors.leftMargin: 10
            verticalAlignment: Text.AlignVCenter
            text: modelData.label
            color: parent.rowEnabled && buttonMouse.containsMouse ? Color.menu.selectedText : Color.menu.text
            opacity: parent.rowEnabled ? 1 : 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Rectangle {
            visible: modelData.separator
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Color.menu.border
          }

          MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.rowEnabled
            onClicked: {
              root.actionTriggered(modelData.action, root.itemData)
              root.opened = false
            }
          }
        }
      }
    }
  }

  Item {
    id: dismissSurface
    anchors.fill: parent
    z: -1

    MouseArea {
      anchors.fill: parent
      onClicked: root.opened = false
    }
  }

  // Keep the menu's input region limited to the card. Outside-click dismissal
  // is intentionally handled by the shell reload-safe menu state rather than
  // relying on HyprlandFocusGrab, which is not available in every plugin host.
}
