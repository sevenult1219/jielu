#!/usr/bin/env python3
"""Generate the LongShot app icon with no external design assets."""
from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
SCALE = 4
SIZE = 1024
CANVAS = SIZE * SCALE


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size: int, top_left: tuple[int, int, int], bottom_right: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x / size * 0.48 + y / size * 0.52)
            # Ease the gradient so the middle is richer.
            t = t * t * (3 - 2 * t)
            px[x, y] = lerp(top_left, bottom_right, t)
    return img


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def main() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    ICONSET.mkdir(parents=True, exist_ok=True)

    margin = 72 * SCALE
    tile_size = CANVAS - margin * 2
    radius = int(tile_size * 0.225)

    tile = gradient(tile_size, (47, 132, 255), (124, 70, 255)).convert("RGBA")
    mask = rounded_mask(tile_size, radius)
    tile.putalpha(mask)

    # Gentle top highlight.
    highlight = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.ellipse(
        (-tile_size * 0.25, -tile_size * 0.78, tile_size * 1.15, tile_size * 0.38),
        fill=(255, 255, 255, 38),
    )
    highlight.putalpha(Image.composite(highlight.getchannel("A"), Image.new("L", highlight.size, 0), mask))
    tile = Image.alpha_composite(tile, highlight)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Soft drop shadow behind the tile.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (margin, margin + 18 * SCALE, CANVAS - margin, CANVAS - margin + 18 * SCALE),
        radius=radius,
        fill=(22, 28, 65, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(20 * SCALE))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(tile, (margin, margin))

    draw = ImageDraw.Draw(canvas)

    def rr(box, r, fill, outline=None, width=0):
        draw.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)

    # A tall page, with a second page peeking out behind it.
    page_w = int(tile_size * 0.51)
    page_h = int(tile_size * 0.70)
    page_x = margin + (tile_size - page_w) // 2 - 12 * SCALE
    page_y = margin + int(tile_size * 0.145)

    back_x = page_x + 20 * SCALE
    back_y = page_y + 22 * SCALE
    rr(
        (back_x, back_y, back_x + page_w, back_y + page_h),
        34 * SCALE,
        (255, 255, 255, 88),
    )

    # Shadow under the page.
    page_shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    psd = ImageDraw.Draw(page_shadow)
    psd.rounded_rectangle(
        (page_x, page_y + 14 * SCALE, page_x + page_w, page_y + page_h + 14 * SCALE),
        radius=34 * SCALE,
        fill=(23, 25, 70, 95),
    )
    page_shadow = page_shadow.filter(ImageFilter.GaussianBlur(16 * SCALE))
    canvas = Image.alpha_composite(canvas, page_shadow)
    draw = ImageDraw.Draw(canvas)

    rr(
        (page_x, page_y, page_x + page_w, page_y + page_h),
        34 * SCALE,
        (250, 251, 255, 255),
    )

    # Page header.
    header_h = int(page_h * 0.245)
    rr(
        (page_x, page_y, page_x + page_w, page_y + header_h),
        34 * SCALE,
        (68, 132, 255, 255),
    )
    draw.rectangle(
        (page_x, page_y + header_h - 34 * SCALE, page_x + page_w, page_y + header_h),
        fill=(68, 132, 255, 255),
    )
    # Header content: an image glyph and two short lines.
    rr(
        (page_x + 34 * SCALE, page_y + 34 * SCALE,
         page_x + 34 * SCALE + 58 * SCALE, page_y + 34 * SCALE + 58 * SCALE),
        14 * SCALE,
        (255, 255, 255, 235),
    )
    draw.ellipse(
        (page_x + 46 * SCALE, page_y + 45 * SCALE,
         page_x + 58 * SCALE, page_y + 57 * SCALE),
        fill=(68, 132, 255, 255),
    )
    draw.polygon(
        [
            (page_x + 38 * SCALE, page_y + 84 * SCALE),
            (page_x + 59 * SCALE, page_y + 62 * SCALE),
            (page_x + 84 * SCALE, page_y + 84 * SCALE),
        ],
        fill=(68, 132, 255, 255),
    )
    rr(
        (page_x + 112 * SCALE, page_y + 43 * SCALE,
         page_x + page_w - 34 * SCALE, page_y + 54 * SCALE),
        5 * SCALE,
        (255, 255, 255, 240),
    )
    rr(
        (page_x + 112 * SCALE, page_y + 67 * SCALE,
         page_x + page_w - 86 * SCALE, page_y + 77 * SCALE),
        5 * SCALE,
        (255, 255, 255, 160),
    )

    # Body text lines and a photo card.
    body_top = page_y + header_h + 42 * SCALE
    line_color = (183, 192, 216, 255)
    widths = [0.78, 0.62, 0.84, 0.72, 0.50]
    for index, factor in enumerate(widths):
        y = body_top + index * 38 * SCALE
        rr(
            (page_x + 34 * SCALE, y,
             page_x + 34 * SCALE + int((page_w - 68 * SCALE) * factor), y + 14 * SCALE),
            7 * SCALE,
            line_color,
        )

    card_top = body_top + 5 * 38 * SCALE + 18 * SCALE
    card_h = int(page_h * 0.205)
    rr(
        (page_x + 34 * SCALE, card_top,
         page_x + page_w - 34 * SCALE, card_top + card_h),
        22 * SCALE,
        (230, 239, 255, 255),
    )
    # A miniature landscape inside the card.
    draw.ellipse(
        (page_x + page_w - 118 * SCALE, card_top + 28 * SCALE,
         page_x + page_w - 78 * SCALE, card_top + 68 * SCALE),
        fill=(255, 196, 92, 255),
    )
    draw.polygon(
        [
            (page_x + 52 * SCALE, card_top + card_h - 14 * SCALE),
            (page_x + 150 * SCALE, card_top + int(card_h * 0.38)),
            (page_x + 238 * SCALE, card_top + card_h - 14 * SCALE),
        ],
        fill=(122, 171, 255, 255),
    )
    draw.polygon(
        [
            (page_x + 150 * SCALE, card_top + card_h - 14 * SCALE),
            (page_x + 216 * SCALE, card_top + int(card_h * 0.55)),
            (page_x + 282 * SCALE, card_top + card_h - 14 * SCALE),
        ],
        fill=(91, 143, 245, 255),
    )

    # Scroll badge.
    badge_radius = int(tile_size * 0.135)
    bx = margin + tile_size - badge_radius - 38 * SCALE
    by = margin + tile_size - badge_radius - 38 * SCALE

    badge_shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    bsd = ImageDraw.Draw(badge_shadow)
    bsd.ellipse(
        (bx - badge_radius, by - badge_radius + 12 * SCALE,
         bx + badge_radius, by + badge_radius + 12 * SCALE),
        fill=(24, 28, 65, 120),
    )
    badge_shadow = badge_shadow.filter(ImageFilter.GaussianBlur(16 * SCALE))
    canvas = Image.alpha_composite(canvas, badge_shadow)
    draw = ImageDraw.Draw(canvas)

    # Vertical gradient inside the badge.
    badge_size = badge_radius * 2
    badge = gradient(badge_size, (255, 126, 92), (255, 58, 92)).convert("RGBA")
    bmask = Image.new("L", (badge_size, badge_size), 0)
    ImageDraw.Draw(bmask).ellipse((0, 0, badge_size - 1, badge_size - 1), fill=255)
    badge.putalpha(bmask)
    canvas.alpha_composite(badge, (bx - badge_radius, by - badge_radius))
    draw = ImageDraw.Draw(canvas)

    # White down arrow.
    stem_w = 15 * SCALE
    draw.rounded_rectangle(
        (bx - stem_w // 2, by - badge_radius * 0.50,
         bx + stem_w // 2, by + badge_radius * 0.10),
        radius=stem_w // 2,
        fill=(255, 255, 255, 255),
    )
    arrow = [
        (bx - badge_radius * 0.34, by + badge_radius * 0.02),
        (bx, by + badge_radius * 0.43),
        (bx + badge_radius * 0.34, by + badge_radius * 0.02),
    ]
    draw.line(arrow, fill=(255, 255, 255, 255), width=15 * SCALE, joint="curve")

    # Downsample with a high-quality filter.
    icon = canvas.resize((SIZE, SIZE), Image.LANCZOS)

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    icon.save(RESOURCES / "AppIcon.png")
    for size in sizes:
        rendered = icon.resize((size, size), Image.LANCZOS)
        if size == 1024:
            rendered.save(ICONSET / "icon_512x512@2x.png")
        else:
            rendered.save(ICONSET / f"icon_{size}x{size}.png")
            if size in (16, 32, 128, 256, 512):
                rendered.resize((size * 2, size * 2), Image.LANCZOS).save(
                    ICONSET / f"icon_{size}x{size}@2x.png"
                )

    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET), "-o", str(RESOURCES / "AppIcon.icns")],
        check=True,
    )
    print(f"Wrote {RESOURCES / 'AppIcon.icns'}")


if __name__ == "__main__":
    main()
