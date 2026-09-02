#!/usr/bin/python3
"""Bounded, descriptor-relative transactions for One-Bit Bureau user state."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import secrets
import signal
import stat
import sys
from pathlib import Path


PLUGIN_ID = "io.github.regionallyfamous.one-bit-bureau"
INSTALL_STATE_NAME = "install-state.json"
INSTALL_STATE_LIMIT = 64 * 1024
INSTALL_STATE_SNAPSHOT_LIMIT = INSTALL_STATE_LIMIT + 1024
COMMAND_NAME = "one-bit-bureau"
COMMAND_LIMIT = 1024 * 1024
MAX_JSON_DEPTH = 6
MAX_JSON_NODES = 128
MAX_JSON_KEYS = 64
MAX_JSON_STRING_BYTES = 4096
TREE_MAX_BYTES = 1024 * 1024
TREE_MAX_FILES = 32
TREE_MAX_DIRECTORIES = 8
TREE_MAX_DEPTH = 3


class SecureIOError(RuntimeError):
    """A path, object, or resource budget did not satisfy the transaction."""


def deadline(_signum: int, _frame: object) -> None:
    raise SecureIOError("secure transaction exceeded its 10-second deadline")


def nofollow_flag() -> int:
    return getattr(os, "O_NOFOLLOW", 0)


def _directory_flags() -> int:
    return os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | nofollow_flag()


def _file_flags() -> int:
    return os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK | nofollow_flag()


def validate_directory(descriptor: int) -> os.stat_result:
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode):
        raise SecureIOError("trusted parent must be a directory")
    if metadata.st_uid != os.getuid():
        raise SecureIOError("trusted parent must be owned by the current user")
    if metadata.st_mode & 0o022:
        raise SecureIOError("trusted parent may not be group or world writable")
    return metadata


def validate_regular(
    descriptor: int,
    byte_limit: int,
    *,
    label: str = "file",
) -> os.stat_result:
    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode):
        raise SecureIOError(f"{label} must be a regular file")
    if metadata.st_uid != os.getuid():
        raise SecureIOError(f"{label} must be owned by the current user")
    if metadata.st_nlink != 1:
        raise SecureIOError(f"{label} must have exactly one link")
    if metadata.st_mode & 0o022:
        raise SecureIOError(f"{label} may not be group or world writable")
    if metadata.st_size > byte_limit:
        raise SecureIOError(f"{label} exceeds its {byte_limit}-byte budget")
    return metadata


def open_child_directory(
    parent_fd: int,
    name: str,
    *,
    create: bool,
    private: bool = False,
) -> int:
    if not name or name in {".", ".."} or "/" in name or "\x00" in name:
        raise SecureIOError("invalid directory component")
    try:
        descriptor = os.open(name, _directory_flags(), dir_fd=parent_fd)
    except FileNotFoundError:
        if not create:
            raise
        os.mkdir(name, 0o700 if private else 0o755, dir_fd=parent_fd)
        os.fsync(parent_fd)
        descriptor = os.open(name, _directory_flags(), dir_fd=parent_fd)
    except OSError as error:
        raise SecureIOError(f"unsafe directory component {name}: {error.strerror}") from error
    validate_directory(descriptor)
    return descriptor


def _home_path() -> Path:
    raw_home = os.environ.get("HOME", "")
    if not raw_home or not os.path.isabs(raw_home) or "\x00" in raw_home:
        raise SecureIOError("HOME must name an absolute directory")
    return Path(os.path.normpath(raw_home))


def open_user_directory(path: str | Path, *, create: bool, private: bool = False) -> int:
    """Open a user-owned directory below HOME without following any component."""
    home = _home_path()
    target = Path(os.path.normpath(os.fspath(path)))
    if not target.is_absolute():
        raise SecureIOError("trusted user path must be absolute")
    try:
        relative = target.relative_to(home)
    except ValueError as error:
        raise SecureIOError("trusted user path must stay below HOME") from error
    try:
        descriptor = os.open(home, _directory_flags())
    except OSError as error:
        raise SecureIOError(f"unsafe HOME directory: {error.strerror}") from error
    validate_directory(descriptor)
    try:
        parts = relative.parts
        for index, component in enumerate(parts):
            child = open_child_directory(
                descriptor,
                component,
                create=create,
                private=private and index == len(parts) - 1,
            )
            if private and index == len(parts) - 1:
                metadata = os.fstat(child)
                if stat.S_IMODE(metadata.st_mode) != 0o700:
                    os.fchmod(child, 0o700)
                    os.fsync(child)
                    os.fsync(descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def open_owned_directory(path: str | Path) -> int:
    """Open an already-existing user directory without following any component."""
    return open_user_directory(path, create=False)


def install_state_path() -> Path:
    return _home_path() / ".local/state/omarchy/plugins" / PLUGIN_ID


def open_install_state_directory(*, create: bool) -> int:
    return open_user_directory(install_state_path(), create=create, private=True)


def _read_descriptor(descriptor: int, byte_limit: int, *, label: str) -> bytes:
    validate_regular(descriptor, byte_limit, label=label)
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = os.read(descriptor, min(65_536, byte_limit + 1 - total))
        if not chunk:
            return b"".join(chunks)
        total += len(chunk)
        if total > byte_limit:
            raise SecureIOError(f"{label} exceeds its {byte_limit}-byte budget")
        chunks.append(chunk)


def read_bytes_at(
    directory_fd: int,
    name: str,
    byte_limit: int,
    *,
    missing_ok: bool = False,
    label: str = "file",
) -> bytes | None:
    if not name or name in {".", ".."} or "/" in name or "\x00" in name:
        raise SecureIOError("invalid file name")
    try:
        descriptor = os.open(name, _file_flags(), dir_fd=directory_fd)
    except FileNotFoundError:
        if missing_ok:
            return None
        raise SecureIOError(f"missing {label}") from None
    except OSError as error:
        raise SecureIOError(f"unsafe {label}: {error.strerror}") from error
    try:
        return _read_descriptor(descriptor, byte_limit, label=label)
    finally:
        os.close(descriptor)


def hash_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def hash_file_at(
    directory_fd: int,
    name: str,
    byte_limit: int,
    *,
    missing_ok: bool = False,
    label: str = "file",
) -> str | None:
    payload = read_bytes_at(
        directory_fd,
        name,
        byte_limit,
        missing_ok=missing_ok,
        label=label,
    )
    return None if payload is None else hash_bytes(payload)


def _entry_identity(directory_fd: int, name: str) -> tuple[int, int] | None:
    try:
        metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    return metadata.st_dev, metadata.st_ino


def _open_existing_identity(
    directory_fd: int,
    name: str,
    byte_limit: int,
    *,
    label: str,
) -> tuple[tuple[int, int], bytes]:
    try:
        descriptor = os.open(name, _file_flags(), dir_fd=directory_fd)
    except FileNotFoundError as error:
        raise SecureIOError(f"missing {label}") from error
    except OSError as error:
        raise SecureIOError(f"unsafe {label}: {error.strerror}") from error
    try:
        metadata = validate_regular(descriptor, byte_limit, label=label)
        payload = _read_descriptor(descriptor, byte_limit, label=label)
        return (metadata.st_dev, metadata.st_ino), payload
    finally:
        os.close(descriptor)


def atomic_write_at(
    directory_fd: int,
    name: str,
    payload: bytes,
    *,
    mode: int,
    byte_limit: int,
    require_absent: bool = False,
    expected_hash: str | None = None,
    label: str = "file",
) -> str:
    """Durably replace one name after validating the exact prior object."""
    if len(payload) > byte_limit:
        raise SecureIOError(f"{label} exceeds its {byte_limit}-byte budget")
    prior_identity: tuple[int, int] | None = None
    if require_absent:
        if _entry_identity(directory_fd, name) is not None:
            raise SecureIOError(f"refusing to replace existing {label}")
    else:
        try:
            prior_identity, prior = _open_existing_identity(
                directory_fd,
                name,
                byte_limit,
                label=label,
            )
        except SecureIOError:
            if expected_hash is not None:
                raise
            if _entry_identity(directory_fd, name) is not None:
                raise
        else:
            if expected_hash is not None and hash_bytes(prior) != expected_hash:
                raise SecureIOError(f"{label} no longer matches its ownership hash")

    temporary = f".{name}.tmp-{os.getpid()}-{secrets.token_hex(16)}"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | nofollow_flag()
    descriptor = os.open(temporary, flags, mode, dir_fd=directory_fd)
    try:
        os.fchmod(descriptor, mode)
        view = memoryview(payload)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
        validate_regular(descriptor, byte_limit, label="temporary transaction file")
    finally:
        os.close(descriptor)
    try:
        current_identity = _entry_identity(directory_fd, name)
        if require_absent and current_identity is not None:
            raise SecureIOError(f"{label} appeared during the transaction")
        if prior_identity is not None and current_identity != prior_identity:
            raise SecureIOError(f"{label} changed during the transaction")
        if prior_identity is None and not require_absent and current_identity is not None:
            raise SecureIOError(f"{label} appeared during the transaction")
        os.replace(temporary, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        os.fsync(directory_fd)
    finally:
        try:
            os.unlink(temporary, dir_fd=directory_fd)
        except FileNotFoundError:
            pass
    return hash_bytes(payload)


def remove_file_at(
    directory_fd: int,
    name: str,
    byte_limit: int,
    *,
    expected_hash: str | None = None,
    missing_ok: bool = False,
    label: str = "file",
) -> bool:
    try:
        identity, payload = _open_existing_identity(
            directory_fd,
            name,
            byte_limit,
            label=label,
        )
    except SecureIOError:
        if missing_ok and _entry_identity(directory_fd, name) is None:
            return False
        raise
    if expected_hash is not None and hash_bytes(payload) != expected_hash:
        return False
    if _entry_identity(directory_fd, name) != identity:
        raise SecureIOError(f"{label} changed during removal")
    os.unlink(name, dir_fd=directory_fd)
    os.fsync(directory_fd)
    return True


def validate_json_budget(value: object) -> None:
    stack: list[tuple[object, int]] = [(value, 1)]
    nodes = 0
    keys = 0
    while stack:
        current, depth = stack.pop()
        nodes += 1
        if nodes > MAX_JSON_NODES:
            raise SecureIOError("JSON exceeds its node ceiling")
        if depth > MAX_JSON_DEPTH:
            raise SecureIOError("JSON exceeds its depth ceiling")
        if isinstance(current, dict):
            keys += len(current)
            if keys > MAX_JSON_KEYS:
                raise SecureIOError("JSON exceeds its key ceiling")
            for key, child in current.items():
                if not isinstance(key, str):
                    raise SecureIOError("JSON object key must be a string")
                if len(key.encode("utf-8")) > MAX_JSON_STRING_BYTES:
                    raise SecureIOError("JSON key exceeds its byte ceiling")
                stack.append((child, depth + 1))
        elif isinstance(current, list):
            stack.extend((child, depth + 1) for child in current)
        elif isinstance(current, str):
            if len(current.encode("utf-8")) > MAX_JSON_STRING_BYTES:
                raise SecureIOError("JSON string exceeds its byte ceiling")
        elif isinstance(current, float) and not math.isfinite(current):
            raise SecureIOError("JSON number must be finite")
        elif current is not None and not isinstance(current, (bool, int, float)):
            raise SecureIOError("JSON contains an unsupported value")


def validate_json_lexical_depth(payload: bytes) -> None:
    depth = 0
    in_string = False
    escaped = False
    for byte in payload:
        if in_string:
            if escaped:
                escaped = False
            elif byte == 0x5C:
                escaped = True
            elif byte == 0x22:
                in_string = False
            continue
        if byte == 0x22:
            in_string = True
        elif byte in {0x5B, 0x7B}:
            depth += 1
            if depth > MAX_JSON_DEPTH:
                raise SecureIOError("JSON exceeds its depth ceiling")
        elif byte in {0x5D, 0x7D}:
            depth -= 1
            if depth < 0:
                raise SecureIOError("JSON structure is unbalanced")


def parse_json(payload: bytes, *, label: str) -> object:
    validate_json_lexical_depth(payload)
    try:
        value = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
        raise SecureIOError(f"{label} is not valid UTF-8 JSON") from error
    validate_json_budget(value)
    return value


def encode_json(value: object, byte_limit: int) -> bytes:
    validate_json_budget(value)
    payload = (
        json.dumps(
            value,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")
    if len(payload) > byte_limit:
        raise SecureIOError("JSON exceeds its byte budget")
    return payload


def read_stdin(byte_limit: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = os.read(0, min(65_536, byte_limit + 1 - total))
        if not chunk:
            return b"".join(chunks)
        total += len(chunk)
        if total > byte_limit:
            raise SecureIOError("standard input exceeds its byte budget")
        chunks.append(chunk)


def _tree_hash(
    directory_fd: int,
    *,
    prefix: str,
    depth: int,
    budget: dict[str, int],
    entries: list[tuple[str, str]],
) -> None:
    if depth > TREE_MAX_DEPTH:
        raise SecureIOError("tree exceeds its depth ceiling")
    try:
        names = sorted(os.listdir(directory_fd))
    except OSError as error:
        raise SecureIOError(f"could not enumerate owned tree: {error}") from error
    for name in names:
        if not name or name in {".", ".."} or "/" in name or "\x00" in name:
            raise SecureIOError("tree contains an invalid entry name")
        relative = f"{prefix}/{name}" if prefix else name
        try:
            metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError as error:
            raise SecureIOError(f"could not inspect tree entry {relative}") from error
        if stat.S_ISDIR(metadata.st_mode):
            budget["directories"] += 1
            if budget["directories"] > TREE_MAX_DIRECTORIES:
                raise SecureIOError("tree exceeds its directory-count ceiling")
            child = open_child_directory(directory_fd, name, create=False)
            try:
                child_metadata = os.fstat(child)
                if (child_metadata.st_dev, child_metadata.st_ino) != (
                    metadata.st_dev,
                    metadata.st_ino,
                ):
                    raise SecureIOError("tree directory changed during inspection")
                _tree_hash(
                    child,
                    prefix=relative,
                    depth=depth + 1,
                    budget=budget,
                    entries=entries,
                )
            finally:
                os.close(child)
        elif stat.S_ISREG(metadata.st_mode):
            budget["files"] += 1
            if budget["files"] > TREE_MAX_FILES:
                raise SecureIOError("tree exceeds its file-count ceiling")
            payload = read_bytes_at(
                directory_fd,
                name,
                TREE_MAX_BYTES,
                label=f"tree entry {relative}",
            )
            assert payload is not None
            budget["bytes"] += len(payload)
            if budget["bytes"] > TREE_MAX_BYTES:
                raise SecureIOError("tree exceeds its total-byte ceiling")
            entries.append((relative, hash_bytes(payload)))
        else:
            raise SecureIOError(f"tree contains unsafe entry {relative}")


def tree_hash_fd(directory_fd: int) -> str:
    validate_directory(directory_fd)
    entries: list[tuple[str, str]] = []
    _tree_hash(
        directory_fd,
        prefix="",
        depth=0,
        budget={"files": 0, "directories": 0, "bytes": 0},
        entries=entries,
    )
    return hash_bytes(json.dumps(entries, separators=(",", ":")).encode("utf-8"))


def tree_hash_at(directory_fd: int, name: str) -> str:
    child = open_child_directory(directory_fd, name, create=False)
    try:
        return tree_hash_fd(child)
    finally:
        os.close(child)


def create_directory_at(directory_fd: int, name: str, *, mode: int = 0o700) -> int:
    if _entry_identity(directory_fd, name) is not None:
        raise SecureIOError("refusing to replace an existing directory")
    os.mkdir(name, mode, dir_fd=directory_fd)
    os.fsync(directory_fd)
    child = os.open(name, _directory_flags(), dir_fd=directory_fd)
    validate_directory(child)
    return child


def _remove_tree_contents(directory_fd: int, *, depth: int, budget: dict[str, int]) -> None:
    if depth > TREE_MAX_DEPTH:
        raise SecureIOError("tree exceeds its removal depth ceiling")
    for name in sorted(os.listdir(directory_fd)):
        metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if stat.S_ISDIR(metadata.st_mode):
            budget["directories"] += 1
            if budget["directories"] > TREE_MAX_DIRECTORIES:
                raise SecureIOError("tree exceeds its removal directory ceiling")
            child = open_child_directory(directory_fd, name, create=False)
            try:
                child_metadata = os.fstat(child)
                if (child_metadata.st_dev, child_metadata.st_ino) != (
                    metadata.st_dev,
                    metadata.st_ino,
                ):
                    raise SecureIOError("tree changed during removal")
                _remove_tree_contents(child, depth=depth + 1, budget=budget)
            finally:
                os.close(child)
            current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            if (current.st_dev, current.st_ino) != (metadata.st_dev, metadata.st_ino):
                raise SecureIOError("tree changed during removal")
            os.rmdir(name, dir_fd=directory_fd)
        elif stat.S_ISREG(metadata.st_mode):
            budget["files"] += 1
            if budget["files"] > TREE_MAX_FILES:
                raise SecureIOError("tree exceeds its removal file ceiling")
            descriptor = os.open(name, _file_flags(), dir_fd=directory_fd)
            try:
                current = validate_regular(
                    descriptor,
                    TREE_MAX_BYTES,
                    label="tree removal entry",
                )
                budget["bytes"] += current.st_size
                if budget["bytes"] > TREE_MAX_BYTES:
                    raise SecureIOError("tree exceeds its removal byte ceiling")
                identity = (current.st_dev, current.st_ino)
            finally:
                os.close(descriptor)
            if _entry_identity(directory_fd, name) != identity:
                raise SecureIOError("tree changed during removal")
            os.unlink(name, dir_fd=directory_fd)
        else:
            raise SecureIOError("tree contains an unsafe removal entry")
    os.fsync(directory_fd)


def remove_tree_at(
    directory_fd: int,
    name: str,
    *,
    expected_hash: str | None = None,
    expected_identity: tuple[int, int] | None = None,
) -> bool:
    try:
        child = open_child_directory(directory_fd, name, create=False)
    except (FileNotFoundError, SecureIOError):
        return False
    try:
        metadata = os.fstat(child)
        identity = (metadata.st_dev, metadata.st_ino)
        if expected_identity is not None and identity != expected_identity:
            raise SecureIOError("owned tree identity changed")
        if expected_hash is not None and tree_hash_fd(child) != expected_hash:
            return False
        _remove_tree_contents(
            child,
            depth=0,
            budget={"files": 0, "directories": 0, "bytes": 0},
        )
        current = _entry_identity(directory_fd, name)
        if current != identity:
            raise SecureIOError("owned tree changed before final removal")
        os.rmdir(name, dir_fd=directory_fd)
        os.fsync(directory_fd)
        return True
    finally:
        os.close(child)


def _plugin_source(plugin_dir: str | Path) -> tuple[int, bytes]:
    plugin_fd = open_owned_directory(plugin_dir)
    try:
        payload = read_bytes_at(
            plugin_fd,
            COMMAND_NAME,
            COMMAND_LIMIT,
            label="command source",
        )
        assert payload is not None
        return plugin_fd, payload
    except BaseException:
        os.close(plugin_fd)
        raise


def _command_directory(*, create: bool) -> int:
    return open_user_directory(_home_path() / ".local/bin", create=create)


def command_source_hash(plugin_dir: str | Path) -> str:
    plugin_fd, payload = _plugin_source(plugin_dir)
    os.close(plugin_fd)
    return hash_bytes(payload)


def command_install(plugin_dir: str | Path, expected_source_hash: str | None = None) -> str:
    plugin_fd, payload = _plugin_source(plugin_dir)
    os.close(plugin_fd)
    if expected_source_hash is not None:
        if not re_full_sha(expected_source_hash):
            raise SecureIOError("invalid expected command source hash")
        if hash_bytes(payload) != expected_source_hash:
            raise SecureIOError("command source changed during installation")
    directory_fd = _command_directory(create=True)
    try:
        return atomic_write_at(
            directory_fd,
            COMMAND_NAME,
            payload,
            mode=0o755,
            byte_limit=COMMAND_LIMIT,
            require_absent=True,
            label="One-Bit Bureau command",
        )
    finally:
        os.close(directory_fd)


def command_replace_if_owned(plugin_dir: str | Path, expected_hash: str) -> str:
    if not re_full_sha(expected_hash):
        raise SecureIOError("invalid command ownership hash")
    try:
        directory_fd = _command_directory(create=False)
    except (FileNotFoundError, SecureIOError):
        return expected_hash
    try:
        try:
            current = hash_file_at(
                directory_fd,
                COMMAND_NAME,
                COMMAND_LIMIT,
                missing_ok=True,
                label="One-Bit Bureau command",
            )
        except SecureIOError:
            return expected_hash
        if current != expected_hash:
            return expected_hash
        plugin_fd, payload = _plugin_source(plugin_dir)
        os.close(plugin_fd)
        return atomic_write_at(
            directory_fd,
            COMMAND_NAME,
            payload,
            mode=0o755,
            byte_limit=COMMAND_LIMIT,
            expected_hash=expected_hash,
            label="One-Bit Bureau command",
        )
    finally:
        os.close(directory_fd)


def command_remove_if_owned(expected_hash: str) -> bool:
    if not re_full_sha(expected_hash):
        raise SecureIOError("invalid command ownership hash")
    try:
        directory_fd = _command_directory(create=False)
    except (FileNotFoundError, SecureIOError):
        return False
    try:
        try:
            return remove_file_at(
                directory_fd,
                COMMAND_NAME,
                COMMAND_LIMIT,
                expected_hash=expected_hash,
                missing_ok=True,
                label="One-Bit Bureau command",
            )
        except SecureIOError:
            return False
    finally:
        os.close(directory_fd)


def re_full_sha(value: str) -> bool:
    return len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def _read_install_state_payload() -> tuple[object, bytes]:
    directory_fd = open_install_state_directory(create=False)
    try:
        payload = read_bytes_at(
            directory_fd,
            INSTALL_STATE_NAME,
            INSTALL_STATE_LIMIT,
            label="install ownership record",
        )
        assert payload is not None
        value = parse_json(payload, label="install ownership record")
        return value, payload
    finally:
        os.close(directory_fd)


def install_state_read() -> bytes:
    value, _payload = _read_install_state_payload()
    return encode_json(value, INSTALL_STATE_LIMIT)


def install_state_snapshot() -> bytes:
    value, payload = _read_install_state_payload()
    return encode_json(
        {"record": value, "recordHash": hash_bytes(payload)},
        INSTALL_STATE_SNAPSHOT_LIMIT,
    )


def install_state_write(
    payload: bytes,
    *,
    expected_hash: str | None = None,
    require_absent: bool = False,
) -> str:
    if expected_hash is not None and not re_full_sha(expected_hash):
        raise SecureIOError("invalid install-state ownership hash")
    value = parse_json(payload, label="install ownership record")
    encoded = encode_json(value, INSTALL_STATE_LIMIT)
    directory_fd = open_install_state_directory(create=True)
    try:
        return atomic_write_at(
            directory_fd,
            INSTALL_STATE_NAME,
            encoded,
            mode=0o600,
            byte_limit=INSTALL_STATE_LIMIT,
            expected_hash=expected_hash,
            require_absent=require_absent,
            label="install ownership record",
        )
    finally:
        os.close(directory_fd)


def install_state_delete(expected_hash: str | None = None) -> bool:
    if expected_hash is not None and not re_full_sha(expected_hash):
        raise SecureIOError("invalid install-state ownership hash")
    try:
        directory_fd = open_install_state_directory(create=False)
    except (FileNotFoundError, SecureIOError):
        return False
    try:
        return remove_file_at(
            directory_fd,
            INSTALL_STATE_NAME,
            INSTALL_STATE_LIMIT,
            expected_hash=expected_hash,
            missing_ok=True,
            label="install ownership record",
        )
    finally:
        os.close(directory_fd)


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("domain", choices=("install-state", "command"))
    parser.add_argument("operation")
    parser.add_argument("--plugin-dir")
    parser.add_argument("--expected-hash")
    parser.add_argument("--require-absent", action="store_true")
    arguments = parser.parse_args()
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(10)

    if arguments.domain == "install-state":
        if arguments.operation == "read":
            os.write(1, install_state_read())
            return 0
        if arguments.operation == "snapshot":
            os.write(1, install_state_snapshot())
            return 0
        if arguments.operation == "exists":
            try:
                install_state_read()
                return 0
            except (FileNotFoundError, SecureIOError):
                return 1
        if arguments.operation == "write":
            print(
                install_state_write(
                    read_stdin(INSTALL_STATE_LIMIT),
                    expected_hash=arguments.expected_hash,
                    require_absent=arguments.require_absent,
                )
            )
            return 0
        if arguments.operation == "delete":
            print(
                "removed"
                if install_state_delete(arguments.expected_hash)
                else "preserved"
            )
            return 0
    elif arguments.domain == "command":
        if arguments.operation in {"source-hash", "install", "replace-if-owned"}:
            if not arguments.plugin_dir:
                raise SecureIOError("command operation requires --plugin-dir")
        if arguments.operation == "source-hash":
            print(command_source_hash(arguments.plugin_dir))
            return 0
        if arguments.operation == "install":
            print(command_install(arguments.plugin_dir, arguments.expected_hash))
            return 0
        if arguments.operation == "replace-if-owned":
            if not arguments.expected_hash:
                raise SecureIOError("command replacement requires --expected-hash")
            print(command_replace_if_owned(arguments.plugin_dir, arguments.expected_hash))
            return 0
        if arguments.operation == "remove-if-owned":
            if not arguments.expected_hash:
                raise SecureIOError("command removal requires --expected-hash")
            print("removed" if command_remove_if_owned(arguments.expected_hash) else "preserved")
            return 0
    raise SecureIOError("unsupported secure transaction")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, SecureIOError) as error:
        print(f"one-bit-bureau secure I/O: {error}", file=sys.stderr)
        raise SystemExit(1)
