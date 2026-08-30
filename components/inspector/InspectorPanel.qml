import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "InspectorModel.js" as InspectorModel

// Reusable shell-hosted Inspector surface. System services resolve objects and
// execute allow-listed actions; this view only normalizes state, renders it,
// and emits intent.
PanelWindow {
  id: root

  property bool opened: false
  property bool reducedMotion: false
  property var invokingScreen: null
  property point invokingPosition: Qt.point(-1, -1)
  property Item returnFocusItem: null
  property var sourceContext: ({})
  readonly property var context: InspectorModel.normalizeContext(root.sourceContext)
  property bool presented: false

  signal actionRequested(string action, var context)
  signal closed()

  function openContext(nextContext, screen, position) {
    // Set screen and anchor before mapping so the panel never flashes on the
    // previously used output during repeated multi-monitor invocation.
    root.invokingScreen = screen || null
    if (position && isFinite(Number(position.x)) && isFinite(Number(position.y)))
      root.invokingPosition = Qt.point(Number(position.x), Number(position.y))
    else
      root.invokingPosition = Qt.point(-1, -1)
    root.sourceContext = nextContext || ({ missing: true })
    root.presented = false
    root.opened = true
    Qt.callLater(function() {
      if (!root.opened) return
      root.presented = true
      inspectorView.focusInitial()
    })
  }

  function open(nextContext, screen, position) {
    root.openContext(nextContext, screen, position)
  }

  function close() {
    root.dismiss()
  }

  function dismiss() {
    if (!root.opened) return
    root.presented = false
    root.opened = false
    root.closed()
    if (root.returnFocusItem)
      Qt.callLater(function() { root.returnFocusItem.forceActiveFocus() })
  }

  function dispatch(action, normalizedContext) {
    root.actionRequested(action, normalizedContext)
  }

  visible: root.opened
  screen: root.invokingScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "regionallyfamous.one-bit-bureau.inspector"
  WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: dismissSurface }

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
    readonly property real edgeMargin: Style.space(16)
    readonly property real anchorGap: Style.space(14)
    readonly property real preferredX: {
      if (root.invokingPosition.x < 0) return root.width - width - edgeMargin
      var after = root.invokingPosition.x + anchorGap
      if (after + width <= root.width - edgeMargin) return after
      return root.invokingPosition.x - width - anchorGap
    }
    readonly property real preferredY: root.invokingPosition.y < 0
      ? edgeMargin
      : root.invokingPosition.y - Style.space(42)

    z: 2
    x: Math.max(edgeMargin, Math.min(preferredX, root.width - width - edgeMargin))
    y: Math.max(edgeMargin, Math.min(preferredY, root.height - height - edgeMargin))
    width: Math.min(Style.space(540), Math.max(Style.space(320), root.width - edgeMargin * 2))
    height: Math.min(Style.space(680), Math.max(Style.space(320), root.height - edgeMargin * 2))
    radius: 0
    color: Color.menu.background
    border.color: Color.menu.border
    border.width: 2
    opacity: root.presented ? 1 : 0
    scale: root.presented || root.reducedMotion ? 1 : 0.985

    Accessible.role: Accessible.Dialog
    Accessible.name: "Bureau Inspector"
    Accessible.description: "Inspect the selected object's identity, facts, and actions"

    Behavior on opacity {
      enabled: !root.reducedMotion
      NumberAnimation { duration: 120; easing.type: Easing.Linear }
    }

    Behavior on scale {
      enabled: !root.reducedMotion
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    // Consume clicks in unused card space so they never fall through to the
    // fullscreen dismissal surface.
    MouseArea {
      anchors.fill: parent
      z: 0
      onClicked: function(mouse) { mouse.accepted = true }
    }

    InspectorView {
      id: inspectorView
      z: 1
      anchors.fill: parent
      context: root.context
      reducedMotion: root.reducedMotion
      onCloseRequested: root.dismiss()
      onActionRequested: function(action, normalizedContext) {
        root.dispatch(action, normalizedContext)
      }
    }
  }

  Component.onDestruction: root.opened = false
}
