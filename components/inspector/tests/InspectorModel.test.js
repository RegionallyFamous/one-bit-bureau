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

const model = loadQmlJs("../InspectorModel.js")

test("normalizes the supported object kinds", () => {
  assert.equal(model.normalizeContext({ kind: "app", name: "Files" }).kind, "app")
  assert.equal(model.normalizeContext({ kind: "window", name: "Notes" }).kind, "window")
  assert.equal(model.normalizeContext({ kind: "unknown", name: "Thing" }).kind, "desktop")
})

test("bounds facts, actions, and display strings", () => {
  const facts = Array.from({ length: 30 }, (_, index) => ({ label: "Fact " + index, value: "x".repeat(400) }))
  const actions = Array.from({ length: 30 }, (_, index) => ({ id: "action" + index, label: "Action " + index, enabled: true }))
  const result = model.normalizeContext({
    kind: "desktop",
    id: "i".repeat(400),
    name: "n".repeat(400),
    facts,
    actions
  })
  assert.equal(result.facts.length, model.LIMITS.facts)
  assert.equal(result.actions.length, model.LIMITS.actions)
  assert.equal(result.id.length, model.LIMITS.id)
  assert.equal(result.name.length, model.LIMITS.name)
  assert.equal(result.facts[0].value.length, model.LIMITS.factValue)
})

test("keeps unavailable actions visible with a reason", () => {
  const result = model.normalizeContext({
    name: "Read me",
    actions: [{ id: "rename", label: "Rename", enabled: false }]
  })
  assert.equal(result.actions.length, 1)
  assert.equal(result.actions[0].enabled, false)
  assert.equal(result.actions[0].reason, "Unavailable for this object")
})

test("missing objects disable every supplied action", () => {
  const result = model.normalizeContext({
    kind: "window",
    id: "0x123",
    name: "Editor",
    missing: true,
    missingReason: "Window closed",
    actions: [{ id: "focus", label: "Focus", enabled: true }]
  })
  assert.equal(result.missing, true)
  assert.equal(result.actions[0].enabled, false)
  assert.equal(result.actions[0].reason, "Window closed")
})

test("rejects malformed action ids without dropping their explanation", () => {
  const result = model.normalizeContext({
    name: "Unsafe",
    actions: [{ id: "open; rm -rf /", label: "Open", enabled: true }]
  })
  assert.equal(result.actions.length, 1)
  assert.equal(result.actions[0].enabled, false)
  assert.equal(result.actions[0].reason, "Action identifier is invalid")
  assert.match(result.actions[0].id, /^invalid-/)
})

test("strips control characters and drops unknown fields", () => {
  const result = model.normalizeContext({
    name: "A\u0000B\nC",
    path: "/secret/path",
    actions: []
  })
  assert.equal(result.name, "A B C")
  assert.equal(Object.prototype.hasOwnProperty.call(result, "path"), false)
})

test("keeps icon loading local", () => {
  assert.equal(model.normalizeIconSource("image://icon/org.example.App"), "image://icon/org.example.App")
  assert.equal(model.normalizeIconSource("file:///tmp/icon.png"), "file:///tmp/icon.png")
  assert.equal(model.normalizeIconSource("/tmp/My Icon.png"), "/tmp/My Icon.png")
  assert.equal(model.normalizeIconSource("https://example.com/tracker.png"), "")
})
