#!/usr/bin/python3

from __future__ import annotations

from collections import defaultdict
from hashlib import blake2s
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
ARTWORK = ROOT / "artwork"
THEME = ROOT / "themes" / "alumina-raster"
BACKGROUND = THEME / "backgrounds" / "alumina-raster.png"
PREVIEW = THEME / "preview.png"
SVG = ARTWORK / "object-first-weave-01.svg"

WIDTH = 3840
HEIGHT = 2160
SEED = b"alumina-object-first-weave-v1"
GROUND = "#b9b9b4"
SHADOW = "#a3a49f"
HIGHLIGHT = "#cfd0ca"
POINT_COUNT = 20_000
MIN_DISTANCE = 14
BUCKET_SIZE = 16


def digest(label: bytes, value: int) -> bytes:
    return blake2s(SEED + label + value.to_bytes(8, "big"), digest_size=16).digest()


def toroidal_distance_squared(a: tuple[int, int], b: tuple[int, int]) -> int:
    dx = abs(a[0] - b[0])
    dy = abs(a[1] - b[1])
    dx = min(dx, WIDTH - dx)
    dy = min(dy, HEIGHT - dy)
    return dx * dx + dy * dy


def generate_points() -> list[tuple[int, int]]:
    bucket_columns = WIDTH // BUCKET_SIZE
    bucket_rows = HEIGHT // BUCKET_SIZE
    buckets: dict[tuple[int, int], list[tuple[int, int]]] = defaultdict(list)
    points: list[tuple[int, int]] = []
    counter = 0

    while len(points) < POINT_COUNT:
        raw = digest(b"point", counter)
        counter += 1
        point = (
            int.from_bytes(raw[:8], "big") % WIDTH,
            int.from_bytes(raw[8:], "big") % HEIGHT,
        )
        bucket_x = point[0] // BUCKET_SIZE
        bucket_y = point[1] // BUCKET_SIZE
        accepted = True
        for offset_y in (-1, 0, 1):
            for offset_x in (-1, 0, 1):
                neighbor = (
                    (bucket_x + offset_x) % bucket_columns,
                    (bucket_y + offset_y) % bucket_rows,
                )
                for other in buckets[neighbor]:
                    if toroidal_distance_squared(point, other) < MIN_DISTANCE * MIN_DISTANCE:
                        accepted = False
                        break
                if not accepted:
                    break
            if not accepted:
                break
        if accepted:
            points.append(point)
            buckets[(bucket_x, bucket_y)].append(point)

    return points


def ranked(points: list[tuple[int, int]], label: bytes) -> list[tuple[int, int]]:
    return sorted(
        points,
        key=lambda point: blake2s(
            SEED + label + point[0].to_bytes(2, "big") + point[1].to_bytes(2, "big"),
            digest_size=16,
        ).digest(),
    )


def split_axis(start: int, length: int, limit: int) -> list[tuple[int, int]]:
    if start < 0:
        return [(start + limit, -start), (0, length + start)]
    if start + length > limit:
        return [(start, limit - start), (0, start + length - limit)]
    return [(start, length)]


def wrapped_rectangles(
    center: tuple[int, int], width: int, height: int
) -> list[tuple[int, int, int, int]]:
    x_segments = split_axis(center[0] - width // 2, width, WIDTH)
    y_segments = split_axis(center[1] - height // 2, height, HEIGHT)
    return [
        (x, y, segment_width, segment_height)
        for x, segment_width in x_segments
        for y, segment_height in y_segments
    ]


def assigned_marks(points: list[tuple[int, int]]) -> list[tuple[str, int, int, int, int]]:
    tone_order = ranked(points, b"tone")
    tone_sets = (
        (SHADOW, tone_order[: POINT_COUNT // 2]),
        (HIGHLIGHT, tone_order[POINT_COUNT // 2 :]),
    )
    marks: list[tuple[str, int, int, int, int]] = []
    for color, tone_points in tone_sets:
        shape_order = ranked(tone_points, b"shape")
        shaped = (
            [(point, 8, 4) for point in shape_order[:4000]]
            + [(point, 4, 8) for point in shape_order[4000:8000]]
            + [(point, 6, 6) for point in shape_order[8000:]]
        )
        for point, width, height in shaped:
            for x, y, rect_width, rect_height in wrapped_rectangles(point, width, height):
                marks.append((color, x, y, rect_width, rect_height))
    return marks


def audit_density(marks: list[tuple[str, int, int, int, int]]) -> None:
    coverage = bytearray(WIDTH * HEIGHT)
    for color, x, y, width, height in marks:
        value = 1 if color == SHADOW else 2
        for row in range(y, y + height):
            start = row * WIDTH + x
            end = start + width
            if any(coverage[start:end]):
                raise RuntimeError("Object-First Weave marks overlap")
            coverage[start:end] = bytes([value]) * width

    expected = 0.0791
    for y in range(0, HEIGHT - 255, 128):
        for x in range(0, WIDTH - 255, 128):
            covered = 0
            for row in range(y, y + 256):
                start = row * WIDTH + x
                covered += sum(pixel != 0 for pixel in coverage[start : start + 256])
            density = covered / (256 * 256)
            if abs(density - expected) > 0.02:
                raise RuntimeError(
                    f"Object-First Weave density drift at {x},{y}: {density:.4f}"
                )


def svg_source(marks: list[tuple[str, int, int, int, int]]) -> str:
    rects = [f'<rect width="{WIDTH}" height="{HEIGHT}" fill="{GROUND}"/>']
    rects.extend(
        f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="{color}"/>'
        for color, x, y, width, height in marks
    )
    body = "\n  ".join(rects)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
        f'viewBox="0 0 {WIDTH} {HEIGHT}" shape-rendering="crispEdges">\n'
        f'  {body}\n'
        '</svg>\n'
    )


def run() -> None:
    (THEME / "backgrounds").mkdir(parents=True, exist_ok=True)
    points = generate_points()
    marks = assigned_marks(points)
    audit_density(marks)
    SVG.write_text(svg_source(marks), encoding="utf-8")
    subprocess.run(
        ["magick", str(SVG), "-alpha", "off", "-strip", "PNG24:" + str(BACKGROUND)],
        check=True,
    )
    subprocess.run(
        [
            "magick",
            str(BACKGROUND),
            "-filter",
            "Lanczos",
            "-resize",
            "1600x900!",
            "-strip",
            "PNG24:" + str(PREVIEW),
        ],
        check=True,
    )


if __name__ == "__main__":
    run()
