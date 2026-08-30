from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PluginSourceContractTest(unittest.TestCase):
    def test_active_window_widget_disappears_without_a_window(self) -> None:
        source = (ROOT / "components/active-window/BarWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "readonly property bool hasActiveWindow: !!(waylandToplevel || hyprlandToplevel)",
            source,
        )
        self.assertIn("visible: hasActiveWindow && displayLabel", source)

    def test_runtime_does_not_take_over_global_alt_tab(self) -> None:
        source = (ROOT / "components/dock/DockPanelBase.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('hl.unbind(\\"ALT + TAB', source)
        self.assertNotIn('o.bind(\\"ALT + TAB', source)
        self.assertNotIn("altTabBindRetry", source)

    def test_dock_surfaces_share_one_persisted_output(self) -> None:
        source = (ROOT / "components/dock/DockPanelBase.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("screen: Quickshell.screens", source)
        self.assertGreaterEqual(source.count("screen: root.dockScreen"), 8)
        self.assertIn("screenName: root.preferredScreenName", source)
        self.assertIn("function setScreen(name: string): bool", source)

    def test_desktop_drop_routes_copied_and_moved_launchers_through_safe_helper(self) -> None:
        source = (ROOT / "components/desktop/bin/desktop-index").read_text(
            encoding="utf-8"
        )
        self.assertIn('mode in ("copy", "move") and source.suffix.lower() == ".desktop"', source)
        self.assertIn('if mode == "move":\n            source.unlink()', source)
        self.assertIn("if result.returncode != 0:", source)

    def test_keyboard_surfaces_leave_super_chords_to_omarchy(self) -> None:
        paths = [
            "components/desktop/Service.qml",
            "components/overview/Overview.qml",
            "components/dock/AltTabPanel.qml",
        ]
        for relative in paths:
            source = (ROOT / relative).read_text(encoding="utf-8")
            guard = "event.modifiers & Qt.MetaModifier"
            self.assertIn(guard, source, relative)
            guard_index = source.index(guard)
            self.assertNotEqual(
                source.find("event.key === Qt.Key_Left", guard_index), -1, relative
            )

    def test_runtime_does_not_claim_omarchy_navigation_bindings(self) -> None:
        runtime = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "components").rglob("*")
            if path.is_file() and path.suffix in {".qml", ".js", ".lua", ".sh"}
        )
        self.assertNotIn("hl.unbind", runtime)
        self.assertNotIn("o.bind", runtime)
        self.assertNotIn("bindings.lua", runtime)
        self.assertNotIn("input.lua", runtime)

    def test_public_lifecycle_uses_exact_plugin_and_theme_sources(self) -> None:
        setup = (ROOT / "setup").read_text(encoding="utf-8")
        update = (ROOT / "update").read_text(encoding="utf-8")
        uninstall = (ROOT / "uninstall").read_text(encoding="utf-8")
        command = (ROOT / "paper-jam").read_text(encoding="utf-8")

        self.assertIn('EXPECTED_REPO_URL="https://github.com/RegionallyFamous/paper-jam-84.git"', setup)
        self.assertIn('omarchy theme source inspect "$repo_url" --json', setup)
        self.assertIn('omarchy theme source install "$THEME_SOURCE_ID" "$THEME_NAME" --json', setup)
        self.assertIn('omarchy "${arguments[@]}"', update)
        self.assertIn('exec bash "$PLUGIN_DIR/update" --reconcile', update)
        self.assertIn('omarchy theme source update "$source_id" --json', update)
        self.assertIn('[[ $theme_commit == "$plugin_commit" ]]', update)
        self.assertIn('omarchy theme source detach "$THEME_SOURCE_ID" "$THEME_NAME" --json', uninstall)
        self.assertIn('PLUGIN_ID="io.github.regionallyfamous.paper-jam-84"', command)


if __name__ == "__main__":
    unittest.main()
