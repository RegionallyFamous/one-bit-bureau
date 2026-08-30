.pragma library

// Pure window-state helpers for the dock. Keeping ordering and summaries out
// of QML makes the rules deterministic and cheap to exercise under Node.

function normalizeAddress(value) {
    var address = String(value || "").trim()
    if (/^[0-9a-fA-F]+$/.test(address)) return "0x" + address.toLowerCase()
    if (/^0x[0-9a-fA-F]+$/.test(address)) return address.toLowerCase()
    return ""
}

function workspaceKey(workspace) {
    if (!workspace) return ""
    var id = Number(workspace.id)
    if (isFinite(id) && id !== 0) return "id:" + id
    var name = String(workspace.name || "").trim()
    return name ? "name:" + name : ""
}

function sameWorkspace(windowData, currentWorkspace) {
    if (!windowData || !currentWorkspace) return false
    if (windowData.pinned === true) return true

    var currentKey = workspaceKey(currentWorkspace)
    var windowKey = workspaceKey({
        id: windowData.workspaceId,
        name: windowData.workspaceName
    })
    return Boolean(currentKey) && currentKey === windowKey
}

function workspaceLabel(windowData) {
    if (!windowData) return "Unknown workspace"
    var name = String(windowData.workspaceName || "").trim()
    if (name) return "Workspace " + name
    var id = Number(windowData.workspaceId)
    return isFinite(id) && id !== 0 ? "Workspace " + id : "Unknown workspace"
}

function touchMru(history, appId, address, limit) {
    var id = String(appId || "").trim()
    var normalized = normalizeAddress(address)
    var next = {}
    var source = history && typeof history === "object" ? history : {}
    for (var key in source)
        next[key] = Array.isArray(source[key]) ? source[key].slice() : []
    if (!id || !normalized) return next

    var values = next[id] || []
    var index = values.indexOf(normalized)
    if (index >= 0) values.splice(index, 1)
    values.unshift(normalized)
    values = values.slice(0, Math.max(1, Number(limit) || 32))
    next[id] = values
    return next
}

function pruneMru(addresses, windows) {
    var live = {}
    ;(windows || []).forEach(function(windowData) {
        var address = normalizeAddress(windowData && windowData.address)
        if (address) live[address] = true
    })
    var output = []
    ;(addresses || []).forEach(function(value) {
        var address = normalizeAddress(value)
        if (address && live[address] && output.indexOf(address) === -1)
            output.push(address)
    })
    return output
}

// MRU is authoritative when known. New/unseen windows then sort by active
// state, current-workspace membership, and finally address so a click never
// depends on compositor collection order.
function orderWindows(windows, mruAddresses, currentWorkspace, activeAddress) {
    var source = (windows || []).slice()
    var active = normalizeAddress(activeAddress)
    var mru = pruneMru(mruAddresses, source)
    var rank = {}
    for (var i = 0; i < mru.length; i++) rank[mru[i]] = i

    source.sort(function(left, right) {
        var leftAddress = normalizeAddress(left && left.address)
        var rightAddress = normalizeAddress(right && right.address)
        var leftRank = rank[leftAddress]
        var rightRank = rank[rightAddress]
        var leftKnown = leftRank !== undefined
        var rightKnown = rightRank !== undefined
        if (leftKnown !== rightKnown) return leftKnown ? -1 : 1
        if (leftKnown && leftRank !== rightRank) return leftRank - rightRank

        var leftActive = Boolean(left && left.active) || (active && leftAddress === active)
        var rightActive = Boolean(right && right.active) || (active && rightAddress === active)
        if (leftActive !== rightActive) return leftActive ? -1 : 1

        var leftHere = sameWorkspace(left, currentWorkspace)
        var rightHere = sameWorkspace(right, currentWorkspace)
        if (leftHere !== rightHere) return leftHere ? -1 : 1

        return leftAddress < rightAddress ? -1 : (leftAddress > rightAddress ? 1 : 0)
    })
    return source
}

function summarizeWindows(windows, currentWorkspace, activeAddress) {
    var source = windows || []
    var active = normalizeAddress(activeAddress)
    var currentCount = 0
    var activeFound = false
    for (var i = 0; i < source.length; i++) {
        var windowData = source[i] || {}
        if (sameWorkspace(windowData, currentWorkspace)) currentCount++
        if (windowData.active || (active && normalizeAddress(windowData.address) === active))
            activeFound = true
    }
    var count = source.length
    return {
        count: count,
        countLabel: count > 2 ? "3+" : String(count),
        active: activeFound,
        currentWorkspaceCount: currentCount,
        otherWorkspaceCount: Math.max(0, count - currentCount),
        windows: source
    }
}

function focusAddresses(windows) {
    var output = []
    ;(windows || []).forEach(function(windowData) {
        var address = normalizeAddress(windowData && windowData.address)
        if (address && output.indexOf(address) === -1) output.push(address)
    })
    return output
}

function plural(count, singular, pluralValue) {
    return count + " " + (count === 1 ? singular : pluralValue)
}

function accessibleDescription(itemData) {
    var item = itemData || {}
    var parts = [item.pinned ? "Pinned application" : "Application"]
    var count = Math.max(0, Number(item.windowCount) || 0)
    if (count === 0) {
        if (item.running) parts.push("running; window details updating")
        return parts.join(", ")
    }
    parts.push(item.active ? "active" : "running")
    parts.push(plural(count, "window", "windows"))
    var here = Math.max(0, Number(item.currentWorkspaceWindowCount) || 0)
    var elsewhere = Math.max(0, Number(item.otherWorkspaceWindowCount) || 0)
    if (here) parts.push(here + " on the current workspace")
    if (elsewhere) parts.push(elsewhere + " on other workspaces")
    return parts.join(", ")
}

// QML does not define `module`; this only exposes the pure helpers to the
// existing Node-based dock suite.
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        normalizeAddress: normalizeAddress,
        workspaceKey: workspaceKey,
        sameWorkspace: sameWorkspace,
        workspaceLabel: workspaceLabel,
        touchMru: touchMru,
        pruneMru: pruneMru,
        orderWindows: orderWindows,
        summarizeWindows: summarizeWindows,
        focusAddresses: focusAddresses,
        accessibleDescription: accessibleDescription
    }
}
