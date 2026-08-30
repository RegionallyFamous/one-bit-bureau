import QtQuick
import Quickshell
import qs.Commons
import "IconResolver.js" as IconResolver

Item {
  id: root

  required property var itemData
  property int iconSize: 52
  // Targets driven by the panel's layout engine. Every change is animated so
  // nothing ever teleports.
  property real targetScale: 1
  property real targetLift: 0
  property real targetOpacity: 1
  property bool animationEnabled: true
  property bool isDragging: false
  property bool leftPressed: false
  property bool tooltipVisible: false
  property string iconSourceOverride: ""
  property point pressPosition: Qt.point(0, 0)
  readonly property bool iconReady: icon.status === Image.Ready
  readonly property bool packNormalized: icon.packCrop !== null
  readonly property real iconCenterOffset: (icon.y + icon.height / 2) - (root.height / 2)
  readonly property string accessibleState: root.itemData.running
    ? (root.itemData.pinned ? "Pinned application, running" : "Application, running")
    : (root.itemData.pinned ? "Pinned application" : "Application")

  signal dragMoved(var itemData, point position)
  signal dragFinished(var itemData, point position)
  signal itemLeftClicked(var itemData)
  signal itemRightClicked(var itemData, point position)
  signal tooltipRequested(var itemData, bool visible, real centerX)
  signal hoverPointerChanged(var itemData, bool inside, real pointerX)
  signal keyboardFocusChanged(var itemData, bool focused)

  width: iconSize + 8
  height: iconSize + 18
  activeFocusOnTab: true

  Accessible.role: Accessible.Button
  Accessible.name: root.itemData.name || root.itemData.id
  Accessible.description: root.accessibleState
  Accessible.focusable: true
  Accessible.selected: !!root.itemData.running
  Accessible.onPressAction: root.itemLeftClicked(root.itemData)

  onActiveFocusChanged: root.keyboardFocusChanged(root.itemData, root.activeFocus)

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.modifiers & Qt.MetaModifier) {
      event.accepted = false
      return
    }
    if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
      root.itemRightClicked(root.itemData, root.mapToItem(null, root.width / 2, 0))
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.itemLeftClicked(root.itemData)
      event.accepted = true
    }
  }

  function iconSource() {
    if (root.iconSourceOverride) return root.iconSourceOverride
    var name = IconResolver.resolveIcon(itemData)
    if (String(name).indexOf("/") === 0) return Util.fileUrl(name)
    if (String(name).indexOf("file:") === 0 || String(name).indexOf("image:") === 0) return name
    return Quickshell.iconPath(name, true)
  }

  Behavior on scale {
    enabled: root.animationEnabled
    NumberAnimation { duration: 70; easing.type: Easing.Linear }
  }
  scale: root.targetScale

  Behavior on y {
    enabled: root.animationEnabled
    NumberAnimation { duration: 70; easing.type: Easing.Linear }
  }
  y: -root.targetLift

  Behavior on opacity {
    enabled: root.animationEnabled
    NumberAnimation { duration: 60; easing.type: Easing.Linear }
  }
  opacity: root.targetOpacity

  Rectangle {
    anchors.fill: parent
    anchors.margins: 2
    color: "transparent"
    border.color: Color.foreground
    border.width: mouse.containsMouse || root.activeFocus ? 2 : 0
  }

  PackAwareImage {
    id: icon
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: root.iconSize
    height: root.iconSize
    source: root.iconSource()
    sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
    fillMode: Image.PreserveAspectFit
    cache: true

    Text {
      anchors.centerIn: parent
      visible: parent.status !== Image.Ready
      text: "◆"
      color: Color.foreground
      font.pixelSize: root.iconSize * 0.42
    }
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: icon.bottom
    anchors.topMargin: 2
    width: 16
    height: 2
    radius: 0
    color: Color.foreground
    visible: !!root.itemData.running
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      root.tooltipVisible = true
      root.tooltipRequested(root.itemData, true, root.mapToItem(null, root.width / 2, 0).x)
      root.hoverPointerChanged(root.itemData, true, root.mapToItem(null, mouseX, mouseY).x)
    }
    onExited: {
      root.tooltipVisible = false
      root.tooltipRequested(root.itemData, false, root.mapToItem(null, root.width / 2, 0).x)
      root.hoverPointerChanged(root.itemData, false, root.mapToItem(null, mouseX, mouseY).x)
    }
    onPressed: function(mouse) {
      root.forceActiveFocus()
      root.leftPressed = mouse.button === Qt.LeftButton
      root.pressPosition = Qt.point(mouseX, mouseY)
    }
    onPositionChanged: {
      if (!pressed) {
        root.hoverPointerChanged(root.itemData, true, root.mapToItem(null, mouseX, mouseY).x)
        return
      }
      if (root.leftPressed && !root.isDragging && Math.hypot(mouseX - root.pressPosition.x, mouseY - root.pressPosition.y) >= 6)
        root.isDragging = true
      if (root.leftPressed && root.isDragging)
        root.dragMoved(root.itemData, Qt.point(mouseX, mouseY))
    }
    onReleased: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.itemRightClicked(root.itemData, root.mapToItem(null, mouseX, mouseY))
      } else if (!root.isDragging) {
        root.itemLeftClicked(root.itemData)
      } else {
        root.dragFinished(root.itemData, Qt.point(mouseX, mouseY))
      }
      root.isDragging = false
      root.leftPressed = false
    }
  }
}
