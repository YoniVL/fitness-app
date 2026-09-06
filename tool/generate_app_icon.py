#!/usr/bin/env python3
"""Renders the Cadans app icon (a rhythmic pulse-wave mark) with Pillow.

Draws at 4x supersample and downsamples with LANCZOS for clean anti-aliased
edges — no external rasterizer (Inkscape/ImageMagick/cairosvg) needed.

Outputs, under assets/icon/:
  icon.png            1024x1024, full green background + mark (legacy/Play Store icon)
  icon_foreground.png 1024x1024, transparent background + mark, scaled to sit
                       inside Android's adaptive-icon safe zone (~66/108 of the canvas)

Run: python tool/generate_app_icon.py [hex_background] [hex_mark]

Defaults to the Modernist palette: an orange-red pulse mark on the near-black
ground (see AppPalette.dark in lib/app/theme.dart).
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

BACKGROUND = sys.argv[1] if len(sys.argv) > 1 else "#131211"
MARK = sys.argv[2] if len(sys.argv) > 2 else "#FF563C"
SIZE = 1024
SUPERSAMPLE = 4
CANVAS = SIZE * SUPERSAMPLE
CENTER = CANVAS / 2

# Pulse-wave vertices as (x, y) offsets from center, in 1024-space (see the
# design note in CLAUDE.md / the plan for how these were derived from the
# chat mockup's 116-unit tile).
POINTS_1024 = [
    (176, 512), (326, 512), (406, 300), (512, 742), (617, 371), (688, 512), (847, 512),
]
STROKE_1024 = 60


def scaled_points(scale: float) -> list[tuple[float, float]]:
    return [
        (CENTER + (x - 512) * scale * SUPERSAMPLE, CENTER + (y - 512) * scale * SUPERSAMPLE)
        for x, y in POINTS_1024
    ]


def draw_mark(draw: ImageDraw.ImageDraw, scale: float, color: str) -> None:
    pts = scaled_points(scale)
    width = int(STROKE_1024 * scale * SUPERSAMPLE)
    draw.line(pts, fill=color, width=width, joint="curve")
    r = width / 2
    for x, y in pts:
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def render(background: str | None, scale: float) -> Image.Image:
    img = Image.new("RGBA", (CANVAS, CANVAS), background or (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_mark(draw, scale, MARK)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)

    icon = render(BACKGROUND, scale=1.0)
    icon.convert("RGB").save(out / "icon.png")

    # Adaptive-icon safe zone is the inner ~66/108 of the canvas — keep the
    # mark's extent comfortably inside that circle.
    foreground = render(None, scale=0.85)
    foreground.save(out / "icon_foreground.png")

    print(f"Wrote {out / 'icon.png'} and {out / 'icon_foreground.png'} "
          f"(mark {MARK} on {BACKGROUND})")


if __name__ == "__main__":
    main()
