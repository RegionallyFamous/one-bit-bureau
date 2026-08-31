#!/usr/bin/python3

from base64 import b64encode
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
BACKGROUNDS = ROOT / "themes" / "one-bit-bureau" / "backgrounds"
PROOFS = {
    BACKGROUNDS / "one-bit-bureau.png": ROOT / "docs" / "wallpaper-crop-proof.png",
    BACKGROUNDS / "one-bit-bureau-cleared-shift.png": ROOT
    / "docs"
    / "wallpaper-cleared-shift-crop-proof.png",
}


def tile(encoded: str, x: int, y: int, width: int, height: int, label: str) -> str:
    return f'''<g transform="translate({x} {y})">
  <image href="data:image/png;base64,{encoded}" width="{width}" height="{height}" preserveAspectRatio="xMidYMid slice"/>
  <rect y="{height}" width="{width}" height="28" fill="#171716"/>
  <text x="{width // 2}" y="{height + 19}" text-anchor="middle" fill="#f4f4f0" font-family="DejaVu Sans Mono, monospace" font-size="12">{label}</text>
</g>'''


def render(wallpaper: Path, output: Path) -> None:
    encoded = b64encode(wallpaper.read_bytes()).decode("ascii")
    tiles = [
        tile(encoded, 20, 70, 560, 315, "16:9 MASTER"),
        tile(encoded, 610, 70, 560, 350, "16:10 CENTER CROP"),
        tile(encoded, 1200, 70, 560, 240, "21:9 CENTER CROP"),
        tile(encoded, 20, 480, 560, 158, "32:9 CENTER CROP"),
        tile(encoded, 610, 480, 560, 420, "4:3 CENTER CROP"),
    ]
    source = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1780" height="950" viewBox="0 0 1780 950">
  <rect width="1780" height="950" fill="#5b5b57"/>
  <rect width="1780" height="42" fill="#171716"/>
  <text x="20" y="27" fill="#f4f4f0" font-family="DejaVu Sans, sans-serif" font-size="14" font-weight="700">WALLPAPER CROP PROOF — NO SHELL / NOT RUNTIME</text>
  {''.join(tiles)}
</svg>'''
    with tempfile.NamedTemporaryFile("w", suffix=".svg", encoding="utf-8") as handle:
        handle.write(source)
        handle.flush()
        subprocess.run(
            ["magick", "-background", "none", handle.name, str(output)], check=True
        )


if __name__ == "__main__":
    for wallpaper, output in PROOFS.items():
        render(wallpaper, output)
