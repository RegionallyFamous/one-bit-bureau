import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.Commons

Item {
  id: root

  required property var context
  property bool reducedMotion: false
  property int currentActionIndex: -1
  property string confirmationActionId: ""

  signal actionRequested(string action, var context)
  signal closeRequested()

  readonly property int actionCount: root.context && root.context.actions ? root.context.actions.length : 0
  readonly property string stateMessage: root.context.missing
    ? root.context.missingReason
    : (root.context.stale ? root.context.staleReason : "")

  function focusInitial() {
    if (root.actionCount > 0) root.focusAction(0)
    else closeButton.forceActiveFocus()
  }

  function focusAction(index) {
    if (root.actionCount <= 0) {
      closeButton.forceActiveFocus()
      return
    }
    var next = Math.max(0, Math.min(index, root.actionCount - 1))
    root.currentActionIndex = next
    actionsFlick.positionViewAtIndex(next, ListView.Contain)
    Qt.callLater(function() {
      var row = actionsFlick.itemAtIndex(next)
      if (row) row.forceActiveFocus()
    })
  }

  function moveActionCursor(index, direction) {
    var next = index + direction
    if (next < 0 || next >= root.actionCount) {
      closeButton.forceActiveFocus()
      return
    }
    root.focusAction(next)
  }

  function requestAction(action) {
    if (!action || action.enabled !== true) return
    if (action.destructive === true && root.confirmationActionId !== action.id) {
      root.confirmationActionId = String(action.id)
      return
    }
    root.confirmationActionId = ""
    root.actionRequested(String(action.id), root.context)
  }

  onContextChanged: {
    root.currentActionIndex = -1
    root.confirmationActionId = ""
  }

  onConfirmationActionIdChanged: {
    if (root.confirmationActionId) confirmationDeadline.restart()
    else confirmationDeadline.stop()
  }

  Timer {
    id: confirmationDeadline
    interval: 4000
    onTriggered: root.confirmationActionId = ""
  }

  Keys.priority: Keys.AfterItem
  Keys.onEscapePressed: function(event) {
    root.closeRequested()
    event.accepted = true
  }

  Accessible.role: Accessible.Pane
  Accessible.name: "Bureau Inspector for " + root.context.name
  Accessible.description: root.stateMessage || "Identity, facts, and available actions"

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(10)

    // Identity stays visually stable even while the selected object's facts
    // refresh. That continuity is the Inspector's primary design promise.
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(94)
      radius: 0
      color: Color.foreground

      Accessible.role: Accessible.Grouping
      Accessible.name: "Identity"

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(10)

        Rectangle {
          Layout.preferredWidth: Style.space(68)
          Layout.preferredHeight: Style.space(68)
          radius: 0
          color: Color.background
          border.color: Color.background
          border.width: 1

          Image {
            id: identityImage
            anchors.fill: parent
            anchors.margins: Style.space(5)
            source: root.context.iconSource
            visible: source !== "" && status !== Image.Error
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(128, 128)
            layer.enabled: visible && root.context.iconGrayscale
            layer.effect: MultiEffect { saturation: -1 }
          }

          Text {
            anchors.centerIn: parent
            visible: !identityImage.visible || identityImage.status !== Image.Ready
            text: root.context.kind === "window" ? "W" : (root.context.kind === "app" ? "A" : "D")
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.bold: true
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            Layout.fillWidth: true
            text: "IDENTITY  /  " + root.context.kindLabel.toUpperCase()
            color: Color.background
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: root.context.name
            color: Color.background
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.context.subtitle || root.context.id
            color: Color.background
            opacity: 0.78
            elide: Text.ElideMiddle
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Rectangle {
          id: closeButton
          Layout.preferredWidth: Style.space(64)
          Layout.preferredHeight: Style.space(36)
          radius: 0
          color: activeFocus || closeMouse.containsMouse ? Color.background : Color.foreground
          border.color: Color.background
          border.width: activeFocus ? 2 : 1
          activeFocusOnTab: true

          Accessible.role: Accessible.Button
          Accessible.name: "Close Bureau Inspector"
          Accessible.description: "Dismiss the inspector and return to the invoking surface"
          Accessible.focusable: true
          Accessible.focused: activeFocus
          Accessible.onPressAction: root.closeRequested()

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Down && root.actionCount > 0) {
              root.focusAction(0); event.accepted = true; return
            }
            if (event.key === Qt.Key_Up && root.actionCount > 0) {
              root.focusAction(root.actionCount - 1); event.accepted = true; return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              root.closeRequested(); event.accepted = true; return
            }
          }

          Text {
            anchors.centerIn: parent
            text: "Close"
            color: closeButton.activeFocus || closeMouse.containsMouse ? Color.foreground : Color.background
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeRequested()
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: visible ? Style.space(42) : 0
      visible: root.stateMessage !== ""
      radius: 0
      color: Color.menu.selectedBackground
      border.color: Color.menu.border
      border.width: 1

      Accessible.role: Accessible.AlertMessage
      Accessible.name: root.context.missing ? "Object unavailable" : "Information may be stale"
      Accessible.description: root.stateMessage

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(8)

        Text {
          text: root.context.missing ? "MISSING" : "STALE"
          color: Color.menu.selectedText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          text: root.stateMessage
          color: Color.menu.selectedText
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: "FACTS"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      Accessible.role: Accessible.Heading
      Accessible.name: "Facts"
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(Style.space(190), Math.max(Style.space(54), factsColumn.implicitHeight + Style.space(12)))
      radius: 0
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 1
      clip: true

      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(6)
        contentWidth: width
        contentHeight: factsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: factsColumn
          width: parent.width

          Repeater {
            model: root.context.facts

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: factsColumn.width
              height: Style.space(34)
              radius: 0
              color: index % 2 ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04) : "transparent"

              Accessible.role: Accessible.StaticText
              Accessible.name: modelData.label + ": " + modelData.value

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(10)

                Text {
                  Layout.preferredWidth: Style.space(126)
                  text: modelData.label
                  color: Color.menu.text
                  opacity: 0.66
                  elide: Text.ElideRight
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.value
                  color: Color.menu.text
                  elide: Text.ElideMiddle
                  horizontalAlignment: Text.AlignRight
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          Text {
            width: factsColumn.width
            height: visible ? Style.space(40) : 0
            visible: root.context.facts.length === 0
            text: root.context.missing ? "No facts are available for this object." : "No additional facts."
            color: Color.menu.text
            opacity: 0.58
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: "ACTIONS"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      Accessible.role: Accessible.Heading
      Accessible.name: "Actions"
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: Style.space(104)
      radius: 0
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 1
      clip: true

      ListView {
        id: actionsFlick
        anchors.fill: parent
        anchors.margins: Style.space(5)
        model: root.context.actions
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: Style.space(3)
        currentIndex: root.currentActionIndex

        Accessible.role: Accessible.List
        Accessible.name: "Actions for " + root.context.name
        Accessible.description: root.actionCount + " actions; unavailable actions remain listed with a reason"

        delegate: Rectangle {
          id: actionRow
          required property var modelData
          required property int index
          readonly property bool available: modelData.enabled === true
          readonly property bool highlighted: activeFocus || actionMouse.containsMouse
          width: ListView.view.width
          height: Style.space(50)
          radius: 0
          color: highlighted ? Color.menu.selectedBackground : "transparent"
          border.color: highlighted ? Color.menu.border : "transparent"
          border.width: activeFocus ? 2 : 1
          opacity: available ? 1 : 0.52
          activeFocusOnTab: true

          Accessible.role: Accessible.Button
          Accessible.name: modelData.label
          Accessible.description: !available
            ? "Unavailable: " + modelData.reason
            : (modelData.destructive ? "Requires a second press to confirm" : "Available action")
          Accessible.focusable: true
          Accessible.focused: activeFocus
          Accessible.onPressAction: root.requestAction(modelData)

          onActiveFocusChanged: {
            if (!activeFocus) return
            root.currentActionIndex = index
            if (root.confirmationActionId && root.confirmationActionId !== modelData.id)
              root.confirmationActionId = ""
          }

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Up) {
              root.moveActionCursor(index, -1); event.accepted = true; return
            }
            if (event.key === Qt.Key_Down) {
              root.moveActionCursor(index, 1); event.accepted = true; return
            }
            if (event.key === Qt.Key_Home) {
              root.focusAction(0); event.accepted = true; return
            }
            if (event.key === Qt.Key_End) {
              root.focusAction(root.actionCount - 1); event.accepted = true; return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              root.requestAction(modelData); event.accepted = true; return
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              Text {
                Layout.fillWidth: true
                text: modelData.label
                color: actionRow.highlighted ? Color.menu.selectedText : Color.menu.text
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: actionRow.activeFocus
              }

              Text {
                Layout.fillWidth: true
                visible: !actionRow.available || root.confirmationActionId === modelData.id
                text: root.confirmationActionId === modelData.id
                  ? "Press again to confirm"
                  : modelData.reason
                color: actionRow.highlighted ? Color.menu.selectedText : Color.menu.text
                elide: Text.ElideRight
                opacity: 0.8
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              text: !actionRow.available
                ? "UNAVAILABLE"
                : (root.confirmationActionId === modelData.id ? "CONFIRM?" : (modelData.destructive ? "CAUTION" : "READY"))
              color: actionRow.highlighted ? Color.menu.selectedText : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: actionRow.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: {
              root.currentActionIndex = index
              if (root.confirmationActionId && root.confirmationActionId !== modelData.id)
                root.confirmationActionId = ""
            }
            onClicked: {
              actionRow.forceActiveFocus()
              root.requestAction(modelData)
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.actionCount === 0
          text: root.context.missing ? "No actions are safe for this object." : "No actions supplied."
          color: Color.menu.text
          opacity: 0.58
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(20)
      text: "↑↓ inspect actions  •  Enter act  •  Tab traverse  •  Esc close"
      color: Color.menu.text
      opacity: 0.62
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Behavior on opacity {
    enabled: !root.reducedMotion
    NumberAnimation { duration: 100; easing.type: Easing.Linear }
  }
}
