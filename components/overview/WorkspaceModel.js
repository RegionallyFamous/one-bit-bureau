.pragma library

var MAX_ORDINARY_WORKSPACE_ID = 999

function valuesOf(value) {
    if (!value)
        return [];
    if (Array.isArray(value))
        return value;
    if (Array.isArray(value.values))
        return value.values;
    return [];
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

function countToplevels(workspace, toplevels) {
    var workspaceId = workspaceIdFor(workspace);
    var source = valuesOf(toplevels);
    var count = 0;
    for (var index = 0; index < source.length; index++)
        if (toplevelWorkspaceId(source[index]) === workspaceId)
            count++;
    if (count > 0)
        return count;
    var nativeToplevels = workspace && workspace.toplevels ? valuesOf(workspace.toplevels) : [];
    return nativeToplevels.length;
}

function ordinaryWorkspaces(workspaces, toplevels, focusedWorkspace) {
    var source = valuesOf(workspaces);
    var focusedId = workspaceIdFor(focusedWorkspace);
    var seen = {};
    var result = [];
    for (var index = 0; index < source.length; index++) {
        var workspace = source[index];
        var id = workspaceIdFor(workspace);
        if (!id || seen[id])
            continue;
        seen[id] = true;
        var count = countToplevels(workspace, toplevels);
        result.push({
            id: id,
            name: String(workspace.name || id),
            label: "Workspace " + id,
            count: count,
            occupied: count > 0,
            active: id === focusedId
        });
    }
    result.sort(function(left, right) { return left.id - right.id; });
    return result;
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
    return /^0x[0-9a-fA-F]+$/.test(address) ? address.toLowerCase() : "";
}

function moveRequest(address, workspaceId, entries) {
    var normalized = normalizedAddress(address);
    if (!normalized)
        return {ok: false, error: "Window is no longer available", address: "", workspaceId: 0};
    var id = ordinaryWorkspaceId(workspaceId);
    if (!id || !workspaceById(entries, id))
        return {ok: false, error: "Workspace is no longer available", address: normalized, workspaceId: 0};
    return {ok: true, error: "", address: normalized, workspaceId: id};
}

if (typeof module !== "undefined")
    module.exports = {
        MAX_ORDINARY_WORKSPACE_ID: MAX_ORDINARY_WORKSPACE_ID,
        ordinaryWorkspaceId: ordinaryWorkspaceId,
        workspaceIdFor: workspaceIdFor,
        toplevelWorkspaceId: toplevelWorkspaceId,
        countToplevels: countToplevels,
        ordinaryWorkspaces: ordinaryWorkspaces,
        workspaceById: workspaceById,
        cycleWorkspaceId: cycleWorkspaceId,
        normalizedAddress: normalizedAddress,
        moveRequest: moveRequest
    };
