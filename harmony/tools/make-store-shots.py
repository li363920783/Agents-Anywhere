#!/usr/bin/env python3
"""Pads device screenshots onto the 9:16 canvas AppGallery requires.

The phone is 1320x2848 (~1:2.16), taller than 9:16, so the shot is scaled to
the full height and the side margins are filled by stretching the screenshot's
own edge columns. The app background is a smooth gradient, so the join is
invisible. Cropping to 9:16 instead would cut the floating tab bar — the one
thing the screenshots exist to show.

    python3 tools/make-store-shots.py <src-dir> <out-dir>

Output is JPEG (the store allows up to 5 MB; these land around 200 KB).
"""

import os
import sys

from PIL import Image

W, H = 1080, 1920
EXTS = ('.jpeg', '.jpg', '.png')


def pad_to_canvas(im):
    scaled = im.convert('RGB').resize(
        (round(im.width * H / im.height), H), Image.LANCZOS)
    canvas = Image.new('RGB', (W, H))
    x = (W - scaled.width) // 2
    if x > 0:
        left = scaled.crop((0, 0, 1, H)).resize((x, H), Image.NEAREST)
        canvas.paste(left, (0, 0))
        right = scaled.crop((scaled.width - 1, 0, scaled.width, H))
        right = right.resize((x, H), Image.NEAREST)
        canvas.paste(right, (W - x, 0))
    canvas.paste(scaled, (x, 0))
    return canvas


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for name in sorted(os.listdir(src)):
        if not name.lower().endswith(EXTS):
            continue
        dst = os.path.join(out, os.path.splitext(name)[0] + '.jpg')
        pad_to_canvas(Image.open(os.path.join(src, name))).save(dst, 'JPEG', quality=92)
        print(f'  {os.path.basename(dst)}  {W}x{H}  {os.path.getsize(dst) // 1024} KB')


if __name__ == '__main__':
    main()
