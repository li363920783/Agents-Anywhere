#!/usr/bin/env python3
"""Generates the Agents Anywhere icon set.

The mark is a *relay*: a solid core with two arcs radiating up and to the right
— one agent, reachable from anywhere. It is drawn from the same geometry at
every size, so the capsule glyph and the app icon stay the same mark.

Run from `harmony/`:

    python3 tools/make-icons.py

Everything is drawn at 4x and downsampled, because Pillow has no antialiasing.
"""

from PIL import Image, ImageDraw
import os
import sys

SS = 4  # supersample factor

# Brand blue, taken from `ohos_id_color_emphasize` so the icon matches the app's
# accent. `LIGHT` is the top-left of the background gradient, `DEEP` the bottom-right.
LIGHT = (74, 158, 255)
DEEP = (0, 71, 196)

WHITE = (255, 255, 255, 255)

# Mark geometry in a unit glyph box. The core sits low-left; the arcs open
# up-right around it.
CORE = (0.300, 0.700)
CORE_R = 0.078
ARC_RADII = (0.190, 0.315)
ARC_STROKE = 0.066
ARC_START = -97.0  # degrees, Pillow convention: 0 = east, increasing clockwise
ARC_END = 7.0


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, a, b, diagonal=True):
    """A smooth two-stop gradient, built small and scaled up."""
    n = 64
    small = Image.new("RGB", (n, n))
    px = small.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1)) if diagonal else y / (n - 1)
            px[x, y] = _lerp(a, b, t)
    return small.resize((size, size), Image.BICUBIC)


def radial_glow(size, centre, radius, strength):
    """An L-mode falloff mask, used to composite a soft light."""
    n = 128
    small = Image.new("L", (n, n), 0)
    px = small.load()
    cx, cy = centre[0] * n, centre[1] * n
    r = radius * n
    for y in range(n):
        for x in range(n):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d < r:
                falloff = (1.0 - d / r) ** 2
                px[x, y] = int(255 * falloff * strength)
    return small.resize((size, size), Image.BICUBIC)


def _arc_points(cx, cy, r, start, end):
    """Pillow's arc has no round caps, so the cap circles need the endpoints."""
    import math
    out = []
    for deg in (start, end):
        rad = math.radians(deg)
        out.append((cx + r * math.cos(rad), cy + r * math.sin(rad)))
    return out


def _ink_bounds():
    """Bounding box of the mark in glyph-box units.

    The mark is not centred on its own glyph box — the core sits low-left and
    the arcs reach up-right — so it has to be measured and shifted, or it reads
    as sitting down-and-left of centre.
    """
    import math
    xs = [CORE[0] - CORE_R, CORE[0] + CORE_R]
    ys = [CORE[1] - CORE_R, CORE[1] + CORE_R]
    half = ARC_STROKE / 2
    for r in ARC_RADII:
        # Sample the span: an axis crossing inside it (here 0 deg and -90 deg)
        # reaches further than either endpoint does.
        for i in range(181):
            deg = ARC_START + (ARC_END - ARC_START) * i / 180
            rad = math.radians(deg)
            xs.append(CORE[0] + r * math.cos(rad))
            ys.append(CORE[1] + r * math.sin(rad))
    return (min(xs) - half, min(ys) - half, max(xs) + half, max(ys) + half)


def mark(size, color, box=0.66):
    """The relay mark, optically centred in a `size` square, occupying `box`."""
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size * SS
    g = s * box
    x0, y0, x1, y1 = _ink_bounds()
    # Centre the ink, not the glyph box.
    ox = s / 2 - (x0 + x1) / 2 * g
    oy = s / 2 - (y0 + y1) / 2 * g

    cx = ox + CORE[0] * g
    cy = oy + CORE[1] * g
    cr = CORE_R * g
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=color)

    stroke = max(1, round(ARC_STROKE * g))
    for r_frac in ARC_RADII:
        r = r_frac * g
        d.arc([cx - r, cy - r, cx + r, cy + r],
              ARC_START, ARC_END, fill=color, width=stroke)
        for px_, py_ in _arc_points(cx, cy, r, ARC_START, ARC_END):
            half = stroke / 2
            d.ellipse([px_ - half, py_ - half, px_ + half, py_ + half], fill=color)

    return img.resize((size, size), Image.LANCZOS)


def app_icon(size=512):
    """Full-bleed icon: gradient field, a soft top-left light, then the mark."""
    base = gradient(size, LIGHT, DEEP).convert("RGBA")
    glow = radial_glow(size, (0.22, 0.16), 0.72, 0.34)
    base = Image.composite(Image.new("RGBA", (size, size), WHITE), base, glow)
    base.alpha_composite(mark(size, WHITE, box=0.60))
    return base.convert("RGB")


def check_glyph(size):
    """Done indicator: a check, drawn as two round-capped strokes."""
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size * SS
    pts = [(0.26 * s, 0.52 * s), (0.44 * s, 0.70 * s), (0.76 * s, 0.32 * s)]
    d.line(pts, fill=WHITE, width=round(0.11 * s), joint="curve")
    half = round(0.11 * s) / 2
    for x, y in (pts[0], pts[2]):
        d.ellipse([x - half, y - half, x + half, y + half], fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def read_glyph(size):
    """Read indicator: a ring around a filled dot."""
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size * SS
    c, r = s / 2, 0.30 * s
    w = round(0.11 * s)
    d.ellipse([c - r, c - r, c + r, c + r], outline=WHITE, width=w)
    ir = 0.11 * s
    d.ellipse([c - ir, c - ir, c + ir, c + ir], fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def lock_backdrop(size=1000):
    """Lock-screen immersive picture: deep field, one big faint mark."""
    base = gradient(size, (18, 34, 74), (4, 8, 20)).convert("RGBA")
    for centre, radius, strength in (((0.16, 0.12), 0.60, 0.30),
                                     ((0.88, 0.92), 0.55, 0.18)):
        mask = radial_glow(size, centre, radius, strength)
        tint = Image.new("RGBA", (size, size), (74, 158, 255, 255))
        base = Image.composite(tint, base, mask)

    faint = mark(size, WHITE, box=0.52)
    faint.putalpha(faint.getchannel("A").point(lambda v: int(v * 0.14)))
    base.alpha_composite(faint)
    return base.convert("RGB")


def store_icons(out_dir):
    """Listing icons for AppGallery. 216 is the size the store asks for; 1024 is
    the master to keep for later. Drawn natively at each size rather than
    resampled, so the strokes stay crisp."""
    os.makedirs(out_dir, exist_ok=True)
    for n in (216, 512, 1024):
        app_icon(n).save(os.path.join(out_dir, f"app_icon-{n}.png"))
        print(f"  app_icon-{n}.png")


def main():
    app_icon(512).save("AppScope/resources/base/media/app_icon.png")
    app_icon(512).save("entry/src/main/resources/base/media/icon.png")
    app_icon(512).save("entry/src/main/resources/base/media/startIcon.png")

    mark(60, WHITE, box=0.74).save("entry/src/main/resources/rawfile/lv_app.png")
    mark(60, WHITE, box=0.90).save("entry/src/main/resources/rawfile/lv_run.png")
    check_glyph(60).save("entry/src/main/resources/rawfile/lv_done.png")
    read_glyph(60).save("entry/src/main/resources/rawfile/lv_read.png")
    lock_backdrop(1000).save("entry/src/main/resources/rawfile/lv_backdrop.png")
    print("in-app icons written")

    # Optional: also emit the store listing sizes into a directory.
    if len(sys.argv) > 1:
        store_icons(sys.argv[1])


if __name__ == "__main__":
    main()
