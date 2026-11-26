"""Render Glimmer's Finder installer background at 1x and 2x. Requires Pillow.

The layout is the shared Protomota drag installer (Inkspring, OpenTalon, PulseCanvas) in Glimmer's palette.
Run it with the packaging Python and commit the result:

    python native/installer/make-background.py

The TIFF goes into the app's resources (native/Glimmer/installer-background.tiff, Mac builds only), so the
installer window points at signed artwork inside Glimmer.app and the disk image holds no loose background file.
"""

import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

APP = "Glimmer"
FONT = "/System/Library/Fonts/SFNS.ttf"
BASE, GLOW = (235, 232, 226), (251, 250, 247)
INK = "#2b2a28"
SECONDARY = "#62605a"
BORDER = "#cfcac1"
WELL = "#fdfcfa"
ACCENT = "#4a6f94"
DOT = "#5d8fbf"


def draw_arrow(canvas: Image.Image, scale: int) -> None:
    # Finder can use the 1x TIFF page. Render the arrow at 4x before downsampling
    # either page so the diagonals and their joins have smooth edge coverage.
    # Drawing it directly at 1x is what leaves the arrow head ragged.
    left, top, width, height = 315, 210, 89, 40
    resolution = 4 * scale
    mask = Image.new("L", (width * resolution, height * resolution))
    draw = ImageDraw.Draw(mask)
    radius = 1.5 * resolution
    for path in ([(321, 230), (397, 230)], [(382, 215), (397, 230), (382, 245)]):
        points = [((x - left) * resolution, (y - top) * resolution) for x, y in path]
        draw.line(points, fill=255, width=3 * resolution)
        for x, y in points:
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    coverage = mask.resize((width * scale, height * scale), Image.Resampling.LANCZOS)
    canvas.paste(ACCENT, (left * scale, top * scale), coverage)


def render(scale: int, target: Path) -> None:
    # The shared layout is 720 x 460. The extra rows only continue the backdrop, so a Finder window
    # with no status bar (492 points of content) shows no bare strip under the artwork.
    width, height = 720 * scale, 492 * scale
    canvas = Image.new("RGB", (width, height))
    canvas.putdata([
        tuple(round(start + (end - start) * amount) for start, end in zip(BASE, GLOW))
        for y in range(height)
        for x in range(width)
        for amount in [math.exp(-(((x / scale - 360) / 410) ** 2
                                  + ((y / scale - 230) / 300) ** 2))]
    ])
    draw = ImageDraw.Draw(canvas)

    def points(*values: float) -> tuple[int, ...]:
        return tuple(round(value * scale) for value in values)

    def text(value: str, y: int, size: int, color: str, bold: bool = False) -> None:
        font = ImageFont.truetype(FONT, size * scale)
        font.set_variation_by_name("Bold" if bold else "Regular")
        if draw.textlength(value, font=font) > 632 * scale:
            raise ValueError(f"Installer text exceeds the safe width: {value}")
        draw.text(points(360, y), value, font=font, fill=color, anchor="mt")

    draw.rounded_rectangle(points(18, 18, 702, 442), radius=22 * scale, outline=BORDER, width=scale)
    text(f"Install {APP}", 48, 30, INK, bold=True)
    text(f"Drag {APP} to Applications to get started.", 95, 16, SECONDARY)
    for left in (109, 439):
        draw.rounded_rectangle(points(left, 154, left + 172, 320), radius=22 * scale, fill=WELL)

    # Finder draws the real app and the Applications shortcut over the two wells.
    left, top, right, bottom, radius = 102, 147, 288, 327, 29
    dots = []
    for start, end, fixed, horizontal in (
        (left + radius, right - radius, top, True),
        (left + radius, right - radius, bottom, True),
        (top + radius, bottom - radius, left, False),
        (top + radius, bottom - radius, right, False),
    ):
        count = round((end - start) / 9)
        for index in range(count + 1):
            value = start + (end - start) * index / count
            dots.append((value, fixed) if horizontal else (fixed, value))
    for cx, cy, start in ((left + radius, top + radius, 180),
                          (right - radius, top + radius, 270),
                          (right - radius, bottom - radius, 0),
                          (left + radius, bottom - radius, 90)):
        for angle in range(start + 15, start + 90, 20):
            dots.append((cx + radius * math.cos(math.radians(angle)),
                         cy + radius * math.sin(math.radians(angle))))
    for x, y in dots:
        draw.ellipse(points(x - 1.15, y - 1.15, x + 1.15, y + 1.15), fill=DOT)

    draw_arrow(canvas, scale)
    draw.line(points(88, 355, 632, 355), fill=BORDER, width=scale)
    text("Eject the disk image when copying is complete.", 378, 15, INK)
    text(f"Open {APP} from your Applications folder.", 410, 14, SECONDARY)
    canvas.save(target, dpi=(72 * scale, 72 * scale))


def main() -> None:
    here = Path(__file__).resolve().parent
    standard, retina = here / "background.png", here / "background@2x.png"
    render(1, standard)
    render(2, retina)
    subprocess.run(["tiffutil", "-cathidpicheck", str(standard), str(retina),
                    "-out", str(here.parent / "Glimmer" / "installer-background.tiff")], check=True)


if __name__ == "__main__":
    main()
