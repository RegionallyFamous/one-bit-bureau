import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Wayland
import "WindowModel.js" as WindowModel
import qs.Commons

Rectangle {
    id: card

    required property var modelData
    required property var controller
    required property var screenToplevels
    required property bool acceptsKeyboard
    required property var windowLayout
    required property real layoutAreaWidth
    required property real layoutAreaHeight
    // Position in the filtered list; -1 hides the card.
    readonly property int slot: card.screenToplevels.indexOf(modelData)
    readonly property bool inLayout: slot >= 0
    property bool hovered: false
    readonly property bool selected: card.acceptsKeyboard && inLayout && slot === card.controller.selectedIndex
    readonly property bool focusedWindow: modelData === Hyprland.activeToplevel
    readonly property bool previewed: card.acceptsKeyboard && inLayout && slot === card.controller.previewIndex
    readonly property bool exitingPreview: card.acceptsKeyboard && inLayout && slot === card.controller.previewExitIndex
    readonly property bool floatingFooter: card.controller.windowFooterStyle === "floating"
    readonly property bool integratedFooter: card.controller.windowFooterStyle === "integrated"
    readonly property bool overlayFooter: card.controller.windowFooterStyle === "overlay"
    readonly property bool centeredFooter: card.controller.windowFooterStyle === "centered"
    readonly property string windowTitle: String(modelData.title || WindowModel.appIdFor(modelData) || "Untitled window")
    readonly property string applicationName: WindowModel.appIdFor(modelData) || "Application"
    readonly property string workspaceName: card.controller.workspaceName(modelData)
    readonly property string iconSource: card.controller.iconFor(modelData)
    readonly property color outlineColor: Color.menu.border
    readonly property color contentTextColor: selected ? Color.menu.selectedText : Color.menu.text
    readonly property real outlineWidth: 2
    // An excluded card keeps its last rectangle, so it neither
    // animates toward the origin nor flies back in from it.
    readonly property var packedRectSource: inLayout ? card.windowLayout[slot] : null
    property var packedRect: Qt.rect(0, 0, 1, 1)
    readonly property var previewRect: card.controller.previewRectFor(modelData, packedRect, card.layoutAreaWidth, card.layoutAreaHeight, Style.spacing.sm, card.controller.windowFooterHeight)
    readonly property var layoutRect: previewed ? previewRect : packedRect

    onPackedRectSourceChanged: {
        if (packedRectSource)
            packedRect = packedRectSource;

    }
    Component.onCompleted: {
        if (packedRectSource)
            packedRect = packedRectSource;

    }
    visible: inLayout
    x: layoutRect.x
    y: layoutRect.y
    width: layoutRect.width
    height: layoutRect.height
    z: previewed ? 11 : (exitingPreview ? 10 : 0)
    radius: 0
    color: Color.menu.background
    border.color: outlineColor
    border.width: outlineWidth
    opacity: card.controller.previewIndex < 0 || previewed ? 1 : 0.6
    Accessible.role: Accessible.Button
    Accessible.name: card.applicationName + ": " + card.windowTitle
    Accessible.description: "Workspace " + card.workspaceName
    Accessible.focusable: card.acceptsKeyboard
    Accessible.focused: card.selected
    Accessible.selectable: true
    Accessible.selected: card.selected
    Accessible.onPressAction: card.controller.activate(card.modelData)

    MouseArea {
        anchors.fill: parent
        enabled: !card.controller.settingsOpen && (card.controller.previewIndex < 0 || card.previewed)
        hoverEnabled: true
        onEnabledChanged: {
            if (!enabled) {
                card.hovered = false;
                if (card.controller.hoveredIndex === card.slot)
                    card.controller.hoveredIndex = -1;

            }
        }
        onEntered: {
            card.hovered = true;
            if (card.acceptsKeyboard) {
                card.controller.hoveredIndex = card.slot;
                card.controller.selectedIndex = card.slot;
            }
        }
        onExited: {
            card.hovered = false;
            if (card.acceptsKeyboard && card.controller.hoveredIndex === card.slot)
                card.controller.hoveredIndex = -1;

        }
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton)
                card.controller.requestClose(card.modelData);
            else
                card.controller.activate(card.modelData);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        spacing: Style.spacing.sm

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(40)
            radius: 0
            color: card.selected ? Color.menu.selectedBackground : Color.menu.background
            border.color: card.outlineColor
            border.width: 1

            Loader {
                anchors.fill: parent
                anchors.margins: Style.spacing.sm
                sourceComponent: integratedFooter
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                id: previewFrame

                readonly property real windowAspectRatio: card.controller.aspectRatioFor(card.modelData)

                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height * windowAspectRatio)
                height: Math.min(parent.height, parent.width / windowAspectRatio)
                radius: 0
                color: Color.background
                clip: true
                layer.enabled: true

                Text {
                    anchors.centerIn: parent
                    text: "Live preview unavailable"
                    textFormat: Text.PlainText
                    color: Color.menu.text
                    opacity: 0.45
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                }

                Item {
                    anchors.centerIn: parent
                    width: parent.width * 2
                    height: parent.height * 2
                    scale: 0.5
                    layer.enabled: true
                    layer.smooth: true

                    ScreencopyView {
                        anchors.fill: parent
                        captureSource: WindowModel.waylandFor(card.modelData)
                        live: card.controller.opened && card.inLayout
                        paintCursor: false
                    }

                }

                Loader {
                    anchors.fill: parent
                    z: 2
                    active: card.overlayFooter
                    sourceComponent: overlayFooter
                }

            }

            Rectangle {
                anchors.fill: previewFrame
                visible: !card.integratedFooter
                z: 5
                radius: previewFrame.radius
                color: "transparent"
                border.color: card.outlineColor
                border.width: card.outlineWidth
            }

        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 0
            visible: false

            Loader {
                anchors.fill: parent
                sourceComponent: card.floatingFooter ? floatingFooter : (card.integratedFooter ? integratedFooter : (card.centeredFooter ? centeredFooter : null))
            }

        }

    }

    // Only the configured footer style is instantiated per card.
    Component {
        id: overlayFooter

        Item {
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.min(parent.height * 0.45, Style.space(84))

                gradient: Gradient {
                    orientation: Gradient.Vertical

                    GradientStop {
                        position: 0
                        color: "transparent"
                    }

                    GradientStop {
                        position: 1
                        color: Qt.rgba(0, 0, 0, 0.94)
                    }

                }

            }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.spacing.md
                spacing: Style.spacing.md

                Image {
                    Layout.preferredWidth: Style.space(28)
                    Layout.preferredHeight: Style.space(28)
                    source: card.iconSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: card.windowTitle
                        textFormat: Text.PlainText
                        color: card.contentTextColor
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                        font.bold: card.selected
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: card.applicationName
                        textFormat: Text.PlainText
                        color: card.contentTextColor
                        opacity: 0.68
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }

                }

                ColumnLayout {
                    spacing: 0

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: card.workspaceName
                        textFormat: Text.PlainText
                        color: card.contentTextColor
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.heading
                        font.bold: true
                    }

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "Workspace"
                        textFormat: Text.PlainText
                        color: card.contentTextColor
                        opacity: 0.55
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                    }

                }

            }

        }

    }

    Component {
        id: floatingFooter

        RowLayout {
            spacing: Style.spacing.md

            Image {
                Layout.preferredWidth: Style.space(30)
                Layout.preferredHeight: Style.space(30)
                source: card.iconSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: card.windowTitle
                    textFormat: Text.PlainText
                    color: card.contentTextColor
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                    font.bold: card.selected
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: card.applicationName
                    textFormat: Text.PlainText
                    color: card.contentTextColor
                    opacity: 0.62
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }

            }

            ColumnLayout {
                spacing: 0

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: card.workspaceName
                    textFormat: Text.PlainText
                    color: card.contentTextColor
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                }

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: "Workspace"
                    textFormat: Text.PlainText
                    color: card.contentTextColor
                    opacity: 0.55
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                }

            }

        }

    }

    Component {
        id: integratedFooter

        RowLayout {
            spacing: Style.spacing.md

            Image {
                Layout.preferredWidth: Style.space(24)
                Layout.preferredHeight: Style.space(24)
                source: card.iconSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    saturation: -1
                    brightness: card.selected ? 1 : 0
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.windowTitle
                textFormat: Text.PlainText
                color: card.contentTextColor
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: card.selected
                elide: Text.ElideRight
            }

            Text {
                text: "WS " + card.workspaceName
                textFormat: Text.PlainText
                color: card.contentTextColor
                opacity: card.focusedWindow ? 1 : 0.68
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }

        }

    }

    Component {
        id: centeredFooter

        ColumnLayout {
            spacing: 0

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Style.spacing.md

                Image {
                    Layout.preferredWidth: Style.space(24)
                    Layout.preferredHeight: Style.space(24)
                    source: card.iconSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Text {
                    Layout.maximumWidth: Math.max(1, card.width - Style.space(80))
                    text: card.windowTitle
                    textFormat: Text.PlainText
                    color: card.contentTextColor
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                    font.bold: card.selected
                    elide: Text.ElideRight
                }

            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Math.max(1, card.width - Style.space(32))
                text: card.applicationName + "  ·  Workspace " + card.workspaceName
                textFormat: Text.PlainText
                color: card.contentTextColor
                opacity: card.focusedWindow ? 1 : 0.62
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
            }

        }

    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        visible: card.focusedWindow
        z: 20
        radius: 0
        color: "transparent"
        border.color: card.outlineColor
        border.width: 1
    }

    Behavior on x {
        enabled: card.controller.motionSettled && !card.controller.reducedMotion

        NumberAnimation {
            duration: card.controller.previewAnimationDuration
            easing.type: card.controller.previewAnimationEasing
        }

    }

    Behavior on y {
        enabled: card.controller.motionSettled && !card.controller.reducedMotion

        NumberAnimation {
            duration: card.controller.previewAnimationDuration
            easing.type: card.controller.previewAnimationEasing
        }

    }

    Behavior on width {
        enabled: card.controller.motionSettled && !card.controller.reducedMotion

        NumberAnimation {
            duration: card.controller.previewAnimationDuration
            easing.type: card.controller.previewAnimationEasing
        }

    }

    Behavior on height {
        enabled: card.controller.motionSettled && !card.controller.reducedMotion

        NumberAnimation {
            duration: card.controller.previewAnimationDuration
            easing.type: card.controller.previewAnimationEasing
        }

    }

    Behavior on opacity {
        enabled: card.controller.motionSettled && !card.controller.reducedMotion

        NumberAnimation {
            duration: card.controller.previewFadeDuration
        }

    }

}
