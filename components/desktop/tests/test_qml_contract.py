from __future__ import annotations

import re
import unittest
from pathlib import Path


SERVICE = (Path(__file__).resolve().parents[1] / "Service.qml").read_text(
    encoding="utf-8"
)


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

    def test_external_drops_accept_only_bounded_local_paths(self) -> None:
        self.assertIn("function localPath(value)", SERVICE)
        self.assertIn('if (path.indexOf("file://") === 0)', SERVICE)
        self.assertIn('if (path.indexOf("://") !== -1)', SERVICE)
        self.assertIn("panel.pathItems(urls)", SERVICE)
        self.assertIn("urls.length < panel.host.maxOperationItems", SERVICE)
        self.assertIn("panel.host.dropMode(drop)", SERVICE)

    def test_structured_helper_receipts_and_truthful_undo(self) -> None:
        self.assertIn('readonly property string operationScript: pluginDir + "/bin/desktop-operation"', SERVICE)
        self.assertIn('["/usr/bin/python3", root.operationScript, verb]', SERVICE)
        self.assertIn('cmd.push("--destination")', SERVICE)
        self.assertIn("data.schemaVersion !== 1", SERVICE)
        self.assertIn("data.undoable === true && root.operationId !== \"\"", SERVICE)
        self.assertIn('["/usr/bin/python3", root.operationScript, "undo", root.operationId]', SERVICE)
        self.assertIn("Accessible.name: \"Undo desktop action\"", SERVICE)
        self.assertIn("event.key === Qt.Key_Z", SERVICE)

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
