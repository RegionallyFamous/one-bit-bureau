import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "DockModel.js" as DockModel
import "IconResolver.js" as IconResolver

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var manifest: null
  property string home: Quickshell.env("HOME")
  property string iconDir: home + "/.config/omarchy/paper-jam-84/icons"
  property string iconMapPath: home + "/.config/omarchy/paper-jam-84/dock-icons.json"
  property string packDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/components/dock/assets/app-icons"
    : root.home + "/.config/omarchy/plugins/io.github.regionallyfamous.paper-jam-84/components/dock/assets/app-icons"
  property string pinPath: home + "/.config/omarchy/paper-jam-84/dock-pinned.json"
  property string tempPinPath: pinPath + ".tmp"
  property string settingsPath: home + "/.config/omarchy/paper-jam-84/dock-settings.json"
  property string tempSettingsPath: settingsPath + ".tmp"
  property var pinnedIds: []
  property var dockOrder: []
  property bool pinFileLoaded: false
  property bool settingsLoaded: false
  property var appEntries: []
  property var runningIds: []
  // Most-recently-used app ids, front = most recent. Maintained from focus
  // changes; powers the Alt+Tab switcher ordering (an app switcher cycles by
  // recency, not by the dock's pinned-first visual order).
  property var mruIds: []
  // Repeater model: stable id strings. Replaced only when the id set changes
  // (apps opened/closed); reorders and pin/running toggles never touch it, so
  // no delegate is torn down by dragging or state changes.
  property var dockItems: []
  property bool appLibraryReady: false
  property bool conflictDetected: false
  property bool dockHovered: false
  property bool menuOpen: false
  property bool pickerOpen: false
  property bool enabled: true
  property bool dockReady: false
  // Shelf auto-hide. Enabled by default; persisted in dock-settings.json.
  property bool autoHide: true
  property string preferredScreenName: ""
  readonly property var dockScreen: {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0)
      return null
    if (root.preferredScreenName) {
      for (var i = 0; i < screens.length; i++) {
        if (String(screens[i].name || "") === root.preferredScreenName)
          return screens[i]
      }
    }
    return screens[0]
  }
  // Short linear reveal timing for the Raster shelf.
  property int hideDelay: 1000
  property int showDelay: 100
  property int hideDuration: 380
  property int showDuration: 280
  property int edgeHeight: 3
  property int peekPx: 0
  // Hide is suppressed while any transient UI is active so the dock does not
  // vanish under a menu, preview, picker or drag.
  property bool hideSuppressed: root.menuOpen || root.pickerOpen || root.previewVisible || root.floatingId !== "" || !!(root.altTab && root.altTab.active)
  property bool edgeHovered: false
  // Combined engagement — dockHovered OR edgeHovered. While true, hide is
  // suppressed and must not be scheduled. Extracted to avoid the fragile 5px
  // gap between dockSurface bottom (H-8) and edge strip (H-3).
  property bool dockEngaged: root.dockHovered || root.edgeHovered
  // Slide state for auto-hide. The PanelWindow stays mapped when enabled;
  // this flag drives the bottomMargin translation so the glide is animated.
  property bool autoHidden: false
  property int dockHeight: 101
  property int bottomMargin: 8
  property int iconSize: 50
  property real hoveredMouseX: -1
  property string hoveredItemId: ""
  property var tooltipItem: null
  property real tooltipCenterX: 0
  property var customIcons: ({})
  property int customIconRevision: 0
  property string focusHelperPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/components/dock/scripts/focus-window"
    : root.home + "/.config/omarchy/plugins/io.github.regionallyfamous.paper-jam-84/components/dock/scripts/focus-window"
  property string stateHelperPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/components/dock/scripts/paper-jam-state"
    : root.home + "/.config/omarchy/plugins/io.github.regionallyfamous.paper-jam-84/components/dock/scripts/paper-jam-state"
  property string runHelperPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/components/dock/scripts/paper-jam-run"
    : root.home + "/.config/omarchy/plugins/io.github.regionallyfamous.paper-jam-84/components/dock/scripts/paper-jam-run"

  // Layout & drag state. The Repeater model (dockItems) is the stable identity
  // list of ids, replaced only when the id set changes; reorders go through
  // applyLayout(), which only mutates existing delegates, so no delegate is
  // ever torn down by dragging. Mutable pinned/running state lives in each
  // delegate's liveData binding so state changes never rebuild the Repeater.
  property int slotWidth: 58
  property int slotSpacing: 8
  property int sidePadding: 18
  property int separatorWidth: 14
  property string floatingId: ""
  property var tempDrag: ({ id: "", index: -1 })
  property var placements: ({})
  property real layoutWidth: 0
  property var visualCache: ({})
  property var delegateById: ({})
  property string ghostSource: ""
  property real ghostX: 0
  property real ghostY: 0
  property real ghostScale: 1.18
  property real ghostOpacity: 1
  property bool ghostSettling: false
  // Drop-inside state, tracked per-frame in onDragMoved from the cursor's
  // dockSurface-local position. Mapping item-to-item inside the same window
  // avoids the PanelWindow's output-anchored scene space entirely, so the
  // check is a plain AABB against the surface the input mask hit-tests.
  property bool dragInsideDock: true

  IpcHandler {
    target: "regionallyfamous.paper-jam-84.dock"
    function toggle() { root.enabled = !root.enabled }
    function show() { root.enabled = true }
    function hide() { root.enabled = false }
    function altTabNext() { root.altTabNext() }
    function altTabPrev() { root.altTabPrev() }
    function altTabCancel() { root.altTabCancel() }
    function toggleAutoHide(): void { root.autoHide = !root.autoHide; root.saveSettings() }
    function setAutoHide(value: string): void {
      var v = String(value).toLowerCase()
      root.autoHide = (v === "true" || v === "1" || v === "on")
      root.saveSettings()
    }
    function getAutoHide(): bool { return root.autoHide }
    function getItemCount(): int { return root.dockItems.length }
    function getReadyIconCount(): int { return root.readyIconCount() }
    function getNormalizedPackIconCount(): int { return root.normalizedPackIconCount() }
    function getIconSize(): int { return root.iconSize }
    function setScreen(name: string): bool {
      var requested = String(name || "").slice(0, 160)
      for (var i = 0; i < Quickshell.screens.length; i++) {
        if (String(Quickshell.screens[i].name || "") === requested) {
          root.preferredScreenName = requested
          root.saveSettings()
          return true
        }
      }
      return false
    }
    function getScreen(): string { return root.dockScreen ? String(root.dockScreen.name || "") : "" }
  }

  function saveSettings() {
    var content = DockModel.serializeSettings({
      autoHide: root.autoHide,
      screenName: root.preferredScreenName
    })
    DockModel.markSettingsWritten(content)
    settingsWriter.path = root.tempSettingsPath
    settingsWriter.setText(content)
    Qt.callLater(function() { settingsRenameProcess.running = true })
  }

  // Central helper: build the state snapshot consumed by the pure helpers.
  function hideState() {
    return {
      autoHide: root.autoHide,
      enabled: root.enabled,
      dockReady: root.dockReady,
      autoHidden: root.autoHidden,
      dockEngaged: root.dockEngaged,
      hideSuppressed: root.hideSuppressed,
      dockHovered: root.dockHovered,
      edgeHovered: root.edgeHovered
    }
  }

  function maybeScheduleHide() {
    if (DockModel.shouldScheduleHide(hideState())) hideTimer.restart()
  }

  onAutoHideChanged: {
    if (!root.autoHide) {
      hideTimer.stop()
      showTimer.stop()
      root.autoHidden = false
    } else {
      maybeScheduleHide()
    }
  }

  onHideSuppressedChanged: {
    if (root.hideSuppressed) {
      hideTimer.stop()
    } else {
      maybeScheduleHide()
    }
  }

  onEnabledChanged: {
    if (!root.enabled) root.hidePreview()
    if (!root.enabled) {
      // Manual hide (Super+H) always stops auto-hide timers.
      hideTimer.stop()
      showTimer.stop()
    } else {
      maybeScheduleHide()
    }
  }

  onDockReadyChanged: {
    maybeScheduleHide()
  }

  onDockScreenChanged: {
    if (root.settingsLoaded && !root.preferredScreenName && root.dockScreen) {
      root.preferredScreenName = String(root.dockScreen.name || "")
      root.saveSettings()
    }
  }

  onDockHoveredChanged: {
    if (root.dockHovered) {
      hideTimer.stop()
      showTimer.stop()
      if (root.autoHide && root.autoHidden) root.autoHidden = false
    } else {
      maybeScheduleHide()
    }
  }

  onDockEngagedChanged: {
    // The fragile 5px gap between dock bottom and edge is now covered by
    // dockEngaged. A single handler here would suffice, but we keep the
    // explicit dock/edge handlers for the reveal path.
    if (!root.dockEngaged) maybeScheduleHide()
    else hideTimer.stop()
  }

  onEdgeHoveredChanged: {
    if (root.edgeHovered) {
      hideTimer.stop()
      if (DockModel.shouldRevealDock(hideState())) showTimer.restart()
    } else {
      showTimer.stop()
      maybeScheduleHide()
      if (root.autoHide && root.autoHidden) {
        // Edge left while still hidden — cancel pending show, stay hidden.
        showTimer.stop()
      }
    }
  }

  function normalizeRunning() {
    var output = []
    try {
      var values = ToplevelManager.toplevels.values
      for (var i = 0; i < values.length; i++) {
        var item = values[i]
        var id = root.desktopIdForWindow(item)
        if (id && output.indexOf(id) === -1) output.push(id)
      }
    } catch (error) {}
    return output
  }

  function desktopIdForWindow(window) {
    var raw = String(window.appId || window.desktopId || window.className || window.initialClass || "").replace(/\.desktop$/, "")
    return DockModel.resolveDesktopId(raw, root.appEntries)
  }

  function hyprlandWindowFor(window) {
    var targetId = String(window.appId || window.desktopId || window.className || window.initialClass || "").toLowerCase()
    var targetTitle = String(window.title || "")
    var fallback = null
    try {
      var values = Hyprland.toplevels.values
      for (var i = 0; i < values.length; i++) {
        var candidate = values[i]
        var ids = []
        if (candidate.wayland && candidate.wayland.appId) ids.push(String(candidate.wayland.appId).toLowerCase())
        var ipc = candidate.lastIpcObject || {}
        if (ipc.appId) ids.push(String(ipc.appId).toLowerCase())
        if (ipc["class"]) ids.push(String(ipc["class"]).toLowerCase())
        if (ipc.initialClass) ids.push(String(ipc.initialClass).toLowerCase())
        if (ids.indexOf(targetId) === -1) continue
        if (targetTitle && candidate.title === targetTitle) return candidate
        if (!fallback) fallback = candidate
      }
    } catch (error) {}
    return fallback
  }

  function hyprlandWindowForItem(item) {
    if (!item) return null
    var fallback = null
    try {
      var values = Hyprland.toplevels.values
      for (var i = 0; i < values.length; i++) {
        var candidate = values[i]
        var ids = []
        if (candidate.wayland && candidate.wayland.appId) ids.push(String(candidate.wayland.appId).toLowerCase())
        var ipc = candidate.lastIpcObject || {}
        if (ipc.appId) ids.push(String(ipc.appId).toLowerCase())
        if (ipc["class"]) ids.push(String(ipc["class"]).toLowerCase())
        if (ipc.initialClass) ids.push(String(ipc.initialClass).toLowerCase())
        for (var j = 0; j < ids.length; j++) {
          if (ids[j] === String(item.id).toLowerCase()) return candidate
          if (root.desktopIdForWindow({ appId: ids[j], title: candidate.title }) === item.id) {
            if (!fallback) fallback = candidate
          }
        }
      }
    } catch (error) {}
    return fallback
  }

  function focusWindowAddress(address) {
    if (!address) return false
    // This Omarchy build uses Hyprland's Lua dispatcher syntax. The older
    // `workspace ...` / `focuswindow ...` strings are parsed as Lua and fail.
    // Focusing by address also switches to the window's workspace without
    // going through Toplevel.activate(), which can warp the pointer.
    var normalized = String(address)
    if (normalized.indexOf("0x") !== 0) normalized = "0x" + normalized
    if (!/^0x[0-9a-fA-F]+$/.test(normalized) || focusWindowProcess.running)
      return false
    focusWindowProcess.command = ["bash", root.focusHelperPath, normalized]
    focusWindowProcess.running = true
    return true
  }

  function focusExistingWindow(hyprWindow) {
    if (!hyprWindow || !hyprWindow.address) return false
    return root.focusWindowAddress(hyprWindow.address)
  }

  onShellChanged: if (root.shell) root.refreshApps()

  function refreshApps() {
    if (!root.shell || !root.shell.appLibrary) return
    try {
      var rows = root.shell.appLibrary.sortedEntries("") || []
      // AppLibrary returns sorted rows shaped as { entry, score, key, name }.
      // Keep only the underlying desktop entries for dock lookup.
      root.appEntries = rows.map(function(row) { return row && row.entry ? row.entry : row })
      root.appLibraryReady = true
    } catch (error) {
      console.warn("paper-jam-84: app library refresh failed", error)
    }
    refreshItems()
  }

  function refreshItems() {
    root.runningIds = normalizeRunning()
    // The session order is authoritative: it preserves drag rearrangements of
    // any app (pinned or running) while dropping apps that closed and
    // appending newly opened ones. Pinned apps stay pinned; running apps are
    // never promoted into the pinned list by dragging.
    var prevOrder = root.dockOrder.join("|")
    root.dockOrder = DockModel.reconcileDockOrder(root.dockOrder, root.pinnedIds, root.runningIds)
    // The layout file mirrors the session order; persist it (debounced) when
    // the order changes so a restart restores the exact interleaving. Wait
    // until the pin file has been read so a slow boot never clobbers it.
    if (root.pinFileLoaded && root.dockOrder.join("|") !== prevOrder)
      persistTimer.restart()
    // Reassign the Repeater model only when the set of ids changed (apps
    // opened/closed, pin file reloaded). A reorder or a pin/running toggle
    // must never touch the model: replacing a JS array model destroys and
    // recreates every delegate. Delegate positions are driven by
    // placements[id] in applyLayout(), so the model's order is irrelevant.
    if (!root.floatingId) {
      if (!root.sameIdSet(root.dockOrder, root.dockItems))
        root.dockItems = root.dockOrder.slice()
    }
    root.applyLayout()
  }

  // Order-insensitive id-set equality: the model must survive reorders and
  // state changes, and only grow/shrink on actual membership changes.
  function sameIdSet(a, b) {
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) {
      if (b.indexOf(a[i]) === -1) return false
    }
    return true
  }

  function cursorXInRow() {
    if (root.hoveredMouseX < 0) return -1
    return dockRow.mapFromItem(null, root.hoveredMouseX, 0).x
  }

  // Leaving the shelf over a gap or the surface padding never triggers a
  // DockItem exit, so reset the hover state here.
  function clearHover() {
    if (root.floatingId) return // the drag controller owns hoveredMouseX
    root.hoveredItemId = ""
    root.hoveredMouseX = -1
    root.applyLayout()
  }

  function registerItem(id, item) { root.delegateById[id] = item }
  function unregisterItem(id) { delete root.delegateById[id] }

  // Live metadata for a dock id, mirrored from the observable root state so a
  // delegate's itemData updates in place instead of the Repeater rebuilding.
  function appNameFor(id) {
    var entry = DockModel.entryFor(id, root.appEntries)
    return entry.name || entry.displayName || id
  }

  function appIconNameFor(id) {
    var entry = DockModel.entryFor(id, root.appEntries)
    return entry.icon || entry.iconName || ""
  }

  function readyIconCount() {
    var count = 0
    for (var id in root.delegateById) {
      var delegate = root.delegateById[id]
      if (delegate && delegate.iconReady)
        count++
    }
    return count
  }

  function normalizedPackIconCount() {
    var count = 0
    for (var id in root.delegateById) {
      var delegate = root.delegateById[id]
      if (delegate && delegate.packNormalized)
        count++
    }
    return count
  }

  // New delegates seed their animated properties from the item's last visual
  // state so a structural rebuild never pops.
  function seedFor(id) {
    var cached = root.visualCache[id]
    if (cached) return cached
    var p = root.placements[id]
    return { x: p ? p.x : 0, scale: p ? p.scale : 1, lift: p ? p.lift : 0 }
  }

  function applyLayout() {
    var cursorX = root.cursorXInRow()
    var baseFlow = DockModel.buildFlow(root.dockOrder, [], root.floatingId, -1)
    if (root.floatingId && cursorX >= 0)
      root.tempDrag.index = DockModel.insertionIndexFor(cursorX, baseFlow, DockModel.LAYOUT_OPTS)
    var flow = DockModel.buildFlow(
      root.dockOrder,
      [],
      root.floatingId,
      root.floatingId ? root.tempDrag.index : -1
    )
    var result = DockModel.computeLayout(flow, cursorX, DockModel.LAYOUT_OPTS)
    root.placements = result.placements
    root.layoutWidth = result.totalWidth
    for (var id in result.placements) {
      var p = result.placements[id]
      var d = root.delegateById[id]
      if (!d) continue
      d.x = p.x
      d.targetScale = p.scale
      d.targetLift = p.lift
      d.targetOpacity = (id === root.floatingId) ? 0 : (p.phantom ? 0.45 : 1)
    }
    // The dragged item is excluded from the flow so it has no placement; hide
    // its dock copy while the ghost follows the cursor.
    if (root.floatingId && root.delegateById[root.floatingId])
      root.delegateById[root.floatingId].targetOpacity = 0
  }

  function checkDockConflict() {
    var registry = root.pluginRegistry || (root.shell ? root.shell.pluginRegistry : null)
    var conflict = false
    if (registry && typeof registry.isEnabled === "function") {
      try { conflict = registry.isEnabled("rosakodu.dock") } catch (error) {}
    }
    root.conflictDetected = conflict
    if (conflict) root.notifyConflict()
  }

  function notifyConflict() {
    if (conflictNotice.running) return
    conflictNotice.running = true
    Quickshell.execDetached(["omarchy-shell", "notify", "Paper Jam Dock is disabled because rosakodu.dock is enabled"])
  }

  function handleClick(item) {
    if (!item) return
    if (item.running) {
      try {
        // Never fall back to Toplevel.activate() here: it can warp the cursor.
        // Existing windows must be focused through Hyprland's IPC path.
        var hyprWindow = root.hyprlandWindowForItem(item)
        if (!root.focusExistingWindow(hyprWindow))
          console.warn("regionallyfamous.paper-jam-84.dock: could not resolve running window for " + item.id)
        return
      } catch (error) {}
    }
    var entry = DockModel.entryFor(item.id, root.appEntries)
    if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.launch === "function")
      root.shell.appLibrary.launch(item.id, entry.name || item.name)
  }

  // ---- Alt+Tab app switcher -------------------------------------------------
  // The switcher is an app switcher, so recency is tracked per application
  // (not per window). The dock's visual order (pinned first) is irrelevant
  // here: focus history drives the cycle order.

  function dockIdForHyprlandWindow(window) {
    try {
      var ids = []
      if (window.wayland && window.wayland.appId) ids.push(String(window.wayland.appId).toLowerCase())
      var ipc = window.lastIpcObject || {}
      if (ipc.appId) ids.push(String(ipc.appId).toLowerCase())
      if (ipc["class"]) ids.push(String(ipc["class"]).toLowerCase())
      if (ipc.initialClass) ids.push(String(ipc.initialClass).toLowerCase())
      for (var i = 0; i < ids.length; i++) {
        var resolved = root.desktopIdForWindow({ appId: ids[i] })
        if (resolved) return resolved
      }
    } catch (error) {}
    return ""
  }

  function touchMru(id) {
    if (!id) return
    var list = root.mruIds.slice(0)
    var i = list.indexOf(id)
    if (i >= 0) list.splice(i, 1)
    list.unshift(id)
    root.mruIds = list
  }

  function altTabAppData(id) {
    var entry = DockModel.entryFor(id, root.appEntries)
    var name = entry && entry.name ? entry.name : IconResolver.sanitizeName(id)
    return { id: id, name: name }
  }

  // MRU order first, then any running app never focused since shell start.
  function buildAltTabApps() {
    var apps = []
    var seen = {}
    for (var i = 0; i < root.mruIds.length; i++) {
      var id = root.mruIds[i]
      if (root.runningIds.indexOf(id) === -1 || seen[id]) continue
      seen[id] = true
      apps.push(root.altTabAppData(id))
    }
    for (var j = 0; j < root.runningIds.length; j++) {
      var rid = root.runningIds[j]
      if (seen[rid]) continue
      seen[rid] = true
      apps.push(root.altTabAppData(rid))
    }
    return apps
  }

  function altTabFocusedIndex(apps) {
    try {
      var win = Hyprland.activeToplevel
      if (!win) return -1
      var id = root.dockIdForHyprlandWindow(win)
      if (!id) return -1
      for (var i = 0; i < apps.length; i++)
        if (apps[i].id === id) return i
    } catch (error) {}
    return -1
  }

  function altTabNext() {
    if (altTab.active) {
      altTab.next()
      return
    }
    var apps = root.buildAltTabApps()
    if (apps.length === 0) return
    var index = root.altTabFocusedIndex(apps)
    // First Tab after opening: land on the app AFTER the focused one, like
    // macOS. With nothing focused, start at the front.
    altTab.open(apps, index < 0 ? 0 : (index + 1) % apps.length)
  }

  function altTabPrev() {
    if (altTab.active) {
      altTab.prev()
      return
    }
    var apps = root.buildAltTabApps()
    if (apps.length === 0) return
    var index = root.altTabFocusedIndex(apps)
    altTab.open(apps, index < 0 ? apps.length - 1 : (index - 1 + apps.length) % apps.length)
  }

  function altTabCancel() {
    altTab.cancel()
  }

  function activateApp(id, name) {
    try {
      // Same no-warp focus path as clicking the dock: never Toplevel.activate().
      var hyprWindow = root.hyprlandWindowForItem({ id: id })
      if (hyprWindow && root.focusExistingWindow(hyprWindow)) return
    } catch (error) {
    }
    var entry = DockModel.entryFor(id, root.appEntries)
    var label = name || (entry && entry.name) || id
    if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.launch === "function")
      root.shell.appLibrary.launch(id, label)
  }

  Process {
    id: focusWindowProcess
  }

  function savePinned() {
    var content = DockModel.serializePinned(root.pinnedIds, root.dockOrder)
    DockModel.markWritten(content)
    tempWriter.path = root.tempPinPath
    tempWriter.setText(content)
    Qt.callLater(function() { renameProcess.running = true })
  }

  function openMenu(item, position) {
    root.tooltipItem = null
    root.hidePreview()
    root.menuOpen = true
    dockMenu.itemData = item
    dockMenu.requestedPosition = Qt.point(position.x, position.y - dockMenu.height - 12)
    dockMenu.opened = true
  }

  function menuAction(action, item) {
    if (action === "toggleAutoHide") {
      root.autoHide = !root.autoHide
      root.saveSettings()
      return
    }
    if (!item) return
    if (action === "togglePin") root.pinnedIds = DockModel.togglePinned(root.pinnedIds, item.id)
    else if (action === "newWindow") handleClick({ id: item.id, name: item.name, running: false })
    else if (action === "close") closeWindow(item.id)
    else if (action === "setIcon") root.openIconPicker(item.id, item.name, false)
    else if (action === "manageIcons") root.openIconManager()
    if (action === "togglePin") { refreshItems(); savePinned() }
  }

  function openIconPicker(appId, appName, fromManage) {
    root.menuOpen = false
    root.pickerOpen = true
    root.hidePreview()
    iconPicker.openForApp(appId, appName, fromManage)
  }

  function openIconManager() {
    root.menuOpen = false
    root.pickerOpen = true
    root.hidePreview()
    iconPicker.openManage()
  }

  function closeWindow(id) {
    try {
      var values = ToplevelManager.toplevels.values
      for (var i = values.length - 1; i >= 0; i--) {
        var window = values[i]
        var windowId = root.desktopIdForWindow(window)
        if (windowId === id && typeof window.close === "function") { window.close(); return }
      }
    } catch (error) {}
  }

  // Drag controller ---------------------------------------------------------
  function onDragMoved(item, position, surfacePosition) {
    if (!root.floatingId) {
      root.floatingId = item.id
      root.tempDrag = { id: item.id, index: -1 }
      root.ghostSource = root.iconSourceFor(item)
      root.ghostScale = 1.18
      root.ghostOpacity = 1
      root.tooltipVisible = false
      root.tooltipItem = null
    }
    root.hoveredMouseX = position.x
    root.hidePreview()
    root.dragInsideDock =
      surfacePosition.x >= 0 && surfacePosition.x <= dockSurface.width &&
      surfacePosition.y >= 0 && surfacePosition.y <= dockSurface.height
    root.ghostX = position.x - root.iconSize * root.ghostScale / 2
    root.ghostY = position.y - root.iconSize * root.ghostScale / 2 - 30
    root.applyLayout()
  }

  function finishDrag(item, surfacePosition) {
    var id = item.id
    if (!root.floatingId) return
    // `dragInsideDock` is tracked per-frame in onDragMoved from the cursor's
    // dockSurface-local position — the same surface the input mask
    // (Region { item: dockSurface }) hit-tests — so a drop is judged against
    // exactly what received the drag instead of a coordinate mapping
    // re-derived at release time.
    var inside = root.dragInsideDock
    console.log("paper-jam-84 finishDrag", JSON.stringify({ id: id, inside: inside, localX: surfacePosition.x, localY: surfacePosition.y, surfaceW: dockSurface.width, surfaceH: dockSurface.height, cursorX: root.cursorXInRow() }))
    var wasPinned = root.pinnedIds.indexOf(id) !== -1
    var persist = false

    try {
    if (inside) {
      var baseFlow = DockModel.buildFlow(root.dockOrder, [], id, -1)
      var idx = root.tempDrag.index
      if (idx < 0) idx = baseFlow.length
      // Reorder the session dock — never the pinned list. Dragging never
      // promotes a running app into a persistent pin.
      var newOrder = DockModel.moveInOrder(root.dockOrder, id, idx)
      console.log("paper-jam-84 reorder", JSON.stringify({ id: id, idx: idx, wasPinned: wasPinned, dockOrderBefore: root.dockOrder, newOrder: newOrder, pinnedBefore: root.pinnedIds, runningIds: root.runningIds }))
      if (newOrder.join("|") !== root.dockOrder.join("|")) {
        root.dockOrder = newOrder
        // Snap the dropped delegate straight to its new slot. Without this the
        // settle spring carries it the whole way from its old slot and swings
        // back past the drop point before settling. The delegate is invisible
        // (opacity 0) while floating, so the snap is seamless: it appears
        // instantly at full opacity exactly where the ghost was, and applyLayout
        // then assigns the identical x, so no spring runs.
        var dropFlow = DockModel.buildFlow(newOrder, [], "", -1)
        var dropResult = DockModel.computeLayout(dropFlow, root.cursorXInRow(), DockModel.LAYOUT_OPTS)
        var dropP = dropResult.placements[id]
        var dropDelegate = root.delegateById[id]
        if (dropP && dropDelegate) {
          dropDelegate.animating = false
          dropDelegate.targetOpacity = 1
          dropDelegate.x = dropP.x
          dropDelegate.animating = true
        }
      }
      if (wasPinned) {
        // A pinned app moved: persist its new relative order among the other
        // pinned apps only (running apps are never written to the pin file).
        var newPinned = DockModel.orderPinned(newOrder, root.pinnedIds)
        if (newPinned.join("|") !== root.pinnedIds.join("|")) {
          root.pinnedIds = newPinned
          persist = true
        }
      }
    } else if (wasPinned) {
      // Dragged out of the dock: the app loses its persistent slot but stays
      // in the session order while it keeps running.
      root.pinnedIds = DockModel.removePinned(root.pinnedIds, id)
      persist = true
    }

    // Restore the dragged delegate at full opacity without the 150ms fade so
    // a drop never reads as a blink, regardless of inside/outside.
    var restoredDelegate = root.delegateById[id]
    if (restoredDelegate) {
      restoredDelegate.animating = false
      restoredDelegate.targetOpacity = 1
      restoredDelegate.animating = true
    }

    root.floatingId = ""
    root.tempDrag = { id: "", index: -1 }
    // Always rebuild so any window/app changes deferred while dragging apply.
    root.refreshItems()
    if (persist) persistTimer.restart()
    // Hide the ghost immediately so it never overlaps the restored icon.
    ghostHideTimer.stop()
    root.ghostSettling = false
    root.ghostOpacity = 1
    root.ghostScale = 1.18
    root.ghostSource = ""
    } catch (error) {
      console.warn("paper-jam-84 finishDrag error", error)
      root.floatingId = ""
      root.tempDrag = { id: "", index: -1 }
      root.refreshItems()
      ghostHideTimer.stop()
      root.ghostSettling = false
      root.ghostOpacity = 1
      root.ghostScale = 1.18
      root.ghostSource = ""
    }
  }

  function showTooltip(item, show) {
    if (root.floatingId) return
    if (show) {
      tooltipItem = item
      tooltipVisible = true
    } else if (tooltipItem && tooltipItem.id === item.id) {
      tooltipVisible = false
      tooltipItem = null
    }
  }

  // Preview controller ------------------------------------------------------
  function onItemHoverChanged(item, isVisible, centerX) {
    if (!item || item.separator) return
    if (isVisible) {
      root.previewCenterX = centerX
      if (root.floatingId || root.menuOpen || root.pickerOpen || !root.enabled) return
      if (!item.running) { root.hidePreview(); return }
      if (root.previewAppId !== item.id) root.hidePreview()
      root.previewAppId = item.id
      previewDelay.restart()
    } else {
      if (root.previewAppId === item.id) previewGrace.restart()
    }
  }

  function hidePreview() {
    var was = root.previewAppId
    previewDelay.stop()
    previewGrace.stop()
    root.previewAppId = ""
    root.previewWindows = []
    root.previewVisible = false
    root.pendingPreviewShow = false
    if (root.deferredTooltipItem && root.hoveredItemId === was) {
      root.tooltipItem = root.deferredTooltipItem
      root.tooltipVisible = true
    }
    root.deferredTooltipItem = null
  }

  function array2(v) {
    if (v === null || v === undefined) return [0, 0]
    try {
      var a = Number(v[0])
      var b = Number(v[1])
      if (!isNaN(a) && !isNaN(b)) return [a, b]
    } catch (error) {}
    return [0, 0]
  }

  function gatherWindowsForApp(id) {
    var output = []
    try {
      var values = Hyprland.toplevels.values
      for (var i = 0; i < values.length; i++) {
        var candidate = values[i]
        var ids = []
        if (candidate.wayland && candidate.wayland.appId) ids.push(String(candidate.wayland.appId).toLowerCase())
        var ipc = candidate.lastIpcObject || {}
        if (ipc.appId) ids.push(String(ipc.appId).toLowerCase())
        if (ipc["class"]) ids.push(String(ipc["class"]).toLowerCase())
        if (ipc.initialClass) ids.push(String(ipc.initialClass).toLowerCase())
        var match = false
        for (var j = 0; j < ids.length; j++) {
          if (ids[j] === String(id).toLowerCase()) { match = true; break }
          if (root.desktopIdForWindow({ appId: ids[j], title: candidate.title }) === id) { match = true; break }
        }
        if (!match) continue
        var pos = root.array2(ipc.at)
        var size = root.array2(ipc.size)
        output.push({
          address: String(candidate.address || ""),
          title: String(candidate.title || ""),
          active: !!(ipc.focused || candidate.focused),
          mapped: !!ipc.mapped,
          minimized: !!ipc.minimized,
          workspaceId: ipc.workspace ? ipc.workspace.id : -1,
          x: pos[0] || 0,
          y: pos[1] || 0,
          w: size[0] || 0,
          h: size[1] || 0
        })
      }
    } catch (error) {}
    return output
  }

  // Window preview cards ----------------------------------------------------
  // Cards use the associated app icon. This stays truthful for minimized,
  // occluded, and other-workspace windows without launching capture jobs.
  function snapshotWindows() {
    // Window cards intentionally use app icons. Avoiding compositor capture
    // keeps hover deterministic and leaves no screenshot pipeline to outlive
    // a plugin reload.
    root.applyThumbnails()
  }

  function applyThumbnails() {
    if (!root.previewAppId) return
    var next = []
    for (var i = 0; i < root.previewWindows.length; i++) {
      var w = root.previewWindows[i]
      var copy = {}
      for (var k in w) copy[k] = w[k]
      next.push(copy)
    }
    root.previewWindows = next
    if (root.pendingPreviewShow) {
      root.pendingPreviewShow = false
      root.previewBottomY = dockSurface.y
      root.previewVisible = true
      root.deferredTooltipItem = root.tooltipItem
      root.tooltipItem = null
      root.tooltipVisible = false
    }
  }

  function thumbnailFor(w) {
    return ""
  }

  function activatePreviewWindow(data) {
    if (!data || !data.address) return
    root.hidePreview()
    root.focusWindowAddress(data.address)
  }

  function loadCustomIcons(content) {
    var parsed = {}
    try {
      var value = JSON.parse(String(content || "{}"))
      if (value && typeof value === "object" && !Array.isArray(value)) parsed = value
    } catch (error) {
      console.warn("paper-jam-84: invalid dock-icons.json")
    }
    root.customIcons = parsed
    root.customIconRevision++
  }

  function customIconSourceFor(id) {
    var file = IconResolver.customIconFile(root.customIcons, id)
    if (!file) return ""
    // The revision prevents QML from retaining an older image after a file
    // is replaced with the same filename.
    return Util.fileUrl(root.iconDir + "/" + file) + "?v=" + root.customIconRevision
  }

  function iconSourceFor(item) {
    // Accept either a live item object or a plain id string (delegates pass
    // their model id after the identity/state split).
    var id = typeof item === "string" ? item : item && item.id
    var customSource = root.customIconSourceFor(id)
    if (customSource) return customSource
    var entry = DockModel.entryFor(id, root.appEntries)
    var manualPack = IconResolver.customIconPack(root.customIcons, id)
    var nativeOnly = IconResolver.customIconMode(root.customIcons, id) === "native"
    var packRole = manualPack || (!nativeOnly ? IconResolver.automaticPackRole({
      id: id,
      desktopId: entry.desktopId,
      name: entry.name,
      displayName: entry.displayName,
      icon: entry.icon,
      iconName: entry.iconName,
      appIcon: entry.appIcon
    }) : "")
    if (packRole) return Util.fileUrl(root.packDir + "/" + packRole + ".png")
    var iconName = entry.icon || entry.iconName || entry.appIcon || ""
    if (root.shell && root.shell.appLibrary && iconName && typeof root.shell.appLibrary.iconSource === "function") {
      var resolved = root.shell.appLibrary.iconSource(iconName)
      if (resolved && String(resolved).indexOf("application-x-executable") === -1)
        return resolved
      var fallbackName = IconResolver.resolveIcon(entry)
      if (fallbackName && fallbackName !== iconName) {
        resolved = root.shell.appLibrary.iconSource(fallbackName)
        if (resolved && String(resolved).indexOf("application-x-executable") === -1)
          return resolved
      }
    }
    return ""
  }

  Timer { id: conflictNotice; interval: 30000 }
  property bool tooltipVisible: false
  property var deferredTooltipItem: null

  // Hover-to-preview state. Lives entirely outside the dock model: it never
  // touches dockItems/dockOrder/pinnedIds, so showing a preview can never
  // rebuild the Repeater or flash the dock.
  property string previewAppId: ""
  property var previewWindows: []
  property bool previewVisible: false
  property real previewCenterX: 0
  property real previewBottomY: 0
  property bool pendingPreviewShow: false

  Timer {
    id: previewDelay
    interval: 180
    onTriggered: {
      if (!root.previewAppId || root.floatingId || root.menuOpen || root.pickerOpen || !root.enabled) return
      var wins = root.gatherWindowsForApp(root.previewAppId)
      if (!wins.length) return
      root.previewWindows = wins
      // Snapshots run before the preview is shown so the panel never appears
      // inside its own thumbnails; the preview pops in once they are ready.
      root.pendingPreviewShow = true
      root.snapshotWindows()
    }
  }

  // Grace period: when the cursor leaves a dock item, the preview stays up
  // long enough for the user to glide into it. Entering the preview panel
  // cancels this; leaving both hides the preview.
  Timer {
    id: previewGrace
    interval: 300
    onTriggered: root.hidePreview()
  }

  function applyStateSnapshot(content) {
    var snapshot = null
    try {
      snapshot = JSON.parse(String(content || ""))
    } catch (error) {
      return
    }
    if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) return

    root.loadCustomIcons(JSON.stringify(snapshot.icons || {}))

    var pinContent = JSON.stringify(snapshot.pins || {})
    if (!root.pinFileLoaded) {
      root.pinFileLoaded = true
      root.pinnedIds = DockModel.parsePinned(pinContent, DockModel.DEFAULT_PINNED)
    } else if (DockModel.shouldReprocess(pinContent)) {
      root.pinnedIds = DockModel.parsePinned(pinContent, root.pinnedIds)
    }
    root.dockOrder = DockModel.parseOrder(pinContent, root.dockOrder)
    root.refreshItems()

    var settingsContent = JSON.stringify(snapshot.settings || {})
    var parsed = DockModel.parseSettings(settingsContent, {
      autoHide: true,
      screenName: root.preferredScreenName
    })
    if (!root.settingsLoaded || DockModel.shouldReprocessSettings(settingsContent)) {
      root.settingsLoaded = true
      root.autoHide = parsed.autoHide
      root.preferredScreenName = parsed.screenName
    }
    if (!root.preferredScreenName && root.dockScreen) {
      root.preferredScreenName = String(root.dockScreen.name || "")
      root.saveSettings()
    }
    if (!root.autoHide) root.autoHidden = false
  }

  function reloadBoundedState() {
    if (stateReaderProcess.running || !root.stateHelperPath || !root.runHelperPath) return
    stateReaderProcess.command = [
      "python3", root.runHelperPath, "2200", "250", "--",
      "python3", root.stateHelperPath, "read",
      root.iconMapPath, root.pinPath, root.settingsPath
    ]
    stateReaderProcess.running = true
    stateReaderDeadline.restart()
  }

  Timer {
    id: stateReaderPoll
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.reloadBoundedState()
  }

  Timer {
    id: stateReaderDeadline
    interval: 2500
    onTriggered: {
      if (stateReaderProcess.running) stateReaderProcess.running = false
    }
  }

  Process {
    id: stateReaderProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStateSnapshot(text)
    }
    onExited: stateReaderDeadline.stop()
  }

  FileView {
    id: tempWriter
    watchChanges: false
    printErrors: false
  }

  FileView {
    id: settingsWriter
    watchChanges: false
    printErrors: false
  }

  Process {
    id: renameProcess
    command: ["mv", root.tempPinPath, root.pinPath]
    onExited: root.refreshItems()
  }

  Process {
    id: settingsRenameProcess
    command: ["mv", root.tempSettingsPath, root.settingsPath]
  }

  Connections {
    target: root.shell ? root.shell.appLibrary : null
    function onAppsChanged() { root.refreshApps() }
  }
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      // Keep the Alt+Tab MRU list in sync with focus changes. The switcher
      // only tracks apps the dock knows about.
      var mruId = root.dockIdForHyprlandWindow(Hyprland.activeToplevel)
      if (mruId && root.runningIds.indexOf(mruId) !== -1) root.touchMru(mruId)
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      root.refreshItems()
      // The preview mirrors the live window set without touching the dock
      // model: cards appear/disappear as windows open/close.
      if (root.previewVisible && root.previewAppId) {
        var wins = root.gatherWindowsForApp(root.previewAppId)
        if (!wins.length) root.hidePreview()
        else root.previewWindows = wins
      }
    }
  }
  Connections {
    target: root.pluginRegistry
    function onPluginsChanged() { root.checkDockConflict() }
    function onScanFinished() { root.checkDockConflict() }
  }

  Component.onCompleted: {
    root.checkDockConflict()
    root.refreshApps()
    root.refreshItems()
    // The alt-tab HUD opens/closes on keypresses; Hyprland's default layer
    // fade would add a visible fade-in. Disable compositor animation for
    // both layer namespaces so the HUD pops in instantly.
    if (!layerRuleProcess.running) layerRuleProcess.running = true
    Qt.callLater(function() { root.dockReady = true })
  }

  Component.onDestruction: {
    stateReaderPoll.stop()
    stateReaderDeadline.stop()
    stateReaderProcess.running = false
    renameProcess.running = false
    settingsRenameProcess.running = false
    layerRuleProcess.running = false
  }

  Process {
    id: layerRuleProcess
    command: ["hyprctl", "eval", "hl.layer_rule({ match = { namespace = \"paper-jam-84-dock-alt-tab\" }, no_anim = true, animation = \"none\" })"]
  }

  PanelWindow {
    id: dockWindow
    visible: !root.conflictDetected && root.enabled
    screen: root.dockScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "paper-jam-84-dock"
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region { item: dockSurface }

    Rectangle {
      id: dockSurface
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.autoHide && root.autoHidden ? -root.dockHeight + root.peekPx : root.bottomMargin
      width: root.layoutWidth
      height: root.dockHeight
      radius: 0
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      opacity: root.enabled ? 1 : 0

      Behavior on width {
        NumberAnimation { duration: 90; easing.type: Easing.Linear }
      }
      Behavior on anchors.bottomMargin {
        NumberAnimation { duration: root.autoHidden ? root.hideDuration : root.showDuration; easing.type: Easing.Linear }
      }
      Behavior on opacity { NumberAnimation { duration: 60; easing.type: Easing.Linear } }

      Item {
        id: dockRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 0
        width: root.layoutWidth - 2 * root.sidePadding
        height: root.iconSize + 16

        Behavior on width {
          NumberAnimation { duration: 90; easing.type: Easing.Linear }
        }

        Repeater {
          model: root.dockItems
          delegate: Item {
            id: wrapper
            required property string modelData
            // The wrapper spans the fixed slot so the icon remains centered.
            width: root.slotWidth * targetScale
            height: root.iconSize + 16
            x: 0
            property bool animating: false

            // Live metadata mirrored from observable root state so a pin or
            // running toggle updates the delegate in place instead of the
            // Repeater rebuilding every DockItem.
            property var liveData: ({
              id: modelData,
              name: root.appNameFor(modelData),
              icon: root.appIconNameFor(modelData),
              pinned: root.pinnedIds.indexOf(modelData) !== -1,
              running: root.runningIds.indexOf(modelData) !== -1
            })

            property alias targetScale: dockItem.targetScale
            property alias targetLift: dockItem.targetLift
            property alias targetOpacity: dockItem.targetOpacity
            readonly property bool iconReady: dockItem.iconReady
            readonly property bool packNormalized: dockItem.packNormalized

            Behavior on x {
              enabled: wrapper.animating
              NumberAnimation { duration: 70; easing.type: Easing.Linear }
            }

            Component.onCompleted: {
              root.registerItem(modelData, wrapper)
              var seed = root.seedFor(modelData)
              x = seed.x
              targetScale = seed.scale
              targetLift = seed.lift
              targetOpacity = (modelData === root.floatingId) ? 0 : 1
              animating = true
            }
            Component.onDestruction: {
              root.visualCache[modelData] = { x: x, scale: targetScale, lift: targetLift }
              root.unregisterItem(modelData)
            }

            DockItem {
              id: dockItem
              anchors.centerIn: parent
              itemData: wrapper.liveData
              iconSize: root.iconSize
              animationEnabled: wrapper.animating
              iconSourceOverride: root.iconSourceFor(modelData)
              onItemLeftClicked: function(clickedItem) { root.handleClick(clickedItem) }
              onItemRightClicked: function(clickedItem, position) { root.openMenu(clickedItem, position) }
              onDragMoved: function(draggedItem, position) {
                root.onDragMoved(draggedItem,
                  dockItem.mapToItem(null, position.x, position.y),
                  dockItem.mapToItem(dockSurface, position.x, position.y))
              }
              onDragFinished: function(draggedItem, position) {
                root.finishDrag(draggedItem, dockItem.mapToItem(dockSurface, position.x, position.y))
              }
              onTooltipRequested: function(hoveredItem, isVisible, centerX) {
                root.tooltipCenterX = centerX
                root.onItemHoverChanged(hoveredItem, isVisible, centerX)
                root.showTooltip(hoveredItem, isVisible)
              }
              onHoverPointerChanged: function(hoveredItem, isInside, pointerX) {
                if (isInside) {
                  root.hoveredItemId = hoveredItem.id
                  root.hoveredMouseX = pointerX
                  root.tooltipCenterX = pointerX
                } else if (!root.floatingId && root.hoveredItemId === hoveredItem.id) {
                  // The cursor left this item's hit area but is still on the
                  // shelf (or already inside a neighbor's). Keep hoveredMouseX
                  // continuous for stable drag insertion; clearHover() resets it when
                  // the cursor actually leaves the dock surface.
                  root.hoveredItemId = ""
                }
                root.applyLayout()
              }
            }
          }
        }
      }

      MouseArea {
        id: mouseArea
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onEntered: {
          root.dockHovered = true
          hideTimer.stop()
          showTimer.stop()
          if (root.autoHide && root.autoHidden) root.autoHidden = false
        }
        onExited: {
          root.dockHovered = false
          root.clearHover()
          maybeScheduleHide()
        }
        onPositionChanged: {
          root.hoveredMouseX = mouseArea.mapToItem(null, mouseX, mouseY).x
          root.applyLayout()
        }
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openIconManager()
        }
      }
    }

    Rectangle {
      visible: root.tooltipVisible && root.tooltipItem !== null
      z: 20
      x: Math.max(12, Math.min(root.tooltipCenterX - width / 2, parent.width - width - 12))
      y: dockSurface.y - height - 8
      width: tooltipText.implicitWidth + 20
      height: 24
      radius: 0
      color: Color.tooltip.background
      border.color: Color.tooltip.border
      border.width: 2
      Text {
        id: tooltipText
        anchors.centerIn: parent
        text: root.tooltipItem ? (root.tooltipItem.name || root.tooltipItem.id) : ""
        color: Color.tooltip.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      // Subtle stem pointing toward the dock icon.
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: -5
        width: 8
        height: 8
        radius: 0
        color: parent.color
        border.color: parent.border.color
        border.width: 1
        rotation: 45
      }
    }

    MouseArea {
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: 18
      hoverEnabled: true
      onEntered: {
        root.dockHovered = true
        hideTimer.stop()
        showTimer.stop()
        if (root.autoHide && root.autoHidden) root.autoHidden = false
      }
      onExited: {
        // Leaving the bottom strip upward into the dock body still keeps the
        // cursor over the main mouseArea. Do not clear hover/hide in that
        // case — the parent area's onExited will handle the true exit.
        if (mouseArea.containsMouse) return
        root.dockHovered = false
        root.clearHover()
        maybeScheduleHide()
      }
    }
  }

  Timer {
    id: hideTimer
    interval: root.hideDelay
    onTriggered: {
      if (!DockModel.shouldHideDock(hideState())) return
      root.autoHidden = true
    }
  }

  Timer {
    id: showTimer
    interval: root.showDelay
    onTriggered: {
      if (!DockModel.shouldRevealDock(hideState())) return
      root.autoHidden = false
      hideTimer.stop()
    }
  }

  DockMenu {
    id: dockMenu
    screen: root.dockScreen
    autoHideEnabled: root.autoHide
    onActionTriggered: function(actionName, selectedItem) { root.menuAction(actionName, selectedItem) }
    onOpenedChanged: if (!opened) root.menuOpen = false
  }

  IconPickerPanel {
    id: iconPicker
    screen: root.dockScreen
    shell: root.shell
    customIcons: root.customIcons
    iconSourceFor: function(id) { return root.iconSourceFor(id) }
    stateHelperPath: root.stateHelperPath
    runHelperPath: root.runHelperPath
    iconMapPath: root.iconMapPath
    packDir: root.packDir
    onOpenChanged: if (!open) root.pickerOpen = false
  }

  // Persistence is written only after the settle animation finishes, matching
  // the "visual state -> animation completes -> persist pin" ordering.
  Timer {
    id: persistTimer
    interval: 300
    onTriggered: root.savePinned()
  }

  Timer {
    id: ghostHideTimer
    interval: 260
    onTriggered: {
      root.ghostSource = ""
      root.ghostSettling = false
      root.ghostOpacity = 1
      root.ghostScale = 1.18
    }
  }

  // Hover-to-preview lives in its own overlay layer window so it can extend
  // far above the dock surface without touching the dock's layout or model.
  WindowPreviewPanel {
    id: previewPanel
    screen: root.dockScreen
    previewVisible: root.previewVisible && !root.floatingId && !root.menuOpen
    windowList: root.previewWindows
    centerX: root.previewCenterX
    bottomY: root.previewBottomY
    iconSourceFor: function(data) { return root.iconSourceFor({ id: root.previewAppId }) }
    thumbnailFor: function(data) { return root.thumbnailFor(data) }
    onActivated: function(data) { root.activatePreviewWindow(data) }
    onPreviewHoverEntered: previewGrace.stop()
    onPreviewHoverExited: previewGrace.restart()
  }

  AltTabPanel {
    id: altTab
    screen: root.dockScreen
    iconSourceFor: function(app) { return root.iconSourceFor(app.id) }
    onActivated: function(appId, appName) { root.activateApp(appId, appName) }
  }

  // Tiling window adaptation: a transparent, input-less layer that reserves
  // the dock's footprint as a Wayland exclusive zone, so tiled windows never
  // overlap the dock. In auto-hide (overlay) mode the zone is always 0 so
  // tiled windows can use the full screen and the dock overlays them like
  // overlay behavior. A separate surface keeps the full-screen dockWindow (whose
  // coordinate space drag ghosts and tooltips rely on) untouched; the zone is
  // simply ignored on surfaces anchored to all four edges. When the dock is
  // hidden the spacer unmaps and tiled windows reclaim the space.
  PanelWindow {
    id: dockSpacerWindow
    visible: !root.conflictDetected && root.enabled && !root.autoHide
    screen: root.dockScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "paper-jam-84-dock-spacer"
    WlrLayershell.exclusiveZone: root.autoHide ? 0 : (root.enabled ? root.dockHeight + root.bottomMargin : 0)
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.dockHeight + root.bottomMargin
    mask: Region {}
  }

  // Edge hot-zone: a 3px invisible strip at the screen bottom that reveals
  // the dock even when it is fully slid off-screen and keeps it visible while
  // the cursor lingers at the edge. Using its own PanelWindow keeps
  // hit-testing alive while dockWindow's mask is off-screen or gapped (8px).
  // The timer adds a subtle 100ms debounce so accidental brushes don't pop
  // the dock, and edgeHovered participates in hide suppression like dockHovered.
  PanelWindow {
    id: edgeHotZone
    visible: !root.conflictDetected && root.enabled && root.autoHide && root.dockReady
    screen: root.dockScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "paper-jam-84-dock-edge"
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.edgeHeight
    mask: Region { item: edgeMouse }

    Item {
      id: edgeMouse
      anchors.fill: parent
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: {
          root.edgeHovered = true
          if (!root.autoHide) return
          if (root.autoHidden) showTimer.restart()
          else hideTimer.stop()
        }
        onExited: {
          root.edgeHovered = false
          showTimer.stop()
          // Leaving the edge while dock is still hidden cancels pending show.
          // Leaving while visible will arm hide via onEdgeHoveredChanged.
        }
      }
    }
  }

  // The dragged icon lives in its own overlay window so it can follow the
  // cursor anywhere on screen without clipping against the dock's mask. Its
  // input region is only the anchor, so it never blocks clicks. Position is
  // driven externally by the drag controller from the phantom's mouse events.
  PanelWindow {
    id: dragGhostWindow
    visible: root.ghostSource !== ""
    screen: root.dockScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "paper-jam-84-dock-drag"
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region { item: ghostAnchor }

    Item {
      id: ghostAnchor
      x: root.ghostX
      y: root.ghostY
      width: root.iconSize * root.ghostScale + 16
      height: root.iconSize * root.ghostScale + 16
      opacity: root.ghostOpacity
      Behavior on x { NumberAnimation { duration: 60; easing.type: Easing.Linear } }
      Behavior on y { NumberAnimation { duration: 60; easing.type: Easing.Linear } }
      Behavior on opacity { NumberAnimation { duration: 60; easing.type: Easing.Linear } }

      Rectangle {
        anchors.centerIn: parent
        width: parent.width - 4
        height: parent.height - 4
        radius: 0
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 2
      }

      PackAwareImage {
        anchors.centerIn: parent
        width: root.iconSize * root.ghostScale
        height: root.iconSize * root.ghostScale
        source: root.ghostSource
        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        asynchronous: true
      }
    }
  }
}
