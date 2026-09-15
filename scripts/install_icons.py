#!/usr/bin/env python3
"""Install GameStream App Icon into iOS Assets and Android mipmaps.

Fails the process if a valid 1024x1024 PNG cannot be produced.
Never silently falls back to a tiny/placeholder icon.
"""
from __future__ import annotations

import base64
import os
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS_OUT = os.path.join(ROOT, "GameStream", "Assets.xcassets", "AppIcon.appiconset")
B64 = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon1024.b64")
GEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generate_app_icons.py")
MIN_BYTES = 20_000

CONTENTS = """{
  "images": [
    {"filename": "fiona.g@example.net", "idiom": "iphone", "scale": "2x", "size": "20x20"},
    {"filename": "carlos.r@example.net", "idiom": "iphone", "scale": "3x", "size": "20x20"},
    {"filename": "icon-60@2x.png", "idiom": "iphone", "scale": "2x", "size": "60x60"},
    {"filename": "icon-60@3x.png", "idiom": "iphone", "scale": "3x", "size": "60x60"},
    {"filename": "icon-76.png", "idiom": "ipad", "scale": "1x", "size": "76x76"},
    {"filename": "icon-76@2x.png", "idiom": "ipad", "scale": "2x", "size": "76x76"},
    {"filename": "icon-83.5@2x.png", "idiom": "ipad", "scale": "2x", "size": "83.5x83.5"},
    {"filename": "icon-1024.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"},
    {"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
  ],
  "info": {"author": "xcode", "version": 1}
}
"""


def png_ihdr(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    length = struct.unpack(">I", data[8:12])[0]
    if length < 13 or data[12:16] != b"IHDR":
        raise ValueError("missing PNG IHDR")
    w, h = struct.unpack(">II", data[16:24])
    return w, h


def require_icon(data: bytes, label: str) -> None:
    if len(data) < MIN_BYTES:
        raise SystemExit(f"{label}: icon is only {len(data)} bytes (need >={MIN_BYTES})")
    w, h = png_ihdr(data)
    if (w, h) != (1024, 1024):
        raise SystemExit(f"{label}: icon is {w}x{h}, expected 1024x1024")


def decode_bundled() -> bytes:
    if not os.path.isfile(B64):
        raise SystemExit(f"missing bundled icon source: {B64}")
    raw = open(B64, "r", encoding="utf-8").read().strip()
    if len(raw) < 1000 or not raw.startswith("iVBOR"):
        raise SystemExit(f"bundled icon1024.b64 is invalid/placeholder ({len(raw)} chars)")
    try:
        data = base64.b64decode(raw, validate=True)
    except Exception as e:
        raise SystemExit(f"invalid base64 in {B64}: {e}")
    require_icon(data, "bundled icon1024.b64")
    return data


def try_generate() -> bytes:
    try:
        import PIL  # noqa: F401
    except ImportError as e:
        raise SystemExit(f"Pillow required to generate App Icon: {e}")
    subprocess.check_call([sys.executable, GEN])
    path = os.path.join(IOS_OUT, "icon-1024.png")
    data = open(path, "rb").read()
    require_icon(data, "generated icon-1024.png")
    print("App Icon generated via generate_app_icons.py")
    return data


def write_ios(data: bytes) -> str:
    os.makedirs(IOS_OUT, exist_ok=True)
    path = os.path.join(IOS_OUT, "icon-1024.png")
    with open(path, "wb") as f:
        f.write(data)
    with open(os.path.join(IOS_OUT, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(CONTENTS)
    from PIL import Image
    import io
    master = Image.open(io.BytesIO(data)).convert("RGBA")
    r, g, b, a = master.split()
    master = Image.merge("RGBA", (r, g, b, a.point(lambda _: 255)))
    sizes = {
        "fiona.g@example.net": 40,
        "carlos.r@example.net": 60,
        "icon-60@2x.png": 120,
        "icon-60@3x.png": 180,
        "icon-76.png": 76,
        "icon-76@2x.png": 152,
        "icon-83.5@2x.png": 167,
    }
    for name, sz in sizes.items():
        resized = master.resize((sz, sz), Image.Resampling.LANCZOS)
        out = os.path.join(IOS_OUT, name)
        resized.save(out, "PNG", optimize=True)
        print(f"wrote {out} ({sz}x{sz})")
    print(f"wrote {path} ({len(data)} bytes, 1024x1024)")
    return path


def write_android(data: bytes) -> None:
    try:
        from PIL import Image
        import io
    except ImportError:
        print("Pillow not installed; skipping Android density PNG export")
        return
    img = Image.open(io.BytesIO(data)).convert("RGBA")
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    if not os.path.isdir(res):
        return
    for folder, size in densities.items():
        out_dir = os.path.join(res, folder)
        os.makedirs(out_dir, exist_ok=True)
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        out = os.path.join(out_dir, "ic_launcher.png")
        resized.save(out, "PNG")
        print(f"wrote {out} ({size}x{size})")


def main() -> None:
    # Always generate a fresh opaque multi-size icon set in CI
    data = try_generate()
    require_icon(data, "final icon")
    write_ios(data)
    write_android(data)


if __name__ == "__main__":
    main()
