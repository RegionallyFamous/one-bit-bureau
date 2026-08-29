#!/usr/bin/python3

from base64 import b64encode
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
WALLPAPER = ROOT / "themes" / "paper-jam-84" / "backgrounds" / "paper-jam-84.png"
OUTPUT = ROOT / "docs" / "wallpaper-crop-proof.png"


def render() -> None:
    encoded = b64encode(WALLPAPER.read_bytes()).decode("ascii")
    source = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1220" viewBox="0 0 1600 1220">
  <rect width="1600" height="1220" fill="#5b5b57"/>
  <rect width="1600" height="42" fill="#171716"/>
  <text x="20" y="27" fill="#f4f4f0" font-family="DejaVu Sans, sans-serif" font-size="14" font-weight="700">WALLPAPER CROP PROOF — NO SHELL / NOT RUNTIME</text>
  <g transform="translate(20 70)"><image href="data:image/png;base64,{encoded}" width="760" height="427" preserveAspectRatio="xMidYMid slice"/><rect y="427" width="760" height="28" fill="#171716"/><text x="380" y="446" text-anchor="middle" fill="#f4f4f0" font-family="DejaVu Sans Mono, monospace" font-size="12">16:9 MASTER</text></g>
  <g transform="translate(820 70)"><image href="data:image/png;base64,{encoded}" width="760" height="475" preserveAspectRatio="xMidYMid slice"/><rect y="475" width="760" height="28" fill="#171716"/><text x="380" y="494" text-anchor="middle" fill="#f4f4f0" font-family="DejaVu Sans Mono, monospace" font-size="12">16:10 CENTER CROP</text></g>
  <g transform="translate(20 610)"><image href="data:image/png;base64,{encoded}" width="760" height="326" preserveAspectRatio="xMidYMid slice"/><rect y="326" width="760" height="28" fill="#171716"/><text x="380" y="345" text-anchor="middle" fill="#f4f4f0" font-family="DejaVu Sans Mono, monospace" font-size="12">21:9 CENTER CROP</text></g>
  <g transform="translate(820 610)"><image href="data:image/png;base64,{encoded}" width="760" height="570" preserveAspectRatio="xMidYMid slice"/><rect y="570" width="760" height="28" fill="#171716"/><text x="380" y="589" text-anchor="middle" fill="#f4f4f0" font-family="DejaVu Sans Mono, monospace" font-size="12">4:3 CENTER CROP</text></g>
</svg>'''
    with tempfile.NamedTemporaryFile("w", suffix=".svg", encoding="utf-8") as handle:
        handle.write(source)
        handle.flush()
        subprocess.run(["magick", "-background", "none", handle.name, str(OUTPUT)], check=True)


if __name__ == "__main__":
    render()
