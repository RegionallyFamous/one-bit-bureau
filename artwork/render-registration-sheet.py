#!/usr/bin/python3

from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
ARTWORK = ROOT / "artwork"
THEME = ROOT / "themes" / "alumina-raster"
BACKGROUND = THEME / "backgrounds" / "alumina-raster.png"
PREVIEW = THEME / "preview.png"
SVG = ARTWORK / "registration-sheet-01.svg"

MASK = (
    "0000000000",
    "0000000000",
    "0000000000",
    "0010100010",
    "0100000101",
    "0001001000",
    "0100010100",
    "0001001010",
    "0100010101",
    "0010101000",
    "0100000001",
    "0000100100",
    "0100010000",
    "0000101000",
    "0100010100",
    "0001001010",
    "0100100001",
    "1010001000",
    "0000100010",
    "0010000100",
    "0101000010",
    "0010100100",
    "0100001010",
    "0001010001",
    "0010001000",
    "0101010100",
    "1000101000",
    "0010010100",
    "0001000001",
    "0010101000",
    "0001000001",
    "0010010010",
    "0101000001",
    "1000100000",
    "0001010010",
    "0000101001",
    "1000000100",
    "0001001001",
    "0010010010",
    "0100100101",
    "1001010000",
    "0100000101",
    "0000000000",
    "0000000000",
    "0000000000",
)


def svg_source() -> str:
    rects = [
        '<rect width="3840" height="2160" fill="#f1f0e8"/>',
        '<rect x="2688" width="24" height="2160" fill="#1c1c1a"/>',
    ]
    for row, occupancy in enumerate(MASK):
        for column, mark in enumerate(occupancy):
            if mark == "1":
                rects.append(
                    f'<rect x="{2784 + column * 48}" y="{row * 48}" '
                    'width="48" height="48" fill="#1c1c1a"/>'
                )
    body = "\n  ".join(rects)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="2160" '
        'viewBox="0 0 3840 2160" shape-rendering="crispEdges">\n'
        f'  {body}\n'
        '</svg>\n'
    )


def run() -> None:
    (THEME / "backgrounds").mkdir(parents=True, exist_ok=True)
    SVG.write_text(svg_source(), encoding="utf-8")
    subprocess.run(
        ["magick", str(SVG), "-alpha", "off", "-colors", "2", "PNG24:" + str(BACKGROUND)],
        check=True,
    )
    subprocess.run(
        [
            "magick",
            str(BACKGROUND),
            "-filter",
            "point",
            "-resize",
            "1600x900!",
            "PNG24:" + str(PREVIEW),
        ],
        check=True,
    )


if __name__ == "__main__":
    run()
