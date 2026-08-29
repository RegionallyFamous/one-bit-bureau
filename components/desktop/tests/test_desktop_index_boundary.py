from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import os
import sys
import tempfile
import types
import unittest
from unittest import mock
from pathlib import Path


BIN_DIR = Path(__file__).resolve().parents[1] / "bin"
INDEX_PATH = BIN_DIR / "desktop-index"


def load_desktop_index():
    fake_gi = types.ModuleType("gi")
    fake_gi.require_version = lambda *_args: None
    fake_repository = types.ModuleType("gi.repository")
    fake_repository.Gio = types.SimpleNamespace()
    fake_repository.GLib = types.SimpleNamespace(Error=Exception)
    fake_gi.repository = fake_repository

    saved = {name: sys.modules.get(name) for name in ("gi", "gi.repository")}
    sys.modules["gi"] = fake_gi
    sys.modules["gi.repository"] = fake_repository
    sys.path.insert(0, str(BIN_DIR))
    try:
        loader = SourceFileLoader("paper_jam_desktop_index_test", str(INDEX_PATH))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.remove(str(BIN_DIR))
        for name, previous in saved.items():
            if previous is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = previous


class DesktopIndexBoundaryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.index = load_desktop_index()

    def test_trash_submits_the_lexical_symlink_not_its_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            desktop = root / "Desktop"
            desktop.mkdir()
            target = root / "target.txt"
            target.write_text("keep me", encoding="utf-8")
            link = desktop / "Desktop Link"
            link.symlink_to(target)
            submitted: list[str] = []

            class FakeFile:
                def __init__(self, path: str):
                    self.path = path

                def trash(self, _cancellable) -> None:
                    submitted.append(self.path)

            class FakeFileFactory:
                @staticmethod
                def new_for_path(path: str) -> FakeFile:
                    return FakeFile(path)

            self.index.desktop_dir = lambda: desktop
            self.index.Gio = types.SimpleNamespace(File=FakeFileFactory)
            self.index.GLib = types.SimpleNamespace(Error=Exception)

            self.index.trash_one(link)

            self.assertEqual(submitted, [str(link)])
            self.assertTrue(link.is_symlink())
            self.assertEqual(target.read_text(encoding="utf-8"), "keep me")

    def test_trash_refuses_items_outside_the_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            desktop = root / "Desktop"
            desktop.mkdir()
            outside = root / "outside.txt"
            outside.write_text("keep me", encoding="utf-8")
            self.index.desktop_dir = lambda: desktop

            with self.assertRaises(PermissionError):
                self.index.trash_one(outside)
            self.assertTrue(outside.exists())

    def test_move_preserves_a_symlink_and_leaves_its_target_in_place(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            desktop = root / "Desktop"
            incoming = root / "Incoming"
            desktop.mkdir()
            incoming.mkdir()
            target = root / "target.txt"
            target.write_text("keep me", encoding="utf-8")
            link = incoming / "Linked file"
            link.symlink_to(target)

            with mock.patch.dict(os.environ, {"HOME": str(root)}):
                destination = self.index.place_one(link, desktop, "move")

            self.assertTrue(destination.is_symlink())
            self.assertFalse(link.exists())
            self.assertEqual(target.read_text(encoding="utf-8"), "keep me")

    def test_move_launcher_uses_safe_helper_before_removing_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            desktop = root / "Desktop"
            incoming = root / "Downloads"
            desktop.mkdir()
            incoming.mkdir()
            source = incoming / "unsafe.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")
            source.chmod(0o755)
            destination = desktop / "unsafe.desktop"

            def safe_helper(args, **_kwargs):
                self.assertEqual(args[-1], str(source))
                destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
                destination.chmod(0o644)
                return types.SimpleNamespace(returncode=0, stdout=f"{destination}\n")

            with mock.patch.dict(os.environ, {"HOME": str(root)}), mock.patch.object(
                self.index.shutil, "which", return_value="/mock/add-to-desktop"
            ), mock.patch.object(self.index.subprocess, "run", side_effect=safe_helper):
                result = self.index.place_one(source, desktop, "move")

            self.assertEqual(result, destination)
            self.assertFalse(source.exists())
            self.assertTrue(destination.exists())
            self.assertEqual(destination.stat().st_mode & 0o111, 0)

    def test_failed_safe_launcher_move_preserves_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            desktop = root / "Desktop"
            incoming = root / "Downloads"
            desktop.mkdir()
            incoming.mkdir()
            source = incoming / "unsafe.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")

            failed = types.SimpleNamespace(returncode=1, stdout="")
            with mock.patch.dict(os.environ, {"HOME": str(root)}), mock.patch.object(
                self.index.shutil, "which", return_value="/mock/add-to-desktop"
            ), mock.patch.object(self.index.subprocess, "run", return_value=failed):
                with self.assertRaises(RuntimeError):
                    self.index.place_one(source, desktop, "move")

            self.assertTrue(source.exists())


if __name__ == "__main__":
    unittest.main()
