from __future__ import annotations

import errno
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import types
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock


BIN_DIR = Path(__file__).resolve().parents[1] / "bin"
OPERATION_PATH = BIN_DIR / "desktop-operation"


def load_operation():
    loader = SourceFileLoader("one_bit_bureau_desktop_operation_test", str(OPERATION_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class DesktopOperationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.operation = load_operation()

    def workspace(self):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        home = root / "home"
        desktop = home / "Desktop"
        config = home / ".config"
        state = home / ".local/state"
        desktop.mkdir(parents=True)
        config.mkdir(parents=True)
        state.mkdir(parents=True)
        (config / "user-dirs.dirs").write_text(
            'XDG_DESKTOP_DIR="$HOME/Desktop"\n', encoding="utf-8"
        )
        environment = {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(config),
            "XDG_STATE_HOME": str(state),
        }
        return temporary, root, desktop, environment

    def test_inspect_returns_bounded_direct_desktop_metadata(self) -> None:
        temporary, _root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            item = desktop / "Notes.txt"
            item.write_text("hello", encoding="utf-8")

            receipt = self.operation.inspect_item(str(item))

            self.assertTrue(receipt["ok"])
            self.assertEqual(receipt["item"]["kind"], "file")
            self.assertEqual(receipt["item"]["size"], 5)
            self.assertEqual(receipt["item"]["sizeText"], "5 bytes")
            self.assertEqual(receipt["item"]["path"], str(item))
            self.assertFalse(receipt["item"]["previewEligible"])
            self.assertEqual(receipt["item"]["previewPolicy"], "One-bit type icon")

    def test_inspect_rejects_outside_items_and_symlinks(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            outside = root / "outside.txt"
            outside.write_text("outside", encoding="utf-8")
            link = desktop / "Outside Link"
            link.symlink_to(outside)

            with self.assertRaisesRegex(self.operation.RequestError, "direct Desktop"):
                self.operation.inspect_item(str(outside))
            with self.assertRaisesRegex(self.operation.ItemError, "Symbolic links"):
                self.operation.inspect_item(str(link))

    def test_remote_uri_relative_path_and_control_char_are_rejected(self) -> None:
        for value in (
            "https://example.com/file.txt",
            "file://server/share/file.txt",
            "relative.txt",
        ):
            with self.subTest(value=value), self.assertRaises(self.operation.RequestError):
                self.operation.local_path(value)
        with self.assertRaises(self.operation.RequestError):
            self.operation._validate_raw_argv(["inspect", "/tmp/bad\nname"])

    def test_copy_uses_unique_names_without_overwrite_and_journals_exact_paths(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            destination = desktop / "Projects"
            destination.mkdir()
            existing = destination / "report.txt"
            existing.write_text("original", encoding="utf-8")
            source = root / "report.txt"
            source.write_text("new", encoding="utf-8")

            receipt, exit_code = self.operation.transfer(
                "copy", [str(source)], str(destination)
            )

            copied = destination / "report 2.txt"
            self.assertEqual(exit_code, 0)
            self.assertEqual(existing.read_text(encoding="utf-8"), "original")
            self.assertEqual(copied.read_text(encoding="utf-8"), "new")
            self.assertEqual(receipt["results"][0]["destination"], str(copied.resolve()))
            self.assertFalse(receipt["undoable"])
            status = self.operation.status(receipt["operationId"])
            self.assertEqual(status["command"], "status")
            self.assertEqual(status["operationCommand"], "copy")
            self.assertEqual(status["results"], receipt["results"])

    def test_collision_suffix_never_exceeds_name_limit(self) -> None:
        name = ("é" * 120) + ".txt"
        numbered = self.operation._numbered_name(name, 9999)
        self.assertLessEqual(len(os.fsencode(numbered)), self.operation.MAX_NAME_BYTES)
        self.assertTrue(numbered.endswith(" 9999.txt"))

    def test_regular_file_move_is_undoable_only_while_unchanged(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            destination = desktop / "Projects"
            destination.mkdir()
            source = desktop / "draft.txt"
            source.write_text("draft", encoding="utf-8")

            receipt, exit_code = self.operation.transfer(
                "move", [str(source)], str(destination)
            )

            moved = Path(receipt["results"][0]["destination"])

            self.assertEqual(exit_code, 0)
            self.assertTrue(receipt["undoable"])
            self.assertFalse(source.exists())
            self.assertTrue(moved.exists())

            undo_receipt, undo_exit = self.operation.undo(receipt["operationId"])

            self.assertEqual(undo_exit, 0)
            self.assertEqual(undo_receipt["state"], "undone")
            self.assertFalse(undo_receipt["undoable"])
            self.assertEqual(source.read_text(encoding="utf-8"), "draft")
            self.assertFalse(moved.exists())

    def test_undo_refuses_changed_destination_and_source_collision(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            destination = desktop / "Projects"
            destination.mkdir()
            changed_source = desktop / "changed.txt"
            changed_source.write_text("before", encoding="utf-8")
            changed_receipt, _ = self.operation.transfer(
                "move", [str(changed_source)], str(destination)
            )
            changed_destination = Path(changed_receipt["results"][0]["destination"])
            changed_destination.write_text("after", encoding="utf-8")

            with self.assertRaisesRegex(self.operation.RequestError, "changed"):
                self.operation.undo(changed_receipt["operationId"])
            self.assertEqual(changed_destination.read_text(encoding="utf-8"), "after")

            collision_source = desktop / "collision.txt"
            collision_source.write_text("move me", encoding="utf-8")
            collision_receipt, _ = self.operation.transfer(
                "move", [str(collision_source)], str(destination)
            )
            collision_source.write_text("replacement", encoding="utf-8")

            with self.assertRaisesRegex(self.operation.RequestError, "occupied"):
                self.operation.undo(collision_receipt["operationId"])
            self.assertEqual(collision_source.read_text(encoding="utf-8"), "replacement")

    def test_directory_move_works_but_never_claims_undo(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            destination = desktop / "Projects"
            destination.mkdir()
            source = root / "Folder"
            source.mkdir()
            (source / "note.txt").write_text("note", encoding="utf-8")

            receipt, exit_code = self.operation.transfer(
                "move", [str(source)], str(destination)
            )

            self.assertEqual(exit_code, 0)
            self.assertFalse(receipt["undoable"])
            self.assertFalse(source.exists())
            self.assertEqual(
                (Path(receipt["results"][0]["destination"]) / "note.txt").read_text(
                    encoding="utf-8"
                ),
                "note",
            )

    def test_launcher_transfer_to_desktop_is_demoted_before_source_removal(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            source = root / "unsafe.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")
            source.chmod(0o755)

            def demote(path):
                path.chmod(path.stat().st_mode & ~0o111)

            with mock.patch.object(
                self.operation, "enforce_untrusted_launcher", side_effect=demote
            ) as helper:
                receipt, exit_code = self.operation.transfer(
                    "move", [str(source)], str(desktop)
                )

            target = Path(receipt["results"][0]["destination"])
            self.assertEqual(exit_code, 0)
            self.assertFalse(source.exists())
            self.assertEqual(target.stat().st_mode & 0o111, 0)
            self.assertFalse(receipt["undoable"])
            helper.assert_called_once_with(target)

    def test_failed_launcher_demotion_keeps_source_and_removes_copy(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            source = root / "unsafe.desktop"
            source.write_text("[Desktop Entry]\nExec=foot\n", encoding="utf-8")

            with mock.patch.object(
                self.operation,
                "enforce_untrusted_launcher",
                side_effect=PermissionError("injected trust failure"),
            ):
                receipt, exit_code = self.operation.transfer(
                    "move", [str(source)], str(desktop)
                )

            self.assertEqual(exit_code, 1)
            self.assertTrue(source.exists())
            self.assertEqual(receipt["state"], "failed")
            self.assertFalse((desktop / source.name).exists())

    def test_cross_filesystem_fallback_moves_without_shell_or_overwrite(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            destination = desktop / "Projects"
            destination.mkdir()
            source = root / "cross-device.txt"
            source.write_text("payload", encoding="utf-8")
            cross_device = OSError(errno.EXDEV, "injected cross-device move")

            with mock.patch.object(
                self.operation, "_rename_noreplace", side_effect=cross_device
            ):
                receipt, exit_code = self.operation.transfer(
                    "move", [str(source)], str(destination)
                )

            target = Path(receipt["results"][0]["destination"])
            self.assertEqual(exit_code, 0)
            self.assertFalse(source.exists())
            self.assertEqual(target.read_text(encoding="utf-8"), "payload")

    def test_partial_batch_records_child_failure_and_success(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            destination = desktop / "Projects"
            destination.mkdir()
            valid = root / "valid.txt"
            valid.write_text("valid", encoding="utf-8")
            missing = root / "missing.txt"

            receipt, exit_code = self.operation.transfer(
                "copy", [str(missing), str(valid)], str(destination)
            )

            self.assertEqual(exit_code, 1)
            self.assertEqual(receipt["state"], "partial")
            self.assertFalse(receipt["ok"])
            self.assertEqual(receipt["error"]["code"], "not_found")
            self.assertEqual(
                [result["status"] for result in receipt["results"]],
                ["failed", "completed"],
            )
            self.assertEqual(receipt["results"][0]["error"]["code"], "not_found")

    def test_directory_recursion_same_folder_and_nested_selection_are_rejected(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            parent = desktop / "Parent"
            child = parent / "Child"
            child.mkdir(parents=True)
            (child / "file.txt").write_text("x", encoding="utf-8")

            recursive, recursive_exit = self.operation.transfer(
                "copy", [str(parent)], str(child)
            )
            self.assertEqual(recursive_exit, 1)
            self.assertEqual(
                recursive["results"][0]["error"]["code"], "destination_recursion"
            )

            same, same_exit = self.operation.transfer("copy", [str(child)], str(parent))
            self.assertEqual(same_exit, 1)
            self.assertEqual(same["results"][0]["error"]["code"], "same_folder")

            destination = desktop / "Destination"
            destination.mkdir()
            nested, nested_exit = self.operation.transfer(
                "copy", [str(child), str(parent)], str(destination)
            )
            self.assertEqual(nested_exit, 1)
            self.assertEqual(nested["state"], "partial")
            self.assertEqual(nested["results"][0]["error"]["code"], "nested_source")

    def test_symlink_descendant_and_fifo_are_rejected_without_copying(self) -> None:
        if not hasattr(os, "mkfifo"):
            self.skipTest("FIFO creation is unavailable")
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            destination = desktop / "Projects"
            destination.mkdir()
            tree = root / "Tree"
            tree.mkdir()
            outside = root / "outside.txt"
            outside.write_text("keep", encoding="utf-8")
            (tree / "link").symlink_to(outside)
            fifo = root / "pipe"
            os.mkfifo(fifo)

            receipt, exit_code = self.operation.transfer(
                "copy", [str(tree), str(fifo)], str(destination)
            )

            self.assertEqual(exit_code, 1)
            self.assertEqual(receipt["state"], "failed")
            self.assertEqual(
                [result["error"]["code"] for result in receipt["results"]],
                ["unsafe_symlink", "unsupported_type"],
            )
            self.assertEqual(list(destination.iterdir()), [])

    def test_trash_is_direct_desktop_only_never_undoable_and_handles_child_failure(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            direct = desktop / "direct.txt"
            direct.write_text("direct", encoding="utf-8")
            outside = root / "outside.txt"
            outside.write_text("outside", encoding="utf-8")
            failed_child = subprocess.CompletedProcess([], 17)

            with mock.patch.object(
                self.operation.subprocess, "run", return_value=failed_child
            ) as runner:
                receipt, exit_code = self.operation.trash([str(direct), str(outside)])

            self.assertEqual(exit_code, 1)
            self.assertEqual(receipt["state"], "failed")
            self.assertFalse(receipt["undoable"])
            self.assertEqual(receipt["results"][0]["error"]["code"], "child_failed")
            self.assertEqual(receipt["results"][1]["error"]["code"], "outside_desktop")
            runner.assert_called_once()
            child_argv = runner.call_args.args[0]
            self.assertEqual(child_argv, ["gio", "trash", str(direct)])
            self.assertFalse(runner.call_args.kwargs.get("shell", False))
            self.assertTrue(runner.call_args.kwargs["start_new_session"])
            self.assertIs(
                runner.call_args.kwargs["preexec_fn"],
                self.operation._kill_child_when_parent_dies,
            )
            self.assertEqual(
                runner.call_args.kwargs["timeout"],
                self.operation.CHILD_TIMEOUT_SECONDS,
            )

    def test_invalid_operation_id_and_stale_status_are_structured_cli_errors(self) -> None:
        temporary, _root, _desktop, environment = self.workspace()
        with temporary:
            bad_id = "../../escape"
            result = subprocess.run(
                [sys.executable, str(OPERATION_PATH), "status", bad_id],
                env={**os.environ, **environment},
                capture_output=True,
                text=True,
                check=False,
            )
            receipt = json.loads(result.stdout)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(receipt["error"]["code"], "invalid_operation_id")
            self.assertNotIn(bad_id, receipt["error"]["message"])

            missing = subprocess.run(
                [sys.executable, str(OPERATION_PATH), "status", "a" * 32],
                env={**os.environ, **environment},
                capture_output=True,
                text=True,
                check=False,
            )
            missing_receipt = json.loads(missing.stdout)
            self.assertEqual(missing.returncode, 2)
            self.assertEqual(missing_receipt["error"]["code"], "operation_not_found")

    def test_hard_argument_source_and_output_boundaries(self) -> None:
        at_limit = "x" * self.operation.MAX_RAW_ARG_BYTES
        self.operation._validate_raw_argv([at_limit])
        with self.assertRaises(self.operation.RequestError):
            self.operation._validate_raw_argv([at_limit + "x"])
        with self.assertRaises(self.operation.RequestError):
            self.operation._validate_raw_argv(
                ["x"] * (self.operation.MAX_RAW_ARGS + 1)
            )
        with self.assertRaises(self.operation.RequestError):
            self.operation.transfer(
                "copy",
                ["/tmp/x"] * (self.operation.MAX_SOURCES + 1),
                "/tmp",
            )
        with self.assertRaises(self.operation.RequestError):
            self.operation._json_bytes(
                {"payload": "x" * self.operation.MAX_OUTPUT_BYTES}
            )

    def test_journal_is_atomic_private_and_contains_no_temporary_files(self) -> None:
        temporary, root, desktop, environment = self.workspace()
        with temporary, mock.patch.dict(os.environ, environment):
            destination = desktop / "Projects"
            destination.mkdir()
            source = root / "note.txt"
            source.write_text("note", encoding="utf-8")
            receipt, _ = self.operation.transfer("copy", [str(source)], str(destination))

            journal_dir = (
                Path(environment["XDG_STATE_HOME"])
                / "one-bit-bureau/desktop-operations"
            )
            journal = journal_dir / f"{receipt['operationId']}.json"
            self.assertTrue(journal.is_file())
            self.assertEqual(stat.S_IMODE(journal.stat().st_mode), 0o600)
            self.assertEqual(list(journal_dir.glob("*.tmp")), [])
            on_disk = json.loads(journal.read_text(encoding="utf-8"))
            self.assertEqual(on_disk["results"], receipt["results"])


if __name__ == "__main__":
    unittest.main()
