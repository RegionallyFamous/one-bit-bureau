from __future__ import annotations

import re
import unittest
from pathlib import Path


SERVICE = (Path(__file__).resolve().parents[1] / "Service.qml").read_text(
    encoding="utf-8"
)


class DesktopQmlContractTest(unittest.TestCase):
    def test_real_photos_keep_color_and_use_a_square_crop(self) -> None:
        self.assertNotIn("MultiEffect", SERVICE)
        self.assertNotIn("saturation: -1", SERVICE)
        self.assertRegex(
            SERVICE,
            r"fillMode:\s*iconRoot\.photoPreview\s*\?\s*Image\.PreserveAspectCrop",
        )

    def test_unpreviewable_images_use_the_raster_fallback(self) -> None:
        self.assertRegex(
            SERVICE,
            r'if \(kind === "image" && !String\(item\.preview \|\| ""\)\)\s*return "image"',
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
        self.assertIn("Qt.Key_Space", body)
        self.assertIn("host.trustAndOpen(host.pendingTrust)", body)


if __name__ == "__main__":
    unittest.main()
