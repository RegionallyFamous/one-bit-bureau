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
    theme: ["aether", "theme designer", "theme editor"],
    document: ["org gnome evince", "document viewer", "evince", "pdf viewer"],
    disk: ["org gnome diskutility", "disk utility", "gnome disks", "disk usage", "disk image mounter", "disk image writer"],
    image: ["imv", "image viewer", "google photos", "photo viewer"],
    spreadsheet: ["libreoffice calc", "spreadsheet"],
    presentation: ["libreoffice impress", "presentation"],
    writer: ["libreoffice writer", "omawrite", "word processor"],
    transfer: ["localsend", "local send", "file transfer"],
    paint: ["pinta", "paint editor", "image editor"],
    "video-edit": ["kdenlive", "omacut", "video editor"],
    broadcast: ["obsproject studio", "obs studio", "screen recorder", "broadcast studio"],
    calculator: ["omacalc", "calculator"],
    printer: ["system config printer", "printer settings", "printing"],
    ocr: ["tensaku", "optical character recognition", "text recognition"],
    project: ["basecamp", "project management"],
    containers: ["docker", "lazydocker", "containers"],
    contacts: ["google contacts", "address book", "contacts"],
    maps: ["google maps", "maps"],
    social: [" x ", "twitter", "social feed"],
    files: ["nautilus", "dolphin", "thunar", "pcmanfm", "nemo", "cosmic files", "file manager"],
    terminal: ["foot", "kitty", "alacritty", "ghostty", "wezterm", "konsole", "kgx", "gnome console", "xterm"],
    browser: ["chromium", "chrome", "firefox", "brave", "vivaldi", "epiphany", "helium", "zen browser"],
    code: ["code", "codium", "cursor", "zed", "sublime text", "intellij", "pycharm", "webstorm", "neovim"],
    mail: ["hey", "thunderbird", "geary", "evolution", "mailspring", "proton mail"],
    chat: ["discord", "slack", "signal", "telegram", "mattermost", "element", "whatsapp", "google messages"],
    music: ["cliamp", "spotify", "rhythmbox", "lollypop", "amberol", "strawberry", "audacious", "music"],
    video: ["vlc", "mpv", "celluloid", "clapper", "totem", "youtube", "zoom", "video player"],
    calendar: ["calendar", "morgen", "fantastical"],
    settings: ["settings", "control center", "pavucontrol", "blueman", "nwg look"],
    games: ["moonlight", "steam", "lutris", "heroic", "bottles", "games"],
    notes: ["obsidian", "xournalpp", "xournal", "logseq", "joplin", "standard notes", "notes"],
    application: []
}

var PACK_ROLES = Object.keys(PACK_ALIASES)

// Every rendered pack asset is trimmed, scaled into the same 230px optical
// box, and centered on a 256px transparent canvas by render-app-icons.py.
var PACK_CROPS = {}
for (var cropIndex = 0; cropIndex < PACK_ROLES.length; cropIndex++)
    PACK_CROPS[PACK_ROLES[cropIndex]] = { x: 13, y: 13, width: 230, height: 230 }

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

function iconPresentationMode(customIcons, item) {
    var data = item || {}
    var id = data.id || data.desktopId
    if (customIconFile(customIcons, id)) return "custom"
    if (customIconPack(customIcons, id)) return "pack"
    if (customIconMode(customIcons, id) === "native") return "native"
    return automaticPackRole(data) ? "pack" : "native-grayscale"
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
        iconPresentationMode: iconPresentationMode,
        packCropForSource: packCropForSource,
        resolveIcon: resolveIcon
    }
}
