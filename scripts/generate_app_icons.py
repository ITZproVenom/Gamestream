#!/usr/bin/env python3
"""Generate GameStream app icon into GameStream/Assets.xcassets/AppIcon.appiconset/"""

from PIL import Image, ImageDraw, ImageFilter
import os
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "GameStream", "Assets.xcassets", "AppIcon.appiconset")


def make_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(22 * (1 - t) + 8 * t)
        g = int(8 * (1 - t) + 18 * t)
        b = int(48 * (1 - t) + 55 * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    def radial(cx, cy, max_r, color, power=1.5):
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        for i in range(max_r, 0, -1):
            a = int(color[3] * (1 - i / max_r) ** power)
            ld.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(color[0], color[1], color[2], a))
        return layer

    img = Image.alpha_composite(img, radial(size // 2, size // 2, int(size * 0.45), (120, 80, 255, 40)))
    img = Image.alpha_composite(
        img, radial(int(size * 0.55), int(size * 0.62), int(size * 0.35), (40, 180, 255, 28), 1.8)
    )

    s = size
    body_w, body_h = int(s * 0.62), int(s * 0.38)
    bx, by = (s - body_w) // 2, int(s * 0.32)
    radius = int(s * 0.12)

    controller = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    cd = ImageDraw.Draw(controller)
    cd.rounded_rectangle([bx, by, bx + body_w, by + body_h], radius=radius, fill=(245, 247, 255, 235))
    grip_r = int(s * 0.14)
    cd.ellipse(
        [bx - int(s * 0.02), by + int(body_h * 0.25), bx + grip_r * 2, by + body_h + int(s * 0.06)],
        fill=(245, 247, 255, 235),
    )
    cd.ellipse(
        [
            bx + body_w - grip_r * 2 + int(s * 0.02),
            by + int(body_h * 0.25),
            bx + body_w + int(s * 0.02),
            by + body_h + int(s * 0.06),
        ],
        fill=(245, 247, 255, 235),
    )

    dx, dy = bx + int(body_w * 0.22), by + int(body_h * 0.48)
    arm, thick = int(s * 0.035), int(s * 0.028)
    cd.rectangle([dx - arm, dy - thick // 2, dx + arm, dy + thick // 2], fill=(40, 30, 70, 220))
    cd.rectangle([dx - thick // 2, dy - arm, dx + thick // 2, dy + arm], fill=(40, 30, 70, 220))

    rx, ry = bx + int(body_w * 0.78), by + int(body_h * 0.48)
    br = max(1, int(s * 0.028))
    for ox, oy, col in [
        (0, -br * 2.2, (90, 200, 120, 230)),
        (0, br * 2.2, (80, 140, 255, 230)),
        (-br * 2.2, 0, (255, 90, 90, 230)),
        (br * 2.2, 0, (255, 200, 60, 230)),
    ]:
        cd.ellipse([rx + ox - br, ry + oy - br, rx + ox + br, ry + oy + br], fill=col)

    shadow = controller.filter(ImageFilter.GaussianBlur(radius=max(1, s // 40)))
    shadow_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    shadow_layer.paste(shadow, (0, int(s * 0.02)))
    px = shadow_layer.load()
    for y in range(s):
        for x in range(s):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (0, 0, 0, min(80, a // 3))

    img = Image.alpha_composite(img, shadow_layer)
    img = Image.alpha_composite(img, controller)

    draw = ImageDraw.Draw(img)
    arc_cx, arc_cy = s // 2, int(s * 0.22)
    for i, rad in enumerate([int(s * 0.06), int(s * 0.10), int(s * 0.14)]):
        alpha = 180 - i * 40
        draw.arc(
            [arc_cx - rad, arc_cy - rad // 2, arc_cx + rad, arc_cy + rad],
            start=200,
            end=340,
            fill=(160, 140, 255, alpha),
            width=max(2, s // 80),
        )

    return img


def main():
    os.makedirs(OUT, exist_ok=True)

    # 1024 marketing / single-size icon (Xcode expands for device sizes)
    icon = make_icon(1024)
    path = os.path.join(OUT, "icon-1024.png")
    bg = Image.new("RGB", (1024, 1024), (12, 10, 28))
    bg.paste(icon, mask=icon.split()[-1])
    bg.save(path, "PNG")
    print("wrote", path)

    contents = {
        "images": [
            {
                "filename": "icon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("wrote Contents.json")


if __name__ == "__main__":
    main()
