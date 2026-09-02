#!/usr/bin/python3
"""Own the narrow, reversible One-Bit Bureau GTK3 preview only."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import NamedTuple


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import one_bit_bureau_secure_io as secure  # noqa: E402


PLUGIN_ID = "io.github.regionallyfamous.one-bit-bureau"
THEME_NAME = "One-Bit-Bureau-GTK3"
STATE_NAME = "app-chrome-state.json"
BACKUP_NAME = "app-chrome-settings.ini"
SETTINGS_NAME = "settings.ini"
STATE_LIMIT = 16 * 1024
MAX_BYTES = 1024 * 1024
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class ChromeError(RuntimeError):
    pass


class LoadedState(NamedTuple):
    value: dict[str, object]
    record_hash: str


def paths(plugin_dir: Path) -> dict[str, Path]:
    home = Path(os.environ["HOME"])
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    data_home = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    state_dir = home / ".local/state/omarchy/plugins" / PLUGIN_ID
    return {
        "settings": config_home / "gtk-3.0/settings.ini",
        "theme": data_home / "themes" / THEME_NAME,
        "state": state_dir / STATE_NAME,
        "backup": state_dir / "backups" / BACKUP_NAME,
        "index_template": plugin_dir / "app-chrome/index.theme",
        "template": plugin_dir / "app-chrome/gtk-3.0/gtk.css",
    }


def _config_gtk_directory(*, create: bool) -> int:
    location = paths(Path("/unused"))
    config_fd = secure.open_user_directory(
        location["settings"].parent.parent,
        create=create,
    )
    try:
        return secure.open_child_directory(
            config_fd,
            "gtk-3.0",
            create=create,
            private=True,
        )
    finally:
        os.close(config_fd)


def _themes_directory(*, create: bool) -> int:
    location = paths(Path("/unused"))
    return secure.open_user_directory(
        location["theme"].parent,
        create=create,
    )


def _state_directory(*, create: bool) -> int:
    return secure.open_install_state_directory(create=create)


def _backup_directory(state_fd: int, *, create: bool) -> int:
    return secure.open_child_directory(
        state_fd,
        "backups",
        create=create,
        private=True,
    )


def _read_plugin_templates(plugin_dir: Path) -> tuple[bytes, bytes]:
    plugin_fd = secure.open_owned_directory(plugin_dir)
    try:
        app_chrome_fd = secure.open_child_directory(
            plugin_fd,
            "app-chrome",
            create=False,
        )
    finally:
        os.close(plugin_fd)
    try:
        index = secure.read_bytes_at(
            app_chrome_fd,
            "index.theme",
            MAX_BYTES,
            label="GTK theme metadata template",
        )
        gtk_fd = secure.open_child_directory(
            app_chrome_fd,
            "gtk-3.0",
            create=False,
        )
    finally:
        os.close(app_chrome_fd)
    try:
        css = secure.read_bytes_at(
            gtk_fd,
            "gtk.css",
            MAX_BYTES,
            label="GTK theme CSS template",
        )
    finally:
        os.close(gtk_fd)
    assert index is not None and css is not None
    if len(index) + len(css) > MAX_BYTES:
        raise ChromeError("GTK template tree exceeds its total-byte ceiling")
    return index, css


def _read_settings(*, missing_ok: bool) -> bytes | None:
    try:
        directory_fd = _config_gtk_directory(create=False)
    except FileNotFoundError:
        if missing_ok:
            return None
        raise ChromeError("GTK settings directory is missing") from None
    try:
        return secure.read_bytes_at(
            directory_fd,
            SETTINGS_NAME,
            MAX_BYTES,
            missing_ok=missing_ok,
            label="GTK settings",
        )
    finally:
        os.close(directory_fd)


def _write_settings(
    payload: bytes,
    *,
    expected_hash: str | None = None,
    require_absent: bool = False,
) -> str:
    directory_fd = _config_gtk_directory(create=True)
    try:
        return secure.atomic_write_at(
            directory_fd,
            SETTINGS_NAME,
            payload,
            mode=0o600,
            byte_limit=MAX_BYTES,
            expected_hash=expected_hash,
            require_absent=require_absent,
            label="GTK settings",
        )
    finally:
        os.close(directory_fd)


def _remove_settings(expected_hash: str) -> bool:
    try:
        directory_fd = _config_gtk_directory(create=False)
    except FileNotFoundError:
        return False
    try:
        return secure.remove_file_at(
            directory_fd,
            SETTINGS_NAME,
            MAX_BYTES,
            expected_hash=expected_hash,
            missing_ok=True,
            label="GTK settings",
        )
    finally:
        os.close(directory_fd)


def _read_backup(*, missing_ok: bool) -> bytes | None:
    try:
        state_fd = _state_directory(create=False)
    except FileNotFoundError:
        if missing_ok:
            return None
        raise ChromeError("app-chrome state directory is missing") from None
    try:
        try:
            backup_fd = _backup_directory(state_fd, create=False)
        except FileNotFoundError:
            if missing_ok:
                return None
            raise ChromeError("app-chrome backup directory is missing") from None
    finally:
        os.close(state_fd)
    try:
        return secure.read_bytes_at(
            backup_fd,
            BACKUP_NAME,
            MAX_BYTES,
            missing_ok=missing_ok,
            label="GTK settings backup",
        )
    finally:
        os.close(backup_fd)


def _write_backup(payload: bytes) -> str:
    state_fd = _state_directory(create=True)
    try:
        backup_fd = _backup_directory(state_fd, create=True)
    finally:
        os.close(state_fd)
    try:
        return secure.atomic_write_at(
            backup_fd,
            BACKUP_NAME,
            payload,
            mode=0o600,
            byte_limit=MAX_BYTES,
            require_absent=True,
            label="GTK settings backup",
        )
    finally:
        os.close(backup_fd)


def _remove_backup(expected_hash: str) -> bool:
    try:
        state_fd = _state_directory(create=False)
    except FileNotFoundError:
        return False
    try:
        try:
            backup_fd = _backup_directory(state_fd, create=False)
        except FileNotFoundError:
            return False
    finally:
        os.close(state_fd)
    try:
        return secure.remove_file_at(
            backup_fd,
            BACKUP_NAME,
            MAX_BYTES,
            expected_hash=expected_hash,
            missing_ok=True,
            label="GTK settings backup",
        )
    finally:
        os.close(backup_fd)


def load_state(_state_path: Path | None = None) -> LoadedState | None:
    try:
        state_fd = _state_directory(create=False)
    except FileNotFoundError:
        return None
    try:
        payload = secure.read_bytes_at(
            state_fd,
            STATE_NAME,
            STATE_LIMIT,
            missing_ok=True,
            label="app-chrome ownership record",
        )
    finally:
        os.close(state_fd)
    if payload is None:
        return None
    value = secure.parse_json(payload, label="app-chrome ownership record")
    if not isinstance(value, dict):
        raise ChromeError("invalid app-chrome ownership record")
    required = {
        "schemaVersion": 1,
        "mechanism": "gtk3-user-theme",
        "themeName": THEME_NAME,
    }
    if any(value.get(key) != expected for key, expected in required.items()):
        raise ChromeError("invalid app-chrome ownership record")
    for key in ("settingsPath", "themePath", "settingsInstalledHash", "themeInstalledHash"):
        if not isinstance(value.get(key), str) or not value[key]:
            raise ChromeError("invalid app-chrome ownership record")
    if not isinstance(value.get("previousSettingsHash"), str):
        raise ChromeError("invalid app-chrome ownership record")
    if not isinstance(value.get("previousSettingsPresent"), bool):
        raise ChromeError("invalid app-chrome ownership record")
    return LoadedState(value=value, record_hash=secure.hash_bytes(payload))


def write_state(_state_path: Path | None, state: dict[str, object]) -> str:
    payload = secure.encode_json(state, STATE_LIMIT)
    state_fd = _state_directory(create=True)
    try:
        return secure.atomic_write_at(
            state_fd,
            STATE_NAME,
            payload,
            mode=0o600,
            byte_limit=STATE_LIMIT,
            require_absent=True,
            label="app-chrome ownership record",
        )
    finally:
        os.close(state_fd)


def _remove_state(expected_hash: str) -> bool:
    state_fd = _state_directory(create=False)
    try:
        return secure.remove_file_at(
            state_fd,
            STATE_NAME,
            STATE_LIMIT,
            expected_hash=expected_hash,
            label="app-chrome ownership record",
        )
    finally:
        os.close(state_fd)


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
        result = original + suffix + b"[Settings]\ngtk-theme-name=One-Bit-Bureau-GTK3\n"
    else:
        result = b""
        for index in range(settings_start + 1, settings_end):
            stripped = lines[index].strip()
            if stripped.startswith(("#", ";")) or "=" not in stripped:
                continue
            key, _value = stripped.split("=", 1)
            if key.strip().lower() == "gtk-theme-name":
                newline = "\n" if lines[index].endswith("\n") else ""
                lines[index] = f"gtk-theme-name={THEME_NAME}{newline}"
                result = "".join(lines).encode()
                break
        if not result:
            lines.insert(settings_end, f"gtk-theme-name={THEME_NAME}\n")
            result = "".join(lines).encode()
    if len(result) > MAX_BYTES:
        raise ChromeError("updated GTK settings exceed the byte ceiling")
    return result


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


def ensure_theme(plugin_dir: Path) -> str:
    index, css = _read_plugin_templates(plugin_dir)
    themes_fd = _themes_directory(create=True)
    theme_fd = -1
    identity: tuple[int, int] | None = None
    try:
        theme_fd = secure.create_directory_at(themes_fd, THEME_NAME)
        metadata = os.fstat(theme_fd)
        identity = (metadata.st_dev, metadata.st_ino)
        secure.atomic_write_at(
            theme_fd,
            "index.theme",
            index,
            mode=0o600,
            byte_limit=MAX_BYTES,
            require_absent=True,
            label="GTK theme metadata",
        )
        gtk_fd = secure.create_directory_at(theme_fd, "gtk-3.0")
        try:
            secure.atomic_write_at(
                gtk_fd,
                "gtk.css",
                css,
                mode=0o600,
                byte_limit=MAX_BYTES,
                require_absent=True,
                label="GTK theme CSS",
            )
        finally:
            os.close(gtk_fd)
        os.fsync(theme_fd)
        return secure.tree_hash_fd(theme_fd)
    except BaseException:
        if theme_fd >= 0:
            os.close(theme_fd)
            theme_fd = -1
        if identity is not None:
            secure.remove_tree_at(themes_fd, THEME_NAME, expected_identity=identity)
        raise
    finally:
        if theme_fd >= 0:
            os.close(theme_fd)
        os.close(themes_fd)


def _theme_hash(*, missing_ok: bool) -> str | None:
    try:
        themes_fd = _themes_directory(create=False)
    except FileNotFoundError:
        if missing_ok:
            return None
        raise ChromeError("GTK themes directory is missing") from None
    try:
        try:
            return secure.tree_hash_at(themes_fd, THEME_NAME)
        except FileNotFoundError:
            if missing_ok:
                return None
            raise ChromeError("GTK preview theme is missing") from None
    finally:
        os.close(themes_fd)


def _remove_theme(expected_hash: str) -> bool:
    try:
        themes_fd = _themes_directory(create=False)
    except FileNotFoundError:
        return False
    try:
        return secure.remove_tree_at(
            themes_fd,
            THEME_NAME,
            expected_hash=expected_hash,
        )
    finally:
        os.close(themes_fd)


def validate_state_for_off(
    location: dict[str, Path],
    state: dict[str, object],
) -> None:
    if Path(str(state["settingsPath"])) != location["settings"] or Path(
        str(state["themePath"])
    ) != location["theme"]:
        raise ChromeError("app-chrome ownership paths do not match this user profile")
    for key in ("settingsInstalledHash", "themeInstalledHash"):
        if not SHA256.fullmatch(str(state[key])):
            raise ChromeError("app-chrome ownership record has an invalid installed hash")
    backup = _read_backup(missing_ok=True)
    if state["previousSettingsPresent"]:
        previous_hash = str(state["previousSettingsHash"])
        if not SHA256.fullmatch(previous_hash):
            raise ChromeError("app-chrome ownership record has an invalid previous-settings hash")
        if backup is None:
            raise ChromeError("app-chrome settings backup is missing")
        if secure.hash_bytes(backup) != previous_hash:
            raise ChromeError("app-chrome settings backup no longer matches its ownership record")
    elif state["previousSettingsHash"] != "":
        raise ChromeError("app-chrome ownership record has an unexpected previous-settings hash")
    elif backup is not None:
        raise ChromeError("app-chrome ownership record has an unexpected settings backup")


def preview(plugin_dir: Path) -> int:
    try:
        _read_plugin_templates(plugin_dir)
    except (ChromeError, secure.SecureIOError, FileNotFoundError) as error:
        print(f"One-Bit Bureau GTK app-chrome preview is unavailable: {error}")
        return 1
    print("GTK3 app-chrome preview: available (opt-in; no changes made).")
    print(f"It would install the user-only theme {THEME_NAME} and set gtk-theme-name in GTK3 settings.")
    print("GTK4/libadwaita is intentionally unsupported and unchanged. Use `one-bit-bureau app-chrome on` to opt in.")
    return 0


def status(plugin_dir: Path) -> int:
    loaded = load_state()
    if loaded is None:
        print("GTK3 app-chrome preview: off")
        print("GTK4/libadwaita: unsupported and unchanged")
        return 0
    location = paths(plugin_dir)
    state = loaded.value
    validate_state_for_off(location, state)
    settings = _read_settings(missing_ok=True)
    settings_matches = settings is not None and secure.hash_bytes(settings) == state["settingsInstalledHash"]
    try:
        current_theme_hash = _theme_hash(missing_ok=True)
    except secure.SecureIOError:
        current_theme_hash = None
    theme_matches = current_theme_hash == state["themeInstalledHash"]
    print("GTK3 app-chrome preview: on")
    print(f"settings: {'owned' if settings_matches else 'modified or missing'}")
    print(f"theme: {'owned' if theme_matches else 'modified or missing'}")
    print("GTK4/libadwaita: unsupported and unchanged")
    return 0


def turn_on(plugin_dir: Path) -> int:
    location = paths(plugin_dir)
    if load_state() is not None:
        raise ChromeError("GTK3 app-chrome preview is already on; run `one-bit-bureau app-chrome off` first")
    if _read_backup(missing_ok=True) is not None:
        raise ChromeError("refusing to replace an unclaimed app-chrome settings backup")
    previous = _read_settings(missing_ok=True)
    previous_present = previous is not None
    previous = previous or b""
    installed = settings_with_theme(previous)
    previous_hash = secure.hash_bytes(previous) if previous_present else ""
    installed_hash = secure.hash_bytes(installed)
    backup_created = False
    settings_written = False
    theme_hash = ""
    try:
        if previous_present:
            _write_backup(previous)
            backup_created = True
        theme_hash = ensure_theme(plugin_dir)
        _write_settings(
            installed,
            expected_hash=previous_hash if previous_present else None,
            require_absent=not previous_present,
        )
        settings_written = True
        write_state(
            None,
            {
                "schemaVersion": 1,
                "mechanism": "gtk3-user-theme",
                "themeName": THEME_NAME,
                "settingsPath": str(location["settings"]),
                "themePath": str(location["theme"]),
                "previousSettingsPresent": previous_present,
                "previousSettingsHash": previous_hash,
                "settingsInstalledHash": installed_hash,
                "themeInstalledHash": theme_hash,
            },
        )
    except BaseException:
        if theme_hash:
            _remove_theme(theme_hash)
        if settings_written:
            if previous_present:
                _write_settings(previous, expected_hash=installed_hash)
            else:
                _remove_settings(installed_hash)
        if backup_created:
            _remove_backup(previous_hash)
        raise
    print("GTK3 app-chrome preview enabled. Reopen GTK3 applications to see it; GTK4/libadwaita is unchanged.")
    return 0


def turn_off(plugin_dir: Path) -> int:
    loaded = load_state()
    if loaded is None:
        print("GTK3 app-chrome preview is already off.")
        return 0
    location = paths(plugin_dir)
    state = loaded.value
    validate_state_for_off(location, state)
    settings = _read_settings(missing_ok=True)
    installed_settings_hash = str(state["settingsInstalledHash"])
    settings_matches = settings is not None and secure.hash_bytes(settings) == installed_settings_hash
    if settings is not None and not settings_matches and settings_theme_name(settings) == THEME_NAME:
        raise ChromeError("GTK settings changed while still selecting the One-Bit Bureau theme; ownership was retained and nothing was removed")

    settings_restored = False
    if settings_matches:
        if state["previousSettingsPresent"]:
            backup = _read_backup(missing_ok=False)
            assert backup is not None
            _write_settings(backup, expected_hash=installed_settings_hash)
        else:
            _remove_settings(installed_settings_hash)
        settings_restored = True

    try:
        theme_removed = _remove_theme(str(state["themeInstalledHash"]))
    except secure.SecureIOError:
        theme_removed = False
    if not settings_restored:
        print(f"preserved modified GTK settings at {location['settings']}", file=sys.stderr)
    if not theme_removed:
        print(f"preserved modified GTK theme at {location['theme']}", file=sys.stderr)

    if state["previousSettingsPresent"]:
        if not _remove_backup(str(state["previousSettingsHash"])):
            raise ChromeError("could not safely remove the owned GTK settings backup")
    if not _remove_state(loaded.record_hash):
        raise ChromeError("could not safely remove the app-chrome ownership record")
    print("GTK3 app-chrome preview disabled; owned settings were restored immediately where unchanged.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("command", choices=("preview", "on", "off", "status"))
    parser.add_argument("--plugin-dir", required=True)
    arguments = parser.parse_args()
    plugin_dir = Path(os.path.normpath(arguments.plugin_dir))
    if not plugin_dir.is_absolute():
        raise ChromeError("plugin directory must be absolute")
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
    except (ChromeError, secure.SecureIOError, FileNotFoundError) as error:
        print(f"one-bit-bureau app-chrome: {error}", file=sys.stderr)
        raise SystemExit(1)
