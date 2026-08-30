.pragma library

// The Inspector is an intent surface, not a general-purpose object viewer.
// Keep its boundary deliberately small so a malformed plugin payload cannot
// allocate an unbounded view or smuggle command data through display fields.
var LIMITS = {
    id: 160,
    name: 96,
    subtitle: 180,
    reason: 180,
    factLabel: 56,
    factValue: 240,
    actionId: 64,
    actionLabel: 72,
    facts: 12,
    actions: 12
}

var KINDS = ["desktop", "app", "window"]

function boundedText(value, limit, fallback) {
    var text = value === undefined || value === null ? "" : String(value)
    text = text.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim()
    if (!text) return fallback || ""
    return text.slice(0, Math.max(0, limit || 0))
}

function normalizeKind(value) {
    var kind = boundedText(value, 16, "desktop").toLowerCase()
    return KINDS.indexOf(kind) >= 0 ? kind : "desktop"
}

function kindLabel(kind) {
    if (kind === "app") return "Application"
    if (kind === "window") return "Window"
    return "Desktop object"
}

function normalizeFact(value, index) {
    if (!value || typeof value !== "object") return null
    var label = boundedText(value.label, LIMITS.factLabel, "")
    var factValue = boundedText(value.value, LIMITS.factValue, "")
    if (!label && !factValue) return null
    return {
        id: boundedText(value.id, LIMITS.actionId, "fact-" + index),
        label: label || "Detail",
        value: factValue || "Not available"
    }
}

function validActionId(value) {
    return /^[A-Za-z][A-Za-z0-9._:-]{0,63}$/.test(value)
}

function normalizeIconSource(value) {
    var source = value === undefined || value === null ? "" : String(value)
    source = source.replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 1024)
    if (!source) return ""
    // Identity art must remain local/offline. The Inspector never turns an
    // object payload into an implicit network request.
    if (source.indexOf("file://") === 0 || source.indexOf("image://") === 0 || source.indexOf("qrc:/") === 0)
        return source
    if (source.charAt(0) === "/" && source.indexOf("//") !== 0 && source.indexOf("://") === -1)
        return source
    return ""
}

function normalizeAction(value, index, missing, missingReason) {
    if (!value || typeof value !== "object") return null
    var id = boundedText(value.id, LIMITS.actionId, "")
    var label = boundedText(value.label, LIMITS.actionLabel, "")
    if (!label && !id) return null

    var idValid = validActionId(id)
    var available = value.enabled === true && idValid && !missing
    var reason = boundedText(value.reason, LIMITS.reason, "")
    if (missing) reason = missingReason
    else if (!idValid) reason = "Action identifier is invalid"
    else if (!available && !reason) reason = "Unavailable for this object"

    return {
        id: idValid ? id : "invalid-" + index,
        label: label || id,
        enabled: available,
        reason: reason,
        destructive: value.destructive === true
    }
}

function normalizeContext(value) {
    var input = value && typeof value === "object" ? value : {}
    var missing = !value || input.missing === true
    var kind = normalizeKind(input.kind)
    var missingReason = boundedText(
        input.missingReason,
        LIMITS.reason,
        "The selected object is no longer available"
    )
    var stale = !missing && input.stale === true
    var staleReason = boundedText(
        input.staleReason,
        LIMITS.reason,
        "These details may be out of date"
    )

    var facts = []
    var factInput = Array.isArray(input.facts) ? input.facts : []
    for (var factIndex = 0; factIndex < factInput.length && facts.length < LIMITS.facts; factIndex++) {
        var fact = normalizeFact(factInput[factIndex], factIndex)
        if (fact) facts.push(fact)
    }

    var actions = []
    var actionInput = Array.isArray(input.actions) ? input.actions : []
    for (var actionIndex = 0; actionIndex < actionInput.length && actions.length < LIMITS.actions; actionIndex++) {
        var action = normalizeAction(actionInput[actionIndex], actionIndex, missing, missingReason)
        if (action) actions.push(action)
    }

    var name = boundedText(input.name, LIMITS.name, "")
    if (!name) name = missing ? kindLabel(kind) + " unavailable" : "Unnamed " + kindLabel(kind).toLowerCase()

    return {
        kind: kind,
        kindLabel: kindLabel(kind),
        id: boundedText(input.id, LIMITS.id, ""),
        name: name,
        subtitle: boundedText(input.subtitle, LIMITS.subtitle, ""),
        iconSource: normalizeIconSource(input.iconSource),
        iconGrayscale: input.iconGrayscale !== false,
        stale: stale,
        staleReason: staleReason,
        missing: missing,
        missingReason: missingReason,
        facts: facts,
        actions: actions
    }
}

// QML does not define `module`; this export only makes the same normalizer
// available to the focused Node tests.
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        LIMITS: LIMITS,
        boundedText: boundedText,
        normalizeKind: normalizeKind,
        kindLabel: kindLabel,
        validActionId: validActionId,
        normalizeIconSource: normalizeIconSource,
        normalizeContext: normalizeContext
    }
}
