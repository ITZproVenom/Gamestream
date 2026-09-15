#!/usr/bin/env python3
"""Generate App Icons from the official repo mark (docs/gamestream-icon.svg design).

Single visual identity for GitHub README, iOS AppIcon, and Android launcher.
"""

from __future__ import annotations

import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "GameStream", "Assets.xcassets", "AppIcon.appiconset")
SVG = os.path.join(ROOT, "docs", "gamestream-icon.svg")


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def make_icon(size: int) -> Image.Image:
    """Rasterize the same art as docs/gamestream-icon.svg at any size.

    SVG geometry is defined on a 256x256 canvas; we scale uniformly.
    """
    s = size
    scale = s / 256.0
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background gradient #160c30 → #0c1220 (full bleed; iOS applies mask)
    for y in range(s):
        t = y / max(s - 1, 1)
        r = int(_lerp(0x16, 0x0C, t))
        g = int(_lerp(0x0C, 0x12, t))
        b = int(_lerp(0x30, 0x20, t))
        draw.line([(0, y), (s, y)], fill=(r, g, b, 255))

    # Glow circle cx=128 cy=128 r=90 — soft violet→cyan
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx = cy = s // 2
    max_r = int(90 * scale)
    for i in range(max_r, 0, -max(1, max_r // 80)):
        t = 1 - i / max_r
        rr = int(_lerp(0x78, 0x28, t))
        gg = int(_lerp(0x64, 0xB4, t))
        bb = int(_lerp(0xFF, 0xFF, t))
        aa = int(_lerp(0.5, 0.0, t) * 255 * 0.85)
        gd.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(rr, gg, bb, aa))
    img = Image.alpha_composite(img, glow)

    def sx(v: float) -> float:
        return v * scale

    draw = ImageDraw.Draw(img)

    # Controller body rect x=58 y=96 w=140 h=72 rx=28  fill #f5f7ff @0.92
    body = [sx(58), sx(96), sx(58 + 140), sx(96 + 72)]
    body_fill = (0xF5, 0xF7, 0xFF, int(0.92 * 255))
    draw.rounded_rectangle(body, radius=max(1, int(28 * scale)), fill=body_fill)

    # Grips: circles at (78,150) and (178,150) r=28
    for gx, gy in [(78, 150), (178, 150)]:
        r = sx(28)
        draw.ellipse(
            [sx(gx) - r, sx(gy) - r, sx(gx) + r, sx(gy) + r],
            fill=body_fill,
        )

    # D-pad fill #281e46
    dpad = (0x28, 0x1E, 0x46, 255)
    draw.rounded_rectangle(
        [sx(84), sx(124), sx(84 + 28), sx(124 + 10)],
        radius=max(1, int(2 * scale)),
        fill=dpad,
    )
    draw.rounded_rectangle(
        [sx(93), sx(115), sx(93 + 10), sx(115 + 28)],
        radius=max(1, int(2 * scale)),
        fill=dpad,
    )

    # Face buttons (match SVG)
    buttons = [
        (162, 118, (0x5A, 0xC8, 0x78)),
        (162, 146, (0x50, 0x8C, 0xFF)),
        (148, 132, (0xFF, 0x5A, 0x5A)),
        (176, 132, (0xFF, 0xC8, 0x3C)),
    ]
    br = sx(7)
    for bx, by, col in buttons:
        draw.ellipse(
            [sx(bx) - br, sx(by) - br, sx(bx) + br, sx(by) + br],
            fill=col + (255,),
        )

    # Antenna arcs (quadratic beziers from SVG paths)
    arc_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arc_layer)
    stroke = (0xA0, 0x8C, 0xFF)

    def arc_points(x0, y0, x1, y1, x2, y2, n=24):
        pts = []
        for i in range(n + 1):
            t = i / n
            x = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * x1 + t**2 * x2
            y = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * y1 + t**2 * y2
            pts.append((sx(x), sx(y)))
        return pts

    w1 = max(1, int(4 * scale))
    w2 = max(1, int(3 * scale))
    ad.line(arc_points(100, 78, 128, 52, 156, 78), fill=stroke + (int(0.7 * 255),), width=w1, joint="curve")
    ad.line(arc_points(110, 68, 128, 48, 146, 68), fill=stroke + (int(0.45 * 255),), width=w2, joint="curve")
    img = Image.alpha_composite(img, arc_layer)

    # Force fully opaque (SpringBoard / TrollStore)
    r, g, b, a = img.split()
    a = a.point(lambda _: 255)
    return Image.merge("RGBA", (r, g, b, a))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    icon = make_icon(1024)
    path = os.path.join(OUT, "icon-1024.png")
    icon.save(path, "PNG", optimize=True)

    sized = {
        "fiona.g@example.net": 40,
        "carlos.r@example.net": 60,
        "icon-60@2x.png": 120,
        "icon-60@3x.png": 180,
        "icon-76.png": 76,
        "icon-76@2x.png": 152,
        "icon-83.5@2x.png": 167,
    }
    for name, sz in sized.items():
        make_icon(sz).save(os.path.join(OUT, name), "PNG", optimize=True)

    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    make_icon(512).save(os.path.join(docs, "gamestream-icon.png"), "PNG", optimize=True)

    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    if os.path.isdir(res):
        for folder, sz in {
            "mipmap-mdpi": 48,
            "mipmap-hdpi": 72,
            "mipmap-xhdpi": 96,
            "mipmap-xxhdpi": 144,
            "mipmap-xxxhdpi": 192,
        }.items():
            out_dir = os.path.join(res, folder)
            os.makedirs(out_dir, exist_ok=True)
            make_icon(sz).save(os.path.join(out_dir, "ic_launcher.png"), "PNG")

    contents = {
        "images": [
            {"filename": "fiona.g@example.net", "idiom": "iphone", "scale": "2x", "size": "20x20"},
            {"filename": "carlos.r@example.net", "idiom": "iphone", "scale": "3x", "size": "20x20"},
            {"filename": "icon-60@2x.png", "idiom": "iphone", "scale": "2x", "size": "60x60"},
            {"filename": "icon-60@3x.png", "idiom": "iphone", "scale": "3x", "size": "60x60"},
            {"filename": "icon-76.png", "idiom": "ipad", "scale": "1x", "size": "76x76"},
            {"filename": "icon-76@2x.png", "idiom": "ipad", "scale": "2x", "size": "76x76"},
            {"filename": "icon-83.5@2x.png", "idiom": "ipad", "scale": "2x", "size": "83.5x83.5"},
            {"filename": "icon-1024.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"},
            {"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")

    import base64
    from pathlib import Path

    raw = Path(path).read_bytes()
    Path(os.path.join(ROOT, "scripts", "icon1024.b64")).write_text(
        base64.b64encode(raw).decode("ascii") + "\n"
    )
    print(f"repo mark → {path} ({os.path.getsize(path)} bytes) + {len(sized)} sizes")
    print(f"source design: {SVG}")


if __name__ == "__main__":
    main()
