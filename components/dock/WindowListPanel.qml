import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// A textual, keyboard-first companion to hover previews. It deliberately uses
// the same already-known window records and never starts a capture pipeline.
PanelWindow {
  id: root

  property bool opened: false
  property string appId: ""
  property string appName: "Application"
  property var windowList: []
  property point requestedPosition: Qt.point(0, 0)
  property Item returnFocusItem: null
  property int currentIndex: -1
  property int currentActionIndex: 0 // 0 = Activate, 1 = Close
  readonly property int rowHeight: 58

  signal activated(var windowData)
  signal closeRequested(var windowData)

  visible: opened
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "one-bit-bureau-window-ledger"
  WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: dismissSurface }

  function dismiss() {
    root.opened = false
  }

  function selectedWindow() {
    return root.currentIndex >= 0 && root.currentIndex < root.windowList.length
      ? root.windowList[root.currentIndex]
      : null
  }

  function moveCursor(delta) {
    if (!root.windowList.length) return
    root.currentIndex = (root.currentIndex + delta + root.windowList.length) % root.windowList.length
    root.ensureCurrentVisible()
  }

  function ensureCurrentVisible() {
    if (root.currentIndex < 0) return
    var top = root.currentIndex * root.rowHeight
    var bottom = top + root.rowHeight
    if (top < listFlick.contentY) listFlick.contentY = top
    else if (bottom > listFlick.contentY + listFlick.height)
      listFlick.contentY = Math.max(0, bottom - listFlick.height)
  }

  function activateCurrent() {
    var selected = root.selectedWindow()
    if (!selected) return
    if (root.currentActionIndex === 0) {
      root.activated(selected)
      root.dismiss()
    } else {
      root.closeRequested(selected)
    }
  }

  function workspaceStatus(windowData) {
    if (!windowData) return "Unknown workspace"
    if (windowData.onCurrentWorkspace) return "Current workspace"
    return String(windowData.workspaceLabel || "Unknown workspace")
  }

  onOpenedChanged: {
    if (root.opened) {
      root.currentIndex = root.windowList.length ? 0 : -1
      root.currentActionIndex = 0
      listFlick.contentY = 0
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      root.currentIndex = -1
      root.currentActionIndex = 0
      if (root.returnFocusItem)
        Qt.callLater(function() { root.returnFocusItem.forceActiveFocus() })
    }
  }

  onWindowListChanged: {
    if (!root.windowList.length) {
      if (root.opened) root.dismiss()
      return
    }
    if (root.currentIndex < 0) root.currentIndex = 0
    else if (root.currentIndex >= root.windowList.length)
      root.currentIndex = root.windowList.length - 1
    Qt.callLater(root.ensureCurrentVisible)
  }

  Item {
    id: dismissSurface
    anchors.fill: parent

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }
  }

  Rectangle {
    id: card
    x: Math.max(12, Math.min(root.requestedPosition.x - width / 2, root.width - width - 12))
    y: Math.max(12, Math.min(root.requestedPosition.y - height - 12, root.height - height - 12))
    width: Math.min(500, root.width - 24)
    height: Math.min(root.height - 24, 58 + rows.implicitHeight)
    color: Color.menu.background
    border.color: Color.menu.border
    border.width: 2

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
    }

    Item {
      id: header
      anchors { top: parent.top; left: parent.left; right: parent.right }
      anchors.margins: 2
      height: 52

      Text {
        anchors { left: parent.left; right: closeHint.left; verticalCenter: parent.verticalCenter }
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        text: root.appName + " — Windows"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        id: closeHint
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        text: "Esc closes"
        color: Color.menu.text
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Color.menu.border
      }
    }

    Flickable {
      id: listFlick
      anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
      anchors.margins: 2
      clip: true
      contentWidth: width
      contentHeight: rows.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: rows
        width: listFlick.width

        Repeater {
          model: root.windowList

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool selected: root.currentIndex === index
            width: rows.width
            height: root.rowHeight
            color: selected ? Color.menu.selectedBackground : "transparent"

            Accessible.role: Accessible.ListItem
            Accessible.name: (modelData.title || root.appName) + ", " + root.workspaceStatus(modelData)
            Accessible.selected: row.selected

            Rectangle {
              id: stateMark
              anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
              width: 8
              height: 8
              color: modelData.active ? (row.selected ? Color.menu.selectedText : Color.menu.text) : "transparent"
              border.color: row.selected ? Color.menu.selectedText : Color.menu.text
              border.width: 1
            }

            Column {
              anchors { left: stateMark.right; leftMargin: 10; right: actions.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
              spacing: 2

              Text {
                width: parent.width
                text: modelData.title || root.appName
                color: row.selected ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.workspaceStatus(modelData)
                color: row.selected ? Color.menu.selectedText : Color.menu.text
                opacity: 0.72
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Row {
              id: actions
              anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
              spacing: 6

              Repeater {
                model: ["Activate", "Close"]

                delegate: Rectangle {
                  required property string modelData
                  required property int index
                  readonly property bool actionSelected: row.selected && root.currentActionIndex === index
                  width: modelData === "Activate" ? 72 : 52
                  height: 28
                  color: actionSelected
                    ? (row.selected ? Color.menu.selectedText : Color.menu.text)
                    : "transparent"
                  border.color: row.selected ? Color.menu.selectedText : Color.menu.text
                  border.width: 1

                  Accessible.role: Accessible.Button
                  Accessible.name: modelData + " " + (row.modelData.title || root.appName)
                  Accessible.focusable: root.opened
                  Accessible.onPressAction: {
                    root.currentIndex = row.index
                    root.currentActionIndex = index
                    root.activateCurrent()
                  }

                  Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: parent.actionSelected
                      ? (row.selected ? Color.menu.selectedBackground : Color.menu.background)
                      : (row.selected ? Color.menu.selectedText : Color.menu.text)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.currentIndex = row.index
                      root.currentActionIndex = index
                      root.activateCurrent()
                    }
                  }
                }
              }
            }

            MouseArea {
              anchors { left: parent.left; right: actions.left; top: parent.top; bottom: parent.bottom }
              hoverEnabled: true
              onEntered: root.currentIndex = row.index
              onClicked: {
                root.currentIndex = row.index
                root.currentActionIndex = 0
                root.activateCurrent()
              }
            }

            Rectangle {
              anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
              height: 1
              color: Color.menu.border
              opacity: 0.45
            }
          }
        }
      }
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
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
        root.currentIndex = 0; root.ensureCurrentVisible(); event.accepted = true; return
      }
      if (event.key === Qt.Key_End) {
        root.currentIndex = root.windowList.length - 1; root.ensureCurrentVisible(); event.accepted = true; return
      }
      if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
        root.currentActionIndex = 0; event.accepted = true; return
      }
      if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
        root.currentActionIndex = 1; event.accepted = true; return
      }
      if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
        root.currentActionIndex = 1; root.activateCurrent(); event.accepted = true; return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        root.activateCurrent(); event.accepted = true; return
      }
    }
  }
}
