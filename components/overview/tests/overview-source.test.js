const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")

const overview = fs.readFileSync("../Overview.qml", "utf8")
const card = fs.readFileSync("../WindowCard.qml", "utf8")
const helper = fs.readFileSync("../move-window-to-workspace", "utf8")

test("overview exposes the shared Inspector boundary", () => {
  assert.match(overview, /signal inspectRequested\(var payload, string screenName\)/)
  assert.match(overview, /function performInspectorAction\(actionId, context\)/)
  assert.match(overview, /windowForAddress\(data\.address \|\| data\.id/)
  assert.match(card, /controller\.requestInspector\(card\.modelData\)/)
})

test("workspace moving stays behind a validated argument-array dispatcher", () => {
  assert.match(overview, /WorkspaceModel\.moveRequest/)
  assert.match(overview, /workspaceMoveProcess\.command = \[/)
  assert.doesNotMatch(overview, /hyprctl dispatch movetoworkspace/)
  assert.match(helper, /\^0x\[0-9a-fA-F\]\+\$/)
  assert.match(helper, /hyprctl -j clients/)
  assert.match(helper, /hyprctl -j workspaces/)
  assert.ok((fs.statSync("../move-window-to-workspace").mode & 0o111) !== 0)
  assert.match(helper, /hl\.dsp\.window\.move\(\{ workspace = \\"\$workspace_id\\", follow = false, window = \\"address:\$address\\" \}\)/)
  assert.match(helper, /hyprctl dispatch movetoworkspacesilent "\$workspace_id,address:\$address"/)
  assert.ok(helper.indexOf("hl.dsp.window.move") < helper.indexOf("movetoworkspacesilent"))
})

test("workspace UI keeps pointer and keyboard action parity", () => {
  assert.match(overview, /acceptedButtons: Qt\.LeftButton \| Qt\.RightButton/)
  assert.match(overview, /Qt\.Key_Menu/)
  assert.match(overview, /Qt\.Key_F10/)
  assert.match(overview, /moveWorkspaceCursor/)
  assert.match(overview, /moveSelectedWindowToWorkspace/)
  assert.match(overview, /Accessible\.name: "Workspace board"/)
})
