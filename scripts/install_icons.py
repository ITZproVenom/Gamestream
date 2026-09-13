#!/usr/bin/env python3
"""Install GameStream App Icon into Assets.xcassets (no deps)."""
import base64
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "GameStream", "Assets.xcassets", "AppIcon.appiconset")
B64 = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon1024.b64")

CONTENTS = (
    '{"images":[{"filename":"icon-1024.png","idiom":"universal",'
    '"platform":"ios","size":"1024x1024"}],'
    '"info":{"author":"xcode","version":1}}'
)


def write_from_b64() -> bool:
    if not os.path.isfile(B64):
        print("missing", B64)
        return False
    data = base64.b64decode(open(B64, "r").read())
    if len(data) < 100 or data[:8] != b"\x89PNG\r\n\x1a\n":
        print("icon1024.b64 is not a valid PNG")
        return False
    os.makedirs(OUT, exist_ok=True)
    png_path = os.path.join(OUT, "icon-1024.png")
    with open(png_path, "wb") as f:
        f.write(data)
    open(os.path.join(OUT, "Contents.json"), "w").write(CONTENTS)
    print("wrote", png_path, "(%d bytes)" % len(data))
    return True


def main():
    os.makedirs(OUT, exist_ok=True)
    gen = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generate_app_icons.py")
    if os.path.isfile(gen):
        try:
            import PIL  # noqa: F401
            subprocess.check_call([sys.executable, gen])
            print("App Icon generated via generate_app_icons.py")
            return
        except Exception as e:
            print("Pillow generate failed, using bundled PNG:", e)

    if write_from_b64():
        return

    print("Writing Contents.json only — archive may warn about a missing icon.")
    open(os.path.join(OUT, "Contents.json"), "w").write(CONTENTS)


if __name__ == "__main__":
    main()
