"""Regenerates the launcher icons (Android legacy PNGs + Windows .ico).

Not needed to build the app: the generated files are already in platform/.
Run from the project root:  python3 tool/make_icons.py   (needs Pillow)
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BG = (11, 13, 18, 255)
TRACK = (42, 47, 60, 255)
ARCS = [  # (start, end) in degrees clockwise from the top, colour
    (0, 60, (124, 156, 255, 255)),
    (101.5, 155.6, (94, 224, 181, 255)),
    (204.4, 258.5, (255, 184, 107, 255)),
]


def draw_icon(size: int, rounded: bool = True) -> Image.Image:
    S = 1024
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=BG)
    else:
        d.rectangle([0, 0, S, S], fill=BG)

    c = S / 2
    r = S * 0.31
    w = S * 0.09
    # Pillow draws the stroke inward from the box, so grow the box by half the stroke
    # to make r the centre line of the ring.
    R = r + w / 2
    bbox = [c - R, c - R, c + R, c + R]
    d.ellipse(bbox, outline=TRACK, width=int(w))

    for a0, a1, col in ARCS:
        d.arc(bbox, a0 - 90, a1 - 90, fill=col, width=int(w))
        for a in (a0, a1):  # round caps
            x = c + r * math.cos(math.radians(a - 90))
            y = c + r * math.sin(math.radians(a - 90))
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=col)

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    res = ROOT / 'platform' / 'android' / 'app' / 'src' / 'main' / 'res'
    for folder, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        out = res / f'mipmap-{folder}'
        out.mkdir(parents=True, exist_ok=True)
        draw_icon(px).save(out / 'ic_launcher.png')

    ico = ROOT / 'platform' / 'windows' / 'runner' / 'resources'
    ico.mkdir(parents=True, exist_ok=True)
    draw_icon(256).save(
        ico / 'app_icon.ico',
        format='ICO',
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    draw_icon(512).save(ROOT / 'tool' / 'icon_preview.png')
    print('icons written')


if __name__ == '__main__':
    main()
