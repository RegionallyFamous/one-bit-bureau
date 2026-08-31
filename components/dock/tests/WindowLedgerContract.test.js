import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const panelBase = fs.readFileSync(path.join(here, "..", "DockPanelBase.qml"), "utf8")
const dockPanel = fs.readFileSync(path.join(here, "..", "DockPanel.qml"), "utf8")
const dockItem = fs.readFileSync(path.join(here, "..", "DockItem.qml"), "utf8")
const dockMenu = fs.readFileSync(path.join(here, "..", "DockMenu.qml"), "utf8")
const windowList = fs.readFileSync(path.join(here, "..", "WindowListPanel.qml"), "utf8")

test("dock items expose truthful count, activity, and workspace state", () => {
  assert.match(panelBase, /property var windowLedger:/)
  assert.match(panelBase, /currentWorkspaceWindowCount: wrapper\.ledgerData\.currentWorkspaceCount/)
  assert.match(panelBase, /otherWorkspaceWindowCount: wrapper\.ledgerData\.otherWorkspaceCount/)
  assert.match(panelBase, /active: wrapper\.ledgerData\.active/)
  assert.match(dockItem, /windowCountLabel/)
  assert.match(dockItem, /currentWorkspaceWindowCount/)
  assert.match(dockItem, /otherWorkspaceWindowCount/)
  assert.match(dockItem, /Accessible\.description:\s*root\.accessibleState/)
  assert.match(dockItem, /Accessible\.selected:\s*!!root\.itemData\.active/)
})

test("focus uses per-app MRU candidates and never launches a known-running app", () => {
  assert.match(panelBase, /property var windowMruByApp:/)
  assert.match(panelBase, /WindowLedger\.touchMru/)
  assert.match(panelBase, /WindowLedger\.orderWindows/)
  assert.match(panelBase, /function focusWindowAddresses\(appId, addresses\)/)
  assert.match(panelBase, /if \(item\.running \|\| root\.appIsRunning\(id\)\) \{[\s\S]*?focusAppWindows\(id\)[\s\S]*?return true/)
  assert.match(panelBase, /if \(root\.appIsRunning\(canonical\)\) \{[\s\S]*?focusAppWindows\(canonical\)[\s\S]*?return true/)
  assert.match(panelBase, /exitCode !== 0 && root\.focusFallbackAddresses\.length/)
  assert.match(panelBase, /function liveWindowForAddress\(address, expectedAppId\)/)
  assert.match(panelBase, /root\.liveWindowForAddress\(normalized, root\.focusRequestAppId\)/)
  assert.match(panelBase, /item\.running \|\| root\.appIsRunning\(id\)/)
})

test("window list is explicit, keyboard accessible, and capture-free", () => {
  assert.match(dockMenu, /action: "showWindows"/)
  assert.match(dockItem, /Qt\.Key_Up[\s\S]*windowListRequested/)
  assert.match(windowList, /WlrLayershell\.keyboardFocus:\s*root\.opened\s*\?\s*WlrKeyboardFocus\.Exclusive/)
  assert.match(windowList, /text: "Activate"|model: \["Activate", "Close"\]/)
  assert.match(windowList, /Qt\.Key_Up/)
  assert.match(windowList, /Qt\.Key_Down/)
  assert.match(windowList, /Qt\.Key_Left/)
  assert.match(windowList, /Qt\.Key_Right/)
  assert.match(windowList, /Qt\.Key_Delete/)
  assert.match(windowList, /Accessible\.role:\s*Accessible\.Button/)
  assert.doesNotMatch(windowList, /ScreencopyView|grim|magick|captureProcess/)
})

test("Get Info routes to the shared Inspector through a narrow dock contract", () => {
  assert.match(dockMenu, /action: "inspect", label: "Get Info"/)
  assert.match(panelBase, /signal inspectorRequested\(var context, var invokingScreen, point invokingPosition\)/)
  assert.match(panelBase, /function inspectorContextForApp\(appId\)/)
  assert.match(panelBase, /function performInspectorAction\(actionId, context\)/)
  assert.match(panelBase, /function contextAppId\(context\)/)
  assert.match(dockPanel, /readonly property var windowLedger:\s*dock\.windowLedger/)
  assert.match(dockPanel, /signal inspectorRequested/)
  assert.match(dockPanel, /function performInspectorAction\(actionId, context\)/)
})

test("window actions expose truthful requested, observed, and failed status", () => {
  assert.match(panelBase, /signal actionStatusReported\(var status\)/)
  assert.match(panelBase, /function beginActionObservation\(/)
  assert.match(panelBase, /WindowLedger\.focusObserved/)
  assert.match(panelBase, /WindowLedger\.closeObserved/)
  assert.match(panelBase, /WindowLedger\.newWindowObserved/)
  assert.match(panelBase, /"requested"/)
  assert.match(panelBase, /"observed"/)
  assert.match(panelBase, /"failed"/)
  assert.match(panelBase, /function getLastActionStatus\(\): string/)
  assert.match(dockPanel, /readonly property var lastActionStatus:\s*dock\.lastActionStatus/)
  assert.match(dockPanel, /signal actionStatusReported\(var status\)/)
})

test("close and new-window dispatch re-resolve identity and never use stale row handles", () => {
  assert.match(panelBase, /function closeWindowData\(data, expectedAppId\)/)
  assert.match(panelBase, /root\.liveWindowForAddress\(address, appId\)/)
  assert.doesNotMatch(panelBase, /data\.waylandToplevel\.close/)
  assert.match(panelBase, /function requestNewWindow\(appId, name\)/)
  assert.match(panelBase, /return root\.requestNewWindow\(id, item\.name\)/)
})
