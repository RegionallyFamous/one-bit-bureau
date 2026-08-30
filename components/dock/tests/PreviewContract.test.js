import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const panelBase = fs.readFileSync(path.join(here, "..", "DockPanelBase.qml"), "utf8")
const previewPanel = fs.readFileSync(path.join(here, "..", "WindowPreviewPanel.qml"), "utf8")

test("preview cards commit immediately with app-icon fallbacks", () => {
  assert.match(panelBase, /function snapshotWindows\(\)[\s\S]*root\.applyThumbnails\(\)/)
  assert.match(panelBase, /function thumbnailFor\(w\) \{\s*return ""/)
})

test("preview layer stays hidden until the batch is committed", () => {
  assert.match(previewPanel, /readonly property bool panelActive:\s*root\.previewVisible/)
  assert.doesNotMatch(previewPanel, /previewVisible\s*\|\|\s*root\.windowList/)
})

test("preview does not launch compositor capture or ImageMagick pipelines", () => {
  assert.doesNotMatch(panelBase, /\bgrim\b|\bmagick\b|captureProcess|thumbnailCommand/)
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
