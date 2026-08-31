from __future__ import annotations

import re
import unittest
from pathlib import Path


SERVICE = (Path(__file__).resolve().parents[1] / "Service.qml").read_text(
    encoding="utf-8"
)
BAR_WIDGET = (
    Path(__file__).resolve().parents[2] / "active-window" / "BarWidget.qml"
).read_text(encoding="utf-8")


class DesktopQmlContractTest(unittest.TestCase):
    def test_safe_image_files_use_bounded_local_thumbnails(self) -> None:
        self.assertIn("import QtQuick.Effects", SERVICE)
        self.assertIn("layer.enabled: iconRoot.photoPreview", SERVICE)
        self.assertIn("layer.effect: MultiEffect", SERVICE)
        self.assertIn("saturation: -1.0", SERVICE)
        self.assertRegex(
            SERVICE,
            r'if \(kind === "image"\)\s*return root\.hasImagePreview\(item\) \? "" : "image"',
        )
        self.assertIn("function hasImagePreview(item)", SERVICE)
        self.assertIn("? Image.PreserveAspectCrop", SERVICE)
        self.assertIn(": Image.PreserveAspectFit", SERVICE)

    def test_photo_selection_keeps_one_constant_grayscale_preview(self) -> None:
        self.assertIn("readonly property bool photoPreview", SERVICE)
        self.assertIn(
            "iconRoot.selected && (panel.host.usesCategoryIcon(iconRoot.modelData) || iconRoot.photoPreview)",
            SERVICE,
        )
        self.assertIn("id: nameRail", SERVICE)
        self.assertIn("desktop thumbnail stays grayscale", SERVICE)
        self.assertEqual(SERVICE.count("layer.effect: MultiEffect"), 1)

    def test_context_menu_has_complete_keyboard_navigation(self) -> None:
        self.assertIn("event.key === Qt.Key_Menu", SERVICE)
        self.assertRegex(
            SERVICE,
            r"event\.key === Qt\.Key_F10 && \(event\.modifiers & Qt\.ShiftModifier\)",
        )
        self.assertIn("function moveMenuCursor(delta)", SERVICE)
        self.assertIn("function activateMenuCursor()", SERVICE)
        self.assertIn("event.key === Qt.Key_Home", SERVICE)
        self.assertIn("event.key === Qt.Key_End", SERVICE)
        self.assertIn("panel.activateMenuCursor()", SERVICE)
        self.assertIn("height: 44", SERVICE)

    def test_desktop_objects_and_dialog_controls_expose_accessibility(self) -> None:
        for role in (
            "Accessible.ListItem",
            "Accessible.PopupMenu",
            "Accessible.MenuItem",
            "Accessible.Dialog",
            "Accessible.AlertMessage",
            "Accessible.Button",
        ):
            with self.subTest(role=role):
                self.assertIn(role, SERVICE)
        for state in (
            "Accessible.name:",
            "Accessible.description:",
            "Accessible.selected:",
            "Accessible.onPressAction:",
        ):
            with self.subTest(state=state):
                self.assertIn(state, SERVICE)
        # Qt derives the accessible disabled state from Item.enabled; there is
        # intentionally no non-existent Accessible.disabled attached property.
        self.assertIn("enabled: rowEnabled", SERVICE)
        self.assertNotIn("Accessible.disabled:", SERVICE)

    def test_index_failures_have_a_visible_accessible_status(self) -> None:
        self.assertIn('property string statusMessage: ""', SERVICE)
        self.assertIn("root.plainText(data.error, 240)", SERVICE)
        self.assertIn("id: statusBox", SERVICE)
        self.assertIn(
            "host.statusIsError ? Accessible.AlertMessage : Accessible.StaticText",
            SERVICE,
        )

    def test_operation_receipts_are_observable_for_deterministic_acceptance(self) -> None:
        self.assertIn(
            "function getOperationMessage(): string { return root.operationMessage }",
            SERVICE,
        )

    def test_super_modified_keys_are_released_before_plugin_handling(self) -> None:
        key_handler = re.search(
            r"Keys\.onPressed: function\(event\) \{(?P<body>.*?)\n\s*\}",
            SERVICE,
            re.DOTALL,
        )
        self.assertIsNotNone(key_handler)
        body = key_handler.group("body")
        self.assertRegex(
            body,
            r"if \(event\.modifiers & Qt\.MetaModifier\) \{\s*event\.accepted = false\s*return",
        )

    def test_trust_dialog_keeps_enter_safe_but_allows_tab_space(self) -> None:
        trust_keys = re.search(
            r"if \(host\.pendingTrust\) \{(?P<body>.*?)event\.accepted = true",
            SERVICE,
            re.DOTALL,
        )
        self.assertIsNotNone(trust_keys)
        body = trust_keys.group("body")
        self.assertIn("Qt.Key_Return", body)
        self.assertIn("host.clearTrustPrompt()", body)
        self.assertIn("Qt.Key_Tab", body)
        self.assertIn("Qt.Key_Up", body)
        self.assertIn("Qt.Key_Down", body)
        self.assertIn("Qt.Key_Space", body)
        self.assertIn("host.trustAndOpen(host.pendingTrust)", body)

    def test_bounded_multi_selection_has_pointer_and_keyboard_parity(self) -> None:
        self.assertIn("property var selectedIds: []", SERVICE)
        self.assertIn("readonly property int maxOperationItems: 64", SERVICE)
        self.assertIn("function setSelectedIds(ids, cursorId, anchorId)", SERVICE)
        self.assertIn("function selectItem(item, modifiers, screenName)", SERVICE)
        self.assertIn("modifiers & Qt.ControlModifier", SERVICE)
        self.assertIn("modifiers & Qt.ShiftModifier", SERVICE)
        self.assertIn("event.key === Qt.Key_A", SERVICE)
        self.assertIn("event.key === Qt.Key_Space", SERVICE)
        self.assertIn("function moveSelectionSpatial(dx, dy, screenName, extend)", SERVICE)
        self.assertIn("Accessible.selected: iconRoot.selected", SERVICE)
        self.assertIn("property bool preservedMultiSelectionOnPress: false", SERVICE)
        self.assertIn("&& panel.host.selectedIds.length > 1", SERVICE)
        self.assertIn("!iconRoot.preservedMultiSelectionOnPress", SERVICE)

    def test_routes_name_noun_verb_and_destination_before_commit(self) -> None:
        self.assertRegex(SERVICE, r"panel\.routeNoun\s*\+ \" -> \"")
        self.assertIn('" -> " + panel.routeDestination', SERVICE)
        self.assertIn('verb = "Move to Trash"', SERVICE)
        self.assertIn('"Target does not accept files"', SERVICE)
        self.assertIn("panel.routeTargetId === String(iconRoot.modelData.id", SERVICE)
        self.assertIn('Accessible.name: panel.dragItems.length + " selected items"', SERVICE)
        self.assertIn('target: "regionallyfamous.one-bit-bureau.desktop"', SERVICE)
        self.assertIn("function getRouteVisible(): bool", SERVICE)
        self.assertIn("function getRouteValid(): bool", SERVICE)
        self.assertIn("function getRouteReason(): string", SERVICE)
        self.assertIn("function getLastRouteValid(): bool", SERVICE)
        self.assertIn("function getLastRouteReason(): string", SERVICE)
        self.assertIn("root.lastRouteSummary = root.routeSummary", SERVICE)
        self.assertIn("host.publishRouteState(panel.screenName", SERVICE)
        self.assertIn("host.clearRouteState(panel.screenName)", SERVICE)
        self.assertIn("Math.max(host.padBottom, 112)", SERVICE)

    def test_external_drops_accept_only_bounded_local_paths(self) -> None:
        self.assertIn("function localPath(value)", SERVICE)
        self.assertIn('if (path.indexOf("file://") === 0)', SERVICE)
        self.assertIn('if (path.indexOf("://") !== -1)', SERVICE)
        self.assertIn("panel.pathItems(urls)", SERVICE)
        self.assertIn("urls.length < panel.host.maxOperationItems", SERVICE)
        self.assertIn("panel.host.dropMode(drop)", SERVICE)

    def test_structured_helper_receipts_and_truthful_undo(self) -> None:
        self.assertIn('readonly property string operationScript: pluginDir + "/bin/desktop-operation"', SERVICE)
        self.assertIn('"reserve", command, "--source-count", String(sourceCount)', SERVICE)
        self.assertIn('"--operation-id", id', SERVICE)
        self.assertIn('cmd.push("--destination")', SERVICE)
        self.assertIn("data.schemaVersion !== 1", SERVICE)
        self.assertIn("data.undoable === true && root.operationId !== \"\"", SERVICE)
        self.assertIn('["/usr/bin/python3", root.operationScript, "undo", root.operationId]', SERVICE)
        self.assertIn('? "Undo desk layout" : "Undo desktop action"', SERVICE)
        self.assertIn("event.key === Qt.Key_Z", SERVICE)

    def test_top_bar_uses_canonical_ipc_for_stable_desk_menu(self) -> None:
        self.assertIn('target: "regionallyfamous.one-bit-bureau.desktop"', SERVICE)
        for ipc_method in (
            "function openDeskMenu(screenName: string): bool",
            "function closeDeskMenu(): bool",
            "function toggleDeskMenu(screenName: string): bool",
            "function getDeskMenuOpen(): bool",
            "function getDeskMenuCurrentAction(): string",
            "function getSelectionCount(): int",
        ):
            with self.subTest(ipc_method=ipc_method):
                self.assertIn(ipc_method, SERVICE)
        self.assertIn('Quickshell.env("OMARCHY_PATH")', BAR_WIDGET)
        self.assertIn(') + "/bin/omarchy-shell"', BAR_WIDGET)
        self.assertIn('"regionallyfamous.one-bit-bureau.desktop", "toggleDeskMenu"', BAR_WIDGET)
        self.assertIn("deskMenuProcess.command = [root.omarchyShellCommand", BAR_WIDGET)
        self.assertNotIn("bash", re.search(
            r"function requestDeskMenu\(\).*?\n  \}", BAR_WIDGET, re.DOTALL
        ).group(0))

    def test_desk_menu_rows_are_selection_aware_and_positionally_stable(self) -> None:
        desk_menu = re.search(
            r"function deskMenuEntries\(\) \{(?P<body>.*?)\n  \}",
            SERVICE,
            re.DOTALL,
        )
        self.assertIsNotNone(desk_menu)
        body = desk_menu.group("body")
        labels = [
            "New Folder",
            "Quick Look",
            "Get Info",
            "Rename",
            "Tidy Desk",
            "Arrange By",
            "  Name",
            "  Kind",
            "  Modified",
            "Undo Desk Layout",
            "Move to Trash",
        ]
        positions = [body.index(f'label: "{label}"') for label in labels]
        self.assertEqual(positions, sorted(positions))
        self.assertGreaterEqual(body.count("reason:"), len(labels))
        self.assertIn('String(modelData.reason || "Unavailable command")', SERVICE)

    def test_space_quick_look_uses_bounded_separated_helper_arguments(self) -> None:
        quick_look = re.search(
            r"function quickLookSelection\(screenName\) \{(?P<body>.*?)\n  \}",
            SERVICE,
            re.DOTALL,
        )
        self.assertIsNotNone(quick_look)
        body = quick_look.group("body")
        self.assertIn('quickLookProc.command = [', body)
        self.assertIn('["/usr/bin/python3", root.quickLookScript, path]', body)
        self.assertIn('quickLookScript: pluginDir + "/bin/desktop-quick-look"', SERVICE)
        self.assertIn('data.command !== "quick-look"', SERVICE)
        self.assertIn('data.state !== "requested"', SERVICE)
        self.assertNotIn("shellQuote", body)
        self.assertNotIn('"bash"', body)
        self.assertIn("event.key === Qt.Key_Space && event.modifiers === Qt.NoModifier", SERVICE)
        self.assertIn("host.quickLookSelection(panel.screenName)", SERVICE)

    def test_tidy_and_arrange_only_persist_deterministic_position_state(self) -> None:
        self.assertIn('var allowed = ["tidy", "name", "kind", "modified"]', SERVICE)
        self.assertIn("var pos = panel.layoutPos(i)", SERVICE)
        self.assertIn("host.applyDeskLayout(panel.screenName, updates, labels[mode])", SERVICE)
        self.assertIn("rightModified - leftModified", SERVICE)
        self.assertIn("return byName !== 0 ? byName : compareText(a.id, b.id)", SERVICE)
        self.assertIn("property var layoutUndoSnapshot: null", SERVICE)
        self.assertIn("function undoDeskLayout()", SERVICE)
        self.assertIn("next[root.layoutUndoScreen]", SERVICE)
        self.assertIn("root.savePositions()", SERVICE)
        arrange_desk = re.search(
            r"function arrangeDesk\(mode\) \{(?P<body>.*?)\n\s*\}",
            SERVICE,
            re.DOTALL,
        )
        self.assertIsNotNone(arrange_desk)
        self.assertNotIn("runOperation", arrange_desk.group("body"))

    def test_marquee_has_ctrl_shift_semantics_and_ctrl_a_parity(self) -> None:
        self.assertIn("property bool marqueeActive: false", SERVICE)
        self.assertIn("function marqueeIds(x1, y1, x2, y2)", SERVICE)
        self.assertIn("function getVisualBounds(screenName: string): string", SERVICE)
        self.assertIn("JSON.stringify(root.visualBoundsForScreen(screenName))", SERVICE)
        self.assertIn("function updateMarqueeSelection()", SERVICE)
        self.assertIn("panel.marqueeBaseSelection = host.selectedIds.slice", SERVICE)
        self.assertIn("panel.marqueeModifiers & Qt.ControlModifier", SERVICE)
        self.assertIn("panel.marqueeModifiers & Qt.ShiftModifier", SERVICE)
        self.assertIn("id: marqueeBox", SERVICE)

    def test_item_workflows_reset_the_empty_click_wallpaper_shortcut(self) -> None:
        self.assertIn("function resetEmptyClickSequence()", SERVICE)
        self.assertIn("panel.emptyClicks = 0", SERVICE)
        self.assertIn("emptyClickTimer.stop()", SERVICE)
        self.assertIn(
            "onPressed: function(mouse) {\n              panel.resetEmptyClickSequence()",
            SERVICE,
        )
        self.assertIn("host.selectAll(panel.screenName)", SERVICE)
        self.assertIn("Press Escape to cancel", SERVICE)

    def test_inline_rename_has_explicit_commit_cancel_and_no_shell_interpolation(self) -> None:
        rename_request = re.search(
            r"function requestRename\(itemId, newName, screenName\) \{(?P<body>.*?)\n  \}",
            SERVICE,
            re.DOTALL,
        )
        self.assertIsNotNone(rename_request)
        body = rename_request.group("body")
        self.assertIn('root.beginReservation("rename", 1, "rename")', body)
        self.assertIn('"rename", "--operation-id", id, "--name", root.renamePendingName, renameSource', SERVICE)
        self.assertNotIn('"bash"', body)
        self.assertNotIn("shellQuote", body)
        self.assertIn("function validRenameName(value)", SERVICE)
        self.assertIn("id: renameField", SERVICE)
        self.assertIn("maximumLength: host.maxNameLength", SERVICE)
        self.assertIn('Accessible.name: "Cancel rename"', SERVICE)
        self.assertIn('? "Renaming" : "Commit rename"', SERVICE)
        self.assertIn("panel.cancelRename()", SERVICE)
        self.assertIn("panel.commitRename()", SERVICE)
        self.assertIn("event.key === Qt.Key_F2", SERVICE)
        self.assertIn("pendingSelectionPath", SERVICE)

    def test_operations_reserve_poll_progress_and_cancel_without_terminating_worker(self) -> None:
        self.assertIn("function beginReservation(command, sourceCount, kind)", SERVICE)
        self.assertIn("data.reservationAccepted === true", SERVICE)
        self.assertIn("function startReservedWorker()", SERVICE)
        self.assertIn("id: statusPollTimer", SERVICE)
        self.assertIn("interval: 250", SERVICE)
        self.assertIn('"status", root.operationId', SERVICE)
        self.assertIn("function updateOperationProgress(data)", SERVICE)
        self.assertIn("function cancelCurrentOperation()", SERVICE)
        self.assertIn('"cancel", root.operationId', SERVICE)
        self.assertIn("data.cancelAccepted !== true", SERVICE)
        self.assertIn('Accessible.name: host.operationState === "cancelling"', SERVICE)
        self.assertIn("function getOperationProgress(): string", SERVICE)
        self.assertIn("function cancelOperation(): bool", SERVICE)
        cancel_function = re.search(
            r"function cancelCurrentOperation\(\) \{(?P<body>.*?)\n  \}",
            SERVICE,
            re.DOTALL,
        )
        self.assertIsNotNone(cancel_function)
        self.assertNotIn("operationProc.running = false", cancel_function.group("body"))
        self.assertIn('state === "cancelled"', SERVICE)
        self.assertIn('state === "partial"', SERVICE)

    def test_disabled_xdg_desktop_is_explained_without_guessing_a_path(self) -> None:
        self.assertIn('property string desktopPath: ""', SERVICE)
        self.assertIn("root.desktopEnabled = data.desktopEnabled === true", SERVICE)
        self.assertIn("root.desktopState = root.plainText(data.desktopState", SERVICE)
        self.assertIn("root.desktopReason = root.plainText(data.desktopReason", SERVICE)
        self.assertIn("id: desktopDisabledBox", SERVICE)
        self.assertIn('text: "Desktop files are off"', SERVICE)
        self.assertIn(
            'text: "Choose a Desktop folder in your XDG user-directory settings to show files here."',
            SERVICE,
        )
        self.assertIn('path: root.desktopEnabled ? root.desktopPath : ""', SERVICE)

    def test_virtual_trash_and_volumes_are_capability_gated_and_re_resolved(self) -> None:
        for field in (
            "virtualId:",
            "trashState:",
            "canOpen:",
            "canUnmount:",
            "canEject:",
            "mountPath:",
        ):
            with self.subTest(field=field):
                self.assertIn(field, SERVICE)
        self.assertIn('kind === "volume"', SERVICE)
        self.assertIn('{ action: "unmount", label: "Unmount"', SERVICE)
        self.assertIn('{ action: "eject", label: "Eject"', SERVICE)
        self.assertIn("function performVirtualAction(action, itemId, screenName)", SERVICE)
        self.assertIn('"--virtual-action", verb, "--virtual-id", String(item.virtualId)', SERVICE)
        self.assertIn('data.command === "virtual-action"', SERVICE)
        self.assertIn("host.isFolderTarget(target)", SERVICE)
        self.assertIn("function selectedOpenItems(fallbackItem)", SERVICE)
        self.assertIn("var openItems = host.selectedOpenItems(null)", SERVICE)
        self.assertIn("function getDeskMenuLabels(): string", SERVICE)
        self.assertIn("function getSelectedId(): string", SERVICE)
        self.assertIn("function getVisualIndex(itemId: string, screenName: string): int", SERVICE)
        self.assertIn("var order = root.visualOrder(screenName)", SERVICE)
        self.assertIn("return host.deskMenuEntries()", SERVICE)

    def test_external_desktop_drops_are_copy_only(self) -> None:
        drop_mode = re.search(
            r"function dropMode\(drop\) \{(?P<body>.*?)\n  \}",
            SERVICE,
            re.DOTALL,
        )
        self.assertIsNotNone(drop_mode)
        self.assertIn('return "copy"', drop_mode.group("body"))
        self.assertNotIn('return "move"', drop_mode.group("body"))
        self.assertIn('return host.runOperation(route.external ? "copy" : "move"', SERVICE)

    def test_spring_open_waits_for_resolved_eligible_folder(self) -> None:
        self.assertIn("property bool routeEligibilityResolved: false", SERVICE)
        self.assertRegex(
            SERVICE,
            r"if \(panel\.routeEligibilityResolved && panel\.routeValid && panel\.routeTarget",
        )
        self.assertIn("id: springOpenTimer", SERVICE)
        self.assertIn("interval: 1800", SERVICE)
        self.assertIn("!panel.routeEligibilityResolved || !panel.routeValid", SERVICE)
        self.assertIn("panel.dragCanceled = true", SERVICE)

    def test_drop_target_tracks_the_dragged_object_without_smoothing_lag(self) -> None:
        self.assertIn("drag.smoothed: false", SERVICE)
        self.assertIn("iconRoot.x + iconRoot.width / 2", SERVICE)
        self.assertIn("iconRoot.y + iconRoot.height / 2", SERVICE)

    def test_desktop_exposes_shared_inspector_coordinator_contract(self) -> None:
        self.assertIn("property var inspectorSubject: null", SERVICE)
        self.assertIn("property bool inspectorOpen: false", SERVICE)
        self.assertIn("signal inspectRequested(var payload, string screenName)", SERVICE)
        self.assertIn("function inspectDesktopItem(id, screenName)", SERVICE)
        self.assertIn("function performInspectorAction(actionId, context)", SERVICE)
        self.assertIn("function closeInspector()", SERVICE)
        self.assertIn('id: "moveToTrash"', SERVICE)
        self.assertIn('id: "trustAndOpen"', SERVICE)

    def test_reduced_motion_disables_receipt_and_route_transitions(self) -> None:
        self.assertIn("readonly property bool reducedMotion:", SERVICE)
        self.assertGreaterEqual(SERVICE.count("enabled: !host.reducedMotion"), 2)


if __name__ == "__main__":
    unittest.main()
