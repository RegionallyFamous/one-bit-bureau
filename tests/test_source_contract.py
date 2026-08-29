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


if __name__ == "__main__":
    unittest.main()
