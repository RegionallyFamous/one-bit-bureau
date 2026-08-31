from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock


BIN_DIR = Path(__file__).resolve().parents[1] / "bin"
QUICK_LOOK_PATH = BIN_DIR / "desktop-quick-look"


def load_quick_look():
    loader = SourceFileLoader("one_bit_bureau_desktop_quick_look_test", str(QUICK_LOOK_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class DesktopQuickLookTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.quick = load_quick_look()

    def workspace(self):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        home = root / "home"
        desktop = home / "Desktop"
        config = home / ".config"
        desktop.mkdir(parents=True)
        config.mkdir(parents=True)
        (config / "user-dirs.dirs").write_text(
            'XDG_DESKTOP_DIR="$HOME/Desktop"\n', encoding="utf-8"
        )
        environment = {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(config),
        }
        return temporary, root, desktop, environment

    def test_preview_uses_separated_sushi_argv_for_adversarial_name(self) -> None:
        temporary, _root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            item = desktop / "$(touch nope); photo.png"
            item.write_bytes(b"image")

            class Child:
                pid = 424242

                @staticmethod
                def wait(timeout=None):
                    return 0

            with mock.patch.object(
                self.quick.subprocess, "Popen", return_value=Child()
            ) as launcher, mock.patch.object(self.quick, "focus_previewer") as focus:
                path = self.quick.validate_path(str(item))
                self.quick.request_preview(path)

            self.assertEqual(
                launcher.call_args.args[0], ["/usr/bin/sushi", str(item)]
            )
            self.assertFalse(launcher.call_args.kwargs.get("shell", False))
            self.assertTrue(launcher.call_args.kwargs["start_new_session"])
            focus.assert_called_once_with()
            self.assertFalse((desktop / "nope").exists())

    def test_previewer_focus_retries_the_canonical_omarchy_helper(self) -> None:
        failed = subprocess.CompletedProcess([], 1)
        focused = subprocess.CompletedProcess([], 0)
        with mock.patch.object(
            self.quick.subprocess, "run", side_effect=[failed, focused]
        ) as runner, mock.patch.object(self.quick.time, "sleep"):
            self.quick.focus_previewer()

        self.assertEqual(runner.call_count, 2)
        for invocation in runner.call_args_list:
            self.assertEqual(
                invocation.args[0],
                ["omarchy-hyprland-focus-app", r"^org\.gnome\.NautilusPreviewer$"],
            )
            self.assertFalse(invocation.kwargs["check"])
            self.assertEqual(
                invocation.kwargs["timeout"], self.quick.FOCUS_ATTEMPT_TIMEOUT_SECONDS
            )

    def test_preview_rejects_remote_relative_symlink_and_special_files(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            outside = root / "outside.txt"
            outside.write_text("outside", encoding="utf-8")
            link = desktop / "link"
            link.symlink_to(outside)
            for raw in ("https://example.com/file", "relative.txt", str(link)):
                with self.subTest(raw=raw), self.assertRaises(self.quick.QuickLookError):
                    self.quick.validate_path(raw)
            if hasattr(os, "mkfifo"):
                fifo = desktop / "pipe"
                os.mkfifo(fifo)
                with self.assertRaisesRegex(self.quick.QuickLookError, "support"):
                    self.quick.validate_path(str(fifo))

    def test_disabled_desktop_refuses_preview_without_recreating_directory(self) -> None:
        temporary, _root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            item = desktop / "note.txt"
            item.write_text("note", encoding="utf-8")
            item.unlink()
            desktop.rmdir()
            (Path(environment["XDG_CONFIG_HOME"]) / "user-dirs.dirs").write_text(
                'XDG_DESKTOP_DIR="$HOME"\n', encoding="utf-8"
            )

            with self.assertRaisesRegex(self.quick.QuickLookError, "disabled"):
                self.quick.validate_path(str(desktop / "note.txt"))

            self.assertFalse(desktop.exists())

    def test_raw_argument_byte_ceiling_accepts_exact_and_rejects_one_over(self) -> None:
        at_limit = "/" + "a" * (self.quick.MAX_RAW_ARG_BYTES - 1)
        self.assertEqual(len(at_limit.encode("utf-8")), self.quick.MAX_RAW_ARG_BYTES)
        with self.assertRaises(self.quick.QuickLookError) as accepted:
            self.quick.validate_path(at_limit)
        self.assertNotEqual(accepted.exception.code, "invalid_argument")
        with self.assertRaises(self.quick.QuickLookError) as rejected:
            self.quick.validate_path(at_limit + "a")
        self.assertEqual(rejected.exception.code, "invalid_argument")

    def test_preview_timeout_invokes_bounded_cleanup_and_structured_cli_error(self) -> None:
        temporary, _root, desktop, environment = self.workspace()
        with temporary:
            item = desktop / "note.txt"
            item.write_text("note", encoding="utf-8")

            class StalledChild:
                pid = 424242

                @staticmethod
                def wait(timeout=None):
                    raise subprocess.TimeoutExpired(["sushi"], timeout)

            result = subprocess.run(
                [os.sys.executable, str(QUICK_LOOK_PATH), "https://example.com/file"],
                env={**os.environ, **environment},
                capture_output=True,
                text=True,
                check=False,
            )
            payload = json.loads(result.stdout)
            self.assertEqual(payload["command"], "quick-look")
            self.assertEqual(payload["state"], "failed")
            self.assertEqual(payload["error"]["code"], "remote_uri")

            with mock.patch.object(
                self.quick.subprocess, "Popen", return_value=StalledChild()
            ), mock.patch.object(self.quick, "stop_child") as cleanup:
                with self.assertRaises(self.quick.QuickLookError) as raised:
                    self.quick.request_preview(item)
            self.assertEqual(raised.exception.code, "preview_timeout")
            cleanup.assert_called_once()


if __name__ == "__main__":
    unittest.main()
