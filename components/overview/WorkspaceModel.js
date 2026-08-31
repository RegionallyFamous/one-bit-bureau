.pragma library

var MAX_ORDINARY_WORKSPACE_ID = 999
var MAX_COLLECTION_ITEMS = 4096
var MAX_ADDRESS_HEX_DIGITS = 16
var MAX_MONITOR_NAME_LENGTH = 128
var MAX_WINDOW_IDENTITY_TEXT_LENGTH = 256
var MAX_LINUX_PID = 4194304

function arrayLikeValues(value) {
    if (!value || typeof value === "string")
        return null;
    if (Array.isArray(value))
        return value;
    var length = Number(value.length);
    if (!isFinite(length) || Math.floor(length) !== length || length < 0 || length > MAX_COLLECTION_ITEMS)
        return null;
    var result = [];
    for (var index = 0; index < length; index++)
        result.push(value[index]);
    return result;
}

function valuesOf(value) {
    var direct = arrayLikeValues(value);
    if (direct !== null)
        return direct;
    var nested = value && typeof value.values !== "function"
        ? arrayLikeValues(value.values)
        : null;
    return nested !== null ? nested : [];
}

function ordinaryWorkspaceId(value) {
    var numeric = Number(value);
    if (!isFinite(numeric) || Math.floor(numeric) !== numeric)
        return 0;
    if (numeric < 1 || numeric > MAX_ORDINARY_WORKSPACE_ID)
        return 0;
    return numeric;
}

function workspaceIdFor(value) {
    if (!value)
        return 0;
    var direct = ordinaryWorkspaceId(value.id);
    if (direct)
        return direct;
    var name = String(value.name || "");
    return /^[1-9][0-9]{0,2}$/.test(name) ? ordinaryWorkspaceId(name) : 0;
}

function toplevelWorkspaceId(toplevel) {
    return workspaceIdFor(toplevel && toplevel.workspace ? toplevel.workspace : null);
}

function boundedMonitorName(value) {
    var name = String(value || "");
    if (name.length < 1 || name.length > MAX_MONITOR_NAME_LENGTH)
        return "";
    return /^[A-Za-z0-9_.:-]+$/.test(name) ? name : "";
}

function monitorNameFor(value) {
    if (!value)
        return "";
    if (typeof value === "string")
        return boundedMonitorName(value);
    var monitor = value.monitor || null;
    if (monitor) {
        var direct = boundedMonitorName(typeof monitor === "string" ? monitor : monitor.name);
        if (direct)
            return direct;
    }
    var ipc = value.lastIpcObject && typeof value.lastIpcObject === "object"
        ? value.lastIpcObject
        : {};
    return boundedMonitorName(ipc.monitor || ipc.monitorName || "");
}

function workspaceOnMonitor(workspace, monitorName) {
    var wanted = boundedMonitorName(monitorName);
    if (!wanted)
        return true;
    return monitorNameFor(workspace) === wanted;
}

function countToplevels(workspace, toplevels, monitorName) {
    var workspaceId = workspaceIdFor(workspace);
    var source = valuesOf(toplevels);
    var count = 0;
    for (var index = 0; index < source.length; index++) {
        var top = source[index];
        if (toplevelWorkspaceId(top) === workspaceId
                && (!boundedMonitorName(monitorName) || monitorNameFor(top) === boundedMonitorName(monitorName)))
            count++;
    }
    if (count > 0)
        return count;
    var nativeToplevels = workspace && workspace.toplevels ? valuesOf(workspace.toplevels) : [];
    return nativeToplevels.length;
}

function countToplevelsOnMonitor(toplevels, monitorName) {
    var wanted = boundedMonitorName(monitorName);
    if (!wanted)
        return 0;
    var source = valuesOf(toplevels);
    var count = 0;
    for (var index = 0; index < source.length; index++)
        if (monitorNameFor(source[index]) === wanted)
            count++;
    return count;
}

function ordinaryWorkspaces(workspaces, toplevels, focusedWorkspace, monitorName) {
    var source = valuesOf(workspaces);
    var focusedId = workspaceIdFor(focusedWorkspace);
    var scopedMonitor = boundedMonitorName(monitorName);
    var seen = {};
    var result = [];
    for (var index = 0; index < source.length; index++) {
        var workspace = source[index];
        if (!workspaceOnMonitor(workspace, scopedMonitor))
            continue;
        var id = workspaceIdFor(workspace);
        if (!id || seen[id])
            continue;
        seen[id] = true;
        var count = countToplevels(workspace, toplevels, scopedMonitor);
        result.push({
            id: id,
            name: String(workspace.name || id),
            label: "Workspace " + id,
            count: count,
            occupied: count > 0,
            active: workspace.active === true || id === focusedId,
            monitorName: scopedMonitor || monitorNameFor(workspace)
        });
    }
    result.sort(function(left, right) { return left.id - right.id; });
    return result;
}

function unsupportedWorkspaceKind(workspace) {
    if (!workspace)
        return "invalid";
    var rawId = Number(workspace.id);
    var name = String(workspace.name || "");
    if (name.indexOf("special:") === 0)
        return "special";
    if (ordinaryWorkspaceId(rawId) || (/^[1-9][0-9]{0,2}$/.test(name) && ordinaryWorkspaceId(name)))
        return "";
    if ((isFinite(rawId) && rawId > MAX_ORDINARY_WORKSPACE_ID) || /^[1-9][0-9]{3,}$/.test(name))
        return "out-of-range";
    if ((isFinite(rawId) && rawId < 1) || name)
        return "named";
    return "invalid";
}

function unsupportedWorkspaceSummary(workspaces, monitorName) {
    var source = valuesOf(workspaces);
    var scopedMonitor = boundedMonitorName(monitorName);
    var result = {total: 0, named: 0, special: 0, outOfRange: 0, unassigned: 0};
    for (var index = 0; index < source.length; index++) {
        var workspace = source[index];
        var actualMonitor = monitorNameFor(workspace);
        if (scopedMonitor && actualMonitor && actualMonitor !== scopedMonitor)
            continue;
        var kind = unsupportedWorkspaceKind(workspace);
        if (!kind && scopedMonitor && !actualMonitor)
            kind = "unassigned";
        if (!kind)
            continue;
        result.total++;
        if (kind === "special")
            result.special++;
        else if (kind === "out-of-range")
            result.outOfRange++;
        else if (kind === "unassigned")
            result.unassigned++;
        else
            result.named++;
    }
    return result;
}

function monitorNames(monitors) {
    var source = valuesOf(monitors);
    var seen = {};
    var result = [];
    for (var index = 0; index < source.length; index++) {
        var name = boundedMonitorName(source[index] && source[index].name);
        if (name && !seen[name]) {
            seen[name] = true;
            result.push(name);
        }
    }
    result.sort();
    return result;
}

function chooseMonitorScope(monitors, requestedName, focusedName) {
    var names = monitorNames(monitors);
    var requested = boundedMonitorName(requestedName);
    var focused = boundedMonitorName(focusedName);
    if (requested && names.indexOf(requested) !== -1)
        return requested;
    if (focused && names.indexOf(focused) !== -1)
        return focused;
    return names.length > 0 ? names[0] : "";
}

function workspaceById(entries, wantedId) {
    var id = ordinaryWorkspaceId(wantedId);
    var source = valuesOf(entries);
    for (var index = 0; index < source.length; index++)
        if (ordinaryWorkspaceId(source[index] && source[index].id) === id)
            return source[index];
    return null;
}

function cycleWorkspaceId(entries, currentId, direction) {
    var source = valuesOf(entries);
    if (source.length === 0)
        return 0;
    var current = ordinaryWorkspaceId(currentId);
    var index = -1;
    for (var candidate = 0; candidate < source.length; candidate++)
        if (ordinaryWorkspaceId(source[candidate] && source[candidate].id) === current) {
            index = candidate;
            break;
        }
    var step = Number(direction) < 0 ? -1 : 1;
    if (index < 0)
        return ordinaryWorkspaceId(source[step < 0 ? source.length - 1 : 0].id);
    index = (index + step + source.length) % source.length;
    return ordinaryWorkspaceId(source[index].id);
}

function normalizedAddress(value) {
    var address = String(value || "");
    var pattern = new RegExp("^0x[0-9a-fA-F]{1," + MAX_ADDRESS_HEX_DIGITS + "}$");
    return pattern.test(address) ? address.toLowerCase() : "";
}

function normalizedPid(value) {
    var pid = Number(value);
    if (!isFinite(pid) || Math.floor(pid) !== pid || pid < 1 || pid > MAX_LINUX_PID)
        return 0;
    return pid;
}

function pidFor(toplevel) {
    var ipc = toplevel && toplevel.lastIpcObject && typeof toplevel.lastIpcObject === "object"
        ? toplevel.lastIpcObject
        : {};
    return normalizedPid(ipc.pid);
}

function boundedWindowIdentityText(value) {
    var text = String(value || "");
    if (text.length > MAX_WINDOW_IDENTITY_TEXT_LENGTH || /[\u0000-\u001f\u007f]/.test(text))
        return "";
    return text;
}

function windowIdentityFor(toplevel) {
    var ipc = toplevel && toplevel.lastIpcObject && typeof toplevel.lastIpcObject === "object"
        ? toplevel.lastIpcObject
        : {};
    return {
        address: normalizedAddress(toplevel && toplevel.address
            ? (/^0x/.test(String(toplevel.address)) ? toplevel.address : "0x" + toplevel.address)
            : ""),
        pid: normalizedPid(ipc.pid),
        initialClass: boundedWindowIdentityText(ipc.initialClass || ipc.class || ""),
        initialTitle: boundedWindowIdentityText(ipc.initialTitle || "")
    };
}

function sameWindowIdentity(left, right) {
    if (!left || !right)
        return false;
    var leftClass = boundedWindowIdentityText(left.initialClass);
    var rightClass = boundedWindowIdentityText(right.initialClass);
    var leftTitle = boundedWindowIdentityText(left.initialTitle);
    var rightTitle = boundedWindowIdentityText(right.initialTitle);
    return normalizedAddress(left.address) !== ""
        && normalizedAddress(left.address) === normalizedAddress(right.address)
        && normalizedPid(left.pid) !== 0
        && normalizedPid(left.pid) === normalizedPid(right.pid)
        && Boolean(leftClass || leftTitle)
        && leftClass === rightClass
        && leftTitle === rightTitle;
}

function moveRequest(address, pid, workspaceId, entries, monitorName) {
    var normalized = normalizedAddress(address);
    if (!normalized)
        return {ok: false, error: "Window is no longer available", address: "", workspaceId: 0};
    var expectedPid = normalizedPid(pid);
    if (!expectedPid)
        return {ok: false, error: "Window identity is incomplete", address: normalized, pid: 0, workspaceId: 0};
    var monitor = boundedMonitorName(monitorName);
    if (!monitor)
        return {ok: false, error: "Display is no longer available", address: normalized, pid: expectedPid, workspaceId: 0};
    var id = ordinaryWorkspaceId(workspaceId);
    var workspace = workspaceById(entries, id);
    if (!id || !workspace)
        return {ok: false, error: "Workspace is no longer available on " + monitor, address: normalized, pid: expectedPid, workspaceId: 0, monitorName: monitor};
    if (boundedMonitorName(workspace.monitorName) !== monitor)
        return {ok: false, error: "Workspace belongs to another display", address: normalized, pid: expectedPid, workspaceId: 0, monitorName: monitor};
    return {ok: true, error: "", address: normalized, pid: expectedPid, workspaceId: id, monitorName: monitor};
}

function parseMoveResult(value) {
    var line = String(value || "").trim().split(/\r?\n/).pop() || "";
    var fields = line.split("\t");
    if (fields.length !== 5 || (fields[0] !== "confirmed" && fields[0] !== "pending"))
        return {state: "", dispatcher: "", address: "", workspaceId: 0, monitorName: ""};
    var address = normalizedAddress(fields[2]);
    var workspaceId = ordinaryWorkspaceId(fields[3]);
    var monitorName = boundedMonitorName(fields[4]);
    var dispatcher = fields[1] === "lua" || fields[1] === "legacy" ? fields[1] : "";
    if (!dispatcher || !address || !workspaceId || !monitorName)
        return {state: "", dispatcher: "", address: "", workspaceId: 0, monitorName: ""};
    return {state: fields[0], dispatcher: dispatcher, address: address, workspaceId: workspaceId, monitorName: monitorName};
}

if (typeof module !== "undefined")
    module.exports = {
        MAX_ORDINARY_WORKSPACE_ID: MAX_ORDINARY_WORKSPACE_ID,
        MAX_COLLECTION_ITEMS: MAX_COLLECTION_ITEMS,
        MAX_ADDRESS_HEX_DIGITS: MAX_ADDRESS_HEX_DIGITS,
        MAX_MONITOR_NAME_LENGTH: MAX_MONITOR_NAME_LENGTH,
        MAX_WINDOW_IDENTITY_TEXT_LENGTH: MAX_WINDOW_IDENTITY_TEXT_LENGTH,
        MAX_LINUX_PID: MAX_LINUX_PID,
        ordinaryWorkspaceId: ordinaryWorkspaceId,
        workspaceIdFor: workspaceIdFor,
        toplevelWorkspaceId: toplevelWorkspaceId,
        boundedMonitorName: boundedMonitorName,
        monitorNameFor: monitorNameFor,
        workspaceOnMonitor: workspaceOnMonitor,
        countToplevels: countToplevels,
        countToplevelsOnMonitor: countToplevelsOnMonitor,
        ordinaryWorkspaces: ordinaryWorkspaces,
        unsupportedWorkspaceKind: unsupportedWorkspaceKind,
        unsupportedWorkspaceSummary: unsupportedWorkspaceSummary,
        monitorNames: monitorNames,
        chooseMonitorScope: chooseMonitorScope,
        workspaceById: workspaceById,
        cycleWorkspaceId: cycleWorkspaceId,
        normalizedAddress: normalizedAddress,
        normalizedPid: normalizedPid,
        pidFor: pidFor,
        boundedWindowIdentityText: boundedWindowIdentityText,
        windowIdentityFor: windowIdentityFor,
        sameWindowIdentity: sameWindowIdentity,
        moveRequest: moveRequest,
        parseMoveResult: parseMoveResult
    };
