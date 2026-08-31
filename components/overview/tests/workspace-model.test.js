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

const model = loadQmlJs("../WorkspaceModel.js")

test("orders only bounded ordinary workspaces", () => {
  const entries = model.ordinaryWorkspaces([
    { id: 8, name: "8" },
    { id: -99, name: "special:scratch" },
    { id: 2, name: "2" },
    { id: 1000, name: "1000" },
    { id: 2, name: "duplicate" },
    { id: 0, name: "named:writing" }
  ], [], { id: 8 })

  assert.deepEqual(Array.from(entries, entry => entry.id), [2, 8])
  assert.equal(entries[0].active, false)
  assert.equal(entries[1].active, true)
})

test("accepts Quickshell array-like workspace collections", () => {
  const qmlValues = {
    0: { id: 2, name: "2" },
    1: { id: 1, name: "1" },
    length: 2
  }
  const entries = model.ordinaryWorkspaces({ values: qmlValues }, [], { id: 1 })

  assert.deepEqual(Array.from(entries, entry => entry.id), [1, 2])
  assert.equal(entries[0].active, true)
})

test("derives occupancy from real windows", () => {
  const entries = model.ordinaryWorkspaces(
    [{ id: 1 }, { id: 4 }],
    [{ workspace: { id: 4 } }, { workspace: { id: 4 } }],
    { id: 1 }
  )

  assert.equal(entries[0].count, 0)
  assert.equal(entries[0].occupied, false)
  assert.equal(entries[1].count, 2)
  assert.equal(entries[1].occupied, true)
})

test("cycles in stable order", () => {
  const entries = [{ id: 1 }, { id: 3 }, { id: 8 }]
  assert.equal(model.cycleWorkspaceId(entries, 1, 1), 3)
  assert.equal(model.cycleWorkspaceId(entries, 1, -1), 8)
  assert.equal(model.cycleWorkspaceId(entries, 99, 1), 1)
})

test("accepts moves only for stable addresses and an existing workspace", () => {
  const entries = [{ id: 1, monitorName: "DP-1" }, { id: 4, monitorName: "DP-1" }]
  const request = model.moveRequest("0xABC123", 4242, 4, entries, "DP-1")
  assert.equal(request.ok, true)
  assert.equal(request.error, "")
  assert.equal(request.address, "0xabc123")
  assert.equal(request.pid, 4242)
  assert.equal(request.workspaceId, 4)
  assert.equal(request.monitorName, "DP-1")
  assert.equal(model.moveRequest("not-an-address", 4242, 4, entries, "DP-1").ok, false)
  assert.equal(model.moveRequest("0xabc123", 0, 4, entries, "DP-1").ok, false)
  assert.equal(model.moveRequest("0xabc123", 4242, 3, entries, "DP-1").ok, false)
  assert.equal(model.moveRequest("0xabc123", 4242, -99, entries, "DP-1").ok, false)
  assert.equal(model.moveRequest("0xabc123", 4242, 4, entries, "HDMI-A-1").ok, false)
})

test("normalizes numeric names but rejects named and special workspaces", () => {
  assert.equal(model.workspaceIdFor({ id: 0, name: "12" }), 12)
  assert.equal(model.workspaceIdFor({ id: 0, name: "named:writing" }), 0)
  assert.equal(model.workspaceIdFor({ id: -4, name: "special:scratch" }), 0)
})

test("scopes ordinary workspaces and occupancy to one monitor", () => {
  const dp = { name: "DP-1" }
  const hdmi = { name: "HDMI-A-1" }
  const workspaces = [
    { id: 1, name: "1", monitor: dp, active: true },
    { id: 2, name: "2", monitor: dp },
    { id: 8, name: "8", monitor: hdmi, active: true }
  ]
  const windows = [
    { workspace: workspaces[0], monitor: dp },
    { workspace: workspaces[2], monitor: hdmi }
  ]
  const entries = model.ordinaryWorkspaces(workspaces, windows, workspaces[0], "DP-1")

  assert.deepEqual(Array.from(entries, entry => entry.id), [1, 2])
  assert.equal(entries[0].count, 1)
  assert.equal(entries[0].active, true)
  assert.equal(entries[0].monitorName, "DP-1")
  assert.equal(model.countToplevelsOnMonitor(windows, "HDMI-A-1"), 1)
})

test("reports why scoped workspaces are unsupported", () => {
  const monitor = { name: "DP-1" }
  const summary = model.unsupportedWorkspaceSummary([
    { id: 1, name: "1", monitor },
    { id: -1, name: "named:writing", monitor },
    { id: -99, name: "special:scratch", monitor },
    { id: 1000, name: "1000", monitor },
    { id: 4, name: "4" },
    { id: -2, name: "named:other", monitor: { name: "HDMI-A-1" } }
  ], "DP-1")

  assert.equal(summary.total, 4)
  assert.equal(summary.named, 1)
  assert.equal(summary.special, 1)
  assert.equal(summary.outOfRange, 1)
  assert.equal(summary.unassigned, 1)
})

test("keeps the invoking monitor until it vanishes, then falls back deterministically", () => {
  const monitors = [{ name: "HDMI-A-1" }, { name: "DP-2" }, { name: "DP-1" }]
  assert.equal(model.chooseMonitorScope(monitors, "DP-2", "HDMI-A-1"), "DP-2")
  assert.equal(model.chooseMonitorScope(monitors, "VANISHED", "HDMI-A-1"), "HDMI-A-1")
  assert.equal(model.chooseMonitorScope(monitors, "VANISHED", "ALSO-GONE"), "DP-1")
  assert.equal(model.chooseMonitorScope([], "DP-1", "DP-1"), "")
})

test("enforces exact public input ceilings", () => {
  assert.equal(model.ordinaryWorkspaceId(999), 999)
  assert.equal(model.ordinaryWorkspaceId(1000), 0)
  assert.equal(model.normalizedAddress("0x1234567890abcdef"), "0x1234567890abcdef")
  assert.equal(model.normalizedAddress("0x1234567890abcdef0"), "")
  assert.equal(model.normalizedPid(4194304), 4194304)
  assert.equal(model.normalizedPid(4194305), 0)
  assert.equal(model.boundedMonitorName("D".repeat(128)).length, 128)
  assert.equal(model.boundedMonitorName("D".repeat(129)), "")
  assert.equal(model.boundedWindowIdentityText("I".repeat(256)).length, 256)
  assert.equal(model.boundedWindowIdentityText("I".repeat(257)), "")
  const maximumCollection = { length: 4096, 4095: { name: "DP-1" } }
  const oversizedCollection = { length: 4097, 4096: { name: "DP-2" } }
  assert.deepEqual(Array.from(model.monitorNames(maximumCollection)), ["DP-1"])
  assert.deepEqual(Array.from(model.monitorNames(oversizedCollection)), [])
})

test("rejects a reused address unless the complete stable fingerprint matches", () => {
  const original = {
    address: "0xabc123",
    pid: 4242,
    initialClass: "org.example.App",
    initialTitle: "Original window"
  }
  assert.equal(model.sameWindowIdentity(original, { ...original }), true)
  assert.equal(model.sameWindowIdentity(original, { ...original, pid: 4243 }), false)
  assert.equal(model.sameWindowIdentity(original, { ...original, initialTitle: "Replacement window" }), false)
  assert.equal(model.sameWindowIdentity({ ...original, initialClass: "", initialTitle: "" }, { ...original, initialClass: "", initialTitle: "" }), false)
})

test("parses only bounded move postcondition records", () => {
  const confirmed = model.parseMoveResult("confirmed\tlegacy\t0xABC123\t4\tDP-1\n")
  assert.equal(confirmed.state, "confirmed")
  assert.equal(confirmed.dispatcher, "legacy")
  assert.equal(confirmed.address, "0xabc123")
  assert.equal(confirmed.workspaceId, 4)
  assert.equal(confirmed.monitorName, "DP-1")
  assert.equal(model.parseMoveResult("confirmed\tother\t0xabc123\t4\tDP-1").state, "")
  assert.equal(model.parseMoveResult("pending\tlua\t0xabc123\t1000\tDP-1").state, "")
})
