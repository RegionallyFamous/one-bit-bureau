#!/usr/bin/python3
"""Helpers shared by the One-Bit Bureau desktop scripts."""

from __future__ import annotations

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib
from pathlib import Path

from desktop_policy import require_desktop_directory, resolve_desktop_location


def desktop_dir() -> Path:
    # Keep every helper on the same xdg-user-dirs policy.  In particular,
    # XDG_DESKTOP_DIR="$HOME" means disabled and must never recreate ~/Desktop.
    return require_desktop_directory()


def desktop_location():
    return resolve_desktop_location()


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
