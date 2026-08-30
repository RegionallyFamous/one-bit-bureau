const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "..", "IconPickerPanel.qml"), "utf8")
const surface = source.slice(source.indexOf("// ---- Surface"))

test("icon manager uses opaque square One-Bit Bureau geometry", () => {
  assert.match(surface, /id: card[\s\S]*?radius: 0[\s\S]*?color: Color\.background[\s\S]*?border\.color: Color\.foreground[\s\S]*?border\.width: 2/)
  assert.match(surface, /id: headerRow[\s\S]*?radius: 0[\s\S]*?color: Color\.foreground/)
  assert.doesNotMatch(surface, /Util\.alpha|🔍|🔎|✕/)

  const radii = [...surface.matchAll(/radius:\s*([^\n]+)/g)].map(match => match[1].trim())
  assert.ok(radii.length >= 6, "the panel declares its important square surfaces")
  assert.ok(radii.every(radius => radius === "0"), `non-square radii found: ${radii.join(", ")}`)
})

test("picker grid and app list expose bounded keyboard cursor movement", () => {
  assert.match(source, /function clampedIndex\(index, count\)/)
  assert.match(source, /function focusGridIndex\(index\)[\s\S]*resultGrid\.positionViewAtIndex\(next, GridView\.Contain\)/)
  assert.match(source, /function moveGridCursor\(index, key\)[\s\S]*Qt\.Key_Left[\s\S]*Qt\.Key_Right[\s\S]*Qt\.Key_Up[\s\S]*Qt\.Key_Down[\s\S]*Qt\.Key_Home[\s\S]*Qt\.Key_End/)
  assert.match(source, /function focusAppIndex\(index, action\)[\s\S]*appList\.positionViewAtIndex\(next, ListView\.Contain\)/)
  assert.match(source, /id: searchField[\s\S]*Keys\.onDownPressed:[\s\S]*focusGridIndex/)
  assert.match(source, /id: appsField[\s\S]*Keys\.onDownPressed:[\s\S]*focusAppIndex/)
  assert.match(source, /function focusAction\(action\)[\s\S]*changeAction\.forceActiveFocus[\s\S]*clearAction\.forceActiveFocus/)
})

test("every action path supports keyboard activation and assistive technology", () => {
  assert.match(source, /component ActionButton: Item[\s\S]*implicitHeight: 44[\s\S]*activeFocusOnTab: enabled && visible/)
  assert.match(source, /Keys\.onPressed: function\(event\)[\s\S]*Qt\.Key_Space[\s\S]*Qt\.Key_Return[\s\S]*Qt\.Key_Enter/)
  assert.match(source, /Accessible\.role: Accessible\.Button/)
  assert.match(source, /Accessible\.name: buttonSelf\.accessibleName/)
  assert.match(source, /Accessible\.description: buttonSelf\.accessibleDescription/)
  assert.match(source, /Accessible\.focusable: (?:enabled|buttonSelf\.enabled) && (?:visible|buttonSelf\.visible)/)
  assert.match(source, /Accessible\.onPressAction:/)
  assert.match(source, /id: changeAction[\s\S]*accessibleName: "Change icon for "/)
  assert.match(source, /id: clearAction[\s\S]*accessibleName: "Clear custom icon for "/)
  assert.match(source, /id: automaticAction[\s\S]*?text: "Automatic"[\s\S]*?height: 44/)
  assert.match(source, /id: nativeAction[\s\S]*?text: "Native"[\s\S]*?height: 44/)
  assert.match(source, /id: doneAction[\s\S]*?text: "Done"[\s\S]*?height: 44/)
})

test("escape and bounded helper execution remain part of the panel contract", () => {
  assert.match(source, /Keys\.onEscapePressed: function\(event\) \{ root\.close\(\); event\.accepted = true \}/)
  assert.match(source, /applyProcess\.command = \["python3", root\.runHelperPath, "2200", "250", "--"\]\.concat\(command\)/)
  assert.match(source, /applyDeadline\.restart\(\)/)
  assert.match(source, /interval: 2500/)
  assert.match(source, /Component\.onDestruction:[\s\S]*applyProcess\.running = false/)
})

test("icon manager previews automatic native fallbacks in grayscale", () => {
  assert.match(source, /property var grayscaleFor: function\(id\) \{ return false \}/)
  assert.match(source, /id: previewImage[\s\S]*?grayscale: root\.mode === "picker" && root\.grayscaleFor\(root\.currentAppId\)/)
  assert.match(source, /id: rowIcon[\s\S]*?grayscale: root\.grayscaleFor\(modelData\.id\)/)
  assert.match(source, /id: nativeAction[\s\S]*?accessibleDescription: "Use the application's original icon"/)
})
