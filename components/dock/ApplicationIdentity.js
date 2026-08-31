.pragma library

// One-Bit Bureau application identity contract.
//
// Priority is deliberately fixed and never consults a window title:
//   1. exact desktop-file id / Wayland app_id
//   2. exact StartupWMClass
//   3. unique, bounded class aliases
//   4. unique, bounded process/executable identity
//
// Every non-exact tier must have one owner. Ambiguity fails closed instead of
// collapsing unrelated applications into one dock identity.

var LIMITS = {
    idChars: 160,
    classChars: 160,
    processChars: 160,
    execChars: 512,
    entries: 4096,
    inputValues: 12,
    aliasesPerEntry: 16,
    processNamesPerEntry: 12
}

function bounded(value, limit) {
    var text = String(value === undefined || value === null ? "" : value).trim()
    return text.length <= limit ? text : ""
}

function normalizeId(value) {
    var text = bounded(value, LIMITS.idChars + 8)
    if (text.toLowerCase().slice(-8) === ".desktop") text = text.slice(0, -8)
    return text.length <= LIMITS.idChars ? text : ""
}

function normalizeClass(value) {
    return bounded(value, LIMITS.classChars)
}

function normalizeProcess(value) {
    var text = bounded(value, LIMITS.processChars)
    if (!text) return ""
    text = text.replace(/\\/g, "/")
    var slash = text.lastIndexOf("/")
    if (slash >= 0) text = text.slice(slash + 1)
    return text.toLowerCase()
}

function key(value) {
    return String(value || "").toLowerCase()
}

function pushUnique(output, value, normalizer, limit) {
    if (output.length >= limit) return
    var clean = normalizer(value)
    if (!clean) return
    var cleanKey = key(clean)
    for (var i = 0; i < output.length; i++)
        if (key(output[i]) === cleanKey) return
    output.push(clean)
}

function appendValues(output, value, normalizer, limit) {
    if (Array.isArray(value)) {
        for (var i = 0; i < value.length && output.length < limit; i++)
            pushUnique(output, value[i], normalizer, limit)
    } else {
        pushUnique(output, value, normalizer, limit)
    }
}

function entryObject(value) {
    return value && value.entry ? value.entry : (value || {})
}

function tokenizeExec(value) {
    var text = bounded(value, LIMITS.execChars)
    if (!text) return []
    var tokens = []
    var current = ""
    var quote = ""
    var escaped = false
    for (var i = 0; i < text.length && tokens.length < 32; i++) {
        var ch = text.charAt(i)
        if (escaped) {
            current += ch
            escaped = false
        } else if (ch === "\\") {
            escaped = true
        } else if (quote) {
            if (ch === quote) quote = ""
            else current += ch
        } else if (ch === "\"" || ch === "'") {
            quote = ch
        } else if (/\s/.test(ch)) {
            if (current) { tokens.push(current); current = "" }
        } else {
            current += ch
        }
    }
    if (current && tokens.length < 32) tokens.push(current)
    return tokens
}

function execIdentityTokens(value) {
    var argv = tokenizeExec(value)
    var output = []
    var index = 0
    while (index < argv.length && (/^[A-Za-z_][A-Za-z0-9_]*=/.test(argv[index])
            || argv[index] === "env" || argv[index] === "/usr/bin/env"
            || argv[index] === "uwsm-app" || argv[index] === "--")) index++
    if (index >= argv.length) return output

    var executable = normalizeProcess(argv[index])
    pushUnique(output, executable, normalizeProcess, LIMITS.processNamesPerEntry)
    if (executable === "flatpak") {
        index++
        while (index < argv.length && argv[index] !== "run") index++
        if (argv[index] === "run") index++
        while (index < argv.length && argv[index].charAt(0) === "-") index++
        if (index < argv.length)
            pushUnique(output, normalizeId(argv[index]), normalizeProcess, LIMITS.processNamesPerEntry)
    } else if (executable === "snap") {
        index++
        if (argv[index] === "run") index++
        if (index < argv.length)
            pushUnique(output, argv[index], normalizeProcess, LIMITS.processNamesPerEntry)
    }
    return output
}

function finalIdSegment(value) {
    var id = normalizeId(value)
    if (!id) return ""
    var segments = id.split(/[.\-]/)
    var last = segments.length ? segments[segments.length - 1] : ""
    return last.length >= 4 ? last : ""
}

function webAppAlias(value) {
    var raw = normalizeClass(value).toLowerCase()
    // Chromium app-mode class: chrome-<host-or-app-id>-<profile>. Keep this
    // deliberately narrow; arbitrary title/name containment is forbidden.
    var match = raw.match(/^chrome-(?:web\.)?([a-z0-9][a-z0-9-]{2,62})(?:\.[a-z0-9.-]{2,190})?__[^\s]{0,190}-(?:default|profile_[0-9]+)$/)
    return match ? match[1] : ""
}

function entrySpec(rawEntry) {
    var entry = entryObject(rawEntry)
    var id = normalizeId(entry.id || entry.desktopId)
    var startup = []
    appendValues(startup, entry.startupWmClass, normalizeClass, 4)
    appendValues(startup, entry.startupWMClass, normalizeClass, 4)
    appendValues(startup, entry.wmClass, normalizeClass, 4)

    var aliases = []
    appendValues(aliases, entry.aliases, normalizeClass, LIMITS.aliasesPerEntry)
    appendValues(aliases, entry.desktopAliases, normalizeClass, LIMITS.aliasesPerEntry)
    appendValues(aliases, id, normalizeClass, LIMITS.aliasesPerEntry)
    appendValues(aliases, finalIdSegment(id), normalizeClass, LIMITS.aliasesPerEntry)

    var processes = []
    appendValues(processes, entry.processNames, normalizeProcess, LIMITS.processNamesPerEntry)
    appendValues(processes, entry.executables, normalizeProcess, LIMITS.processNamesPerEntry)
    appendValues(processes, execIdentityTokens(entry.execString), normalizeProcess, LIMITS.processNamesPerEntry)
    return { id: id, startup: startup, aliases: aliases, processes: processes }
}

function buildSpecs(entries, preferredIds) {
    var output = []
    var seen = {}
    var source = entries || []
    for (var i = 0; i < source.length && output.length < LIMITS.entries; i++) {
        var spec = entrySpec(source[i])
        if (!spec.id || seen[key(spec.id)]) continue
        seen[key(spec.id)] = true
        output.push(spec)
    }
    var preferred = preferredIds || []
    for (var j = 0; j < preferred.length && output.length < LIMITS.entries; j++) {
        var id = normalizeId(preferred[j])
        if (!id || seen[key(id)]) continue
        seen[key(id)] = true
        output.push(entrySpec({ id: id }))
    }
    return output
}

function inputValues(identity, names, normalizer) {
    var output = []
    var source = identity || {}
    for (var i = 0; i < names.length && output.length < LIMITS.inputValues; i++)
        appendValues(output, source[names[i]], normalizer, LIMITS.inputValues)
    return output
}

function ownersFor(values, specs, field) {
    var ambiguousOwners = []
    var ambiguousValue = ""
    for (var valueIndex = 0; valueIndex < values.length; valueIndex++) {
        var wanted = key(values[valueIndex])
        var owners = []
        for (var specIndex = 0; specIndex < specs.length; specIndex++) {
            var candidates = field === "id" ? [specs[specIndex].id] : specs[specIndex][field]
            for (var candidateIndex = 0; candidateIndex < candidates.length; candidateIndex++) {
                if (key(candidates[candidateIndex]) !== wanted) continue
                if (owners.indexOf(specs[specIndex].id) === -1) owners.push(specs[specIndex].id)
            }
        }
        if (owners.length === 1) {
            // Respect input priority: the first value with exactly one owner
            // wins before consulting weaker identity evidence.
            return { owners: owners, value: values[valueIndex] }
        }
        if (owners.length > 1 && !ambiguousOwners.length) {
            // A mutable current class can be generic while initialClass is
            // stable and unique. Continue through the bounded input list and
            // only fail ambiguous if no later value has exactly one owner.
            ambiguousOwners = owners
            ambiguousValue = values[valueIndex]
        }
    }
    return { owners: ambiguousOwners, value: ambiguousValue }
}

function resultFor(match, method) {
    if (match.owners.length === 1) {
        return {
            id: match.owners[0],
            method: method,
            matchedValue: match.value,
            ambiguous: false,
            candidates: match.owners.slice()
        }
    }
    if (match.owners.length > 1) {
        return {
            id: "",
            method: method + "-ambiguous",
            matchedValue: match.value,
            ambiguous: true,
            candidates: match.owners.slice(0, 8)
        }
    }
    return null
}

function unresolved(identity, exactValues, classValues, processValues) {
    var fallback = exactValues.length ? exactValues[0]
        : (classValues.length ? classValues[0] : (processValues.length ? processValues[0] : ""))
    return {
        id: normalizeId(fallback) || normalizeClass(fallback) || normalizeProcess(fallback),
        method: "unresolved",
        matchedValue: "",
        ambiguous: false,
        candidates: []
    }
}

function resolve(identity, entries, preferredIds) {
    var source = identity || {}
    var specs = buildSpecs(entries, preferredIds)
    var exactValues = inputValues(source,
        ["desktopId", "appId", "waylandAppId", "appIds"], normalizeId)
    var classValues = inputValues(source,
        ["className", "initialClass", "wmClass", "xwaylandClass", "classes"], normalizeClass)
    var processValues = inputValues(source,
        ["processName", "executable", "processNames", "executables"], normalizeProcess)

    var match = ownersFor(exactValues, specs, "id")
    var resolved = resultFor(match, "exact-app-id")
    if (resolved) return resolved

    match = ownersFor(classValues, specs, "startup")
    resolved = resultFor(match, "startup-wm-class")
    if (resolved) return resolved

    var aliasValues = classValues.slice()
    for (var i = 0; i < classValues.length && aliasValues.length < LIMITS.inputValues; i++)
        pushUnique(aliasValues, webAppAlias(classValues[i]), normalizeClass, LIMITS.inputValues)
    match = ownersFor(aliasValues, specs, "aliases")
    resolved = resultFor(match, "bounded-alias")
    if (resolved) return resolved

    match = ownersFor(processValues, specs, "processes")
    resolved = resultFor(match, "process-executable")
    if (resolved) return resolved

    return unresolved(source, exactValues, classValues, processValues)
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        LIMITS: LIMITS,
        bounded: bounded,
        normalizeId: normalizeId,
        normalizeClass: normalizeClass,
        normalizeProcess: normalizeProcess,
        tokenizeExec: tokenizeExec,
        execIdentityTokens: execIdentityTokens,
        finalIdSegment: finalIdSegment,
        webAppAlias: webAppAlias,
        entrySpec: entrySpec,
        buildSpecs: buildSpecs,
        resolve: resolve
    }
}
