const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")

const panel = fs.readFileSync("../InspectorPanel.qml", "utf8")
const view = fs.readFileSync("../InspectorView.qml", "utf8")

test("panel exposes the hosted inspector lifecycle and intent boundary", () => {
  assert.match(panel, /signal actionRequested\(string action, var context\)/)
  assert.match(panel, /signal closed\(\)/)
  assert.match(panel, /function openContext\(nextContext, screen, position\)/)
  assert.match(panel, /WlrLayershell\.keyboardFocus: root\.opened \? WlrKeyboardFocus\.Exclusive/)
  assert.match(panel, /screen: root\.invokingScreen \|\|/)
})

test("panel supports outside and Escape dismissal", () => {
  assert.match(panel, /onClicked: root\.dismiss\(\)/)
  assert.match(view, /Keys\.onEscapePressed/)
  assert.match(view, /root\.closeRequested\(\)/)
})

test("view exposes identity, facts, actions, accessibility, and reduced motion", () => {
  assert.match(view, /IDENTITY/)
  assert.match(view, /FACTS/)
  assert.match(view, /ACTIONS/)
  assert.match(view, /Accessible\.name/)
  assert.match(view, /enabled: !root\.reducedMotion/)
  assert.match(view, /actionsFlick\.itemAtIndex\(next\)/)
  assert.doesNotMatch(view, /actionRepeater/)
  assert.match(view, /UNAVAILABLE/)
  assert.match(view, /modelData\.reason/)
  assert.match(view, /Press again to confirm/)
})
