import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const panelBase = fs.readFileSync(path.join(here, "..", "DockPanelBase.qml"), "utf8")
const dockItem = fs.readFileSync(path.join(here, "..", "DockItem.qml"), "utf8")
const dockMenu = fs.readFileSync(path.join(here, "..", "DockMenu.qml"), "utf8")
const previewPanel = fs.readFileSync(path.join(here, "..", "WindowPreviewPanel.qml"), "utf8")
const previewCard = fs.readFileSync(path.join(here, "..", "WindowPreview.qml"), "utf8")
const altTab = fs.readFileSync(path.join(here, "..", "AltTabPanel.qml"), "utf8")
const packImage = fs.readFileSync(path.join(here, "..", "PackAwareImage.qml"), "utf8")

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

test("dock artwork is vertically centered and exposes its live offset", () => {
  assert.match(dockItem, /PackAwareImage \{[\s\S]*?anchors\.verticalCenter: parent\.verticalCenter/)
  assert.match(dockItem, /readonly property real iconCenterOffset:/)
  assert.match(panelBase, /function getMaxIconCenterOffset\(\): int/)
})

test("unmatched automatic app icons stay grayscale across dock surfaces", () => {
  assert.match(packImage, /property bool grayscale: false/)
  assert.match(packImage, /layer\.enabled:\s*root\.grayscale/)
  assert.match(packImage, /MultiEffect \{\s*saturation: -1\.0/)
  assert.match(panelBase, /function iconUsesAutomaticNativeFallback\(item\)/)
  assert.match(panelBase, /=== "native-grayscale"/)
  assert.match(panelBase, /grayscaleIcon:\s*root\.iconUsesAutomaticNativeFallback\(modelData\)/)
  assert.match(panelBase, /ghostGrayscale\s*=\s*root\.iconUsesAutomaticNativeFallback\(item\)/)
  assert.match(panelBase, /function getIconReadyForApp\(appId: string\): bool/)
  assert.match(panelBase, /function getIconGrayscale\(appId: string\): bool/)
  assert.match(panelBase, /function getIconBounds\(appId: string\): string/)
  assert.match(previewPanel, /iconGrayscale:\s*root\.iconGrayscaleFor\(w\)/)
  assert.match(previewCard, /grayscale:\s*root\.iconGrayscale/)
  assert.match(altTab, /grayscale:\s*root\.grayscaleFor\(modelData\)/)
})

test("dock items expose an accessible press action and keyboard context menu", () => {
  assert.match(dockItem, /Accessible\.role:\s*Accessible\.Button/)
  assert.match(dockItem, /Accessible\.name:/)
  assert.match(dockItem, /Accessible\.focusable:\s*true/)
  assert.match(dockItem, /Accessible\.selected:\s*!!root\.itemData\.active/)
  assert.match(dockItem, /Accessible\.onPressAction:/)
  assert.match(dockItem, /Qt\.Key_Menu/)
  assert.match(dockItem, /Qt\.Key_F10[\s\S]*Qt\.ShiftModifier/)
})

test("dock menu skips inert rows and supports full keyboard traversal", () => {
  assert.match(dockMenu, /WlrLayershell\.keyboardFocus:\s*root\.opened\s*\?\s*WlrKeyboardFocus\.Exclusive/)
  assert.match(dockMenu, /function moveCursor\(direction\)/)
  assert.match(dockMenu, /Qt\.Key_Up/)
  assert.match(dockMenu, /Qt\.Key_Down/)
  assert.match(dockMenu, /Qt\.Key_Home/)
  assert.match(dockMenu, /Qt\.Key_End/)
  assert.match(dockMenu, /Qt\.Key_Space/)
  assert.match(dockMenu, /Qt\.Key_Escape/)
  assert.match(dockMenu, /event\.modifiers\s*&\s*Qt\.MetaModifier/)
  assert.match(dockMenu, /Color\.menu\.selectedBackground/)
  assert.match(dockMenu, /Color\.menu\.selectedText/)
})

test("reduced motion is read strictly from inline plugin config and disables dock previews", () => {
  assert.match(panelBase, /inlinePluginSetting\("reducedMotion", false\)\s*===\s*true/)
  assert.match(panelBase, /config\.bar\s*&&\s*config\.bar\.layout/)
  assert.match(panelBase, /function getReducedMotion\(\): bool/)
  assert.match(panelBase, /reducedMotion:\s*root\.reducedMotion/)
  assert.match(previewPanel, /enabled:\s*!root\.reducedMotion/)
  assert.match(previewPanel, /animationEnabled:\s*!root\.reducedMotion/)
  assert.match(previewCard, /enabled:\s*root\.animationEnabled/)
})

test("acceptance can open and inspect the icon manager over narrow IPC", () => {
  assert.match(panelBase, /function openManageIcons\(\): bool/)
  assert.match(panelBase, /function closeManageIcons\(\): bool/)
  assert.match(panelBase, /function getIconPickerOpen\(\): bool/)
  assert.match(panelBase, /function getIconPickerMode\(\): string/)
  assert.match(panelBase, /function getMenuCurrentAction\(\): string/)
  assert.match(panelBase, /function getAutoHidden\(\): bool/)
  assert.match(panelBase, /property int edgeHeight: 6/)
  assert.match(panelBase, /function getEdgeHovered\(\): bool/)
  assert.match(panelBase, /function getAltTabActive\(\): bool/)
  assert.match(panelBase, /function openMenuForApp\(appId: string\): bool/)
})
