import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "DockModel.js" as DockModel
import "IconResolver.js" as IconResolver
import "WindowLedger.js" as WindowLedger

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var manifest: null
  property var service: null
  property string home: Quickshell.env("HOME")
  property string iconDir: home + "/.config/omarchy/one-bit-bureau/icons"
  property string packDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/components/dock/assets/app-icons"
    : root.home + "/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau/components/dock/assets/app-icons"
  property var pinnedIds: []
  property var dockOrder: []
  property bool pinFileLoaded: false
  property bool settingsLoaded: false
  property int settingsMutationRevision: 0
  property int stateReaderSettingsRevision: 0
  property bool settingsWritePending: false
  property string pendingSettingsContent: ""
  property string pendingPinsContent: ""
  property var appEntries: []
  property var runningIds: []
  // Most-recently-used app ids, front = most recent. Maintained from focus
  // changes; powers the Alt+Tab switcher ordering (an app switcher cycles by
  // recency, not by the dock's pinned-first visual order).
  property var mruIds: []
  // Canonical per-app window truth for every dock surface. Each entry contains
  // ordered window records plus count, active, and workspace split metadata.
  // DockPanel exposes this map read-only for Experience/Inspector integration.
  property var windowLedger: ({})
  property var windowMruByApp: ({})
  property int windowStateRevision: 0
  property bool windowListOpen: false
  property point lastMenuPosition: Qt.point(0, 0)
  property int actionStatusSerial: 0
  property var lastActionStatus: ({
    serial: 0,
    action: "",
    state: "idle",
    appId: "",
    address: "",
    message: ""
  })
  property var actionObservation: null

  // Inspector integration stays narrow: the dock owns app/window truth and
  // asks its host to open the shared Inspector with a normalized context.
  signal inspectorRequested(var context, var invokingScreen, point invokingPosition)
  signal actionStatusReported(var status)
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
  readonly property bool reducedMotion: root.inlinePluginSetting("reducedMotion", false) === true
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
  property int edgeHeight: 6
  property int peekPx: 0
  // Hide is suppressed while any transient UI is active so the dock does not
  // vanish under a menu, preview, picker or drag.
  property bool hideSuppressed: root.menuOpen || root.pickerOpen || root.previewVisible || root.windowListOpen || root.floatingId !== "" || !!(root.altTab && root.altTab.active)
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
    : root.home + "/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau/components/dock/scripts/focus-window"
  property string focusRequestAppId: ""
  property var focusFallbackAddresses: []
  property var focusAttemptedAddresses: []
  property var queuedFocusRequest: null
  property string stateHelperPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/components/dock/scripts/one-bit-bureau-state"
    : root.home + "/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau/components/dock/scripts/one-bit-bureau-state"
  property string runHelperPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/components/dock/scripts/one-bit-bureau-run"
    : root.home + "/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau/components/dock/scripts/one-bit-bureau-run"

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
  property bool ghostGrayscale: false
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

  function inlinePluginSetting(name, fallback) {
    var config = root.shell && root.shell.shellConfig ? root.shell.shellConfig : null
    var pluginId = root.manifest && root.manifest.id
      ? String(root.manifest.id)
      : "io.github.regionallyfamous.one-bit-bureau"
    if (!config) return fallback
    var plugins = Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      var entry = plugins[i]
      if (entry && String(entry.id || "") === pluginId
          && entry[name] !== undefined && entry[name] !== null)
        return entry[name]
    }
    // One-Bit Bureau also provides the active-application bar widget. Its settings
    // UI writes inline values to bar.layout, so the coordinated dock reads the
    // same key there when the top-level plugin entry does not override it.
    var layout = config.bar && config.bar.layout ? config.bar.layout : ({})
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var rows = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
      for (var j = 0; j < rows.length; j++) {
        var widget = rows[j]
        if (widget && String(widget.id || "") === pluginId
            && widget[name] !== undefined && widget[name] !== null)
          return widget[name]
      }
    }
    return fallback
  }

  IpcHandler {
    target: "regionallyfamous.one-bit-bureau.dock"
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
    function getDockItemIds(): string {
      var values = []
      var limit = Math.min(root.dockItems.length, 64)
      for (var i = 0; i < limit; i++)
        values.push(String(root.dockItems[i] || "").slice(0, 160))
      return JSON.stringify(values)
    }
    function getReadyIconCount(): int { return root.readyIconCount() }
    function getNormalizedPackIconCount(): int { return root.normalizedPackIconCount() }
    function getIconSize(): int { return root.iconSize }
    function getMaxIconCenterOffset(): int { return Math.round(root.maxIconCenterOffset()) }
    function getIconReadyForApp(appId: string): bool {
      var id = String(appId || "").replace(/\.desktop$/, "").slice(0, 256)
      var delegate = root.delegateById[id]
      return !!(delegate && delegate.iconReady)
    }
    function getIconGrayscale(appId: string): bool { return root.iconUsesAutomaticNativeFallback(appId) }
    function getIconBounds(appId: string): string { return root.iconBounds(appId) }
    function getReducedMotion(): bool { return root.reducedMotion }
    function openManageIcons(): bool { return root.openIconManager() }
    function closeManageIcons(): bool { return root.closeIconManager() }
    function getIconPickerOpen(): bool { return iconPicker.open }
    function getIconPickerMode(): string { return String(iconPicker.mode || "") }
    function getMenuOpen(): bool { return dockMenu.opened }
    function getMenuCurrentIndex(): int { return dockMenu.currentIndex }
    function getMenuCurrentAction(): string { return dockMenu.currentAction() }
    function getWindowListOpen(): bool { return windowListPanel.opened }
    function getWindowListCount(): int { return windowListPanel.windowList.length }
    function getWindowCount(appId: string): int {
      return root.windowLedgerFor(String(appId || "").replace(/\.desktop$/, "")).count
    }
    function getLastActionStatus(): string { return JSON.stringify(root.lastActionStatus) }
    function getLastActionState(): string { return String(root.lastActionStatus.state || "idle") }
    function getLastActionKind(): string { return String(root.lastActionStatus.action || "") }
    function getLastActionAppId(): string { return String(root.lastActionStatus.appId || "") }
    function getIdentityForAddress(address: string): string {
      var candidate = root.liveWindowForAddress(address)
      return JSON.stringify(candidate ? identityController.resolveWindow(candidate) : ({
        id: "", method: "missing-address", ambiguous: false, candidates: []
      }))
    }
    function requestFocusForApp(appId: string): bool { return root.focusAppWindows(root.contextAppId({ appId: appId })) }
    function requestCloseForApp(appId: string): bool { return root.closeWindow(root.contextAppId({ appId: appId })) }
    function requestNewWindowForApp(appId: string): bool {
      var id = root.contextAppId({ appId: appId })
      return root.requestNewWindow(id, root.appNameFor(id))
    }
    function getAutoHidden(): bool { return root.autoHidden }
    function getEdgeHovered(): bool { return root.edgeHovered }
    function getAltTabActive(): bool { return altTab.active }
    function openMenuForApp(appId: string): bool { return root.openMenuForApp(appId) }
    function openWindowListForApp(appId: string): bool { return root.openWindowListForApp(appId) }
    function closeWindowList(): bool { windowListPanel.dismiss(); return true }
    function openMenuFirst(): bool {
      return root.dockItems.length > 0 ? root.openMenuForApp(String(root.dockItems[0])) : false
    }
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
    var settings = {
      autoHide: root.autoHide,
      screenName: root.preferredScreenName
    }
    var content = DockModel.serializeSettings(settings)
    root.settingsMutationRevision += 1
    root.settingsWritePending = true
    DockModel.markSettingsWritten(DockModel.serializeSettingsSnapshot(settings))
    root.pendingSettingsContent = content
    root.startSettingsWrite()
  }

  function startSettingsWrite() {
    if (settingsWriterProcess.running || !root.pendingSettingsContent)
      return
    var content = root.pendingSettingsContent
    root.pendingSettingsContent = ""
    settingsWriterProcess.command = [
      "python3", root.runHelperPath, "12000", "250", "0", "4096", "--",
      "python3", root.stateHelperPath, "write", "settings", content
    ]
    settingsWriterProcess.running = true
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
    var values = root.foreignToplevelValues()
    for (var i = 0; i < values.length; i++) {
      // The foreign-toplevel model is authoritative for membership. Enrich
      // each live object with Hyprland class metadata when available so
      // generated Chromium ids still resolve to their canonical launcher.
      var hyprlandWindow = root.hyprlandWindowFor(values[i])
      var id = hyprlandWindow
        ? root.dockIdForHyprlandWindow(hyprlandWindow)
        : root.desktopIdForWindow(values[i])
      if (id && output.indexOf(id) === -1) output.push(id)
    }
    return output
  }

  function foreignToplevelValues() {
    var output = []
    try {
      var values = ToplevelManager.toplevels.values
      for (var i = 0; i < values.length; i++) {
        if (values[i]) output.push(values[i])
      }
    } catch (error) {}
    return output
  }

  function hyprlandWindowIsLive(window) {
    if (!window) return false
    var ipc = window.lastIpcObject || {}
    // Quickshell can retain a Hyprland toplevel object for a short period
    // after its compositor client closes. The mapped flag is the authoritative
    // boundary: minimized and off-workspace windows remain mapped, while a
    // closed stale object must not keep a ghost application in the dock.
    return ipc.mapped !== false
  }

  function allLiveHyprlandWindows() {
    var output = []
    try {
      var values = Hyprland.toplevels.values
      for (var i = 0; i < values.length && output.length < 64; i++)
        if (root.hyprlandWindowIsLive(values[i])) output.push(values[i])
    } catch (error) {}
    return output
  }

  function currentWorkspaceDescriptor() {
    var workspace = Hyprland.focusedWorkspace
    return workspace ? {
      id: Number(workspace.id || 0),
      name: String(workspace.name || "")
    } : null
  }

  function activeWindowAddress() {
    var active = Hyprland.activeToplevel
    return WindowLedger.normalizeAddress(active && active.address)
  }

  function liveWindowForAddress(address, expectedAppId) {
    var wantedAddress = WindowLedger.normalizeAddress(address)
    var wantedApp = identityController.normalizeId(expectedAppId || "")
    if (!wantedAddress) return null
    var values = root.liveHyprlandWindows()
    for (var i = 0; i < values.length; i++) {
      var candidate = values[i]
      if (WindowLedger.normalizeAddress(candidate && candidate.address) !== wantedAddress) continue
      // Re-resolve immediately before every dispatch. An address can be reused
      // after a close, so matching the address without stable identity is not
      // sufficient when the caller knows which application it targeted.
      if (wantedApp && root.dockIdForHyprlandWindow(candidate) !== wantedApp) return null
      return candidate
    }
    return null
  }

  function allLedgerWindows() {
    var output = []
    var ledger = root.windowLedger || ({})
    for (var appId in ledger) {
      var windows = ledger[appId] && Array.isArray(ledger[appId].windows)
        ? ledger[appId].windows : []
      for (var i = 0; i < windows.length && output.length < 256; i++)
        output.push(windows[i])
      if (output.length >= 256) break
    }
    return output
  }

  function reportActionStatus(action, state, appId, address, message) {
    root.actionStatusSerial++
    root.lastActionStatus = {
      serial: root.actionStatusSerial,
      action: String(action || "").slice(0, 32),
      state: String(state || "failed").slice(0, 16),
      appId: identityController.normalizeId(appId || ""),
      address: WindowLedger.normalizeAddress(address),
      message: String(message || "").slice(0, 240)
    }
    root.actionStatusReported(root.lastActionStatus)
    return root.lastActionStatus
  }

  function beginActionObservation(action, appId, address, beforeAddresses, requestedMessage) {
    actionObservationTimer.stop()
    var status = root.reportActionStatus(
      action, "requested", appId, address, requestedMessage)
    root.actionObservation = {
      serial: status.serial,
      action: status.action,
      appId: status.appId,
      address: status.address,
      beforeAddresses: (beforeAddresses || []).slice(0, 64)
    }
    actionObservationTimer.restart()
    root.observeActionPostcondition()
  }

  function observeActionPostcondition() {
    var observation = root.actionObservation
    if (!observation || observation.serial !== root.lastActionStatus.serial) return false
    var windows = root.allLedgerWindows()
    var observed = false
    var message = ""
    if (observation.action === "focus") {
      observed = WindowLedger.focusObserved(
        windows, root.activeWindowAddress(), observation.appId, observation.address)
      message = "Window focus observed."
    } else if (observation.action === "close") {
      observed = WindowLedger.closeObserved(windows, observation.address, observation.appId)
      message = "Window closure observed."
    } else if (observation.action === "new-window") {
      observed = WindowLedger.newWindowObserved(
        observation.beforeAddresses, windows, observation.appId)
      message = "New window observed."
    } else if (observation.action === "open") {
      observed = WindowLedger.newWindowObserved(
        observation.beforeAddresses, windows, observation.appId)
      message = "Application window observed."
    }
    if (!observed) return false
    actionObservationTimer.stop()
    root.actionObservation = null
    root.reportActionStatus(
      observation.action, "observed", observation.appId, observation.address, message)
    return true
  }

  function emptyWindowLedger() {
    return {
      count: 0,
      countLabel: "0",
      active: false,
      currentWorkspaceCount: 0,
      otherWorkspaceCount: 0,
      windows: []
    }
  }

  function windowLedgerFor(id) {
    // Make bindings that call this function depend on ledger replacement.
    var ledger = root.windowLedger
    return ledger && ledger[id] ? ledger[id] : root.emptyWindowLedger()
  }

  function rawWindowsForApp(id) {
    var output = []
    var wanted = String(id || "")
    try {
      var values = root.liveHyprlandWindows()
      for (var i = 0; i < values.length; i++) {
        var candidate = values[i]
        if (root.dockIdForHyprlandWindow(candidate) !== wanted) continue
        var ipc = candidate.lastIpcObject || {}
        var workspace = candidate.workspace || ipc.workspace || null
        var position = root.array2(ipc.at)
        var size = root.array2(ipc.size)
        var address = WindowLedger.normalizeAddress(candidate.address)
        output.push({
          appId: wanted,
          address: address,
          title: String(candidate.title || ""),
          active: address !== "" && address === root.activeWindowAddress(),
          mapped: ipc.mapped !== false,
          minimized: !!ipc.minimized,
          pinned: ipc.pinned === true,
          workspaceId: workspace ? Number(workspace.id || 0) : 0,
          workspaceName: workspace ? String(workspace.name || "") : "",
          x: position[0] || 0,
          y: position[1] || 0,
          w: size[0] || 0,
          h: size[1] || 0,
          waylandToplevel: candidate.wayland || null
        })
      }
    } catch (error) {}
    return output
  }

  function rebuildWindowLedger() {
    var grouped = {}
    try {
      var values = root.liveHyprlandWindows()
      for (var i = 0; i < values.length; i++) {
        var candidate = values[i]
        var id = root.dockIdForHyprlandWindow(candidate)
        if (!id) continue
        if (!grouped[id]) grouped[id] = []
        var ipc = candidate.lastIpcObject || {}
        var workspace = candidate.workspace || ipc.workspace || null
        var position = root.array2(ipc.at)
        var size = root.array2(ipc.size)
        var address = WindowLedger.normalizeAddress(candidate.address)
        grouped[id].push({
          appId: id,
          address: address,
          title: String(candidate.title || ""),
          active: address !== "" && address === root.activeWindowAddress(),
          mapped: ipc.mapped !== false,
          minimized: !!ipc.minimized,
          pinned: ipc.pinned === true,
          workspaceId: workspace ? Number(workspace.id || 0) : 0,
          workspaceName: workspace ? String(workspace.name || "") : "",
          x: position[0] || 0,
          y: position[1] || 0,
          w: size[0] || 0,
          h: size[1] || 0,
          waylandToplevel: candidate.wayland || null
        })
      }
    } catch (error) {}

    var currentWorkspace = root.currentWorkspaceDescriptor()
    var activeAddress = root.activeWindowAddress()
    var next = {}
    for (var appId in grouped) {
      var ordered = WindowLedger.orderWindows(
        grouped[appId], root.windowMruByApp[appId] || [], currentWorkspace, activeAddress)
      for (var j = 0; j < ordered.length; j++) {
        ordered[j].onCurrentWorkspace = WindowLedger.sameWorkspace(ordered[j], currentWorkspace)
        ordered[j].workspaceLabel = WindowLedger.workspaceLabel(ordered[j])
      }
      next[appId] = WindowLedger.summarizeWindows(ordered, currentWorkspace, activeAddress)
    }
    root.windowLedger = next
    root.windowStateRevision++
    root.observeActionPostcondition()

    if (root.previewAppId) {
      var previewLedger = root.windowLedgerFor(root.previewAppId)
      if (!previewLedger.count) root.hidePreview()
      else root.previewWindows = previewLedger.windows
    }
    if (windowListPanel.opened) {
      var listLedger = root.windowLedgerFor(windowListPanel.appId)
      windowListPanel.windowList = listLedger.windows
    }
  }

  function desktopIdForWindow(window) {
    return identityController.resolveInput({
      desktopId: window && window.desktopId,
      appId: window && window.appId,
      className: window && window.className,
      initialClass: window && window.initialClass
    }).id
  }

  function hyprlandWindowFor(window, excludedAddresses) {
    var targetId = String(window.appId || window.desktopId || window.className || window.initialClass || "").toLowerCase()
    var targetTitle = String(window.title || "")
    var idFallback = null
    var targetIdentity = identityController.resolveInput({
      desktopId: window.desktopId,
      appId: window.appId,
      className: window.className,
      initialClass: window.initialClass
    }).id
    var excluded = Array.isArray(excludedAddresses) ? excludedAddresses : []
    try {
      var values = Hyprland.toplevels.values
      for (var i = 0; i < values.length; i++) {
        var candidate = values[i]
        if (!root.hyprlandWindowIsLive(candidate)) continue
        var address = WindowLedger.normalizeAddress(candidate.address)
        if (address && excluded.indexOf(address) !== -1) continue
        if (candidate.wayland === window) return candidate
        var ids = []
        if (candidate.wayland && candidate.wayland.appId) ids.push(String(candidate.wayland.appId).toLowerCase())
        var ipc = candidate.lastIpcObject || {}
        if (ipc.appId) ids.push(String(ipc.appId).toLowerCase())
        if (ipc["class"]) ids.push(String(ipc["class"]).toLowerCase())
        if (ipc.initialClass) ids.push(String(ipc.initialClass).toLowerCase())
        var idMatches = targetId !== "" && ids.indexOf(targetId) !== -1
        var titleMatches = targetTitle !== "" && String(candidate.title || "") === targetTitle
        if (idMatches && titleMatches) return candidate
        var candidateIdentity = identityController.resolveWindow(candidate).id
        if (targetIdentity && candidateIdentity === targetIdentity) {
          if (titleMatches) return candidate
          if (!idFallback) idFallback = candidate
        }
        if (idMatches && !idFallback) idFallback = candidate
      }
    } catch (error) {}
    // Never bridge on title alone. Titles are mutable content, not application
    // identity, and equal-title windows from unrelated apps must remain apart.
    return idFallback
  }

  function liveHyprlandWindows() {
    var output = []
    var seenAddresses = []
    var values = root.foreignToplevelValues()
    for (var i = 0; i < values.length; i++) {
      var candidate = root.hyprlandWindowFor(values[i], seenAddresses)
      if (!candidate) continue
      var address = WindowLedger.normalizeAddress(candidate.address)
      if (address && seenAddresses.indexOf(address) !== -1) continue
      if (address) seenAddresses.push(address)
      output.push(candidate)
    }
    return output
  }

  function hyprlandWindowForItem(item) {
    if (!item) return null
    var fallback = null
    try {
      var values = root.liveHyprlandWindows()
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

  function startNextFocusAttempt() {
    if (!root.focusFallbackAddresses.length) {
      if (root.focusRequestAppId)
        root.reportActionStatus("focus", "failed", root.focusRequestAppId, "",
          "No current window could be resolved for focus.")
      root.finishFocusRequest()
      return false
    }
    var addresses = root.focusFallbackAddresses.slice()
    var normalized = WindowLedger.normalizeAddress(addresses.shift())
    root.focusFallbackAddresses = addresses
    if (!normalized) return root.startNextFocusAttempt()

    var candidate = root.liveWindowForAddress(normalized, root.focusRequestAppId)
    if (!candidate) return root.startNextFocusAttempt()
    var currentAppId = root.dockIdForHyprlandWindow(candidate)
    if (!root.focusRequestAppId) root.focusRequestAppId = currentAppId

    // This Omarchy build uses Hyprland's Lua dispatcher syntax. The older
    // `workspace ...` / `focuswindow ...` strings are parsed as Lua and fail.
    // Focusing by address also switches to the window's workspace without
    // going through Toplevel.activate(), which can warp the pointer.
    var attempted = root.focusAttemptedAddresses.slice()
    attempted.push(normalized)
    root.focusAttemptedAddresses = attempted
    root.beginActionObservation(
      "focus", root.focusRequestAppId, normalized, [], "Focus requested.")
    focusWindowProcess.command = [
      "python3", root.runHelperPath, "3000", "250", "0", "8192", "--",
      "bash", root.focusHelperPath, normalized
    ]
    focusWindowProcess.running = true
    return true
  }

  function finishFocusRequest() {
    root.focusRequestAppId = ""
    root.focusFallbackAddresses = []
    root.focusAttemptedAddresses = []
    var queued = root.queuedFocusRequest
    root.queuedFocusRequest = null
    if (queued)
      Qt.callLater(function() { root.focusWindowAddresses(queued.appId, queued.addresses) })
  }

  function focusWindowAddresses(appId, addresses) {
    var clean = []
    for (var i = 0; i < (addresses || []).length; i++) {
      var address = WindowLedger.normalizeAddress(addresses[i])
      if (address && clean.indexOf(address) === -1) clean.push(address)
    }
    if (!clean.length) return false
    var request = { appId: String(appId || ""), addresses: clean }
    if (focusWindowProcess.running || root.focusFallbackAddresses.length) {
      // Last request wins while the helper is restoring cursor state. This
      // remains a focus request; it is never converted into an app launch.
      root.queuedFocusRequest = request
      return true
    }
    root.focusRequestAppId = request.appId
    root.focusFallbackAddresses = request.addresses
    root.focusAttemptedAddresses = []
    return root.startNextFocusAttempt()
  }

  function focusWindowAddress(address, expectedAppId) {
    return root.focusWindowAddresses(expectedAppId || "", [address])
  }

  function focusExistingWindow(hyprWindow) {
    if (!hyprWindow || !hyprWindow.address) return false
    return root.focusWindowAddress(
      hyprWindow.address, root.dockIdForHyprlandWindow(hyprWindow))
  }

  function focusAppWindows(appId) {
    var canonical = root.contextAppId({ appId: appId })
    if (!canonical) return false
    var ledger = root.windowLedgerFor(canonical)
    if (!ledger.count) {
      // Hyprland and the foreign-toplevel protocol may update on adjacent
      // frames. Re-read once, but do not launch merely because resolution is
      // temporarily stale.
      root.rebuildWindowLedger()
      ledger = root.windowLedgerFor(canonical)
    }
    if (!ledger.count) {
      root.reportActionStatus("focus", "failed", canonical, "",
        "No current window could be resolved for focus.")
      return false
    }
    return root.focusWindowAddresses(canonical, WindowLedger.focusAddresses(ledger.windows))
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
      console.warn("one-bit-bureau: app library refresh failed", error)
    }
    refreshItems()
  }

  function refreshItems() {
    root.runningIds = normalizeRunning()
    root.rebuildWindowLedger()
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

  function maxIconCenterOffset() {
    var maximum = 0
    for (var id in root.delegateById) {
      var delegate = root.delegateById[id]
      if (delegate)
        maximum = Math.max(maximum, Math.abs(delegate.iconCenterOffset))
    }
    return maximum
  }

  function iconBounds(appId) {
    var id = String(appId || "").replace(/\.desktop$/, "").slice(0, 256)
    var delegate = root.delegateById[id]
    if (!delegate || !delegate.focusTarget) return ""
    var target = delegate.focusTarget
    var point = target.mapToItem(null, 0, 0)
    return [
      Math.round(point.x),
      Math.round(point.y),
      Math.round(target.width),
      Math.round(target.height)
    ].join(",")
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
    if (!conflictNotificationProcess.running)
      conflictNotificationProcess.running = true
  }

  function handleClick(item) {
    if (!item) return false
    var id = root.contextAppId({ appId: item.id })
    if (!id) return false
    if (item.running || root.appIsRunning(id)) {
      // Never fall back to launch for a known-running app. The compositor and
      // foreign-toplevel feeds can differ for a frame; a duplicate process is
      // worse than a focus request that safely does nothing and can be retried.
      var focused = root.focusAppWindows(id)
      if (!focused)
        console.warn("regionallyfamous.one-bit-bureau.dock: running window state is not focusable yet for " + id)
      return focused
    }
    return root.requestLaunch(id, item.name, "open")
  }

  function appIsRunning(appId) {
    var id = root.contextAppId({ appId: appId })
    if (!id) return false
    // Preserve positive truth from the previous authoritative snapshot while
    // re-reading the current foreign-toplevel set. A transient empty bridge
    // may delay an open, but it must never cause a duplicate launch.
    if (root.runningIds.indexOf(id) !== -1) return true
    return root.normalizeRunning().indexOf(id) !== -1
  }

  function requestLaunch(appId, name, action) {
    var id = root.contextAppId({ appId: appId })
    var kind = action === "new-window" ? "new-window" : "open"
    if (!id) return false
    root.rebuildWindowLedger()
    var before = WindowLedger.focusAddresses(root.windowLedgerFor(id).windows)
    var entry = DockModel.entryFor(id, root.appEntries)
    var label = name || (entry && entry.name) || id
    if (!root.shell || !root.shell.appLibrary
        || typeof root.shell.appLibrary.launch !== "function") {
      root.reportActionStatus(kind, "failed", id, "", "Application launch is unavailable.")
      return false
    }
    root.beginActionObservation(
      kind, id, "", before,
      kind === "new-window" ? "New window requested." : "Open requested.")
    root.shell.appLibrary.launch(id, label)
    return true
  }

  function requestNewWindow(appId, name) {
    return root.requestLaunch(appId, name, "new-window")
  }

  // ---- Alt+Tab app switcher -------------------------------------------------
  // The switcher is an app switcher, so recency is tracked per application
  // (not per window). The dock's visual order (pinned first) is irrelevant
  // here: focus history drives the cycle order.

  function dockIdForHyprlandWindow(window) {
    try {
      return identityController.resolveWindow(window).id
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

  function touchWindowMru(id, address) {
    if (!id || !address) return
    root.windowMruByApp = WindowLedger.touchMru(root.windowMruByApp, id, address, 32)
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
    var canonical = root.contextAppId({ appId: id })
    if (!canonical) return false
    if (root.appIsRunning(canonical)) {
      var focused = root.focusAppWindows(canonical)
      if (!focused)
        console.warn("regionallyfamous.one-bit-bureau.dock: app switch target is not focusable yet for " + canonical)
      return focused
    }
    return root.requestLaunch(canonical, name, "open")
  }

  Process {
    id: focusWindowProcess
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 && root.focusFallbackAddresses.length) {
        Qt.callLater(root.startNextFocusAttempt)
        return
      }
      if (exitCode !== 0 && root.focusRequestAppId) {
        console.warn("regionallyfamous.one-bit-bureau.dock: all focus candidates became stale for " + root.focusRequestAppId)
        actionObservationTimer.stop()
        root.actionObservation = null
        root.reportActionStatus("focus", "failed", root.focusRequestAppId, "",
          "All focus candidates became stale before dispatch completed.")
      }
      root.finishFocusRequest()
    }
  }

  Timer {
    id: actionObservationTimer
    interval: 1400
    repeat: false
    onTriggered: {
      var observation = root.actionObservation
      if (!observation || observation.serial !== root.lastActionStatus.serial) return
      root.actionObservation = null
      root.reportActionStatus(
        observation.action, "requested", observation.appId, observation.address,
        "Action requested; confirmation was not observed.")
    }
  }

  function savePinned() {
    var content = DockModel.serializePinned(root.pinnedIds, root.dockOrder)
    DockModel.markWritten(content)
    root.pendingPinsContent = content
    root.startPinsWrite()
  }

  function startPinsWrite() {
    if (pinsWriterProcess.running || !root.pendingPinsContent)
      return
    var content = root.pendingPinsContent
    root.pendingPinsContent = ""
    pinsWriterProcess.command = [
      "python3", root.runHelperPath, "12000", "250", "0", "4096", "--",
      "python3", root.stateHelperPath, "write", "pins", content
    ]
    pinsWriterProcess.running = true
  }

  function openMenu(item, position, returnFocusItem) {
    root.tooltipItem = null
    root.hidePreview()
    if (windowListPanel.opened) windowListPanel.dismiss()
    root.menuOpen = true
    root.lastMenuPosition = Qt.point(position.x, position.y)
    dockMenu.itemData = item
    dockMenu.returnFocusItem = returnFocusItem || null
    dockMenu.requestedPosition = Qt.point(position.x, position.y - dockMenu.height - 12)
    dockMenu.opened = true
  }

  function openMenuForApp(appId) {
    var id = String(appId || "").replace(/\.desktop$/, "").slice(0, 256)
    var delegate = root.delegateById[id]
    if (!delegate || !delegate.focusTarget) return false
    root.enabled = true
    root.autoHidden = false
    delegate.focusTarget.forceActiveFocus()
    root.openMenu(
      delegate.liveData,
      delegate.focusTarget.mapToItem(null, delegate.focusTarget.width / 2, 0),
      delegate.focusTarget
    )
    return true
  }

  function inspectorContextForApp(appId) {
    var id = String(appId || "").replace(/\.desktop$/, "").slice(0, 256)
    var entry = DockModel.entryFor(id, root.appEntries) || ({})
    var ledger = root.windowLedgerFor(id)
    var name = entry.name || entry.displayName || id || "Application"
    var pinned = root.pinnedIds.indexOf(id) !== -1
    var running = root.runningIds.indexOf(id) !== -1
    return {
      kind: "app",
      id: id,
      name: name,
      subtitle: running
        ? (ledger.count === 1 ? "1 window" : ledger.count + " windows")
        : "Not running",
      iconSource: root.iconSourceFor(id),
      iconGrayscale: root.iconUsesAutomaticNativeFallback(id),
      facts: [
        { id: "pinned", label: "Dock", value: pinned ? "Pinned" : "Not pinned" },
        { id: "running", label: "State", value: running ? (ledger.active ? "Active" : "Running") : "Not running" },
        { id: "windows", label: "Windows", value: String(ledger.count) },
        { id: "currentWorkspace", label: "This workspace", value: String(ledger.currentWorkspaceCount) },
        { id: "otherWorkspaces", label: "Other workspaces", value: String(ledger.otherWorkspaceCount) }
      ],
      actions: [
        { id: "activate", label: running ? "Activate" : "Open", enabled: true },
        { id: "new-window", label: "New Window", enabled: true },
        {
          id: "show-windows",
          label: "Show Windows",
          enabled: ledger.count > 0,
          reason: ledger.count > 0 ? "" : "No windows are open."
        },
        {
          id: "close",
          label: "Close Recent Window",
          enabled: ledger.count > 0,
          reason: ledger.count > 0 ? "" : "No windows are open.",
          destructive: true
        },
        { id: "toggle-pin", label: pinned ? "Unpin from Dock" : "Pin to Dock", enabled: true },
        { id: "set-icon", label: "Change Icon", enabled: true }
      ]
    }
  }

  function requestInspector(item) {
    if (!item || !item.id) return false
    root.menuOpen = false
    dockMenu.opened = false
    root.hidePreview()
    root.inspectorRequested(
      root.inspectorContextForApp(item.id),
      root.dockScreen,
      root.lastMenuPosition)
    return true
  }

  function contextAppId(context) {
    var value = context || {}
    var raw = identityController.normalizeId(value.appId || value.desktopId || value.id || "")
    if (!raw) return ""
    var resolved = identityController.resolveInput({
      desktopId: value.desktopId || raw,
      appId: value.appId || "",
      className: value.className || "",
      initialClass: value.initialClass || "",
      processName: value.processName || "",
      executable: value.executable || ""
    }).id
    if (root.delegateById[resolved] || root.runningIds.indexOf(resolved) !== -1 || root.pinnedIds.indexOf(resolved) !== -1)
      return resolved
    for (var i = 0; i < root.appEntries.length; i++) {
      var entry = root.appEntries[i] || {}
      var id = String(entry.id || entry.desktopId || "").replace(/\.desktop$/, "")
      if (id.toLowerCase() === raw.toLowerCase()) return id
    }
    return resolved || raw
  }

  // Called by the shared Inspector host after actionRequested. App identity is
  // always re-resolved here so a stale context cannot act on an old delegate.
  function performInspectorAction(actionId, context) {
    var action = String(actionId || "")
    var id = root.contextAppId(context)
    if (!id) return false
    var item = root.inspectorContextForApp(id)
    if (action === "open" || action === "activate" || action === "dock.activate") {
      return root.handleClick({ id: id, name: item.name, running: item.running })
    }
    if (action === "new-window" || action === "newWindow" || action === "dock.new-window") {
      return root.requestNewWindow(id, item.name)
    }
    if (action === "show-windows" || action === "showWindows" || action === "dock.show-windows")
      return root.openWindowListForApp(id)
    if (action === "close" || action === "close-window" || action === "dock.close-window")
      return root.closeWindow(id)
    if (action === "toggle-pin" || action === "togglePin" || action === "dock.toggle-pin") {
      root.pinnedIds = DockModel.togglePinned(root.pinnedIds, id)
      root.refreshItems()
      root.savePinned()
      return true
    }
    if (action === "set-icon" || action === "setIcon" || action === "dock.set-icon") {
      root.openIconPicker(id, item.name, false)
      return true
    }
    return false
  }

  function openWindowList(item, position, returnFocusItem) {
    if (!item || !item.id) return false
    root.rebuildWindowLedger()
    var ledger = root.windowLedgerFor(item.id)
    if (!ledger.count) return false
    root.hidePreview()
    root.menuOpen = false
    dockMenu.opened = false
    root.windowListOpen = true
    windowListPanel.appId = item.id
    windowListPanel.appName = item.name || root.appNameFor(item.id)
    windowListPanel.windowList = ledger.windows
    windowListPanel.returnFocusItem = returnFocusItem || null
    windowListPanel.requestedPosition = position || Qt.point(dockWindow.width / 2, dockWindow.height - root.dockHeight)
    windowListPanel.opened = true
    return true
  }

  function openWindowListForApp(appId) {
    var id = String(appId || "").replace(/\.desktop$/, "").slice(0, 256)
    var delegate = root.delegateById[id]
    var focusItem = delegate && delegate.focusTarget ? delegate.focusTarget : null
    var position = focusItem
      ? focusItem.mapToItem(null, focusItem.width / 2, 0)
      : Qt.point(dockWindow.width / 2, dockWindow.height - root.dockHeight)
    root.enabled = true
    root.autoHidden = false
    if (focusItem) focusItem.forceActiveFocus()
    return root.openWindowList({ id: id, name: root.appNameFor(id) }, position, focusItem)
  }

  function menuAction(action, item) {
    if (action === "toggleAutoHide") {
      root.autoHide = !root.autoHide
      root.saveSettings()
      return
    }
    if (!item) return
    if (action === "togglePin") root.pinnedIds = DockModel.togglePinned(root.pinnedIds, item.id)
    else if (action === "newWindow") root.requestNewWindow(item.id, item.name)
    else if (action === "close") closeWindow(item.id)
    else if (action === "inspect") root.requestInspector(item)
    else if (action === "showWindows") root.openWindowList(item, root.lastMenuPosition, dockMenu.returnFocusItem)
    else if (action === "setIcon") root.openIconPicker(item.id, item.name, false)
    else if (action === "manageIcons") root.openIconManager()
    if (action === "togglePin") { refreshItems(); savePinned() }
  }

  function openIconPicker(appId, appName, fromManage) {
    root.menuOpen = false
    dockMenu.opened = false
    root.pickerOpen = true
    root.hidePreview()
    iconPicker.openForApp(appId, appName, fromManage)
  }

  function openIconManager() {
    root.menuOpen = false
    dockMenu.opened = false
    root.pickerOpen = true
    root.hidePreview()
    iconPicker.openManage()
    return true
  }

  function closeIconManager() {
    iconPicker.close()
    root.pickerOpen = false
    return true
  }

  function closeWindowData(data, expectedAppId) {
    if (!data) return false
    var address = WindowLedger.normalizeAddress(data.address)
    var appId = root.contextAppId({ appId: expectedAppId || data.appId || "" })
    if (!address || !appId) return false
    var candidate = root.liveWindowForAddress(address, appId)
    if (!candidate) {
      root.reportActionStatus("close", "failed", appId, address,
        "The selected window became stale before close could be requested.")
      return false
    }
    var wayland = candidate.wayland
    if (wayland && typeof wayland.close === "function") {
      root.beginActionObservation("close", appId, address, [], "Close requested.")
      wayland.close()
      return true
    }
    root.reportActionStatus("close", "failed", appId, address,
      "The current window does not expose a close action.")
    return false
  }

  function closeWindow(id) {
    var appId = root.contextAppId({ appId: id })
    if (!appId) return false
    root.rebuildWindowLedger()
    var ledger = root.windowLedgerFor(appId)
    if (ledger.windows.length) return root.closeWindowData(ledger.windows[0], appId)
    root.reportActionStatus("close", "failed", appId, "",
      "No current window could be resolved for close.")
    return false
  }

  // Drag controller ---------------------------------------------------------
  function onDragMoved(item, position, surfacePosition) {
    if (!root.floatingId) {
      root.floatingId = item.id
      root.tempDrag = { id: item.id, index: -1 }
      root.ghostSource = root.iconSourceFor(item)
      root.ghostGrayscale = root.iconUsesAutomaticNativeFallback(item)
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
    console.log("one-bit-bureau finishDrag", JSON.stringify({ id: id, inside: inside, localX: surfacePosition.x, localY: surfacePosition.y, surfaceW: dockSurface.width, surfaceH: dockSurface.height, cursorX: root.cursorXInRow() }))
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
      console.log("one-bit-bureau reorder", JSON.stringify({ id: id, idx: idx, wasPinned: wasPinned, dockOrderBefore: root.dockOrder, newOrder: newOrder, pinnedBefore: root.pinnedIds, runningIds: root.runningIds }))
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
    root.ghostGrayscale = false
    } catch (error) {
      console.warn("one-bit-bureau finishDrag error", error)
      root.floatingId = ""
      root.tempDrag = { id: "", index: -1 }
      root.refreshItems()
      ghostHideTimer.stop()
      root.ghostSettling = false
      root.ghostOpacity = 1
      root.ghostScale = 1.18
      root.ghostSource = ""
      root.ghostGrayscale = false
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

  function tooltipTextFor(item) {
    if (!item) return ""
    var name = item.name || item.id
    var count = Number(item.windowCount || 0)
    if (!count) return name
    var state = count + (count === 1 ? " window" : " windows")
    var here = Number(item.currentWorkspaceWindowCount || 0)
    var elsewhere = Number(item.otherWorkspaceWindowCount || 0)
    if (here && elsewhere) state += " · " + here + " here, " + elsewhere + " elsewhere"
    else if (elsewhere) state += " · other workspace"
    else state += " · current workspace"
    return name + " · " + state
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
    var ledger = root.windowLedgerFor(id)
    if (!ledger.count) {
      root.rebuildWindowLedger()
      ledger = root.windowLedgerFor(id)
    }
    return ledger.windows.slice()
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
    root.focusWindowAddress(data.address, data.appId || root.previewAppId)
  }

  function loadCustomIcons(content) {
    var parsed = {}
    try {
      var value = JSON.parse(String(content || "{}"))
      if (value && typeof value === "object" && !Array.isArray(value)) parsed = value
    } catch (error) {
      console.warn("one-bit-bureau: invalid dock-icons.json")
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

  function iconIdentityFor(id, entry) {
    return {
      id: id,
      desktopId: entry.desktopId,
      name: entry.name,
      displayName: entry.displayName,
      icon: entry.icon,
      iconName: entry.iconName,
      appIcon: entry.appIcon
    }
  }

  // Automatic matching is the authored One-Bit path. Every fresh Omarchy app
  // has a role; uncommon apps retain a grayscale native icon when one resolves,
  // then fall back to the bundled Application mark instead of a blank slot.
  // Custom files, manual pack choices, and explicit Native remain untouched.
  function iconUsesAutomaticNativeFallback(item) {
    var id = typeof item === "string" ? item : item && item.id
    if (!id) return false
    var entry = DockModel.entryFor(id, root.appEntries)
    return IconResolver.iconPresentationMode(
      root.customIcons,
      root.iconIdentityFor(id, entry)
    ) === "native-grayscale"
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
    var packRole = manualPack || (!nativeOnly
      ? IconResolver.automaticPackRole(root.iconIdentityFor(id, entry))
      : "")
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
    return Util.fileUrl(root.packDir + "/application.png")
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

  function applyStateSnapshot(content, settingsRevision) {
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

    // A state read may have started before an IPC/UI settings mutation. Never
    // let that stale snapshot roll the user's choice back while the atomic
    // settings write is landing on disk.
    var settingsSnapshotIsCurrent = Number(settingsRevision) === root.settingsMutationRevision
      && !root.settingsWritePending
    if (settingsSnapshotIsCurrent) {
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
  }

  function reloadBoundedState() {
    if (stateReaderProcess.running || root.settingsWritePending || !root.stateHelperPath || !root.runHelperPath) return
    root.stateReaderSettingsRevision = root.settingsMutationRevision
    stateReaderProcess.command = [
      "python3", root.runHelperPath, "12000", "250", "262144", "4096", "--",
      "python3", root.stateHelperPath, "read", "dock"
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
    interval: 12500
    onTriggered: {
      if (stateReaderProcess.running) stateReaderProcess.running = false
    }
  }

  Process {
    id: stateReaderProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStateSnapshot(text, root.stateReaderSettingsRevision)
    }
    onExited: stateReaderDeadline.stop()
  }

  Process {
    id: pinsWriterProcess
    onExited: {
      root.refreshItems()
      if (root.pendingPinsContent)
        Qt.callLater(root.startPinsWrite)
      else
        Qt.callLater(root.reloadBoundedState)
    }
  }

  Process {
    id: settingsWriterProcess
    onExited: {
      if (root.pendingSettingsContent) {
        Qt.callLater(root.startSettingsWrite)
      } else {
        root.settingsWritePending = false
        Qt.callLater(root.reloadBoundedState)
      }
    }
  }

  Connections {
    target: root.shell ? root.shell.appLibrary : null
    function onAppsChanged() { root.refreshApps() }
  }

  // Compositor and foreign-toplevel membership notifications can be
  // coalesced when several windows map in the same frame. Periodically
  // reconcile both bounded models so a missed edge converges without a shell
  // restart; normal event-driven updates remain immediate.
  Timer {
    id: compositorReconcileTimer
    interval: 2000
    running: root.enabled && root.dockReady
    repeat: true
    onTriggered: {
      Hyprland.refreshToplevels()
      root.refreshItems()
    }
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      var active = Hyprland.activeToplevel
      var mruId = root.dockIdForHyprlandWindow(active)
      if (mruId) {
        root.touchMru(mruId)
        root.touchWindowMru(mruId, active && active.address)
      }
      root.rebuildWindowLedger()
    }
    function onFocusedWorkspaceChanged() { root.rebuildWindowLedger() }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      identityController.refreshProcesses(root.allLiveHyprlandWindows())
      root.refreshItems()
    }
  }

  Instantiator {
    model: Hyprland.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onWorkspaceChanged() { root.rebuildWindowLedger() }
      function onLastIpcObjectChanged() { root.refreshItems() }
      function onTitleChanged() { root.rebuildWindowLedger() }
      function onWaylandHandleChanged() { root.rebuildWindowLedger() }
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      // lastIpcObject is a snapshot. Refresh it when the authoritative
      // foreign-toplevel set changes so generated app ids can be compared
      // with Hyprland's live class and initialClass before dock aggregation.
      Hyprland.refreshToplevels()
      root.refreshItems()
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
    identityController.refreshProcesses(root.allLiveHyprlandWindows())
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
    pinsWriterProcess.running = false
    settingsWriterProcess.running = false
    layerRuleProcess.running = false
    focusWindowProcess.running = false
    conflictNotificationProcess.running = false
    actionObservationTimer.stop()
  }

  Process {
    id: layerRuleProcess
    command: [
      "python3", root.runHelperPath, "2000", "200", "0", "4096", "--",
      "hyprctl", "eval", "hl.layer_rule({ match = { namespace = \"one-bit-bureau-dock-alt-tab\" }, no_anim = true, animation = \"none\" })"
    ]
  }

  Process {
    id: conflictNotificationProcess
    command: [
      "python3", root.runHelperPath, "2000", "200", "0", "4096", "--",
      "omarchy-shell", "notify", "One-Bit Bureau Dock is disabled because rosakodu.dock is enabled"
    ]
  }

  PanelWindow {
    id: dockWindow
    visible: !root.conflictDetected && root.enabled
    screen: root.dockScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "one-bit-bureau-dock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
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
        enabled: !root.reducedMotion
        NumberAnimation { duration: 90; easing.type: Easing.Linear }
      }
      Behavior on anchors.bottomMargin {
        enabled: !root.reducedMotion
        NumberAnimation { duration: root.autoHidden ? root.hideDuration : root.showDuration; easing.type: Easing.Linear }
      }
      Behavior on opacity {
        enabled: !root.reducedMotion
        NumberAnimation { duration: 60; easing.type: Easing.Linear }
      }

      Item {
        id: dockRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 0
        width: root.layoutWidth - 2 * root.sidePadding
        height: root.iconSize + 16

        Behavior on width {
          enabled: !root.reducedMotion
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
            readonly property var ledgerData: root.windowLedgerFor(modelData)

            // Live metadata mirrored from observable root state so a pin or
            // running toggle updates the delegate in place instead of the
            // Repeater rebuilding every DockItem.
            property var liveData: ({
              id: modelData,
              name: root.appNameFor(modelData),
              icon: root.appIconNameFor(modelData),
              pinned: root.pinnedIds.indexOf(modelData) !== -1,
              running: root.runningIds.indexOf(modelData) !== -1,
              active: wrapper.ledgerData.active,
              windowCount: wrapper.ledgerData.count,
              windowCountLabel: wrapper.ledgerData.countLabel,
              currentWorkspaceWindowCount: wrapper.ledgerData.currentWorkspaceCount,
              otherWorkspaceWindowCount: wrapper.ledgerData.otherWorkspaceCount
            })

            property alias targetScale: dockItem.targetScale
            property alias targetLift: dockItem.targetLift
            property alias targetOpacity: dockItem.targetOpacity
            readonly property bool iconReady: dockItem.iconReady
            readonly property bool packNormalized: dockItem.packNormalized
            readonly property real iconCenterOffset: dockItem.iconCenterOffset
            readonly property Item focusTarget: dockItem

            Behavior on x {
              enabled: wrapper.animating && !root.reducedMotion
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
              animationEnabled: wrapper.animating && !root.reducedMotion
              iconSourceOverride: root.iconSourceFor(modelData)
              grayscaleIcon: root.iconUsesAutomaticNativeFallback(modelData)
              onItemLeftClicked: function(clickedItem) { root.handleClick(clickedItem) }
              onItemRightClicked: function(clickedItem, position) { root.openMenu(clickedItem, position, dockItem) }
              onWindowListRequested: function(clickedItem, position) { root.openWindowList(clickedItem, position, dockItem) }
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
              onKeyboardFocusChanged: function(focusedItem, focused) {
                if (focused) root.hoveredItemId = focusedItem.id
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
        text: root.tooltipTextFor(root.tooltipItem)
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

  ApplicationIdentityController {
    id: identityController
    manifest: root.manifest
    runHelperPath: root.runHelperPath
    appEntries: root.appEntries
    preferredIds: root.pinnedIds
    onIdentityChanged: Qt.callLater(root.refreshItems)
  }

  WindowListPanel {
    id: windowListPanel
    screen: root.dockScreen
    onActivated: function(windowData) { root.focusWindowAddresses(windowListPanel.appId, [windowData.address]) }
    onCloseRequested: function(windowData) { root.closeWindowData(windowData, windowListPanel.appId) }
    onOpenedChanged: root.windowListOpen = opened
  }

  IconPickerPanel {
    id: iconPicker
    screen: root.dockScreen
    shell: root.shell
    customIcons: root.customIcons
    iconSourceFor: function(id) { return root.iconSourceFor(id) }
    grayscaleFor: function(id) { return root.iconUsesAutomaticNativeFallback(id) }
    stateHelperPath: root.stateHelperPath
    runHelperPath: root.runHelperPath
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
      root.ghostGrayscale = false
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
    reducedMotion: root.reducedMotion
    iconSourceFor: function(data) { return root.iconSourceFor({ id: root.previewAppId }) }
    iconGrayscaleFor: function(data) { return root.iconUsesAutomaticNativeFallback(root.previewAppId) }
    thumbnailFor: function(data) { return root.thumbnailFor(data) }
    onActivated: function(data) { root.activatePreviewWindow(data) }
    onPreviewHoverEntered: previewGrace.stop()
    onPreviewHoverExited: previewGrace.restart()
  }

  AltTabPanel {
    id: altTab
    screen: root.dockScreen
    iconSourceFor: function(app) { return root.iconSourceFor(app.id) }
    grayscaleFor: function(app) { return root.iconUsesAutomaticNativeFallback(app.id) }
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
    WlrLayershell.namespace: "one-bit-bureau-dock-spacer"
    WlrLayershell.exclusiveZone: root.autoHide ? 0 : (root.enabled ? root.dockHeight + root.bottomMargin : 0)
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.dockHeight + root.bottomMargin
    mask: Region {}
  }

  // Edge hot-zone: a 6px invisible strip at the screen bottom that reveals
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
    WlrLayershell.namespace: "one-bit-bureau-dock-edge"
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
    WlrLayershell.namespace: "one-bit-bureau-dock-drag"
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region { item: ghostAnchor }

    Item {
      id: ghostAnchor
      x: root.ghostX
      y: root.ghostY
      width: root.iconSize * root.ghostScale + 16
      height: root.iconSize * root.ghostScale + 16
      opacity: root.ghostOpacity
      Behavior on x {
        enabled: !root.reducedMotion
        NumberAnimation { duration: 60; easing.type: Easing.Linear }
      }
      Behavior on y {
        enabled: !root.reducedMotion
        NumberAnimation { duration: 60; easing.type: Easing.Linear }
      }
      Behavior on opacity {
        enabled: !root.reducedMotion
        NumberAnimation { duration: 60; easing.type: Easing.Linear }
      }

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
        grayscale: root.ghostGrayscale
        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        asynchronous: true
      }
    }
  }
}
