#!/usr/bin/python3

from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "artwork" / "imagegen"
WALLPAPER_SOURCE = SOURCE_DIR / "bitmap-workbench-wallpaper-source.png"
CLEARED_SHIFT_SOURCE = SOURCE_DIR / "bitmap-workbench-cleared-shift-source.png"
ATLAS_SOURCE = SOURCE_DIR / "bitmap-desktop-object-atlas-source.png"
IMAGE_FALLBACK_SOURCE = SOURCE_DIR / "bitmap-image-fallback-source.png"
THEME_DIR = ROOT / "themes" / "one-bit-bureau"
BACKGROUND = THEME_DIR / "backgrounds" / "one-bit-bureau.png"
CLEARED_SHIFT_BACKGROUND = THEME_DIR / "backgrounds" / "one-bit-bureau-cleared-shift.png"
PREVIEW = THEME_DIR / "preview.png"
ASSET_DIR = ROOT / "components" / "desktop" / "assets"

OBJECTS = {
    0: "folder",
    1: "document",
    2: "link",
    3: "launcher",
    4: "volume",
    5: "archive",
    6: "trash",
}


def run(*args: str) -> None:
    subprocess.run(["magick", *args], check=True)


def render_wallpaper(source: Path, output: Path) -> None:
    run(
        str(source),
        "-colorspace",
        "Gray",
        "-threshold",
        "60%",
        "-colorspace",
        "sRGB",
        "+level-colors",
        "#171716,#f4f4f0",
        "-filter",
        "point",
        "-resize",
        "3840x2160!",
        str(output),
    )


def render_wallpapers() -> None:
    render_wallpaper(WALLPAPER_SOURCE, BACKGROUND)
    render_wallpaper(CLEARED_SHIFT_SOURCE, CLEARED_SHIFT_BACKGROUND)
    run(
        str(BACKGROUND),
        "-filter",
        "Lanczos",
        "-resize",
        "1600x900",
        str(PREVIEW),
    )


def render_object(source: Path, output: Path, selected: bool) -> None:
    colors = "#f4f4f0,#171716" if selected else "#171716,#f4f4f0"
    run(
        str(source),
        "-channel",
        "A",
        "-threshold",
        "50%",
        "+channel",
        "-channel",
        "RGB",
        "-colorspace",
        "Gray",
        "-threshold",
        "60%",
        "-colorspace",
        "sRGB",
        "+level-colors",
        colors,
        "+channel",
        "-trim",
        "+repage",
        "-filter",
        "point",
        "-resize",
        "56x56>",
        "-gravity",
        "center",
        "-background",
        "none",
        "-extent",
        "64x64",
        str(output),
    )


def render_objects() -> None:
    with tempfile.TemporaryDirectory(prefix="one-bit-bureau-atlas-") as temporary:
        temporary_dir = Path(temporary)
        run(
            str(ATLAS_SOURCE),
            "-crop",
            "4x2@",
            "+repage",
            str(temporary_dir / "cell-%d.png"),
        )
        for index, name in OBJECTS.items():
            source = temporary_dir / f"cell-{index}.png"
            render_object(source, ASSET_DIR / f"{name}.png", selected=False)
            render_object(source, ASSET_DIR / f"{name}-selected.png", selected=True)
    render_object(
        IMAGE_FALLBACK_SOURCE, ASSET_DIR / "image.png", selected=False
    )
    render_object(
        IMAGE_FALLBACK_SOURCE, ASSET_DIR / "image-selected.png", selected=True
    )


def main() -> None:
    if not all(
        source.is_file()
        for source in (
            WALLPAPER_SOURCE,
            CLEARED_SHIFT_SOURCE,
            ATLAS_SOURCE,
            IMAGE_FALLBACK_SOURCE,
        )
    ):
        raise SystemExit("Bitmap Workbench ImageGen sources are missing")
    render_wallpapers()
    render_objects()
    subprocess.run([sys.executable, str(ROOT / "artwork" / "render-crop-proof.py")], check=True)


if __name__ == "__main__":
    main()
