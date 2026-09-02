from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import one_bit_bureau_secure_io as secure  # noqa: E402


class SecureIOTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary.name) / "home"
        self.home.mkdir(mode=0o700)
        self.previous_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.home)

    def tearDown(self) -> None:
        if self.previous_home is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = self.previous_home
        self.temporary.cleanup()

    def write_install_state(self, value: object | None = None) -> Path:
        payload = json.dumps(value or {"schemaVersion": 3}).encode("utf-8")
        secure.install_state_write(payload)
        return secure.install_state_path() / secure.INSTALL_STATE_NAME

    def test_install_state_uses_random_exclusive_atomic_file_and_durable_mode(self) -> None:
        state_dir = secure.install_state_path()
        state_dir.mkdir(parents=True, mode=0o700)
        victim = self.home / "victim"
        victim.write_text("keep", encoding="utf-8")
        (state_dir / "install-state.json.tmp").symlink_to(victim)

        state = self.write_install_state({"schemaVersion": 3, "product": "One-Bit Bureau"})

        self.assertEqual(victim.read_text(encoding="utf-8"), "keep")
        self.assertTrue((state_dir / "install-state.json.tmp").is_symlink())
        self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o600)
        self.assertEqual(json.loads(secure.install_state_read()), {
            "product": "One-Bit Bureau",
            "schemaVersion": 3,
        })

    def test_install_state_rejects_symlink_fifo_hardlink_and_oversize(self) -> None:
        state_dir = secure.install_state_path()
        state_dir.mkdir(parents=True, mode=0o700)
        state = state_dir / secure.INSTALL_STATE_NAME
        victim = self.home / "victim"
        victim.write_text("keep", encoding="utf-8")

        state.symlink_to(victim)
        with self.assertRaises(secure.SecureIOError):
            secure.install_state_write(b'{"schemaVersion":3}')
        self.assertEqual(victim.read_text(encoding="utf-8"), "keep")

        state.unlink()
        os.mkfifo(state, 0o600)
        with self.assertRaises(secure.SecureIOError):
            secure.install_state_read()

    def test_install_state_accepts_exact_raw_and_multibyte_boundaries(self) -> None:
        state_dir = secure.install_state_path()
        state_dir.mkdir(parents=True, mode=0o700)
        state = state_dir / secure.INSTALL_STATE_NAME
        prefix = b'{"schemaVersion":3}'
        state.write_bytes(prefix + b" " * (secure.INSTALL_STATE_LIMIT - len(prefix)))
        self.assertEqual(json.loads(secure.install_state_read()), {"schemaVersion": 3})

        exact_string = {"value": "é" * (secure.MAX_JSON_STRING_BYTES // 2)}
        secure.install_state_write(
            json.dumps(exact_string, ensure_ascii=False).encode("utf-8")
        )
        self.assertEqual(json.loads(secure.install_state_read()), exact_string)

        state.unlink()
        state.write_bytes(b"{}")
        os.link(state, state_dir / "second-link")
        with self.assertRaises(secure.SecureIOError):
            secure.install_state_read()

        (state_dir / "second-link").unlink()
        state.write_bytes(b"x" * (secure.INSTALL_STATE_LIMIT + 1))
        with self.assertRaises(secure.SecureIOError):
            secure.install_state_read()

    def test_install_state_rejects_depth_key_and_multibyte_byte_overflow(self) -> None:
        deep: object = "end"
        for _ in range(secure.MAX_JSON_DEPTH + 1):
            deep = {"next": deep}
        with self.assertRaises(secure.SecureIOError):
            secure.install_state_write(json.dumps(deep).encode("utf-8"))

        too_many_keys = {f"key-{index}": index for index in range(secure.MAX_JSON_KEYS + 1)}
        with self.assertRaises(secure.SecureIOError):
            secure.install_state_write(json.dumps(too_many_keys).encode("utf-8"))

        oversized_string = {"value": "é" * (secure.MAX_JSON_STRING_BYTES // 2 + 1)}
        with self.assertRaises(secure.SecureIOError):
            secure.install_state_write(
                json.dumps(oversized_string, ensure_ascii=False).encode("utf-8")
            )
        for malformed in (b"{", b"]", b'{"unterminated":"value}'):
            with self.assertRaises(secure.SecureIOError):
                secure.install_state_write(malformed)

        deeply_nested = (b"[" * 2000) + b"0" + (b"]" * 2000)
        with self.assertRaises(secure.SecureIOError):
            secure.install_state_write(deeply_nested)

    def test_command_install_update_and_remove_are_hash_bound(self) -> None:
        plugin = self.home / "plugin"
        plugin.mkdir(mode=0o700)
        source = plugin / secure.COMMAND_NAME
        source.write_bytes(b"#!/bin/bash\necho first\n")
        source.chmod(0o644)
        command_dir = self.home / ".local/bin"
        command_dir.mkdir(parents=True, mode=0o755)
        victim = self.home / "victim"
        victim.write_text("keep", encoding="utf-8")
        (command_dir / "one-bit-bureau.tmp").symlink_to(victim)

        first_hash = secure.command_install(plugin)
        target = command_dir / secure.COMMAND_NAME
        self.assertEqual(first_hash, secure.hash_bytes(target.read_bytes()))
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)
        self.assertEqual(victim.read_text(encoding="utf-8"), "keep")

        source.write_bytes(b"#!/bin/bash\necho second\n")
        second_hash = secure.command_replace_if_owned(plugin, first_hash)
        self.assertNotEqual(second_hash, first_hash)
        self.assertIn(b"second", target.read_bytes())
        self.assertTrue(secure.command_remove_if_owned(second_hash))
        self.assertFalse(target.exists())

    def test_command_preserves_symlink_and_hardlink_targets(self) -> None:
        plugin = self.home / "plugin"
        plugin.mkdir(mode=0o700)
        (plugin / secure.COMMAND_NAME).write_bytes(b"new command")
        command_dir = self.home / ".local/bin"
        command_dir.mkdir(parents=True, mode=0o755)
        target = command_dir / secure.COMMAND_NAME
        victim = self.home / "victim"
        victim.write_bytes(b"owned command")
        expected = secure.hash_bytes(victim.read_bytes())

        target.symlink_to(victim)
        self.assertEqual(secure.command_replace_if_owned(plugin, expected), expected)
        self.assertFalse(secure.command_remove_if_owned(expected))
        self.assertEqual(victim.read_bytes(), b"owned command")

        target.unlink()
        os.link(victim, target)
        self.assertEqual(secure.command_replace_if_owned(plugin, expected), expected)
        self.assertFalse(secure.command_remove_if_owned(expected))
        self.assertEqual(victim.read_bytes(), b"owned command")

    def test_tree_hash_rejects_file_count_depth_total_bytes_and_symlinks(self) -> None:
        trees = self.home / "trees"
        trees.mkdir(mode=0o700)

        exact = trees / "exact"
        exact.mkdir(mode=0o700)
        for index in range(secure.TREE_MAX_FILES):
            (exact / f"file-{index}").write_bytes(b"")
        parent_fd = secure.open_user_directory(trees, create=False)
        try:
            self.assertRegex(secure.tree_hash_at(parent_fd, "exact"), r"^[a-f0-9]{64}$")
        finally:
            os.close(parent_fd)

        too_many = trees / "too-many"
        too_many.mkdir(mode=0o700)
        for index in range(secure.TREE_MAX_FILES + 1):
            (too_many / f"file-{index}").write_bytes(b"")
        parent_fd = secure.open_user_directory(trees, create=False)
        try:
            with self.assertRaises(secure.SecureIOError):
                secure.tree_hash_at(parent_fd, "too-many")
        finally:
            os.close(parent_fd)

        too_deep = trees / "too-deep"
        cursor = too_deep
        for _ in range(secure.TREE_MAX_DEPTH + 2):
            cursor.mkdir(mode=0o700)
            cursor = cursor / "child"
        parent_fd = secure.open_user_directory(trees, create=False)
        try:
            with self.assertRaises(secure.SecureIOError):
                secure.tree_hash_at(parent_fd, "too-deep")
        finally:
            os.close(parent_fd)

        too_large = trees / "too-large"
        too_large.mkdir(mode=0o700)
        (too_large / "first").write_bytes(b"a" * (secure.TREE_MAX_BYTES // 2 + 1))
        (too_large / "second").write_bytes(b"b" * (secure.TREE_MAX_BYTES // 2 + 1))
        parent_fd = secure.open_user_directory(trees, create=False)
        try:
            with self.assertRaises(secure.SecureIOError):
                secure.tree_hash_at(parent_fd, "too-large")
        finally:
            os.close(parent_fd)

        linked = trees / "linked"
        linked.mkdir(mode=0o700)
        (linked / "outside").symlink_to(self.home / "victim")
        parent_fd = secure.open_user_directory(trees, create=False)
        try:
            with self.assertRaises(secure.SecureIOError):
                secure.tree_hash_at(parent_fd, "linked")
        finally:
            os.close(parent_fd)

    def test_tree_hash_and_removal_ignore_an_exhausted_caller_cursor(self) -> None:
        trees = self.home / "trees"
        trees.mkdir(mode=0o700)
        owned = trees / "owned"
        child = owned / "child"
        child.mkdir(parents=True, mode=0o700)
        (owned / "root-file").write_bytes(b"root")
        (child / "nested-file").write_bytes(b"nested")

        parent_fd = secure.open_user_directory(trees, create=False)
        owned_fd = secure.open_child_directory(parent_fd, "owned", create=False)
        try:
            expected = secure.tree_hash_fd(owned_fd)
            os.listdir(owned_fd)
            self.assertEqual(secure.tree_hash_fd(owned_fd), expected)
        finally:
            os.close(owned_fd)

        try:
            self.assertTrue(secure.remove_tree_at(parent_fd, "owned", expected_hash=expected))
            self.assertFalse(owned.exists())
        finally:
            os.close(parent_fd)


if __name__ == "__main__":
    unittest.main()
