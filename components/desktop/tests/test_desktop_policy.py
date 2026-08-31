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
    MAX_USER_DIRS_BYTES,
    copy_untrusted_launcher,
    is_trusted_application_launcher,
    lexical_path,
    require_desktop_directory,
    resolve_desktop_location,
    trusted_application_dirs,
)


class DesktopPolicyTest(unittest.TestCase):
    def test_xdg_home_value_disables_desktop_without_recreating_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            config = home / ".config"
            config.mkdir(parents=True)
            (config / "user-dirs.dirs").write_text(
                'XDG_DESKTOP_DIR="$HOME"\n', encoding="utf-8"
            )

            location = resolve_desktop_location(
                home=home,
                environ={"XDG_CONFIG_HOME": str(config)},
            )

            self.assertFalse(location.enabled)
            self.assertEqual(location.state, "disabled")
            self.assertIsNone(location.path)
            self.assertFalse((home / "Desktop").exists())
            with self.assertRaisesRegex(RuntimeError, "disabled"):
                require_desktop_directory(
                    home=home,
                    environ={"XDG_CONFIG_HOME": str(config)},
                )

    def test_xdg_custom_desktop_is_resolved_but_not_created(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            config = home / ".config"
            config.mkdir(parents=True)
            (config / "user-dirs.dirs").write_text(
                'XDG_DESKTOP_DIR="$HOME/Desk Space"\n', encoding="utf-8"
            )

            location = resolve_desktop_location(
                home=home,
                environ={"XDG_CONFIG_HOME": str(config)},
            )

            self.assertTrue(location.enabled)
            self.assertEqual(location.path, (home / "Desk Space").resolve())
            self.assertFalse((home / "Desk Space").exists())

    def test_user_dirs_byte_ceiling_accepts_exact_limit_and_rejects_one_over(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            config = home / ".config"
            config.mkdir(parents=True)
            user_dirs = config / "user-dirs.dirs"
            assignment = b'XDG_DESKTOP_DIR="$HOME/Exact"\n'
            user_dirs.write_bytes(
                assignment + b"#" * (MAX_USER_DIRS_BYTES - len(assignment))
            )
            environment = {"XDG_CONFIG_HOME": str(config)}

            at_limit = resolve_desktop_location(home=home, environ=environment)
            self.assertEqual(at_limit.path, (home / "Exact").resolve())

            user_dirs.write_bytes(
                assignment + b"#" * (MAX_USER_DIRS_BYTES + 1 - len(assignment))
            )
            over_limit = resolve_desktop_location(home=home, environ=environment)
            self.assertEqual(over_limit.path, (home / "Desktop").resolve())

    def test_symlinked_user_dirs_configuration_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            config = home / ".config"
            config.mkdir(parents=True)
            outside = root / "outside-user-dirs"
            outside.write_text('XDG_DESKTOP_DIR="$HOME/Outside"\n', encoding="utf-8")
            (config / "user-dirs.dirs").symlink_to(outside)

            location = resolve_desktop_location(
                home=home,
                environ={"XDG_CONFIG_HOME": str(config)},
            )

            self.assertEqual(location.path, (home / "Desktop").resolve())

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
