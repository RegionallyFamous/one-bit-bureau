import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "IconResolver.js" as IconResolver

// One-Bit Bureau icon picker. Two views share one paper surface:
//  - picker: choose an offline One-Bit Bureau role or the native app icon
//  - manage: browse every installed app and open the picker for any of them,
//    docked or not. Custom icons are keyed by app id, so an app that is not
//    on the dock shows its assigned icon the moment it appears.
PanelWindow {
  id: root

  property bool open: false
  property string mode: "picker" // "picker" | "manage"
  property string currentAppId: ""
  property string currentAppName: ""
  property bool fromManage: false
  property var customIcons: ({})
  property var iconSourceFor: function(id) { return "" }
  property var grayscaleFor: function(id) { return false }
  property string stateHelperPath: ""
  property string runHelperPath: ""
  property string iconMapPath: ""
  property string packDir: ""
  property var shell: null

  property var results: []
  property var appRows: []
  property bool busy: false
  property string statusText: ""
  // Bumped after every successful apply/clear and when the icon mapping is
  // reloaded, forcing preview/row bindings (which cannot track property reads
  // inside the iconSourceFor function) to re-evaluate.
  property int appliedRevision: 0
  property int gridCell: 112
  readonly property var packIcons: [
    { pack: "application", label: "Application" },
    { pack: "files", label: "Files" },
    { pack: "terminal", label: "Terminal" },
    { pack: "browser", label: "Web" },
    { pack: "code", label: "Code" },
    { pack: "mail", label: "Mail" },
    { pack: "chat", label: "Chat" },
    { pack: "music", label: "Music" },
    { pack: "video", label: "Video" },
    { pack: "calendar", label: "Calendar" },
    { pack: "settings", label: "Controls" },
    { pack: "games", label: "Games" },
    { pack: "notes", label: "Notes" },
    { pack: "theme", label: "Themes" },
    { pack: "document", label: "Documents" },
    { pack: "disk", label: "Disks" },
    { pack: "image", label: "Images" },
    { pack: "spreadsheet", label: "Spreadsheets" },
    { pack: "presentation", label: "Presentations" },
    { pack: "writer", label: "Writing" },
    { pack: "transfer", label: "Transfer" },
    { pack: "paint", label: "Paint" },
    { pack: "video-edit", label: "Video Editing" },
    { pack: "broadcast", label: "Broadcast" },
    { pack: "calculator", label: "Calculator" },
    { pack: "printer", label: "Printing" },
    { pack: "ocr", label: "Text Scan" },
    { pack: "project", label: "Projects" },
    { pack: "containers", label: "Containers" },
    { pack: "contacts", label: "Contacts" },
    { pack: "maps", label: "Maps" },
    { pack: "social", label: "Social" }
  ]

  function appHasCustomIcon(id) {
    return IconResolver.hasCustomOverride(root.customIcons, id)
  }

  function packSource(role) {
    return root.packDir ? Util.fileUrl(root.packDir + "/" + role + ".png") : ""
  }

  function showPackIcons(query) {
    var needle = String(query || "").trim().toLowerCase()
    var filtered = []
    for (var i = 0; i < root.packIcons.length; i++) {
      var icon = root.packIcons[i]
      if (!needle || String(icon.label).toLowerCase().indexOf(needle) !== -1 || String(icon.pack).indexOf(needle) !== -1)
        filtered.push(icon)
    }
    root.results = filtered
    resultGrid.currentIndex = filtered.length ? 0 : -1
    root.statusText = filtered.length ? "One-Bit Bureau pack — works offline" : "No One-Bit Bureau icon matches"
  }

  function previewSource(id) {
    var source = root.iconSourceFor(id)
    if (!source) return ""
    return String(source) + "?v=" + root.appliedRevision
  }

  function openForApp(appId, appName, fromManage) {
    root.currentAppId = String(appId || "")
    root.currentAppName = String(appName || IconResolver.sanitizeName(root.currentAppId))
    root.fromManage = !!fromManage
    root.mode = "picker"
    root.statusText = ""
    root.open = true
    root.appliedRevision++
    Qt.callLater(function() { searchField.forceActiveFocus() })
    root.prefillSearch()
  }

  function openManage() {
    root.mode = "manage"
    root.statusText = ""
    root.open = true
    root.appliedRevision++
    root.reloadApps()
    Qt.callLater(function() { appsField.forceActiveFocus() })
  }

  function close() {
    root.open = false
    root.results = []
    root.appRows = []
    root.statusText = ""
    applyDeadline.stop()
    applyProcess.running = false
    root.busy = false
  }

  // The original bundled pack is the complete, offline source of overrides.
  function prefillSearch() {
    searchField.text = ""
    root.showPackIcons("")
  }

  function searching(query) {
    root.showPackIcons(query)
  }

  function applyResult(item) {
    if (item && item.pack) {
      root.applyWith(["python3", root.stateHelperPath, "write", root.iconMapPath, root.currentAppId, "pack", item.pack], "One-Bit Bureau icon applied")
      return
    }
  }

  function useNativeIcon() {
    root.applyWith(["python3", root.stateHelperPath, "write", root.iconMapPath, root.currentAppId, "native"], "Using the app's native icon")
  }

  function useAutomaticIcon() {
    root.applyWith(["python3", root.stateHelperPath, "write", root.iconMapPath, root.currentAppId, "auto"], "Automatic icon association restored")
  }

  function clearIcon(appId) {
    root.applyWith(["python3", root.stateHelperPath, "write", root.iconMapPath, appId, "clear"], "Custom icon cleared")
  }

  function applyWith(command, successMessage) {
    if (root.busy || !root.stateHelperPath || !root.runHelperPath || !root.iconMapPath) {
      if (!root.stateHelperPath || !root.runHelperPath || !root.iconMapPath) root.statusText = "Icon state helper not found — reinstall the plugin"
      return
    }
    root.busy = true
    root.statusText = "Applying"
    applyProcess.pendingSuccess = successMessage
    applyProcess.command = ["python3", root.runHelperPath, "2200", "250", "--"].concat(command)
    applyProcess.running = true
    applyDeadline.restart()
  }

  function reloadApps() {
    if (!root.shell || !root.shell.appLibrary) {
      root.appRows = []
      appList.currentIndex = -1
      return
    }
    try {
      var rows = root.shell.appLibrary.sortedEntries(String(appsField.text).trim())
      var list = []
      for (var i = 0; i < rows.length && list.length < 400; i++) {
        var entry = rows[i] && rows[i].entry ? rows[i].entry : (rows[i] || {})
        var id = String(entry.id || "").replace(/\.desktop$/, "")
        if (!id) continue
        list.push({ id: id, name: entry.name || entry.displayName || id })
      }
      root.appRows = list
      appList.currentIndex = list.length ? 0 : -1
    } catch (error) {
      root.appRows = []
      appList.currentIndex = -1
    }
  }

  function openAppPicker(row) {
    if (!row || !row.id) return
    root.openForApp(row.id, row.name, true)
  }

  function clampedIndex(index, count) {
    if (count <= 0) return -1
    return Math.max(0, Math.min(index, count - 1))
  }

  function focusGridIndex(index) {
    var next = root.clampedIndex(index, root.results.length)
    if (next < 0) {
      searchField.forceActiveFocus()
      return
    }
    resultGrid.currentIndex = next
    resultGrid.positionViewAtIndex(next, GridView.Contain)
    Qt.callLater(function() {
      var tile = resultGrid.itemAtIndex(next)
      if (tile) tile.forceActiveFocus()
      else resultGrid.forceActiveFocus()
    })
  }

  function moveGridCursor(index, key) {
    var columns = Math.max(1, Math.floor(resultGrid.width / root.gridCell))
    var next = index
    if (key === Qt.Key_Left) next--
    else if (key === Qt.Key_Right) next++
    else if (key === Qt.Key_Up) {
      if (index < columns) {
        searchField.forceActiveFocus()
        return true
      }
      next -= columns
    } else if (key === Qt.Key_Down) {
      if (index + columns >= root.results.length) {
        automaticAction.forceActiveFocus()
        return true
      }
      next += columns
    }
    else if (key === Qt.Key_Home) next = 0
    else if (key === Qt.Key_End) next = root.results.length - 1
    else return false
    root.focusGridIndex(next)
    return true
  }

  function focusAppIndex(index, action) {
    var next = root.clampedIndex(index, root.appRows.length)
    if (next < 0) {
      appsField.forceActiveFocus()
      return
    }
    appList.currentIndex = next
    appList.positionViewAtIndex(next, ListView.Contain)
    Qt.callLater(function() {
      var row = appList.itemAtIndex(next)
      if (row) row.focusAction(action || "row")
      else appList.forceActiveFocus()
    })
  }

  function returnToManager() {
    root.mode = "manage"
    root.statusText = ""
    root.reloadApps()
    Qt.callLater(function() { appsField.forceActiveFocus() })
  }

  visible: root.open
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "regionallyfamous.one-bit-bureau.dock-icon-picker"
  WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: dismissSurface }

  onCustomIconsChanged: root.appliedRevision++

  Timer {
    id: appsTimer
    interval: 200
    onTriggered: root.reloadApps()
  }

  Process {
    id: applyProcess
    property string pendingSuccess: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim()) root.applyError = text.trim()
      }
    }
    onExited: function(exitCode) {
      applyDeadline.stop()
      var success = exitCode === 0
      root.busy = false
      if (success) {
        root.appliedRevision++
        root.statusText = applyProcess.pendingSuccess
      } else {
        root.statusText = "Failed — " + (root.applyError || "couldn't complete the change")
      }
      root.applyError = ""
    }
  }

  Timer {
    id: applyDeadline
    interval: 2500
    onTriggered: {
      if (applyProcess.running) {
        applyProcess.running = false
        root.busy = false
        root.statusText = "Failed — icon update timed out"
      }
    }
  }

  property string applyError: ""

  Connections {
    target: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
    function onAppsChanged() { if (root.open && root.mode === "manage") root.reloadApps() }
  }

  Component.onDestruction: {
    appsTimer.stop()
    applyDeadline.stop()
    applyProcess.running = false
  }

  // ---- Surface -------------------------------------------------------------

  Item {
    id: dismissSurface
    anchors.fill: parent
    z: -1

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: 760
    height: 560
    radius: 0
    color: Color.background
    border.color: Color.foreground
    border.width: 2

    Accessible.role: Accessible.Dialog
    Accessible.name: root.mode === "picker" ? "Choose an icon for " + root.currentAppName : "One-Bit Bureau icon manager"

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }

      Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        // Header -------------------------------------------------------------
        Rectangle {
          id: headerRow
          width: parent.width
          height: 56
          radius: 0
          color: Color.foreground

          Row {
            id: headerContent
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8

            Rectangle {
              id: previewTile
              width: 44
              height: 44
              radius: 0
              color: Color.background
              visible: root.mode === "picker"

              PackAwareImage {
                id: previewImage
                anchors.centerIn: parent
                width: 38
                height: 38
                source: root.mode === "picker" ? root.previewSource(root.currentAppId) : ""
                grayscale: root.mode === "picker" && root.grayscaleFor(root.currentAppId)
                sourceSize: Qt.size(76, 76)
                fillMode: Image.PreserveAspectFit
                cache: true

                Text {
                  anchors.centerIn: parent
                  visible: parent.status !== Image.Ready
                  text: "?"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: headerContent.width
                - closeButton.width
                - (previewTile.visible ? previewTile.width : 0)
                - (backButton.visible ? backButton.width : 0)
                - headerContent.spacing * (1 + (previewTile.visible ? 1 : 0) + (backButton.visible ? 1 : 0))
              spacing: 1

              Text {
                width: parent.width
                text: root.mode === "picker" ? root.currentAppName : "Icon Manager"
                elide: Text.ElideRight
                color: Color.background
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                width: parent.width
                text: root.mode === "picker"
                  ? "Choose a One-Bit Bureau mark or keep the app original"
                  : "Assign icons to installed applications"
                elide: Text.ElideRight
                color: Color.background
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            ActionButton {
              id: backButton
              text: "All apps"
              accessibleDescription: "Return to the installed application list"
              width: 82
              height: 44
              inverse: true
              visible: root.mode === "picker" && root.fromManage
              onClicked: root.returnToManager()
              onNavigate: function(key) {
                if (key === Qt.Key_Right) closeButton.forceActiveFocus()
                else if (key === Qt.Key_Left) closeButton.forceActiveFocus()
                else if (key === Qt.Key_Down) searchField.forceActiveFocus()
              }
            }

            ActionButton {
              id: closeButton
              text: "Close"
              accessibleDescription: "Close the icon manager"
              width: 68
              height: 44
              inverse: true
              onClicked: root.close()
              onNavigate: function(key) {
                if (key === Qt.Key_Left && backButton.visible) backButton.forceActiveFocus()
                else if (key === Qt.Key_Right && backButton.visible) backButton.forceActiveFocus()
                else if (key === Qt.Key_Down && root.mode === "picker") searchField.forceActiveFocus()
                else if (key === Qt.Key_Down) appsField.forceActiveFocus()
              }
            }
          }
        }

        // Search row ---------------------------------------------------------
        Rectangle {
          id: searchRow
          width: parent.width
          height: 44
          radius: 0
          color: Color.background
          border.color: Color.foreground
          border.width: searchField.activeFocus || appsField.activeFocus ? 2 : 1

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            text: "Find:"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          TextField {
            id: searchField
            visible: root.mode === "picker"
            anchors.left: parent.left
            anchors.leftMargin: 56
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Filter One-Bit Bureau icons"
            placeholderTextColor: Qt.darker(Color.foreground, 1.6)
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            background: Item {}
            Accessible.name: "Filter One-Bit Bureau icons"
            Accessible.searchEdit: true
            onTextChanged: root.searching(text)
            Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
            Keys.onUpPressed: function(event) { closeButton.forceActiveFocus(); event.accepted = true }
            Keys.onDownPressed: function(event) { root.focusGridIndex(resultGrid.currentIndex < 0 ? 0 : resultGrid.currentIndex); event.accepted = true }
          }

          TextField {
            id: appsField
            visible: root.mode === "manage"
            anchors.left: parent.left
            anchors.leftMargin: 56
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Search installed apps"
            placeholderTextColor: Qt.darker(Color.foreground, 1.6)
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            background: Item {}
            Accessible.name: "Search installed applications"
            Accessible.searchEdit: true
            onTextChanged: { root.statusText = ""; appsTimer.restart() }
            Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
            Keys.onUpPressed: function(event) { closeButton.forceActiveFocus(); event.accepted = true }
            Keys.onDownPressed: function(event) { root.focusAppIndex(appList.currentIndex < 0 ? 0 : appList.currentIndex, "row"); event.accepted = true }
          }
        }

        // Content ------------------------------------------------------------
        Rectangle {
          id: contentFrame
          width: parent.width
          height: 324
          radius: 0
          clip: true
          color: Color.background
          border.color: Color.foreground
          border.width: 1

          GridView {
            id: resultGrid
            visible: root.mode === "picker"
            anchors.fill: parent
            anchors.margins: 2
            model: root.results
            cellWidth: root.gridCell
            cellHeight: root.gridCell
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            activeFocusOnTab: false
            currentIndex: root.results.length > 0 ? 0 : -1

            Keys.onPressed: function(event) {
              var index = resultGrid.currentIndex < 0 ? 0 : resultGrid.currentIndex
              if (root.moveGridCursor(index, event.key)) {
                event.accepted = true
                return
              }
              if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                  && index < root.results.length) {
                root.applyResult(root.results[index])
                event.accepted = true
                return
              }
              event.accepted = false
            }

            Accessible.role: Accessible.List
            Accessible.name: "One-Bit Bureau icon choices"
            Accessible.description: resultGrid.currentIndex >= 0 && resultGrid.currentIndex < root.results.length
              ? String(root.results[resultGrid.currentIndex].label || "icon")
              : "No matching icons"

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: root.gridCell
              height: root.gridCell
              radius: 0
              enabled: !root.busy
              activeFocusOnTab: enabled
              property bool keyboardCursor: resultGrid.currentIndex === index && activeFocus
              color: keyboardCursor ? Color.foreground : Color.background
              border.color: Color.foreground
              border.width: keyboardCursor ? 2 : (gridMouse.containsMouse ? 1 : 0)

              Accessible.role: Accessible.Button
              Accessible.name: "Use " + String(modelData.label || "icon") + " icon for " + root.currentAppName
              Accessible.description: "Applies this icon immediately"
              Accessible.focusable: enabled && visible
              Accessible.focused: activeFocus
              Accessible.selectable: true
              Accessible.selected: resultGrid.currentIndex === index
              Accessible.onPressAction: root.applyResult(modelData)

              Keys.onPressed: function(event) {
                if (root.moveGridCursor(index, event.key)) {
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                  root.applyResult(modelData)
                  event.accepted = true
                  return
                }
                event.accepted = false
              }

              Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: 74
                  height: 74
                  radius: 0
                  color: Color.background
                  border.color: Color.foreground
                  border.width: 1

                  PackAwareImage {
                    anchors.centerIn: parent
                    width: 66
                    height: 66
                    source: root.packSource(modelData.pack)
                    sourceSize: Qt.size(136, 136)
                    fillMode: Image.PreserveAspectFit
                    cache: true
                    asynchronous: false
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: root.gridCell - 12
                  text: modelData.label || "icon"
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  color: parent.parent.keyboardCursor ? Color.background : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: parent.parent.keyboardCursor
                }
              }

              MouseArea {
                id: gridMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: {
                  resultGrid.currentIndex = index
                  parent.forceActiveFocus()
                }
                onClicked: root.applyResult(modelData)
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.results.length === 0 && root.statusText === ""
              text: "One-Bit Bureau icon pack unavailable"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          ListView {
            id: appList
            visible: root.mode === "manage"
            anchors.fill: parent
            anchors.margins: 2
            model: root.appRows
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 0
            activeFocusOnTab: false
            currentIndex: root.appRows.length > 0 ? 0 : -1

            Keys.onPressed: function(event) {
              var index = appList.currentIndex < 0 ? 0 : appList.currentIndex
              if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                root.focusAppIndex(index + (event.key === Qt.Key_Up ? -1 : 1), "row")
                event.accepted = true
                return
              }
              if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                  && index < root.appRows.length) {
                root.openAppPicker(root.appRows[index])
                event.accepted = true
                return
              }
              event.accepted = false
            }

            Accessible.role: Accessible.List
            Accessible.name: "Installed applications"

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: ListView.view.width
              height: 56
              radius: 0
              activeFocusOnTab: true
              property bool keyboardCursor: activeFocus || changeAction.activeFocus || clearAction.activeFocus
              color: index % 2 === 1 ? Qt.darker(Color.background, 1.04) : Color.background
              border.color: Color.foreground
              border.width: keyboardCursor ? 2 : (rowMouse.containsMouse ? 1 : 0)

              function focusAction(action) {
                if (action === "change") changeAction.forceActiveFocus()
                else if (action === "clear" && clearAction.visible) clearAction.forceActiveFocus()
                else forceActiveFocus()
              }

              function moveRow(delta, action) {
                if (index + delta < 0) {
                  appsField.forceActiveFocus()
                  return
                }
                if (index + delta >= root.appRows.length) {
                  doneAction.forceActiveFocus()
                  return
                }
                root.focusAppIndex(index + delta, action)
              }

              Accessible.role: Accessible.ListItem
              Accessible.name: String(modelData.name)
              Accessible.description: root.appHasCustomIcon(modelData.id) ? "Custom icon assigned" : "Automatic icon association"
              Accessible.focusable: enabled && visible
              Accessible.focused: activeFocus
              Accessible.selectable: true
              Accessible.selected: appList.currentIndex === index
              Accessible.onPressAction: root.openAppPicker(modelData)

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                  moveRow(event.key === Qt.Key_Up ? -1 : 1, "row")
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Right) {
                  changeAction.forceActiveFocus()
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                  root.focusAppIndex(event.key === Qt.Key_Home ? 0 : root.appRows.length - 1, "row")
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                  root.openAppPicker(modelData)
                  event.accepted = true
                  return
                }
                event.accepted = false
              }

              PackAwareImage {
                id: rowIcon
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                source: root.previewSource(modelData.id)
                grayscale: root.grayscaleFor(modelData.id)
                sourceSize: Qt.size(72, 72)
                fillMode: Image.PreserveAspectFit
                cache: true
                asynchronous: false
              }

              Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: 12
                anchors.right: actions.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                elide: Text.ElideRight
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              Row {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                ActionButton {
                  id: changeAction
                  text: "Change"
                  accessibleName: "Change icon for " + String(modelData.name)
                  accessibleDescription: "Open the One-Bit Bureau icon choices"
                  width: 76
                  height: 44
                  onClicked: root.openAppPicker(modelData)
                  onNavigate: function(key) {
                    if (key === Qt.Key_Left) parent.parent.forceActiveFocus()
                    else if (key === Qt.Key_Right && clearAction.visible) clearAction.forceActiveFocus()
                    else if (key === Qt.Key_Right) parent.parent.forceActiveFocus()
                    else if (key === Qt.Key_Up || key === Qt.Key_Down) parent.parent.moveRow(key === Qt.Key_Up ? -1 : 1, "change")
                  }
                }

                ActionButton {
                  id: clearAction
                  text: "Clear"
                  accessibleName: "Clear custom icon for " + String(modelData.name)
                  accessibleDescription: "Restore automatic icon association"
                  width: 64
                  height: 44
                  visible: root.appHasCustomIcon(modelData.id)
                  enabled: !root.busy
                  onClicked: root.clearIcon(modelData.id)
                  onNavigate: function(key) {
                    if (key === Qt.Key_Left) changeAction.forceActiveFocus()
                    else if (key === Qt.Key_Right) parent.parent.forceActiveFocus()
                    else if (key === Qt.Key_Up || key === Qt.Key_Down) parent.parent.moveRow(key === Qt.Key_Up ? -1 : 1, "clear")
                  }
                }
              }

              MouseArea {
                id: rowMouse
                anchors.left: parent.left
                anchors.right: actions.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: {
                  appList.currentIndex = index
                  parent.forceActiveFocus()
                }
                onClicked: root.openAppPicker(modelData)
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.appRows.length === 0
              text: root.shell && root.shell.appLibrary ? "No apps match" : "App library unavailable"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }

        // Bottom actions ------------------------------------------------------
        Item {
          id: bottomRow
          width: parent.width
          height: 44

          ActionButton {
            id: automaticAction
            text: "Automatic"
            accessibleDescription: "Use One-Bit Bureau's automatic app association"
            anchors.left: parent.left
            width: 100
            height: 44
            visible: root.mode === "picker"
            enabled: !root.busy
            onClicked: root.useAutomaticIcon()
            onNavigate: function(key) {
              if (key === Qt.Key_Right) nativeAction.forceActiveFocus()
              else if (key === Qt.Key_Left) doneAction.forceActiveFocus()
              else if (key === Qt.Key_Up) root.focusGridIndex(resultGrid.currentIndex < 0 ? root.results.length - 1 : resultGrid.currentIndex)
            }
          }
          ActionButton {
            id: nativeAction
            text: "Native"
            accessibleDescription: "Use the application's original icon"
            anchors.left: automaticAction.right
            anchors.leftMargin: 8
            width: 84
            height: 44
            visible: root.mode === "picker"
            enabled: !root.busy
            onClicked: root.useNativeIcon()
            onNavigate: function(key) {
              if (key === Qt.Key_Left) automaticAction.forceActiveFocus()
              else if (key === Qt.Key_Right) doneAction.forceActiveFocus()
              else if (key === Qt.Key_Up) root.focusGridIndex(resultGrid.currentIndex < 0 ? root.results.length - 1 : resultGrid.currentIndex)
            }
          }

          ActionButton {
            id: doneAction
            text: "Done"
            accessibleDescription: "Close the icon manager"
            anchors.right: parent.right
            width: 80
            height: 44
            accent: true
            onClicked: root.close()
            onNavigate: function(key) {
              if (key === Qt.Key_Up && root.mode === "picker") root.focusGridIndex(resultGrid.currentIndex < 0 ? root.results.length - 1 : resultGrid.currentIndex)
              else if (key === Qt.Key_Up) root.focusAppIndex(appList.currentIndex < 0 ? root.appRows.length - 1 : appList.currentIndex, "row")
              else if (key === Qt.Key_Left && root.mode === "picker") nativeAction.forceActiveFocus()
              else if (key === Qt.Key_Right && root.mode === "picker") automaticAction.forceActiveFocus()
            }
          }
        }

        // Status --------------------------------------------------------------
        Row {
          id: statusRow
          width: parent.width
          height: 16

          Text {
            width: parent.width
            text: root.statusText
            elide: Text.ElideRight
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            Accessible.role: Accessible.StaticText
            Accessible.name: root.statusText
          }
        }
      }
    }
  }

  component ActionButton: Item {
    id: buttonSelf
    property string text: ""
    property string accessibleName: text
    property string accessibleDescription: ""
    property bool accent: false
    property bool dimmed: false
    property bool inverse: false
    property int visualHeight: 30
    implicitHeight: 44
    activeFocusOnTab: enabled && visible
    signal clicked()
    signal navigate(int key)

    Accessible.role: Accessible.Button
    Accessible.name: buttonSelf.accessibleName
    Accessible.description: buttonSelf.accessibleDescription
    Accessible.focusable: buttonSelf.enabled && buttonSelf.visible
    Accessible.focused: buttonSelf.activeFocus
    Accessible.defaultButton: buttonSelf.accent
    Accessible.onPressAction: if (buttonSelf.enabled) buttonSelf.clicked()

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
        buttonSelf.navigate(event.key)
        event.accepted = true
        return
      }
      if (!buttonSelf.enabled || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)) {
        event.accepted = false
        return
      }
      buttonSelf.clicked()
      event.accepted = true
    }

    Rectangle {
      id: buttonFace
      anchors.centerIn: parent
      width: parent.width
      height: Math.min(parent.height, buttonSelf.visualHeight)
      radius: 0
      color: {
        if (!buttonSelf.enabled || buttonSelf.dimmed) return Color.background
        if (buttonSelf.activeFocus || buttonMouse.containsMouse || buttonMouse.pressed)
          return buttonSelf.inverse ? Color.background : Color.foreground
        return buttonSelf.inverse ? Color.foreground : Color.background
      }
      border.color: buttonSelf.inverse ? Color.background : Color.foreground
      border.width: buttonSelf.activeFocus || buttonSelf.accent ? 2 : 1

      Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        visible: buttonSelf.accent && !buttonSelf.activeFocus
        radius: 0
        color: "transparent"
        border.color: buttonSelf.inverse ? Color.background : Color.foreground
        border.width: 1
      }

      Text {
        anchors.centerIn: parent
        text: buttonSelf.text
        color: {
          if (buttonSelf.activeFocus || buttonMouse.containsMouse || buttonMouse.pressed)
            return buttonSelf.inverse ? Color.foreground : Color.background
          return buttonSelf.inverse ? Color.background : Color.foreground
        }
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: buttonSelf.accent || buttonSelf.activeFocus
      }
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      enabled: buttonSelf.enabled
      hoverEnabled: true
      cursorShape: buttonSelf.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onPressed: buttonSelf.forceActiveFocus()
      onClicked: if (buttonSelf.enabled) buttonSelf.clicked()
    }
  }
}
