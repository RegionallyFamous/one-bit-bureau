import QtQuick
import Quickshell
import Quickshell.Io
import "ApplicationIdentity.js" as ApplicationIdentity
import "WindowLedger.js" as WindowLedger

Item {
  id: root

  property var manifest: null
  property string home: Quickshell.env("HOME")
  property string runHelperPath: ""
  property var appEntries: []
  property var preferredIds: []
  property var desktopMetadata: ({})
  property var processMetadata: ({})
  property var identityEntries: []
  property int processRequestRevision: 0
  property int processReaderRevision: 0
  property bool processRefreshPending: false

  readonly property string metadataHelperPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/components/dock/scripts/application-identity-metadata"
    : home + "/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau/components/dock/scripts/application-identity-metadata"

  signal identityChanged()

  function metadataForId(id) {
    var wanted = String(id || "").toLowerCase()
    for (var key in root.desktopMetadata)
      if (String(key).toLowerCase() === wanted) return root.desktopMetadata[key] || ({})
    return ({})
  }

  function mergeEntries() {
    var output = []
    var seen = ({})
    var source = root.appEntries || []
    var limit = Math.min(source.length, ApplicationIdentity.LIMITS.entries)
    for (var i = 0; i < limit; i++) {
      var sourceEntry = source[i] && source[i].entry ? source[i].entry : (source[i] || {})
      var id = ApplicationIdentity.normalizeId(sourceEntry.id || sourceEntry.desktopId)
      if (!id) continue
      seen[id.toLowerCase()] = true
      var metadata = root.metadataForId(id)
      var aliases = []
      if (Array.isArray(metadata.aliases)) aliases = metadata.aliases.slice(0, 16)
      if (Array.isArray(sourceEntry.aliases)) aliases = aliases.concat(sourceEntry.aliases.slice(0, 16))
      var processes = []
      if (Array.isArray(metadata.processNames)) processes = metadata.processNames.slice(0, 12)
      if (Array.isArray(sourceEntry.processNames)) processes = processes.concat(sourceEntry.processNames.slice(0, 12))
      output.push({
        id: id,
        desktopId: id,
        startupWmClass: metadata.startupWmClass || sourceEntry.startupWmClass || sourceEntry.startupWMClass || "",
        wmClass: sourceEntry.wmClass || "",
        aliases: aliases.slice(0, 16),
        processNames: processes.slice(0, 12),
        execString: metadata.execString || sourceEntry.execString || ""
      })
    }
    var preferred = root.preferredIds || []
    for (var preferredIndex = 0; preferredIndex < preferred.length
        && output.length < ApplicationIdentity.LIMITS.entries; preferredIndex++) {
      var preferredId = ApplicationIdentity.normalizeId(preferred[preferredIndex])
      if (!preferredId || seen[preferredId.toLowerCase()]) continue
      seen[preferredId.toLowerCase()] = true
      var preferredMetadata = root.metadataForId(preferredId)
      output.push({
        id: preferredId,
        desktopId: preferredId,
        startupWmClass: preferredMetadata.startupWmClass || "",
        aliases: Array.isArray(preferredMetadata.aliases) ? preferredMetadata.aliases.slice(0, 16) : [],
        processNames: Array.isArray(preferredMetadata.processNames) ? preferredMetadata.processNames.slice(0, 12) : [],
        execString: preferredMetadata.execString || ""
      })
    }
    root.identityEntries = output
    root.identityChanged()
  }

  function parseDesktopIndex(content) {
    var parsed = null
    try { parsed = JSON.parse(String(content || "")) } catch (error) {}
    if (!parsed || parsed.version !== 1 || !parsed.entries
        || typeof parsed.entries !== "object" || Array.isArray(parsed.entries)) return
    root.desktopMetadata = parsed.entries
    root.mergeEntries()
  }

  function refreshDesktopIndex() {
    if (!root.metadataHelperPath || !root.runHelperPath || desktopIndexProcess.running) return false
    desktopIndexProcess.command = [
      "python3", root.runHelperPath, "3500", "250", "131072", "8192", "--",
      "python3", root.metadataHelperPath, "desktop-index"
    ]
    desktopIndexProcess.running = true
    return true
  }

  function processArguments(windows) {
    var output = []
    var source = windows || []
    var limit = Math.min(source.length, 64)
    for (var i = 0; i < limit; i++) {
      var window = source[i]
      var address = WindowLedger.normalizeAddress(window && window.address)
      var ipc = window && window.lastIpcObject ? window.lastIpcObject : ({})
      var pid = Number(ipc.pid || 0)
      if (!address || !isFinite(pid) || pid < 1 || pid > 4194304) continue
      output.push(address + "=" + Math.floor(pid))
    }
    return output
  }

  function refreshProcesses(windows) {
    root.processRequestRevision++
    root.pendingProcessArguments = root.processArguments(windows)
    if (processIndexProcess.running) {
      root.processRefreshPending = true
      return true
    }
    return root.startProcessRefresh()
  }

  property var pendingProcessArguments: []

  function startProcessRefresh() {
    var args = root.pendingProcessArguments.slice(0, 64)
    root.processReaderRevision = root.processRequestRevision
    root.processRefreshPending = false
    if (!args.length) {
      root.processMetadata = ({})
      root.identityChanged()
      return false
    }
    processIndexProcess.command = [
      "python3", root.runHelperPath, "1800", "200", "65536", "8192", "--",
      "python3", root.metadataHelperPath, "process"
    ].concat(args)
    processIndexProcess.running = true
    return true
  }

  function parseProcessIndex(content, revision) {
    if (revision !== root.processRequestRevision) return
    var parsed = null
    try { parsed = JSON.parse(String(content || "")) } catch (error) {}
    if (!parsed || parsed.version !== 1 || !parsed.processes
        || typeof parsed.processes !== "object" || Array.isArray(parsed.processes)) return
    root.processMetadata = parsed.processes
    root.identityChanged()
  }

  function processForWindow(window) {
    var address = WindowLedger.normalizeAddress(window && window.address)
    var record = address ? root.processMetadata[address] : null
    var ipc = window && window.lastIpcObject ? window.lastIpcObject : ({})
    if (!record || Number(record.pid || 0) !== Number(ipc.pid || 0)) return ({})
    return record
  }

  function identityInputForWindow(window) {
    var candidate = window || ({})
    var ipc = candidate.lastIpcObject || ({})
    var wayland = candidate.wayland || ({})
    var process = root.processForWindow(candidate)
    return {
      desktopId: candidate.desktopId || "",
      appId: ipc.appId || "",
      waylandAppId: wayland.appId || candidate.appId || "",
      className: ipc["class"] || candidate.className || "",
      initialClass: ipc.initialClass || candidate.initialClass || "",
      processName: process.processName || "",
      executable: process.executable || "",
      processNames: process.identityNames || []
    }
  }

  function resolveWindow(window) {
    return ApplicationIdentity.resolve(
      root.identityInputForWindow(window), root.identityEntries, root.preferredIds)
  }

  function resolveInput(input) {
    return ApplicationIdentity.resolve(input || ({}), root.identityEntries, root.preferredIds)
  }

  function normalizeId(value) {
    return ApplicationIdentity.normalizeId(value)
  }

  onAppEntriesChanged: root.mergeEntries()
  onPreferredIdsChanged: root.mergeEntries()

  Process {
    id: desktopIndexProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseDesktopIndex(text)
    }
  }

  Process {
    id: processIndexProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseProcessIndex(text, root.processReaderRevision)
    }
    onExited: {
      if (root.processRefreshPending || root.processReaderRevision !== root.processRequestRevision)
        Qt.callLater(root.startProcessRefresh)
    }
  }

  Component.onCompleted: {
    root.mergeEntries()
    root.refreshDesktopIndex()
  }

  Component.onDestruction: {
    desktopIndexProcess.running = false
    processIndexProcess.running = false
  }
}
