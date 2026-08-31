#!/usr/bin/python3
"""Pure path and trust policy for the One-Bit Bureau desktop helpers.

This module deliberately has no Gtk/Gio dependency so the security-sensitive
path rules can be unit-tested outside a running Omarchy session.
"""

from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote, urlparse


MAX_USER_DIRS_BYTES = 64 * 1024
LAUNCHER_METADATA_TIMEOUT_SECONDS = 10
_DESKTOP_ASSIGNMENT_RE = re.compile(
    rb'^\s*XDG_DESKTOP_DIR="((?:[^"\\]|\\.)*)"\s*$'
)


class DesktopDisabledError(RuntimeError):
    """The user explicitly disabled the XDG Desktop directory."""


@dataclass(frozen=True)
class DesktopLocation:
    enabled: bool
    path: Path | None
    state: str
    reason: str


def _absolute_path(value: str, *, home: Path) -> Path:
    expanded = os.path.expanduser(value.replace("${HOME}", str(home)).replace("$HOME", str(home)))
    if "$" in expanded or not os.path.isabs(expanded) or expanded.startswith("//"):
        raise ValueError("XDG Desktop path is not an absolute local path")
    return Path(os.path.abspath(expanded)).resolve()


def _read_regular_file(path: Path, limit: int) -> bytes | None:
    """Read a small regular file without following a final symlink."""

    fd = -1
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            return None
        chunks: list[bytes] = []
        remaining = limit + 1
        while remaining:
            block = os.read(fd, min(8192, remaining))
            if not block:
                break
            chunks.append(block)
            remaining -= len(block)
        payload = b"".join(chunks)
        return payload if len(payload) <= limit else None
    except OSError:
        return None
    finally:
        if fd >= 0:
            os.close(fd)


def resolve_desktop_location(
    *,
    home: Path | None = None,
    environ: dict[str, str] | None = None,
    max_user_dirs_bytes: int = MAX_USER_DIRS_BYTES,
) -> DesktopLocation:
    """Resolve XDG_DESKTOP_DIR without evaluating shell syntax.

    Per xdg-user-dirs, a user directory which resolves to the home directory is
    disabled.  A missing or invalid configuration falls back to the conventional
    ``$HOME/Desktop`` path, but this function never creates it.
    """

    env = os.environ if environ is None else environ
    user_home = (Path.home() if home is None else Path(home)).expanduser().resolve()
    config_raw = env.get("XDG_CONFIG_HOME", "")
    try:
        config = (
            _absolute_path(config_raw, home=user_home)
            if config_raw
            else user_home / ".config"
        )
    except ValueError:
        config = user_home / ".config"

    payload = _read_regular_file(config / "user-dirs.dirs", max_user_dirs_bytes)
    configured: Path | None = None
    if payload is not None:
        for line in payload.splitlines():
            match = _DESKTOP_ASSIGNMENT_RE.fullmatch(line)
            if not match:
                continue
            try:
                raw = re.sub(rb"\\([\\\"$`])", rb"\1", match.group(1)).decode(
                    "utf-8", "strict"
                )
                configured = _absolute_path(raw, home=user_home)
            except (UnicodeDecodeError, ValueError, OSError):
                configured = None
            break

    path = configured if configured is not None else (user_home / "Desktop").resolve()
    if path == user_home:
        return DesktopLocation(
            enabled=False,
            path=None,
            state="disabled",
            reason="The Desktop directory is disabled in XDG user directories.",
        )
    return DesktopLocation(enabled=True, path=path, state="enabled", reason="")


def require_desktop_directory(
    *, home: Path | None = None, environ: dict[str, str] | None = None
) -> Path:
    location = resolve_desktop_location(home=home, environ=environ)
    if not location.enabled or location.path is None:
        raise DesktopDisabledError(location.reason)
    return location.path


def lexical_path(value: str) -> Path:
    """Return an absolute local path without resolving its final symlink."""

    text = str(value or "").strip().strip("<>").strip()
    if not text:
        raise ValueError("Path is empty")
    if text.startswith("file://"):
        parsed = urlparse(text)
        if parsed.netloc and parsed.netloc.lower() not in {"", "localhost"}:
            raise ValueError("Remote file URI is not allowed")
        text = unquote(parsed.path)
        if not text:
            raise ValueError("File URI has no local path")
    return Path(os.path.abspath(os.path.expanduser(text)))


def _metadata_is_trusted(gio_info_output: str) -> bool:
    for line in str(gio_info_output or "").splitlines():
        stripped = line.strip()
        prefix = "metadata::trusted:"
        if stripped.startswith(prefix):
            return stripped[len(prefix) :].strip().lower() in {"true", "yes", "1"}
    return False


def enforce_untrusted_launcher(
    path: Path,
    *,
    runner=subprocess.run,
    chmod_func=os.chmod,
) -> None:
    """Clear both launcher trust signals or fail without claiming success."""

    current = path.stat(follow_symlinks=False)
    if not stat.S_ISREG(current.st_mode):
        raise ValueError("Launcher destination is not a regular file")
    chmod_func(path, stat.S_IMODE(current.st_mode) & ~0o111)
    runner(
        ["gio", "set", str(path), "metadata::trusted", "false"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=LAUNCHER_METADATA_TIMEOUT_SECONDS,
        start_new_session=True,
    )
    after = path.stat(follow_symlinks=False)
    if after.st_mode & 0o111:
        raise PermissionError("Could not clear launcher execute bits")
    info = runner(
        ["gio", "info", "-a", "metadata::trusted", str(path)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=LAUNCHER_METADATA_TIMEOUT_SECONDS,
        start_new_session=True,
    )
    if _metadata_is_trusted(info.stdout):
        raise PermissionError("Could not clear launcher trusted metadata")


def copy_untrusted_launcher(
    source: Path,
    destination: Path,
    *,
    runner=subprocess.run,
    chmod_func=os.chmod,
    copy_func=shutil.copy2,
) -> None:
    """Copy a launcher and remove the copy if its safe state cannot be proved."""

    try:
        copy_func(source, destination)
        enforce_untrusted_launcher(
            destination,
            runner=runner,
            chmod_func=chmod_func,
        )
    except Exception:
        try:
            destination.unlink()
        except FileNotFoundError:
            pass
        raise


def is_under(path: Path, root: Path) -> bool:
    try:
        path.expanduser().resolve().relative_to(root.expanduser().resolve())
        return True
    except (ValueError, OSError):
        return False


def trusted_application_dirs(
    *, home: Path | None = None, environ: dict[str, str] | None = None
) -> list[Path]:
    env = os.environ if environ is None else environ
    user_home = Path.home() if home is None else home
    directories: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        try:
            resolved = path.expanduser().resolve()
        except OSError:
            return
        key = str(resolved)
        if key in seen:
            return
        seen.add(key)
        directories.append(resolved)

    add(Path("/usr/share/applications"))
    add(Path("/usr/local/share/applications"))
    add(user_home / ".local/share/applications")
    for raw in env.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if raw.strip():
            add(Path(raw) / "applications")
    data_home = env.get("XDG_DATA_HOME")
    if data_home:
        add(Path(data_home) / "applications")
    return directories


def is_trusted_application_launcher(
    path: Path, directories: list[Path] | None = None
) -> bool:
    if path.suffix.lower() != ".desktop":
        return False
    roots = trusted_application_dirs() if directories is None else directories
    return any(is_under(path, root) for root in roots)
