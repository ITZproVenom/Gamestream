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
    {
      "filename": "icon-1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
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
    try:
        data = base64.b64decode(raw, validate=True)
    except Exception as e:
        raise SystemExit(f"icon1024.b64 is not valid base64: {e}") from e
    require_icon(data, "icon1024.b64")
    return data


def try_generate() -> bytes | None:
    if not os.path.isfile(GEN):
        return None
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("Pillow not installed; using bundled 1024x1024 PNG")
        return None
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
    generated = None
    try:
        generated = try_generate()
    except SystemExit:
        raise
    except Exception as e:
        print(f"generate_app_icons.py failed: {e}", file=sys.stderr)
        print("Will use bundled 1024x1024 PNG (must still be valid).", file=sys.stderr)

    data = generated if generated is not None else decode_bundled()
    require_icon(data, "final icon")
    write_ios(data)
    write_android(data)


if __name__ == "__main__":
    main()
