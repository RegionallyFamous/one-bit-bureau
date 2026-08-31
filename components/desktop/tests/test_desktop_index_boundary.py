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
        loader = SourceFileLoader("one_bit_bureau_desktop_index_test", str(INDEX_PATH))
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

    def test_safe_raster_image_exposes_a_local_thumbnail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image = Path(temporary) / "photo.png"
            image.write_bytes(b"not decoded by the indexer")

            with mock.patch.object(
                self.index, "guess_icon", return_value="image-x-generic"
            ), mock.patch.object(
                self.index, "allowed_icon_roots", return_value=[Path(temporary)]
            ):
                item = self.index.item_for(image)

            self.assertEqual(item["kind"], "image")
            self.assertEqual(item["preview"], str(image.resolve()))

    def test_direct_item_emits_bounded_modified_timestamp(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            item_path = Path(temporary) / "note.txt"
            item_path.write_text("note", encoding="utf-8")
            timestamp_ns = 1_700_000_000_123_000_000
            os.utime(item_path, ns=(timestamp_ns, timestamp_ns))

            with mock.patch.object(self.index, "guess_icon", return_value="text-x-generic"):
                item = self.index.item_for(item_path)

            self.assertEqual(item["modifiedUnixMs"], timestamp_ns // 1_000_000)

    def test_disabled_desktop_returns_explicit_state_without_creation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            config = home / ".config"
            config.mkdir(parents=True)
            (config / "user-dirs.dirs").write_text(
                'XDG_DESKTOP_DIR="$HOME"\n', encoding="utf-8"
            )
            environment = {
                "HOME": str(home),
                "XDG_CONFIG_HOME": str(config),
            }
            with mock.patch.dict(os.environ, environment), mock.patch.object(
                self.index, "mounted_volume_records", return_value=[]
            ):
                payload = self.index.list_items()

            self.assertFalse(payload["desktopEnabled"])
            self.assertEqual(payload["desktopState"], "disabled")
            self.assertEqual(payload["desktop"], "")
            self.assertEqual(payload["items"][0]["id"], "virtual:trash")
            self.assertFalse((home / "Desktop").exists())

    def test_trash_virtual_object_reports_empty_full_and_unknown(self) -> None:
        class Enumerator:
            def __init__(self, value):
                self.value = value

            def next_file(self, _cancellable):
                return self.value

            def close(self, _cancellable):
                pass

        class TrashFile:
            def __init__(self, value):
                self.value = value

            def enumerate_children(self, *_args):
                if isinstance(self.value, Exception):
                    raise self.value
                return Enumerator(self.value)

        class FileFactory:
            value = None

            @classmethod
            def new_for_uri(cls, _uri):
                return TrashFile(cls.value)

        fake_gio = types.SimpleNamespace(
            File=FileFactory,
            FileQueryInfoFlags=types.SimpleNamespace(NOFOLLOW_SYMLINKS=0),
        )
        with mock.patch.object(self.index, "Gio", fake_gio):
            FileFactory.value = None
            self.assertEqual(self.index.virtual_trash_item()["trashState"], "empty")
            FileFactory.value = object()
            full = self.index.virtual_trash_item()
            self.assertEqual(full["trashState"], "full")
            self.assertEqual(full["icon"], "user-trash-full")
            FileFactory.value = RuntimeError("injected")
            self.assertEqual(self.index.virtual_trash_item()["trashState"], "unknown")

    def test_volume_records_are_deterministic_bounded_and_local_only(self) -> None:
        class Icon:
            def to_string(self):
                return "drive-removable-media"

        class Root:
            def __init__(self, index):
                self.index = index

            def get_path(self):
                return f"/run/media/test/Volume {self.index}"

            def get_uri(self):
                return f"file:///run/media/test/Volume%20{self.index}"

        class Volume:
            def __init__(self, index):
                self.index = index

            def get_uuid(self):
                return f"uuid-{self.index}"

            def get_identifier(self, kind):
                self.kind = kind
                return f"/dev/test{self.index}"

            def can_eject(self):
                return self.index % 2 == 0

        class Mount:
            def __init__(self, index):
                self.index = index

            def is_shadowed(self):
                return False

            def get_root(self):
                return Root(self.index)

            def get_volume(self):
                return Volume(self.index)

            def get_uuid(self):
                return ""

            def get_name(self):
                return f"Volume {self.index}"

            def get_icon(self):
                return Icon()

            def can_unmount(self):
                return True

            def can_eject(self):
                return False

        mounts = [Mount(index) for index in range(self.index.MAX_VOLUMES + 1)]
        monitor = types.SimpleNamespace(get_mounts=lambda: mounts)
        fake_gio = types.SimpleNamespace(
            VolumeMonitor=types.SimpleNamespace(get=lambda: monitor)
        )
        with mock.patch.object(self.index, "Gio", fake_gio):
            first = self.index.mounted_volume_records()
            second = self.index.mounted_volume_records()

        self.assertEqual(len(first), self.index.MAX_VOLUMES)
        self.assertEqual(
            [record["virtualId"] for record in first],
            [record["virtualId"] for record in second],
        )
        self.assertTrue(all(record["virtualId"].startswith("volume:") for record in first))
        self.assertTrue(all(len(os.fsencode(record["path"])) <= self.index.MAX_PATH_BYTES for record in first))

    def test_virtual_actions_revalidate_capability_and_postcondition(self) -> None:
        virtual_id = "volume:" + "a" * 32
        record = {
            "virtualId": virtual_id,
            "name": "Disk",
            "_uri": "file:///run/media/test/Disk",
            "canUnmount": False,
            "canEject": True,
        }
        commands = []
        with mock.patch.object(
            self.index, "mounted_volume_records", return_value=[record]
        ), mock.patch.object(
            self.index, "_run_device_command", side_effect=commands.append
        ):
            refusal, refusal_exit = self.index.perform_virtual_action(
                "unmount", "virtual:" + virtual_id
            )
        self.assertEqual(refusal_exit, 1)
        self.assertEqual(refusal["error"]["code"], "unsupported_action")
        self.assertEqual(commands, [])

        with mock.patch.object(
            self.index,
            "mounted_volume_records",
            side_effect=[[record], []],
        ), mock.patch.object(
            self.index, "_run_device_command", side_effect=commands.append
        ):
            success, success_exit = self.index.perform_virtual_action(
                "eject", virtual_id
            )
        self.assertEqual(success_exit, 0)
        self.assertEqual(success["state"], "completed")
        self.assertEqual(
            commands[-1],
            [
                "/usr/bin/gio",
                "mount",
                "--eject",
                "file:///run/media/test/Disk",
            ],
        )

    def test_virtual_open_uses_omarchys_files_application(self) -> None:
        virtual_id = "volume:" + "b" * 32
        record = {
            "virtualId": virtual_id,
            "name": "Disk",
            "_uri": "file:///run/media/test/Disk",
            "canUnmount": False,
            "canEject": False,
        }
        commands = []
        with mock.patch.object(
            self.index, "mounted_volume_records", return_value=[record]
        ), mock.patch.object(
            self.index, "_run_device_command", side_effect=commands.append
        ):
            trash, trash_exit = self.index.perform_virtual_action("open", "trash")
            volume, volume_exit = self.index.perform_virtual_action("open", virtual_id)

        self.assertEqual(trash_exit, 0)
        self.assertEqual(trash["state"], "requested")
        self.assertEqual(
            commands[0],
            [
                "/usr/bin/uwsm",
                "app",
                "-t",
                "service",
                "--",
                "/usr/bin/nautilus",
                "--new-window",
                "trash:///",
            ],
        )
        self.assertEqual(volume_exit, 0)
        self.assertEqual(volume["state"], "requested")
        self.assertEqual(
            commands[1],
            [
                "/usr/bin/uwsm",
                "app",
                "-t",
                "service",
                "--",
                "/usr/bin/nautilus",
                "--new-window",
                "file:///run/media/test/Disk",
            ],
        )

    def test_animated_or_vector_image_falls_back_to_the_bitmap_icon(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image = Path(temporary) / "drawing.svg"
            image.write_text("<svg/>", encoding="utf-8")

            with mock.patch.object(
                self.index, "guess_icon", return_value="image-x-generic"
            ), mock.patch.object(
                self.index, "allowed_icon_roots", return_value=[Path(temporary)]
            ):
                item = self.index.item_for(image)

            self.assertEqual(item["kind"], "image")
            self.assertEqual(item["preview"], "")

    def test_thumbnail_file_size_ceiling_accepts_exactly_the_limit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            at_limit = root / "at-limit.png"
            over_limit = root / "over-limit.png"
            with at_limit.open("wb") as handle:
                handle.truncate(self.index.MAX_PREVIEW_FILE_BYTES)
            with over_limit.open("wb") as handle:
                handle.truncate(self.index.MAX_PREVIEW_FILE_BYTES + 1)

            with mock.patch.object(
                self.index, "allowed_icon_roots", return_value=[root]
            ):
                self.assertTrue(
                    self.index.is_allowed_local_image(
                        at_limit,
                        self.index.MAX_PREVIEW_FILE_BYTES,
                        self.index.SAFE_PREVIEW_SUFFIXES,
                    )
                )
                self.assertFalse(
                    self.index.is_allowed_local_image(
                        over_limit,
                        self.index.MAX_PREVIEW_FILE_BYTES,
                        self.index.SAFE_PREVIEW_SUFFIXES,
                    )
                )

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
