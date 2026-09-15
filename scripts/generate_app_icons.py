#!/usr/bin/env python3
"""Generate GameStream App Icon into GameStream/Assets.xcassets/AppIcon.appiconset/"""

from PIL import Image, ImageDraw, ImageFilter
import os
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "GameStream", "Assets.xcassets", "AppIcon.appiconset")


def make_icon(size: int) -> Image.Image:
    # Opaque background so SpringBoard / TrollStore always show a solid icon
    img = Image.new("RGBA", (size, size), (18, 12, 40, 255))
    draw = ImageDraw.Draw(img)

    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(28 * (1 - t) + 12 * t)
        g = int(10 * (1 - t) + 20 * t)
        b = int(58 * (1 - t) + 72 * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    def blob(cx, cy, max_r, color):
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        step = max(1, max_r // 64)
        for i in range(max_r, 0, -step):
            a = int(color[3] * (1 - i / max_r) ** 1.6)
            ld.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(color[0], color[1], color[2], a))
        return layer

    img = Image.alpha_composite(img, blob(size // 2, size // 2, int(size * 0.48), (130, 90, 255, 55)))
    img = Image.alpha_composite(
        img, blob(int(size * 0.62), int(size * 0.68), int(size * 0.32), (40, 190, 255, 40))
    )

    s = size
    body_w, body_h = int(s * 0.62), int(s * 0.38)
    bx, by = (s - body_w) // 2, int(s * 0.34)
    radius = max(8, int(s * 0.12))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        [bx + 2, by + 4, bx + body_w + 2, by + body_h + 4],
        radius=radius,
        fill=(0, 0, 0, 90),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, size // 80)))
    img = Image.alpha_composite(img, shadow)

    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle(
        [bx, by, bx + body_w, by + body_h], radius=radius, fill=(245, 245, 250, 255)
    )

    cx, cy = bx + int(body_w * 0.28), by + body_h // 2
    arm = max(3, int(s * 0.035))
    span = max(8, int(s * 0.07))
    draw.rectangle([cx - span, cy - arm, cx + span, cy + arm], fill=(40, 40, 50, 255))
    draw.rectangle([cx - arm, cy - span, cx + arm, cy + span], fill=(40, 40, 50, 255))

    bcx, bcy = bx + int(body_w * 0.72), by + body_h // 2
    br = max(4, int(s * 0.028))
    for dx, dy, col in [
        (-br * 2, 0, (90, 200, 120)),
        (br * 2, 0, (80, 140, 255)),
        (0, -br * 2, (255, 90, 90)),
        (0, br * 2, (255, 200, 60)),
    ]:
        draw.ellipse(
            [bcx + dx - br, bcy + dy - br, bcx + dx + br, bcy + dy + br],
            fill=col + (255,),
        )

    gw, gh = int(s * 0.14), int(s * 0.22)
    gy = by + body_h - int(gh * 0.35)
    draw.rounded_rectangle(
        [bx - int(gw * 0.15), gy, bx + gw, gy + gh],
        radius=int(gw * 0.4),
        fill=(245, 245, 250, 255),
    )
    draw.rounded_rectangle(
        [bx + body_w - gw, gy, bx + body_w + int(gw * 0.15), gy + gh],
        radius=int(gw * 0.4),
        fill=(245, 245, 250, 255),
    )

    # Force fully opaque alpha channel (SpringBoard rejects flaky alpha icons)
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
    print(f"wrote {path} ({os.path.getsize(path)} bytes) + {len(sized)} sizes")


if __name__ == "__main__":
    main()
