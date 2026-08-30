.pragma library

var FALLBACK_MAP = {
    "org.kde.dolphin": "system-file-manager",
    "dolphin": "system-file-manager",
    "code": "vscode",
    "com.visualstudio.code": "vscode",
    "google-chrome": "google-chrome",
    "com.google.Chrome": "google-chrome",
    "whatsapp": "WhatsApp",
    "discord": "Discord",
    "omarchy-discord": "Discord"
}

var PACK_ALIASES = {
    files: ["nautilus", "dolphin", "thunar", "pcmanfm", "nemo", "cosmic files", "file manager"],
    terminal: ["foot", "kitty", "alacritty", "ghostty", "wezterm", "konsole", "kgx", "gnome console", "xterm"],
    browser: ["chromium", "chrome", "firefox", "brave", "vivaldi", "epiphany", "helium", "zen browser"],
    code: ["code", "codium", "cursor", "zed", "sublime text", "intellij", "pycharm", "webstorm", "neovim"],
    mail: ["thunderbird", "geary", "evolution", "mailspring", "proton mail"],
    chat: ["discord", "slack", "signal", "telegram", "mattermost", "element", "whatsapp"],
    music: ["spotify", "rhythmbox", "lollypop", "amberol", "strawberry", "audacious", "music"],
    video: ["vlc", "mpv", "celluloid", "clapper", "totem", "obs studio", "video"],
    calendar: ["calendar", "morgen", "fantastical"],
    settings: ["settings", "control center", "pavucontrol", "blueman", "nwg look"],
    games: ["steam", "lutris", "heroic", "bottles", "games"],
    notes: ["obsidian", "logseq", "joplin", "standard notes", "notes"]
}

var PACK_ROLES = Object.keys(PACK_ALIASES)

// Alpha bounds measured from the bundled 256x256 raster originals. Keeping
// the source files untouched preserves their authored masters while the UI
// presents the painted artwork at a consistent visual size.
var PACK_CROPS = {
    browser: { x: 23, y: 46, width: 207, height: 145 },
    calendar: { x: 23, y: 13, width: 214, height: 230 },
    chat: { x: 20, y: 34, width: 216, height: 190 },
    code: { x: 44, y: 25, width: 175, height: 193 },
    files: { x: 37, y: 19, width: 189, height: 199 },
    games: { x: 24, y: 24, width: 218, height: 199 },
    mail: { x: 14, y: 34, width: 217, height: 188 },
    music: { x: 45, y: 13, width: 177, height: 222 },
    notes: { x: 28, y: 18, width: 192, height: 210 },
    settings: { x: 30, y: 36, width: 202, height: 188 },
    terminal: { x: 28, y: 13, width: 199, height: 230 },
    video: { x: 58, y: 13, width: 158, height: 219 }
}

function sanitizeName(value) {
    return String(value || "").replace(/\.desktop$/i, "").replace(/[-_]+/g, " ").trim()
}

function normalizeId(value) {
    var id = String(value || "").trim()
    return id.endsWith(".desktop") ? id.slice(0, -8) : id
}

function customIconEntry(customIcons, id) {
    var key = normalizeId(id)
    var value = customIcons && customIcons[key]
    if (!value && customIcons) {
        var lowerKey = key.toLowerCase()
        for (var candidate in customIcons) {
            var normalizedCandidate = normalizeId(candidate)
            if (normalizedCandidate.toLowerCase() === lowerKey) {
                value = customIcons[candidate]
                break
            }
        }
        // Web apps often run with a generated Chrome/Helium class such as
        // chrome-web.whatsapp.com__-Default rather than WhatsApp.desktop.
        if (!value && lowerKey.length >= 4) {
            for (var alias in customIcons) {
                var normalizedAlias = normalizeId(alias).toLowerCase()
                if (lowerKey.indexOf(normalizedAlias) !== -1) {
                    value = customIcons[alias]
                    break
                }
            }
        }
    }
    return value || null
}

function customIconFile(customIcons, id) {
    var value = customIconEntry(customIcons, id)
    if (!value) return ""
    var file = typeof value === "string" ? value : value.file
    file = String(file || "").trim()
    return /^[A-Za-z0-9._-]+$/.test(file) ? file : ""
}

function customIconPack(customIcons, id) {
    var value = customIconEntry(customIcons, id)
    if (!value || typeof value !== "object") return ""
    var pack = String(value.pack || "").trim()
    return PACK_ROLES.indexOf(pack) !== -1 ? pack : ""
}

function customIconMode(customIcons, id) {
    var value = customIconEntry(customIcons, id)
    if (!value || typeof value !== "object") return ""
    var mode = String(value.mode || "").trim()
    return mode === "native" ? mode : ""
}

function hasCustomOverride(customIcons, id) {
    return customIconFile(customIcons, id) !== ""
        || customIconPack(customIcons, id) !== ""
        || customIconMode(customIcons, id) !== ""
}

function searchableIdentity(item) {
    var data = item || {}
    var values = [
        data.id,
        data.desktopId,
        data.name,
        data.displayName,
        data.icon,
        data.iconName,
        data.appIcon
    ]
    return " " + values.map(function(value) {
        return normalizeId(value).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()
    }).filter(Boolean).join(" ") + " "
}

function automaticPackRole(item) {
    var identity = searchableIdentity(item)
    for (var roleIndex = 0; roleIndex < PACK_ROLES.length; roleIndex++) {
        var role = PACK_ROLES[roleIndex]
        var aliases = PACK_ALIASES[role]
        for (var aliasIndex = 0; aliasIndex < aliases.length; aliasIndex++) {
            var needle = " " + aliases[aliasIndex].replace(/[^a-z0-9]+/g, " ").trim() + " "
            if (identity.indexOf(needle) !== -1) return role
        }
    }
    return ""
}

function packCropForSource(source) {
    var value = String(source || "").split("?")[0].split("#")[0]
    if (value.indexOf("/components/dock/assets/app-icons/") === -1) return null
    for (var role in PACK_CROPS) {
        if (value.endsWith("/" + role + ".png")) return PACK_CROPS[role]
    }
    return null
}

function resolveIcon(item) {
    var data = item || {}
    var icon = String(data.icon || data.iconName || "").trim()
    if (icon) return icon

    var id = normalizeId(data.id || data.desktopId)
    if (FALLBACK_MAP[id]) return FALLBACK_MAP[id]

    var lower = id.toLowerCase()
    for (var key in FALLBACK_MAP) {
        if (key.toLowerCase() === lower) return FALLBACK_MAP[key]
    }
    return "application-x-executable"
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        FALLBACK_MAP: FALLBACK_MAP,
        PACK_ALIASES: PACK_ALIASES,
        PACK_ROLES: PACK_ROLES,
        PACK_CROPS: PACK_CROPS,
        sanitizeName: sanitizeName,
        normalizeId: normalizeId,
        customIconEntry: customIconEntry,
        customIconFile: customIconFile,
        customIconPack: customIconPack,
        customIconMode: customIconMode,
        hasCustomOverride: hasCustomOverride,
        automaticPackRole: automaticPackRole,
        packCropForSource: packCropForSource,
        resolveIcon: resolveIcon
    }
}
