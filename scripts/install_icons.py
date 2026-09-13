#!/usr/bin/env python3
"""Install App Icon from scripts/icon1024.b64 into Assets.xcassets."""
import base64, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "GameStream", "Assets.xcassets", "AppIcon.appiconset")
B64_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon1024.b64")
CONTENTS = '{"images":[{"filename":"icon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}'
def main():
    os.makedirs(OUT, exist_ok=True)
    raw = base64.b64decode(open(B64_PATH).read().strip())
    open(os.path.join(OUT, "icon-1024.png"), "wb").write(raw)
    open(os.path.join(OUT, "Contents.json"), "w").write(CONTENTS)
    print("Installed icon-1024.png", len(raw), "bytes")
if __name__ == "__main__":
    main()
