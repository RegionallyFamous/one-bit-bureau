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
  property Item returnFocusItem: null
  property int currentIndex: -1
  readonly property var menuEntries: [
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

  signal actionTriggered(string action, var itemData)

  visible: opened && itemData !== null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "one-bit-bureau-dock-menu"
  WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: dismissSurface }

  function selectable(index) {
    var entry = root.menuEntries[index]
    return !!entry && !entry.separator && entry.enabled !== false
  }

  function firstSelectable() {
    for (var i = 0; i < root.menuEntries.length; i++)
      if (root.selectable(i)) return i
    return -1
  }

  function lastSelectable() {
    for (var i = root.menuEntries.length - 1; i >= 0; i--)
      if (root.selectable(i)) return i
    return -1
  }

  function moveCursor(direction) {
    if (!root.menuEntries.length) return
    var index = root.currentIndex
    for (var step = 0; step < root.menuEntries.length; step++) {
      index = (index + direction + root.menuEntries.length) % root.menuEntries.length
      if (root.selectable(index)) {
        root.currentIndex = index
        return
      }
    }
  }

  function activateCurrent() {
    if (!root.selectable(root.currentIndex)) return
    var entry = root.menuEntries[root.currentIndex]
    root.actionTriggered(entry.action, root.itemData)
    root.opened = false
  }

  function currentAction() {
    return root.selectable(root.currentIndex) ? String(root.menuEntries[root.currentIndex].action || "") : ""
  }

  function dismiss() {
    root.opened = false
  }

  onOpenedChanged: {
    if (root.opened) {
      root.currentIndex = root.firstSelectable()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      root.currentIndex = -1
      if (root.returnFocusItem)
        Qt.callLater(function() { root.returnFocusItem.forceActiveFocus() })
    }
  }

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
        model: root.menuEntries
        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property bool rowEnabled: !modelData.separator && modelData.enabled !== false
          readonly property bool highlighted: rowEnabled && (root.currentIndex === index || buttonMouse.containsMouse)
          width: parent.width
          height: modelData.separator ? 10 : 36
          radius: 0
          color: highlighted ? Color.menu.selectedBackground : "transparent"

          Accessible.ignored: modelData.separator
          Accessible.role: Accessible.MenuItem
          Accessible.name: modelData.label
          Accessible.selected: highlighted
          Accessible.onPressAction: {
            if (rowEnabled) {
              root.currentIndex = index
              root.activateCurrent()
            }
          }

          Text {
            visible: !modelData.separator
            anchors.fill: parent
            anchors.leftMargin: 10
            verticalAlignment: Text.AlignVCenter
            text: modelData.label
            color: parent.highlighted ? Color.menu.selectedText : Color.menu.text
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
            onEntered: root.currentIndex = index
            onClicked: {
              root.currentIndex = index
              root.activateCurrent()
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
      onClicked: root.dismiss()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      // Hyprland owns Super chords. Never turn a global desktop shortcut into
      // a menu action just because this overlay currently has keyboard focus.
      if (event.modifiers & Qt.MetaModifier) {
        event.accepted = false
        return
      }
      if (event.key === Qt.Key_Escape) {
        root.dismiss(); event.accepted = true; return
      }
      if (event.key === Qt.Key_Up) {
        root.moveCursor(-1); event.accepted = true; return
      }
      if (event.key === Qt.Key_Down) {
        root.moveCursor(1); event.accepted = true; return
      }
      if (event.key === Qt.Key_Home) {
        root.currentIndex = root.firstSelectable(); event.accepted = true; return
      }
      if (event.key === Qt.Key_End) {
        root.currentIndex = root.lastSelectable(); event.accepted = true; return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        root.activateCurrent(); event.accepted = true; return
      }
    }
  }

  // Keep the menu's input region limited to the card. Outside-click dismissal
  // is intentionally handled by the shell reload-safe menu state rather than
  // relying on HyprlandFocusGrab, which is not available in every plugin host.
}
