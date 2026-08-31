const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

function loadQmlJs(path) {
  const source = fs.readFileSync(path, "utf8").replace(/^\.pragma library\s*/, "")
  const context = { module: { exports: {} }, console }
  vm.runInNewContext(source, context, { filename: path })
  return context.module.exports
}

const identity = loadQmlJs("ApplicationIdentity.js")

const entries = [
  {
    id: "org.gnome.Nautilus",
    startupWmClass: "org.gnome.Nautilus",
    execString: "nautilus --new-window"
  },
  {
    id: "org.kde.dolphin",
    startupWmClass: "dolphin",
    execString: "dolphin"
  },
  {
    id: "com.visualstudio.code",
    startupWmClass: ["electron", "Code"],
    aliases: ["code", "vscode"],
    execString: "/usr/bin/code --unity-launch"
  },
  {
    id: "io.codex.Code",
    startupWmClass: ["electron", "Codex"],
    aliases: ["codex"],
    execString: "/opt/codex/codex"
  },
  {
    id: "org.mozilla.firefox",
    startupWmClass: "firefox",
    execString: "flatpak run org.mozilla.firefox"
  },
  {
    id: "chromium",
    startupWmClass: "Chromium",
    aliases: ["chromium"],
    execString: "chromium"
  },
  {
    id: "google-chrome",
    startupWmClass: "Google-chrome",
    aliases: ["google-chrome"],
    execString: "google-chrome-stable"
  },
  {
    id: "web.whatsapp",
    aliases: ["whatsapp"],
    execString: "chromium --app=https://web.whatsapp.com"
  }
]

test("uses the documented exact, StartupWMClass, alias, and process priority", () => {
  assert.deepEqual(
    identity.resolve({ waylandAppId: "org.gnome.Nautilus" }, entries).method,
    "exact-app-id"
  )
  assert.equal(
    identity.resolve({ className: "dolphin" }, entries).id,
    "org.kde.dolphin"
  )
  assert.equal(
    identity.resolve({ className: "vscode" }, entries).method,
    "bounded-alias"
  )
  const process = identity.resolve({ executable: "/usr/bin/google-chrome-stable" }, entries)
  assert.equal(process.id, "google-chrome")
  assert.equal(process.method, "process-executable")
})

test("covers Flatpak and Chromium web-app identities without title matching", () => {
  assert.equal(
    identity.resolve({ appId: "org.mozilla.firefox" }, entries).id,
    "org.mozilla.firefox"
  )
  const pwa = identity.resolve({ className: "chrome-web.whatsapp.com__-Default" }, entries)
  assert.equal(pwa.id, "web.whatsapp")
  assert.equal(pwa.method, "bounded-alias")
  assert.equal(identity.resolve({ title: "com.visualstudio.code" }, entries).id, "")
})

test("uses stable initialClass after a generic mutable Electron class", () => {
  const code = identity.resolve({ className: "electron", initialClass: "Code" }, entries)
  const codex = identity.resolve({ className: "electron", initialClass: "Codex" }, entries)
  assert.equal(code.id, "com.visualstudio.code")
  assert.equal(codex.id, "io.codex.Code")
  assert.equal(code.method, "startup-wm-class")
  assert.equal(codex.method, "startup-wm-class")
})

test("fails closed for ambiguous aliases and process executables", () => {
  const shared = [
    { id: "org.example.Alpha", aliases: ["shared"], execString: "shared-bin" },
    { id: "org.example.Beta", aliases: ["shared"], execString: "shared-bin" }
  ]
  const byAlias = identity.resolve({ className: "shared" }, shared)
  assert.equal(byAlias.id, "")
  assert.equal(byAlias.method, "bounded-alias-ambiguous")
  assert.deepEqual(Array.from(byAlias.candidates), ["org.example.Alpha", "org.example.Beta"])

  const byProcess = identity.resolve({ processName: "shared-bin" }, shared)
  assert.equal(byProcess.id, "")
  assert.equal(byProcess.method, "process-executable-ambiguous")
})

test("keeps Code and Codex separate across GTK, Qt, Electron, and XWayland inputs", () => {
  assert.equal(identity.resolve({ className: "org.gnome.Nautilus" }, entries).id, "org.gnome.Nautilus")
  assert.equal(identity.resolve({ xwaylandClass: "dolphin" }, entries).id, "org.kde.dolphin")
  assert.equal(identity.resolve({ initialClass: "Code" }, entries).id, "com.visualstudio.code")
  assert.equal(identity.resolve({ initialClass: "Codex" }, entries).id, "io.codex.Code")
  assert.notEqual(
    identity.resolve({ initialClass: "Code" }, entries).id,
    identity.resolve({ initialClass: "Codex" }, entries).id
  )
})

test("enforces exact documented identity ceilings", () => {
  const id160 = "a".repeat(160)
  assert.equal(identity.resolve({ appId: id160 }, [{ id: id160 }]).id, id160)
  assert.equal(identity.resolve({ appId: "b".repeat(161) }, [{ id: "b".repeat(161) }]).id, "")

  const aliases = Array.from({ length: 17 }, (_, index) => "alias" + index)
  assert.equal(
    identity.resolve({ className: "alias15" }, [{ id: "alias-owner", aliases }]).id,
    "alias-owner"
  )
  assert.equal(
    identity.resolve({ className: "alias16" }, [{ id: "alias-owner", aliases }]).method,
    "unresolved"
  )

  const classes = Array.from({ length: 12 }, (_, index) => "unknown" + index)
  classes.push("Code")
  assert.equal(identity.resolve({ classes }, entries).method, "unresolved")

  const exec512 = "tool512 " + "x".repeat(504)
  const exec513 = "tool513 " + "x".repeat(505)
  assert.equal(exec512.length, 512)
  assert.equal(exec513.length, 513)
  const execEntries = [
    { id: "accepted", execString: exec512 },
    { id: "rejected", execString: exec513 }
  ]
  assert.equal(identity.resolve({ processName: "tool512" }, execEntries).id, "accepted")
  assert.equal(identity.resolve({ processName: "tool513" }, execEntries).method, "unresolved")

  const manyEntries = Array.from({ length: 4097 }, (_, index) => ({ id: "entry" + index }))
  assert.equal(identity.resolve({ appId: "entry4095" }, manyEntries).id, "entry4095")
  assert.equal(identity.resolve({ appId: "entry4096" }, manyEntries).method, "unresolved")
})
