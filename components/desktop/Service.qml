import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var items: []
  property string itemsJson: ""
  property var positions: ({})
  property string desktopPath: Quickshell.env("HOME") + "/Desktop"
  // selectedId is the keyboard cursor/anchor for compatibility with the
  // original single-selection implementation. selectedIds is the bounded,
  // authoritative selection set.
  property string selectedId: ""
  property var selectedIds: []
  property string selectionAnchorId: ""
  property int iconSize: 64
  property int cellW: 120
  property int cellH: 142
  property int padLeft: 24
  property int padRight: 24
  property int padBottom: 24
  property string statusMessage: ""
  property bool statusIsError: false
  property bool operationBusy: false
  property string operationMessage: ""
  property bool operationIsError: false
  property bool operationUndoable: false
  property string operationId: ""
  property string operationScreen: ""
  property string operationOutput: ""
  property string operationErrorOutput: ""
  property string operationCommand: ""
  property string inspectOutput: ""
  property string inspectErrorOutput: ""
  property string inspectPendingId: ""
  property string inspectPendingScreen: ""
  property var inspectorSubject: null
  property bool inspectorOpen: false
  property string inspectorScreen: ""
  property bool routeVisible: false
  property bool routeValid: false
  property string routeReason: ""
  property string routeSummary: ""
  property string routeScreen: ""
  property bool lastRouteValid: false
  property string lastRouteReason: ""
  property string lastRouteSummary: ""
  readonly property int maxItems: 256
  readonly property int maxOperationItems: 64
  readonly property int maxListChars: 262144
  readonly property int maxOperationChars: 131072
  readonly property int maxNameLength: 120
  property var pendingTrust: null
  property string pendingTrustScreen: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: (manifest && manifest.__sourceDir)
    ? String(manifest.__sourceDir) + "/components/desktop"
    : (home + "/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau/components/desktop")
  readonly property string indexScript: pluginDir + "/bin/desktop-index"
  readonly property string addScript: pluginDir + "/bin/add-to-desktop"
  readonly property string operationScript: pluginDir + "/bin/desktop-operation"
  readonly property string hyperlinkScript: home + "/.local/bin/create-hyperlink"
  readonly property string positionsPath: home + "/.config/omarchy/one-bit-bureau/desktop-icon-positions.json"
  readonly property string pluginId: String((root.manifest && root.manifest.id) || "io.github.regionallyfamous.one-bit-bureau")
  readonly property var pluginEntry: {
    var config = root.shell && root.shell.shellConfig ? root.shell.shellConfig : null
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++)
      if (plugins[i] && String(plugins[i].id || "") === root.pluginId)
        return plugins[i]
    return null
  }
  readonly property bool reducedMotion: root.pluginEntry && root.pluginEntry.reducedMotion === true

  signal inspectRequested(var payload, string screenName)
  signal inspectorCloseRequested()

  IpcHandler {
    target: "regionallyfamous.one-bit-bureau.desktop"
    function getRouteVisible(): bool { return root.routeVisible }
    function getRouteValid(): bool { return root.routeValid }
    function getRouteReason(): string { return root.routeReason }
    function getRouteSummary(): string { return root.routeSummary }
    function getLastRouteValid(): bool { return root.lastRouteValid }
    function getLastRouteReason(): string { return root.lastRouteReason }
    function getLastRouteSummary(): string { return root.lastRouteSummary }
  }

  function publishRouteState(screenName, visible, valid, reason, summary) {
    root.routeScreen = String(screenName || "")
    root.routeVisible = visible === true
    root.routeValid = valid === true
    root.routeReason = root.plainText(reason, 160)
    root.routeSummary = root.plainText(summary, 280)
    root.lastRouteValid = root.routeValid
    root.lastRouteReason = root.routeReason
    root.lastRouteSummary = root.routeSummary
  }

  function clearRouteState(screenName) {
    if (root.routeScreen !== String(screenName || ""))
      return
    root.routeVisible = false
    root.routeValid = false
    root.routeReason = ""
    root.routeSummary = ""
    root.routeScreen = ""
  }

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

  function basename(path) {
    var value = String(path || "").replace(/\/+$/, "")
    var slash = value.lastIndexOf("/")
    return root.plainText(slash >= 0 ? value.slice(slash + 1) : value, 100) || "item"
  }

  function localPath(value) {
    var path = String(value || "")
    if (path.indexOf("file://") === 0) {
      var encoded = path.slice(7)
      // Only file:///absolute/path is local. file://host/path and every other
      // URI scheme stay outside the filesystem helper's authority.
      if (!encoded || encoded.charAt(0) !== "/" || encoded.charAt(1) === "/")
        return ""
      try {
        path = decodeURIComponent(encoded)
      } catch (e) {
        return ""
      }
    }
    if (!path || path.charAt(0) !== "/" || path.indexOf("\u0000") !== -1)
      return ""
    if (path.indexOf("://") !== -1)
      return ""
    return path
  }

  function itemById(id) {
    var wanted = String(id || "")
    for (var i = 0; i < root.items.length; i++)
      if (root.items[i].id === wanted)
        return root.items[i]
    return null
  }

  function isSelected(itemOrId) {
    var id = typeof itemOrId === "object" && itemOrId
      ? String(itemOrId.id || "")
      : String(itemOrId || "")
    return id !== "" && root.selectedIds.indexOf(id) !== -1
  }

  function setSelectedIds(ids, cursorId, anchorId) {
    var next = []
    var seen = ({})
    var limit = Math.min(Array.isArray(ids) ? ids.length : 0, root.maxOperationItems)
    for (var i = 0; i < limit; i++) {
      var id = String(ids[i] || "")
      if (!id || seen[id] || !root.itemById(id))
        continue
      seen[id] = true
      next.push(id)
    }
    root.selectedIds = next
    var cursor = String(cursorId || "")
    if (cursor && next.indexOf(cursor) !== -1)
      root.selectedId = cursor
    else
      root.selectedId = next.length > 0 ? next[next.length - 1] : ""
    if (anchorId !== undefined)
      root.selectionAnchorId = String(anchorId || "")
    else if (!root.selectionAnchorId || !root.itemById(root.selectionAnchorId))
      root.selectionAnchorId = root.selectedId
  }

  function clearSelection() {
    root.selectedIds = []
    root.selectedId = ""
    root.selectionAnchorId = ""
  }

  function selectedItems(fallbackItem) {
    var selected = []
    var wanted = ({})
    for (var i = 0; i < root.selectedIds.length && selected.length < root.maxOperationItems; i++)
      wanted[root.selectedIds[i]] = true
    for (var j = 0; j < root.items.length && selected.length < root.maxOperationItems; j++)
      if (wanted[root.items[j].id] && !root.isTrash(root.items[j]))
        selected.push(root.items[j])
    if (selected.length === 0 && fallbackItem && !root.isTrash(fallbackItem))
      selected.push(fallbackItem)
    return selected
  }

  function selectedPaths(fallbackItem) {
    var chosen = root.selectedItems(fallbackItem)
    var paths = []
    for (var i = 0; i < chosen.length; i++) {
      var path = root.localPath(chosen[i].path)
      if (path)
        paths.push(path)
    }
    return paths
  }

  function selectedPathsExcept(excludedItem) {
    var excludedId = excludedItem ? String(excludedItem.id || "") : ""
    var chosen = root.selectedItems(null)
    var paths = []
    for (var i = 0; i < chosen.length; i++) {
      if (excludedId && chosen[i].id === excludedId)
        continue
      var path = root.localPath(chosen[i].path)
      if (path)
        paths.push(path)
    }
    return paths
  }

  function rangeIds(fromId, toId, screenName) {
    var order = root.visualOrder(screenName)
    var from = -1
    var to = -1
    for (var i = 0; i < order.length; i++) {
      if (order[i].id === fromId) from = i
      if (order[i].id === toId) to = i
    }
    if (from < 0 || to < 0)
      return toId ? [toId] : []
    var first = Math.min(from, to)
    var last = Math.max(from, to)
    var result = []
    for (var j = first; j <= last && result.length < root.maxOperationItems; j++)
      result.push(order[j].id)
    return result
  }

  function selectItem(item, modifiers, screenName) {
    if (!item || !item.id)
      return
    var id = String(item.id)
    var ctrl = !!(modifiers & Qt.ControlModifier)
    var shift = !!(modifiers & Qt.ShiftModifier)
    if (shift) {
      var anchor = root.selectionAnchorId || root.selectedId || id
      var range = root.rangeIds(anchor, id, screenName)
      if (ctrl)
        range = root.selectedIds.concat(range)
      root.setSelectedIds(range, id, anchor)
      return
    }
    if (ctrl) {
      var next = root.selectedIds.slice()
      var index = next.indexOf(id)
      if (index >= 0)
        next.splice(index, 1)
      else if (next.length < root.maxOperationItems)
        next.push(id)
      root.setSelectedIds(next, index >= 0 ? "" : id, id)
      return
    }
    root.setSelectedIds([id], id, id)
  }

  function selectAll(screenName) {
    var order = root.visualOrder(screenName)
    var ids = []
    for (var i = 0; i < order.length && ids.length < root.maxOperationItems; i++)
      ids.push(order[i].id)
    root.setSelectedIds(ids, ids.length > 0 ? ids[ids.length - 1] : "",
                        ids.length > 0 ? ids[0] : "")
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

  function categoryIconName(item) {
    if (!item)
      return ""
    var kind = String(item.kind || "")
    if (kind === "trash")
      return "trash"
    if (kind === "folder" || item.isDir)
      return "folder"
    if (kind === "image")
      return root.hasImagePreview(item) ? "" : "image"
    if (kind === "file") {
      var filename = String(item.name || item.path || "").toLowerCase()
      if (/\.(7z|bz2|gz|rar|tar|tgz|xz|zip)$/.test(filename))
        return "archive"
      return "document"
    }
    if (kind === "link")
      return "link"
    if (kind === "launcher") {
      var icon = String(item.icon || "")
      if (!icon || icon === "application-x-executable")
        return "launcher"
    }
    return ""
  }

  function usesCategoryIcon(item) {
    return root.categoryIconName(item) !== ""
  }

  function hasImagePreview(item) {
    return !!(item
      && item.kind === "image"
      && root.localFileUrl(String(item.preview || "")))
  }

  function accessibleDescription(item) {
    if (!item)
      return "Desktop object"
    if (root.isUntrustedLauncher(item))
      return "Untrusted application shortcut. Opening asks for confirmation."
    if (root.isTrash(item))
      return "Trash. Press to open."
    if (root.hasImagePreview(item))
      return "Picture file shown as a grayscale photo thumbnail. Press to open the original."
    if (item.isDir || item.kind === "folder")
      return "Folder. Press to open."
    if (item.kind === "launcher")
      return "Application shortcut. Press to open."
    return "File. Press to open."
  }

  function objectIconSource(item, selected) {
    var category = root.categoryIconName(item)
    if (!category)
      return root.iconSource(item)
    var suffix = selected ? "-selected" : ""
    return root.localFileUrl(root.pluginDir + "/assets/" + category + suffix + ".png")
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

  function moveSelection(delta, screenName, extend) {
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
    var nextId = order[idx].id
    if (extend) {
      var anchor = root.selectionAnchorId || root.selectedId || nextId
      root.setSelectedIds(root.rangeIds(anchor, nextId, screenName), nextId, anchor)
    } else {
      root.setSelectedIds([nextId], nextId, nextId)
    }
  }

  function moveSelectionSpatial(dx, dy, screenName, extend) {
    var current = root.itemById(root.selectedId)
    if (!current) {
      root.moveSelection(1, screenName, extend)
      return
    }
    var currentPos = null
    var byScreen = root.positions[screenName]
    if (byScreen && byScreen[current.id])
      currentPos = byScreen[current.id]
    if (!currentPos) {
      root.moveSelection((dx < 0 || dy < 0) ? -1 : 1, screenName, extend)
      return
    }
    var best = null
    var bestScore = Number.MAX_VALUE
    for (var i = 0; i < root.items.length; i++) {
      var candidate = root.items[i]
      if (candidate.id === current.id)
        continue
      var p = byScreen ? byScreen[candidate.id] : null
      if (!p)
        continue
      var deltaX = Number(p.x) - Number(currentPos.x)
      var deltaY = Number(p.y) - Number(currentPos.y)
      var primary = dx !== 0 ? deltaX * dx : deltaY * dy
      if (primary <= 0)
        continue
      var secondary = dx !== 0 ? Math.abs(deltaY) : Math.abs(deltaX)
      // Prefer the nearest item in the requested half-plane, with a strong
      // bias for candidates aligned on the same visual row or column.
      var score = primary * 1000 + secondary * 4
      if (score < bestScore) {
        bestScore = score
        best = candidate
      }
    }
    if (!best) {
      root.moveSelection((dx < 0 || dy < 0) ? -1 : 1, screenName, extend)
      return
    }
    if (extend) {
      var anchor = root.selectionAnchorId || current.id
      root.setSelectedIds(root.rangeIds(anchor, best.id, screenName), best.id, anchor)
    } else {
      root.setSelectedIds([best.id], best.id, best.id)
    }
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

  function setOperationError(message, screenName) {
    root.operationBusy = false
    if (screenName !== undefined)
      root.operationScreen = String(screenName || "")
    root.operationMessage = root.plainText(message, 300) || "Desktop action failed."
    root.operationIsError = true
    root.operationUndoable = false
    root.operationId = ""
    receiptDismissTimer.stop()
  }

  function operationNoun(count) {
    return count === 1 ? "1 item" : count + " items"
  }

  function operationReceipt(data) {
    var results = Array.isArray(data.results) ? data.results.slice(0, root.maxOperationItems) : []
    var completed = 0
    for (var i = 0; i < results.length; i++)
      if (results[i] && results[i].status === "completed")
        completed++
    var total = results.length || (Array.isArray(data.sources) ? data.sources.length : 0)
    var noun = root.operationNoun(total || completed || 1)
    var destination = root.basename(data.destination)
    var command = String(data.command || root.operationCommand)
    var state = String(data.state || "")
    if (state === "partial")
      return completed + " of " + total + " items completed · Review the failed items"
    if (command === "copy")
      return "Copied " + noun + " to " + destination
    if (command === "move")
      return "Moved " + noun + " to " + destination
    if (command === "trash")
      return "Moved " + noun + " to Trash"
    if (command === "undo")
      return state === "undo-partial"
        ? "Undo completed only part of the operation · Review the failed items"
        : "Undid the last desktop move"
    return "Desktop action completed"
  }

  function applyOperationResult(raw, exitCode) {
    operationDeadline.stop()
    root.operationBusy = false
    var text = String(raw || "").trim()
    if (!text || text.length > root.maxOperationChars) {
      root.setOperationError(text.length > root.maxOperationChars
        ? "Desktop action returned too much data."
        : "Desktop actions are unavailable. The operation helper did not return a result.")
      return
    }
    try {
      var data = JSON.parse(text)
      if (!data || data.schemaVersion !== 1 || typeof data.ok !== "boolean") {
        root.setOperationError("Desktop action returned an invalid result.")
        return
      }
      var error = data.error && typeof data.error === "object"
        ? root.plainText(data.error.message, 260)
        : ""
      root.operationMessage = data.ok || data.state === "partial"
        ? root.operationReceipt(data)
        : (error || "Desktop action failed.")
      root.operationIsError = !data.ok
      root.operationId = data.undoable === true ? String(data.operationId || "").slice(0, 160) : ""
      root.operationUndoable = data.undoable === true && root.operationId !== ""
      if (!root.operationUndoable)
        receiptDismissTimer.restart()
      else
        receiptDismissTimer.stop()
      Qt.callLater(root.refresh)
      root.operationCommand = ""
    } catch (e) {
      console.warn("one-bit-bureau desktop: failed to parse operation result:", e)
      var fallback = root.plainText(root.operationErrorOutput, 260)
      root.setOperationError(fallback || "Desktop action returned an invalid result.")
      root.operationCommand = ""
    }
  }

  function runOperation(command, sources, destination, screenName) {
    if (operationProc.running || root.operationBusy) {
      root.operationMessage = "Another desktop action is still in progress."
      root.operationIsError = true
      return false
    }
    var verb = String(command || "")
    if (["copy", "move", "trash"].indexOf(verb) === -1) {
      root.setOperationError("That desktop action is not supported.", screenName)
      return false
    }
    var local = []
    var seen = ({})
    var incoming = Array.isArray(sources) ? sources : []
    for (var i = 0; i < incoming.length && local.length < root.maxOperationItems; i++) {
      var path = root.localPath(incoming[i])
      if (path && !seen[path]) {
        seen[path] = true
        local.push(path)
      }
    }
    if (local.length === 0) {
      root.setOperationError("Only local files can be used in desktop actions.", screenName)
      return false
    }
    var cmd = ["/usr/bin/python3", root.operationScript, verb]
    if (verb === "copy" || verb === "move") {
      var target = root.localPath(destination)
      if (!target) {
        root.setOperationError("The destination is not a local folder.", screenName)
        return false
      }
      cmd.push("--destination")
      cmd.push(target)
    }
    for (var j = 0; j < local.length; j++)
      cmd.push(local[j])
    root.operationOutput = ""
    root.operationErrorOutput = ""
    root.operationCommand = verb
    root.operationScreen = String(screenName || "")
    root.operationBusy = true
    root.operationMessage = root.operationNoun(local.length) + " -> "
      + (verb === "copy" ? "Copy" : verb === "move" ? "Move" : "Move to Trash")
      + " -> " + (verb === "trash" ? "Trash" : root.basename(destination))
    root.operationIsError = false
    root.operationUndoable = false
    root.operationId = ""
    operationProc.command = cmd
    operationProc.running = true
    operationDeadline.restart()
    return true
  }

  function undoLastOperation() {
    if (!root.operationUndoable || !root.operationId || operationProc.running)
      return
    root.operationOutput = ""
    root.operationErrorOutput = ""
    root.operationCommand = "undo"
    root.operationBusy = true
    root.operationUndoable = false
    operationProc.command = ["/usr/bin/python3", root.operationScript, "undo", root.operationId]
    operationProc.running = true
    operationDeadline.restart()
  }

  function dismissReceipt() {
    receiptDismissTimer.stop()
    root.operationMessage = ""
    root.operationIsError = false
    root.operationUndoable = false
    root.operationId = ""
    root.operationScreen = ""
  }

  function trashUrls(urls, screenName) {
    root.runOperation("trash", urls, "", screenName)
  }

  function trashItem(item, screenName) {
    if (!item || !item.path || root.isTrash(item)) return
    root.trashUrls(root.selectedPaths(item), screenName)
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
    root.runOperation(mode === "move" ? "move" : "copy", urls, root.desktopPath)
  }

  function dropMode(drop) {
    if (!drop) return "copy"
    if (drop.proposedAction === Qt.LinkAction) return "link"
    if (drop.proposedAction === Qt.MoveAction) return "move"
    return "copy"
  }

  function inspectorFallback(item, reason) {
    var subtitle = item && (item.kind === "folder" || item.isDir)
      ? "Folder"
      : item && item.kind === "launcher" ? "Application shortcut"
      : item && item.kind === "trash" ? "Trash"
      : "Desktop item"
    var facts = [
      { id: "kind", label: "Kind", value: subtitle },
      { id: "location", label: "Location", value: item ? root.plainText(item.path, 240) : "Unavailable" }
    ]
    if (reason)
      facts.push({ id: "metadata", label: "Metadata", value: root.plainText(reason, 220) })
    if (item && item.kind === "launcher")
      facts.push({ id: "trust", label: "Launcher trust", value: root.isUntrustedLauncher(item) ? "Confirmation required" : "Allowed" })
    return {
      kind: "desktop",
      id: item ? String(item.id || "") : "",
      name: item ? root.plainText(item.name) : "Missing desktop item",
      subtitle: subtitle,
      iconSource: item ? root.objectIconSource(item, root.isSelected(item)) : "",
      stale: !!reason,
      staleReason: reason ? root.plainText(reason, 220) : "",
      missing: !item,
      missingReason: item ? "" : "This desktop item is no longer available.",
      facts: facts,
      actions: [
        {
          id: "open",
          label: "Open",
          enabled: !!item && !root.isUntrustedLauncher(item),
          reason: item && root.isUntrustedLauncher(item) ? "Confirm launcher trust first." : item ? "" : "Item is missing."
        },
        {
          id: "showInFiles",
          label: "Show in Files",
          enabled: !!item && !!item.path,
          reason: item && item.path ? "" : "No local location is available."
        },
        {
          id: "moveToTrash",
          label: "Move to Trash",
          enabled: !!item && !root.isTrash(item),
          reason: item && root.isTrash(item) ? "Trash cannot be moved into itself." : item ? "" : "Item is missing.",
          destructive: true
        },
        {
          id: "trustAndOpen",
          label: "Trust and Open",
          enabled: !!item && root.isUntrustedLauncher(item),
          reason: item && root.isUntrustedLauncher(item) ? "" : "This item does not need launcher trust."
        }
      ]
    }
  }

  function inspectorPayload(item, meta, reason) {
    var payload = root.inspectorFallback(item, reason)
    var data = meta && typeof meta === "object" ? meta : ({})
    function fact(id, label, value) {
      var clean = root.plainText(value, 240)
      if (clean)
        payload.facts.push({ id: id, label: label, value: clean })
    }
    fact("size", "Size", data.sizeText !== undefined ? data.sizeText : data.size)
    fact("modified", "Modified", data.modifiedText || data.modified || data.modifiedTime)
    fact("contentType", "Content type", data.mimeType || data.mime || data.contentType)
    if (data.previewPolicy)
      fact("previewPolicy", "Preview", data.previewPolicy)
    return payload
  }

  function requestInspector(item, screenName) {
    if (!item || !item.id)
      return
    if (inspectProc.running) {
      root.inspectPendingId = ""
      root.inspectPendingScreen = ""
      inspectProc.running = false
    }
    root.inspectPendingId = String(item.id)
    root.inspectPendingScreen = String(screenName || "")
    root.inspectOutput = ""
    root.inspectErrorOutput = ""
    inspectProc.command = ["/usr/bin/python3", root.operationScript, "inspect", String(item.path || "")]
    inspectProc.running = true
    inspectDeadline.restart()
  }

  function publishInspector(payload, screenName) {
    root.inspectorSubject = payload
    root.inspectorScreen = String(screenName || "")
    root.inspectorOpen = true
    root.inspectRequested(payload, root.inspectorScreen)
  }

  function inspectDesktopItem(id, screenName) {
    var item = root.itemById(id)
    if (!item) {
      root.publishInspector(root.inspectorFallback(null, "This desktop item is no longer available."), screenName)
      return false
    }
    root.requestInspector(item, screenName)
    return true
  }

  function closeInspector() {
    inspectDeadline.stop()
    root.inspectorOpen = false
    root.inspectorSubject = null
    root.inspectorScreen = ""
    root.inspectPendingId = ""
    root.inspectPendingScreen = ""
    if (inspectProc.running)
      inspectProc.running = false
    root.inspectorCloseRequested()
  }

  function applyInspectResult(raw, exitCode) {
    inspectDeadline.stop()
    var item = root.itemById(root.inspectPendingId)
    if (!item) {
      root.publishInspector(root.inspectorFallback(null, "This desktop item is no longer available."), root.inspectPendingScreen)
      return
    }
    var text = String(raw || "").trim()
    if (!text || text.length > root.maxOperationChars) {
      root.publishInspector(root.inspectorFallback(item, "Detailed metadata is unavailable."), root.inspectPendingScreen)
      return
    }
    try {
      var data = JSON.parse(text)
      if (!data || data.schemaVersion !== 1 || data.command !== "inspect" || data.ok !== true) {
        var reason = data && data.error ? root.plainText(data.error.message, 220) : "Detailed metadata is unavailable."
        root.publishInspector(root.inspectorFallback(item, reason), root.inspectPendingScreen)
        return
      }
      root.publishInspector(root.inspectorPayload(item, data.item, ""), root.inspectPendingScreen)
    } catch (e) {
      root.publishInspector(root.inspectorFallback(item, "Detailed metadata is unavailable."), root.inspectPendingScreen)
    }
  }

  function performInspectorAction(actionId, context) {
    var action = String(actionId || "")
    var id = context && typeof context === "object" ? String(context.id || "") : String(context || "")
    var item = root.itemById(id)
    if (!item) {
      root.setOperationError("That desktop item is no longer available.", root.inspectorScreen)
      return false
    }
    if (action === "open") {
      root.openOrConfirm(item, root.inspectorScreen)
      return true
    }
    if (action === "showInFiles") {
      root.revealItem(item)
      return true
    }
    if (action === "moveToTrash" && !root.isTrash(item)) {
      root.trashUrls([item.path], root.inspectorScreen)
      return true
    }
    if (action === "trustAndOpen" && root.isUntrustedLauncher(item)) {
      root.trustAndOpen(item)
      return true
    }
    return false
  }

  function applyList(raw) {
    var text = String(raw || "").trim()
    if (!text) {
      root.statusMessage = "Desktop objects could not be refreshed."
      root.statusIsError = true
      return
    }
    if (text.length > root.maxListChars) {
      console.warn("one-bit-bureau desktop: index output exceeded resource ceiling")
      root.statusMessage = "Desktop objects could not be refreshed because the result was too large."
      root.statusIsError = true
      return
    }
    try {
      var data = JSON.parse(text)
      var errorMessage = root.plainText(data.error, 240)
      root.statusMessage = errorMessage
        ? "Desktop could not be read: " + errorMessage
        : data.truncated ? "Some desktop objects are not shown." : ""
      root.statusIsError = !!errorMessage
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
      // Prune disappeared objects from selection without changing the anchor
      // of a surviving range.
      root.setSelectedIds(root.selectedIds, root.selectedId, root.selectionAnchorId)
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
      console.warn("one-bit-bureau desktop: failed to parse index:", e)
      root.statusMessage = "Desktop objects could not be refreshed."
      root.statusIsError = true
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

  function setItemPositions(screenName, updates) {
    var next = JSON.parse(JSON.stringify(root.positions || {}))
    if (!next[screenName])
      next[screenName] = ({})
    var values = Array.isArray(updates) ? updates : []
    for (var i = 0; i < values.length && i < root.maxOperationItems; i++) {
      var update = values[i]
      if (!update || !root.itemById(update.id))
        continue
      next[screenName][String(update.id)] = {
        x: Math.round(Number(update.x) || 0),
        y: Math.round(Number(update.y) || 0)
      }
    }
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

  Process {
    id: operationProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.operationOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.operationErrorOutput = text
    }
    onExited: function(exitCode) {
      if (root.operationCommand !== "")
        root.applyOperationResult(root.operationOutput, exitCode)
    }
  }

  Timer {
    id: operationDeadline
    interval: 120000
    repeat: false
    onTriggered: {
      if (!operationProc.running)
        return
      root.operationCommand = ""
      operationProc.running = false
      root.setOperationError("Desktop action timed out. Check the destination before retrying.")
    }
  }

  Timer {
    id: receiptDismissTimer
    interval: 8000
    repeat: false
    onTriggered: {
      if (!root.operationUndoable && !root.operationBusy)
        root.dismissReceipt()
    }
  }

  Process {
    id: inspectProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.inspectOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.inspectErrorOutput = text
    }
    onExited: function(exitCode) {
      if (root.inspectPendingId !== "")
        root.applyInspectResult(root.inspectOutput, exitCode)
    }
  }

  Timer {
    id: inspectDeadline
    interval: 2500
    repeat: false
    onTriggered: {
      if (!inspectProc.running)
        return
      var item = root.itemById(root.inspectPendingId)
      var screenName = root.inspectPendingScreen
      root.inspectPendingId = ""
      root.inspectPendingScreen = ""
      inspectProc.running = false
      root.publishInspector(root.inspectorFallback(item, "Detailed metadata timed out."), screenName)
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
      WlrLayershell.namespace: "one-bit-bureau-desktop"
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
      property bool dragCanceled: false
      property string draggingItemId: ""
      property var dragItems: []
      property var dragOriginalPositions: ({})
      property string routeNoun: ""
      property string routeVerb: ""
      property string routeDestination: ""
      property string routeReason: ""
      property string routeTargetId: ""
      property var routeTarget: null
      property var currentRoute: null
      property bool routeValid: false
      property bool routeVisible: false
      property bool routeEligibilityResolved: false
      property bool routeExternal: false
      property string springOpenedTargetId: ""
      readonly property string routeText: !panel.routeVisible ? "" : panel.routeNoun
        + " -> " + (panel.routeValid ? panel.routeVerb : "Cannot: " + panel.routeReason)
        + " -> " + panel.routeDestination
      property int emptyClicks: 0
      property int trustFocusIndex: 0
      property int menuCursorIndex: -1
      property bool _initialized: false
      property var _knownIds: ({})

      function selectionNoun(items) {
        var count = items && items.length ? items.length : 0
        if (count === 1)
          return host.plainText(items[0].name, 80)
        return count + " items"
      }

      function pathItems(paths) {
        var values = []
        for (var i = 0; paths && i < paths.length && values.length < host.maxOperationItems; i++) {
          var path = host.localPath(paths[i])
          if (path)
            values.push({ id: "external-" + i, name: host.basename(path), path: path, kind: "external" })
        }
        return values
      }

      function resolveRoute(target, sources, mode, external) {
        var items = Array.isArray(sources) ? sources.slice(0, host.maxOperationItems) : []
        if (target && (target.kind === "folder" || target.isDir)) {
          var withoutTarget = []
          for (var sourceIndex = 0; sourceIndex < items.length; sourceIndex++)
            if (String(items[sourceIndex].id || "") !== String(target.id || ""))
              withoutTarget.push(items[sourceIndex])
          items = withoutTarget
        }
        var noun = panel.selectionNoun(items)
        var destination = target ? host.plainText(target.name, 80) : "Desktop"
        var verb = external ? (mode === "move" ? "Move" : "Copy") : "Arrange"
        var valid = items.length > 0
        var reason = valid ? "" : "No local items"
        if (mode === "link") {
          valid = false
          reason = "Links are not supported"
        } else if (target && host.isTrash(target)) {
          verb = "Move to Trash"
          destination = "Trash"
          for (var i = 0; i < items.length; i++) {
            if (host.isTrash(items[i])) {
              valid = false
              reason = "Trash cannot contain itself"
              break
            }
          }
        } else if (target && (target.kind === "folder" || target.isDir)) {
          verb = external ? (mode === "move" ? "Move" : "Copy") : "Move"
          destination = host.plainText(target.name, 80)
          var targetPath = host.localPath(target.path)
          if (!targetPath) {
            valid = false
            reason = "Folder is not local"
          }
          for (var j = 0; valid && j < items.length; j++) {
            if (host.localPath(items[j].path) === targetPath) {
              valid = false
              reason = "Folder cannot contain itself"
            }
          }
        } else if (target) {
          valid = false
          verb = ""
          reason = target.kind === "launcher"
            ? "Applications do not accept desktop files here"
            : "Target does not accept files"
        }
        return {
          noun: noun,
          verb: verb,
          destination: destination,
          reason: reason,
          valid: valid,
          target: target,
          targetId: target ? String(target.id || "") : "",
          sources: items,
          mode: mode,
          external: !!external,
          resolved: true
        }
      }

      function applyRoute(route) {
        springOpenTimer.stop()
        if (panel.routeTargetId !== route.targetId)
          panel.springOpenedTargetId = ""
        panel.routeNoun = route.noun
        panel.routeVerb = route.verb
        panel.routeDestination = route.destination
        panel.routeReason = route.reason
        panel.routeValid = route.valid
        panel.routeTarget = route.target
        panel.routeTargetId = route.targetId
        panel.routeExternal = route.external
        panel.currentRoute = route
        panel.routeEligibilityResolved = route.resolved === true
        panel.routeVisible = true
        host.publishRouteState(panel.screenName, true, route.valid, route.reason, panel.routeText)
        if (panel.routeEligibilityResolved && panel.routeValid && panel.routeTarget
            && panel.springOpenedTargetId !== panel.routeTargetId
            && (panel.routeTarget.kind === "folder" || panel.routeTarget.isDir))
          springOpenTimer.restart()
      }

      function clearRoute() {
        host.clearRouteState(panel.screenName)
        springOpenTimer.stop()
        panel.routeNoun = ""
        panel.routeVerb = ""
        panel.routeDestination = ""
        panel.routeReason = ""
        panel.routeTargetId = ""
        panel.routeTarget = null
        panel.currentRoute = null
        panel.routeValid = false
        panel.routeVisible = false
        panel.routeEligibilityResolved = false
        panel.routeExternal = false
        panel.springOpenedTargetId = ""
      }

      function cancelRoute() {
        panel.dragCanceled = true
        panel.clearRoute()
      }

      function updateInternalRoute(x, y, exceptId) {
        var target = panel.itemAt(x, y, exceptId)
        panel.applyRoute(panel.resolveRoute(target, panel.dragItems, "move", false))
      }

      function updateExternalRoute(drop) {
        var urls = []
        if (drop && drop.urls)
          for (var i = 0; i < drop.urls.length && urls.length < host.maxOperationItems; i++)
            urls.push(String(drop.urls[i]))
        var items = panel.pathItems(urls)
        var target = panel.itemAt(drop ? drop.x : -1, drop ? drop.y : -1, "")
        panel.applyRoute(panel.resolveRoute(target, items, host.dropMode(drop), true))
      }

      function executeRoute(route, fallbackItem) {
        if (!route || !route.valid)
          return false
        var paths = []
        var items = Array.isArray(route.sources) ? route.sources : []
        for (var i = 0; i < items.length; i++) {
          var path = host.localPath(items[i].path)
          if (path)
            paths.push(path)
        }
        if (route.target && host.isTrash(route.target))
          return host.runOperation("trash", paths, "", panel.screenName)
        if (route.target && (route.target.kind === "folder" || route.target.isDir))
          return host.runOperation(route.external && route.mode === "copy" ? "copy" : "move", paths, route.target.path, panel.screenName)
        if (route.external)
          return host.runOperation(route.mode === "move" ? "move" : "copy", paths, host.desktopPath, panel.screenName)
        return false
      }

      Timer {
        id: springOpenTimer
        // Leave enough dwell time to read the route slip and release onto the
        // folder. A shorter delay made deliberate drops feel like accidental
        // folder launches and could hide the route confirmation itself.
        interval: 1800
        repeat: false
        onTriggered: {
          // Eligibility is deliberately resolved before the timer begins.
          // Re-check identity because folder state can disappear mid-drag.
          if (!panel.routeVisible || !panel.routeEligibilityResolved || !panel.routeValid)
            return
          var target = host.itemById(panel.routeTargetId)
          if (target && (target.kind === "folder" || target.isDir)) {
            panel.springOpenedTargetId = panel.routeTargetId
            host.openItem(target)
          }
        }
      }

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
        menuCursorIndex = -1
      }

      function firstEnabledMenuIndex(fromEnd) {
        var entries = panel.menuEntries
        if (!entries || entries.length === 0)
          return -1
        if (fromEnd) {
          for (var i = entries.length - 1; i >= 0; i--)
            if (entries[i].enabled !== false)
              return i
        } else {
          for (var j = 0; j < entries.length; j++)
            if (entries[j].enabled !== false)
              return j
        }
        return -1
      }

      function resetMenuCursor(fromEnd) {
        panel.menuCursorIndex = panel.firstEnabledMenuIndex(!!fromEnd)
      }

      function moveMenuCursor(delta) {
        var entries = panel.menuEntries
        if (!entries || entries.length === 0)
          return
        var start = panel.menuCursorIndex
        if (start < 0 || start >= entries.length) {
          panel.resetMenuCursor(delta < 0)
          return
        }
        for (var step = 1; step <= entries.length; step++) {
          var candidate = (start + delta * step) % entries.length
          if (candidate < 0)
            candidate += entries.length
          if (entries[candidate].enabled !== false) {
            panel.menuCursorIndex = candidate
            return
          }
        }
      }

      function activateMenuCursor() {
        var entries = panel.menuEntries
        var index = panel.menuCursorIndex
        if (!entries || index < 0 || index >= entries.length)
          return
        var entry = entries[index]
        if (entry.enabled === false)
          return
        menuBox.activateMenu(String(entry.action || ""))
      }

      function selectedItem() {
        for (var i = 0; i < host.items.length; i++)
          if (host.items[i].id === host.selectedId)
            return host.items[i]
        return null
      }

      function openEmptyMenu(mouse) {
        menuKind = "empty"
        menuItem = null
        menuX = mouse.x
        menuY = mouse.y
        panel.resetMenuCursor(false)
      }

      function openItemMenu(item, iconItem, mouse) {
        var p = contentItem.mapFromItem(iconItem, mouse.x, mouse.y)
        panel.openItemMenuAt(item, p.x, p.y)
      }

      function openItemMenuAt(item, x, y) {
        menuKind = "item"
        menuItem = item
        menuX = x
        menuY = y
        panel.resetMenuCursor(false)
      }

      function openKeyboardContextMenu() {
        var item = panel.selectedItem()
        if (item) {
          for (var i = 0; i < host.items.length; i++) {
            if (host.items[i].id === item.id) {
              var p = panel.posFor(item, i)
              panel.openItemMenuAt(item, p.x + Math.round(host.cellW / 2), p.y + Math.round(host.cellH / 2))
              return
            }
          }
        }
        menuKind = "empty"
        menuItem = null
        menuX = panel.padLeft + 12
        menuY = panel.padTop + 12
        panel.resetMenuCursor(false)
      }

      readonly property var menuEntries: {
        if (menuKind === "item") {
          var selected = host.selectedItems(null)
          var targetSelected = menuItem ? host.isSelected(menuItem) : false
          var canRouteHere = menuItem && (menuItem.kind === "folder" || menuItem.isDir)
            && selected.length > (targetSelected ? 1 : 0)
          var canTrashSelection = menuItem && host.isTrash(menuItem) && selected.length > 0
          if (host.isTrash(menuItem)) {
            var trashEntries = [
              { action: "open", label: "Open Trash", enabled: true },
              { action: "inspect", label: "Get Info", enabled: true },
              { action: "trash-selected", label: "Move Selected to Trash", enabled: canTrashSelection },
              { action: "files", label: "Show in Files", enabled: true },
              { action: "trash", label: "Move to Trash", enabled: false }
            ]
            return trashEntries
          }
          if (menuItem && menuItem.kind === "launcher")
            return [
              { action: "open", label: "Open", enabled: !host.isUntrustedLauncher(menuItem) },
              { action: "trust-open", label: "Trust and Open", enabled: host.isUntrustedLauncher(menuItem) },
              { action: "trust", label: "Allow Launching", enabled: host.isUntrustedLauncher(menuItem) },
              { action: "inspect", label: "Get Info", enabled: true },
              { action: "files", label: "Show in Files", enabled: true },
              { action: "trash", label: "Move to Trash", enabled: true }
            ]
          var entries = [
            { action: "open", label: "Open", enabled: true },
            { action: "inspect", label: "Get Info", enabled: true },
            { action: "files", label: "Show in Files", enabled: true },
            { action: "trash", label: "Move to Trash", enabled: true }
          ]
          if (menuItem && (menuItem.kind === "folder" || menuItem.isDir)) {
            entries.splice(2, 0,
              { action: "move-here", label: "Move Selected Here", enabled: canRouteHere },
              { action: "copy-here", label: "Copy Selected Here", enabled: canRouteHere })
          }
          return entries
        }
        if (menuKind === "empty")
          return [
            { action: "folder", label: "New Folder", enabled: true },
            { action: "shortcut", label: "New Shortcut…", enabled: true },
            { action: "pin", label: "Pin Application…", enabled: true },
            { action: "addfiles", label: "Add Files…", enabled: true },
            { action: "files", label: "Open Desktop Folder", enabled: true },
            { action: "refresh", label: "Refresh", enabled: true }
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
          if (event.modifiers & Qt.MetaModifier) {
            event.accepted = false
            return
          }
          if (host.pendingTrust) {
            if (event.key === Qt.Key_Escape
                || event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter) {
              // The safe default remains Cancel. Enter never trusts code.
              host.clearTrustPrompt()
              panel.closeMenu()
            } else if (event.key === Qt.Key_Tab
                       || event.key === Qt.Key_Backtab
                       || event.key === Qt.Key_Left
                       || event.key === Qt.Key_Right
                       || event.key === Qt.Key_Up
                       || event.key === Qt.Key_Down) {
              panel.trustFocusIndex = panel.trustFocusIndex === 0 ? 1 : 0
            } else if (event.key === Qt.Key_Space) {
              if (panel.trustFocusIndex === 0)
                host.clearTrustPrompt()
              else
                host.trustAndOpen(host.pendingTrust)
            } else {
              return
            }
            event.accepted = true
            return
          }
          var contextMenuKey = event.key === Qt.Key_Menu
            || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))
          if (panel.menuKind !== "") {
            if (event.key === Qt.Key_Escape) {
              panel.closeMenu()
            } else if (event.key === Qt.Key_Home) {
              panel.resetMenuCursor(false)
            } else if (event.key === Qt.Key_End) {
              panel.resetMenuCursor(true)
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left
                       || event.key === Qt.Key_Backtab
                       || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
              panel.moveMenuCursor(-1)
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right
                       || event.key === Qt.Key_Tab) {
              panel.moveMenuCursor(1)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                       || event.key === Qt.Key_Space) {
              panel.activateMenuCursor()
            } else if (contextMenuKey) {
              // Leave an already-open context menu stable.
            } else {
              return
            }
            event.accepted = true
            return
          }
          if (contextMenuKey) {
            panel.openKeyboardContextMenu()
            event.accepted = true
          } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)
                     && host.operationUndoable) {
            host.undoLastOperation()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (panel.routeVisible)
              panel.cancelRoute()
            else if (host.operationMessage !== "")
              host.dismissReceipt()
            else
              host.clearSelection()
            event.accepted = true
          } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            host.selectAll(panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Space && (event.modifiers & Qt.ControlModifier)) {
            var cursorItem = host.itemById(host.selectedId)
            if (cursorItem)
              host.selectItem(cursorItem, Qt.ControlModifier, panel.screenName)
            event.accepted = true
          } else if ((event.key === Qt.Key_I && (event.modifiers & Qt.ControlModifier))
                     || (event.key === Qt.Key_Return && (event.modifiers & Qt.AltModifier))) {
            var infoItem = host.itemById(host.selectedId)
            if (infoItem)
              host.requestInspector(infoItem, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Delete && host.selectedIds.length > 0) {
            host.trashUrls(host.selectedPaths(null), panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var openItems = host.selectedItems(null)
            for (var j = 0; j < openItems.length; j++) {
              host.openOrConfirm(openItems[j], panel.screenName)
              if (host.pendingTrust)
                break
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            host.moveSelection(event.modifiers & Qt.ShiftModifier ? -1 : 1,
                               panel.screenName, false)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            host.moveSelection(-1, panel.screenName, false)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            host.moveSelectionSpatial(-1, 0, panel.screenName,
                                      !!(event.modifiers & Qt.ShiftModifier))
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            host.moveSelectionSpatial(1, 0, panel.screenName,
                                      !!(event.modifiers & Qt.ShiftModifier))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            host.moveSelectionSpatial(0, -1, panel.screenName,
                                      !!(event.modifiers & Qt.ShiftModifier))
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            host.moveSelectionSpatial(0, 1, panel.screenName,
                                      !!(event.modifiers & Qt.ShiftModifier))
            event.accepted = true
          }
        }
        onClicked: function(mouse) {
          host.clearSelection()
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
        onEntered: function(drop) {
          panel.dropping = true
          panel.updateExternalRoute(drop)
        }
        onPositionChanged: function(drop) {
          panel.updateExternalRoute(drop)
        }
        onExited: {
          panel.dropping = false
          if (panel.routeExternal)
            panel.clearRoute()
        }
        onDropped: function(drop) {
          panel.dropping = false
          panel.updateExternalRoute(drop)
          var route = panel.currentRoute
          if (route && route.valid) {
            drop.acceptProposedAction()
            panel.executeRoute(route, null)
          }
          panel.clearRoute()
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: panel.dropping
        color: "transparent"
        border.width: 2
        border.color: Color.foreground
        z: 5
      }

      Rectangle {
        id: routeSlip
        visible: panel.routeVisible
        z: 18
        width: Math.min(620, Math.max(260, routeLabel.implicitWidth + 28))
        height: routeLabel.implicitHeight + 20
        x: Math.round(panel.width / 2 - width / 2)
        // The dock is a separate layer-shell surface and can paint above this
        // desktop layer. Reserve its visual footprint so the signature route
        // sentence never sits behind dock icons.
        y: Math.max(panel.padTop + 8, panel.height - height - Math.max(host.padBottom, 112))
        radius: 0
        color: Color.popups.background
        border.width: 2
        border.color: panel.routeValid ? Color.popups.border : Color.urgent
        Accessible.role: panel.routeValid ? Accessible.StaticText : Accessible.AlertMessage
        Accessible.name: routeLabel.text
        Accessible.description: panel.routeValid
          ? "Resolved desktop route. Release to perform it or press Escape to cancel."
          : "Invalid desktop route. Press Escape to cancel."

        Text {
          id: routeLabel
          anchors.centerIn: parent
          width: Math.min(580, implicitWidth)
          text: panel.routeText
          textFormat: Text.PlainText
          color: Color.popups.text
          font.pixelSize: 13
          font.family: Style.fontFamily
          font.bold: true
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }

        Behavior on opacity {
          enabled: !host.reducedMotion
          NumberAnimation { duration: 90 }
        }
      }

      Rectangle {
        id: statusBox
        visible: host.statusMessage !== ""
          && Quickshell.screens.length > 0
          && panel.modelData === Quickshell.screens[0]
        z: 19
        width: Math.min(420, Math.max(0, panel.width - 48))
        height: statusText.implicitHeight + 20
        x: Math.round(panel.width / 2 - width / 2)
        y: panel.padTop
        radius: 0
        color: Color.popups.background
        border.width: 2
        border.color: host.statusIsError ? Color.urgent : Color.popups.border
        Accessible.role: host.statusIsError ? Accessible.AlertMessage : Accessible.StaticText
        Accessible.name: statusText.text
        Accessible.description: host.statusIsError
          ? "Desktop service error"
          : "Desktop service status"

        Text {
          id: statusText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 10
          text: host.statusMessage
          textFormat: Text.PlainText
          color: Color.popups.text
          font.pixelSize: 13
          font.family: Style.fontFamily
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
      }

      Rectangle {
        id: receiptBox
        visible: host.operationMessage !== ""
          && Quickshell.screens.length > 0
          && (host.operationScreen !== ""
            ? panel.screenName === host.operationScreen
            : panel.modelData === Quickshell.screens[0])
        z: 19
        width: Math.min(540, Math.max(280, receiptContent.implicitWidth + 24))
        height: receiptContent.implicitHeight + 20
        x: Math.round(panel.width / 2 - width / 2)
        y: panel.padTop + (statusBox.visible ? statusBox.height + 8 : 0)
        radius: 0
        color: Color.popups.background
        border.width: 2
        border.color: host.operationIsError ? Color.urgent : Color.popups.border
        Accessible.role: host.operationIsError ? Accessible.AlertMessage : Accessible.StaticText
        Accessible.name: receiptMessage.text
        Accessible.description: host.operationUndoable
          ? "Desktop action completed and can be undone."
          : host.operationIsError ? "Desktop action failed." : "Desktop action receipt."

        Row {
          id: receiptContent
          anchors.centerIn: parent
          spacing: 10

          Text {
            id: receiptMessage
            width: Math.min(360, implicitWidth)
            anchors.verticalCenter: parent.verticalCenter
            text: host.operationMessage
            textFormat: Text.PlainText
            color: Color.popups.text
            opacity: host.operationBusy ? 0.72 : 1
            font.pixelSize: 13
            font.family: Style.fontFamily
            wrapMode: Text.WordWrap
          }

          Rectangle {
            id: undoButton
            visible: host.operationUndoable
            enabled: visible && !host.operationBusy
            width: Math.max(52, undoLabel.implicitWidth + 20)
            height: 44
            color: undoMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
            border.width: 1
            border.color: Color.popups.border
            Accessible.role: Accessible.Button
            Accessible.name: "Undo desktop action"
            Accessible.description: "Restore the files moved by the last completed operation."
            Accessible.focusable: true
            Accessible.onPressAction: host.undoLastOperation()

            Text {
              id: undoLabel
              anchors.centerIn: parent
              text: "Undo"
              textFormat: Text.PlainText
              color: undoMouse.containsMouse ? Color.menu.selectedText : Color.popups.text
              font.pixelSize: 13
              font.family: Style.fontFamily
            }

            MouseArea {
              id: undoMouse
              anchors.fill: parent
              hoverEnabled: true
              enabled: parent.enabled
              onClicked: host.undoLastOperation()
            }
          }

          Rectangle {
            id: dismissReceiptButton
            visible: !host.operationBusy
            width: 44
            height: 44
            color: dismissReceiptMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
            border.width: 1
            border.color: Color.popups.border
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss desktop receipt"
            Accessible.description: "Hide this completion or error receipt."
            Accessible.focusable: true
            Accessible.onPressAction: host.dismissReceipt()

            Text {
              anchors.centerIn: parent
              text: "×"
              textFormat: Text.PlainText
              color: dismissReceiptMouse.containsMouse ? Color.menu.selectedText : Color.popups.text
              font.pixelSize: 16
              font.family: Style.fontFamily
            }

            MouseArea {
              id: dismissReceiptMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: host.dismissReceipt()
            }
          }
        }

        Behavior on opacity {
          enabled: !host.reducedMotion
          NumberAnimation { duration: 100 }
        }
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
          property bool preservedMultiSelectionOnPress: false
          readonly property bool selected: panel.host.isSelected(iconRoot.modelData)
          readonly property bool photoPreview: panel.host.hasImagePreview(iconRoot.modelData)
          readonly property bool routeTargeted: panel.routeVisible
            && panel.routeTargetId === String(iconRoot.modelData.id || "")
          Accessible.role: Accessible.ListItem
          Accessible.name: panel.host.plainText(iconRoot.modelData.name)
          Accessible.description: panel.host.accessibleDescription(iconRoot.modelData)
          Accessible.selectable: true
          Accessible.selected: iconRoot.selected
          Accessible.focusable: true
          Accessible.focused: panel.host.selectedId === iconRoot.modelData.id && emptyMouse.activeFocus
          Accessible.onPressAction: panel.host.openOrConfirm(iconRoot.modelData, panel.screenName)
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
            radius: 0
            color: iconRoot.routeTargeted && panel.routeValid ? Color.menu.background : "transparent"
            border.width: iconRoot.routeTargeted ? 2 : iconHover.hovered && !iconRoot.selected ? 1 : 0
            border.color: iconRoot.routeTargeted && !panel.routeValid ? Color.urgent : Color.foreground
          }

          HoverHandler { id: iconHover }

          Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            Item {
              width: panel.host.iconSize + 8
              height: panel.host.iconSize + 8
              anchors.horizontalCenter: parent.horizontalCenter
              clip: true

              Rectangle {
                id: objectEnclosure
                anchors.fill: parent
                radius: 0
                color: iconRoot.selected && (panel.host.usesCategoryIcon(iconRoot.modelData) || iconRoot.photoPreview)
                  ? Color.foreground
                  : iconRoot.photoPreview ? Color.menu.background : "transparent"
                border.width: iconRoot.selected ? 2 : iconRoot.photoPreview ? 1 : 0
                border.color: Color.foreground
              }

              Rectangle {
                visible: iconMouse.drag.active && panel.dragItems.length > 1
                z: 3
                anchors.right: parent.right
                anchors.top: parent.top
                width: 24
                height: 24
                radius: 0
                color: Color.foreground
                border.width: 1
                border.color: Color.menu.background
                Accessible.role: Accessible.StaticText
                Accessible.name: panel.dragItems.length + " selected items"

                Text {
                  anchors.centerIn: parent
                  text: String(Math.min(panel.dragItems.length, panel.host.maxOperationItems))
                  textFormat: Text.PlainText
                  color: Color.menu.selectedText
                  font.pixelSize: 12
                  font.bold: true
                  font.family: Style.fontFamily
                }
              }

              Image {
                id: desktopIcon
                anchors.centerIn: parent
                // The source file remains untouched and opens in full color. Its
                // desktop thumbnail stays grayscale in every interaction state.
                width: panel.host.iconSize
                height: panel.host.iconSize
                source: panel.host.objectIconSource(iconRoot.modelData, iconRoot.selected)
                fillMode: panel.host.hasImagePreview(iconRoot.modelData)
                  ? Image.PreserveAspectCrop
                  : Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: panel.host.hasImagePreview(iconRoot.modelData)
                  || !panel.host.usesCategoryIcon(iconRoot.modelData)
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                layer.enabled: iconRoot.photoPreview
                layer.effect: MultiEffect {
                  saturation: -1.0
                }
              }

              Rectangle {
                visible: panel.host.isUntrustedLauncher(iconRoot.modelData)
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 20
                height: 20
                radius: 0
                color: Color.urgent
                border.width: 1
                border.color: Color.foreground

                Text {
                  anchors.centerIn: parent
                  text: "!"
                  textFormat: Text.PlainText
                  color: Color.menu.selectedText
                  font.pixelSize: 13
                  font.bold: true
                  font.family: Style.fontFamily
                }
              }
            }

            Rectangle {
              id: nameRail
              width: parent.width
              height: Math.min(44, desktopLabel.implicitHeight + 6)
              radius: 0
              color: iconRoot.selected ? Color.foreground : Color.menu.background
              border.width: 1
              border.color: Color.foreground

              Text {
                id: desktopLabel
                anchors.fill: parent
                anchors.margins: 3
                text: panel.host.plainText(iconRoot.modelData.name)
                textFormat: Text.PlainText
                color: iconRoot.selected ? Color.menu.selectedText : Color.foreground
                font.pixelSize: 14
                font.family: Style.fontFamily
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                horizontalAlignment: Text.AlignHCenter
              }
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
            drag.target: panel.host.isTrash(iconRoot.modelData) ? null : iconRoot
            drag.axis: Drag.XAndYAxis
            // Drop routing is calculated from the object's actual bounds.
            // Exact pointer tracking keeps a brisk drag from lagging one cell
            // behind and resolving against the wrong desktop object.
            drag.smoothed: false
            drag.threshold: 36
            drag.minimumX: 0
            drag.minimumY: 0
            drag.maximumX: Math.max(0, panel.width - iconRoot.width)
            drag.maximumY: Math.max(0, panel.height - iconRoot.height)
            onPressed: function(mouse) {
              iconRoot.pressX = iconRoot.x
              iconRoot.pressY = iconRoot.y
              iconRoot.preservedMultiSelectionOnPress = mouse.button === Qt.LeftButton
                && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                && panel.host.isSelected(iconRoot.modelData)
                && panel.host.selectedIds.length > 1
              var routingTarget = mouse.button === Qt.RightButton
                && (panel.host.isTrash(iconRoot.modelData)
                    || iconRoot.modelData.kind === "folder" || iconRoot.modelData.isDir)
                && panel.host.selectedIds.length > 0
                && !panel.host.isSelected(iconRoot.modelData)
              if (!routingTarget && !iconRoot.preservedMultiSelectionOnPress)
                panel.host.selectItem(iconRoot.modelData, mouse.modifiers, panel.screenName)
              panel.dragCanceled = false
              panel.draggingItemId = String(iconRoot.modelData.id || "")
              panel.dragItems = panel.host.selectedItems(iconRoot.modelData)
              var originals = ({})
              for (var i = 0; i < panel.dragItems.length; i++) {
                var source = panel.dragItems[i]
                for (var j = 0; j < panel.host.items.length; j++) {
                  if (panel.host.items[j].id === source.id) {
                    var sourcePos = panel.posFor(source, j)
                    originals[source.id] = { x: sourcePos.x, y: sourcePos.y }
                    break
                  }
                }
              }
              panel.dragOriginalPositions = originals
              emptyMouse.forceActiveFocus()
            }
            onPositionChanged: function(mouse) {
              if (!iconMouse.drag.active || panel.host.isTrash(iconRoot.modelData))
                return
              panel.updateInternalRoute(
                iconRoot.x + iconRoot.width / 2,
                iconRoot.y + iconRoot.height / 2,
                iconRoot.modelData.id
              )
            }
            onReleased: function(mouse) {
              if (!iconMouse.drag.active) {
                if (iconRoot.preservedMultiSelectionOnPress)
                  panel.host.selectItem(iconRoot.modelData, Qt.NoModifier, panel.screenName)
                iconRoot.preservedMultiSelectionOnPress = false
                panel.clearRoute()
                return
              }
              panel.updateInternalRoute(
                iconRoot.x + iconRoot.width / 2,
                iconRoot.y + iconRoot.height / 2,
                iconRoot.modelData.id
              )
              var route = panel.currentRoute
              var original = panel.dragOriginalPositions[iconRoot.modelData.id]
              if (panel.dragCanceled) {
                if (original) {
                  iconRoot.x = original.x
                  iconRoot.y = original.y
                }
                panel.clearRoute()
                iconRoot.preservedMultiSelectionOnPress = false
                return
              }
              if (route && route.target) {
                if (route.valid)
                  panel.executeRoute(route, iconRoot.modelData)
                else
                  panel.host.setOperationError(route.noun + " cannot be routed: " + route.reason + ".", panel.screenName)
                if (original) {
                  iconRoot.x = original.x
                  iconRoot.y = original.y
                }
                panel.clearRoute()
                iconRoot.preservedMultiSelectionOnPress = false
                return
              }
              var snapped = panel.snap(iconRoot.x, iconRoot.y)
              var deltaX = original ? snapped.x - original.x : 0
              var deltaY = original ? snapped.y - original.y : 0
              var updates = []
              for (var i = 0; i < panel.dragItems.length; i++) {
                var source = panel.dragItems[i]
                var sourceOriginal = panel.dragOriginalPositions[source.id]
                if (!sourceOriginal)
                  continue
                var next = panel.snap(sourceOriginal.x + deltaX, sourceOriginal.y + deltaY)
                updates.push({ id: source.id, x: next.x, y: next.y })
              }
              panel.host.setItemPositions(panel.screenName, updates)
              iconRoot.x = snapped.x
              iconRoot.y = snapped.y
              panel.clearRoute()
              iconRoot.preservedMultiSelectionOnPress = false
            }
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) {
                panel.openItemMenu(iconRoot.modelData, iconRoot, mouse)
                return
              }
              if (iconMouse.drag.active) return
              if (Math.abs(iconRoot.x - iconRoot.pressX) > 8 || Math.abs(iconRoot.y - iconRoot.pressY) > 8)
                return
              panel.closeMenu()
            }
            onDoubleClicked: function(mouse) {
              if (mouse.button !== Qt.LeftButton || iconMouse.drag.active)
                return
              panel.host.openOrConfirm(iconRoot.modelData, panel.screenName)
            }
          }

          DropArea {
            anchors.fill: parent
            z: 3
            enabled: panel.host.isTrash(iconRoot.modelData)
              || iconRoot.modelData.kind === "folder" || iconRoot.modelData.isDir
            keys: ["text/uri-list"]
            onEntered: function(drop) {
              panel.dropping = true
              var urls = []
              if (drop.urls)
                for (var i = 0; i < drop.urls.length && urls.length < panel.host.maxOperationItems; i++)
                  urls.push(String(drop.urls[i]))
              panel.applyRoute(panel.resolveRoute(iconRoot.modelData, panel.pathItems(urls), panel.host.dropMode(drop), true))
            }
            onPositionChanged: function(drop) {
              var urls = []
              if (drop.urls)
                for (var i = 0; i < drop.urls.length && urls.length < panel.host.maxOperationItems; i++)
                  urls.push(String(drop.urls[i]))
              panel.applyRoute(panel.resolveRoute(iconRoot.modelData, panel.pathItems(urls), panel.host.dropMode(drop), true))
            }
            onExited: {
              panel.dropping = false
              if (panel.routeExternal)
                panel.clearRoute()
            }
            onDropped: function(drop) {
              panel.dropping = false
              var urls = []
              if (drop.urls)
                for (var i = 0; i < drop.urls.length && urls.length < panel.host.maxOperationItems; i++)
                  urls.push(String(drop.urls[i]))
              panel.applyRoute(panel.resolveRoute(iconRoot.modelData, panel.pathItems(urls), panel.host.dropMode(drop), true))
              var route = panel.currentRoute
              if (route && route.valid) {
                drop.acceptProposedAction()
                panel.executeRoute(route, null)
              }
              panel.clearRoute()
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
        radius: 0
        color: Color.popups.background
        border.width: 2
        border.color: Color.popups.border
        x: Math.min(Math.max(8, menuX), Math.max(8, panel.width - width - 8))
        y: Math.min(Math.max(8, menuY), Math.max(8, panel.height - height - 8))

        // Bind plugin state onto this item so menu JS never needs the `panel` id.
        property var pluginHost: host
        property var currentItem: menuItem
        property string currentScreen: panel.screenName
        property int closeTick: 0
        property int cursorIndex: panel.menuCursorIndex
        Accessible.role: Accessible.PopupMenu
        Accessible.name: currentItem
          ? "Commands for " + pluginHost.plainText(currentItem.name)
          : "Desktop commands"
        Accessible.description: "Use the arrow keys to choose a command. Enter or Space activates it. Escape closes the menu."
        Accessible.focusable: true
        Accessible.focused: visible && emptyMouse.activeFocus

        function setCursorIndex(index) {
          panel.menuCursorIndex = index
        }

        function activateMenu(action) {
          var item = currentItem
          var plugin = pluginHost
          var screenName = currentScreen
          closeTick += 1
          if (!plugin)
            return
          if (action === "open")
            plugin.openOrConfirm(item, screenName)
          else if (action === "inspect")
            plugin.requestInspector(item, screenName)
          else if (action === "trust")
            plugin.allowLaunching(item)
          else if (action === "trust-open")
            plugin.trustAndOpen(item)
          else if (action === "trash")
            plugin.trashItem(item, screenName)
          else if (action === "trash-selected")
            plugin.trashUrls(plugin.selectedPaths(null), screenName)
          else if (action === "move-here")
            plugin.runOperation("move", plugin.selectedPathsExcept(item), item.path, screenName)
          else if (action === "copy-here")
            plugin.runOperation("copy", plugin.selectedPathsExcept(item), item.path, screenName)
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
              id: menuRow
              required property var modelData
              required property int index
              readonly property bool rowEnabled: modelData.enabled !== false
              readonly property bool keyboardCurrent: index === menuBox.cursorIndex
              width: menuCol.width
              height: 44
              enabled: rowEnabled
              radius: 0
              color: rowEnabled && (rowMouse.containsMouse || keyboardCurrent)
                ? Color.menu.selectedBackground
                : "transparent"
              Accessible.role: Accessible.MenuItem
              Accessible.name: String(modelData.label || "")
              Accessible.description: rowEnabled ? "Activate command" : "Unavailable command"
              Accessible.focusable: rowEnabled
              Accessible.focused: keyboardCurrent
              Accessible.selected: keyboardCurrent
              Accessible.onPressAction: menuRow.activateRow()

              function activateRow() {
                if (!menuRow.rowEnabled)
                  return
                menuBox.activateMenu(String(menuRow.modelData.action || ""))
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                text: String(modelData.label || "")
                textFormat: Text.PlainText
                color: parent.rowEnabled && (rowMouse.containsMouse || parent.keyboardCurrent)
                  ? Color.menu.selectedText
                  : Color.popups.text
                opacity: parent.rowEnabled ? 1 : 0.5
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: parent.rowEnabled
                onEntered: menuBox.setCursorIndex(menuRow.index)
                onClicked: function(mouse) {
                  menuRow.activateRow()
                }
              }
            }
          }
        }
      }

      Connections {
        target: menuBox
        function onCloseTickChanged() {
          panel.closeMenu()
        }
      }

      Connections {
        target: host
        function onItemsChanged() {
          panel.maybeRepack()
        }
        function onPendingTrustChanged() {
          panel.trustFocusIndex = 0
          if (host.pendingTrust)
            emptyMouse.forceActiveFocus()
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
        radius: 0
        color: Color.popups.background
        border.width: 2
        border.color: Color.popups.border
        Accessible.role: Accessible.Dialog
        Accessible.name: "Untrusted launcher"
        Accessible.description: trustMessage.text
        Accessible.focusable: true
        Accessible.focused: visible && emptyMouse.activeFocus
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
            Accessible.role: Accessible.Heading
            Accessible.name: text
          }

          Text {
            id: trustMessage
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
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
          }

          Row {
            anchors.right: parent.right
            spacing: 8

            Rectangle {
              id: cancelButton
              readonly property bool keyboardFocus: host.pendingTrust && panel.trustFocusIndex === 0
              width: Math.max(44, cancelLabel.implicitWidth + 20)
              height: 44
              radius: 0
              color: cancelMouse.containsMouse || keyboardFocus ? Color.menu.selectedBackground : "transparent"
              border.width: 2
              border.color: Color.popups.border
              Accessible.role: Accessible.Button
              Accessible.name: "Cancel"
              Accessible.description: "Do not trust or open this launcher. Enter and Escape also choose Cancel."
              Accessible.focusable: true
              Accessible.focused: keyboardFocus
              Accessible.defaultButton: true
              Accessible.onPressAction: host.clearTrustPrompt()

              Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 0
                color: "transparent"
                border.width: 1
                border.color: cancelMouse.containsMouse || parent.keyboardFocus ? Color.menu.selectedText : Color.popups.border
              }

              Text {
                id: cancelLabel
                anchors.centerIn: parent
                text: "Cancel"
                textFormat: Text.PlainText
                color: cancelMouse.containsMouse || parent.keyboardFocus ? Color.menu.selectedText : Color.popups.text
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: cancelMouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: panel.trustFocusIndex = 0
                onClicked: host.clearTrustPrompt()
              }
            }

            Rectangle {
              id: trustButton
              readonly property bool keyboardFocus: host.pendingTrust && panel.trustFocusIndex === 1
              width: Math.max(44, trustLabel.implicitWidth + 20)
              height: 44
              radius: 0
              color: trustMouse.containsMouse || keyboardFocus ? Color.menu.selectedBackground : "transparent"
              border.width: 2
              border.color: Color.popups.border
              Accessible.role: Accessible.Button
              Accessible.name: "Trust and Open"
              Accessible.description: "Mark this launcher as trusted and run it. Space activates this choice when focused."
              Accessible.focusable: true
              Accessible.focused: keyboardFocus
              Accessible.defaultButton: false
              enabled: !!host.pendingTrust
              Accessible.onPressAction: {
                if (host.pendingTrust)
                  host.trustAndOpen(host.pendingTrust)
              }

              Text {
                id: trustLabel
                anchors.centerIn: parent
                text: "Trust and Open"
                textFormat: Text.PlainText
                color: trustMouse.containsMouse || parent.keyboardFocus ? Color.menu.selectedText : Color.popups.text
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: trustMouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: panel.trustFocusIndex = 1
                onClicked: host.trustAndOpen(host.pendingTrust)
              }
            }
          }
        }
      }
    }
  }
}
