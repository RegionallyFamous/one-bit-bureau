import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const panelBase = fs.readFileSync(path.join(here, "..", "DockPanelBase.qml"), "utf8")
const previewPanel = fs.readFileSync(path.join(here, "..", "WindowPreviewPanel.qml"), "utf8")

test("preview batch ids are numeric and active captures use a non-batch sentinel", () => {
  assert.match(panelBase, /required property int jobBatch/)
  assert.match(panelBase, /jobBatch:\s*-1/)
  assert.match(panelBase, /self\.jobBatch === root\.currentThumbBatch/)
})

test("preview layer stays hidden until the batch is committed", () => {
  assert.match(previewPanel, /readonly property bool panelActive:\s*root\.previewVisible/)
  assert.doesNotMatch(previewPanel, /previewVisible\s*\|\|\s*root\.windowList/)
})

test("preview capture has a hard timeout so failed jobs still commit the batch", () => {
  assert.equal((panelBase.match(/command: \["timeout", "--kill-after=1s", "3s"/g) || []).length, 2)
})

test("the plugin never replaces global Alt+Tab bindings at runtime", () => {
  assert.doesNotMatch(panelBase, /hl\.unbind\(\\?"ALT \+ TAB/)
  assert.doesNotMatch(panelBase, /o\.bind\(\\?"ALT \+ TAB/)
  assert.doesNotMatch(panelBase, /altTabBindRetry|altTabBindProcess/)
})

test("window focus delegates temporary cursor state to the trap-safe helper", () => {
  assert.match(panelBase, /focusWindowProcess\.command = \["bash", root\.focusHelperPath, normalized\]/)
  assert.doesNotMatch(panelBase, /pendingCursorPosition|focusNoWarpProcess|restoreCursorWarps/)
})
