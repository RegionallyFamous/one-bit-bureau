from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


BIN_DIR = Path(__file__).resolve().parents[1] / "bin"
sys.path.insert(0, str(BIN_DIR))

from desktop_policy import (  # noqa: E402
    copy_untrusted_launcher,
    is_trusted_application_launcher,
    lexical_path,
    trusted_application_dirs,
)


class DesktopPolicyTest(unittest.TestCase):
    def test_empty_local_paths_are_rejected(self) -> None:
        for value in ("", "   ", "<>", "<   >", "file://", "file://localhost"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    lexical_path(value)

    def test_lexical_path_does_not_follow_a_desktop_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "outside.txt"
            target.write_text("keep me", encoding="utf-8")
            link = root / "Desktop Link"
            link.symlink_to(target)

            result = lexical_path(str(link))

            self.assertEqual(result, link)
            self.assertNotEqual(result, target.resolve())
            self.assertTrue(result.is_symlink())

    def test_file_uri_keeps_the_lexical_symlink_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "target.txt"
            target.write_text("keep me", encoding="utf-8")
            link = root / "Desktop Link"
            link.symlink_to(target)

            self.assertEqual(lexical_path(link.as_uri()), link)

    def test_only_canonical_application_roots_are_trusted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            data = root / "xdg-data"
            trusted = data / "applications" / "safe.desktop"
            misleading = home / "Downloads" / "applications" / "unsafe.desktop"
            trusted.parent.mkdir(parents=True)
            misleading.parent.mkdir(parents=True)
            trusted.write_text("[Desktop Entry]\n", encoding="utf-8")
            misleading.write_text("[Desktop Entry]\n", encoding="utf-8")
            env = {
                "XDG_DATA_HOME": str(data),
                "XDG_DATA_DIRS": "",
            }
            roots = trusted_application_dirs(home=home, environ=env)

            self.assertTrue(is_trusted_application_launcher(trusted, roots))
            self.assertFalse(is_trusted_application_launcher(misleading, roots))

    def test_symlink_out_of_a_trusted_root_is_not_trusted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            applications = root / "applications"
            outside = root / "Downloads" / "unsafe.desktop"
            applications.mkdir()
            outside.parent.mkdir()
            outside.write_text("[Desktop Entry]\n", encoding="utf-8")
            linked = applications / "linked.desktop"
            linked.symlink_to(outside)

            self.assertFalse(
                is_trusted_application_launcher(linked, [applications])
            )

    @staticmethod
    def _untrusted_metadata_runner(args, **_kwargs):
        if args[1] == "info":
            return subprocess.CompletedProcess(args, 0, "attributes:\n  metadata::trusted: false\n", "")
        return subprocess.CompletedProcess(args, 0, "", "")

    def test_executable_launcher_copy_is_provably_demoted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.desktop"
            destination = root / "destination.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")
            source.chmod(0o755)

            copy_untrusted_launcher(
                source,
                destination,
                runner=self._untrusted_metadata_runner,
            )

            self.assertTrue(destination.exists())
            self.assertEqual(destination.stat().st_mode & 0o111, 0)

    def test_launcher_copy_is_removed_when_chmod_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.desktop"
            destination = root / "destination.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")

            def fail_chmod(_path, _mode):
                raise PermissionError("injected chmod failure")

            with self.assertRaises(PermissionError):
                copy_untrusted_launcher(
                    source,
                    destination,
                    runner=self._untrusted_metadata_runner,
                    chmod_func=fail_chmod,
                )
            self.assertFalse(destination.exists())

    def test_launcher_copy_is_removed_when_gio_set_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.desktop"
            destination = root / "destination.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")

            def fail_set(args, **_kwargs):
                raise subprocess.CalledProcessError(1, args)

            with self.assertRaises(subprocess.CalledProcessError):
                copy_untrusted_launcher(source, destination, runner=fail_set)
            self.assertFalse(destination.exists())

    def test_partial_launcher_copy_is_removed_when_copy_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.desktop"
            destination = root / "destination.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")

            def partial_copy(_source, dest):
                dest.write_text("partial", encoding="utf-8")
                dest.chmod(0o755)
                raise OSError("injected copy failure")

            with self.assertRaises(OSError):
                copy_untrusted_launcher(
                    source,
                    destination,
                    runner=self._untrusted_metadata_runner,
                    copy_func=partial_copy,
                )
            self.assertFalse(destination.exists())

    def test_launcher_copy_is_removed_if_trusted_metadata_survives(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.desktop"
            destination = root / "destination.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")
            source.chmod(0o755)

            def still_trusted(args, **_kwargs):
                output = "attributes:\n  metadata::trusted: true\n" if args[1] == "info" else ""
                return subprocess.CompletedProcess(args, 0, output, "")

            with self.assertRaises(PermissionError):
                copy_untrusted_launcher(source, destination, runner=still_trusted)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
