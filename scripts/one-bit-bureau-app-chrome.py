#!/usr/bin/env python3
"""Own the narrow, reversible One-Bit Bureau GTK3 preview only."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tempfile
from pathlib import Path


PLUGIN_ID = "io.github.regionallyfamous.one-bit-bureau"
THEME_NAME = "One-Bit-Bureau-GTK3"
MAX_BYTES = 1024 * 1024
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class ChromeError(RuntimeError):
    pass


def regular_file(path: Path, *, absent_ok: bool = False) -> bool:
    if not path.exists() and not path.is_symlink():
        return False if absent_ok else (_ for _ in ()).throw(ChromeError(f"missing {path}"))
    if path.is_symlink() or not path.is_file():
        raise ChromeError(f"unsafe non-regular file: {path}")
    if path.stat().st_size > MAX_BYTES:
        raise ChromeError(f"file exceeds {MAX_BYTES} bytes: {path}")
    return True


def sha256_file(path: Path) -> str:
    regular_file(path)
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_hash(path: Path) -> str:
    if path.is_symlink() or not path.is_dir():
        raise ChromeError(f"unsafe theme directory: {path}")
    entries: list[tuple[str, str]] = []
    for child in sorted(path.rglob("*")):
        if child.is_symlink():
            raise ChromeError(f"unsafe theme entry: {child}")
        if child.is_dir():
            continue
        if not child.is_file():
            raise ChromeError(f"unsafe theme entry: {child}")
        entries.append((str(child.relative_to(path)), sha256_file(child)))
    return hashlib.sha256(json.dumps(entries, separators=(",", ":")).encode()).hexdigest()


def atomic_write(path: Path, payload: bytes, mode: int = 0o600) -> None:
    parent = path.parent
    if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
        raise ChromeError(f"unsafe parent directory: {parent}")
    parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def safe_remove_tree(path: Path) -> None:
    if path.is_symlink() or not path.is_dir():
        raise ChromeError(f"unsafe theme directory: {path}")
    for child in path.rglob("*"):
        if child.is_symlink() or (not child.is_dir() and not child.is_file()):
            raise ChromeError(f"refusing to remove symlinked theme entry: {child}")
    shutil.rmtree(path)


def settings_with_theme(original: bytes) -> bytes:
    lines = original.decode("utf-8", "strict").splitlines(keepends=True)
    settings_start: int | None = None
    settings_end = len(lines)
    for index, line in enumerate(lines):
        if line.strip().lower() == "[settings]":
            settings_start = index
            for later in range(index + 1, len(lines)):
                if lines[later].lstrip().startswith("["):
                    settings_end = later
                    break
            break
    if settings_start is None:
        suffix = b"" if not original or original.endswith(b"\n") else b"\n"
        return original + suffix + b"[Settings]\ngtk-theme-name=One-Bit-Bureau-GTK3\n"
    for index in range(settings_start + 1, settings_end):
        stripped = lines[index].strip()
        if stripped.startswith("#") or stripped.startswith(";") or "=" not in stripped:
            continue
        key, _value = stripped.split("=", 1)
        if key.strip().lower() == "gtk-theme-name":
            newline = "\n" if lines[index].endswith("\n") else ""
            lines[index] = f"gtk-theme-name={THEME_NAME}{newline}"
            return "".join(lines).encode()
    lines.insert(settings_end, f"gtk-theme-name={THEME_NAME}\n")
    return "".join(lines).encode()


def settings_theme_name(payload: bytes) -> str | None:
    lines = payload.decode("utf-8", "strict").splitlines()
    in_settings = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_settings = stripped.lower() == "[settings]"
            continue
        if not in_settings or stripped.startswith(("#", ";")) or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        if key.strip().lower() == "gtk-theme-name":
            return value.strip()
    return None


def paths(plugin_dir: Path) -> dict[str, Path]:
    home = Path(os.environ["HOME"])
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    data_home = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    # This must match setup/uninstall exactly. XDG_STATE_HOME is intentionally
    # not honored here because Omarchy's plugin ownership records have one
    # stable, user-scoped location under HOME.
    state_dir = home / ".local/state/omarchy/plugins" / PLUGIN_ID
    return {
        "settings": config_home / "gtk-3.0/settings.ini",
        "theme": data_home / "themes" / THEME_NAME,
        "state": state_dir / "app-chrome-state.json",
        "backup": state_dir / "backups/app-chrome-settings.ini",
        "index_template": plugin_dir / "app-chrome/index.theme",
        "template": plugin_dir / "app-chrome/gtk-3.0/gtk.css",
    }


def load_state(state_path: Path) -> dict | None:
    if not state_path.exists() and not state_path.is_symlink():
        return None
    regular_file(state_path)
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise ChromeError(f"corrupt app-chrome ownership record: {error}") from error
    required = {
        "schemaVersion": 1,
        "mechanism": "gtk3-user-theme",
        "themeName": THEME_NAME,
    }
    if not isinstance(state, dict) or any(state.get(key) != value for key, value in required.items()):
        raise ChromeError("invalid app-chrome ownership record")
    for key in ("settingsPath", "themePath", "settingsInstalledHash", "themeInstalledHash"):
        if not isinstance(state.get(key), str) or not state[key]:
            raise ChromeError("invalid app-chrome ownership record")
    if not isinstance(state.get("previousSettingsHash"), str):
        raise ChromeError("invalid app-chrome ownership record")
    if not isinstance(state.get("previousSettingsPresent"), bool):
        raise ChromeError("invalid app-chrome ownership record")
    return state


def write_state(state_path: Path, state: dict) -> None:
    atomic_write(state_path, (json.dumps(state, indent=2, sort_keys=True) + "\n").encode())


def ensure_theme(index_template: Path, template: Path, destination: Path) -> str:
    regular_file(index_template)
    regular_file(template)
    if destination.exists() or destination.is_symlink():
        raise ChromeError(f"refusing to replace existing GTK theme directory: {destination}")
    created = False
    try:
        destination.mkdir(parents=True, mode=0o700)
        created = True
        atomic_write(destination / "index.theme", index_template.read_bytes(), 0o600)
        target = destination / "gtk-3.0/gtk.css"
        target.parent.mkdir(mode=0o700)
        atomic_write(target, template.read_bytes(), 0o600)
        return tree_hash(destination)
    except BaseException:
        if created and destination.exists() and not destination.is_symlink():
            safe_remove_tree(destination)
        raise


def preview(plugin_dir: Path) -> int:
    location = paths(plugin_dir)
    try:
        regular_file(location["index_template"])
        regular_file(location["template"])
    except ChromeError as error:
        print(f"One-Bit Bureau GTK app-chrome preview is unavailable: {error}")
        return 1
    print("GTK3 app-chrome preview: available (opt-in; no changes made).")
    print(f"It would install the user-only theme {THEME_NAME} and set gtk-theme-name in GTK3 settings.")
    print("GTK4/libadwaita is intentionally unsupported and unchanged. Use `one-bit-bureau app-chrome on` to opt in.")
    return 0


def status(plugin_dir: Path) -> int:
    location = paths(plugin_dir)
    state = load_state(location["state"])
    if state is None:
        print("GTK3 app-chrome preview: off")
        print("GTK4/libadwaita: unsupported and unchanged")
        return 0
    validate_state_for_off(location, state)
    settings = Path(state["settingsPath"])
    theme = Path(state["themePath"])
    settings_matches = settings.exists() and not settings.is_symlink() and sha256_file(settings) == state["settingsInstalledHash"]
    theme_matches = theme.exists() and not theme.is_symlink() and tree_hash(theme) == state["themeInstalledHash"]
    print("GTK3 app-chrome preview: on")
    print(f"settings: {'owned' if settings_matches else 'modified or missing'}")
    print(f"theme: {'owned' if theme_matches else 'modified or missing'}")
    print("GTK4/libadwaita: unsupported and unchanged")
    return 0


def validate_state_for_off(location: dict[str, Path], state: dict) -> None:
    if Path(state["settingsPath"]) != location["settings"] or Path(state["themePath"]) != location["theme"]:
        raise ChromeError("app-chrome ownership paths do not match this user profile")
    for key in ("settingsInstalledHash", "themeInstalledHash"):
        if not SHA256.fullmatch(state[key]):
            raise ChromeError("app-chrome ownership record has an invalid installed hash")
    backup = location["backup"]
    if state["previousSettingsPresent"]:
        if not SHA256.fullmatch(state["previousSettingsHash"]):
            raise ChromeError("app-chrome ownership record has an invalid previous-settings hash")
        regular_file(backup)
        if sha256_file(backup) != state["previousSettingsHash"]:
            raise ChromeError("app-chrome settings backup no longer matches its ownership record")
    elif state["previousSettingsHash"] != "":
        raise ChromeError("app-chrome ownership record has an unexpected previous-settings hash")
    elif backup.exists() or backup.is_symlink():
        raise ChromeError("app-chrome ownership record has an unexpected settings backup")


def turn_on(plugin_dir: Path) -> int:
    location = paths(plugin_dir)
    if load_state(location["state"]) is not None:
        raise ChromeError("GTK3 app-chrome preview is already on; run `one-bit-bureau app-chrome off` first")
    if location["backup"].exists() or location["backup"].is_symlink():
        raise ChromeError("refusing to replace an unclaimed app-chrome settings backup")
    settings = location["settings"]
    backup_created = False
    if settings.exists() or settings.is_symlink():
        regular_file(settings)
        previous = settings.read_bytes()
        previous_present = True
    else:
        previous = b""
        previous_present = False
    installed = settings_with_theme(previous)
    settings_written = False
    theme_hash = ""
    installed_hash = hashlib.sha256(installed).hexdigest()
    try:
        if previous_present:
            atomic_write(location["backup"], previous)
            backup_created = True
        theme_hash = ensure_theme(location["index_template"], location["template"], location["theme"])
        atomic_write(settings, installed)
        settings_written = True
        state = {
            "schemaVersion": 1,
            "mechanism": "gtk3-user-theme",
            "themeName": THEME_NAME,
            "settingsPath": str(settings),
            "themePath": str(location["theme"]),
            "previousSettingsPresent": previous_present,
            "previousSettingsHash": hashlib.sha256(previous).hexdigest() if previous_present else "",
            "settingsInstalledHash": installed_hash,
            "themeInstalledHash": theme_hash,
        }
        write_state(location["state"], state)
    except BaseException:
        if location["theme"].exists() and not location["theme"].is_symlink() and theme_hash and tree_hash(location["theme"]) == theme_hash:
            safe_remove_tree(location["theme"])
        if settings_written and settings.exists() and not settings.is_symlink() and sha256_file(settings) == installed_hash and previous_present:
            atomic_write(settings, previous)
        elif settings_written and settings.exists() and not settings.is_symlink() and sha256_file(settings) == installed_hash:
            settings.unlink()
        if backup_created and location["backup"].exists() and not location["backup"].is_symlink():
            location["backup"].unlink()
        raise
    print("GTK3 app-chrome preview enabled. Reopen GTK3 applications to see it; GTK4/libadwaita is unchanged.")
    return 0


def turn_off(plugin_dir: Path) -> int:
    location = paths(plugin_dir)
    state = load_state(location["state"])
    if state is None:
        print("GTK3 app-chrome preview is already off.")
        return 0
    validate_state_for_off(location, state)
    expected_settings = location["settings"]
    expected_theme = location["theme"]
    settings_restored = False
    settings = expected_settings
    settings_matches = settings.exists() and not settings.is_symlink() and sha256_file(settings) == state["settingsInstalledHash"]
    if settings.exists() and not settings.is_symlink() and not settings_matches:
        if settings_theme_name(settings.read_bytes()) == THEME_NAME:
            raise ChromeError("GTK settings changed while still selecting the One-Bit Bureau theme; ownership was retained and nothing was removed")
    elif settings.is_symlink():
        raise ChromeError("GTK settings became a symlink; ownership was retained and nothing was removed")
    if settings_matches:
        if state["previousSettingsPresent"]:
            backup = location["backup"]
            atomic_write(settings, backup.read_bytes())
        else:
            settings.unlink()
        settings_restored = True
    theme_removed = False
    theme = expected_theme
    if theme.exists() and not theme.is_symlink() and tree_hash(theme) == state["themeInstalledHash"]:
        safe_remove_tree(theme)
        theme_removed = True
    elif theme.is_symlink():
        print(f"preserved modified GTK theme at {theme}", file=sys.stderr)
    if not settings_restored:
        print(f"preserved modified GTK settings at {settings}", file=sys.stderr)
    if not theme_removed and theme.exists():
        print(f"preserved modified GTK theme at {theme}", file=sys.stderr)
    for candidate in (location["state"], location["backup"]):
        if candidate.exists() and not candidate.is_symlink():
            candidate.unlink()
    print("GTK3 app-chrome preview disabled; owned settings were restored immediately where unchanged.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("command", choices=("preview", "on", "off", "status"))
    parser.add_argument("--plugin-dir", required=True)
    arguments = parser.parse_args()
    candidate = Path(arguments.plugin_dir)
    if candidate.is_symlink() or not candidate.is_dir():
        raise ChromeError(f"unsafe plugin directory: {candidate}")
    plugin_dir = candidate.resolve()
    if arguments.command == "preview":
        return preview(plugin_dir)
    if arguments.command == "status":
        return status(plugin_dir)
    if arguments.command == "on":
        return turn_on(plugin_dir)
    return turn_off(plugin_dir)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ChromeError as error:
        print(f"one-bit-bureau app-chrome: {error}", file=sys.stderr)
        raise SystemExit(1)
