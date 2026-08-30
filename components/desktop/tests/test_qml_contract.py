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


if __name__ == "__main__":
    unittest.main()
