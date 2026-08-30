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
  const entries = [{ id: 1 }, { id: 4 }]
  const request = model.moveRequest("0xABC123", 4, entries)
  assert.equal(request.ok, true)
  assert.equal(request.error, "")
  assert.equal(request.address, "0xabc123")
  assert.equal(request.workspaceId, 4)
  assert.equal(model.moveRequest("not-an-address", 4, entries).ok, false)
  assert.equal(model.moveRequest("0xabc123", 3, entries).ok, false)
  assert.equal(model.moveRequest("0xabc123", -99, entries).ok, false)
})

test("normalizes numeric names but rejects named and special workspaces", () => {
  assert.equal(model.workspaceIdFor({ id: 0, name: "12" }), 12)
  assert.equal(model.workspaceIdFor({ id: 0, name: "named:writing" }), 0)
  assert.equal(model.workspaceIdFor({ id: -4, name: "special:scratch" }), 0)
})
