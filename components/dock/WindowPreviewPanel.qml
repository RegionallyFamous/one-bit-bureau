import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Overlay panel that renders the hover-to-preview popup above the dock. It is
// independent from the dock model and can appear as soon as the live window
// list is known. Cards prefer a direct compositor capture and can fall back
// to a cached thumbnail or application icon.
PanelWindow {
  id: root

  property bool previewVisible: false
  property bool reducedMotion: false
  property var windowList: []
  property real centerX: 0
  property real bottomY: 0
  property var iconSourceFor: function(item) { return "" }
  property var iconGrayscaleFor: function(item) { return false }
  property var thumbnailFor: function(item) { return "" }
  property Component cardComponent: Qt.createComponent("WindowPreview.qml")
  property var cards: []
  // `windowList` is populated before fallback captures finish. Keep the
  // layer-shell window out of those screenshots and out of the dock's
  // auto-hide state until DockPanelBase explicitly commits the preview.
  readonly property bool panelActive: root.previewVisible

  signal activated(var windowData)
  signal previewHoverEntered()
  signal previewHoverExited()

  function rebuild() {
    if (!root.windowList) return
    for (var i = 0; i < root.cards.length; i++)
      root.cards[i].destroy()
    root.cards = []

    var windows = root.windowList
    for (var j = 0; j < windows.length; j++) {
      var w = windows[j]
      var card = root.cardComponent.createObject(row, {
        windowData: w,
        iconSource: root.iconSourceFor(w),
        iconGrayscale: root.iconGrayscaleFor(w),
        thumbnail: root.thumbnailFor(w),
        active: !!w.active,
        animationEnabled: !root.reducedMotion
      })
      if (!card) {
        console.warn("one-bit-bureau preview card failed:", root.cardComponent.errorString())
        continue
      }
      card.activated.connect(function(data) { root.activated(data) })
      root.cards.push(card)
    }
  }

  onWindowListChanged: Qt.callLater(root.rebuild)
  onReducedMotionChanged: {
    for (var i = 0; i < root.cards.length; i++)
      if (root.cards[i]) root.cards[i].animationEnabled = !root.reducedMotion
  }

  visible: root.panelActive
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "one-bit-bureau-dock-preview"
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: previewRow }

  Item {
    id: previewRow
    x: Math.max(8, Math.min(root.centerX - width / 2, parent.width - width - 8))
    // DockPanel supplies the exact dock surface Y when preview state commits.
    y: Math.max(8, (root.bottomY > 0 ? root.bottomY : parent.height - 123) - height - 6)
    width: row.implicitWidth
    height: row.implicitHeight
    opacity: root.panelActive ? 1 : 0
    scale: 1

    Behavior on opacity {
      enabled: !root.reducedMotion
      NumberAnimation { duration: 80; easing.type: Easing.Linear }
    }

    Row {
      id: row
      spacing: 10
    }

    MouseArea {
      id: hoverArea
      anchors.fill: parent
      anchors.margins: -12
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      cursorShape: Qt.PointingHandCursor
      onEntered: root.previewHoverEntered()
      onExited: root.previewHoverExited()
    }
  }
}
