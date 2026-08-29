import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var items: []
  property string itemsJson: ""
  property var positions: ({})
  property string desktopPath: Quickshell.env("HOME") + "/Desktop"
  property string selectedId: ""
  property int iconSize: 72
  property int cellW: 144
  property int cellH: 162
  property int padLeft: 24
  property int padRight: 24
  property int padBottom: 24
  readonly property int maxItems: 256
  readonly property int maxListChars: 262144
  readonly property int maxNameLength: 120
  property var pendingTrust: null
  property string pendingTrustScreen: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: (manifest && manifest.__sourceDir)
    ? String(manifest.__sourceDir) + "/components/desktop"
    : (home + "/.config/omarchy/plugins/io.github.regionallyfamous.alumina/components/desktop")
  readonly property string indexScript: pluginDir + "/bin/desktop-index"
  readonly property string addScript: pluginDir + "/bin/add-to-desktop"
  readonly property string hyperlinkScript: home + "/.local/bin/create-hyperlink"
  readonly property string positionsPath: home + "/.config/omarchy/desktop-icon-positions.json"

  function padTopFor(screen) {
    var bar = shell && shell.bar ? shell.bar : null
    var barSize = bar && bar.barSize ? bar.barSize : 26
    var extra = 24
    if (bar && bar.position === "top" && !bar.barHidden)
      return barSize + extra
    return extra
  }

  function padLeftFor(screen) {
    var bar = shell && shell.bar ? shell.bar : null
    var barSize = bar && bar.barSize ? bar.barSize : 26
    if (bar && bar.position === "left" && !bar.barHidden)
      return barSize + 24
    return root.padLeft
  }

  function isTrash(item) {
    return !!(item && item.kind === "trash")
  }

  function isUntrustedLauncher(item) {
    return !!(item && item.kind === "launcher" && item.trusted !== true)
  }

  function isBlockedIconUrl(value) {
    var lower = String(value || "").toLowerCase()
    return lower.indexOf("http:") === 0
      || lower.indexOf("https:") === 0
      || lower.indexOf("ftp:") === 0
      || lower.indexOf("ftps:") === 0
      || lower.indexOf("sftp:") === 0
      || lower.indexOf("smb:") === 0
      || lower.indexOf("nfs:") === 0
      || lower.indexOf("dav:") === 0
      || lower.indexOf("data:") === 0
      || lower.indexOf("qrc:") === 0
      || lower.indexOf("image:") === 0
      || lower.indexOf("qt:") === 0
  }

  function isLocalFileUrl(value) {
    var icon = String(value || "")
    if (icon.indexOf("file://") !== 0)
      return false
    var rest = icon.slice(7)
    return rest.charAt(0) === "/" && rest.charAt(1) !== "/"
  }

  function plainText(value, maxLen) {
    var text = String(value || "").replace(/[<>\u0001-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ")
    text = text.replace(/\s+/g, " ").trim()
    var limit = maxLen || root.maxNameLength
    if (text.length > limit)
      text = text.slice(0, limit)
    return text
  }

  function fallbackIcon(item) {
    return Quickshell.iconPath(item && item.isDir ? "folder" : "text-x-generic", true)
  }

  function localFileUrl(path) {
    var value = String(path || "")
    if (root.isBlockedIconUrl(value))
      return ""
    if (root.isLocalFileUrl(value))
      return value
    if (!value || value.charAt(0) !== "/" || value.indexOf("//") === 0)
      return ""
    if (value.indexOf("://") !== -1)
      return ""
    return Util.fileUrl(value)
  }

  function safeIconSource(icon, item) {
    var value = String(icon || "")
    var fallback = root.fallbackIcon(item)
    if (!value || root.isBlockedIconUrl(value))
      return fallback
    if (root.isLocalFileUrl(value))
      return value
    if (value.charAt(0) === "/") {
      var local = root.localFileUrl(value)
      return local || fallback
    }
    if (value.indexOf("/") >= 0 || value.indexOf("\\") >= 0 || value.indexOf(":") >= 0)
      return fallback
    if (!/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(value))
      return fallback
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0)
      return themed
    return fallback
  }

  function iconSource(item) {
    if (!item) return ""
    var preview = String(item.preview || "")
    if (preview) {
      var previewUrl = root.localFileUrl(preview)
      if (previewUrl)
        return previewUrl
    }
    return root.safeIconSource(item.icon, item)
  }

  function sanitizeItem(item) {
    if (!item || typeof item !== "object")
      return null
    var kind = root.plainText(item.kind, 32)
    var icon = String(item.icon || "")
    var preview = String(item.preview || "")
    if (root.isBlockedIconUrl(icon))
      icon = ""
    if (root.isBlockedIconUrl(preview))
      preview = ""
    return {
      id: String(item.id || "").slice(0, 255),
      name: root.plainText(item.name, root.maxNameLength) || "Item",
      path: String(item.path || ""),
      icon: icon,
      preview: preview,
      isDir: !!item.isDir,
      kind: kind,
      trusted: item.trusted === true || kind !== "launcher"
    }
  }

  function refresh() {
    if (!listProc.running)
      listProc.running = true
  }

  function visualOrder(screenName) {
    var items = root.items
    if (!items || items.length === 0)
      return []
    var ps = screenName ? root.positions[screenName] : null
    if (!ps) {
      for (var k in root.positions) {
        ps = root.positions[k]
        break
      }
    }
    var arr = items.slice()
    arr.sort(function(a, b) {
      var pa = ps ? ps[a.id] : null
      var pb = ps ? ps[b.id] : null
      var ya = pa ? pa.y : 1e9, xa = pa ? pa.x : 1e9
      var yb = pb ? pb.y : 1e9, xb = pb ? pb.x : 1e9
      if (ya !== yb)
        return ya - yb
      return xa - xb
    })
    return arr
  }

  function moveSelection(delta, screenName) {
    var order = root.visualOrder(screenName)
    if (order.length === 0)
      return
    var idx = -1
    for (var i = 0; i < order.length; i++) {
      if (order[i].id === root.selectedId) {
        idx = i
        break
      }
    }
    if (idx === -1)
      idx = 0
    else {
      idx = (idx + delta) % order.length
      if (idx < 0)
        idx += order.length
    }
    root.selectedId = order[idx].id
  }

  function openItem(item) {
    if (!item || !item.path) return
    Quickshell.execDetached(["/usr/bin/python3", root.indexScript, "--open", item.path])
  }

  function openOrConfirm(item, screenName) {
    if (!item || !item.path) return
    if (root.isUntrustedLauncher(item)) {
      root.pendingTrust = item
      root.pendingTrustScreen = screenName || ""
      return
    }
    root.openItem(item)
  }

  function clearTrustPrompt() {
    root.pendingTrust = null
    root.pendingTrustScreen = ""
  }

  function allowLaunching(item) {
    if (!item || !item.path) return
    Quickshell.execDetached(["/usr/bin/python3", root.indexScript, "--trust", item.path])
    root.clearTrustPrompt()
    Qt.callLater(root.refresh)
  }

  function trustAndOpen(item) {
    if (!item || !item.path) return
    Quickshell.execDetached(["/usr/bin/python3", root.indexScript, "--trust-and-open", item.path])
    root.clearTrustPrompt()
    Qt.callLater(root.refresh)
  }

  function trashUrls(urls) {
    if (!urls || urls.length === 0) return
    var cmd = ["/usr/bin/python3", root.indexScript, "--trash"]
    var limit = Math.min(urls.length, root.maxItems)
    for (var i = 0; i < limit; i++)
      cmd.push(String(urls[i]))
    Quickshell.execDetached(cmd)
    Qt.callLater(root.refresh)
  }

  function trashItem(item) {
    if (!item || !item.path || root.isTrash(item)) return
    root.trashUrls([item.path])
  }

  function revealItem(item) {
    if (item && item.path)
      Quickshell.execDetached(["nautilus", "--select", item.path])
    else
      root.openDesktopFolder()
  }

  function newFolder() {
    Quickshell.execDetached([
      "bash", "-lc",
      "d=" + Util.shellQuote(root.desktopPath) + "; " +
      "n='New Folder'; p=\"$d/$n\"; i=2; " +
      "while [ -e \"$p\" ]; do p=\"$d/$n $i\"; i=$((i+1)); done; " +
      "mkdir -p \"$p\""
    ])
    Qt.callLater(root.refresh)
  }

  function newShortcut() {
    Quickshell.execDetached([root.hyperlinkScript, "--directory", root.desktopPath])
  }

  function pinApp() {
    Quickshell.execDetached(["/usr/bin/python3", root.addScript, "--pick-app"])
  }

  function addFiles() {
    Quickshell.execDetached(["/usr/bin/python3", root.addScript, "--pick-files"])
  }

  function openDesktopFolder() {
    Quickshell.execDetached(["xdg-open", root.desktopPath])
  }

  function switchWallpaper() {
    Quickshell.execDetached([
      "bash", "-lc",
      "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""
    ])
  }

  function placeUrls(urls, mode) {
    if (!urls || urls.length === 0) return
    var cmd = ["/usr/bin/python3", root.indexScript, "--mode", mode || "copy", "--place"]
    var limit = Math.min(urls.length, root.maxItems)
    for (var i = 0; i < limit; i++)
      cmd.push(String(urls[i]))
    Quickshell.execDetached(cmd)
    Qt.callLater(root.refresh)
  }

  function dropMode(drop) {
    if (!drop) return "copy"
    if (drop.proposedAction === Qt.LinkAction) return "link"
    if (drop.proposedAction === Qt.MoveAction) return "move"
    return "copy"
  }

  function applyList(raw) {
    var text = String(raw || "").trim()
    if (!text)
      return
    if (text.length > root.maxListChars) {
      console.warn("desktop-icons: index output exceeded resource ceiling")
      return
    }
    try {
      var data = JSON.parse(text)
      var incoming = Array.isArray(data.items) ? data.items.slice(0, root.maxItems) : []
      var items = []
      for (var i = 0; i < incoming.length; i++) {
        var item = root.sanitizeItem(incoming[i])
        if (item && item.id)
          items.push(item)
      }
      var desktop = data.desktop ? String(data.desktop) : root.desktopPath
      var next = JSON.stringify({ desktop: desktop, items: items })
      if (next === root.itemsJson)
        return
      root.desktopPath = desktop
      root.itemsJson = next
      root.items = items
      if (root.pendingTrust && root.pendingTrust.id) {
        var pendingId = root.pendingTrust.id
        var stillUntrusted = false
        for (var j = 0; j < items.length; j++) {
          if (items[j].id === pendingId && root.isUntrustedLauncher(items[j])) {
            stillUntrusted = true
            break
          }
        }
        if (!stillUntrusted)
          root.clearTrustPrompt()
      }
    } catch (e) {
      console.warn("desktop-icons: failed to parse index:", e)
    }
  }

  function applyPositions(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      root.positions = Util.isPlainObject(data) ? data : ({})
    } catch (e) {
      root.positions = ({})
    }
  }

  function savePositions() {
    posFile.setText(JSON.stringify(root.positions || {}, null, 2) + "\n")
  }

  function setItemPos(screenName, itemId, x, y) {
    var next = JSON.parse(JSON.stringify(root.positions || {}))
    if (!next[screenName])
      next[screenName] = ({})
    next[screenName][itemId] = { x: Math.round(x), y: Math.round(y) }
    root.positions = next
    root.savePositions()
  }

  Process {
    id: listProc
    command: ["/usr/bin/python3", root.indexScript]
    stdout: StdioCollector {
      onStreamFinished: root.applyList(text)
    }
  }

  FileView {
    id: posFile
    path: root.positionsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyPositions(text())
    onLoadFailed: root.positions = ({})
    onFileChanged: reload()
  }

  // Watch the Desktop folder itself so icons appear, move, or get deleted
  // immediately instead of waiting for the fallback poll below.
  FileView {
    id: desktopWatch
    path: root.desktopPath
    watchChanges: true
    printErrors: false
    onLoaded: root.refresh()
    onFileChanged: root.refresh()
    onLoadFailed: root.refresh()
  }

  // Safety-net poll. The directory watch above handles the common case
  // instantly; this keeps add/delete responsive if the watch ever misses.
  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      // Repeater delegates with required properties cannot see outer ids.
      property var host: root

      screen: modelData
      visible: true
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "desktop-icons"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      anchors { top: true; bottom: true; left: true; right: true }
      // Default mask is the opaque pixels only, so a transparent desktop
      // lets clicks fall through to omarchy-background (double-click
      // wallpaper). Cover the whole surface so icon clicks land here.
      mask: Region {
        width: panel.width
        height: panel.height
      }

      readonly property string screenName: modelData.name || "default"
      property int padTop: host.padTopFor(modelData)
      property int padLeft: host.padLeftFor(modelData)
      property string menuKind: ""
      property var menuItem: null
      property real menuX: 0
      property real menuY: 0
      property bool dropping: false
      property int emptyClicks: 0
      property bool _initialized: false
      property var _knownIds: ({})

      function layoutPos(index) {
        var availH = Math.max(host.cellH, panel.height - panel.padTop - host.padBottom)
        var rows = Math.max(1, Math.floor(availH / host.cellH))
        var col = Math.floor(index / rows)
        var row = index % rows
        return {
          x: panel.padLeft + col * host.cellW,
          y: panel.padTop + row * host.cellH
        }
      }

      function posFor(item, index) {
        var byScreen = host.positions[panel.screenName]
        if (item && byScreen && byScreen[item.id] && byScreen[item.id].x !== undefined)
          return byScreen[item.id]
        return layoutPos(index)
      }

      function snap(x, y) {
        var col = Math.round((x - panel.padLeft) / host.cellW)
        var row = Math.round((y - panel.padTop) / host.cellH)
        if (col < 0) col = 0
        if (row < 0) row = 0
        return {
          x: panel.padLeft + col * host.cellW,
          y: panel.padTop + row * host.cellH
        }
      }

      function itemAt(x, y, exceptId) {
        for (var i = 0; i < host.items.length; i++) {
          var item = host.items[i]
          if (exceptId && item.id === exceptId)
            continue
          var pos = panel.posFor(item, i)
          if (x >= pos.x && x < pos.x + host.cellW && y >= pos.y && y < pos.y + host.cellH)
            return item
        }
        return null
      }

      function trustIconPos() {
        var item = host.pendingTrust
        if (!item)
          return null
        for (var i = 0; i < host.items.length; i++) {
          if (host.items[i].id === item.id)
            return panel.posFor(host.items[i], i)
        }
        return null
      }

      // Place newly added icons at the bottom-most free grid cell (just past
      // the last occupied icon), skipping any cell already taken. This keeps
      // them out of the way of manually dragged icons while still landing at
      // the bottom of the list when the grid is tidy. Existing icons keep
      // their positions; stale positions for removed items are cleaned up.
      // Triggered only on add/remove, never on a drag or a routine refresh.
      function assignMissing() {
        var cur = {}
        for (var i = 0; i < host.items.length; i++)
          cur[host.items[i].id] = true
        var next = JSON.parse(JSON.stringify(host.positions || {}))
        if (!next[panel.screenName])
          next[panel.screenName] = {}
        var byScreen = next[panel.screenName]
        var dirty = false
        for (var id in byScreen) {
          if (!cur[id]) {
            delete byScreen[id]
            dirty = true
          }
        }

        var availH = Math.max(host.cellH, panel.height - panel.padTop - host.padBottom)
        var rows = Math.max(1, Math.floor(availH / host.cellH))
        function cellKey(p) {
          var col = Math.round((p.x - panel.padLeft) / host.cellW)
          var row = Math.round((p.y - panel.padTop) / host.cellH)
          if (col < 0) col = 0
          if (row < 0) row = 0
          return col + "," + row
        }
        var occupied = {}
        for (var id2 in byScreen)
          occupied[cellKey(byScreen[id2])] = true
        function firstFree(start) {
          var idx = start
          var guard = 0
          var max = Math.max(host.maxItems * 4, rows * 16)
          while (guard < max) {
            var col = Math.floor(idx / rows)
            var row = idx % rows
            if (!occupied[col + "," + row])
              return idx
            idx++
            guard++
          }
          return start
        }
        var lastIdx = -1
        for (var id3 in byScreen) {
          var parts = cellKey(byScreen[id3]).split(",")
          var idx = parseInt(parts[0], 10) * rows + parseInt(parts[1], 10)
          if (idx > lastIdx)
            lastIdx = idx
        }
        var nextIdx = firstFree(lastIdx + 1)
        for (var i = 0; i < host.items.length; i++) {
          var item = host.items[i]
          if (!byScreen[item.id]) {
            var pp = panel.layoutPos(nextIdx)
            var pos = { x: Math.round(pp.x), y: Math.round(pp.y) }
            byScreen[item.id] = pos
            occupied[cellKey(pos)] = true
            nextIdx = firstFree(nextIdx + 1)
            dirty = true
          }
        }
        if (!dirty)
          return
        host.positions = next
        host.savePositions()
      }

      // Detect add/remove (item id set change) and place only new icons.
      // First load still assigns missing positions so unsaved items do not
      // land on top of dragged ones; existing saved positions stay put.
      function maybeRepack() {
        var cur = {}
        for (var i = 0; i < host.items.length; i++)
          cur[host.items[i].id] = true
        if (!panel._initialized) {
          panel._knownIds = cur
          panel._initialized = true
          if (panel.width > host.cellW && panel.height > host.cellH)
            panel.assignMissing()
          return
        }
        var changed = false
        for (var id in cur)
          if (!panel._knownIds[id])
            changed = true
        for (var id in panel._knownIds)
          if (!cur[id])
            changed = true
        panel._knownIds = cur
        if (changed)
          panel.assignMissing()
      }

      function closeMenu() {
        menuKind = ""
        menuItem = null
      }

      function openEmptyMenu(mouse) {
        menuKind = "empty"
        menuItem = null
        menuX = mouse.x
        menuY = mouse.y
      }

      function openItemMenu(item, iconItem, mouse) {
        menuKind = "item"
        menuItem = item
        var p = contentItem.mapFromItem(iconItem, mouse.x, mouse.y)
        menuX = p.x
        menuY = p.y
      }

      readonly property var menuEntries: {
        if (menuKind === "item") {
          if (host.isTrash(menuItem))
            return [
              { action: "open", label: "Open Trash" },
              { action: "files", label: "Show in Files" }
            ]
          if (host.isUntrustedLauncher(menuItem))
            return [
              { action: "trust-open", label: "Trust and Open" },
              { action: "trust", label: "Allow launching" },
              { action: "files", label: "Show in Files" },
              { action: "trash", label: "Move to Trash" }
            ]
          return [
            { action: "open", label: "Open" },
            { action: "files", label: "Show in Files" },
            { action: "trash", label: "Move to Trash" }
          ]
        }
        if (menuKind === "empty")
          return [
            { action: "folder", label: "New Folder" },
            { action: "shortcut", label: "New Shortcut…" },
            { action: "pin", label: "Pin application…" },
            { action: "addfiles", label: "Add files…" },
            { action: "files", label: "Open Desktop Folder" },
            { action: "refresh", label: "Refresh" }
          ]
        return []
      }

      Timer {
        id: emptyClickTimer
        interval: 2500
        repeat: false
        onTriggered: panel.emptyClicks = 0
      }

      MouseArea {
        id: emptyMouse
        z: 0
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (host.pendingTrust)
              host.clearTrustPrompt()
            panel.closeMenu()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete && host.selectedId) {
            for (var i = 0; i < host.items.length; i++) {
              if (host.items[i].id === host.selectedId) {
                host.trashItem(host.items[i])
                host.selectedId = ""
                break
              }
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            for (var j = 0; j < host.items.length; j++) {
              if (host.items[j].id === host.selectedId) {
                host.openOrConfirm(host.items[j], panel.screenName)
                break
              }
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            host.moveSelection(event.modifiers & Qt.ShiftModifier ? -1 : 1, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            host.moveSelection(-1, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            host.moveSelection(-1, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            host.moveSelection(1, panel.screenName)
            event.accepted = true
          }
        }
        onClicked: function(mouse) {
          host.selectedId = ""
          emptyMouse.forceActiveFocus()
          if (host.pendingTrust) {
            host.clearTrustPrompt()
            panel.emptyClicks = 0
            if (mouse.button === Qt.RightButton)
              panel.openEmptyMenu(mouse)
            return
          }
          if (mouse.button === Qt.RightButton) {
            panel.emptyClicks = 0
            panel.openEmptyMenu(mouse)
            return
          }
          panel.closeMenu()
          panel.emptyClicks += 1
          emptyClickTimer.restart()
          if (panel.emptyClicks >= 5) {
            panel.emptyClicks = 0
            host.switchWallpaper()
          }
        }
      }

      DropArea {
        z: 0
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: panel.dropping = true
        onExited: panel.dropping = false
        onDropped: function(drop) {
          panel.dropping = false
          var urls = []
          if (drop.urls) {
            for (var i = 0; i < drop.urls.length; i++)
              urls.push(String(drop.urls[i]))
          }
          if (urls.length > 0) {
            drop.acceptProposedAction()
            var target = panel.itemAt(drop.x, drop.y, "")
            if (target && host.isTrash(target))
              host.trashUrls(urls)
            else
              host.placeUrls(urls, host.dropMode(drop))
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: panel.dropping
        color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 0.35)
        z: 5
      }

      Repeater {
        model: panel.host.items

        Item {
          id: iconRoot
          required property var modelData
          required property int index

          width: panel.host.cellW
          height: panel.host.cellH
          z: iconMouse.drag.active ? 6 : 2
          property real pressX: 0
          property real pressY: 0

          Binding on x {
            value: panel.posFor(iconRoot.modelData, iconRoot.index).x
            when: !iconMouse.drag.active
            restoreMode: Binding.RestoreNone
          }
          Binding on y {
            value: panel.posFor(iconRoot.modelData, iconRoot.index).y
            when: !iconMouse.drag.active
            restoreMode: Binding.RestoreNone
          }

          Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 8
            color: panel.host.selectedId === iconRoot.modelData.id ? Qt.rgba(1, 1, 1, 0.18) : (iconHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
            border.width: panel.host.selectedId === iconRoot.modelData.id ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.35)
          }

          HoverHandler { id: iconHover }

          Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            Item {
              width: panel.host.iconSize
              height: panel.host.iconSize
              anchors.horizontalCenter: parent.horizontalCenter

              Image {
                anchors.fill: parent
                source: panel.host.iconSource(iconRoot.modelData)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                sourceSize.width: panel.host.iconSize * Screen.devicePixelRatio
                sourceSize.height: panel.host.iconSize * Screen.devicePixelRatio
              }

              Rectangle {
                visible: panel.host.isUntrustedLauncher(iconRoot.modelData)
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 20
                height: 20
                radius: 10
                color: "#cc8a1515"
                border.width: 1
                border.color: "#eeffffff"

                Text {
                  anchors.centerIn: parent
                  text: "!"
                  textFormat: Text.PlainText
                  color: "white"
                  font.pixelSize: 13
                  font.bold: true
                  font.family: Style.fontFamily
                }
              }
            }

            Text {
              width: parent.width
              text: panel.host.plainText(iconRoot.modelData.name)
              textFormat: Text.PlainText
              color: "white"
              style: Text.Outline
              styleColor: "#cc000000"
              font.pixelSize: 18
              font.family: Style.fontFamily
              wrapMode: Text.Wrap
              elide: Text.ElideRight
              maximumLineCount: 2
              horizontalAlignment: Text.AlignHCenter
            }
          }

          MouseArea {
            id: iconMouse
            anchors.fill: parent
            z: 2
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            drag.target: iconRoot
            drag.axis: Drag.XAndYAxis
            drag.threshold: 36
            drag.minimumX: 0
            drag.minimumY: 0
            drag.maximumX: Math.max(0, panel.width - iconRoot.width)
            drag.maximumY: Math.max(0, panel.height - iconRoot.height)
            onPressed: function(mouse) {
              iconRoot.pressX = iconRoot.x
              iconRoot.pressY = iconRoot.y
              panel.host.selectedId = iconRoot.modelData.id
              emptyMouse.forceActiveFocus()
            }
            onReleased: function(mouse) {
              if (!iconMouse.drag.active) return
              var target = panel.itemAt(
                iconRoot.x + iconRoot.width / 2,
                iconRoot.y + iconRoot.height / 2,
                iconRoot.modelData.id
              )
              if (target && panel.host.isTrash(target) && !panel.host.isTrash(iconRoot.modelData)) {
                panel.host.trashItem(iconRoot.modelData)
                return
              }
              var snapped = panel.snap(iconRoot.x, iconRoot.y)
              iconRoot.x = snapped.x
              iconRoot.y = snapped.y
              panel.host.setItemPos(panel.screenName, iconRoot.modelData.id, snapped.x, snapped.y)
            }
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) {
                panel.host.selectedId = iconRoot.modelData.id
                panel.openItemMenu(iconRoot.modelData, iconRoot, mouse)
                return
              }
              if (iconMouse.drag.active) return
              if (Math.abs(iconRoot.x - iconRoot.pressX) > 8 || Math.abs(iconRoot.y - iconRoot.pressY) > 8)
                return
              panel.closeMenu()
              panel.host.openOrConfirm(iconRoot.modelData, panel.screenName)
            }
          }

          DropArea {
            anchors.fill: parent
            z: 3
            enabled: panel.host.isTrash(iconRoot.modelData)
            keys: ["text/uri-list"]
            onEntered: panel.dropping = true
            onExited: panel.dropping = false
            onDropped: function(drop) {
              panel.dropping = false
              if (!panel.host.isTrash(iconRoot.modelData))
                return
              var urls = []
              if (drop.urls) {
                for (var i = 0; i < drop.urls.length; i++)
                  urls.push(String(drop.urls[i]))
              }
              if (urls.length > 0) {
                drop.acceptProposedAction()
                panel.host.trashUrls(urls)
              }
            }
          }
        }
      }

      Rectangle {
        id: menuBox
        visible: menuKind !== ""
        z: 20
        width: menuCol.implicitWidth + 16
        height: menuCol.implicitHeight + 12
        radius: 8
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border
        x: Math.min(Math.max(8, menuX), Math.max(8, panel.width - width - 8))
        y: Math.min(Math.max(8, menuY), Math.max(8, panel.height - height - 8))

        // Bind plugin state onto this item so menu JS never needs the `panel` id.
        property var pluginHost: host
        property var currentItem: menuItem
        property string currentScreen: panel.screenName
        property int closeTick: 0

        function activateMenu(action) {
          var item = currentItem
          var plugin = pluginHost
          var screenName = currentScreen
          closeTick += 1
          if (!plugin)
            return
          if (action === "open")
            plugin.openOrConfirm(item, screenName)
          else if (action === "trust")
            plugin.allowLaunching(item)
          else if (action === "trust-open")
            plugin.trustAndOpen(item)
          else if (action === "trash")
            plugin.trashItem(item)
          else if (action === "folder")
            plugin.newFolder()
          else if (action === "shortcut")
            plugin.newShortcut()
          else if (action === "pin")
            plugin.pinApp()
          else if (action === "addfiles")
            plugin.addFiles()
          else if (action === "refresh")
            plugin.refresh()
          else if (action === "files") {
            if (item && item.path)
              plugin.revealItem(item)
            else
              plugin.openDesktopFolder()
          }
        }

        Column {
          id: menuCol
          anchors.centerIn: parent
          width: Math.max(188, implicitWidth)
          spacing: 2

          Repeater {
            model: menuEntries

            Rectangle {
              width: menuCol.width
              height: 28
              radius: 4
              color: rowMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : "transparent"

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                text: String(modelData.label || "")
                textFormat: Text.PlainText
                color: Color.popups.text
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: function(mouse) {
                  var action = String(modelData.action || "")
                  var node = rowMouse
                  while (node) {
                    if (typeof node.activateMenu === "function") {
                      node.activateMenu(action)
                      return
                    }
                    node = node.parent
                  }
                }
              }
            }
          }
        }
      }

      Connections {
        target: menuBox
        function onCloseTickChanged() {
          menuKind = ""
          menuItem = null
        }
      }

      Connections {
        target: host
        function onItemsChanged() {
          panel.maybeRepack()
        }
      }

      Rectangle {
        id: trustBox
        visible: {
          var item = host.pendingTrust
          if (!item)
            return false
          if (host.pendingTrustScreen && host.pendingTrustScreen !== panel.screenName)
            return false
          return true
        }
        z: 21
        width: Math.min(360, Math.max(280, panel.width - 48))
        height: trustCol.implicitHeight + 24
        radius: 8
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border
        x: {
          var p = panel.trustIconPos()
          if (!p)
            return Math.max(8, Math.round(panel.width / 2 - width / 2))
          return Math.min(Math.max(8, Math.round(p.x + host.cellW / 2 - width / 2)),
                          Math.max(8, panel.width - width - 8))
        }
        y: {
          var p = panel.trustIconPos()
          if (!p)
            return Math.max(8, Math.round(panel.height / 2 - height / 2))
          var above = p.y - height - 8
          if (above >= 8)
            return above
          return p.y + host.cellH + 8
        }

        MouseArea {
          anchors.fill: parent
          onClicked: {}
        }

        Column {
          id: trustCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 12
          spacing: 10

          Text {
            width: parent.width
            text: "Untrusted launcher"
            textFormat: Text.PlainText
            color: Color.popups.text
            font.pixelSize: 15
            font.bold: true
            font.family: Style.fontFamily
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: {
              var item = host.pendingTrust
              var label = item ? (item.id || item.name || "this shortcut") : "this shortcut"
              return "\"" + host.plainText(label, 80) + "\" is not marked as trusted. Opening it will run commands from the file."
            }
            textFormat: Text.PlainText
            color: Color.popups.text
            font.pixelSize: 13
            font.family: Style.fontFamily
            wrapMode: Text.WordWrap
          }

          Row {
            anchors.right: parent.right
            spacing: 8

            Rectangle {
              width: cancelLabel.implicitWidth + 20
              height: 28
              radius: 4
              color: cancelMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : "transparent"
              border.width: 1
              border.color: Color.popups.border

              Text {
                id: cancelLabel
                anchors.centerIn: parent
                text: "Cancel"
                textFormat: Text.PlainText
                color: Color.popups.text
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: cancelMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: host.clearTrustPrompt()
              }
            }

            Rectangle {
              width: trustLabel.implicitWidth + 20
              height: 28
              radius: 4
              color: trustMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : Qt.rgba(1, 1, 1, 0.08)
              border.width: 1
              border.color: Color.popups.border

              Text {
                id: trustLabel
                anchors.centerIn: parent
                text: "Trust and Open"
                textFormat: Text.PlainText
                color: Color.popups.text
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: trustMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: host.trustAndOpen(host.pendingTrust)
              }
            }
          }
        }
      }
    }
  }
}
