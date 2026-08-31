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

const ledger = loadQmlJs("WindowLedger.js")

test("normalizes only Hyprland window addresses", () => {
  assert.equal(ledger.normalizeAddress("ABC123"), "0xabc123")
  assert.equal(ledger.normalizeAddress("0xDEF456"), "0xdef456")
  assert.equal(ledger.normalizeAddress("address:0xabc"), "")
  assert.equal(ledger.normalizeAddress("not-an-address"), "")
})

test("tracks a bounded per-app window MRU without mutating prior state", () => {
  const initial = { firefox: ["0xaaa", "0xbbb"], foot: ["0x111"] }
  const touched = ledger.touchMru(initial, "firefox", "0xbbb", 3)
  assert.deepEqual(Array.from(touched.firefox), ["0xbbb", "0xaaa"])
  assert.deepEqual(Array.from(initial.firefox), ["0xaaa", "0xbbb"])
  assert.deepEqual(Array.from(touched.foot), ["0x111"])

  let bounded = touched
  bounded = ledger.touchMru(bounded, "firefox", "0xccc", 2)
  assert.deepEqual(Array.from(bounded.firefox), ["0xccc", "0xbbb"])
})

test("orders windows by live MRU then active, workspace, and stable address", () => {
  const current = { id: 2, name: "2" }
  const windows = [
    { address: "0xccc", workspaceId: 3, active: false },
    { address: "0xaaa", workspaceId: 2, active: false },
    { address: "0xbbb", workspaceId: 2, active: true }
  ]
  const ordered = ledger.orderWindows(windows, ["0xccc", "0xstale"], current, "0xbbb")
  assert.deepEqual(Array.from(ordered, item => item.address), ["0xccc", "0xbbb", "0xaaa"])

  const unseen = ledger.orderWindows(windows, [], current, "0xbbb")
  assert.deepEqual(Array.from(unseen, item => item.address), ["0xbbb", "0xaaa", "0xccc"])
})

test("summarizes active and cross-workspace window truth", () => {
  const windows = [
    { address: "0xaaa", workspaceId: 2 },
    { address: "0xbbb", workspaceId: 3 },
    { address: "0xccc", workspaceId: 2, pinned: true }
  ]
  const summary = ledger.summarizeWindows(windows, { id: 2 }, "0xbbb")
  assert.equal(summary.count, 3)
  assert.equal(summary.countLabel, "3+")
  assert.equal(summary.active, true)
  assert.equal(summary.currentWorkspaceCount, 2)
  assert.equal(summary.otherWorkspaceCount, 1)
  assert.deepEqual(Array.from(ledger.focusAddresses(windows)), ["0xaaa", "0xbbb", "0xccc"])
})

test("accessible descriptions report activity, count, and workspace split", () => {
  assert.equal(
    ledger.accessibleDescription({
      pinned: true,
      running: true,
      active: true,
      windowCount: 2,
      currentWorkspaceWindowCount: 1,
      otherWorkspaceWindowCount: 1
    }),
    "Pinned application, active, 2 windows, 1 on the current workspace, 1 on other workspaces"
  )
  assert.equal(
    ledger.accessibleDescription({ pinned: false, running: true, windowCount: 0 }),
    "Application, running; window details updating"
  )
  assert.equal(ledger.accessibleDescription({ pinned: false, running: false }), "Application")
})

test("focus postconditions require the active address to retain the expected identity", () => {
  const windows = [
    { appId: "firefox", address: "0xaaa" },
    { appId: "terminal", address: "0xbbb" }
  ]
  assert.equal(ledger.focusObserved(windows, "0xaaa", "firefox", "0xaaa"), true)
  assert.equal(ledger.focusObserved(windows, "0xaaa", "terminal", "0xaaa"), false)
  assert.equal(ledger.focusObserved(windows, "0xaaa", "firefox", "0xbbb"), false)
  assert.equal(ledger.focusObserved(windows, "0xstale", "firefox", "0xstale"), false)
})

test("close postconditions accept disappearance or address reuse by another app", () => {
  assert.equal(ledger.closeObserved([], "0xaaa", "firefox"), true)
  assert.equal(
    ledger.closeObserved([{ appId: "terminal", address: "0xaaa" }], "0xaaa", "firefox"),
    true
  )
  assert.equal(
    ledger.closeObserved([{ appId: "firefox", address: "0xaaa" }], "0xaaa", "firefox"),
    false
  )
})

test("new-window postconditions require a new address for the expected app", () => {
  const windows = [
    { appId: "firefox", address: "0xaaa" },
    { appId: "firefox", address: "0xbbb" },
    { appId: "terminal", address: "0xccc" }
  ]
  assert.equal(ledger.newWindowObserved(["0xaaa"], windows, "firefox"), true)
  assert.equal(ledger.newWindowObserved(["0xaaa", "0xbbb"], windows, "firefox"), false)
  assert.equal(ledger.newWindowObserved(["0xaaa"], [windows[0], windows[2]], "firefox"), false)
})
