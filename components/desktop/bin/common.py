#!/usr/bin/python3
"""Helpers shared by the desktop-icons plugin scripts (desktop-index, add-to-desktop)."""

from __future__ import annotations

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib
from pathlib import Path


def desktop_dir() -> Path:
    special = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP)
    path = Path(special) if special else Path.home() / "Desktop"
    if path.resolve() == Path.home().resolve():
        path = Path.home() / "Desktop"
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def unique_dest(directory: Path, name: str) -> Path:
    candidate = directory / name
    if not candidate.exists():
        return candidate
    stem = Path(name).stem
    suffix = Path(name).suffix
    if name.endswith(suffix) and suffix:
        base = name[: -len(suffix)]
    else:
        base = name
        suffix = ""
    index = 2
    while True:
        candidate = directory / f"{base} {index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def guess_icon(path: Path) -> str:
    if path.is_dir():
        return "folder"
    content_type, _uncertain = Gio.content_type_guess(str(path), None)
    icon = Gio.content_type_get_generic_icon_name(content_type) if content_type else None
    return icon or "text-x-generic"
