#!/usr/bin/python3

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artwork" / "imagegen" / "one-bit-bureau-brand-source.png"
TEXT_SOURCE = ROOT / "artwork" / "imagegen" / "one-bit-bureau-brand-text-source.png"
BRANDING_DIR = ROOT / "branding"
THEME_DIR = ROOT / "themes" / "one-bit-bureau"
PLUGIN_ICON = ROOT / "components" / "overview" / "assets" / "icon.png"


def require(command: str) -> str:
    path = shutil.which(command)
    if not path:
        raise SystemExit(f"{command} is required")
    return path


def run(*args: str, env: dict[str, str] | None = None) -> None:
    subprocess.run(args, check=True, env=env)


def find_omarchy_root() -> Path:
    configured = os.environ.get("OMARCHY_PATH", "")
    candidates = [Path(configured)] if configured else []
    candidates.append(ROOT.parent.parent)
    for candidate in candidates:
        if (candidate / "bin" / "omarchy-transcode-ascii").is_file():
            return candidate
    raise SystemExit("set OMARCHY_PATH to an Omarchy source checkout")


def main() -> None:
    magick = require("magick")
    if not SOURCE.is_file():
        raise SystemExit(f"missing source: {SOURCE}")
    if not TEXT_SOURCE.is_file():
        raise SystemExit(f"missing source: {TEXT_SOURCE}")
    omarchy_root = find_omarchy_root()
    BRANDING_DIR.mkdir(parents=True, exist_ok=True)
    PLUGIN_ICON.parent.mkdir(parents=True, exist_ok=True)

    run(
        magick,
        str(SOURCE),
        "-trim",
        "+repage",
        "-resize",
        "470x470",
        "-gravity",
        "center",
        "-background",
        "none",
        "-extent",
        "512x512",
        "-strip",
        str(BRANDING_DIR / "one-bit-bureau-mark.png"),
    )
    run(
        magick,
        str(SOURCE),
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
        str(PLUGIN_ICON),
    )
    run(
        magick,
        str(SOURCE),
        "-trim",
        "+repage",
        "-resize",
        "360x300",
        "-strip",
        str(THEME_DIR / "unlock.png"),
    )

    transcode = omarchy_root / "bin" / "omarchy-transcode-ascii"
    with tempfile.TemporaryDirectory(prefix="one-bit-bureau-ascii-") as temporary:
        flattened = Path(temporary) / "one-bit-bureau-mark-flat.png"
        run(
            magick,
            str(TEXT_SOURCE),
            "-trim",
            "+repage",
            "-resize",
            "470x470",
            "-gravity",
            "center",
            "-background",
            "none",
            "-extent",
            "512x512",
            "-background",
            "white",
            "-alpha",
            "remove",
            str(flattened),
        )
        run(
            "bash",
            str(transcode),
            str(flattened),
            str(BRANDING_DIR / "about.txt"),
            "--width",
            "48",
            "--height",
            "22",
            "--mode",
            "block",
        )
        run(
            "bash",
            str(transcode),
            str(flattened),
            str(BRANDING_DIR / "screensaver.txt"),
            "--width",
            "80",
            "--height",
            "26",
            "--mode",
            "block",
        )

    with tempfile.TemporaryDirectory(prefix="one-bit-bureau-branding-") as temporary:
        fake_imv = Path(temporary) / "imv"
        fake_imv.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
        fake_imv.chmod(0o755)
        portable_cp = Path(temporary) / "cp"
        portable_cp.write_text(
            "#!/bin/bash\n"
            "if [[ ${1:-} == '-t' ]]; then\n"
            "  target=$2\n"
            "  shift 2\n"
            "  exec /bin/cp \"$@\" \"$target\"\n"
            "fi\n"
            "exec /bin/cp \"$@\"\n",
            encoding="utf-8",
        )
        portable_cp.chmod(0o755)
        environment = dict(os.environ)
        environment["OMARCHY_PATH"] = str(omarchy_root)
        environment["PATH"] = f"{temporary}:{environment['PATH']}"
        run(
            "bash",
            str(omarchy_root / "bin" / "omarchy-plymouth-preview"),
            "#f4f4f0",
            "#171716",
            str(THEME_DIR / "unlock.png"),
            str(THEME_DIR / "preview-unlock.png"),
            env=environment,
        )

    print("Rendered One-Bit Bureau plugin, theme unlock, about, and screensaver branding")


if __name__ == "__main__":
    main()
