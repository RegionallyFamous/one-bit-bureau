#!/usr/bin/python3

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "artwork" / "imagegen" / "app-icons"
OUTPUT_DIR = ROOT / "components" / "dock" / "assets" / "app-icons"
CONTACT_SHEET = ROOT / "docs" / "app-icon-pack.png"
ROLES = (
    "files",
    "terminal",
    "browser",
    "code",
    "mail",
    "chat",
    "music",
    "video",
    "calendar",
    "settings",
    "games",
    "notes",
)


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def output(command: str, *args: str) -> str:
    return subprocess.run(
        (command, *args), check=True, capture_output=True, text=True
    ).stdout.strip()


def require(command: str) -> str:
    path = shutil.which(command)
    if not path:
        raise SystemExit(f"{command} is required")
    return path


def render_icon(magick: str, identify: str, role: str) -> Path:
    source = SOURCE_DIR / f"{role}-source.png"
    if not source.is_file():
        raise SystemExit(f"missing source: {source}")
    geometry = output(identify, "-ping", "-format", "%wx%h", str(source))
    channels = output(identify, "-ping", "-format", "%[channels]", str(source))
    if geometry != "1254x1254" or "a" not in channels.lower():
        raise SystemExit(f"unexpected source format for {source}: {geometry} {channels}")

    destination = OUTPUT_DIR / f"{role}.png"
    run(
        magick,
        str(source),
        "-trim",
        "+repage",
        "-resize",
        "230x230",
        "-gravity",
        "center",
        "-background",
        "none",
        "-extent",
        "256x256",
        "-strip",
        str(destination),
    )
    return destination


def contact_sheet(magick: str, icons: list[Path]) -> None:
    font = ""
    fc_match = shutil.which("fc-match")
    if fc_match:
        font = output(fc_match, "monospace", "-f", "%{file}").splitlines()[0]
    command = [
        magick,
        "montage",
        "-background",
        "#d8d4c8",
        "-fill",
        "#171716",
        "-pointsize",
        "18",
    ]
    if font:
        command.extend(("-font", font))
    for icon in icons:
        command.extend(("-label", icon.stem, str(icon)))
    command.extend(("-tile", "4x3", "-geometry", "164x188+14+14", str(CONTACT_SHEET)))
    run(*command)


def main() -> None:
    magick = require("magick")
    identify = require("identify")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    icons = [render_icon(magick, identify, role) for role in ROLES]
    contact_sheet(magick, icons)
    print(f"Rendered {len(icons)} Paper Jam icons and {CONTACT_SHEET}")


if __name__ == "__main__":
    main()
